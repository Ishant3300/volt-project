'use strict';

/**
 * Contract-expiry scheduler — see config/expiryRules.js for the rules and
 * services/expirySchedule.js for the (pure, unit-tested) date logic.
 *
 * - refreshPlan(): turns the rules + live contracts + exchange holiday
 *   calendars into ExpiryAction rows (idempotent upsert by key).
 * - runDue(): every minute. An OPEN whose time has come enables each name's
 *   next contract. A CUT whose time has come (just after that market's
 *   close) first captures the closing bid/ask snapshot; it only closes
 *   positions once an admin has confirmed it — then every open position in
 *   that contract is closed at the snapshot (long at bid, short at ask) and
 *   the contract is disabled (closing-only), except GIFT NIFTY which is one
 *   continuous instrument and stays enabled.
 */

const mongoose = require('mongoose');
const ExpiryAction = require('../models/ExpiryAction');
const KiteInstrument = require('../models/KiteInstrument');
const { EFFECTIVE_FROM, NEW_CONTRACTS_CLOSED_FROM, OPEN_TIME, GROUPS } = require('../config/expiryRules');
const { planGroup } = require('./expirySchedule');
const { getHolidays } = require('./marketCalendarService');
const { addUtcDays, dateKey, toIndiaDateOnly } = require('../utils/settlementDates');
const { beginTradeWrite } = require('./tradeWriteFenceService');
const { closeOpenPositions, bidAskPrice } = require('./positionCloseService');

const groupByKey = new Map(GROUPS.map((g) => [g.key, g]));
/** Contract types a rule group covers — futures unless it says otherwise (NFO options: CE/PE). */
const typesOf = (group) => ({ $in: (group && group.instrumentTypes) || ['FUT'] });
const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const exactName = (name) => new RegExp(`^${escapeRegex(name)}$`, 'i');

/**
 * A cut must be confirmed within this long after its close — before the
 * next session opens (MCX 11:31 PM → 8:31 AM). Later than that, the closing
 * snapshot is stale and the contract may have traded again, so the cut is
 * marked missed and nothing is closed (the expiry-day close still runs).
 */
const CONFIRM_WINDOW_MS = 9 * 60 * 60 * 1000;

// Tokens of next contracts in their rollover window (OPEN done, matching CUT
// not done yet) — kept on the live price feed (livePriceService) so rollover
// always has a reopen price.
let rolloverTokens = new Set();

let lastRefreshAt = 0;
let lastPlanErrors = [];

/* ------------------------------------------------------------ planning -- */

async function loadContracts(group, today) {
  if (group.tradingsymbols) {
    // GIFT NIFTY is one continuous instrument here; its real contract
    // expiries come from NSEIX's own listing (every NIFTY future it lists),
    // falling back to the near month stored on the instrument.
    const name = group.tradingsymbols[0];
    const feed = require('./giftNiftyFeedService');
    let expiries = feed.getListedExpiries();
    if (expiries.length === 0) expiries = await feed.fetchListedExpiries().catch(() => []);
    if (expiries.length === 0) {
      const inst = await KiteInstrument.findOne({ tradingsymbol: name, deleted_at: null }).select('expiry').lean();
      if (inst?.expiry) expiries = [inst.expiry];
    }
    if (expiries.length === 0) throw new Error('GIFT NIFTY expiry unavailable from NSE IX');
    return expiries.filter((e) => e >= today).map((expiry) => ({ name, expiry }));
  }
  const rows = await KiteInstrument.aggregate([
    { $match: { segment: { $in: group.segments }, instrument_type: typesOf(group), is_active: true, deleted_at: null, expiry: { $gte: today } } },
    { $group: { _id: { name: '$name', expiry: '$expiry' } } },
  ]);
  const wanted = group.names ? new Set(group.names.map((n) => n.toUpperCase())) : null;
  return rows
    .map((r) => ({ name: r._id.name, expiry: r._id.expiry }))
    .filter((c) => c.name && (!wanted || wanted.has(String(c.name).toUpperCase())));
}

/** Calendar years a contract's open/cut dates can fall in. */
function yearsNeeded(contract) {
  const expiry = new Date(contract.expiry);
  const years = [expiry.getUTCFullYear()];
  // A January expiry's open/cut can count back into December.
  if (expiry.getUTCMonth() === 0) years.push(expiry.getUTCFullYear() - 1);
  return years;
}

