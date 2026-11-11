'use strict';

/**
 * Broker links (owner, 11 Nov 2026): the limits a broker's settings must stay
 * inside, and saving a client / sub-master link. Used by the admin Brokers
 * routes and the master broker routes alike. Writes only BrokerClientLink /
 * BrokerMasterLink — never a user, a master, a trade, a brokerage rule or
 * anything the ledger / settlement reads.
 *
 * Limits — the broker is paid only out of the paying master M's own part, so
 * M never pays a broker out of his upline's money:
 *   rate field              ≤ the markup on EVERY script it covers: (the level below's rate on
 *                            that script) − (M's own rate on it; M's highest when he has no
 *                            row for it), same unit (paisa per ₹100, or ₹ per lot) as below.
 *                            A rate may cover the whole segment, NFO Index / Stock scripts,
 *                            or one MCX script (services/brokerRates, 12 Nov 2026).
 *   brokerage sharing %      ≤ M's brokerage_sharing
 *   P&L sharing %            ≤ M's pnl_sharing − the level below's (0 for a client)
 */

const BrokerageSettings = require('../models/BrokerageSettings');
const BrokerClientLink = require('../models/BrokerClientLink');
const BrokerMasterLink = require('../models/BrokerMasterLink');
const User = require('../models/User');
const Master = require('../models/Master');
const { normSegment } = require('./brokerEarnings');
const { CATEGORY_SEGMENTS, SCRIPT_SEGMENTS, rateKey, rateScope } = require('./brokerRates');
const { categoryForNfoScript } = require('../constants/nfoIndexUnderlyings');

const RATE_TYPES = ['TURNOVER WISE', 'LOT WISE'];
const LOT_SEGMENTS = new Set(['NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT']);
const fail = (status, message) => Object.assign(new Error(message), { status });
const r4 = (n) => Math.round((Number(n) || 0) * 1e4) / 1e4;

const up = (v) => (v == null || v === '' ? null : String(v).trim().toUpperCase());
const minMax = (vals) => (vals.length ? { min: Math.min(...vals), max: Math.max(...vals) } : null);

/**
 * An account's brokerage rows for the broker limits — only scripts that trade
 * somewhere (12 Nov 2026). Rows of scripts in no active instrument (dropped F&O
 * stocks, MCX agri…) are hidden from the Brk Settings lists, so "apply to all"
 * never changes them; they can never earn brokerage, so they must not pull the
 * broker's room down (a client set to 6 on every visible script showed "2–6").
 * Same filter as the settings lists (utils/hideNonTrading).
 */
async function rowsOf(ownerId, { globalFallback = false } = {}) {
  const { withoutNonTrading } = require('../utils/hideNonTrading');
  const fields = 'type exchange_name brk_value script_name';
  const find = async (filter) => BrokerageSettings.find(await withoutNonTrading(BrokerageSettings, filter, 'script_name')).select(fields).lean();
  let rows = await find({ user_id: ownerId, deleted_at: null });
  let usesGlobal = false;
  if (globalFallback && rows.length === 0) {
    rows = await find({ user_id: null, deleted_at: null });
    usesGlobal = true;
  }
  return { rows, usesGlobal };
}

/**
 * Per segment: the room for a broker rate, script by script. The level below's
 * dominant type is the unit; the paying master's rows of the other unit can't be
 * compared (then no room). Returns { segment, type, below, paying, x_max } plus
 * categories { INDEX, STOCK } for NFO-FUT / NFO-OPT and scripts[] for MCX-FUT / MCX-OPT.
 */
function segmentLimit(segment, belowRows, payingRows) {
  const fallbackType = LOT_SEGMENTS.has(segment) ? 'LOT WISE' : 'TURNOVER WISE';
  const mine = belowRows.filter((r) => normSegment(r.exchange_name) === segment);
  if (mine.length === 0) return { segment, type: fallbackType, below: null, paying: null, x_max: 0 };
  const counts = {};
  for (const r of mine) counts[r.type] = (counts[r.type] || 0) + 1;
  const dominant = Object.entries(counts).sort((a, b) => b[1] - a[1])[0][0];
  const type = RATE_TYPES.includes(dominant) ? dominant : fallbackType;
  const below = mine.filter((r) => r.type === dominant);
  const payAll = payingRows.filter((r) => normSegment(r.exchange_name) === segment);
  const pay = payAll.filter((r) => r.type === dominant);
  const payMax = pay.length ? Math.max(...pay.map((r) => Number(r.brk_value) || 0)) : (payAll.length ? Infinity : 0);
  const payByScript = new Map(pay.filter((r) => up(r.script_name)).map((r) => [up(r.script_name), Number(r.brk_value) || 0]));
  const items = below.map((r) => {
    const script = up(r.script_name);
    const v = Number(r.brk_value) || 0;
    const p = script && payByScript.has(script) ? payByScript.get(script) : payMax;
    return { script, below: v, paying: Number.isFinite(p) ? p : null, markup: Number.isFinite(p) ? v - p : -Infinity };
  });
  const room = (list) => (list.length ? Math.max(0, r4(Math.min(...list.map((i) => i.markup)))) : 0);
  const payVals = (pay.length ? pay : payAll).map((r) => Number(r.brk_value) || 0);
  const out = {
    segment,
    type,
    below: { type: dominant, ...minMax(below.map((r) => Number(r.brk_value) || 0)) },
    paying: payVals.length ? { type: (pay.length ? pay : payAll)[0].type, ...minMax(payVals) } : null,
    x_max: room(items),
  };
  if (CATEGORY_SEGMENTS.has(segment)) {
    out.categories = {};
    for (const cat of ['INDEX', 'STOCK']) {
      // A row with no script name is a whole-segment rule: it counts for both.
      const list = items.filter((i) => !i.script || categoryForNfoScript(segment, i.script) === cat);
      out.categories[cat] = { below: minMax(list.map((i) => i.below)), x_max: room(list) };
    }
  }
  if (SCRIPT_SEGMENTS.has(segment)) {
    out.scripts = items
      .filter((i) => i.script)
      .map((i) => ({ script: i.script, below: i.below, paying: i.paying, x_max: Number.isFinite(i.markup) ? Math.max(0, r4(i.markup)) : 0 }))
      .sort((a, b) => a.script.localeCompare(b.script));
  }
  return out;
}

