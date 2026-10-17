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
  cron.schedule('31 23 * * 1-5', run('MCX close prices', () => simFeed.writeClosePrices(['mcx'], istDate())), tz);
  // Global session closes 02:30 IST the next morning — belongs to the previous trading day.
  cron.schedule('31 2 * * 2-6', run('Global close prices', () => simFeed.writeClosePrices(['global'], istDate(-1))), tz);
  cron.schedule('0 4 * * *', run('Roll anchors', () => simFeed.rollAnchors()), tz);
  console.log('🎲 [practiceCron] scheduled: close prices NSE 15:31 / MCX 23:31 / global 02:31, anchors 04:00');
}

module.exports = { start };