/**
 * Holidays for every year the contracts need. A year whose calendar can't be
 * loaded (e.g. mcxindia.com refusing the request and no verified fallback for
 * that year yet) no longer fails the whole group: it is returned in
 * `unavailable`, and refreshPlan plans every contract that doesn't need it.
 */
async function loadHolidays(calendar, contracts) {
  if (calendar === 'WEEKDAYS') return { holidays: null, unavailable: new Map() };
  const years = new Set();
  for (const c of contracts) for (const y of yearsNeeded(c)) years.add(y);
  const all = new Set();
  const unavailable = new Map(); // year -> error message
  for (const y of years) {
    try {
      for (const key of await getHolidays(calendar, y)) all.add(key);
    } catch (e) {
      unavailable.set(y, e.message);
    }
  }
  return { holidays: all, unavailable };
}

/**
 * Keep a contract the planner had to skip (its calendar year unavailable)
 * closed, the same way closeNewTargetsUntilOpen keeps a not-yet-open target
 * closed: only contracts loaded after NEW_CONTRACTS_CLOSED_FROM, only if
 * still enabled, and never a name's nearest contract (the one trading now).
 * Without this a newly listed far month stayed tradable — GOLDM27JANFUT on
 * 5 Oct 2026, when the 2027 MCX calendar couldn't be fetched.
 */
async function closeSkippedContracts(group, skipped, allContracts, now) {
  const nearest = new Map(); // NAME -> earliest expiry ms
  for (const c of allContracts) {
    const k = String(c.name).toUpperCase();
    const t = new Date(c.expiry).getTime();
    if (!nearest.has(k) || t < nearest.get(k)) nearest.set(k, t);
  }
  const cutoff = mongoose.Types.ObjectId.createFromTime(Math.floor(NEW_CONTRACTS_CLOSED_FROM.getTime() / 1000));
  let closed = 0;
  for (const c of skipped) {
    if (new Date(c.expiry).getTime() === nearest.get(String(c.name).toUpperCase())) continue;
    const day = new Date(c.expiry);
    const res = await KiteInstrument.updateMany(
      {
        _id: { $gt: cutoff },
        segment: { $in: group.segments },
        instrument_type: typesOf(group),
        name: exactName(c.name),
        expiry: { $gte: day, $lt: addUtcDays(day, 1) },
        enabled: { $ne: false },
        deleted_at: null,
      },
      { $set: { enabled: false, ban_reason: 'Opens once its trading calendar is available', banned_at: now } },
    );
    closed += res.modifiedCount;
  }
  if (closed) {
    invalidateSearchCache();
    console.log(`🔒 [ExpiryActions] ${group.key}: ${closed} contract(s) kept closed until their trading calendar is available`);
  }
}

/**
 * Upsert every planned action. Only 'planned'/'confirmed'/'paused' rows are
 * ever rewritten or retired — an action that ran (or is running) is history.
 */
