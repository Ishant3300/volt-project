'use strict';

/**
 * COMEX in dollars, billed in rupees (25 Oct 2026, the user's rules):
 *  - COMEX prices, trades, brokerage, margin and wallets are all in US
 *    dollars; nothing in the trading flow converts.
 *  - Only the weekly settlement (the bill) converts, per client: the
 *    client's COMEX net for the week (P&L − brokerage, in $) is converted at
 *      base + spread when negative (debit bill, e.g. 88 + 1 = 89)
 *      base − spread when positive (credit bill, e.g. 88 − 1 = 87).
 *    The rupee amount then flows through the ledger and sharing like any
 *    other amount; no separate spread entry.
 *  - Admin sets base and spread (models/ComexRate.js); a change applies to
 *    the next settlement, i.e. to the current week.
 *  - Per account (1 Nov 2026): a master (key 'master:<id>') and a client (key
 *    'user:<id>') may have their own base and spread, set where COMEX is
 *    ticked. An account without one inherits the nearest master above it that
 *    has one, else admin's default. A master can't give an account below
 *    him a lower base or spread than his own. The settlement converts each
 *    CLIENT at that client's rate; the ledger and sharing are unchanged.
 */

const COMEX_EXCHANGE = 'COMEX';

function isComex(exchangeOrSegment) {
  const s = String(exchangeOrSegment || '').toUpperCase();
  return s === COMEX_EXCHANGE || s === 'COMEX-FUT';
}

/** The rate for a client's COMEX net (in $): debit → base + spread, credit → base − spread. */
function rateForNet(netUsd, fx) {
  if (!fx) return null;
  if (netUsd < 0) return fx.base + fx.spread;
  if (netUsd > 0) return fx.base - fx.spread;
  return fx.base;
}

const DEFAULT_KEY = 'comex';
const clientKey = (userId) => `user:${userId}`;
const masterKey = (masterId) => `master:${masterId}`;
const uniqIds = (ids) => [...new Set((ids || []).filter(Boolean).map(String))];

/** { base, spread } from a ComexRate doc, or null (missing, removed, no base). */
function fxOf(doc) {
  if (!doc || doc.active === false || !(Number(doc.base) > 0)) return null;
  return { base: Number(doc.base), spread: Number(doc.spread) || 0 };
}

/**
 * Rate lookup for a set of clients (and masters): returns
 *   fxFor(userId)            → the client's own rate ('client'), else the
 *                              nearest master above with one ('master'), else
 *                              admin's default ('default'), else null;
 *   fxFor.forMaster(masterId) → the same from that master upwards.
 */
async function loadComexFxResolver(userIds = [], session = null, { masterIds = [] } = {}) {
  const ComexRate = require('../models/ComexRate');
  const User = require('../models/User');
  const Master = require('../models/Master');
  const withSession = (q) => (session ? q.session(session) : q);
  const ids = uniqIds(userIds);

  const users = ids.length ? await withSession(User.find({ _id: { $in: ids } }).select('_id master_id')).lean() : [];
  const parentOfUser = new Map(users.map((u) => [String(u._id), u.master_id ? String(u.master_id) : null]));
  const masters = await withSession(Master.find({}).select('_id master_id')).lean();
  const parentOfMaster = new Map(masters.map((m) => [String(m._id), m.master_id ? String(m.master_id) : null]));
  const chainOf = (masterId) => {
    const out = [];
    const seen = new Set();
    for (let cur = masterId ? String(masterId) : null; cur && !seen.has(cur); cur = parentOfMaster.get(cur) || null) {
      seen.add(cur);
      out.push(cur);
    }
    return out;
  };

  const keys = new Set([DEFAULT_KEY]);
  for (const id of ids) {
    keys.add(clientKey(id));
    for (const m of chainOf(parentOfUser.get(id))) keys.add(masterKey(m));
  }
  for (const id of uniqIds(masterIds)) for (const m of chainOf(id)) keys.add(masterKey(m));
  const docs = await withSession(ComexRate.find({ key: { $in: [...keys] } }).select('key base spread active')).lean();
  const byKey = new Map(docs.map((d) => [d.key, d]));
  const def = fxOf(byKey.get(DEFAULT_KEY));

  const forMaster = (masterId) => {
    for (const m of chainOf(masterId)) {
      const own = fxOf(byKey.get(masterKey(m)));
      if (own) return { ...own, source: 'master', master_id: m };
    }
    return def ? { ...def, source: 'default' } : null;
  };
  const fxFor = (uid) => {
    const own = uid ? fxOf(byKey.get(clientKey(uid))) : null;
    if (own) return { ...own, source: 'client' };
    return forMaster(uid ? parentOfUser.get(String(uid)) : null);
  };
  fxFor.forMaster = forMaster;
  return fxFor;
}

