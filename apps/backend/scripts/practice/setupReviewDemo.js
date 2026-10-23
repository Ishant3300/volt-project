'use strict';

/**
 * Demo accounts for App Store review of the VELO trading simulator (practice
 * backend ONLY — refuses to run unless PRACTICE_MODE=1 and the database is the
 * practice one). Re-runnable: existing demo accounts are kept, only missing
 * ones are created. Passwords come from the environment; nothing is printed.
 *
 *   PRACTICE_MODE=1 DEMO_MASTER_PW=… DEMO_ADMIN_PW=… DEMO_CLIENT_PW=… \
 *     node scripts/practice/setupReviewDemo.js
 *
 * Creates:
 *  - master VELODEMO ("Demo Broker") — a normal practice master with a virtual
 *    token wallet to fund its clients; fully usable (create clients, fund, limits).
 *  - clients demo.client1@example.com and demo.client2@example.com under
 *    VELODEMO, made through the practice sign-up (same accounts as any user).
 *  - admin velo_review_admin — watch-only (shared simulation settings can't be
 *    changed) and sees only the VELODEMO tree (every other master is hidden,
 *    so public practice users' details are never shown). No two-factor.
 */
require('dotenv').config();
const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');
const { PRACTICE } = require('../../src/config/practice');
const { ADMIN_PERMISSION_KEYS } = require('../../src/constants/adminPermissions');

const MASTER = 'VELODEMO';
const ADMIN = 'velo_review_admin';
const CLIENTS = ['demo.client1@example.com', 'demo.client2@example.com'];
const MASTER_WALLET = { NSE: 10000000, INDEX: 10000000, NSEOPT: 10000000, MCX: 10000000, COMEX: 0, GLOBAL: 0 };
const API = process.env.PRACTICE_API || 'http://127.0.0.1:3100/api';

async function main() {
  if (!PRACTICE) throw new Error('practice backend only (PRACTICE_MODE=1)');
  const { DEMO_MASTER_PW, DEMO_ADMIN_PW, DEMO_CLIENT_PW } = process.env;
  if (!DEMO_MASTER_PW || !DEMO_ADMIN_PW || !DEMO_CLIENT_PW) throw new Error('set DEMO_MASTER_PW, DEMO_ADMIN_PW, DEMO_CLIENT_PW');

  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  if (!/practice/i.test(db.databaseName)) throw new Error(`refusing: database "${db.databaseName}" is not the practice one`);
  const now = new Date();

  // Master — modelled on the PRACTICE master (same server/admin, exchanges).
  const base = await db.collection('masters').findOne({ username: process.env.PRACTICE_MASTER_USERNAME || 'PRACTICE', deleted_at: null });
  if (!base) throw new Error('PRACTICE master not found');
  let master = await db.collection('masters').findOne({ username: MASTER });
  if (!master) {
    const { _id, username, name, password, createdAt, updatedAt, ...rest } = base;
    await db.collection('masters').insertOne({
      ...rest, username: MASTER, name: 'Demo Broker', password: await bcrypt.hash(DEMO_MASTER_PW, 10),
      wallet: MASTER_WALLET, credits: 0, equity: 0, ledger_balance: 0, createdAt: now, updatedAt: now,
    });
    master = await db.collection('masters').findOne({ username: MASTER });
    console.log('created master', MASTER);
  } else console.log('master exists', MASTER);

  // Clients — through the practice sign-up, then moved under VELODEMO.
  for (const email of CLIENTS) {
    let u = await db.collection('users').findOne({ username: email, deleted_at: null });
    if (!u) {
      const r = await fetch(`${API}/auth/practice-signup`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ name: email.startsWith('demo.client1') ? 'Demo Client One' : 'Demo Client Two', email, password: DEMO_CLIENT_PW, experience: 'new', markets: ['NSE_FUT', 'NSE_OPT', 'MCX'], tokens: 1000000 }),
      });
      if (r.status !== 201) throw new Error(`sign-up ${email}: HTTP ${r.status} ${await r.text()}`);
      u = await db.collection('users').findOne({ username: email, deleted_at: null });
      console.log('created client', email);
    } else console.log('client exists', email);
    if (String(u.master_id) !== String(master._id)) {
      await db.collection('users').updateOne({ _id: u._id }, { $set: { master_id: master._id, updatedAt: now } });
      console.log('moved under', MASTER, email);
    }
  }

  // Admin — watch-only, every master except VELODEMO hidden.
  const hidden = (await db.collection('masters').find({ _id: { $ne: master._id } }).project({ _id: 1 }).toArray()).map((m) => m._id);
  const admin = await db.collection('admins').findOne({ username: ADMIN });
  const adminFields = { is_super_admin: false, watch_only: true, permissions: [...ADMIN_PERMISSION_KEYS], hidden_master_ids: hidden, totp_enabled: false, active_status: true, deleted_at: null, updatedAt: now };
  if (!admin) {
    await db.collection('admins').insertOne({ username: ADMIN, name: 'App Review Admin', password: await bcrypt.hash(DEMO_ADMIN_PW, 10), ...adminFields, createdAt: now });
    console.log('created admin', ADMIN, 'hiding', hidden.length, 'other master(s)');
  } else {
    await db.collection('admins').updateOne({ _id: admin._id }, { $set: adminFields });
    console.log('admin exists — visibility refreshed', ADMIN, 'hiding', hidden.length);
  }
  await mongoose.disconnect();
}

main().catch(async (e) => { console.error('FAILED:', e.message); await mongoose.disconnect().catch(() => {}); process.exit(1); });
