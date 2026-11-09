'use strict';

// Account transfer end to end (services/accountTransferService.js) on a THROWAWAY
// MongoDB replica set in this PC's memory — never the live database:
//   node scripts/cashEq/runFnoSettlementTestsLocally.js tests/accountTransfer.integration.test.js
// The runner starts mongod on 127.0.0.1 and passes its URI; this file also refuses
// any non-local host and any database not named stkr_xfer_it_*.
//
// The scenario is the 9 Nov 2026 KARAN move: client under BDS82 → RITESH (0/0,
// BDS82's sub-master), with a carried-forward position, 2 pending orders, this
// week's and last week's rejected rows, settled history, and one script whose
// rate is below RITESH's. A control client under BDS82 must never change.

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_xfer_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);

const oid = () => new mongoose.Types.ObjectId();
const ids = {
  server: oid(), admin: oid(),
  harry: oid(), bds: oid(), ritesh: oid(), other: oid(),
  karan: oid(), control: oid(),
};
const CUTOFF = new Date('2026-11-06T22:16:00Z'); // last completed settlement's trade cutoff
const WEEK = new Date('2026-11-09T05:00:00Z'); // a time in the open week

describeIntegration('account transfer on a local MongoDB', () => {
  let service;
  let db;

  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    const host = new URL(process.env.MONGO_URI.replace(/^mongodb(\+srv)?:\/\//, 'http://').split(',')[0]).hostname;
    if (host !== '127.0.0.1' && host !== 'localhost') throw new Error(`Refusing non-local MongoDB host ${host}`);
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_xfer_it_') || mongoose.connection.name === 'stocker') throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    db = mongoose.connection.db;
    // Collections must exist before multi-document transactions write to them.
    for (const c of ['users', 'masters', 'trades', 'brokeragesettings', 'account_transfers', 'settlementruns', 'settlementfences', 'tradewriteleases', 'kiteinstruments', 'comexrates', 'admins', 'adminactions']) {
      await db.createCollection(c).catch(() => {});
    }
    service = require('../src/services/accountTransferService');
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_xfer_it_')) await mongoose.connection.dropDatabase();
    } finally { await mongoose.disconnect(); }
  });

  const master = (id, username, parent, pnl, brk, exchanges, base = 10) => ({
    _id: id, name: username, username, password: 'x', credits: 0, pnl_sharing: pnl, brokerage_sharing: brk,
    exchanges_allowed: exchanges, trade_limit: exchanges, server_id: ids.server, admin_id: ids.admin, master_id: parent,
    status: 'active', active_status: true, deleted_at: null, profit_book_base_minutes: base,
  });
  const user = (id, username, masterId) => ({
    _id: id, name: username, username, password: 'x', credits: 2500000, pnl_sharing: 0, brokerage_sharing: 0,
    exchanges_allowed: [
      { exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G' },
      { exchange_name: 'INDICES', turnover: true, lot: false, group_name: 'G' },
    ],
    trade_limit: [], server_id: ids.server, master_id: masterId, status: 'active', active_status: true, deleted_at: null,
    profit_book_minutes: 10, wallet: { NSE: 30000000, INDEX: 20000000, NSEOPT: 0, MCX: 0, COMEX: 0, GLOBAL: 0 },
  });
  const rate = (owner, ex, script, v, type = 'TURNOVER WISE') => ({ _id: oid(), user_id: owner, exchange_name: ex, script_name: script, type, brk_value: v, deleted_at: null });
  const trade = (userId, masterId, fields) => ({
    _id: oid(), user_id: userId, master_id: masterId, instrument_token: '1001', tradingsymbol: 'GIFTNIFTY26NOVFUT', exchange: 'NFO',
    transaction_type: 'SELL', quantity: 250, price: 24766, order_type: 'MARKET', status: 'completed', executed_quantity: 250,
    executed_price: 24766, deleted_at: null, createdAt: WEEK, updatedAt: WEEK, ...fields,
  });

  async function seed() {
    for (const c of ['users', 'masters', 'trades', 'brokeragesettings', 'account_transfers', 'settlementruns', 'settlementfences', 'tradewriteleases']) await db.collection(c).deleteMany({});
    await db.collection('masters').insertMany([
      master(ids.harry, 'harry', null, 100, 100, ['NFO-FUT', 'GLOBAL']),
      master(ids.bds, 'BDS82', ids.harry, 18, 18, ['NFO-FUT', 'GLOBAL']),
      master(ids.ritesh, 'RITESH', ids.bds, 0, 0, ['NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'GLOBAL']),
      master(ids.other, 'OTHERTOP', null, 50, 50, ['NFO-FUT'], 15),
    ]);
    await db.collection('users').insertMany([user(ids.karan, 'KARAN', ids.bds), user(ids.control, 'CONTROL', ids.bds)]);
    await db.collection('brokeragesettings').insertMany([
      rate(ids.karan, 'NFO-FUT', 'ABC', 6), rate(ids.karan, 'NFO-FUT', 'DEF', 6), rate(ids.karan, 'NFO-FUT', 'EXIDEIND', 1), rate(ids.karan, 'INDICES', 'GIFTNIFTY', 6),
      rate(ids.control, 'NFO-FUT', 'ABC', 6), rate(ids.control, 'NFO-FUT', 'EXIDEIND', 1),
      rate(ids.ritesh, 'NFO-FUT', 'ABC', 2), rate(ids.ritesh, 'NFO-FUT', 'DEF', 2), rate(ids.ritesh, 'NFO-FUT', 'EXIDEIND', 2), rate(ids.ritesh, 'INDICES', 'GIFTNIFTY', 2),
      rate(ids.bds, 'NFO-FUT', 'ABC', 1), rate(ids.bds, 'NFO-FUT', 'DEF', 1), rate(ids.bds, 'NFO-FUT', 'EXIDEIND', 1), rate(ids.bds, 'INDICES', 'GIFTNIFTY', 1),
      rate(ids.harry, 'NFO-FUT', 'ABC', 1), rate(ids.harry, 'NFO-FUT', 'DEF', 1), rate(ids.harry, 'NFO-FUT', 'EXIDEIND', 1), rate(ids.harry, 'INDICES', 'GIFTNIFTY', 1),
      rate(ids.other, 'NFO-FUT', 'ABC', 3),
    ]);
    await db.collection('trades').insertMany([
      // settled history (retired by the last settlement) — never moves
      trade(ids.karan, ids.bds, { createdAt: new Date('2026-11-04T05:00:00Z'), deleted_at: CUTOFF, transaction_type: 'BUY' }),
      trade(ids.karan, ids.bds, { createdAt: new Date('2026-11-05T05:00:00Z'), deleted_at: CUTOFF }),
      // last week's rejected row (not deleted, before the cutoff) — history, never moves
      trade(ids.karan, ids.bds, { status: 'rejected', executed_quantity: 0, createdAt: new Date('2026-11-05T06:00:00Z') }),
      // the open week: carry-forward, 2 pending, 1 rejected
      trade(ids.karan, ids.bds, { trade_type: 'carry_forward', createdAt: new Date('2026-11-06T22:21:04Z') }),
      trade(ids.karan, ids.bds, { status: 'pending', order_type: 'LIMIT', transaction_type: 'BUY', quantity: 150, price: 24825, executed_quantity: 0 }),
      trade(ids.karan, ids.bds, { status: 'pending', order_type: 'LIMIT', transaction_type: 'BUY', quantity: 100, price: 24801, executed_quantity: 0 }),
      trade(ids.karan, ids.bds, { status: 'rejected', executed_quantity: 0 }),
      // control client's open row
      trade(ids.control, ids.bds, { trade_type: 'carry_forward' }),
    ]);
    await db.collection('settlementruns').insertOne({
      _id: oid(), period_key: '2026-11-06', trading_date: new Date('2026-11-06T00:00:00Z'), trade_cutoff_at: CUTOFF,
      price_dates: { nse: new Date('2026-11-06T00:00:00Z'), mcx: new Date('2026-11-06T00:00:00Z') }, status: 'completed',
      completed_at: new Date('2026-11-06T22:30:00Z'), createdAt: new Date('2026-11-06T22:20:00Z'), updatedAt: new Date('2026-11-06T22:30:00Z'),
    });
  }

  const snapshot = async () => ({
    users: await db.collection('users').find({}).sort({ _id: 1 }).toArray(),
    trades: await db.collection('trades').find({}).sort({ _id: 1 }).toArray(),
    rates: await db.collection('brokeragesettings').find({}).sort({ _id: 1 }).toArray(),
    masters: await db.collection('masters').find({}).sort({ _id: 1 }).toArray(),
  });
  const actor = { id: String(ids.admin), username: 'Supervolt' };
  const preview = (to, extra = {}) => service.buildPreview({ userIds: [String(ids.karan)], toMasterId: String(to), ...extra });
  const apply = (p, extra = {}) => service.applyTransfer({
    userIds: [String(ids.karan)], toMasterId: p.to.id, token: p.token, acceptWarnings: true, raiseLowRates: false, confirmUsername: p.to.username, actor, ...extra,
  });

  beforeEach(seed);

  test('preview: no blocks, low-rate warning, exactly the open week moves, money matches the Ledger', async () => {
    const p = await preview(ids.ritesh);
    expect(p.block_count).toBe(0);
    const c = p.clients[0];
    expect(c.from.username).toBe('BDS82');
    expect(c.warnings.map((w) => w.code)).toEqual(['LOW_RATES']);
    expect(c.low_rates).toEqual([expect.objectContaining({ script_name: 'EXIDEIND', client_value: 1, master_value: 2, raise_to: 6 })]);
    expect(c.rows).toEqual(expect.objectContaining({ completed: 1, pending: 2, other: 1, total: 4 }));
    expect(c.rows.open_positions).toEqual([{ symbol: 'GIFTNIFTY26NOVFUT', qty: -250 }]);
    const nfo = c.money.after.brokerage.find((b) => b.segment === 'NFO-FUT');
    expect(nfo.client_rate).toBe(6);
    expect(nfo.levels.map((l) => l.keep)).toEqual([4, 1.18, 0.82, 0]);
    expect(c.money.after.pnl.map((l) => l.pct)).toEqual([0, 18, 82, 0]);
    const before = c.money.before.brokerage.find((b) => b.segment === 'NFO-FUT');
    expect(before.levels.map((l) => l.keep)).toEqual([5.18, 0.82, 0]);
  });

  test('refusals change nothing: wrong code, warnings not accepted, stale preview', async () => {
    const p = await preview(ids.ritesh);
    const before = await snapshot();
    await expect(apply(p, { confirmUsername: 'BDS82' })).rejects.toMatchObject({ status: 400 });
    await expect(apply(p, { acceptWarnings: false })).rejects.toMatchObject({ status: 422 });
    await expect(apply(p, { token: 'x' })).rejects.toMatchObject({ status: 409 });
    // an order placed after the preview
    await db.collection('trades').insertOne(trade(ids.karan, ids.bds, { status: 'pending', order_type: 'LIMIT', executed_quantity: 0 }));
    const changed = await snapshot();
    await expect(apply(p)).rejects.toMatchObject({ status: 409 });
    expect(await snapshot()).toEqual(changed);
    expect(changed.users).toEqual(before.users);
  });

  test('transfer + raise low rates: only his master, his open-week rows and the low rate change; Undo puts it all back', async () => {
    const before = await snapshot();
    const p = await preview(ids.ritesh);
    const { transfer, verification } = await apply(p, { raiseLowRates: true });
    expect(verification.ok).toBe(true);
    const after = await snapshot();

    const karan = after.users.find((u) => String(u._id) === String(ids.karan));
    expect(String(karan.master_id)).toBe(String(ids.ritesh));
    // everything else on the user unchanged
    const strip = (u) => { const { master_id, updatedAt, ...rest } = u; return rest; };
    expect(strip(karan)).toEqual(strip(before.users.find((u) => String(u._id) === String(ids.karan))));
    expect(after.users.find((u) => String(u._id) === String(ids.control))).toEqual(before.users.find((u) => String(u._id) === String(ids.control)));
    expect(after.masters).toEqual(before.masters);

    const moved = new Set(transfer.items[0].moved_rows.map((r) => String(r.trade_id)));
    expect(moved.size).toBe(4);
    for (const t of after.trades) {
      const was = before.trades.find((b) => String(b._id) === String(t._id));
      if (moved.has(String(t._id))) {
        expect(String(t.master_id)).toBe(String(ids.ritesh));
        const { master_id, ...rest } = t; const { master_id: _m, ...wasRest } = was;
        expect(rest).toEqual(wasRest); // only master_id changed — not even updatedAt
      } else {
        expect(t).toEqual(was); // history, last week's rejected row and the control client untouched
      }
    }

    const changedRates = after.rates.filter((r, i) => r.brk_value !== before.rates[i].brk_value);
    expect(changedRates.map((r) => [String(r.user_id), r.script_name, r.brk_value])).toEqual([[String(ids.karan), 'EXIDEIND', 6]]);
    expect(transfer.items[0].rate_changes).toEqual([expect.objectContaining({ script_name: 'EXIDEIND', from_value: 1, to_value: 6 })]);

    // Undo
    await expect(service.undoTransfer({ transferId: transfer._id, confirmUsername: 'BDS82', actor })).rejects.toMatchObject({ status: 400 });
    const u = await service.undoTransfer({ transferId: transfer._id, confirmUsername: 'RITESH', actor });
    expect(u.verification.ok).toBe(true);
    const back = await snapshot();
    expect(back.users.map(strip)).toEqual(before.users.map(strip));
    expect(String(back.users.find((x) => String(x._id) === String(ids.karan)).master_id)).toBe(String(ids.bds));
    expect(back.trades).toEqual(before.trades);
    const strip2 = (r) => { const { effective_from, ...rest } = r; return rest; };
    expect(back.rates.map(strip2)).toEqual(before.rates.map(strip2));
    await expect(service.undoTransfer({ transferId: transfer._id, confirmUsername: 'RITESH', actor })).rejects.toMatchObject({ status: 409 });
    const doc = await db.collection('account_transfers').findOne({ _id: transfer._id });
    expect(doc.status).toBe('undone');
  });

  test('without the tick, rates stay as they are', async () => {
    const before = await snapshot();
    const p = await preview(ids.ritesh);
    await apply(p, { raiseLowRates: false });
    expect((await snapshot()).rates).toEqual(before.rates);
  });

  test('cross-tree move: segment / profit-book / cross-tree are warnings (not blocks) and it goes through', async () => {
    const p = await preview(ids.other);
    expect(p.block_count).toBe(0);
    expect(p.clients[0].warnings.map((w) => w.code).sort()).toEqual(['CROSS_TREE', 'PROFIT_BOOK_BELOW_BASE', 'SEGMENT_NOT_ALLOWED']);
    expect(p.clients[0].warnings.find((w) => w.code === 'SEGMENT_NOT_ALLOWED').segments).toEqual(['INDICES']);
    const { verification } = await apply(p);
    expect(verification.ok).toBe(true);
    const karan = await db.collection('users').findOne({ _id: ids.karan });
    expect(String(karan.master_id)).toBe(String(ids.other));
    expect(karan.profit_book_minutes).toBe(10); // unchanged — only warned
  });

  test('blocks: already there, inactive target, hidden master, settlement running', async () => {
    await db.collection('users').updateOne({ _id: ids.karan }, { $set: { master_id: ids.ritesh } });
    expect((await preview(ids.ritesh)).clients[0].blocks.map((b) => b.code)).toEqual(['ALREADY_UNDER_TARGET']);
    await seed();
    await db.collection('masters').updateOne({ _id: ids.ritesh }, { $set: { active_status: false } });
    expect((await preview(ids.ritesh)).to.blocks.map((b) => b.code)).toEqual(['TARGET_INACTIVE']);
    await seed();
    expect((await preview(ids.ritesh, { hiddenMasterIds: new Set([String(ids.bds)]) })).to.blocks.map((b) => b.code)).toEqual(['TARGET_HIDDEN']);
    await seed();
    await db.collection('settlementfences').insertOne({ _id: 'global', lock_owner: 'test', locked_until: new Date(Date.now() + 600_000) });
    const p = await preview(ids.ritesh);
    expect(p.to.blocks.map((b) => b.code)).toEqual(['SETTLEMENT_RUNNING']);
    await expect(apply(p)).rejects.toMatchObject({ status: 422 });
    expect(String((await db.collection('users').findOne({ _id: ids.karan })).master_id)).toBe(String(ids.bds));
  });

  test('several clients in one transfer: one record, both moved, verified', async () => {
    const p = await service.buildPreview({ userIds: [String(ids.karan), String(ids.control)], toMasterId: String(ids.ritesh) });
    expect(p.block_count).toBe(0);
    const { transfer, verification } = await service.applyTransfer({
      userIds: [String(ids.karan), String(ids.control)], toMasterId: String(ids.ritesh), token: p.token, acceptWarnings: true, raiseLowRates: false, confirmUsername: 'RITESH', actor,
    });
    expect(verification.ok).toBe(true);
    expect(transfer.items.map((i) => i.username).sort()).toEqual(['CONTROL', 'KARAN']);
    expect(transfer.items.find((i) => i.username === 'CONTROL').moved_rows).toHaveLength(1);
    expect(await db.collection('users').countDocuments({ master_id: ids.ritesh })).toBe(2);
  });

  test('an order that lands on the old master right after the commit is swept over and recorded', async () => {
    const p = await preview(ids.ritesh);
    await apply(p);
    const late = trade(ids.karan, ids.bds, { status: 'pending', order_type: 'LIMIT', executed_quantity: 0 });
    await db.collection('trades').insertOne(late);
    const moved = await service._private.sweepLateRows(new Map([[String(ids.karan), String(ids.ritesh)]]), CUTOFF);
    expect(moved.get(String(ids.karan)).map((r) => String(r.trade_id))).toEqual([String(late._id)]);
    expect(String((await db.collection('trades').findOne({ _id: late._id })).master_id)).toBe(String(ids.ritesh));
  });

  describe('HTTP: only admins with ACCOUNT_TRANSFER, never watch-only for changes', () => {
    const jwt = require('jsonwebtoken');
    const express = require('express');
    const request = require('supertest');
    const admins = { superA: oid(), plain: oid(), granted: oid(), watch: oid() };
    let app;
    const tok = (id) => `Bearer ${jwt.sign({ id: String(id), role: 'admin', investor: false }, process.env.JWT_SECRET, { expiresIn: '5m' })}`;

    beforeAll(() => {
      process.env.JWT_SECRET = 'xfer-local-test-secret';
      app = express();
      app.use(express.json());
      app.use('/api/admin', require('../src/routes/adminRoutes'));
    });
    beforeEach(async () => {
      await db.collection('admins').deleteMany({});
      const a = (id, username, extra) => ({ _id: id, username, name: username, password: 'x', active_status: true, deleted_at: null, permissions: [], watch_only: false, is_super_admin: false, hidden_master_ids: [], ...extra });
      await db.collection('admins').insertMany([
        a(admins.superA, 'Supervolt', { is_super_admin: true }),
        a(admins.plain, 'plain', { permissions: ['WALLET_MANAGE'] }),
        a(admins.granted, 'granted', { permissions: ['ACCOUNT_TRANSFER'] }),
        a(admins.watch, 'watch', { permissions: ['ACCOUNT_TRANSFER'], watch_only: true }),
      ]);
    });
    const url = () => `/api/admin/account-transfers/preview?user_ids=${ids.karan}&to_master_id=${ids.ritesh}`;

    test('no token 401; admin without the permission 403; super admin and granted admin see the preview', async () => {
      expect((await request(app).get(url())).status).toBe(401);
      expect((await request(app).get(url()).set('Authorization', tok(admins.plain))).status).toBe(403);
      const s = await request(app).get(url()).set('Authorization', tok(admins.superA));
      expect(s.status).toBe(200);
      expect(s.body.data.clients[0].user.username).toBe('KARAN');
      expect((await request(app).get(url()).set('Authorization', tok(admins.granted))).status).toBe(200);
    });

    test('watch-only can preview but not transfer; a granted admin transfers and it is recorded with his name', async () => {
      const pv = (await request(app).get(url()).set('Authorization', tok(admins.watch))).body.data;
      const body = { user_ids: [String(ids.karan)], to_master_id: String(ids.ritesh), token: pv.token, accept_warnings: true, raise_low_rates: false, confirm_username: 'RITESH' };
      expect((await request(app).post('/api/admin/account-transfers').set('Authorization', tok(admins.watch)).send(body)).status).toBe(403);
      expect(String((await db.collection('users').findOne({ _id: ids.karan })).master_id)).toBe(String(ids.bds));
      const ok = await request(app).post('/api/admin/account-transfers').set('Authorization', tok(admins.granted)).send(body);
      expect(ok.status).toBe(200);
      expect(ok.body.data.verification.ok).toBe(true);
      expect(ok.body.data.transfer.actor_username).toBe('granted');
      const list = await request(app).get('/api/admin/account-transfers').set('Authorization', tok(admins.granted));
      expect(list.body.data.items).toHaveLength(1);
      expect(list.body.data.items[0].can_undo).toBe(true);
      const one = await request(app).get(`/api/admin/account-transfers/${ok.body.data.transfer._id}`).set('Authorization', tok(admins.granted));
      expect(one.body.data.verification.ok).toBe(true);
      const undo = await request(app).post(`/api/admin/account-transfers/${ok.body.data.transfer._id}/undo`).set('Authorization', tok(admins.granted)).send({ confirm_username: 'RITESH' });
      expect(undo.status).toBe(200);
      expect(String((await db.collection('users').findOne({ _id: ids.karan })).master_id)).toBe(String(ids.bds));
    });

    test('a blocked transfer answers 422 with the reasons, and changes nothing', async () => {
      await db.collection('masters').updateOne({ _id: ids.ritesh }, { $set: { status: 'suspended' } });
      const pv = (await request(app).get(url()).set('Authorization', tok(admins.superA))).body.data;
      const res = await request(app).post('/api/admin/account-transfers').set('Authorization', tok(admins.superA))
        .send({ user_ids: [String(ids.karan)], to_master_id: String(ids.ritesh), token: pv.token, accept_warnings: true, confirm_username: 'RITESH' });
      expect(res.status).toBe(422);
      expect(res.body.data.preview.to.blocks.map((b) => b.code)).toEqual(['TARGET_INACTIVE']);
      expect(String((await db.collection('users').findOne({ _id: ids.karan })).master_id)).toBe(String(ids.bds));
    });
  });

  test('no undo after a settlement has started since the transfer', async () => {
    const p = await preview(ids.ritesh);
    const { transfer } = await apply(p);
    await db.collection('settlementruns').insertOne({
      _id: oid(), period_key: '2026-11-13', trading_date: new Date('2026-11-13T00:00:00Z'), trade_cutoff_at: new Date('2026-11-13T22:16:00Z'),
      price_dates: { nse: new Date(), mcx: new Date() }, status: 'completed', createdAt: new Date(Date.now() + 1000), updatedAt: new Date(),
    });
    await expect(service.undoTransfer({ transferId: transfer._id, confirmUsername: 'RITESH', actor })).rejects.toMatchObject({ status: 409 });
    const list = await service.listTransfers({});
    expect(list.items[0].can_undo).toBe(false);
  });
});