async function refreshPlan(now = new Date()) {
  const today = toIndiaDateOnly(now);
  const todayKey = dateKey(today);
  const errors = [];

  for (const group of GROUPS) {
    try {
      const allContracts = await loadContracts(group, today);
      const { holidays, unavailable } = await loadHolidays(group.calendar, allContracts);
      // Contracts whose open/cut needs a calendar year that couldn't be
      // loaded are left out of this plan (and kept closed); every other
      // contract of the group is planned as usual.
      const contracts = allContracts.filter((c) => !yearsNeeded(c).some((y) => unavailable.has(y)));
      if (unavailable.size > 0) {
        const skipped = allContracts.filter((c) => !contracts.includes(c));
        const why = [...unavailable].map(([y, msg]) => `${y}: ${msg}`).join('; ');
        console.warn(`⚠️  [ExpiryActions] ${group.key}: ${skipped.length} contract(s) not planned yet — calendar unavailable (${why}): ${skipped.map((c) => `${c.name} ${dateKey(c.expiry)}`).join(', ')}`);
        await closeSkippedContracts(group, skipped, allContracts, now);
      }
      const planned = planGroup(group, contracts, holidays, { effectiveFrom: group.effectiveFrom || EFFECTIVE_FROM, openTime: OPEN_TIME });
      const keys = new Set(planned.map((a) => a.key));

      for (const a of planned) {
        const fields = {
          group_key: group.key,
          group_label: group.label,
          exchange_label: group.exchangeLabel,
          segments: group.segments,
          continuous: !!group.continuous,
          names: a.names,
          current_expiry: a.current_expiry,
          targets: a.targets,
          action_date: a.action_date,
          close_time: a.kind === 'CUT' ? group.closeTime : null,
          execute_at: a.execute_at,
        };
        const existing = await ExpiryAction.findOne({ key: a.key }).select('status').lean();
        if (!existing) {
          await ExpiryAction.updateOne({ key: a.key }, { $setOnInsert: { key: a.key, kind: a.kind, status: 'planned', ...fields } }, { upsert: true });
        } else if (['planned', 'confirmed', 'paused', 'obsolete'].includes(existing.status)) {
          const status = existing.status === 'obsolete' ? 'planned' : existing.status;
          await ExpiryAction.updateOne({ _id: existing._id }, { $set: { ...fields, status } });
        }
      }

      await ExpiryAction.updateMany(
        { group_key: group.key, status: { $in: ['planned', 'confirmed', 'paused'] }, action_date: { $gte: todayKey }, key: { $nin: [...keys] } },
        { $set: { status: 'obsolete' } },
      );
      if (group.reconcile) await reconcileOpenWindow(group, contracts, holidays, now);
    } catch (e) {
      console.error(`❌ [ExpiryActions] Planning failed for ${group.key}: ${e.message}`);
      errors.push({ group: group.key, label: group.label, error: e.message });
    }
  }
  try {
    await refreshRolloverTokens();
  } catch (e) {
    console.error(`❌ [ExpiryActions] Rollover token refresh failed: ${e.message}`);
  }
  try {
    await closeNewTargetsUntilOpen(now);
  } catch (e) {
    console.error(`❌ [ExpiryActions] Closing new contracts failed: ${e.message}`);
    errors.push({ group: 'NEW_CONTRACTS', label: 'New contracts', error: e.message });
  }
  lastRefreshAt = Date.now();
  lastPlanErrors = errors;
  return { errors };
}

/**
 * Enforce "only current + next open" for a reconcile group (NFO options):
 * per underlying, the current expiry and — from its open day, 1 working day
 * before the current expires — the next one may be open; every strike in
 * any later expiry is closed, including strikes the daily sync adds later.
 * Never opens anything (the OPEN action does that) and never touches
 * existing positions (a closed contract is closing-only).
 */
async function reconcileOpenWindow(group, contracts, holidays, now) {
  const { workingDaysBefore } = require('./expirySchedule');
  const today = toIndiaDateOnly(now);
  const byName = new Map();
  for (const c of contracts) {
    const k = String(c.name);
    if (!byName.has(k)) byName.set(k, new Set());
    byName.get(k).add(dateKey(c.expiry));
  }
  // Names sharing the same allowed-expiry set share one update.
  const byAllowed = new Map();
  for (const [name, keys] of byName) {
    const sorted = [...keys].sort();
    const allowed = [sorted[0]];
    if (sorted[1]) {
      const openDay = workingDaysBefore(new Date(`${sorted[0]}T00:00:00Z`), group.open.days, holidays);
      if (dateKey(today) >= dateKey(openDay)) allowed.push(sorted[1]);
    }
    const k = allowed.join(',');
    if (!byAllowed.has(k)) byAllowed.set(k, { allowed, names: [] });
    byAllowed.get(k).names.push(name);
  }
  let closed = 0;
  for (const { allowed, names } of byAllowed.values()) {
    const res = await KiteInstrument.updateMany(
      {
        segment: { $in: group.segments },
        instrument_type: typesOf(group),
        name: { $in: names },
        expiry: { $gte: today, $nin: allowed.map((k) => new Date(`${k}T00:00:00Z`)) },
        enabled: { $ne: false },
        deleted_at: null,
      },
      { $set: { enabled: false, ban_reason: 'Opens for trading 1 working day before the previous expiry', banned_at: now } },
    );
    closed += res.modifiedCount;
  }
  if (closed) {
    invalidateSearchCache();
    console.log(`🔒 [ExpiryActions] ${group.label}: closed ${closed} contract(s) outside the current + next window`);
  }
  return closed;
}