function segmentLimits(segments, belowRows, payingRows) {
  return segments.map((segment) => segmentLimit(segment, belowRows, payingRows));
}

/** Limits for a broker on a client: paying master = the client's master. */
async function clientLimits(userId) {
  const user = await User.findOne({ _id: userId, deleted_at: null }).select('username name master_id exchanges_allowed').lean();
  if (!user) throw fail(404, 'Client not found');
  const paying = user.master_id ? await Master.findOne({ _id: user.master_id, deleted_at: null }).select('username name pnl_sharing brokerage_sharing').lean() : null;
  if (!paying) throw fail(400, "The client's master was not found");
  const { rows: belowRows, usesGlobal } = await rowsOf(user._id, { globalFallback: true });
  const { rows: payingRows } = await rowsOf(paying._id);
  const segments = [...new Set((user.exchanges_allowed || []).map((e) => normSegment(e.exchange_name)).filter(Boolean))];
  return {
    kind: 'client',
    target: { id: String(user._id), username: user.username, name: user.name, uses_global_brokerage: usesGlobal },
    paying_master: { id: String(paying._id), username: paying.username, name: paying.name },
    pnl_max: Math.max(0, Number(paying.pnl_sharing) || 0),
    brk_max: Math.max(0, Number(paying.brokerage_sharing) || 0),
    below_pnl_pct: 0,
    segments: segmentLimits(segments, belowRows, payingRows),
  };
}

/** Limits for a broker on a sub-master S: paying master = S's parent. */
async function subMasterLimits(masterId) {
  const sub = await Master.findOne({ _id: masterId, deleted_at: null }).select('username name master_id pnl_sharing brokerage_sharing exchanges_allowed').lean();
  if (!sub) throw fail(404, 'Sub-master not found');
  const paying = sub.master_id ? await Master.findOne({ _id: sub.master_id, deleted_at: null }).select('username name pnl_sharing brokerage_sharing').lean() : null;
  if (!paying) throw fail(400, 'A broker can be added only on a sub-master (a master with a parent master)');
  const { rows: belowRows } = await rowsOf(sub._id);
  const { rows: payingRows } = await rowsOf(paying._id);
  const segments = [...new Set((sub.exchanges_allowed || []).map((e) => normSegment(typeof e === 'string' ? e : e.exchange_name)).filter(Boolean))];
  const belowPnl = Math.max(0, Number(sub.pnl_sharing) || 0);
  const belowBrk = Math.max(0, Number(sub.brokerage_sharing) || 0);
  return {
    kind: 'master',
    target: { id: String(sub._id), username: sub.username, name: sub.name },
    paying_master: { id: String(paying._id), username: paying.username, name: paying.name },
    pnl_max: Math.max(0, (Number(paying.pnl_sharing) || 0) - belowPnl),
    // Ledger ceilings are cumulative: the broker's own % sits between S's and M's.
    brk_max: Math.max(0, (Number(paying.brokerage_sharing) || 0) - belowBrk),
    below_pnl_pct: belowPnl,
    below_brk_pct: belowBrk,
    segments: segmentLimits(segments, belowRows, payingRows),
  };
}

