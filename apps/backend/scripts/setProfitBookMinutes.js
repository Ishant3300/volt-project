'use strict';

/**
 * One-time (20 Oct 2026): give every existing client the profit book time the
 * old universal admin setting applied — 10 minutes on every script — so
 * nothing changes for anyone when per-client times go live
 * (utils/profitBookTime.js). Only accounts without the field are touched.
 *
 *   node scripts/setProfitBookMinutes.js          # dry run: counts only
 *   node scripts/setProfitBookMinutes.js --apply  # write
 */
require('dotenv').config();
const mongoose = require('mongoose');
const { DEFAULT_PROFIT_BOOK_MINUTES } = require('../src/utils/profitBookTime');

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const users = mongoose.connection.db.collection('users');
  const missing = { profit_book_minutes: { $exists: false } };
  const count = await users.countDocuments(missing);
  console.log(`Clients without profit_book_minutes: ${count} (would set ${DEFAULT_PROFIT_BOOK_MINUTES})`);
  if (process.argv.includes('--apply') && count > 0) {
    const res = await users.updateMany(missing, { $set: { profit_book_minutes: DEFAULT_PROFIT_BOOK_MINUTES } });
    console.log(`Set on ${res.modifiedCount} client(s).`);
  }
  await mongoose.disconnect();
})().catch((e) => { console.error(e.message); process.exit(1); });
