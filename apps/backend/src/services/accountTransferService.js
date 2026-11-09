'use strict';
/**
 * Account transfer (owner, 9 Nov 2026): move client accounts to another master
 * from the admin panel — the same steps that were done by hand for the BDS82 →
 * RITESH, Harish → AMD and RAHUL → BHUMIK/RITESH moves, with the checks built in.
 *
 * What a transfer changes, in ONE database transaction under the trade-write
 * lease (so it can't interleave with a settlement or a fill):
 *   1. the client's master (users.master_id);
 *   2. the client's rows of the CURRENT, not yet settled week (trades.master_id):
 *      every completed / pending row that isn't deleted — exactly the rows the
 *      next settlement reads (it books each position under the master on the
 *      position's first row, and both fill paths keep a pending order's own
 *      master) — plus this week's cancelled / rejected rows (history screens);
 *   3. optionally (raise_low_rates), the client's brokerage on scripts where his
 *      rate is BELOW the new master's own rate: raised to his usual rate for
 *      that segment (never below the new master's rate), effective from now;
 *   4. an AccountTransfer record with everything needed to Undo it.
 * Past weeks (settled trades, settlement history, bills, ledger entries),
 * wallets and credits, and every other account are never touched. Funding
 * stays where it is (owner's choice): later withdrawals return to the new master.
 *
 * After the commit the running server's caches are refreshed (live metrics,
 * master tree, brokerage rules) — no restart is needed.
 *
 * Checks (preview): BLOCKS make a transfer impossible; WARNINGS must be
 * accepted. By the owner's decision a segment the new master doesn't have and
 * a profit-book time below the new master's base are warnings, not blocks.
 */

const crypto = require('crypto');
const mongoose = require('mongoose');
const User = require('../models/User');
const Master = require('../models/Master');
const Trade = require('../models/Trade');
const BrokerageSettings = require('../models/BrokerageSettings');
const SettlementRun = require('../models/SettlementRun');
const AccountTransfer = require('../models/AccountTransfer');
const { isUserExchangeRowAllowed, normalizeExchangeName } = require('../utils/exchangeAccess');
const { profitBookMinutesOf, baseOf } = require('../utils/profitBookTime');

const MAX_CLIENTS = 100;
const ACTIVE_STATUSES = ['completed', 'pending'];

// ─── errors ──────────────────────────────────────────────────────────────────

class TransferError extends Error {
  constructor(status, message, data = null) {
    super(message);
    this.status = status;
    this.data = data;
  }
}

// ─── pure helpers (unit-tested) ─────────────────────────────────────────────

const idOf = (v) => (v == null ? null : String(v._id || v));
/** "RITESH (172717)" — name and code, or just the code when they're the same. */
const label = (a) => (!a ? '—' : a.name && a.name !== a.username ? `${a.name} (${a.username})` : String(a.username || a.name || '—'));
const round2 = (n) => Math.round((Number(n) + Number.EPSILON) * 100) / 100;
const round4 = (n) => Math.round((Number(n) + Number.EPSILON) * 10000) / 10000;

/** A client's ticked segments (exchanges_allowed rows with turnover or lot on), as stored. */
function clientSegments(user) {
  return [...new Set((user?.exchanges_allowed || [])
    .filter(isUserExchangeRowAllowed)
    .map((ex) => String(ex.exchange_name || '').toUpperCase())
    .filter(Boolean))];
}

/** The client's segments the master doesn't have (GLOBAL and INDICES count as the same). */
function segmentsNotAllowed(user, master) {
  const allowed = new Set((master?.exchanges_allowed || []).map(normalizeExchangeName));
  return clientSegments(user).filter((seg) => !allowed.has(normalizeExchangeName(seg)));
}

/**
 * The chain from a master up to the top: [direct master, its parent, …, top].
 * Cycle-guarded; stops at a missing master.
 */
function chainOf(masterId, mastersById) {
  const out = [];
  const seen = new Set();
  for (let cur = idOf(masterId); cur && !seen.has(cur); ) {
    seen.add(cur);
    const m = mastersById.get(cur);
    if (!m) break;
    out.push(m);
    cur = idOf(m.master_id);
  }
  return out;
}

/**
 * P&L share of every level for one client (the Ledger's ceiling model,
 * weeklyAdminController): the direct master keeps its own %, each master above
 * keeps (its % − the % of the master below it), admin keeps (100 − top's %).
 * Returns [{ master_id, username, name, pct }, …, { admin: true, pct }].
 */
function pnlSplit(chain) {
  const out = [];
  let below = 0;
  for (const m of chain) {
    const own = Number(m.pnl_sharing) || 0;
    out.push({ master_id: idOf(m), username: m.username, name: m.name, pct: round4(own - below) });
    below = own;
  }
  out.push({ admin: true, pct: round4(100 - below) });
  return out;
}

