/**
 * Soft-delete the 4 Zerodha/Kite-sourced global cash-index instruments —
 * US 100 (Nasdaq 100), US 500 (S&P 500), US 30 (Dow Jones 30), UK 100
 * (FTSE 100) — superseded by the real Massive-sourced tradable futures
 * (NQ, ES, YM; no FTSE 100 replacement exists yet). Same targets as the
 * original scripts/removeZerodhaGlobalIndices.js, but SOFT-deletes
 * (deleted_at) instead of hard-deleting: US 30 and US 500 carry real
 * historical Trade records, and a hard delete would leave those trades
 * unable to resolve their own instrument's name/segment/lot_size in
 * reports/statements afterward. Soft-delete is safe regardless of trade
 * history and hides them from every browse/search/watchlist path the same
 * way (all of those already filter deleted_at: null).
 *
 * The original hard-delete script's fix never stuck: nothing excluded these
 * names from fetchInstruments.js's allowlist, so the daily Kite sync cron
 * silently recreated them every day since — see EXCLUDED_CASH_INDEX_NAMES
 * in fetchInstruments.js for the actual fix preventing recurrence.
 *
 * Also soft-deletes any Watchlist entries referencing them.
 *
 * Usage: node scripts/removeZerodhaGlobalIndicesV2.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const connectDatabase = require('../src/database/database');
const KiteInstrument = require('../src/models/KiteInstrument');
const Trade = require('../src/models/Trade');
const Watchlist = require('../src/models/Watchlist');

const TARGET_NAMES = ['US 100', 'US 500', 'US 30', 'UK 100'];

async function run() {
  await connectDatabase();

  const instruments = await KiteInstrument.find({
    name: { $in: TARGET_NAMES },
    deleted_at: null,
  }).lean();

  if (instruments.length === 0) {
    console.log('No matching (non-deleted) instruments found.');
    await mongoose.connection.close();
    process.exit(0);
  }

  console.log(`Found ${instruments.length} instrument(s) to soft-delete:`);
  for (const inst of instruments) {
    const tradeCount = await Trade.countDocuments({ instrument_token: inst.instrument_token });
    console.log(`  - ${inst.name} (${inst.tradingsymbol}, token ${inst.instrument_token}, ${tradeCount} trade(s) referencing it)`);
  }

  const tokens = instruments.map(i => i.instrument_token);

  const wlResult = await Watchlist.updateMany(
    { instrument_token: { $in: tokens }, deleted_at: null },
    { deleted_at: new Date() }
  );
  console.log(`\nSoft-deleted ${wlResult.modifiedCount} watchlist entry(ies).`);

  const result = await KiteInstrument.updateMany(
    { instrument_token: { $in: tokens } },
    { deleted_at: new Date(), enabled: false }
  );
  console.log(`Soft-deleted ${result.modifiedCount} instrument(s).`);

  try {
    const searchService = require('../src/services/instrumentSearchService');
    searchService.invalidateCache();
  } catch (_) {}

  await mongoose.connection.close();
  process.exit(0);
}

run().catch((err) => {
  console.error('Failed:', err.message);
  process.exit(1);
});
