'use strict';

/**
 * Practice database setup + nightly reference copy (docs/practice-trading.md).
 *
 *   MONGO_URI      practice database (written)          — from the practice .env
 *   LIVE_MONGO_URI live database (READ ONLY: contracts, servers)
 *
 *   node scripts/practice/setupPractice.js            setup + contract copy
 *   node scripts/practice/setupPractice.js contracts  contract copy only (nightly)
 *
 * Copies ONLY reference data: active F&O / MCX / global / GIFT contracts and
 * the server records. Never accounts, trades, money or brokerage. Existing
 * practice contracts keep their (simulated) price fields — only new
 * contracts get the live close as their first price. Refuses to run if the
 * practice database is the live database.
 */
require('dotenv').config();
const crypto = require('crypto');
const bcrypt = require('bcryptjs');
const { MongoClient } = require('mongoose').mongo;

const PRICE_FIELDS = ['last_price', 'settlement_price', 'settlement_price_date', 'settlement_price_source', 'ohlc_open', 'ohlc_high', 'ohlc_low', 'ohlc_close'];
const SEGMENTS = ['NFO-FUT', 'NFO-OPT', 'BFO-FUT', 'BFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT', 'INDICES', 'GLOBAL'];
const dbName = (uri) => new URL(uri.replace(/^mongodb(\+srv)?:\/\//, 'http://')).pathname.replace('/', '') || 'test';

(async () => {
  const practiceUri = process.env.MONGO_URI; const liveUri = process.env.LIVE_MONGO_URI;
  if (process.env.PRACTICE_MODE !== '1') throw new Error('run only with the practice .env (PRACTICE_MODE=1)');
  if (!practiceUri || !liveUri) throw new Error('MONGO_URI and LIVE_MONGO_URI are required');
  if (practiceUri === liveUri || dbName(practiceUri) === dbName(liveUri)) throw new Error('practice database must not be the live database');

  const P = await MongoClient.connect(practiceUri); const L = await MongoClient.connect(liveUri);
  const pd = P.db(); const ld = L.db();
  const onlyContracts = process.argv[2] === 'contracts';

  if (!onlyContracts) {
    for (const s of await ld.collection('servers').find({}).toArray()) await pd.collection('servers').updateOne({ _id: s._id }, { $set: s }, { upsert: true });
    const server = await pd.collection('servers').findOne({});
    let admin = await pd.collection('admins').findOne({ username: 'practice_admin' });
    if (!admin) {
      // Internal owner only — random password, nobody logs in with it.
      await pd.collection('admins').insertOne({ username: 'practice_admin', name: 'Practice Admin', password: await bcrypt.hash(crypto.randomBytes(24).toString('hex'), 10), is_super_admin: false, permissions: [], createdAt: new Date(), updatedAt: new Date() });
      admin = await pd.collection('admins').findOne({ username: 'practice_admin' });
    }
    if (!(await pd.collection('masters').findOne({ username: 'PRACTICE' }))) {
      await pd.collection('masters').insertOne({
        name: 'Practice Accounts', username: 'PRACTICE', password: await bcrypt.hash(crypto.randomBytes(24).toString('hex'), 10),
        credits: 0, equity: 0, pnl_sharing: 0, brokerage_sharing: 0, exchanges_allowed: SEGMENTS, trade_limit: [], add_master: false,
        server_id: server._id, admin_id: admin._id, master_id: null, status: 'active', active_status: true, deleted_at: null,
        wallet: { NSE: 0, INDEX: 0, NSEOPT: 0, MCX: 0, COMEX: 0, GLOBAL: 0 }, createdAt: new Date(), updatedAt: new Date(),
      });
    }
    console.log(`servers ${await pd.collection('servers').countDocuments()}, admin practice_admin, master PRACTICE ready`);
  }

  // Contracts: active + not expired, in the traded segments.
  const today = new Date(); today.setUTCHours(0, 0, 0, 0);
  const filter = { $or: [{ segment: { $in: SEGMENTS } }, { exchange: 'NSEIX' }], deleted_at: null, $and: [{ $or: [{ expiry: null }, { expiry: { $gte: today } }] }] };
  const cursor = ld.collection('kiteinstruments').find(filter);
  let inserted = 0; let updated = 0; let ops = [];
  const flush = async () => { if (ops.length) { const r = await pd.collection('kiteinstruments').bulkWrite(ops, { ordered: false }); inserted += r.upsertedCount; updated += r.modifiedCount; ops = []; } };
  for await (const doc of cursor) {
    const nonPrice = { ...doc }; delete nonPrice._id;
    const seed = {};
    for (const f of PRICE_FIELDS) { if (f in nonPrice) { seed[f] = nonPrice[f]; delete nonPrice[f]; } }
    ops.push({ updateOne: { filter: { instrument_token: doc.instrument_token }, update: { $set: nonPrice, $setOnInsert: { _id: doc._id, ...seed } }, upsert: true } });
    if (ops.length >= 1000) await flush();
  }
  await flush();
  console.log(`contracts: ${inserted} new, ${updated} updated (prices of existing practice contracts untouched)`);
  await P.close(); await L.close();
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