async function targetTokens(action) {
  const tokens = [];
  for (const t of action.targets || []) {
    const day = new Date(t.expiry);
    const rows = await KiteInstrument.find({
      segment: { $in: action.segments }, instrument_type: 'FUT', name: exactName(t.name),
      expiry: { $gte: day, $lt: addUtcDays(day, 1) }, deleted_at: null,
    }).select('instrument_token').lean();
    tokens.push(...rows.map((r) => r.instrument_token.toString()));
  }
  return tokens;
}

async function refreshRolloverTokens() {
  const opens = await ExpiryAction.find({ kind: 'OPEN', status: 'done' }).lean();
  const next = new Set();
  // Any next contract that is open for trading — opened by the schedule OR
  // by hand (Expiry management → Open expiry): every enabled future in a
  // ruled segment that isn't the nearest expiry of its name.
  const segments = [...new Set(GROUPS.filter((g) => !g.continuous && !g.instrumentTypes).flatMap((g) => g.segments))];
  const today = toIndiaDateOnly(new Date());
  const futures = await KiteInstrument.find({ segment: { $in: segments }, instrument_type: 'FUT', is_active: true, expiry: { $gte: today }, deleted_at: null })
    .select('instrument_token segment name expiry enabled').lean();
  const nearest = new Map();
  for (const f of futures) {
    const k = `${f.segment}|${String(f.name).toUpperCase()}`;
    if (!nearest.has(k) || f.expiry < nearest.get(k)) nearest.set(k, f.expiry);
  }
  for (const f of futures) {
    const k = `${f.segment}|${String(f.name).toUpperCase()}`;
    if (f.enabled !== false && f.expiry > nearest.get(k)) next.add(f.instrument_token.toString());
  }
  for (const open of opens) {
    const cut = await ExpiryAction.findOne({ kind: 'CUT', group_key: open.group_key, current_expiry: open.current_expiry }).select('status').lean();
    if (cut && cut.status === 'done') continue;
    if (!cut && new Date(open.current_expiry) < addUtcDays(new Date(), -1)) continue;
    for (const token of await targetTokens(open)) next.add(token);
  }
  rolloverTokens = next;
  try { require('./livePriceService').ensureSubscribed([...next]); } catch (_) {}
}

function getRolloverTokens() {
  return [...rolloverTokens];
}

/**
 * A contract loaded after NEW_CONTRACTS_CLOSED_FROM arrives enabled (schema
 * default), which would let it trade before its open day. Close each such
 * OPEN target once; it reopens when its OPEN runs.
 */
async function closeNewTargetsUntilOpen(now) {
  const pending = await ExpiryAction.find({ kind: 'OPEN', status: { $in: ['planned', 'paused'] }, execute_at: { $gt: now } }).lean();
  const cutoff = mongoose.Types.ObjectId.createFromTime(Math.floor(NEW_CONTRACTS_CLOSED_FROM.getTime() / 1000));
  for (const action of pending) {
    const handled = new Set(action.closed_targets || []);
    const fresh = action.targets.filter((t) => !handled.has(`${t.name}|${dateKey(t.expiry)}`));
    if (fresh.length === 0) continue;
    let closed = 0;
    for (const t of fresh) {
      const day = new Date(t.expiry);
      const res = await KiteInstrument.updateMany(
        {
          _id: { $gt: cutoff },
          segment: { $in: action.segments },
          instrument_type: typesOf(groupByKey.get(action.group_key)),
          name: exactName(t.name),
          expiry: { $gte: day, $lt: addUtcDays(day, 1) },
          enabled: { $ne: false },
          deleted_at: null,
        },
        { $set: { enabled: false, ban_reason: `Opens for trading on ${action.action_date}`, banned_at: now } },
      );
      closed += res.modifiedCount;
    }
    await ExpiryAction.updateOne({ _id: action._id }, { $addToSet: { closed_targets: { $each: fresh.map((t) => `${t.name}|${dateKey(t.expiry)}`) } } });
    if (closed) {
      invalidateSearchCache();
      console.log(`🔒 [ExpiryActions] ${action.key}: ${closed} newly loaded contract(s) closed until ${action.action_date}`);
    }
  }
}

/* ----------------------------------------------------------- execution -- */

