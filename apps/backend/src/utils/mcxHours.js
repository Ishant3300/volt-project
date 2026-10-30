'use strict';

/**
 * MCX's non-agri evening close follows US daylight saving: 11:30 PM IST while
 * the US is on summer time, 11:55 PM IST in US winter (from the trading day
 * after the US clock change — 2 Nov 2026 to 12 Mar 2027, then 11:30 again from
 * 15 Mar 2027). Decided per IST trading date from New York's own offset, so
 * every future switch happens by itself. No requires (the watchdog uses it).
 */

const SUMMER_CLOSE = '23:30';
const WINTER_CLOSE = '23:55';

const nyZone = new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', timeZoneName: 'short' });

/** True when New York is on daylight time on IST date `YYYY-MM-DD` (checked at 12:00 UTC that day). */
function usSummerTimeOn(ymd) {
  const [y, m, d] = ymd.split('-').map(Number);
  const name = nyZone.formatToParts(new Date(Date.UTC(y, m - 1, d, 12))).find((p) => p.type === 'timeZoneName');
  return name ? name.value === 'EDT' : false;
}

/** MCX close `HH:MM` IST on IST date `YYYY-MM-DD`. */
function mcxCloseOn(ymd) {
  return usSummerTimeOn(ymd) ? SUMMER_CLOSE : WINTER_CLOSE;
}

/** MCX close as minutes after IST midnight on IST date `YYYY-MM-DD`. */
function mcxCloseMinutesOn(ymd) {
  const [hh, mm] = mcxCloseOn(ymd).split(':').map(Number);
  return hh * 60 + mm;
}

module.exports = { SUMMER_CLOSE, WINTER_CLOSE, usSummerTimeOn, mcxCloseOn, mcxCloseMinutesOn };
