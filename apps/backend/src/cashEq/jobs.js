'use strict';

// Equity background jobs — started once from index.js (live server only, never practice).
// Every job checks the on/off switch, so with equity off nothing runs and no Kite
// connection is opened.
//
//   every 30 s        feed.refresh(): connect / subscribe / disconnect as needed
//   08:05 IST Mon–Fri NSE EQ stock list, then the approved (MTF) list
//                     (after the F&O 07:30 instrument sync, never at the same time)

const cron = require('node-cron');
const feed = require('./feed');
const { enabled } = require('./switch');
const { EqInstrument, EqWatchlist, EqAudit } = require('./models');
const instruments = require('./instruments');

let started = false;
let syncing = false;

async function syncLists(trigger) {
  if (syncing) return { skipped: 'already running' };
  syncing = true;
  try {
    const stocks = await instruments.syncInstruments();
    let mtf;
    try {
      mtf = await instruments.syncMtfList();
    } catch (err) {
      mtf = { error: err.message }; // stock list still synced; approved flags unchanged
      console.log(`⚠️ [cashEq] MTF list not synced: ${err.message}`);
    }
    await EqAudit.create({
      actor: { role: 'system', username: trigger }, action: 'lists_sync', target: { kind: 'instruments' },
      details: { stocks, mtf: mtf.error ? mtf : { ...mtf, added: mtf.added.slice(0, 100), removed: mtf.removed.slice(0, 100) } },
    });
    return { stocks, mtf };
  } finally {
    syncing = false;
  }
}

function start(livePriceService) {
  if (started) return;
  if (require('../config/practice').PRACTICE) return; // practice server: no equity, no Kite
  started = true;

  // What equity needs prices for (M4/M5 add held and pending scripts at higher priority).
  feed.registerSource('watchlists', () => EqWatchlist.distinct('instrument_token'), 50);
  feed.start(livePriceService);

  const tick = async () => {
    try {
      if (!(await enabled())) {
        feed.stop('equity switched off');
        return;
      }
      // First time on: the stock list is empty — fetch it now rather than waiting for 08:05.
      if (!syncing && !(await EqInstrument.exists({}))) await syncLists('first start');
      await feed.refresh();
    } catch (err) {
      console.log(`⚠️ [cashEq] refresh: ${err.message}`);
    }
  };
  const h = setInterval(tick, 30 * 1000);
  h.unref?.();
  setTimeout(tick, 60 * 1000).unref?.(); // first run a minute after start (startup stays quick)

  cron.schedule('5 8 * * 1-5', async () => {
    try {
      if (await enabled()) await syncLists('08:05 daily');
    } catch (err) {
      console.log(`⚠️ [cashEq] daily list sync failed: ${err.message}`);
    }
  }, { timezone: 'Asia/Kolkata' });

  console.log('📈 [cashEq] jobs scheduled (idle unless cashEq:enabled)');
}

module.exports = { start, syncLists };