async function resolveCutInstruments(action) {
  const group = groupByKey.get(action.group_key);
  if (action.continuous) {
    return KiteInstrument.find({ tradingsymbol: { $in: group.tradingsymbols }, deleted_at: null })
      .select('instrument_token tradingsymbol exchange segment last_price').lean();
  }
  const day = new Date(action.current_expiry);
  const rows = await KiteInstrument.find({
    segment: { $in: action.segments },
    instrument_type: typesOf(group),
    expiry: { $gte: day, $lt: addUtcDays(day, 1) },
    deleted_at: null,
  }).select('instrument_token tradingsymbol exchange segment last_price name expiry').lean();
  const names = new Set(action.names.map((n) => n.toUpperCase()));
  return rows.filter((r) => names.has(String(r.name).toUpperCase()));
}

async function captureSnapshot(action) {
  const metricsEngine = require('./metricsEngine');
  const instruments = await resolveCutInstruments(action);
  const prices = instruments.map((i) => {
    const token = i.instrument_token.toString();
    return {
      token,
      symbol: i.tradingsymbol,
      bid: Number(metricsEngine._bidMap?.get(token)) || 0,
      ask: Number(metricsEngine._askMap?.get(token)) || 0,
      ltp: Number(metricsEngine._ltpMap?.get(token) || i.last_price) || 0,
    };
  });
  const snapshot = { captured_at: new Date(), prices };
  await ExpiryAction.updateOne({ _id: action._id, 'snapshot.captured_at': null }, { $set: { snapshot } });
  console.log(`📸 [ExpiryActions] Closing snapshot for ${action.key}: ${prices.map((p) => `${p.symbol} ${p.bid}/${p.ask}`).join(', ')}`);
}

/** Atomically move a due action into 'running' — nothing runs twice. */
function claim(action, fromStatuses) {
  return ExpiryAction.findOneAndUpdate(
    { _id: action._id, status: { $in: fromStatuses } },
    { $set: { status: 'running', started_at: new Date(), error: null } },
    { new: true },
  ).lean();
}

function invalidateSearchCache() {
  try { require('./instrumentSearchService').invalidateCache(); } catch (_) {}
}

async function executeOpen(action) {
  let enabled = 0;
  for (const t of action.targets) {
    const day = new Date(t.expiry);
    const res = await KiteInstrument.updateMany(
      {
        segment: { $in: action.segments },
        instrument_type: typesOf(groupByKey.get(action.group_key)),
        name: exactName(t.name),
        expiry: { $gte: day, $lt: addUtcDays(day, 1) },
        deleted_at: null,
      },
      { $set: { enabled: true, ban_reason: null, banned_at: null } },
    );
    enabled += res.modifiedCount;
  }
  invalidateSearchCache();
  await ExpiryAction.updateOne({ _id: action._id }, {
    $set: { status: 'done', executed_at: new Date(), 'result.contracts': enabled },
  });
  // Put the new contracts on the live feed now — rollover needs their price.
  const tokens = await targetTokens(action);
  tokens.forEach((t) => rolloverTokens.add(t));
  try { require('./livePriceService').ensureSubscribed(tokens); } catch (_) {}
  console.log(`🟢 [ExpiryActions] ${action.key}: opened next contracts (${enabled} enabled)`);
  // "NEW CONTRACT Open" notice on the banner automatically (banner only, no
  // push). Re-posted on each open of the day so it lists all of them.
  try {
    const draft = await buildAnnouncement(action.action_date);
    if (draft.message) {
      await require('./announcementBoard').postSection('expiry', draft.message, { ref: action.action_date, expiresAt: draft.expires_at });
      console.log(`📣 [ExpiryActions] ${action.key}: new-contract notice on the banner until ${draft.expires_at.toISOString()}`);
    }
  } catch (e) { console.error(`❌ [ExpiryActions] new-contract notice not posted: ${e.message}`); }
}

function notifyUser(userId, action) {
  const message = `Your ${action.group_label} positions were closed ahead of expiry at the closing rate.`;
  try {
    require('./livePriceService').broadcastToUser(userId, { type: 'admin_square_off', message });
  } catch (_) {}
  try {
    require('./firebaseService').sendNotification(userId, 'admin_order_execution', {
      title: `${action.group_label} positions closed`,
      body: message,
      data: { reason: 'expiry_cut' },
    });
  } catch (_) {}
}

/**
 * Every watchlist entry on a cut contract moves to that name's next
 * contract, keeping its place in the list. Dropped instead when there is no
 * next contract, or the owner already watches it. Apps show the change the
 * next time their watchlist loads.
 */
