'use strict';

/**
 * NSE / BSE F&O pre-open: from 9:00 to 9:15 AM IST Kite already streams NFO and
 * BFO quotes, but they are the pre-open order book's indicative prices — nothing
 * has traded. 11 Nov 2026 09:00:00 IST: ANGELONE NOV FUT came in with a 309 bid
 * (official close 339.10, Kite's own LTP still 339.10 at 9:14); the long position
 * was valued at that bid and client 433652 was margin squared-off for -3.93 lakh.
 *
 * During the pre-open such a tick is dropped the same way a bad quote is: not
 * shown, not valued, not matched (livePriceService._applyTicks). The first tick
 * after the open is used as usual. No NFO/BFO order has ever filled before 9:15
 * on this platform, so nothing else changes.
 *
 * Special sessions (utils/specialSessions.js, e.g. Muhurat): the 15 minutes
 * before that day's NSE window opens.
 *
 * Only real Kite tokens (32-bit; the low byte is the segment: 2 = NFO, 5 = BFO).
 * GIFT / Massive / synthetic tokens are larger numbers and never match.
 */

const specialSessions = require('./specialSessions');

const FO_SEGMENTS = new Set([2, 5]); // Kite segment ids: NFO, BFO
const PRE_OPEN_FROM = 9 * 60; // 9:00 IST
const OPEN = 9 * 60 + 15; // 9:15 IST
const PRE_OPEN_MIN = 15;

function minutesOf(hhmm) {
  const [h, m] = String(hhmm).split(':').map(Number);
  return h * 60 + m;
}

/** Is this Kite token an NSE/BSE F&O contract? */
function isFoToken(instrumentToken) {
  const token = Number(instrumentToken);
  if (!Number.isInteger(token) || token <= 0 || token >= 2 ** 32) return false;
  return FO_SEGMENTS.has(token % 256);
}

/** Is `now` inside an NSE F&O pre-open (regular day, or a special session's)? */
function isPreOpenTime(now = new Date()) {
  const hhmm = specialSessions.istHhmm(now);
  const min = minutesOf(hhmm);
  if (min >= PRE_OPEN_FROM && min < OPEN) return true;
  const session = specialSessions.sessionOn(specialSessions.istYmd(now));
  const nse = session && session.windows.find((w) => w.key === 'NSE');
  if (!nse) return false;
  const open = minutesOf(nse.open);
  return min >= open - PRE_OPEN_MIN && min < open;
}

/** Drop this tick? (an NFO/BFO quote during the pre-open) */
function isFoPreOpenTick(instrumentToken, now = new Date()) {
  return isFoToken(instrumentToken) && isPreOpenTime(now);
}

module.exports = { isFoPreOpenTick, isFoToken, isPreOpenTime };
