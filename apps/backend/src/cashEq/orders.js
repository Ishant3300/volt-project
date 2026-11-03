'use strict';

// Equity orders (M4): place / modify / cancel, fills against the real NSE book with the
// low-volume rules (liquidity.js), day-end expiry. Own collections and own matcher only —
// the F&O order code, its BullMQ price queue and its matcher never see equity orders.
//
// Checks on every order:
//   • NSE cash session 09:15–15:30 Mon–Fri (and admin holiday list)
//   • whole shares; LIMIT price within the widest NSE band of the previous close
//   • MARKET only when the stock is really trading (illiquid guard)
//   • buy: per-script and total limits incl. open buy orders; sell: ≤ held − open sells
// Each stock is processed one order at a time (per-stock lock), oldest order first.

const { EqOrder, EqTrade, EqCounter, EqClient, EqInstrument, EqSettings } = require('./models');
const liquidity = require('./liquidity');
const book = require('./book');
const feed = require('./feed');
const { withTxn } = require('./txn');
const { istNow, marketOpen } = require('./engine');

class HttpError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

// ---------------------------------------------------------------------------
// Settings (admin-editable low-volume numbers), cached 30 s
// ---------------------------------------------------------------------------

let settingsCache = null;
async function getSettings() {
  if (settingsCache && Date.now() - settingsCache.at < 30000) return settingsCache.value;
  const doc = await EqSettings.findOne({ _id: 'liquidity' }).lean();
  const value = { ...liquidity.settingsWith(doc?.values || {}), holidays: Array.isArray(doc?.values?.holidays) ? doc.values.holidays : [] };
  settingsCache = { value, at: Date.now() };
  return value;
}
function clearSettingsCache() { settingsCache = null; }

// ---------------------------------------------------------------------------
// Per-stock lock and state
// ---------------------------------------------------------------------------

const locks = new Map(); // token -> promise chain
function withLock(token, fn) {
  const prev = locks.get(token) || Promise.resolve();
  const run = prev.then(fn, fn);
  const tail = run.catch(() => {});
  locks.set(token, tail);
  tail.then(() => { if (locks.get(token) === tail) locks.delete(token); });
  return run;
}