/**
 * Brokerage kept by every level per unit of the client's rate (the Ledger's
 * rate-gap model, weeklyAdminController _getUserEntryBatched /
 * _getAggregatedEntryBatched): with the client paying c and level j having its
 * own rate r_j and brokerage sharing B_j —
 *   direct master: (c − r1) + r1·B1/100
 *   master j ≥ 2:  r(j−1)·(100 − B(j−1))/100 − r_j·(100 − B_j)/100
 *   admin:         r_top·(100 − B_top)/100
 * The levels add up to c. `levels` = [{ rate, sharing }] from the direct master up.
 */
function brokerageSplit(clientRate, levels) {
  const c = Number(clientRate) || 0;
  const out = [];
  if (levels.length === 0) return [{ admin: true, keep: round4(c) }];
  const passUp = (lv) => (Number(lv.rate) || 0) * (100 - (Number(lv.sharing) || 0)) / 100;
  const r1 = Number(levels[0].rate) || 0;
  out.push({ keep: round4((c - r1) + r1 * (Number(levels[0].sharing) || 0) / 100) });
  for (let j = 1; j < levels.length; j++) out.push({ keep: round4(passUp(levels[j - 1]) - passUp(levels[j])) });
  out.push({ admin: true, keep: round4(passUp(levels[levels.length - 1])) });
  return out;
}

/**
 * The most common rate among an account's brokerage rows for one exchange
 * (exactly as stored) and type; ties go to the higher rate. null when none.
 */
function usualRate(rows, exchangeName, type) {
  const ex = String(exchangeName || '').toUpperCase();
  const counts = new Map();
  for (const r of rows) {
    if (String(r.exchange_name || '').toUpperCase() !== ex || r.type !== type || r.deleted_at) continue;
    const v = Number(r.brk_value);
    if (!Number.isFinite(v)) continue;
    counts.set(v, (counts.get(v) || 0) + 1);
  }
  let best = null;
  let bestN = 0;
  for (const [v, n] of counts) if (n > bestN || (n === bestN && v > best)) { best = v; bestN = n; }
  return best;
}

/** The type (TURNOVER WISE / LOT WISE) most of an account's rows use for an exchange. */
function usualType(rows, exchangeName) {
  const ex = String(exchangeName || '').toUpperCase();
  const counts = new Map();
  for (const r of rows) {
    if (String(r.exchange_name || '').toUpperCase() !== ex || r.deleted_at) continue;
    counts.set(r.type, (counts.get(r.type) || 0) + 1);
  }
  let best = null;
  let bestN = 0;
  for (const [t, n] of counts) if (n > bestN) { best = t; bestN = n; }
  return best;
}

const rateKey = (r) => `${String(r.exchange_name || '').toUpperCase()}|${String(r.script_name || '').toUpperCase()}|${r.type}`;

/**
 * Scripts (that can be traded now) where the client's rate is BELOW the new
 * master's own rate for the exact same exchange/script/type — the new master
 * would earn nothing or less than nothing on them. raise_to = the client's
 * usual rate for that exchange and type, never below the master's rate.
 */
function lowRates(clientRows, masterRows, isTradable = () => true) {
  const masterByKey = new Map();
  for (const r of masterRows) if (!r.deleted_at && !masterByKey.has(rateKey(r))) masterByKey.set(rateKey(r), r);
  const out = [];
  for (const r of clientRows) {
    if (r.deleted_at) continue;
    const m = masterByKey.get(rateKey(r));
    if (!m) continue;
    const cv = Number(r.brk_value);
    const mv = Number(m.brk_value);
    if (!(cv < mv) || !isTradable(r.script_name)) continue;
    const usual = usualRate(clientRows, r.exchange_name, r.type);
    out.push({
      brokerage_id: idOf(r),
      exchange_name: r.exchange_name,
      script_name: r.script_name,
      type: r.type,
      client_value: cv,
      master_value: mv,
      raise_to: Math.max(usual == null ? mv : usual, mv),
    });
  }
  return out.sort((a, b) => (a.exchange_name + a.script_name).localeCompare(b.exchange_name + b.script_name));
}

/**
 * The client's rows of the current, not yet settled week. Settlement retires
 * every completed row and cancels every pending one, so "not deleted and
 * completed/pending" is exactly the open week; cancelled/rejected rows of the
 * week are those created since the last completed settlement's cutoff.
 */
function currentPeriodFilter(userIds, lastCutoff) {
  const or = [{ status: { $in: ACTIVE_STATUSES } }];
  if (lastCutoff) or.push({ createdAt: { $gte: lastCutoff } });
  return { user_id: { $in: userIds }, deleted_at: null, $or: or };
}

function previewToken(canonical) {
  return crypto.createHash('sha256').update(JSON.stringify(canonical)).digest('hex');
}

// ─── data access ────────────────────────────────────────────────────────────

const withSession = (q, session) => (session ? q.session(session) : q);