async function swapWatchlistsToNextContract(instruments) {
  const Watchlist = require('../models/Watchlist');
  let swapped = 0;
  let removed = 0;
  for (const old of instruments) {
    const oldToken = old.instrument_token.toString();
    const entries = await Watchlist.find({ instrument_token: oldToken, deleted_at: null }).select('owner_id owner_type').lean();
    if (entries.length === 0) continue;
    const next = await KiteInstrument.findOne({
      segment: old.segment,
      instrument_type: 'FUT',
      name: exactName(old.name),
      expiry: { $gt: old.expiry },
      deleted_at: null,
    }).sort({ expiry: 1 }).select('_id instrument_token').lean();

    for (const entry of entries) {
      const alreadyWatching = next && await Watchlist.exists({
        owner_id: entry.owner_id, owner_type: entry.owner_type, instrument_token: next.instrument_token.toString(), deleted_at: null,
      });
      if (next && !alreadyWatching) {
        await Watchlist.updateOne({ _id: entry._id, deleted_at: null }, {
          $set: { instrument_token: next.instrument_token.toString(), kite_instrument_id: next._id },
        });
        swapped++;
      } else {
        await Watchlist.updateOne({ _id: entry._id, deleted_at: null }, { $set: { deleted_at: new Date() } });
        removed++;
      }
    }
  }
  return { swapped, removed };
}

async function executeCut(action) {
  let lease = null;
  try {
    lease = await beginTradeWrite('expiry_cut');
    const instruments = await resolveCutInstruments(action);
    const quotes = new Map((action.snapshot?.prices || []).map((p) => [p.token, p]));
    const metricsEngine = require('./metricsEngine');
    const quoteFor = (token) => quotes.get(token) || {
      bid: metricsEngine._bidMap?.get(token),
      ask: metricsEngine._askMap?.get(token),
      ltp: metricsEngine._ltpMap?.get(token),
    };
    const expiryKey = dateKey(action.current_expiry);

    const result = await closeOpenPositions({
      instruments,
      priceFor: (token, closeSide) => bidAskPrice(quoteFor(token), closeSide),
      lease,
      trade: {
        placed_by: 'ADMIN',
        trade_type: 'admin_square_off',
        remarks: (symbol) => `Expiry cut ahead of ${expiryKey} expiry (${symbol})`,
      },
      reason: 'EXPIRY_CUT',
      txSuffix: 'EXC',
      onUserClosed: (userId) => notifyUser(userId, action),
    });

    let disabled = 0;
    if (!action.continuous && instruments.length) {
      const res = await KiteInstrument.updateMany(
        { instrument_token: { $in: instruments.map((i) => i.instrument_token) } },
        { $set: { enabled: false, ban_reason: 'Contract closed ahead of expiry', banned_at: new Date() } },
      );
      disabled = res.modifiedCount;
      invalidateSearchCache();
    }
    // Watchlists move to the next contract even if some positions failed to
    // close — the old contract is closed for trading either way.
    const watch = action.continuous ? { swapped: 0, removed: 0 } : await swapWatchlistsToNextContract(instruments);

    const failures = [...result.failures, ...result.skipped].map((f) => ({ ...f, user_id: String(f.user_id) }));
    await ExpiryAction.updateOne({ _id: action._id }, {
      $set: {
        status: failures.length ? 'failed' : 'done',
        executed_at: new Date(),
        error: failures.length ? `${failures.length} position(s) could not be closed — confirm again to retry` : null,
        result: {
          contracts: disabled,
          open_positions: result.openPositions,
          positions_closed: result.squared,
          watchlist_swapped: watch.swapped,
          watchlist_removed: watch.removed,
          failures,
        },
      },
    });
    console.log(`🔴 [ExpiryActions] ${action.key}: closed ${result.squared}/${result.openPositions} position(s), ${disabled} contract(s) disabled, watchlists ${watch.swapped} moved/${watch.removed} removed, ${failures.length} failure(s)`);
  } finally {
    await lease?.release();
  }
}

