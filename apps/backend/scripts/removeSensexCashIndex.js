/**
 * Hard-delete the SENSEX cash-index quote (segment INDICES, exchange BSE,
 * instrument_token 265, no expiry) — a raw Kite spot quote never used
 * anywhere on the platform, per explicit instruction. Does NOT touch
 * SENSEX's real BFO-FUT/BFO-OPT derivatives, which are genuinely traded
 * (fetchInstruments.js's EXCLUDED_CASH_INDEX_NAMES keeps this from being
 * re-synced, and is segment-scoped for the same reason).
 *
 * Also soft-deletes any Watchlist entries referencing it, same as the
 * auto-remove-on-expiry logic in watchlistController.js.
 *
 * Safety: refuses to delete if any Trade record references its
 * instrument_token unless run with --force.
 *
 * Usage: node scripts/removeSensexCashIndex.js [--force]
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const connectDatabase = require('../src/database/database');
const KiteInstrument = require('../src/models/KiteInstrument');
const Trade = require('../src/models/Trade');
const Watchlist = require('../src/models/Watchlist');

const FORCE = process.argv.includes('--force');

async function run() {
  await connectDatabase();

  const instruments = await KiteInstrument.find({
    name: { $regex: /^SENSEX$/i },
    segment: 'INDICES',
  }).lean();

  if (instruments.length === 0) {
    console.log('No SENSEX cash-index instrument found.');
    await mongoose.connection.close();
    process.exit(0);
  }

  for (const inst of instruments) {
    console.log(`Found: ${inst.tradingsymbol} (token ${inst.instrument_token}, exchange ${inst.exchange})`);
  }

  const blockedTokens = [];
  for (const inst of instruments) {
    const tradeCount = await Trade.countDocuments({ instrument_token: inst.instrument_token });
    if (tradeCount > 0) {
      console.warn(`⚠️  ${inst.tradingsymbol} has ${tradeCount} trade record(s) referencing it.`);
      blockedTokens.push(inst.instrument_token);
    }
  }

  if (blockedTokens.length > 0 && !FORCE) {
    console.error(`\n❌ Refusing to hard-delete ${blockedTokens.length} instrument(s) with existing trade history (run with --force to override).`);
    await mongoose.connection.close();
    process.exit(1);
  }

  const tokens = instruments.map(i => i.instrument_token);

  const wlResult = await Watchlist.updateMany(
    { instrument_token: { $in: tokens }, deleted_at: null },
    { deleted_at: new Date() }
  );
  console.log(`\n🗑️  Soft-deleted ${wlResult.modifiedCount} watchlist entry(ies).`);

  const result = await KiteInstrument.deleteMany({ instrument_token: { $in: tokens } });
  console.log(`✅ Deleted ${result.deletedCount} instrument(s).`);

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