async function lastSettlementCutoff(session = null) {
  const run = await withSession(SettlementRun.findOne({ status: 'completed' }).sort({ trading_date: -1 }).select('trade_cutoff_at period_key completed_at'), session).lean();
  return run?.trade_cutoff_at ? new Date(run.trade_cutoff_at) : null;
}

/** True while a weekly settlement holds the fence or a run is unresolved (same check every trade write makes). */
async function settlementUnresolved() {
  const fence = require('./tradeWriteFenceService');
  const check = fence._private && fence._private.hasUnresolvedSettlement;
  if (typeof check !== 'function') throw new Error('settlement check unavailable');
  return check();
}

async function loadTradableNames() {
  try {
    const { tradingScriptNames, isTradingName } = require('./brokerageCopyService');
    const trading = await tradingScriptNames();
    return (name) => isTradingName(trading, name);
  } catch (_) {
    return () => true;
  }
}

async function comexBeforeAfter(userId, toMasterId, session) {
  try {
    const { loadComexFx, loadMasterComexFx } = require('../utils/comexFx');
    const before = await loadComexFx(session, userId);
    if (before?.source === 'client') return { before, after: before, changes: false };
    const after = await loadMasterComexFx(toMasterId, session);
    const same = (a, b) => (!a && !b) || (a && b && a.base === b.base && a.spread === b.spread);
    return { before, after, changes: !same(before, after) };
  } catch (_) {
    return null;
  }
}

/** Rates of a master for the money table: its own rows, else the global rows (as the Ledger does). */
function rulesOf(masterId, rowsByOwner, globalRows) {
  const own = rowsByOwner.get(idOf(masterId));
  return own && own.length ? own : globalRows;
}

// ─── preview ────────────────────────────────────────────────────────────────

/**
 * Everything the admin needs to decide, without writing anything.
 * @param {object} p
 * @param {string[]} p.userIds
 * @param {string} p.toMasterId
 * @param {Set<string>|null} [p.hiddenMasterIds] the calling admin's hidden masters (expanded)
 */
