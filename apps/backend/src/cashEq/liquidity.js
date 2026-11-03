'use strict';

// Equity low-volume fill rules — pure functions (no database, no feed).
//
// We have no order book of our own: equity orders fill against the REAL NSE book
// (Kite's 5-level depth and the exchange's traded volume), the way an exchange would
// treat an aggressive order in a thin stock:
//   • depth sweep   — a fill only takes the quantity actually showing on the other side,
//                     level by level, each at its own price (real market impact)
//   • participation — all our clients together get at most a share of the volume the
//                     exchange really trades (per stock, platform-wide), so a big order in
//                     a thin stock fills step by step as the market trades
//   • illiquid guard— MARKET orders only when the stock is actually trading (recent trade,
//                     tight spread, depth on the other side); otherwise LIMIT only
//   • price collar  — no fill too far from the last traded price

const DEFAULTS = Object.freeze({
  participation_pct: 10, // % of exchange volume traded after the order, shared by all our open orders
  day_participation_pct: 10, // % of the day's exchange volume, all our fills in the stock together
  depth_levels: 5,
  stale_minutes: 5, // MARKET orders need a trade within this many minutes
  max_spread_pct: 1, // MARKET orders need (ask − bid) ≤ this % of the price
  collar_pct: 2, // no fill more than this % away from the LTP
  limit_band_pct: 20, // LIMIT price must be within this % of the previous close (widest NSE band)
});

const round2 = (n) => Math.round(n * 100) / 100;

function settingsWith(over = {}) {
  const out = { ...DEFAULTS };
  for (const k of Object.keys(DEFAULTS)) {
    const v = Number(over[k]);
    if (Number.isFinite(v) && v >= 0) out[k] = v;
  }
  return out;
}

/** Validate an admin change to the settings; returns error messages. */
function checkSettings(s) {
  const errs = [];
  const pct = (k, max) => { if (!(s[k] > 0 && s[k] <= max)) errs.push(`${k.replace(/_/g, ' ')} must be above 0 and at most ${max}`); };
  pct('participation_pct', 100);
  pct('day_participation_pct', 100);
  pct('max_spread_pct', 20);
  pct('collar_pct', 20);
  pct('limit_band_pct', 50);
  if (!(Number.isInteger(s.depth_levels) && s.depth_levels >= 1 && s.depth_levels <= 5)) errs.push('depth levels must be 1 to 5');
  if (!(s.stale_minutes >= 1 && s.stale_minutes <= 120)) errs.push('stale minutes must be 1 to 120');
  return errs;
}

/**
 * Why a MARKET order can't be accepted right now (LIMIT only), or null.
 * `nowSec` = current time in epoch seconds.
 */
function illiquidReason(quote, side, s, nowSec) {
  if (!quote || !(quote.last_price > 0)) return 'No price for this stock yet';
  const levels = side === 'B' ? quote.depth?.sell : quote.depth?.buy;
  if (!levels || !levels.length) return `Nobody is ${side === 'B' ? 'selling' : 'buying'} right now — use a limit order`;
  if (!quote.last_trade_ts || nowSec - quote.last_trade_ts > s.stale_minutes * 60) {
    return `No trade in the last ${s.stale_minutes} minutes (low volume) — use a limit order`;
  }
  const bid = quote.bid_price;
  const ask = quote.ask_price;
  if (bid > 0 && ask > 0 && ((ask - bid) / quote.last_price) * 100 > s.max_spread_pct) {
    return `Buy/sell gap is wider than ${s.max_spread_pct} % (low volume) — use a limit order`;
  }
  return null;
}

/** LIMIT price sanity: within the widest NSE band of the previous close. */
function limitPriceReason(limitPrice, quote, s) {
  if (!(limitPrice > 0)) return 'Enter a limit price';
  const ref = quote?.close > 0 ? quote.close : quote?.last_price;
  if (ref > 0 && Math.abs(limitPrice - ref) / ref * 100 > s.limit_band_pct) {
    return `Limit price is more than ${s.limit_band_pct} % away from the previous close (${ref})`;
  }
  return null;
}

/**
 * Sweep the other side of the book for one order.
 *   side        'B' takes sell levels (lowest first), 'S' takes buy levels (highest first)
 *   wantQty     quantity still to fill
 *   capQty      most this order may take now (participation / day cap), whole shares
 *   limitPrice  null for MARKET
 *   used        Map(levelPrice → qty already taken from this depth snapshot by our
 *               other orders) — the real book doesn't shrink from simulated fills, so
 *               two orders can't both take the same displayed quantity
 * Returns { fills: [{ qty, price }], qty, avgPrice } — fills already within the collar.
 */
function sweep({ side, quote, wantQty, capQty, limitPrice = null, used = new Map(), s }) {
  const levels = ((side === 'B' ? quote?.depth?.sell : quote?.depth?.buy) || []).slice(0, s.depth_levels);
  const ltp = quote?.last_price;
  let left = Math.min(Math.floor(wantQty), Math.floor(capQty));
  const fills = [];
  if (!(left > 0) || !(ltp > 0)) return { fills, qty: 0, avgPrice: null };
  const collar = s.collar_pct / 100;
  for (const lvl of levels) {
    if (left <= 0) break;
    const price = lvl.price;
    if (limitPrice != null && (side === 'B' ? price > limitPrice : price < limitPrice)) break; // levels are sorted
    if (side === 'B' ? price > ltp * (1 + collar) : price < ltp * (1 - collar)) break;
    const free = lvl.qty - (used.get(price) || 0);
    const take = Math.min(left, free);
    if (take <= 0) continue;
    fills.push({ qty: take, price });
    left -= take;
  }
  const qty = fills.reduce((a, f) => a + f.qty, 0);
  const avgPrice = qty ? round2(fills.reduce((a, f) => a + f.qty * f.price, 0) / qty) : null;
  return { fills, qty, avgPrice };
}

/**
 * Per-stock participation state, platform-wide (one object per stock per day).
 *   volume     exchange day volume when we last looked
 *   budget     shares our open orders may still take from volume traded since they came in
 *   filled     shares all our clients filled in this stock today
 */
function newStockState(date) {
  return { date, volume: null, budget: 0, filled: 0, snapshot: null, used: new Map() };
}

/** A new tick: grow the budget by the participation share of the new exchange volume. */
function onVolume(state, quote, s) {
  if (state.snapshot !== quote) { state.snapshot = quote; state.used = new Map(); }
  const v = Number(quote.volume);
  if (!Number.isFinite(v)) return 0;
  if (state.volume == null || v < state.volume) { state.volume = v; return 0; }
  const delta = v - state.volume;
  state.volume = v;
  state.budget += (delta * s.participation_pct) / 100;
  return delta;
}

/** Shares all our clients may still fill in this stock today. */
function dayRoom(state, quote, s) {
  const v = Number(quote?.volume) || 0;
  return Math.max(0, Math.floor((v * s.day_participation_pct) / 100) - state.filled);
}

/** Record fills against the state (budget, day total, depth used). */
function take(state, fills, { fromBudget }) {
  let q = 0;
  for (const f of fills) {
    state.used.set(f.price, (state.used.get(f.price) || 0) + f.qty);
    q += f.qty;
  }
  state.filled += q;
  if (fromBudget) state.budget = Math.max(0, state.budget - q);
  return q;
}

module.exports = {
  DEFAULTS, settingsWith, checkSettings, illiquidReason, limitPriceReason, sweep, newStockState, onVolume, dayRoom, take,
};
