'use strict';

/**
 * CME Globex hours for COMEX metals and the GLOBAL index futures (Dow,
 * Nasdaq, S&P, Russell, Nikkei): Sunday–Friday 5:00 PM – 4:00 PM Chicago
 * time, with a daily break 4:00–5:00 PM (cmegroup.com contract specs).
 * Worked out in Chicago time, so US daylight saving moves it by itself:
 * the break is 2:30–3:30 AM IST in US summer, 3:30–4:30 AM IST in US winter.
 * The apps' fixed 2:00–3:30 AM IST window doesn't move — from 2 Nov 2026 it
 * reopens at 3:30 while CME is still shut, so order placement checks this.
 * Exchange holidays are not known here.
 */

const CHICAGO = 'America/Chicago';
const CLOSE_MIN = 16 * 60; // 4:00 PM
const OPEN_MIN = 17 * 60; // 5:00 PM

const fmt = new Intl.DateTimeFormat('en-US', { timeZone: CHICAGO, weekday: 'short', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });

function chicagoParts(ms) {
  const p = Object.fromEntries(fmt.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { weekday: p.weekday, minutes: Number(p.hour) * 60 + Number(p.minute) };
}

/** Is CME Globex (COMEX / GLOBAL index futures) trading at `ms`? */
function isCmeOpen(ms = Date.now()) {
  const { weekday, minutes } = chicagoParts(ms);
  if (weekday === 'Sat') return false;
  if (weekday === 'Sun') return minutes >= OPEN_MIN;
  if (weekday === 'Fri') return minutes < CLOSE_MIN;
  return minutes < CLOSE_MIN || minutes >= OPEN_MIN; // Mon–Thu: daily break 4–5 PM
}

/** When CME next opens after `ms` (a closed moment), to the minute. */
function cmeNextOpen(ms = Date.now()) {
  let t = Math.floor(ms / 60_000) * 60_000;
  for (let i = 0; i < 3 * 24 * 60; i++) { // at most ~2 days (weekend)
    t += 60_000;
    if (isCmeOpen(t)) return t;
  }
  return null;
}

const istTime = (ms) => new Date(ms).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata', weekday: 'short', hour: 'numeric', minute: '2-digit', hour12: true });

/** Message for an order refused while CME is closed. */
function cmeClosedMessage(ms = Date.now()) {
  const next = cmeNextOpen(ms);
  return `This market (CME) is closed right now${next ? ` — it opens again at ${istTime(next)} IST` : ''}. No order can be placed while it is closed.`;
}

module.exports = { isCmeOpen, cmeNextOpen, cmeClosedMessage };