async function buildPreview({ userIds, toMasterId, hiddenMasterIds = null, session = null }) {
  const ids = [...new Set((userIds || []).map(String).filter(Boolean))];
  if (ids.length === 0) throw new TransferError(400, 'Select at least one client');
  if (ids.length > MAX_CLIENTS) throw new TransferError(400, `At most ${MAX_CLIENTS} clients in one transfer`);
  if (!ids.every((x) => mongoose.isValidObjectId(x))) throw new TransferError(400, 'Invalid client id');
  if (!toMasterId || !mongoose.isValidObjectId(String(toMasterId))) throw new TransferError(400, 'Select the new master');

  const masters = await withSession(Master.find({}).select('_id name username master_id pnl_sharing brokerage_sharing exchanges_allowed status active_status deleted_at server_id profit_book_base_minutes'), session).lean();
  const mastersById = new Map(masters.map((m) => [idOf(m), m]));
  const to = mastersById.get(String(toMasterId));
  if (!to) throw new TransferError(404, 'New master not found');

  const users = await withSession(User.find({ _id: { $in: ids } }).select('_id name username master_id status active_status deleted_at exchanges_allowed profit_book_minutes server_id'), session).lean();
  const usersById = new Map(users.map((u) => [idOf(u), u]));

  const lastCutoff = await lastSettlementCutoff(session);
  const rows = await withSession(Trade.find(currentPeriodFilter(ids, lastCutoff)).select('_id user_id master_id status trade_type tradingsymbol transaction_type executed_quantity quantity createdAt').sort({ _id: 1 }), session).lean();
  const rowsByUser = new Map();
  for (const r of rows) {
    const k = idOf(r.user_id);
    if (!rowsByUser.has(k)) rowsByUser.set(k, []);
    rowsByUser.get(k).push(r);
  }

  const toChain = chainOf(to, mastersById);
  const ruleOwnerIds = new Set([...ids]);
  for (const m of toChain) ruleOwnerIds.add(idOf(m));
  for (const u of users) for (const m of chainOf(u.master_id, mastersById)) ruleOwnerIds.add(idOf(m));
  const brkRows = await withSession(BrokerageSettings.find({ $or: [{ user_id: { $in: [...ruleOwnerIds] } }, { user_id: null }], deleted_at: null }).select('_id user_id exchange_name script_name type brk_value deleted_at'), session).lean();
  const rowsByOwner = new Map();
  const globalRows = [];
  for (const r of brkRows) {
    if (!r.user_id) { globalRows.push(r); continue; }
    const k = idOf(r.user_id);
    if (!rowsByOwner.has(k)) rowsByOwner.set(k, []);
    rowsByOwner.get(k).push(r);
  }
  const isTradable = await loadTradableNames();
  const unresolved = await settlementUnresolved();

  const toBlocks = [];
  if (to.deleted_at) toBlocks.push({ code: 'TARGET_DELETED', message: `${label(to)} is deleted` });
  if (to.status !== 'active' || to.active_status === false) toBlocks.push({ code: 'TARGET_INACTIVE', message: `${label(to)} is not active` });
  if (hiddenMasterIds && toChain.some((m) => hiddenMasterIds.has(idOf(m)))) toBlocks.push({ code: 'TARGET_HIDDEN', message: `${label(to)} is not visible to your admin account` });
  if (unresolved) toBlocks.push({ code: 'SETTLEMENT_RUNNING', message: 'A weekly settlement is running or unresolved — try again after it completes' });

  const masterView = (m) => ({ id: idOf(m), username: m.username, name: m.name, pnl_sharing: Number(m.pnl_sharing) || 0, brokerage_sharing: Number(m.brokerage_sharing) || 0 });
  const toTop = toChain[toChain.length - 1];

  const clients = [];
  for (const id of ids) {
    const u = usersById.get(id);
    if (!u) {
      clients.push({ user: { id }, blocks: [{ code: 'CLIENT_NOT_FOUND', message: 'Client not found' }], warnings: [], notices: [] });
      continue;
    }
    const blocks = [];
    const warnings = [];
    const notices = [];
    const from = mastersById.get(idOf(u.master_id));
    const fromChain = chainOf(u.master_id, mastersById);
    if (u.deleted_at) blocks.push({ code: 'CLIENT_DELETED', message: `${label(u)} is deleted` });
    if (idOf(u.master_id) === idOf(to)) blocks.push({ code: 'ALREADY_UNDER_TARGET', message: `${label(u)} is already under ${label(to)}` });
    if (!from) blocks.push({ code: 'CURRENT_MASTER_MISSING', message: `${label(u)}'s current master was not found` });
    if (hiddenMasterIds && fromChain.some((m) => hiddenMasterIds.has(idOf(m)))) blocks.push({ code: 'SOURCE_HIDDEN', message: `${label(u)}'s current master is not visible to your admin account` });
    if (idOf(u.server_id) !== idOf(to.server_id)) blocks.push({ code: 'SERVER_MISMATCH', message: `${label(u)} and ${label(to)} are on different servers` });

    // Warnings the admin must accept (owner: these two are warnings, not blocks).
    const missingSegs = segmentsNotAllowed(u, to);
    if (missingSegs.length) {
      warnings.push({
        code: 'SEGMENT_NOT_ALLOWED',
        message: `${label(to)} does not have ${missingSegs.join(', ')} himself. ${label(u)} keeps trading ${missingSegs.length > 1 ? 'them' : 'it'} (his own permission decides), but ${label(to)}'s own edit screens may not show ${missingSegs.length > 1 ? 'these segments' : 'this segment'}.`,
        segments: missingSegs,
      });
    }
    const minutes = profitBookMinutesOf(u);
    const base = baseOf(to);
    if (minutes < base) {
      warnings.push({
        code: 'PROFIT_BOOK_BELOW_BASE',
        message: `Profit-book time ${minutes} min is below ${label(to)}'s base of ${base} min. It stays ${minutes} min; editing his account later will ask for at least ${base} min.`,
        minutes,
        base,
      });
    }
    const fromTop = fromChain[fromChain.length - 1];
    if (from && idOf(fromTop) !== idOf(toTop)) {
      warnings.push({ code: 'CROSS_TREE', message: `Moves from ${label(fromTop)}'s tree to ${label(toTop)}'s tree — the P&L and brokerage shares of every upline change (see the tables).` });
    }
    const clientRows = rowsByOwner.get(id) || [];
    const toRules = rulesOf(to, rowsByOwner, globalRows);
    const low = lowRates(clientRows, toRules, isTradable);
    if (low.length) {
      warnings.push({
        code: 'LOW_RATES',
        message: `On ${low.length} script${low.length > 1 ? 's' : ''} ${label(u)}'s rate is below ${label(to)}'s own rate, so ${label(to)} would earn nothing or less on ${low.length > 1 ? 'them' : 'it'}. Tick "raise low rates" to set them to his usual rate.`,
        count: low.length,
      });
    }
    const comex = clientSegments(u).some((s) => s.startsWith('COMEX')) ? await comexBeforeAfter(id, idOf(to), session) : null;
    if (comex?.changes) {
      const f = (x) => (x ? `${x.base} ± ${x.spread}` : 'not set');
      warnings.push({ code: 'COMEX_RATE_CHANGES', message: `His COMEX dollar rate is inherited and changes from ${f(comex.before)} to ${f(comex.after)} at the next settlement.` });
    }

    // What moves with him.
    const myRows = rowsByUser.get(id) || [];
    const net = new Map();
    for (const r of myRows) {
      if (r.status !== 'completed') continue;
      const q = Number(r.executed_quantity) || 0;
      net.set(r.tradingsymbol, (net.get(r.tradingsymbol) || 0) + (r.transaction_type === 'BUY' ? q : -q));
    }
    const openPositions = [...net].filter(([, q]) => Math.abs(q) > 1e-9).map(([symbol, qty]) => ({ symbol, qty }));
    const counts = { completed: 0, pending: 0, other: 0 };
    for (const r of myRows) {
      if (r.status === 'completed') counts.completed++;
      else if (r.status === 'pending') counts.pending++;
      else counts.other++;
    }
    notices.push({ code: 'FUNDING_STAYS', message: `Wallets and credits stay as they are; a later withdrawal returns to ${label(to)}.` });
    notices.push({ code: 'PREVIOUS_WEEK_LEDGER', message: `Past weeks stay booked under ${from ? label(from) : 'the old master'} (settlements, bills). The Ledger's "Previous Week" view groups by today's master, so it will show him under ${label(to)}.` });

    // Money from now on, before vs after.
    const moneyFor = (chain) => {
      const pnl = pnlSplit(chain);
      const brokerage = clientSegments(u).map((seg) => {
        const type = usualType(clientRows, seg);
        const clientRate = type ? usualRate(clientRows, seg, type) : null;
        if (clientRate == null) return { segment: seg, type: null, client_rate: null, levels: [] };
        const levels = chain.map((m) => {
          const rules = rulesOf(m, rowsByOwner, globalRows);
          return { rate: usualRate(rules, seg, type) ?? 0, sharing: Number(m.brokerage_sharing) || 0 };
        });
        const split = brokerageSplit(clientRate, levels);
        return {
          segment: seg,
          type,
          unit: type === 'LOT WISE' ? 'per lot' : 'per ₹1 crore turnover (rate × 1,000)',
          client_rate: clientRate,
          levels: split.map((s, i) => (s.admin ? { admin: true, keep: s.keep } : { master_id: idOf(chain[i]), username: chain[i].username, rate: levels[i].rate, keep: s.keep })),
        };
      });
      return { pnl, brokerage };
    };

    clients.push({
      user: { id, username: u.username, name: u.name, status: u.status, active_status: u.active_status !== false },
      from: from ? masterView(from) : null,
      from_chain: fromChain.map(masterView),
      to_chain: toChain.map(masterView),
      blocks,
      warnings,
      notices,
      rows: { ...counts, total: myRows.length, open_positions: openPositions },
      row_ids: myRows.map((r) => ({ id: idOf(r), status: r.status, master_id: idOf(r.master_id) })),
      low_rates: low,
      money: { before: from ? moneyFor(fromChain) : null, after: moneyFor(toChain) },
    });
  }

  const canonical = {
    to: { id: idOf(to), parent: idOf(to.master_id), p: to.pnl_sharing, b: to.brokerage_sharing, s: to.status, a: to.active_status, d: !!to.deleted_at },
    chain: toChain.map((m) => [idOf(m), m.pnl_sharing, m.brokerage_sharing]),
    clients: clients.map((c) => ({
      id: c.user.id,
      from: c.from?.id || null,
      rows: (c.row_ids || []).map((r) => [r.id, r.status, r.master_id]),
      low: (c.low_rates || []).map((l) => [l.brokerage_id, l.client_value, l.master_value, l.raise_to]),
      w: (c.warnings || []).map((w) => w.code),
      b: (c.blocks || []).map((b) => b.code),
    })),
    toBlocks: toBlocks.map((b) => b.code),
  };

  return {
    to: { ...masterView(to), chain: toChain.map(masterView), blocks: toBlocks },
    clients,
    last_settlement_cutoff: lastCutoff,
    block_count: toBlocks.length + clients.reduce((s, c) => s + c.blocks.length, 0),
    warning_count: clients.reduce((s, c) => s + c.warnings.length, 0),
    low_rate_count: clients.reduce((s, c) => s + (c.low_rates || []).length, 0),
    token: previewToken(canonical),
  };
}