/**
 * Current { base, spread, source } — for one client (own, else inherited, else
 * the default) or, with no userId, admin's default; null when none is set.
 */
async function loadComexFx(session = null, userId = null) {
  const fxFor = await loadComexFxResolver(userId ? [userId] : [], session);
  return fxFor(userId);
}

/** A master's rate: his own, else inherited from above, else admin's default. */
async function loadMasterComexFx(masterId, session = null) {
  const fxFor = await loadComexFxResolver([], session, { masterIds: [masterId] });
  return fxFor.forMaster(masterId);
}

/**
 * The limit a master must respect (1 Nov 2026): neither base nor spread below
 * `floor` (the rate of the master directly above the account). Returns an
 * error message, or null when fine / no floor.
 */
function belowFloorMessage(rate, floor) {
  if (!floor) return null;
  const eps = 1e-9;
  if (rate.base + eps < floor.base || rate.spread + eps < floor.spread) {
    return `Can't be below the rate above this account — dollar rate at least ${floor.base}, spread at least ${floor.spread}`;
  }
  return null;
}

/**
 * One rate for a view that covers several clients (a master's combined
 * report): theirs when every client has the same rate; otherwise admin's
 * default flagged `mixed` — such a view pools all clients' COMEX per script,
 * so it can only estimate. Each client's own bill and settlement are exact.
 */
async function loadComexFxForUsers(userIds = [], session = null) {
  const ids = [...new Set((userIds || []).filter(Boolean).map(String))];
  const fxFor = await loadComexFxResolver(ids, session);
  if (ids.length === 0) return fxFor(null);
  const list = ids.map(fxFor);
  const first = list[0];
  const same = list.every((f) => (f === null && first === null) || (f && first && f.base === first.base && f.spread === first.spread));
  if (same) return first;
  const def = fxFor(null);
  return def ? { ...def, mixed: true } : null;
}

/**
 * GET /trade/report's rate: one client's own rate when the report is for one
 * client, else loadComexFxForUsers over the clients with COMEX in it.
 */
async function loadComexFxForReport(userScope, trades, snapshots) {
  const mongoose = require('mongoose');
  const scoped = userScope && userScope.user_id;
  if (scoped && mongoose.isValidObjectId(scoped)) return loadComexFxForUsers([scoped]);
  const ids = [...(trades || []), ...(snapshots || [])].filter((t) => isComex(t.exchange)).map((t) => t.user_id);
  return loadComexFxForUsers(ids);
}

const MONEY_FIELDS = ['realized_pnl', 'settlement_pnl', 'total_pnl', 'brokerage', 'net_pnl'];

/**
 * Settlement: convert every client's COMEX snapshots to rupees in place, one
 * rate per client chosen from the sign of that client's COMEX net. The
 * dollar figures are kept as usd_* with the rate used; fills stay in $.
 * Throws when a client has COMEX amounts but no rate is set — booking dollars
 * as rupees would be silently wrong. `fx` is one { base, spread } for all, or
 * a uid => fx lookup (loadComexFxResolver: each client's own rate).
 * @returns {{ users: number, rates: Object<string, number> }}
 */
function convertComexSnapshots(snapshots, fxOrLookup) {
  const fxFor = typeof fxOrLookup === 'function' ? fxOrLookup : () => fxOrLookup;
  const byUser = new Map();
  for (const s of snapshots) {
    if (!isComex(s.exchange)) continue;
    const uid = s.user_id.toString();
    if (!byUser.has(uid)) byUser.set(uid, []);
    byUser.get(uid).push(s);
  }
  const rates = {};
  for (const [uid, list] of byUser) {
    const netUsd = list.reduce((sum, s) => sum + (Number(s.net_pnl) || 0), 0);
    const hasAmounts = list.some((s) => MONEY_FIELDS.some((f) => Math.abs(Number(s[f]) || 0) >= 0.005));
    const fx = fxFor(uid);
    if (!fx) {
      if (!hasAmounts) continue;
      const error = new Error('COMEX USD/INR rate is not set — admin must set it before COMEX can be settled');
      error.code = 'COMEX_RATE_MISSING';
      error.details = { user_id: uid };
      throw error;
    }
    const rate = rateForNet(netUsd, fx);
    rates[uid] = rate;
    for (const s of list) {
      for (const f of MONEY_FIELDS) {
        s[`usd_${f}`] = Number(s[f]) || 0;
        s[f] = (Number(s[f]) || 0) * rate;
      }
      s.currency = 'USD';
      s.fx_base = fx.base;
      s.fx_spread = fx.spread;
      s.fx_rate = rate;
    }
  }
  return { users: Object.keys(rates).length, rates };
}