/** Every minute: run whatever is due. */
async function runDue(now = new Date()) {
  const due = await ExpiryAction.find({ status: { $in: ['planned', 'confirmed'] }, execute_at: { $lte: now } })
    .sort({ execute_at: 1 }).lean();

  for (const action of due) {
    try {
      if (action.kind === 'OPEN') {
        const claimed = await claim(action, ['planned', 'confirmed']);
        if (claimed) await executeOpen(claimed);
        continue;
      }
      if (!action.snapshot?.captured_at) await captureSnapshot(action);
      if (action.status !== 'confirmed') {
        if (now - new Date(action.execute_at) > CONFIRM_WINDOW_MS) {
          await ExpiryAction.updateOne({ _id: action._id, status: 'planned' }, {
            $set: { status: 'failed', error: 'Not confirmed before the next session — nothing was closed; the expiry-day close still applies.' },
          });
        }
        continue; // waits for an admin
      }
      const claimed = await claim(action, ['confirmed']);
      if (claimed) await executeCut(claimed);
    } catch (e) {
      console.error(`❌ [ExpiryActions] ${action.key} failed: ${e.message}`);
      await ExpiryAction.updateOne({ _id: action._id, status: 'running' }, { $set: { status: 'failed', error: e.message } });
    }
  }
}

/* --------------------------------------------------------------- admin -- */

async function list({ from, to } = {}) {
  if (Date.now() - lastRefreshAt > 60_000) await refreshPlan();
  const filter = { status: { $ne: 'obsolete' } };
  if (from || to) filter.action_date = { ...(from ? { $gte: from } : {}), ...(to ? { $lte: to } : {}) };
  const actions = await ExpiryAction.find(filter).sort({ execute_at: 1, key: 1 }).lean();
  return { actions: actions.map(({ _id, __v, ...a }) => ({ id: _id, ...a })), plan_errors: lastPlanErrors };
}

const TRANSITIONS = {
  confirm: { kinds: ['CUT'], from: ['planned', 'paused', 'failed'], to: 'confirmed' },
  unconfirm: { kinds: ['CUT'], from: ['confirmed'], to: 'planned' },
  pause: { kinds: ['OPEN', 'CUT'], from: ['planned', 'confirmed'], to: 'paused' },
  resume: { kinds: ['OPEN', 'CUT'], from: ['paused'], to: 'planned' },
};

async function transition(id, op, adminId, now = new Date()) {
  const t = TRANSITIONS[op];
  if (!t) throw Object.assign(new Error(`Unknown action "${op}"`), { status: 400 });
  const set = { status: t.to };
  if (op === 'confirm') {
    Object.assign(set, { confirmed_by: adminId || null, confirmed_at: new Date() });
    const current = await ExpiryAction.findById(id).select('execute_at').lean();
    if (current && now - new Date(current.execute_at) > CONFIRM_WINDOW_MS) {
      throw Object.assign(new Error("Too late to confirm — the next session has started since this cut's close"), { status: 409 });
    }
  }
  if (op === 'unconfirm') Object.assign(set, { confirmed_by: null, confirmed_at: null });
  const updated = await ExpiryAction.findOneAndUpdate(
    { _id: id, kind: { $in: t.kinds }, status: { $in: t.from } },
    { $set: set },
    { new: true },
  ).lean();
  if (!updated) {
    const current = await ExpiryAction.findById(id).select('kind status').lean();
    if (!current) throw Object.assign(new Error('Expiry action not found'), { status: 404 });
    throw Object.assign(new Error(`Cannot ${op} a ${current.kind} action that is ${current.status}`), { status: 409 });
  }
  return updated;
}

/* -------------------------------------------------------- announcement -- */

const EXCHANGE_ORDER = ['MCX', 'COMEX', 'NSE', 'GIFT NIFTY', 'GLOBAL'];
const WEEKDAYS = ['SUNDAY', 'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY'];
const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/** '2026-10-23' → '23-OCT-FRIDAY' */
function formatDay(key) {
  const d = new Date(`${key}T00:00:00.000Z`);
  return `${String(d.getUTCDate()).padStart(2, '0')}-${MONTHS[d.getUTCMonth()]}-${WEEKDAYS[d.getUTCDay()]}`;
}

/** '23:30' → '11.30 P.M.' */
function formatTime(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return `${h % 12 || 12}.${String(m).padStart(2, '0')} ${h < 12 ? 'A.M.' : 'P.M.'}`;
}

/**
 * The "NEW CONTRACT Open 📢" notice for one day's opens, in the format the
 * business already circulates by hand. The admin can edit it before publishing.
 */