const stocks = new Map(); // token -> participation state (liquidity.newStockState)
async function stockState(token, date) {
  let st = stocks.get(token);
  if (!st || st.date !== date) {
    st = liquidity.newStockState(date);
    const today = await EqTrade.find({ instrument_token: token, date, deleted_at: null }).select('qty').lean();
    st.filled = today.reduce((a, t) => a + t.qty, 0);
    stocks.set(token, st);
  }
  return st;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function nowParts() {
  const at = new Date();
  const { date } = istNow(at);
  const ist = new Date(at.getTime() + 5.5 * 3600_000);
  return { date, time: ist.toISOString().slice(11, 19), at };
}

function marketClosedReason(s, at = new Date()) {
  if (!marketOpen(at)) return 'NSE cash market is closed (09:15–15:30, Monday to Friday)';
  if (s.holidays.includes(istNow(at).date)) return 'NSE holiday today';
  return null;
}

async function resolveClient(cash, clientId) {
  if (cash.role === 'cash_client') {
    if (clientId && String(clientId) !== cash.id) throw new HttpError(403, 'You can only place orders for yourself');
    return cash.doc;
  }
  if (!clientId) throw new HttpError(400, 'Choose the client');
  const client = await EqClient.findOne({ _id: clientId, deleted_at: null });
  if (!client) throw new HttpError(404, 'Equity client not found');
  if (cash.role === 'cash_master') {
    const { subtreeIds } = require('./controller')._internals;
    if (!(await subtreeIds(cash.id)).has(String(client.master_id))) throw new HttpError(403, 'Not your equity client');
  } else if (cash.role !== 'admin') {
    throw new HttpError(403, 'Not allowed');
  }
  if (cash.watchOnly) throw new HttpError(403, 'Watch-only admins cannot place orders');
  return client;
}

function notify(order) {
  const lps = feed.lps;
  if (!lps) return;
  const data = { type: 'cash_order', data: order };
  lps.broadcastToUser(String(order.client_id), data);
  if (order.placed_by?.id && String(order.placed_by.id) !== String(order.client_id)) lps.broadcastToUser(String(order.placed_by.id), data);
}

const actorOf = (cash) => ({ role: cash.role, id: cash.id, username: cash.username });

// ---------------------------------------------------------------------------
// Fills
// ---------------------------------------------------------------------------

/**
 * Record fills for one order in one transaction: a trade row per depth level taken,
 * the order's filled qty / average / status (only if nobody changed it meanwhile).
 * Returns the updated order, or null if the order was no longer open.
 */
async function recordFills(order, fills, st, { fromBudget }) {
  const { date, time } = nowParts();
  const qty = fills.reduce((a, f) => a + f.qty, 0);
  const updated = await withTxn(async (session) => {
    const opts = session ? { session } : {};
    const prevFilled = order.filled_qty;
    const newFilled = prevFilled + qty;
    const value = (order.filled_value || 0) + fills.reduce((a, f) => a + f.qty * f.price, 0);
    const avg = Math.round((value / newFilled) * 10000) / 10000;
    const done = newFilled >= order.qty;
    const res = await EqOrder.updateOne(
      { _id: order._id, status: 'OPEN', filled_qty: prevFilled },
      { $set: { filled_qty: newFilled, filled_value: value, avg_price: avg, status: done ? 'FILLED' : 'OPEN',
        reason: done ? '' : `Filled ${newFilled} of ${order.qty} — rest filling as the market trades`, ...(done ? { closed_at: new Date() } : {}) } },
      opts
    );
    if (!res.modifiedCount) return null;
    for (const f of fills) {
      const counter = await EqCounter.findOneAndUpdate({ _id: 'trade' }, { $inc: { seq: 1 } }, { upsert: true, new: true, ...opts });
      await EqTrade.create([{
        seq: counter.seq, client_id: order.client_id, order_id: order._id, instrument_token: order.instrument_token,
        tradingsymbol: order.tradingsymbol, mtf: order.mtf, side: order.side, qty: f.qty, price: f.price, date, add_time: `${date} ${time}`,
      }], opts);
    }
    await EqClient.updateOne({ _id: order.client_id, first_trade_at: null }, { $set: { first_trade_at: new Date() } }, opts);
    return EqOrder.findOne({ _id: order._id }).session(session || null).lean();
  });
  if (updated) {
    liquidity.take(st, fills, { fromBudget });
    notify(updated);
  }
  return updated;
}

// ---------------------------------------------------------------------------
// Place / modify / cancel
// ---------------------------------------------------------------------------

function parseOrderInput(body) {
  const side = String(body?.side || '').toUpperCase();
  const type = String(body?.order_type || 'MARKET').toUpperCase();
  const qty = Number(body?.qty);
  const token = Number(body?.instrument_token);
  const limit = body?.limit_price === undefined || body?.limit_price === null || body?.limit_price === '' ? null : Number(body.limit_price);
  if (!['B', 'S'].includes(side)) throw new HttpError(400, 'Side must be B (buy) or S (sell)');
  if (!['MARKET', 'LIMIT'].includes(type)) throw new HttpError(400, 'Order type must be MARKET or LIMIT');
  if (!Number.isInteger(qty) || qty < 1 || qty > 10_000_000) throw new HttpError(400, 'Quantity must be a whole number of shares');
  if (!Number.isInteger(token) || token <= 0) throw new HttpError(400, 'Choose a stock');
  if (type === 'LIMIT' && !(limit > 0)) throw new HttpError(400, 'Enter a limit price');
  return { side, type, qty, token, limit: type === 'LIMIT' ? Math.round(limit * 100) / 100 : null };
}

/** Tick-size check for a LIMIT price. */
function tickReason(price, tick) {
  if (!(tick > 0)) return null;
  const n = Math.round(price / tick);
  return Math.abs(n * tick - price) < 1e-6 ? null : `Limit price must be in steps of ${tick}`;
}

async function placeOrder(cash, body) {
  const input = parseOrderInput(body);
  const client = await resolveClient(cash, body?.client_id);
  if (client.status !== 'active') throw new HttpError(403, 'This equity account is not active');
  const inst = await EqInstrument.findOne({ instrument_token: input.token, is_active: true }).lean();
  if (!inst) throw new HttpError(404, 'Stock not found');
  const s = await getSettings();
  const { date } = nowParts();

  const base = {
    client_id: client._id, master_id: client.master_id, placed_by: actorOf(cash),
    instrument_token: inst.instrument_token, tradingsymbol: inst.tradingsymbol, mtf: !!inst.mtf,
    side: input.side, order_type: input.type, qty: input.qty, limit_price: input.limit, date,
  };
  const reject = async (reason) => {
    const o = await EqOrder.create({ ...base, status: 'REJECTED', reason, closed_at: new Date(), closed_by: actorOf(cash) });
    return { ok: false, order: o.toJSON(), message: reason };
  };

  const closed = marketClosedReason(s);
  if (closed) return reject(closed);
  const quote = feed.getQuotes([inst.instrument_token])[0];
  if (!quote || !(quote.last_price > 0)) return reject('No live price for this stock yet — open it in the watchlist first');
  if (input.type === 'MARKET') {
    const why = liquidity.illiquidReason(quote, input.side, s, Date.now() / 1000);
    if (why) return reject(why);
  } else {
    const why = liquidity.limitPriceReason(input.limit, quote, s) || tickReason(input.limit, inst.tick_size);
    if (why) return reject(why);
  }

  return withLock(inst.instrument_token, async () => {
    const trades = await book.loadTrades(client._id);
    const { holdings } = book.holdingsFrom(client, trades);
    const open = await book.openOrders(client._id);
    let reservePrice = null;
    if (input.side === 'S') {
      const can = book.sellable(holdings, open, inst.tradingsymbol);
      if (input.qty > can) return reject(can ? `You can sell at most ${can} ${inst.tradingsymbol} (no short selling)` : `No ${inst.tradingsymbol} shares to sell (no short selling)`);
    } else {
      reservePrice = input.type === 'LIMIT' ? input.limit : (quote.ask_price || quote.last_price);
      const lc = book.limitCheck(client, holdings, open, inst.tradingsymbol, input.qty * reservePrice);
      if (!lc.ok) return reject(lc.reason);
    }

    const created = await EqOrder.create({ ...base, status: 'OPEN', ref_price: quote.last_price, reserve_price: reservePrice });
    let order = created.toObject();
    openTokens.add(order.instrument_token);

    // Fill now what the real book allows: visible depth, within today's participation room.
    const st = await stockState(inst.instrument_token, date);
    liquidity.onVolume(st, quote, s);
    const r = liquidity.sweep({
      side: order.side, quote, wantQty: order.qty, capQty: liquidity.dayRoom(st, quote, s),
      limitPrice: order.limit_price, used: st.used, s,
    });
    if (r.qty > 0) order = (await recordFills(order, r.fills, st, { fromBudget: false })) || order;
    else if (order.order_type === 'MARKET') {
      await EqOrder.updateOne({ _id: order._id }, { $set: { reason: 'Waiting — fills as the market trades (low volume)' } });
      order.reason = 'Waiting — fills as the market trades (low volume)';
    }
    if (order.status === 'OPEN') feed.refresh().catch(() => {});
    notify(order);
    return { ok: true, order, message: order.status === 'FILLED' ? 'Filled' : order.filled_qty ? order.reason : 'Order placed' };
  });
}

async function loadOrderFor(cash, id) {
  const order = await EqOrder.findOne({ _id: id });
  if (!order) throw new HttpError(404, 'Order not found');
  await resolveClient(cash, cash.role === 'cash_client' ? undefined : order.client_id);
  if (cash.role === 'cash_client' && String(order.client_id) !== cash.id) throw new HttpError(404, 'Order not found');
  return order;
}

async function cancelOrder(cash, id) {
  const order = await loadOrderFor(cash, id);
  return withLock(order.instrument_token, async () => {
    const reason = order.filled_qty ? `Cancelled — ${order.filled_qty} of ${order.qty} filled` : 'Cancelled';
    const res = await EqOrder.updateOne({ _id: order._id, status: 'OPEN' }, { $set: { status: 'CANCELLED', reason, closed_at: new Date(), closed_by: actorOf(cash) } });
    if (!res.modifiedCount) throw new HttpError(400, 'Order is no longer open');
    const o = await EqOrder.findOne({ _id: order._id }).lean();
    notify(o);
    return o;
  });
}

/** Change an open LIMIT order's price and/or quantity (not below what's filled). */
async function modifyOrder(cash, id, body) {
  const order = await loadOrderFor(cash, id);
  if (order.order_type !== 'LIMIT') throw new HttpError(400, 'Only limit orders can be changed — cancel and place again');
  const s = await getSettings();
  const closed = marketClosedReason(s);
  if (closed) throw new HttpError(400, closed);
  return withLock(order.instrument_token, async () => {
    const cur = await EqOrder.findOne({ _id: order._id }).lean();
    if (cur.status !== 'OPEN') throw new HttpError(400, 'Order is no longer open');
    const qty = body?.qty === undefined ? cur.qty : Number(body.qty);
    const limit = body?.limit_price === undefined ? cur.limit_price : Math.round(Number(body.limit_price) * 100) / 100;
    if (!Number.isInteger(qty) || qty <= cur.filled_qty) throw new HttpError(400, `Quantity must be more than the ${cur.filled_qty} already filled`);
    const quote = feed.getQuotes([cur.instrument_token])[0];
    const inst = await EqInstrument.findOne({ instrument_token: cur.instrument_token }).lean();
    const why = liquidity.limitPriceReason(limit, quote, s) || tickReason(limit, inst?.tick_size);
    if (why) throw new HttpError(400, why);
    const client = await EqClient.findOne({ _id: cur.client_id }).lean();
    const trades = await book.loadTrades(client._id);
    const { holdings } = book.holdingsFrom(client, trades);
    const open = await book.openOrders(client._id, cur._id);
    if (cur.side === 'S') {
      const can = book.sellable(holdings, open, cur.tradingsymbol);
      if (qty - cur.filled_qty > can) throw new HttpError(400, `You can sell at most ${can + cur.filled_qty} in this order (no short selling)`);
    } else {
      const lc = book.limitCheck(client, holdings, open, cur.tradingsymbol, (qty - cur.filled_qty) * limit);
      if (!lc.ok) throw new HttpError(400, lc.reason);
    }
    const res = await EqOrder.updateOne({ _id: cur._id, status: 'OPEN', filled_qty: cur.filled_qty },
      { $set: { qty, limit_price: limit, reserve_price: cur.side === 'B' ? limit : null } });
    if (!res.modifiedCount) throw new HttpError(409, 'Order changed meanwhile — try again');
    let o = await EqOrder.findOne({ _id: cur._id }).lean();
    // The new price may meet the book now.
    if (quote) {
      const st = await stockState(o.instrument_token, o.date);
      liquidity.onVolume(st, quote, s);
      const r = liquidity.sweep({ side: o.side, quote, wantQty: o.qty - o.filled_qty, capQty: liquidity.dayRoom(st, quote, s), limitPrice: o.limit_price, used: st.used, s });
      if (r.qty > 0) o = (await recordFills(o, r.fills, st, { fromBudget: false })) || o;
    }
    notify(o);
    return o;
  });
}

// ---------------------------------------------------------------------------
// Matching on ticks (pending remainders)
// ---------------------------------------------------------------------------

const busy = new Set();
const again = new Set();

/** Feed listener: process stocks that have open orders, at most one run at a time per stock. */
function onTicks(ticks) {
  for (const t of ticks) {
    const token = t.instrument_token;
    if (!openTokens.has(token)) continue;
    if (busy.has(token)) { again.add(token); continue; }
    busy.add(token);
    withLock(token, () => processStock(token))
      .catch((e) => console.log(`⚠️ [cashEq orders] ${token}: ${e.message}`))
      .finally(() => {
        busy.delete(token);
        if (again.delete(token)) onTicks([{ instrument_token: token }]);
      });
  }
}

const openTokens = new Set();
async function refreshOpenTokens() {
  const tokens = await EqOrder.distinct('instrument_token', { status: 'OPEN' });
  openTokens.clear();
  tokens.forEach((t) => openTokens.add(Number(t)));
  return [...openTokens];
}

async function processStock(token) {
  const s = await getSettings();
  const { date } = nowParts();
  const orders = await EqOrder.find({ instrument_token: token, status: 'OPEN', date }).sort({ createdAt: 1 }).lean();
  if (!orders.length) {
    openTokens.delete(token);
    stocks.delete(token);
    return 0;
  }
  if (marketClosedReason(s)) return 0;
  const quote = feed.getQuotes([token])[0];
  if (!quote) return 0;
  const st = await stockState(token, date);
  liquidity.onVolume(st, quote, s);
  // Paced: open orders take their volume share at most every fill_interval_sec, so a thin
  // stock gives a few bigger fills instead of a 1-share trade on every tick.
  if (Date.now() - st.lastFillAt < s.fill_interval_sec * 1000) return 0;
  let filled = 0;
  for (const o of orders) {
    const cap = Math.min(Math.floor(st.budget), liquidity.dayRoom(st, quote, s));
    if (cap <= 0) break;
    const r = liquidity.sweep({ side: o.side, quote, wantQty: o.qty - o.filled_qty, capQty: cap, limitPrice: o.limit_price, used: st.used, s });
    if (!r.qty) continue;
    const u = await recordFills(o, r.fills, st, { fromBudget: true });
    if (u) filled += r.qty;
  }
  if (filled) st.lastFillAt = Date.now();
  return filled;
}

/** Day orders: anything still open at the close (or from an earlier day) expires. */
async function expireOpen(beforeOrOn) {
  const open = await EqOrder.find({ status: 'OPEN' }).lean();
  let n = 0;
  for (const o of open) {
    if (o.date > beforeOrOn) continue;
    await withLock(o.instrument_token, async () => {
      const reason = o.filled_qty ? `Filled ${o.filled_qty} of ${o.qty}; rest expired at the close` : 'Not filled by the close (day order)';
      const res = await EqOrder.updateOne({ _id: o._id, status: 'OPEN' }, { $set: { status: 'EXPIRED', reason, closed_at: new Date(), closed_by: { role: 'system', username: 'day end' } } });
      if (res.modifiedCount) { n++; notify({ ...o, status: 'EXPIRED', reason }); }
    });
  }
  await refreshOpenTokens();
  return n;
}

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

/** Client ids the caller may see (null = all). */
async function visibleClientIds(cash) {
  if (cash.role === 'admin') return null;
  if (cash.role === 'cash_client') return [cash.id];
  const { subtreeIds } = require('./controller')._internals;
  const masters = [...(await subtreeIds(cash.id))];
  const clients = await EqClient.find({ master_id: { $in: masters } }).select('_id').lean();
  return clients.map((c) => String(c._id));
}

async function listOrders(cash, q = {}) {
  const ids = await visibleClientIds(cash);
  const filter = {};
  if (q.client_id) {
    if (ids && !ids.includes(String(q.client_id))) throw new HttpError(403, 'Not your equity client');
    filter.client_id = q.client_id;
  } else if (ids) filter.client_id = { $in: ids };
  if (q.status) filter.status = String(q.status).toUpperCase();
  if (q.date) filter.date = String(q.date);
  return EqOrder.find(filter).sort({ createdAt: -1 }).limit(Math.min(Number(q.limit) || 200, 1000)).lean();
}

async function listTrades(cash, q = {}) {
  const ids = await visibleClientIds(cash);
  const filter = { deleted_at: null };
  if (q.client_id) {
    if (ids && !ids.includes(String(q.client_id))) throw new HttpError(403, 'Not your equity client');
    filter.client_id = q.client_id;
  } else if (ids) filter.client_id = { $in: ids };
  if (q.date) filter.date = String(q.date);
  return EqTrade.find(filter).sort({ seq: -1 }).limit(Math.min(Number(q.limit) || 500, 2000)).lean();
}

/** What the order ticket shows before placing: holdings, sellable, limit room, liquidity. */
async function preview(cash, q) {
  const client = await resolveClient(cash, q.client_id);
  const token = Number(q.instrument_token);
  const inst = await EqInstrument.findOne({ instrument_token: token }).lean();
  if (!inst) throw new HttpError(404, 'Stock not found');
  const s = await getSettings();
  const trades = await book.loadTrades(client._id);
  const { holdings } = book.holdingsFrom(client, trades);
  const open = await book.openOrders(client._id);
  const quote = feed.getQuotes([token])[0] || null;
  const lc = book.limitCheck(client, holdings, open, inst.tradingsymbol, 0);
  const now = Date.now() / 1000;
  return {
    client: { _id: client._id, name: client.name, username: client.username },
    stock: { instrument_token: token, tradingsymbol: inst.tradingsymbol, name: inst.name, mtf: !!inst.mtf, tick_size: inst.tick_size },
    held: holdings.get(inst.tradingsymbol)?.qty || 0,
    sellable: book.sellable(holdings, open, inst.tradingsymbol),
    limits: { per_script: lc.per_script, total: lc.total },
    rates: inst.mtf
      ? { brokerage: client.brokerage_mtf, interest_pct: client.interest_mtf_pct, category: 'approved' }
      : { brokerage: client.brokerage_non, interest_pct: client.interest_non_pct, category: 'non-approved' },
    market: {
      closed: marketClosedReason(s),
      market_buy: quote ? liquidity.illiquidReason(quote, 'B', s, now) : 'No price yet',
      market_sell: quote ? liquidity.illiquidReason(quote, 'S', s, now) : 'No price yet',
    },
    quote,
  };
}

module.exports = {
  HttpError, getSettings, clearSettingsCache, placeOrder, modifyOrder, cancelOrder, onTicks, processStock,
  refreshOpenTokens, expireOpen, listOrders, listTrades, preview, openTokens, _stocks: stocks,
};