/**
 * A bill's COMEX block (GET /trade/report). `instruments` are the bill's
 * per-script rows (P&L / brokerage in $ for COMEX — recomputed from $ prices);
 * `snapshots` the SettlementHistory rows the bill window touches. Settled
 * weeks use the rupee amounts their settlement booked; anything not yet
 * settled is an ESTIMATE at today's rate (debit/credit by its own sign).
 * Returns null when the bill has no COMEX.
 */
function comexBillBlock(instruments, snapshots, fx) {
  const rows = (instruments || []).filter((i) => isComex(i.exchange));
  if (rows.length === 0) return null;
  const r2 = (n) => Math.round(n * 100) / 100;
  const usdPnl = rows.reduce((t, i) => t + (Number(i.pnl) || 0), 0);
  const usdBrk = rows.reduce((t, i) => t + (Number(i.brokerage) || 0), 0);

  const periods = new Map();
  for (const s of snapshots || []) {
    if (!isComex(s.exchange) || s.fx_rate == null) continue;
    const key = s.settlement_period_key || String(s.settlement_run_id);
    const p = periods.get(key) || { period_key: key, settlement_date: s.settlement_date, settlement_trading_date: s.settlement_trading_date || null, fx_rate: s.fx_rate, usd_pnl: 0, usd_brokerage: 0, inr_pnl: 0, inr_brokerage: 0 };
    p.usd_pnl += Number(s.usd_total_pnl) || 0;
    p.usd_brokerage += Number(s.usd_brokerage) || 0;
    p.inr_pnl += Number(s.total_pnl) || 0;
    p.inr_brokerage += Number(s.brokerage) || 0;
    periods.set(key, p);
  }
  const settled = [...periods.values()].map((p) => ({
    ...p,
    usd_net: r2(p.usd_pnl - p.usd_brokerage),
    inr_net: r2(p.inr_pnl - p.inr_brokerage),
  }));
  const setUsdPnl = settled.reduce((t, p) => t + p.usd_pnl, 0);
  const setUsdBrk = settled.reduce((t, p) => t + p.usd_brokerage, 0);

  const remPnl = usdPnl - setUsdPnl;
  const remBrk = usdBrk - setUsdBrk;
  let estimate = null;
  let inrPnl = settled.reduce((t, p) => t + p.inr_pnl, 0);
  let inrBrk = settled.reduce((t, p) => t + p.inr_brokerage, 0);
  let complete = true;
  if (Math.abs(remPnl) >= 0.005 || Math.abs(remBrk) >= 0.005) {
    const remNet = remPnl - remBrk;
    const rate = rateForNet(remNet, fx);
    estimate = { usd_pnl: r2(remPnl), usd_brokerage: r2(remBrk), usd_net: r2(remNet), fx_rate: rate, inr_net: rate == null ? null : r2(remNet * rate) };
    if (rate == null) complete = false;
    else { inrPnl += remPnl * rate; inrBrk += remBrk * rate; }
  }
  return {
    currency: 'USD',
    usd_pnl: r2(usdPnl),
    usd_brokerage: r2(usdBrk),
    usd_net: r2(usdPnl - usdBrk),
    settled,
    estimate,
    fx: fx ? { base: fx.base, spread: fx.spread, debit_rate: fx.base + fx.spread, credit_rate: fx.base - fx.spread, source: fx.source || null, mixed: !!fx.mixed } : null,
    inr_pnl: complete ? r2(inrPnl) : null,
    inr_brokerage: complete ? r2(inrBrk) : null,
    inr_net: complete ? r2(inrPnl - inrBrk) : null,
  };
}

module.exports = {
  COMEX_EXCHANGE,
  isComex,
  rateForNet,
  clientKey,
  masterKey,
  belowFloorMessage,
  loadComexFx,
  loadMasterComexFx,
  loadComexFxResolver,
  loadComexFxForUsers,
  loadComexFxForReport,
  convertComexSnapshots,
  comexBillBlock,
};
