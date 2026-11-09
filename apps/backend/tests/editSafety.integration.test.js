'use strict';

// Server fixes of 9 Nov 2026 (mobile edit audit) end to end, on a THROWAWAY
// MongoDB replica set in this PC's memory — never the live database:
//   node scripts/cashEq/runFnoSettlementTestsLocally.js tests/editSafety.integration.test.js
// Refuses any non-local host and any database not named stkr_edit_it_*.
//
//  A. deleting a script on a MASTER's list stays inside that master (+ his direct clients)
//  B. masters can't create / edit / delete platform default brokerage rows
//  C. a master control toggle pushes down only the control that changed
//  D. watch-only admins can't edit clients / master details; a master can't edit himself via /details
//  E. masters can only read / bulk-create rates for their own tree (+ read their upline)
//  F. a client's group switch is all-or-nothing; an empty group is refused

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_edit_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);

const oid = () => new mongoose.Types.ObjectId();
const ids = {
  server: oid(), superA: oid(), watchA: oid(),
  harry: oid(), bds: oid(), rit: oid(), other: oid(),
  c1: oid(), c2: oid(), cx: oid(),
};

describeIntegration('edit safety fixes on a local MongoDB', () => {
  let db;
  let app;
  let request;
  const jwt = require('jsonwebtoken');
  const tok = (id, role) => `Bearer ${jwt.sign({ id: String(id), role, investor: false }, process.env.JWT_SECRET, { expiresIn: '5m' })}`;
  const asSuper = () => tok(ids.superA, 'admin');
  const asWatch = () => tok(ids.watchA, 'admin');
  const asMaster = (id) => tok(id, 'master');

  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    const host = new URL(process.env.MONGO_URI.replace(/^mongodb(\+srv)?:\/\//, 'http://').split(',')[0]).hostname;
    if (host !== '127.0.0.1' && host !== 'localhost') throw new Error(`Refusing non-local MongoDB host ${host}`);
    process.env.JWT_SECRET = 'edit-safety-local-test-secret';
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_edit_it_') || mongoose.connection.name === 'stocker') throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    db = mongoose.connection.db;
    for (const c of ['users', 'masters', 'admins', 'servers', 'trades', 'brokeragesettings', 'scriptquantities', 'groupedquantities', 'kiteinstruments', 'settlementruns', 'settlementfences', 'tradewriteleases', 'transactions', 'adminactions']) {
      await db.createCollection(c).catch(() => {});
    }
    await require('../src/models/ScriptQuantity').syncIndexes(); // the unique (owner, exchange, script) index
    const express = require('express');
    request = require('supertest');
    app = express();
    app.use(express.json());
    app.use('/api/admin', require('../src/routes/adminRoutes'));
    app.use('/api/masters', require('../src/routes/masterRoutes'));
    app.use('/api/master', require('../src/routes/masterFlowRoutes'));
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_edit_it_')) await mongoose.connection.dropDatabase();
    } finally { await mongoose.disconnect(); }
  });

  const perms = (extra = {}) => ({
    account_summary: true, pnl_summary: true, client_summary: true, settlement_report: true, generate_pdf: true, weekly_admin: true,
    intraday_history: true, userwise_open_position: true, script_quantity: true, deleted_trade: true, trade_account: true,
    close_only: false, bet: false, margin_square: false, fresh_stoploss: false, ...extra,
  });
  const master = (id, username, parent, extra = {}) => ({
    _id: id, name: username, username, password: 'x', credits: 0, pnl_sharing: 50, brokerage_sharing: 50,
    exchanges_allowed: ['NFO-FUT', 'GLOBAL'], trade_limit: ['NFO-FUT'], server_id: ids.server, admin_id: ids.superA, master_id: parent,
    status: 'active', active_status: true, deleted_at: null, permissions: perms(), profit_book_base_minutes: 0, equity: 0,
    script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'G1' }], createdAt: new Date(), updatedAt: new Date(), ...extra,
  });
  const user = (id, username, m, extra = {}) => ({
    _id: id, name: username, username, password: 'x', credits: 1000, pnl_sharing: 0, brokerage_sharing: 0,
    exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G1' }], trade_limit: ['NFO-FUT'],
    server_id: ids.server, master_id: m, status: 'active', active_status: true, deleted_at: null, profit_book_minutes: 10,
    close_only: false, bet: false, margin_square_off: false, createdAt: new Date(), updatedAt: new Date(), ...extra,
  });
  const sq = (owner, type, script, max = 10) => ({ _id: oid(), owner_id: owner, owner_type: type, exchange_name: 'NFO-FUT', script_name: script, lot_size: 1, max_qty: max, brk_qty: 5, deleted_at: null, createdAt: new Date(), updatedAt: new Date() });
  const rate = (owner, script, v) => ({ _id: oid(), user_id: owner, exchange_name: 'NFO-FUT', script_name: script, type: 'TURNOVER WISE', brk_value: v, deleted_at: null });
  const gq = (lot, script, max = 20) => ({ _id: oid(), lot_name: lot, exchange_name: 'NFO-FUT', raw_name: script, lot_size: 1, max_qty: max, break_qty: 10, deleted_at: null, createdAt: new Date(), updatedAt: new Date() });

  beforeEach(async () => {
    for (const c of ['users', 'masters', 'admins', 'servers', 'brokeragesettings', 'scriptquantities', 'groupedquantities', 'kiteinstruments', 'settlementfences', 'tradewriteleases']) await db.collection(c).deleteMany({});
    await db.collection('servers').insertOne({ _id: ids.server, name: 'WealthX' });
    const a = (id, username, extra) => ({ _id: id, username, name: username, password: 'x', active_status: true, deleted_at: null, permissions: [], watch_only: false, is_super_admin: false, hidden_master_ids: [], ...extra });
    await db.collection('admins').insertMany([a(ids.superA, 'Supervolt', { is_super_admin: true }), a(ids.watchA, 'watcher', { watch_only: true, permissions: ['MASTER_EDIT_ANY', 'BROKERAGE_MANAGE', 'QUANTITY_MANAGE'] })]);
    await db.collection('masters').insertMany([
      master(ids.harry, 'harry', null), master(ids.bds, 'BDS82', ids.harry), master(ids.rit, 'RITESH', ids.bds), master(ids.other, 'OTHER', null),
    ]);
    await db.collection('users').insertMany([
      user(ids.c1, 'C1', ids.bds, { close_only: true }), user(ids.c2, 'C2', ids.bds), user(ids.cx, 'CX', ids.other),
    ]);
    await db.collection('scriptquantities').insertMany([
      sq(ids.bds, 'Master', 'RELIANCE'), sq(ids.c1, 'User', 'RELIANCE'), sq(ids.c2, 'User', 'RELIANCE'),
      sq(ids.other, 'Master', 'RELIANCE'), sq(ids.cx, 'User', 'RELIANCE'),
      sq(ids.c1, 'User', 'ABC', 7), sq(ids.c1, 'User', 'DEF', 7),
    ]);
    await db.collection('brokeragesettings').insertMany([
      rate(null, 'ABC', 2), rate(ids.harry, 'ABC', 1), rate(ids.bds, 'ABC', 1), rate(ids.c1, 'ABC', 6), rate(ids.cx, 'ABC', 6), rate(ids.other, 'ABC', 1),
    ]);
    await db.collection('groupedquantities').insertMany([
      gq('G1', 'ABC'), gq('G1', 'DEF'),
      gq('G2', 'ABC', 50), gq('G2', 'DEF', 50), gq('G2', 'GHI', 50),
      gq('GDUP', 'ABC'), gq('GDUP', 'ABC'), // a broken group: the same script twice → the insert fails
    ]);
    await db.collection('kiteinstruments').insertMany(['ABC', 'DEF', 'GHI', 'RELIANCE'].map((s, i) => ({ _id: oid(), instrument_token: String(9000 + i), tradingsymbol: `${s}26NOVFUT`, name: s, raw_name: s, segment: 'NFO-FUT', exchange: 'NFO', is_active: true, enabled: true, lot_size: 1 })));
  });

  const sqRows = (owner, script) => db.collection('scriptquantities').find({ owner_id: owner, script_name: script, deleted_at: null }).toArray();
  const userDoc = (id) => db.collection('users').findOne({ _id: id });

  // ── A
  test('A: admin deleting a script on a MASTER list touches only that master + his clients', async () => {
    const row = (await sqRows(ids.bds, 'RELIANCE'))[0];
    const res = await request(app).delete(`/api/admin/script-quantities/${row._id}`).set('Authorization', asSuper());
    expect(res.status).toBe(200);
    expect(await sqRows(ids.bds, 'RELIANCE')).toHaveLength(0);
    // his direct client keeps his own limit: a master's ordinary (non-0) row
    // never reaches clients — same rule as joining a group (server batch 2)
    expect(await sqRows(ids.c1, 'RELIANCE')).toHaveLength(1);
    // another master of the same admin and his client keep their limit
    expect(await sqRows(ids.other, 'RELIANCE')).toHaveLength(1);
    expect(await sqRows(ids.cx, 'RELIANCE')).toHaveLength(1);
  });

  // ── B
  test('B: masters are refused on platform default rows (create / edit / delete); admin is not', async () => {
    const global = await db.collection('brokeragesettings').findOne({ user_id: null });
    const create = await request(app).post('/api/admin/brokerage-settings').set('Authorization', asMaster(ids.bds)).send({ type: 'TURNOVER WISE', exchange_name: 'NFO-FUT', script_name: 'ZZZ', brk_value: 9 });
    expect(create.status).toBe(403);
    expect((await request(app).put(`/api/admin/brokerage-settings/${global._id}`).set('Authorization', asMaster(ids.bds)).send({ brk_value: 9 })).status).toBe(403);
    expect((await request(app).delete(`/api/admin/brokerage-settings/${global._id}`).set('Authorization', asMaster(ids.bds))).status).toBe(403);
    const after = await db.collection('brokeragesettings').findOne({ _id: global._id });
    expect(after.brk_value).toBe(2);
    expect(after.deleted_at).toBeNull();
    expect(await db.collection('brokeragesettings').countDocuments({ user_id: null, script_name: 'ZZZ' })).toBe(0);
    // admin still can
    expect((await request(app).put(`/api/admin/brokerage-settings/${global._id}`).set('Authorization', asSuper()).send({ brk_value: 3 })).status).toBe(200);
    // a master on his own client's row still works
    const c1row = await db.collection('brokeragesettings').findOne({ user_id: ids.c1 });
    expect((await request(app).put(`/api/admin/brokerage-settings/${c1row._id}`).set('Authorization', asMaster(ids.bds)).send({ brk_value: 7 })).status).toBe(200);
  });

  // ── C
  test('C: toggling one control pushes down only that control', async () => {
    // Fresh Stop-Loss only (the app sends all four controls with their current values)
    let res = await request(app).put(`/api/masters/${ids.bds}/permissions`).set('Authorization', asSuper()).send({ permissions: perms({ fresh_stoploss: true }) });
    expect(res.status).toBe(200);
    expect((await userDoc(ids.c1)).close_only).toBe(true); // his own setting kept
    expect((await userDoc(ids.c2)).close_only).toBe(false);
    // Close Only really changes → pushed to every direct client
    res = await request(app).put(`/api/masters/${ids.bds}/permissions`).set('Authorization', asSuper()).send({ permissions: perms({ fresh_stoploss: true, close_only: true }) });
    expect(res.status).toBe(200);
    expect((await userDoc(ids.c1)).close_only).toBe(true);
    expect((await userDoc(ids.c2)).close_only).toBe(true);
    // a client set individually afterwards survives the next unrelated toggle
    await db.collection('users').updateOne({ _id: ids.c2 }, { $set: { close_only: false, bet: true } });
    res = await request(app).put(`/api/masters/${ids.bds}/permissions`).set('Authorization', asSuper()).send({ permissions: perms({ fresh_stoploss: false, close_only: true }) });
    expect(res.status).toBe(200);
    expect((await userDoc(ids.c2)).close_only).toBe(false);
    expect((await userDoc(ids.c2)).bet).toBe(true);
    // other master's client never touched
    expect((await userDoc(ids.cx)).close_only).toBe(false);
  });

  // ── D
  test('D: watch-only admin cannot edit a client or master details; a master cannot edit himself via /details', async () => {
    expect((await request(app).put(`/api/master/users/${ids.c1}`).set('Authorization', asWatch()).send({ note: 'x' })).status).toBe(403);
    expect((await request(app).put(`/api/master/users/${ids.c1}/details`).set('Authorization', asWatch()).send({ note: 'x' })).status).toBe(403);
    expect((await request(app).put(`/api/master/masters/${ids.rit}/details`).set('Authorization', asWatch()).send({ note: 'x' })).status).toBe(403);
    expect((await request(app).put(`/api/master/masters/${ids.bds}/details`).set('Authorization', asMaster(ids.bds)).send({ note: 'self' })).status).toBe(403);
    // still allowed: a master editing his sub-master, and his client
    expect((await request(app).put(`/api/master/masters/${ids.rit}/details`).set('Authorization', asMaster(ids.bds)).send({ note: 'ok' })).status).toBe(200);
    expect((await request(app).put(`/api/master/users/${ids.c1}`).set('Authorization', asMaster(ids.bds)).send({ note: 'ok' })).status).toBe(200);
  });

  // ── E
  test('E: masters read / bulk-create rates only for their tree (+ read their upline)', async () => {
    const get = (who, uid) => request(app).get(`/api/admin/brokerage-settings/exchange/NFO-FUT?type=TURNOVER%20WISE&limit=2000&user_id=${uid}`).set('Authorization', asMaster(who));
    expect((await get(ids.bds, ids.c1)).status).toBe(200); // own client
    expect((await get(ids.bds, ids.rit)).status).toBe(200); // own sub-master
    expect((await get(ids.bds, ids.bds)).status).toBe(200); // himself
    expect((await get(ids.bds, ids.harry)).status).toBe(200); // his parent (upline)
    expect((await get(ids.bds, ids.cx)).status).toBe(403); // another tree's client
    expect((await get(ids.bds, ids.other)).status).toBe(403); // another tree's master
    expect((await request(app).get('/api/admin/brokerage-settings/exchange/NFO-FUT?type=TURNOVER%20WISE').set('Authorization', asMaster(ids.bds))).status).toBe(200); // platform defaults still readable
    const create = (who, uid) => request(app).post('/api/admin/brokerage-settings/bulk-create').set('Authorization', asMaster(who)).send({ exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', default_brk_value: 6, user_id: String(uid) });
    expect((await create(ids.bds, ids.cx)).status).toBe(403);
    expect(await db.collection('brokeragesettings').countDocuments({ user_id: ids.cx })).toBe(1);
    expect((await create(ids.bds, ids.c2)).status).toBe(201);
  });

  // ── F
  test('F1: switching to a group with no scripts is refused and nothing changes', async () => {
    const before = await userDoc(ids.c1);
    const res = await request(app).put(`/api/master/users/${ids.c1}`).set('Authorization', asSuper())
      .send({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'EMPTY' }] });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/no scripts/);
    expect((await userDoc(ids.c1)).exchanges_allowed[0].group_name).toBe('G1');
    expect((await userDoc(ids.c1)).updatedAt).toEqual(before.updatedAt);
    expect(await sqRows(ids.c1, 'ABC')).toHaveLength(1);
  });

  test('F2: a good switch replaces the limits; a failing switch keeps the old limits and the old group (409)', async () => {
    let res = await request(app).put(`/api/master/users/${ids.c1}`).set('Authorization', asSuper())
      .send({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G2' }] });
    expect(res.status).toBe(200);
    expect((await sqRows(ids.c1, 'ABC'))[0].max_qty).toBe(50);
    expect(await sqRows(ids.c1, 'GHI')).toHaveLength(1);

    // GDUP lists ABC twice → the insert fails inside the transaction → nothing changes
    res = await request(app).put(`/api/master/users/${ids.c1}`).set('Authorization', asSuper())
      .send({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'GDUP' }] });
    expect(res.status).toBe(409);
    expect(res.body.message).toMatch(/previous group and limits kept/);
    expect((await userDoc(ids.c1)).exchanges_allowed[0].group_name).toBe('G2');
    expect((await sqRows(ids.c1, 'ABC'))[0].max_qty).toBe(50);
    expect(await sqRows(ids.c1, 'GHI')).toHaveLength(1);
    // exactly G2's rows survive the failed switch: ABC, DEF, GHI (a switch replaces the whole exchange with the group's scripts)
    expect(await db.collection('scriptquantities').countDocuments({ owner_id: ids.c1, exchange_name: 'NFO-FUT', deleted_at: null })).toBe(3);
  });

  test('F3: the admin edit route (PUT /api/admin/users/:id) has the same protection', async () => {
    let res = await request(app).put(`/api/admin/users/${ids.c1}`).set('Authorization', asSuper())
      .send({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'EMPTY' }] });
    expect(res.status).toBe(400);
    res = await request(app).put(`/api/admin/users/${ids.c1}`).set('Authorization', asSuper())
      .send({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'GDUP' }] });
    expect(res.status).toBe(409);
    expect((await userDoc(ids.c1)).exchanges_allowed[0].group_name).toBe('G1');
    expect((await sqRows(ids.c1, 'ABC'))[0].max_qty).toBe(7);
  });

  test('F4: a failed switch on a NEWLY added exchange leaves that exchange switched off (never open without limits)', async () => {
    await db.collection('groupedquantities').insertMany([
      { _id: oid(), lot_name: 'GX', exchange_name: 'NFO-OPT', raw_name: 'NIFTY', lot_size: 1, max_qty: 5, break_qty: 2, deleted_at: null },
      { _id: oid(), lot_name: 'GX', exchange_name: 'NFO-OPT', raw_name: 'NIFTY', lot_size: 1, max_qty: 5, break_qty: 2, deleted_at: null },
    ]);
    const res = await request(app).put(`/api/master/users/${ids.c1}`).set('Authorization', asSuper()).send({ exchanges_allowed: [
      { exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G1' },
      { exchange_name: 'NFO-OPT', turnover: false, lot: true, group_name: 'GX' },
    ] });
    expect(res.status).toBe(409);
    expect(res.body.message).toMatch(/left switched off/);
    const opt = (await userDoc(ids.c1)).exchanges_allowed.find((e) => e.exchange_name === 'NFO-OPT');
    expect(opt.turnover).toBe(false);
    expect(opt.lot).toBe(false);
    expect(await db.collection('scriptquantities').countDocuments({ owner_id: ids.c1, exchange_name: 'NFO-OPT', deleted_at: null })).toBe(0);
  });
});
