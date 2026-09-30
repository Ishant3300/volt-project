'use strict';

/**
 * NSE F&O closing window: from 3:20 PM to 3:40 PM IST only MARKET orders are
 * allowed in NFO-FUT and NFO-OPT (SENSEX included — it trades under the NFO
 * segments). All pending LIMIT / SL / SL-M NFO orders are cancelled at 3:20
 * (cronService), and masters/clients can't place or modify one until 3:40.
 * Admin is not restricted. Every other segment is unaffected.
 */
const SEGMENTS = new Set(['NFO-FUT', 'NFO-OPT']);
const FROM_MIN = 15 * 60 + 20; // 3:20 PM IST
const TO_MIN = 15 * 60 + 40; // 3:40 PM IST (exclusive)

/** Minutes past midnight in IST for a given instant. */
function istMinutes(now) {
  const ist = new Date(now.getTime() + 5.5 * 3600e3);
  return ist.getUTCHours() * 60 + ist.getUTCMinutes();
}

function isNfoMarketOnlyWindow(segment, now = new Date()) {
  if (!SEGMENTS.has(String(segment || '').toUpperCase())) return false;
  const min = istMinutes(now);
  return min >= FROM_MIN && min < TO_MIN;
}

const MESSAGE = 'Only market orders are allowed in NFO between 3:20 PM and 3:40 PM. Limit and stop-loss orders are not accepted in this window.';
const CANCEL_REMARK = 'Auto-cancelled: limit/stop-loss orders are not allowed in NFO from 3:20 PM to 3:40 PM';

module.exports = { isNfoMarketOnlyWindow, MESSAGE, CANCEL_REMARK, SEGMENTS };