// ─── apply ──────────────────────────────────────────────────────────────────

/** Refresh the running server's in-memory state after a commit (no restart needed). */
async function refreshCaches(userIds, { rulesChanged = false } = {}) {
  const metricsEngine = require('./metricsEngine');
  try { if (typeof metricsEngine.refreshMasterTree === 'function') await metricsEngine.refreshMasterTree(); } catch (e) { console.error('[AccountTransfer] master tree refresh failed:', e.message); }
  if (rulesChanged) { try { await metricsEngine.reloadRules(); } catch (e) { console.error('[AccountTransfer] rules reload failed:', e.message); } }
  for (const uid of userIds) {
    try { await metricsEngine.onTradeExecuted(String(uid)); } catch (e) { console.error(`[AccountTransfer] metrics refresh failed for ${uid}:`, e.message); }
  }
}

/**
 * Rows of these clients that are still on another master after the commit —
 * an order placed in the instant the transfer committed. Moved right away and
 * recorded as late_rows. Returns Map(userId → rows moved).
 */
async function sweepLateRows(userToMaster, lastCutoff) {
  const moved = new Map();
  const ids = [...userToMaster.keys()];
  const stray = await Trade.find(currentPeriodFilter(ids, lastCutoff)).select('_id user_id master_id status').lean();
  for (const r of stray) {
    const uid = idOf(r.user_id);
    const target = userToMaster.get(uid);
    if (!target || idOf(r.master_id) === target) continue;
    const res = await Trade.updateOne({ _id: r._id, master_id: r.master_id }, { $set: { master_id: new mongoose.Types.ObjectId(target) } }, { timestamps: false });
    if (res.modifiedCount === 1) {
      if (!moved.has(uid)) moved.set(uid, []);
      moved.get(uid).push({ trade_id: r._id, from_master_id: r.master_id || null, status: r.status });
    }
  }
  return moved;
}

