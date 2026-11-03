'use strict';

// A client's equity book — trades in engine shape, brokerage per category, holdings and
// limit use. Everything goes through engine.js (the Trade Terminal port) so the numbers
// here are the same ones the statement and month-end will use.

const engine = require('./engine');
const rules = require('./rules');
const { EqTrade, EqOrder } = require('./models');

/** eqcash_trades row → Trade Terminal trade. */
function toEngineTrade(t) {
  return {
    id: t.seq, ot: 'O', date: t.date, valan: '', segment: 'NSEEQ', script: t.tradingsymbol, option: '', strike: 0,
    tradeType: 'NRM', side: t.side, lot: t.qty, qty: t.qty, rate: t.price, clientCode: String(t.client_id),
    user: '', ip: '', addTime: t.add_time, mtf: !!t.mtf, token: t.instrument_token,
  };
}

/**
 * Brokerage and net rates. Each trade uses its category's rate set (approved / non-approved),
 * fixed when it was traded. Intraday matching is per script and day, and a script's
 * category is the same all day (the list syncs before the market opens).
 */
function calcsFor(client, trades) {
  const out = new Map();
  for (const set of ['mtf', 'non']) {
    const mine = trades.filter((t) => (set === 'mtf') === !!t.mtf);
    if (!mine.length) continue;
    for (const [id, c] of engine.computeTradeCalcs(mine, [rules.toSlab(client, set)])) out.set(id, c);
  }
  return out;
}

async function loadTrades(clientId) {
  const rows = await EqTrade.find({ client_id: clientId, deleted_at: null }).sort({ seq: 1 }).lean();
  return rows.map(toEngineTrade);
}

/**
 * Open holdings per script: qty and margin value (net buy cost of the open lots — the
 * same "margin used" the interest is charged on). Month-end carry (M6) will revalue
 * carried lots at the bhav close.
 */
function holdingsFrom(client, trades) {
  const calcs = calcsFor(client, trades);
  const { portions } = engine.buildEquityLots(trades, calcs);
  const by = new Map();
  for (const p of portions) {
    if (p.closeDate !== null) continue;
    const h = by.get(p.script) || { script: p.script, qty: 0, value: 0 };
    h.qty += p.qty;
    h.value += p.qty * p.netBuyRate;
    by.set(p.script, h);
  }
  return { holdings: by, calcs };
}

/** Open orders of a client (optionally leaving one out, e.g. the order being modified). */
async function openOrders(clientId, exceptId = null) {
  const rows = await EqOrder.find({ client_id: clientId, status: 'OPEN' }).lean();
  return rows.filter((o) => String(o._id) !== String(exceptId));
}

/**
 * Limit use for a new buy of `value` in `script`: holdings value + open buy orders
 * (their unfilled qty at the reserve price) + this order, per script and in total.
 */
function limitCheck(client, holdings, open, script, value) {
  const pending = (filter) => open.filter((o) => o.side === 'B' && filter(o))
    .reduce((a, o) => a + (o.qty - o.filled_qty) * (o.reserve_price || 0), 0);
  let total = 0;
  for (const h of holdings.values()) total += h.value;
  const inScript = (holdings.get(script)?.value || 0);
  const scriptUsed = inScript + pending((o) => o.tradingsymbol === script);
  const totalUsed = total + pending(() => true);
  const out = {
    per_script: { limit: client.per_script_limit, used: scriptUsed, room: Math.max(0, client.per_script_limit - scriptUsed) },
    total: { limit: client.total_limit, used: totalUsed, room: Math.max(0, client.total_limit - totalUsed) },
    ok: true,
    reason: '',
  };
  if (scriptUsed + value > client.per_script_limit + 0.005) {
    out.ok = false;
    out.reason = `Above the per-script limit for ${script}: limit ${rules.lakh(client.per_script_limit)}, used ${rules.lakh(Math.round(scriptUsed))}, room ${rules.lakh(Math.round(out.per_script.room))}`;
  } else if (totalUsed + value > client.total_limit + 0.005) {
    out.ok = false;
    out.reason = `Above the total limit: limit ${rules.lakh(client.total_limit)}, used ${rules.lakh(Math.round(totalUsed))}, room ${rules.lakh(Math.round(out.total.room))}`;
  }
  return out;
}

/** Shares the client can still sell in a script: held minus open sell orders (no short selling). */
function sellable(holdings, open, script) {
  const held = holdings.get(script)?.qty || 0;
  const pendingSells = open.filter((o) => o.side === 'S' && o.tradingsymbol === script).reduce((a, o) => a + o.qty - o.filled_qty, 0);
  return Math.max(0, held - pendingSells);
}

module.exports = { toEngineTrade, calcsFor, loadTrades, holdingsFrom, openOrders, limitCheck, sellable };
