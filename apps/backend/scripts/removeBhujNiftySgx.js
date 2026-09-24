/**
 * Permanently remove the legacy "BHUJ NIFTY" synthetic instrument (token
 * 9999999, exchange/segment SGX) — the last remaining SGX-tagged data after
 * SGX was dropped as a selectable exchange everywhere (GIFT NIFTY moved to
 * GLOBAL; SGX now carries nothing else). Per explicit instruction, this
 * hard-deletes the 6 historical Trade records too, not just soft-deleting
 * the instrument — unlike every other cleanup script in this repo, which
 * deliberately preserves trade history. That means this changes the
 * historical P&L/brokerage totals for the 2 users who hold those trades.
 *
 * Deliberately NOT touched: User.credits/equity for those 2 users. The
 * brokerage these trades charged months ago already moved real balance —
 * unwinding that now would be a separate, far riskier retroactive financial
 * correction that wasn't asked for. This script only removes the trade
 * *records*, not their already-settled financial effects.
 *
 * Usage: node scripts/removeBhujNiftySgx.js
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const connectDatabase = require('../src/database/database');
const KiteInstrument = require('../src/models/KiteInstrument');
const Trade = require('../src/models/Trade');
const Transaction = require('../src/models/Transaction');
const Watchlist = require('../src/models/Watchlist');

const TOKEN = '9999999';

async function run() {
  await connectDatabase();

  const trades = await Trade.find({ instrument_token: TOKEN }).lean();
  console.log(`Found ${trades.length} trade(s) to delete:`);
  for (const t of trades) {
    console.log(`  - ${t._id} (${t.transaction_type} x${t.executed_quantity} @ ${t.executed_price}, brokerage ${t.brokerage})`);
  }
  const tradeIds = trades.map(t => t._id);

  const txResult = await Transaction.deleteMany({ referenceId: { $in: tradeIds } });
  console.log(`\nDeleted ${txResult.deletedCount} linked Transaction record(s).`);

  const tradeResult = await Trade.deleteMany({ instrument_token: TOKEN });
  console.log(`Deleted ${tradeResult.deletedCount} Trade record(s).`);

  const wlResult = await Watchlist.updateMany(
    { instrument_token: TOKEN, deleted_at: null },
    { deleted_at: new Date() }
  );
  console.log(`Soft-deleted ${wlResult.modifiedCount} watchlist entry(ies).`);

  const instResult = await KiteInstrument.updateMany(
    { instrument_token: TOKEN },
    { deleted_at: new Date(), enabled: false }
  );
  console.log(`Soft-deleted ${instResult.modifiedCount} instrument(s).`);

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
