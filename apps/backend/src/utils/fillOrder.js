'use strict';

/**
 * Trades in the order they FILLED, for any running-average position walk.
 *
 * A pending LIMIT/SL order is created when it is placed but fills later, so
 * sorting by createdAt (placement) replays it before orders placed after it
 * that filled first. Trade.pnl is booked at fill time in the real order, so a
 * placement-order replay gives the open part of the position a different
 * average than the one the trades were booked against. Found 7 Nov 2026: KK
 * (117905) GIFTNIFTY — SL BUY 50 @ 25051 placed 21:14:40, filled 21:37:32,
 * after a SELL 50 @ 25039 at 21:36:50; settlement's average for the 200 short
 * came out 24,998.875 instead of 24,996.20, booking 46,487 instead of 45,952
 * (+535). 7 settled positions were off (31 Oct + 7 Nov).
 *
 * Fill time = executed_at (createdAt when a legacy row has none); ties keep
 * placement order, then _id, so same-instant rows stay as before.
 */
const ms = (d) => (d ? new Date(d).getTime() : NaN);
const fillTime = (t) => { const e = ms(t.executed_at); return Number.isFinite(e) ? e : ms(t.createdAt); };

function byFillTime(a, b) {
  return (fillTime(a) - fillTime(b))
    || (ms(a.createdAt) - ms(b.createdAt))
    || String(a._id).localeCompare(String(b._id));
}

/** Sorts in place and returns the same array. */
function sortByFillTime(trades) {
  return trades.sort(byFillTime);
}

module.exports = { byFillTime, sortByFillTime, fillTime };