/** Checks a broker's settings against the limits. Returns { rates, pnl_share_pct, brk_share_pct }. */
function cleanSettings(body, limits) {
  const pct = (v, name, max) => {
    const n = v === undefined || v === null || v === '' ? 0 : Number(v);
    if (!Number.isFinite(n) || n < 0 || n > 100) throw fail(400, `${name} must be between 0 and 100`);
    if (n > max + 1e-9) throw fail(400, `${name} can be at most ${r4(max)}% here (it comes out of ${limits.paying_master.name || limits.paying_master.username}'s own share)`);
    return r4(n);
  };
  const pnl = pct(body.pnl_share_pct, 'P&L sharing', limits.pnl_max);
  const brk = pct(body.brk_share_pct, 'Brokerage sharing', limits.brk_max);
  const raw = Array.isArray(body.rates) ? body.rates : [];
  const payer = limits.paying_master.name || limits.paying_master.username;
  const rates = [];
  const seen = new Set();
  for (const r of raw) {
    const segment = normSegment(r && r.segment);
    const value = Number(r && r.value);
    if (!segment) throw fail(400, 'Each rate needs a segment');
    const category = up(r && r.category);
    const script = up(r && r.script);
    const scope = rateScope({ category, script });
    const label = scope === 'script' ? `${segment} ${script}` : scope === 'category' ? `${segment} ${category === 'INDEX' ? 'Index' : 'Stock'}` : segment;
    const key = rateKey({ segment, category: scope === 'category' ? category : null, script });
    if (seen.has(key)) throw fail(400, `${label} is listed twice`);
    seen.add(key);
    if (!Number.isFinite(value) || value < 0) throw fail(400, `Rate for ${label} must be 0 or more`);
    if (value === 0) continue;
    const lim = limits.segments.find((s) => s.segment === segment);
    if (!lim) throw fail(400, `${segment} is not enabled for ${limits.target.name || limits.target.username}`);
    const type = String((r && r.type) || lim.type).toUpperCase();
    if (type !== lim.type) throw fail(400, `${segment}: the rate must be ${lim.type === 'LOT WISE' ? '₹ per lot' : 'paisa per ₹100'} (the unit of the brokerage below)`);
    let max = lim.x_max;
    if (scope === 'category') {
      if (!lim.categories || !['INDEX', 'STOCK'].includes(category)) throw fail(400, `${segment} has no Index / Stock split`);
      max = lim.categories[category].x_max;
    } else if (scope === 'script') {
      if (!lim.scripts) throw fail(400, `${segment} has no per-script rates`);
      const sc = lim.scripts.find((x) => x.script === script);
      if (!sc) throw fail(400, `${label}: not a script this account trades`);
      max = sc.x_max;
    }
    if (value > max + 1e-9) {
      throw fail(400, `${label}: the broker can get at most ${max} ${lim.type === 'LOT WISE' ? '₹/lot' : 'paisa'} here (the markup over ${payer}'s own rate)`);
    }
    rates.push({ segment, type, value: r4(value), ...(scope === 'category' ? { category } : {}), ...(scope === 'script' ? { script } : {}) });
  }
  return { rates, pnl_share_pct: pnl, brk_share_pct: brk };
}

/**
 * Saves a link from `from` (default now). The target's open link, if any, ends
 * at that moment — a change is a new link, earlier weeks keep theirs.
 *   Model     BrokerClientLink | BrokerMasterLink
 *   key       { user_id } | { target_master_id }
 */
async function saveLink({ Model, key, extra, brokerId, settings, from, actor }) {
  const at = from ? new Date(from) : new Date();
  if (Number.isNaN(at.getTime())) throw fail(400, 'Invalid start date');
  const open = await Model.findOne({ ...key, to: null });
  if (open && open.from >= at) throw fail(409, 'This account already has a broker from that date or later — choose a later start date, or end that link first.');
  const later = await Model.findOne({ ...key, to: { $gt: at } }).lean();
  if (later && (!open || String(later._id) !== String(open._id))) throw fail(409, 'The start date overlaps an earlier broker period — choose a later start date.');
  if (open) {
    open.to = at;
    open.ended_by = actor.adminId || actor.masterId || null;
    await open.save();
  }
  const link = await Model.create({
    broker_id: brokerId,
    ...key,
    ...extra,
    ...settings,
    from: at,
    created_by: actor.adminId || null,
    created_by_master: actor.masterId || null,
  });
  return link;
}

async function addClientLink({ brokerId, userId, body, actor }) {
  const limits = await clientLimits(userId);
  const settings = body.view_only === true ? { rates: [], pnl_share_pct: 0, brk_share_pct: 0 } : cleanSettings(body, limits);
  return saveLink({ Model: BrokerClientLink, key: { user_id: userId }, extra: { master_id: limits.paying_master.id }, brokerId, settings, from: body.from, actor });
}

async function addMasterLink({ brokerId, masterId, body, actor }) {
  const limits = await subMasterLimits(masterId);
  const settings = body.view_only === true ? { rates: [], pnl_share_pct: 0, brk_share_pct: 0 } : cleanSettings(body, limits);
  return saveLink({ Model: BrokerMasterLink, key: { target_master_id: masterId }, extra: { parent_master_id: limits.paying_master.id }, brokerId, settings, from: body.from, actor });
}

module.exports = { clientLimits, subMasterLimits, cleanSettings, addClientLink, addMasterLink };
