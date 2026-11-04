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
const { EqInstrument, EqWatchlist, EqAudit, EqTrade } = require('./models');
const instruments = require('./instruments');
const orders = require('./orders');
const { istNow, addDays } = require('./engine');

/** Stocks any equity client holds (net bought > sold), cached 5 minutes. */
let heldCache = { at: 0, tokens: [] };
async function heldTokens() {
  if (Date.now() - heldCache.at < 5 * 60 * 1000) return heldCache.tokens;
  const rows = await EqTrade.aggregate([
    { $match: { deleted_at: null } },
    { $group: { _id: { c: '$client_id', t: '$instrument_token' }, q: { $sum: { $cond: [{ $eq: ['$side', 'B'] }, '$qty', { $multiply: ['$qty', -1] }] } } } },
    { $match: { q: { $gt: 0 } } },
    { $group: { _id: '$_id.t' } },
  ]);
  heldCache = { at: Date.now(), tokens: rows.map((r) => r._id) };
  return heldCache.tokens;
}

let started = false;
let syncing = false;

/**
 * The practice server has config/practice.js; the LIVE server's copy never had the
 * practice files (4 Nov 2026: requiring it there threw and the deploy rolled back) —
 * missing file = live server.
 */
function isPracticeServer() {
  try {
    return Boolean(require('../config/practice').PRACTICE);
  } catch (_) {
    return false;
  }
}

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
  if (isPracticeServer()) return; // practice server: no equity, no Kite
  started = true;

  // What equity needs prices for, most important first (the cap keeps the first 800).
  feed.registerSource('open orders', () => orders.refreshOpenTokens(), 10);
  feed.registerSource('holdings', heldTokens, 20);
  feed.registerSource('watchlists', () => EqWatchlist.distinct('instrument_token'), 50);
  feed.addListener(orders.onTicks);
  feed.start(livePriceService);

  // Orders left open from an earlier day (e.g. a restart over the close) expire.
  setTimeout(() => {
    orders.expireOpen(addDays(istNow().date, -1)).catch((e) => console.log(`⚠️ [cashEq] expire old orders: ${e.message}`));
  }, 60 * 1000).unref?.();
  cron.schedule('31 15 * * 1-5', async () => {
    try {
      const n = await orders.expireOpen(istNow().date);
      if (n) console.log(`📈 [cashEq] ${n} open equity order(s) expired at the close`);
    } catch (err) {
      console.log(`⚠️ [cashEq] day-end expiry failed: ${err.message}`);
    }
  }, { timezone: 'Asia/Kolkata' });

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
