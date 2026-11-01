'use strict';

/**
 * Practice mode only (docs/practice-trading.md): end-of-session jobs for the
 * simulated prices.
 *
 * - At each market's close the simulated close becomes the contract's
 *   settlement price (source PRACTICE_SIM), so the weekly settlement (Sat
 *   02:50) and expiry closes use simulated prices like everything else.
 * - Nightly the anchors are rolled forward (pure optimisation — the walk is
 *   unchanged).
 */
const cron = require('node-cron');
const simFeed = require('./simFeed');

const istDate = (offsetDays = 0) => new Date(Date.now() + 5.5 * 3600e3 + offsetDays * 864e5).toISOString().slice(0, 10);

function start() {
  const tz = { timezone: 'Asia/Kolkata' };
  const run = (label, fn) => async () => {
    try { console.log(`🎲 [practiceCron] ${label}: ${await fn()}`); } catch (e) { console.error(`❌ [practiceCron] ${label} failed: ${e.message}`); }
  };
  cron.schedule('31 15 * * 1-5', run('NSE close prices', () => simFeed.writeClosePrices(['nse'], istDate())), tz);
  // MCX closes 23:30 IST in US summer time, 23:55 in winter (utils/mcxHours.js,
  // 1 Nov 2026): one minute after whichever close applies that day.
  const { mcxCloseOn } = require('../../utils/mcxHours');
  const mcxClose = (hhmm) => run(`MCX close prices (${hhmm})`, async () => {
    const day = istDate();
    if (mcxCloseOn(day) !== hhmm) return 'not the close time today';
    return simFeed.writeClosePrices(['mcx'], day);
  });
  cron.schedule('31 23 * * 1-5', mcxClose('23:30'), tz);
  cron.schedule('56 23 * * 1-5', mcxClose('23:55'), tz);
  // Global (CME) closes 4:00 PM Chicago — 02:30 IST in US summer, 03:30 in
  // winter, the next IST morning — and belongs to the previous trading day.
  cron.schedule('1 16 * * 1-5', run('Global close prices', () => simFeed.writeClosePrices(['global'], istDate(-1))), { timezone: 'America/Chicago' });
  cron.schedule('0 4 * * *', run('Roll anchors', () => simFeed.rollAnchors()), tz);
  console.log('🎲 [practiceCron] scheduled: close prices NSE 15:31 / MCX 1 min after its close (23:30 or 23:55) / global 4:01 PM Chicago, anchors 04:00');
}

module.exports = { start };
