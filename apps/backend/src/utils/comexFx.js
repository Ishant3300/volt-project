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

/** Current { base, spread } or null when admin has not set one. */
async function loadComexFx(session = null) {
  const ComexRate = require('../models/ComexRate');
  const q = ComexRate.findOne({ key: 'comex' }).select('base spread');
  if (session) q.session(session);
  const doc = await q.lean();
  if (!doc || !(Number(doc.base) > 0)) return null;
  return { base: Number(doc.base), spread: Number(doc.spread) || 0 };
}

const MONEY_FIELDS = ['realized_pnl', 'settlement_pnl', 'total_pnl', 'brokerage', 'net_pnl'];

/**
 * Settlement: convert every client's COMEX snapshots to rupees in place, one
 * rate per client chosen from the sign of that client's COMEX net. The
 * dollar figures are kept as usd_* with the rate used; fills stay in $.
 * Throws when a client has COMEX amounts but no rate is set — booking dollars
 * as rupees would be silently wrong.
 * @returns {{ users: number, rates: Object<string, number> }}
 */
function convertComexSnapshots(snapshots, fx) {
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
    const p = periods.get(key) || { period_key: key, settlement_date: s.settlement_date, fx_rate: s.fx_rate, usd_pnl: 0, usd_brokerage: 0, inr_pnl: 0, inr_brokerage: 0 };
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
    fx: fx ? { base: fx.base, spread: fx.spread, debit_rate: fx.base + fx.spread, credit_rate: fx.base - fx.spread } : null,
    inr_pnl: complete ? r2(inrPnl) : null,
    inr_brokerage: complete ? r2(inrBrk) : null,
    inr_net: complete ? r2(inrPnl - inrBrk) : null,
  };
}

module.exports = { COMEX_EXCHANGE, isComex, rateForNet, loadComexFx, convertComexSnapshots, comexBillBlock };
