'use strict';

/**
 * Practice mode — simulated prices (docs/practice-trading.md).
 *
 * Pure and deterministic: the price of a contract at any moment depends only
 * on its anchor {price, slot} and the clock, so every process, restart, chart,
 * fill and settlement agrees without storing ticks.
 *
 *   slot      = 30-minute step of the IST clock
 *   price(s)  = anchor.price × exp(σ · Σ z(token, i)),  i ∈ (anchor.slot, s]
 *               counting only slots inside the contract's market session
 *   z         = seeded standard normal from (token, i)
 *
 * Not real market prices — never derived from any feed after the first anchor.
 */

const IST_MS = 5.5 * 3600 * 1000;
const DEFAULT_STEP_MIN = 30;

// Volatility per 30-minute step (log-return σ), by kind of contract.
const SIGMA = {
  index_fut: 0.0035,
  stock_fut: 0.006,
  option: 0.04,
  mcx: 0.005,
  global: 0.004,
};

function stepMs(stepMin = DEFAULT_STEP_MIN) {
  return stepMin * 60 * 1000;
}

/** 30-minute slot number of an instant, aligned to the IST clock. */
function slotOf(ms, stepMin = DEFAULT_STEP_MIN) {
  return Math.floor((ms + IST_MS) / stepMs(stepMin));
}

/** UTC ms at which a slot starts. */
function slotStart(slot, stepMin = DEFAULT_STEP_MIN) {
  return slot * stepMs(stepMin) - IST_MS;
}