/**
 * Do the transfer. Re-builds the preview and refuses unless it matches the one
 * the admin confirmed (token), has no blocks, and every warning was accepted.
 */
async function applyTransfer({ userIds, toMasterId, token, acceptWarnings, raiseLowRates, confirmUsername, actor, hiddenMasterIds = null }) {
  const preview = await buildPreview({ userIds, toMasterId, hiddenMasterIds });
  if (!confirmUsername || String(confirmUsername).trim() !== String(preview.to.username)) {
    throw new TransferError(400, `Type the new master's code (${preview.to.username}) to confirm`);
  }
  if (preview.block_count > 0) throw new TransferError(422, 'This transfer has blocks — see the preview', { preview });
  if (!token || token !== preview.token) throw new TransferError(409, 'Something changed since the preview (an order, a fill or a setting). Preview again before transferring.', { preview });
  if (preview.warning_count > 0 && acceptWarnings !== true) throw new TransferError(422, 'Accept the warnings to continue', { preview });

  const toId = new mongoose.Types.ObjectId(preview.to.id);
  const lastCutoff = preview.last_settlement_cutoff;
  const wantRaise = raiseLowRates === true && preview.low_rate_count > 0;
  const now = new Date();
  let record = null;

  const { withTradeWriteLease } = require('./tradeWriteFenceService');
  await withTradeWriteLease('account_transfer', async (lease) => {
    const session = await mongoose.startSession();
    try {
      await session.withTransaction(async () => {
        await lease.assertActive({ session });
        const items = [];
        for (const c of preview.clients) {
          const uid = new mongoose.Types.ObjectId(c.user.id);
          const fromId = new mongoose.Types.ObjectId(c.from.id);

          // Same rows as the preview, inside the transaction.
          const live = await Trade.find(currentPeriodFilter([uid], lastCutoff)).select('_id status master_id').sort({ _id: 1 }).session(session).lean();
          const liveSig = live.map((r) => `${idOf(r)}|${r.status}|${idOf(r.master_id)}`).join(',');
          const prevSig = c.row_ids.map((r) => `${r.id}|${r.status}|${r.master_id}`).join(',');
          if (liveSig !== prevSig) throw new TransferError(409, `${c.user.username}'s orders changed while transferring — nothing was changed. Preview again.`);

          const ur = await User.updateOne({ _id: uid, master_id: fromId, deleted_at: null }, { $set: { master_id: toId, updatedAt: now } }, { session });
          if (ur.modifiedCount !== 1) throw new TransferError(409, `${c.user.username} changed while transferring — nothing was changed. Preview again.`);

          const toMove = live.filter((r) => idOf(r.master_id) !== idOf(toId));
          if (toMove.length) {
            const tr = await Trade.updateMany({ _id: { $in: toMove.map((r) => r._id) }, user_id: uid, deleted_at: null }, { $set: { master_id: toId } }, { session, timestamps: false });
            if (tr.modifiedCount !== toMove.length) throw new TransferError(409, `${c.user.username}: ${tr.modifiedCount} of ${toMove.length} rows moved — rolled back. Preview again.`);
          }

          const rateChanges = [];
          if (wantRaise) {
            for (const l of c.low_rates) {
              const br = await BrokerageSettings.updateOne(
                { _id: new mongoose.Types.ObjectId(l.brokerage_id), user_id: uid, deleted_at: null, brk_value: l.client_value },
                { $set: { brk_value: l.raise_to, effective_from: now } },
                { session, runValidators: true },
              );
              if (br.modifiedCount !== 1) throw new TransferError(409, `${c.user.username}: the rate for ${l.script_name} changed while transferring — rolled back. Preview again.`);
              rateChanges.push({ brokerage_id: l.brokerage_id, exchange_name: l.exchange_name, script_name: l.script_name, type: l.type, from_value: l.client_value, to_value: l.raise_to });
            }
          }

          items.push({
            user_id: uid,
            username: c.user.username,
            name: c.user.name,
            from_master_id: fromId,
            from_master_username: c.from.username,
            moved_rows: toMove.map((r) => ({ trade_id: r._id, from_master_id: r.master_id || null, status: r.status })),
            rate_changes: rateChanges,
            warnings: c.warnings.map((w) => w.code),
          });
        }
        const [doc] = await AccountTransfer.create([{
          to_master_id: toId,
          to_master_username: preview.to.username,
          items,
          raise_low_rates: wantRaise,
          actor_id: String(actor.id),
          actor_username: actor.username || null,
        }], { session });
        record = doc;
      });
    } finally {
      await session.endSession();
    }
  });

  // After the commit: late rows, caches, verification.
  const userToMaster = new Map(preview.clients.map((c) => [c.user.id, preview.to.id]));
  const late = await sweepLateRows(userToMaster, lastCutoff);
  if (late.size) {
    for (const item of record.items) {
      const add = late.get(idOf(item.user_id));
      if (add) item.late_rows = add;
    }
    await AccountTransfer.updateOne({ _id: record._id }, { $set: { items: record.items } });
  }
  await refreshCaches(preview.clients.map((c) => c.user.id), { rulesChanged: wantRaise });
  const verification = await verifyTransfer(record._id);
  return { transfer: record.toObject ? record.toObject() : record, verification };
}