async function buildAnnouncement(date) {
  const opens = await ExpiryAction.find({ kind: 'OPEN', action_date: date, status: { $ne: 'obsolete' } }).lean();
  if (opens.length === 0) return { message: '', opens: 0 };
  const cuts = await ExpiryAction.find({
    kind: 'CUT',
    status: { $ne: 'obsolete' },
    $or: opens.map((o) => ({ group_key: o.group_key, current_expiry: o.current_expiry })),
  }).lean();

  const lines = ['NEW CONTRACT Open 📢', ''];
  for (const exchange of EXCHANGE_ORDER) {
    const blocks = opens
      .filter((o) => o.exchange_label === exchange)
      .map((o) => {
        const group = groupByKey.get(o.group_key);
        if (!group?.names) return [`ALL ${group ? group.label.toUpperCase() : o.group_label.toUpperCase()}`];
        return [...new Set(o.targets.map((t) => t.name.toUpperCase()))];
      });
    if (blocks.length === 0) continue;
    lines.push(`${exchange} - `, '');
    blocks.forEach((names) => lines.push(...names, ''));
  }

  const settlements = new Map();
  for (const c of cuts) {
    const k = `${c.action_date}|${c.close_time}`;
    if (!settlements.has(k)) settlements.set(k, { date: c.action_date, time: c.close_time, labels: [] });
    settlements.get(k).labels.push(c.group_label);
  }
  for (const s of [...settlements.values()].sort((a, b) => a.date.localeCompare(b.date))) {
    const prefix = settlements.size > 1 ? `${s.labels.join(', ')} — ` : '';
    lines.push(`${prefix}Old Contract settlement: ${formatDay(s.date)} at last Quotation`, ` ( ${formatTime(s.time)} )`, '');
  }
  // The notice leaves the banner once the last old contract has settled.
  const last = [...settlements.values()].sort((a, b) => `${a.date}${a.time}`.localeCompare(`${b.date}${b.time}`)).pop();
  const expires_at = last ? new Date(`${last.date}T${last.time}:00+05:30`) : new Date(`${date}T23:59:00+05:30`);
  return { message: lines.join('\n').trimEnd(), opens: opens.length, expires_at };
}

/**
 * Publish: becomes the app-wide announcement banner (replacing the current
 * one), plus an optional push notification to every client and master with
 * the app installed — sent in the background, one account at a time,
 * respecting each account's notification settings.
 */
async function publishAnnouncement({ message, push, adminId, date }) {
  const text = String(message || '').trim();
  if (!text) throw Object.assign(new Error('Message is required'), { status: 400 });
  // That day's 'expiry' section of the banner only — the ban list and an
  // admin's own message keep scrolling alongside (services/announcementBoard.js).
  const day = /^\d{4}-\d{2}-\d{2}$/.test(String(date || '')) ? date : dateKey(toIndiaDateOnly(new Date()));
  const { expires_at } = await buildAnnouncement(day);
  const announcement = await require('./announcementBoard').postSection('expiry', text, { ref: day, expiresAt: expires_at, createdBy: adminId });

  let recipients = 0;
  if (push) {
    const User = require('../models/User');
    const Master = require('../models/Master');
    const withTokens = { deleted_at: null, 'fcm_tokens.0': { $exists: true } };
    const ids = [
      ...(await User.find(withTokens).select('_id').lean()),
      ...(await Master.find(withTokens).select('_id').lean()),
    ].map((r) => r._id.toString());
    recipients = ids.length;
    const firebaseService = require('./firebaseService');
    const title = text.split('\n')[0].slice(0, 80);
    const body = text.split('\n').slice(1).filter((l) => l.trim()).join(', ').slice(0, 900);
    (async () => {
      for (const id of ids) {
        await firebaseService.sendNotification(id, 'announcement', { title, body, data: { reason: 'expiry_announcement' } });
      }
      console.log(`📣 [ExpiryActions] Announcement pushed to ${ids.length} account(s)`);
    })().catch((e) => console.error(`❌ [ExpiryActions] Announcement push failed: ${e.message}`));
  }
  return { announcement_id: announcement._id, push_recipients: recipients };
}

module.exports = {
  getRolloverTokens,
  refreshPlan,
  runDue,
  list,
  transition,
  buildAnnouncement,
  publishAnnouncement,
  _private: { reconcileOpenWindow, formatDay, formatTime, captureSnapshot, executeCut, executeOpen, closeNewTargetsUntilOpen, refreshRolloverTokensForTest: refreshRolloverTokens },
};