// FNV-1a 32-bit hash → mulberry32 PRNG → Box-Muller normal.
function hash32(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
/** Seeded standard normal for (token, slot). */
function z(token, slot) {
  const rnd = mulberry32(hash32(`${token}:${slot}`));
  const u1 = Math.max(rnd(), 1e-12);
  const u2 = rnd();
  return Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
}

/** Which kind of contract (volatility + session), from segment / exchange / name. */
function kindOf(meta = {}) {
  const seg = String(meta.segment || '').toUpperCase();
  const ex = String(meta.exchange || '').toUpperCase();
  const type = String(meta.instrument_type || '').toUpperCase();
  if (type === 'CE' || type === 'PE' || seg.endsWith('-OPT')) return 'option';
  if (seg.startsWith('MCX') || ex === 'MCX') return 'mcx';
  if (seg.startsWith('COMEX') || seg === 'GLOBAL' || seg === 'INDICES' || ex === 'NSEIX' || ex === 'COMEX' || ex === 'GLOBAL') return 'global';
  const name = String(meta.name || '').toUpperCase();
  if (['NIFTY', 'BANKNIFTY', 'SENSEX', 'FINNIFTY', 'MIDCPNIFTY', 'NIFTYNXT50', 'BANKEX'].includes(name)) return 'index_fut';
  return 'stock_fut';
}

/**
 * Is the contract's market open during this slot? (IST, weekdays.)
 *   NSE/BSE F&O 09:15–15:30 · MCX 09:00–23:30 · global/GIFT 06:30–02:30 next day
 */
function sessionOpen(slot, meta = {}, stepMin = DEFAULT_STEP_MIN) {
  const startIst = new Date(slotStart(slot, stepMin) + IST_MS);
  const day = startIst.getUTCDay(); // 0 Sun … 6 Sat (IST)
  const mins = startIst.getUTCHours() * 60 + startIst.getUTCMinutes();
  const kind = kindOf(meta);
  if (kind === 'global') {
    // Mon 06:30 → Sat 02:30, open overnight; closed Sat after 02:30 and Sunday.
    if (day === 0) return false;
    if (day === 6) return mins < 150;
    if (day === 1) return mins >= 390;
    return mins >= 390 || mins < 150;
  }
  if (day === 0 || day === 6) return false;
  if (kind === 'mcx') return mins >= 540 && mins < 1410;
  return mins >= 555 && mins < 930; // NSE / BSE: 09:15 – 15:30
}

function roundTick(price, tick = 0.05) {
  const t = tick > 0 ? tick : 0.05;
  return Math.max(t, Math.round(price / t) * t);
}

/**
 * Simulated price of a contract at `ms`.
 * @param {object} anchor  { price, slot }
 * @param {object} meta    { instrument_token, segment, exchange, name, instrument_type, tick_size }
 */
function priceAt(anchor, meta, ms, stepMin = DEFAULT_STEP_MIN) {
  const token = String(meta.instrument_token);
  const sigma = SIGMA[kindOf(meta)];
  const target = slotOf(ms, stepMin);
  let logSum = 0;
  for (let s = anchor.slot + 1; s <= target; s++) {
    if (sessionOpen(s, meta, stepMin)) logSum += z(token, s);
  }
  return roundTick(anchor.price * Math.exp(sigma * logSum), meta.tick_size);
}

/** Full tick object (same fields the live feed sends) for a contract at `ms`. */
function tickAt(anchor, meta, ms, stepMin = DEFAULT_STEP_MIN) {
  const tick = meta.tick_size > 0 ? meta.tick_size : 0.05;
  const ltp = priceAt(anchor, meta, ms, stepMin);
  const day = dayOhlc(anchor, meta, ms, stepMin);
  const close = day.prevClose;
  return {
    instrument_token: String(meta.instrument_token),
    last_price: ltp,
    bid_price: roundTick(ltp - tick, tick),
    ask_price: roundTick(ltp + tick, tick),
    open: day.open,
    high: day.high,
    low: day.low,
    close,
    change: close ? Math.round((ltp - close) * 100) / 100 : 0,
    change_percent: close ? Math.round(((ltp - close) / close) * 10000) / 100 : 0,
  };
}

/** Today's (IST) open / high / low so far and the previous day's close, from the walk. */
function dayOhlc(anchor, meta, ms, stepMin = DEFAULT_STEP_MIN) {
  const target = slotOf(ms, stepMin);
  const perDay = (24 * 60) / stepMin;
  const dayFirst = Math.floor(target / perDay) * perDay; // first slot of today (IST midnight)
  const prevClose = priceAt(anchor, meta, slotStart(Math.max(anchor.slot, dayFirst - 1), stepMin), stepMin);
  let open = null; let high = -Infinity; let low = Infinity;
  for (let s = Math.max(dayFirst, anchor.slot); s <= target; s++) {
    if (s !== anchor.slot && !sessionOpen(s, meta, stepMin)) continue;
    const p = priceAt(anchor, meta, slotStart(s, stepMin), stepMin);
    if (open == null) open = p;
    if (p > high) high = p;
    if (p < low) low = p;
  }
  if (open == null) { open = prevClose; high = prevClose; low = prevClose; }
  return { open, high, low, prevClose };
}

/**
 * Chart candles from the walk: one candle per `intervalMin`, [from, to] (ms).
 * Within a 30-minute slot the price is flat, so candles step every 30 minutes.
 */
function candles(anchor, meta, fromMs, toMs, intervalMin, stepMin = DEFAULT_STEP_MIN) {
  const out = [];
  const iv = intervalMin * 60 * 1000;
  const first = Math.ceil((fromMs + IST_MS) / iv) * iv - IST_MS;
  for (let t = first; t <= toMs && out.length < 5000; t += iv) {
    const o = priceAt(anchor, meta, t, stepMin);
    const c = priceAt(anchor, meta, Math.min(t + iv - 1, toMs), stepMin);
    let h = Math.max(o, c); let l = Math.min(o, c);
    for (let s = slotOf(t, stepMin) + 1; s <= slotOf(Math.min(t + iv - 1, toMs), stepMin); s++) {
      const p = priceAt(anchor, meta, slotStart(s, stepMin), stepMin);
      if (p > h) h = p;
      if (p < l) l = p;
    }
    out.push({ date: new Date(t).toISOString(), open: o, high: h, low: l, close: c, volume: 0 });
  }
  return out;
}

module.exports = { SIGMA, slotOf, slotStart, z, kindOf, sessionOpen, roundTick, priceAt, tickAt, dayOhlc, candles };