/** Re-read everything a transfer changed and confirm it is as recorded. */
async function verifyTransfer(transferId) {
  const t = await AccountTransfer.findById(transferId).lean();
  if (!t) throw new TransferError(404, 'Transfer not found');
  const target = t.status === 'undone' ? null : idOf(t.to_master_id);
  const lastCutoff = await lastSettlementCutoff();
  const out = [];
  for (const it of t.items) {
    const want = target || idOf(it.from_master_id);
    // After an undo, a recorded row goes back to the master IT had (normally his old master).
    const recorded = new Map([...(it.moved_rows || []), ...(it.late_rows || [])].map((r) => [idOf(r.trade_id), r.from_master_id ? idOf(r.from_master_id) : want]));
    const u = await User.findById(it.user_id).select('master_id').lean();
    const rows = await Trade.find(currentPeriodFilter([it.user_id], lastCutoff)).select('_id master_id').lean();
    const rowsOff = rows.filter((r) => idOf(r.master_id) !== (target ? want : (recorded.get(idOf(r)) || want))).length;
    let ratesOk = true;
    for (const rc of it.rate_changes || []) {
      const b = await BrokerageSettings.findById(rc.brokerage_id).select('brk_value').lean();
      const expect = t.status === 'undone' ? rc.from_value : rc.to_value;
      if (!b || Number(b.brk_value) !== Number(expect)) ratesOk = false;
    }
    out.push({ user_id: idOf(it.user_id), username: it.username, master_ok: idOf(u?.master_id) === want, rows_checked: rows.length, rows_on_other_master: rowsOff, rates_ok: ratesOk });
  }
  return { ok: out.every((x) => x.master_ok && x.rows_on_other_master === 0 && x.rates_ok), clients: out };
}

// ─── undo ───────────────────────────────────────────────────────────────────

/**
 * Put a transfer back, as long as no settlement has completed since it (the
 * week it moved is still open) and every client is still under the master it
 * was moved to. Rows of the open week go back (including ones placed after the
 * transfer — he is back under the old master for the whole week, as before);
 * raised rates go back only where they still hold the raised value.
 */
