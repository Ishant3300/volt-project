/**
 * Hard-delete the 4 Zerodha/Kite-sourced global cash-index instruments —
 * US 100 (Nasdaq 100), US 500 (S&P 500), US 30 (Dow Jones 30), UK 100
 * (FTSE 100) — now superseded by the real Massive-sourced tradable futures
 * (NQ, ES, YM; no FTSE 100 replacement exists yet, removed anyway per
 * explicit instruction). SENSEX and GIFT NIFTY are NOT touched — SENSEX is
 * a genuine Indian index, and GIFT NIFTY is already fed by the NSEIX
 * scraper (giftNiftyFeedService.js), not a raw Kite cash quote.
 *
 * NOT handled here (explicitly deferred by the user, to be done separately):
 * syntheticInstrumentService.js's Bhuj Nifty calculation reads US 100/US 30
 * as live inputs — after this runs, that lookup will find nothing and the
 * synthetic index will stop updating until repointed at the new Massive
 * tickers.
 *
 * Safety: refuses to delete an instrument that has ANY Trade record
 * referencing its instrument_token unless run with --force, since a hard
 * delete (not soft-delete) would leave those historical trades unable to
 * resolve their own instrument's name/segment/lot_size afterward.
 *
 * Usage: node scripts/removeZerodhaGlobalIndices.js [--force]
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const connectDatabase = require('../src/database/database');
const KiteInstrument = require('../src/models/KiteInstrument');
const Trade = require('../src/models/Trade');

const TARGET_NAMES = ['US 100', 'US 500', 'US 30', 'UK 100'];
const FORCE = process.argv.includes('--force');

async function run() {
  await connectDatabase();

  const instruments = await KiteInstrument.find({
    $or: [
      { name: { $in: TARGET_NAMES } },
      { tradingsymbol: { $in: TARGET_NAMES } },
    ],
  }).lean();

  if (instruments.length === 0) {
    console.log('No matching instruments found.');
    await mongoose.connection.close();
    process.exit(0);
  }

  console.log(`Found ${instruments.length} instrument(s) to remove:`);
  for (const inst of instruments) {
    console.log(`  - ${inst.display_name || inst.name} (${inst.tradingsymbol}, token ${inst.instrument_token})`);
  }

  const blockedTokens = [];
  for (const inst of instruments) {
    const tradeCount = await Trade.countDocuments({ instrument_token: inst.instrument_token });
    if (tradeCount > 0) {
      console.warn(`⚠️  ${inst.display_name || inst.name} has ${tradeCount} trade record(s) referencing it.`);
      blockedTokens.push(inst.instrument_token);
    }
  }

  if (blockedTokens.length > 0 && !FORCE) {
    console.error(`\n❌ Refusing to hard-delete ${blockedTokens.length} instrument(s) with existing trade history (run with --force to override — those trades will no longer resolve their instrument's name/segment/lot_size afterward).`);
    await mongoose.connection.close();
    process.exit(1);
  }

  const tokens = instruments.map(i => i.instrument_token);
  const result = await KiteInstrument.deleteMany({ instrument_token: { $in: tokens } });
  console.log(`\n✅ Deleted ${result.deletedCount} instrument(s).`);

  try {
    const searchService = require('../src/services/instrumentSearchService');
    searchService.invalidateCache();
  } catch (_) {}

  await mongoose.connection.close();
  process.exit(0);
}

run().catch((err) => {
  console.error('❌ Failed:', err.message);
  process.exit(1);
});
