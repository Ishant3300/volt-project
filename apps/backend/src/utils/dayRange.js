'use strict';

/**
 * Day high/low per script, taken from the feed's own ticks (Kite: tick.low/high;
 * GIFT: NSE IX row LOW/HIGH). Every real trade prints inside the day's range, so a
 * price outside the known range whose own tick did NOT move the low/high to include
 * it is a bad quote (4 Nov 2026 12:22 IST: GIFT 2375.2 while the day low stayed
 * 23,673.5 — it filled 8 limit orders the market never reached).
 *
 *   acceptTick()  feeds: false = bad quote → not shown, not matched, not valued
 *   inRange()     order matching + market orders: is this price inside today's range?
 *
 * COMEX/Global (Massive) are not fed here yet: their high/low comes from a poll that
 * can lag the live quote.
 */

const { getIndiaDateTimeParts } = require('./settlementDates');

const ranges = new Map(); // token -> { low, high, day }
// DAY_RANGE_FEED=monitor: feeds only log a would-be bad quote (kill switch; market
// orders and order matching still check the range).
const FEED_MONITOR_ONLY = String(process.env.DAY_RANGE_FEED || '').toLowerCase() === 'monitor';

function dayKey(now = new Date()) {
  const p = getIndiaDateTimeParts(now);
  return `${p.year}-${p.month}-${p.day}`;
}

/** Rounding room: 0.05% of the price, at least one 0.05 tick. */
function tolerance(price) {
  return Math.max(Math.abs(price) * 0.0005, 0.05);
}

function isOutside(range, price) {
  return price < range.low - tolerance(range.low) || price > range.high + tolerance(range.high);
}

function current(token, now) {
  const r = ranges.get(String(token));
  return r && r.day === dayKey(now) ? r : null;
}

/**
 * A feed tick. Returns false for a bad quote: outside the known range while the
 * tick's own low/high did not move to include it (or the tick contradicts itself).
 * A good tick with a low/high records it as the script's range.
 */
function acceptTick(token, price, tickLow, tickHigh, now = new Date()) {
  const p = Number(price);
  if (!(p > 0)) return true;
  const lo = Number(tickLow);
  const hi = Number(tickHigh);
  const hasTick = lo > 0 && hi > 0 && hi >= lo;
  const prev = current(token, now);
  let bad = hasTick && isOutside({ low: lo, high: hi }, p); // contradicts its own low/high
  if (!bad && prev && isOutside(prev, p)) {
    const moved = hasTick && (lo < prev.low - 1e-9 || hi > prev.high + 1e-9);
    bad = !moved;
  }
  if (bad) {
    if (!FEED_MONITOR_ONLY) return false;
    console.warn(`⚠️  [DayRange] monitor: token=${token} price ${p} would be ignored (outside ${prev ? prev.low + '–' + prev.high : lo + '–' + hi})`);
    return true;
  }
  if (hasTick) ranges.set(String(token), { low: lo, high: hi, day: dayKey(now) });
  return true;
}

/** True when the price lies inside today's known range (or no range is known yet). */
function inRange(token, price, now = new Date()) {
  const r = current(token, now);
  const p = Number(price);
  return !r || !(p > 0) || !isOutside(r, p);
}

/** Today's { low, high } for a script, or null. */
function rangeOf(token, now = new Date()) {
  const r = current(token, now);
  return r ? { low: r.low, high: r.high } : null;
}

function _reset() {
  ranges.clear();
}

module.exports = { acceptTick, inRange, rangeOf, tolerance, _reset };