async function undoTransfer({ transferId, confirmUsername, actor, hiddenMasterIds = null }) {
  if (!mongoose.isValidObjectId(String(transferId))) throw new TransferError(400, 'Invalid transfer id');
  const t = await AccountTransfer.findById(transferId).lean();
  if (!t) throw new TransferError(404, 'Transfer not found');
  if (t.status !== 'done') throw new TransferError(409, 'This transfer was already undone');
  if (!confirmUsername || String(confirmUsername).trim() !== String(t.to_master_username)) {
    throw new TransferError(400, `Type ${t.to_master_username} to confirm the undo`);
  }
  if (!canUndo(t, await latestSettlementRunStart())) throw new TransferError(409, 'A settlement has run since this transfer, so it can no longer be undone here');
  if (await settlementUnresolved()) throw new TransferError(423, 'A weekly settlement is running or unresolved — try again after it completes');

  const masters = await Master.find({}).select('_id username master_id deleted_at status active_status').lean();
  const mastersById = new Map(masters.map((m) => [idOf(m), m]));
  for (const it of t.items) {
    const back = mastersById.get(idOf(it.from_master_id));
    if (!back || back.deleted_at) throw new TransferError(409, `${it.username}'s old master ${it.from_master_username} no longer exists`);
    if (hiddenMasterIds && (chainOf(back, mastersById).some((m) => hiddenMasterIds.has(idOf(m))) || chainOf(t.to_master_id, mastersById).some((m) => hiddenMasterIds.has(idOf(m))))) {
      throw new TransferError(403, 'This transfer involves a master that is not visible to your admin account');
    }
  }

  const lastCutoff = await lastSettlementCutoff();
  const toId = idOf(t.to_master_id);
  const details = [];
  const { withTradeWriteLease } = require('./tradeWriteFenceService');
  await withTradeWriteLease('account_transfer_undo', async (lease) => {
    const session = await mongoose.startSession();
    try {
      await session.withTransaction(async () => {
        await lease.assertActive({ session });
        details.length = 0;
        for (const it of t.items) {
          const uid = new mongoose.Types.ObjectId(idOf(it.user_id));
          const fromId = new mongoose.Types.ObjectId(idOf(it.from_master_id));
          const ur = await User.updateOne({ _id: uid, master_id: new mongoose.Types.ObjectId(toId), deleted_at: null }, { $set: { master_id: fromId, updatedAt: new Date() } }, { session });
          if (ur.modifiedCount !== 1) throw new TransferError(409, `${it.username} is no longer under ${t.to_master_username} — nothing was undone`);
          // Each recorded row goes back to the master it had; every other open-week row on the new master goes to his old master.
          const recorded = new Map([...(it.moved_rows || []), ...(it.late_rows || [])].map((r) => [idOf(r.trade_id), r.from_master_id ? idOf(r.from_master_id) : null]));
          const rows = await Trade.find({ ...currentPeriodFilter([uid], lastCutoff), master_id: new mongoose.Types.ObjectId(toId) }).select('_id').session(session).lean();
          let rowsBack = 0;
          for (const r of rows) {
            const back = recorded.get(idOf(r)) || idOf(fromId);
            const res = await Trade.updateOne({ _id: r._id, master_id: new mongoose.Types.ObjectId(toId) }, { $set: { master_id: new mongoose.Types.ObjectId(back) } }, { session, timestamps: false });
            rowsBack += res.modifiedCount;
          }
          const rates = [];
          for (const rc of it.rate_changes || []) {
            const res = await BrokerageSettings.updateOne(
              { _id: rc.brokerage_id, deleted_at: null, brk_value: rc.to_value },
              { $set: { brk_value: rc.from_value, effective_from: new Date() } },
              { session, runValidators: true },
            );
            rates.push({ script_name: rc.script_name, restored: res.modifiedCount === 1 });
          }
          details.push({ user_id: idOf(uid), username: it.username, rows_back: rowsBack, rates });
        }
        await AccountTransfer.updateOne(
          { _id: t._id, status: 'done' },
          { $set: { status: 'undone', undone_at: new Date(), undone_by_id: String(actor.id), undone_by_username: actor.username || null, undo_details: details } },
          { session },
        );
      });
    } finally {
      await session.endSession();
    }
  });

  await refreshCaches(t.items.map((it) => idOf(it.user_id)), { rulesChanged: t.items.some((it) => (it.rate_changes || []).length) });
  const verification = await verifyTransfer(t._id);
  return { details, verification };
}

/** Latest settlement run of any status (Undo is only possible for transfers after it). */
async function latestSettlementRunStart() {
  const run = await SettlementRun.findOne({}).sort({ createdAt: -1 }).select('createdAt').lean();
  return run?.createdAt ? new Date(run.createdAt) : null;
}

const canUndo = (t, lastRunStart) => t.status === 'done' && !(lastRunStart && lastRunStart > new Date(t.created_at));

async function listTransfers({ page = 1, limit = 30 } = {}) {
  const p = Math.max(1, Number(page) || 1);
  const l = Math.min(100, Math.max(1, Number(limit) || 30));
  const [items, total, lastRunStart] = await Promise.all([
    AccountTransfer.find({}).sort({ created_at: -1 }).skip((p - 1) * l).limit(l).lean(),
    AccountTransfer.countDocuments({}),
    latestSettlementRunStart(),
  ]);
  return { items: items.map((t) => ({ ...t, can_undo: canUndo(t, lastRunStart) })), total, page: p, limit: l };
}

async function getTransfer(transferId) {
  if (!mongoose.isValidObjectId(String(transferId))) throw new TransferError(400, 'Invalid transfer id');
  const t = await AccountTransfer.findById(transferId).lean();
  if (!t) throw new TransferError(404, 'Transfer not found');
  return { ...t, can_undo: canUndo(t, await latestSettlementRunStart()) };
}

module.exports = {
  MAX_CLIENTS,
  TransferError,
  buildPreview,
  applyTransfer,
  undoTransfer,
  verifyTransfer,
  listTransfers,
  getTransfer,
  _private: {
    clientSegments,
    segmentsNotAllowed,
    chainOf,
    pnlSplit,
    brokerageSplit,
    usualRate,
    usualType,
    lowRates,
    currentPeriodFilter,
    previewToken,
    sweepLateRows,
  },
};
