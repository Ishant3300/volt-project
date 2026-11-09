'use strict';

// Server batch 2 of 9 Nov 2026 (mobile edit audit) end to end, on a THROWAWAY
// MongoDB replica set in this PC's memory — never the live database:
//   node scripts/cashEq/runFnoSettlementTestsLocally.js tests/editSafetyBatch2.integration.test.js
// Refuses any non-local host and any database not named stkr_edit2_it_*.
//
// The owner's rule for every script-limit path: "same rule as joining the
// group" — a client's limits come from his group; from his master he takes
// only BLOCKS (max 0). A group edit still sets everyone on the group (the
// owner's way to lower a limit for all), except where a master blocked it.

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_edit2_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);

const oid = () => new mongoose.Types.ObjectId();
const ids = {
  server: oid(), superA: oid(),
  harry: oid(), bds: oid(), rit: oid(), other: oid(),
  c1: oid(), c2: oid(), c3: oid(), cx: oid(),
};

describeIntegration('edit safety batch 2 on a local MongoDB', () => {
  let db;
  let app;
  let request;
  const jwt = require('jsonwebtoken');
  const tok = (id, role) => `Bearer ${jwt.sign({ id: String(id), role, investor: false }, process.env.JWT_SECRET, { expiresIn: '5m' })}`;
  const asSuper = () => tok(ids.superA, 'admin');
  const asMaster = (id) => tok(id, 'master');

  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    const host = new URL(process.env.MONGO_URI.replace(/^mongodb(\+srv)?:\/\//, 'http://').split(',')[0]).hostname;
    if (host !== '127.0.0.1' && host !== 'localhost') throw new Error(`Refusing non-local MongoDB host ${host}`);
    process.env.JWT_SECRET = 'edit-safety-2-local-test-secret';
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_edit2_it_') || mongoose.connection.name === 'stocker') throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    db = mongoose.connection.db;
    for (const c of ['users', 'masters', 'admins', 'servers', 'trades', 'brokeragesettings', 'scriptquantities', 'groupedquantities', 'kiteinstruments', 'settlementruns', 'settlementfences', 'tradewriteleases', 'transactions', 'adminactions']) {
      await db.createCollection(c).catch(() => {});
    }
    await require('../src/models/ScriptQuantity').syncIndexes();
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
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_edit2_it_')) await mongoose.connection.dropDatabase();
    } finally { await mongoose.disconnect(); }
  });

  const perms = () => ({
    account_summary: true, pnl_summary: true, client_summary: true, settlement_report: true, generate_pdf: true, weekly_admin: true,
    intraday_history: true, userwise_open_position: true, script_quantity: true, deleted_trade: true, trade_account: true,
    close_only: false, bet: false, margin_square: false, fresh_stoploss: false,
  });
  const master = (id, username, parent, group, extra = {}) => ({
    _id: id, name: username, username, password: 'x', credits: 0, pnl_sharing: 50, brokerage_sharing: 50,
    exchanges_allowed: ['NFO-FUT'], trade_limit: ['NFO-FUT'], server_id: ids.server, admin_id: ids.superA, master_id: parent,
    status: 'active', active_status: true, deleted_at: null, permissions: perms(), profit_book_base_minutes: 0, equity: 0,
    script_quantity_groups: group ? [{ exchange_name: 'NFO-FUT', group_name: group }] : [], createdAt: new Date(), updatedAt: new Date(), ...extra,
  });
  const user = (id, username, m, group, extra = {}) => ({
    _id: id, name: username, username, password: 'x', credits: 1000, pnl_sharing: 0, brokerage_sharing: 0,
    exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: group }], trade_limit: ['NFO-FUT'],
    server_id: ids.server, master_id: m, status: 'active', active_status: true, deleted_at: null, profit_book_minutes: 10,
    close_only: false, bet: false, margin_square_off: false, createdAt: new Date(), updatedAt: new Date(), ...extra,
  });
  const sq = (owner, type, script, max) => ({ _id: oid(), owner_id: owner, owner_type: type, exchange_name: 'NFO-FUT', script_name: script, lot_size: 1, max_qty: max, brk_qty: max, deleted_at: null, createdAt: new Date(), updatedAt: new Date() });
  const gq = (lot, script, max) => ({ _id: oid(), lot_name: lot, exchange_name: 'NFO-FUT', raw_name: script, lot_size: 1, max_qty: max, break_qty: max, deleted_at: null, createdAt: new Date(), updatedAt: new Date() });
  const rate = (owner, script, v) => ({ _id: oid(), user_id: owner, exchange_name: 'NFO-FUT', script_name: script, type: 'TURNOVER WISE', brk_value: v, deleted_at: null });

  beforeEach(async () => {
    for (const c of ['users', 'masters', 'admins', 'servers', 'brokeragesettings', 'scriptquantities', 'groupedquantities', 'kiteinstruments']) await db.collection(c).deleteMany({});
    await db.collection('servers').insertOne({ _id: ids.server, name: 'WealthX' });
    await db.collection('admins').insertOne({ _id: ids.superA, username: 'Supervolt', name: 'Supervolt', password: 'x', active_status: true, deleted_at: null, permissions: [], watch_only: false, is_super_admin: true, hidden_master_ids: [] });
    await db.collection('masters').insertMany([
      master(ids.harry, 'harry', null, 'G1'), master(ids.bds, 'BDS82', ids.harry, 'G1'),
      master(ids.rit, 'RITESH', ids.bds, 'G1'), master(ids.other, 'OTHER', null, 'G1'),
    ]);
    await db.collection('users').insertMany([
      user(ids.c1, 'C1', ids.bds, 'G1'), user(ids.c2, 'C2', ids.bds, 'G1'),
      user(ids.c3, 'C3', ids.rit, 'G2'), user(ids.cx, 'CX', ids.other, 'G1'),
    ]);
    await db.collection('groupedquantities').insertMany([
      gq('G1', 'ABC', 20), gq('G1', 'DEF', 20),
      gq('G2', 'ABC', 50), gq('G2', 'DEF', 50), gq('G2', 'GHI', 50),
      gq('GDUP', 'ABC', 5), gq('GDUP', 'ABC', 5), // broken group: the same script twice → insert fails
    ]);
    await db.collection('scriptquantities').insertMany([
      // BDS82 has his OWN block on DEF; his clients carry it
      sq(ids.bds, 'Master', 'ABC', 20), sq(ids.bds, 'Master', 'DEF', 0),
      sq(ids.rit, 'Master', 'ABC', 20), sq(ids.rit, 'Master', 'DEF', 20),
      sq(ids.other, 'Master', 'ABC', 20), sq(ids.other, 'Master', 'DEF', 20),
      sq(ids.c1, 'User', 'ABC', 20), sq(ids.c1, 'User', 'DEF', 0),
      sq(ids.c2, 'User', 'ABC', 15), sq(ids.c2, 'User', 'DEF', 0),
      sq(ids.c3, 'User', 'ABC', 50), sq(ids.c3, 'User', 'DEF', 50), sq(ids.c3, 'User', 'GHI', 50),
      sq(ids.cx, 'User', 'ABC', 20), sq(ids.cx, 'User', 'DEF', 20),
    ]);
    await db.collection('kiteinstruments').insertMany(['ABC', 'DEF', 'GHI', 'RELIANCE'].map((s, i) => ({ _id: oid(), instrument_token: String(9000 + i), tradingsymbol: `${s}26NOVFUT`, name: s, raw_name: s, segment: 'NFO-FUT', exchange: 'NFO', is_active: true, enabled: true, lot_size: 1 })));
  });

  const maxOf = async (owner, script) => {
    const rows = await db.collection('scriptquantities').find({ owner_id: owner, script_name: script, deleted_at: null }).toArray();
    if (rows.length > 1) throw new Error(`duplicate live rows for ${owner} ${script}`);
    return rows.length ? rows[0].max_qty : null; // null = no row (no limit)
  };
  const groupRow = (lot, script) => db.collection('groupedquantities').findOne({ lot_name: lot, raw_name: script, deleted_at: null });

  // ── 1. group edit: everyone on it, except where the client's master (or the master himself) blocked it
  test('group edit sets every member but keeps master blocks (client and master)', async () => {
    let res = await request(app).put(`/api/admin/grouped-quantities/${(await groupRow('G1', 'DEF'))._id}`).set('Authorization', asSuper()).send({ max_qty: 10, break_qty: 10 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'DEF')).toBe(0); // BDS82 blocks DEF
    expect(await maxOf(ids.c2, 'DEF')).toBe(0);
    expect(await maxOf(ids.bds, 'DEF')).toBe(0); // his own block kept
    expect(await maxOf(ids.cx, 'DEF')).toBe(10);
    expect(await maxOf(ids.rit, 'DEF')).toBe(10);
    expect(await maxOf(ids.other, 'DEF')).toBe(10);
    expect(await maxOf(ids.c3, 'DEF')).toBe(50); // other group untouched

    // lowering ABC reaches everyone on G1, also a client set lower/higher by hand (intended)
    res = await request(app).put(`/api/admin/grouped-quantities/${(await groupRow('G1', 'ABC'))._id}`).set('Authorization', asSuper()).send({ max_qty: 5, break_qty: 5 });
    expect(res.status).toBe(200);
    for (const who of [ids.c1, ids.c2, ids.cx, ids.bds, ids.rit, ids.other]) expect(await maxOf(who, 'ABC')).toBe(5);
  });

  test('group edit that unblocks a script the GROUP had blocked for a master reaches his clients on other groups', async () => {
    await db.collection('groupedquantities').insertOne(gq('G1', 'GHI', 0));
    await db.collection('scriptquantities').insertMany([sq(ids.rit, 'Master', 'GHI', 0)]);
    await db.collection('scriptquantities').updateOne({ owner_id: ids.c3, script_name: 'GHI' }, { $set: { max_qty: 0, brk_qty: 0 } });
    const res = await request(app).put(`/api/admin/grouped-quantities/${(await groupRow('G1', 'GHI'))._id}`).set('Authorization', asSuper()).send({ max_qty: 30, break_qty: 30 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.rit, 'GHI')).toBe(30); // the 0 came from the group — not his own block
    expect(await maxOf(ids.c3, 'GHI')).toBe(50); // RITESH's client (on G2) back to G2's value
    expect(await maxOf(ids.c1, 'GHI')).toBe(30); // G1 members get the script
  });

  test('a new script added to a group: own blocks kept, members get it', async () => {
    await db.collection('scriptquantities').insertOne(sq(ids.other, 'Master', 'GHI', 0)); // OTHER blocked GHI himself
    const res = await request(app).post('/api/admin/grouped-quantities').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', lot_name: 'G1', raw_name: 'GHI', max_qty: 40, break_qty: 40, lot_size: 1 });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.other, 'GHI')).toBe(0);
    expect(await maxOf(ids.cx, 'GHI')).toBe(0); // OTHER's client: blocked by his master
    expect(await maxOf(ids.c1, 'GHI')).toBe(40);
    expect(await maxOf(ids.bds, 'GHI')).toBe(40);
  });

  // ── 2. a script removed from a group
  test('removing a script from a group removes the group row; blocks stay', async () => {
    const res = await request(app).delete(`/api/admin/grouped-quantities/${(await groupRow('G1', 'DEF'))._id}`).set('Authorization', asSuper());
    expect(res.status).toBe(200);
    expect(await maxOf(ids.cx, 'DEF')).toBeNull();
    expect(await maxOf(ids.rit, 'DEF')).toBeNull();
    expect(await maxOf(ids.other, 'DEF')).toBeNull();
    expect(await maxOf(ids.bds, 'DEF')).toBe(0); // his own block
    expect(await maxOf(ids.c1, 'DEF')).toBe(0); // blocked by BDS82
    expect(await maxOf(ids.c3, 'DEF')).toBe(50); // G2 untouched
  });

  // ── 3. a master's own row: only blocks reach his clients
  test('master row: a non-block change leaves clients; block / unblock follow the joining rule', async () => {
    const abc = await db.collection('scriptquantities').findOne({ owner_id: ids.bds, script_name: 'ABC' });
    let res = await request(app).put(`/api/admin/script-quantities/${abc._id}`).set('Authorization', asSuper()).send({ max_qty: 7 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'ABC')).toBe(20);
    expect(await maxOf(ids.c2, 'ABC')).toBe(15);

    res = await request(app).put(`/api/admin/script-quantities/${abc._id}`).set('Authorization', asSuper()).send({ max_qty: 0 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'ABC')).toBe(0);
    expect(await maxOf(ids.c2, 'ABC')).toBe(0);
    expect(await maxOf(ids.cx, 'ABC')).toBe(20); // another master's client

    res = await request(app).put(`/api/admin/script-quantities/${abc._id}`).set('Authorization', asSuper()).send({ max_qty: 9 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'ABC')).toBe(20); // back to G1's value, like joining
    expect(await maxOf(ids.c2, 'ABC')).toBe(20);

    // deleting his DEF block: clients back to the group's value
    const def = await db.collection('scriptquantities').findOne({ owner_id: ids.bds, script_name: 'DEF', deleted_at: null });
    res = await request(app).delete(`/api/admin/script-quantities/${def._id}`).set('Authorization', asSuper());
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'DEF')).toBe(20);
    expect(await maxOf(ids.c2, 'DEF')).toBe(20);

    // deleting an ordinary row: clients keep their group limit (no row = no limit was the old result)
    res = await request(app).delete(`/api/admin/script-quantities/${abc._id}`).set('Authorization', asSuper());
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'ABC')).toBe(20);
  });

  test('master row created as a block (single create) blocks his clients; an unblock of a script their group lacks removes the 0', async () => {
    let res = await request(app).post('/api/admin/script-quantities').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', script_name: 'GHI', lot_size: 1, max_qty: 0, brk_qty: 0, owner_id: String(ids.bds), owner_type: 'Master' });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.c1, 'GHI')).toBe(0);
    res = await request(app).post('/api/admin/script-quantities').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', script_name: 'GHI', lot_size: 1, max_qty: 30, brk_qty: 30, owner_id: String(ids.bds), owner_type: 'Master' });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.c1, 'GHI')).toBeNull(); // G1 has no GHI — exactly what joining gives
  });

  // ── 4. admin platform rows fill only what's missing
  test('admin create fills accounts with no row and never overwrites a limit', async () => {
    let res = await request(app).post('/api/admin/script-quantities').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', script_name: 'ABC', lot_size: 1, max_qty: 1, brk_qty: 1 });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.c1, 'ABC')).toBe(20);
    expect(await maxOf(ids.c2, 'ABC')).toBe(15);
    expect(await maxOf(ids.bds, 'ABC')).toBe(20);
    res = await request(app).post('/api/admin/script-quantities').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', script_name: 'RELIANCE', lot_size: 1, max_qty: 3, brk_qty: 3 });
    expect(res.status).toBe(201);
    for (const who of [ids.c1, ids.c3, ids.cx, ids.bds, ids.other]) expect(await maxOf(who, 'RELIANCE')).toBe(3);
  });

  // ── 5. bulk group create under an existing name
  test('bulk-creating a group under an existing name keeps its existing values', async () => {
    const res = await request(app).post('/api/admin/grouped-quantities/bulk-create').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', lot_name: 'G1', default_max_qty: 1, default_break_qty: 1 });
    expect([200, 201]).toContain(res.status);
    expect((await groupRow('G1', 'ABC')).max_qty).toBe(20);
    expect((await groupRow('G1', 'DEF')).max_qty).toBe(20);
    expect((await groupRow('G1', 'GHI')).max_qty).toBe(1);
  });

  // ── 6. bulk script create by a master
  test('master bulk create: every script checked, existing limits kept, a 0 default blocks his clients for NEW scripts only', async () => {
    await db.collection('scriptquantities').insertMany(['ABC', 'DEF', 'GHI', 'RELIANCE'].map((s) => sq(ids.superA, 'Admin', s, 100)));
    // RITESH (sub-master on G1): G1 lacks GHI/RELIANCE → refused (same as single create)
    let res = await request(app).post('/api/admin/script-quantities/bulk-create').set('Authorization', asMaster(ids.bds))
      .send({ exchange_name: 'NFO-FUT', default_max_qty: 0, default_brk_qty: 0, owner_id: String(ids.rit), owner_type: 'Master' });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/GHI|RELIANCE/);
    // for himself (admin ceiling 100 everywhere): allowed
    res = await request(app).post('/api/admin/script-quantities/bulk-create').set('Authorization', asMaster(ids.bds))
      .send({ exchange_name: 'NFO-FUT', default_max_qty: 0, default_brk_qty: 0 });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.bds, 'ABC')).toBe(20); // existing kept
    expect(await maxOf(ids.bds, 'GHI')).toBe(0);
    expect(await maxOf(ids.c1, 'GHI')).toBe(0); // new block reaches his clients
    expect(await maxOf(ids.c1, 'ABC')).toBe(20); // untouched
    // above the ceiling for one script → refused, nothing written
    await db.collection('scriptquantities').updateOne({ owner_type: 'Admin', script_name: 'RELIANCE' }, { $set: { max_qty: 2 } });
    res = await request(app).post('/api/admin/script-quantities/bulk-create').set('Authorization', asMaster(ids.bds))
      .send({ exchange_name: 'NFO-FUT', default_max_qty: 5, default_brk_qty: 5 });
    expect(res.status).toBe(400);
    expect(res.body.message).toMatch(/RELIANCE \(limit 2\)/);
  });

  // ── 6b. admin list prefers the Admin row
  test('the de-duplicated list shows the Admin row, not a master row', async () => {
    await db.collection('scriptquantities').insertOne(sq(ids.superA, 'Admin', 'ABC', 99));
    const res = await request(app).get('/api/admin/script-quantities/exchange/NFO-FUT?limit=100').set('Authorization', asSuper());
    expect(res.status).toBe(200);
    const abc = res.body.data.items.find((i) => i.script_name === 'ABC');
    expect(abc.max_qty).toBe(99);
  });

  // ── 7/8. master group switch
  test('master group switch: own blocks kept, empty group refused, failure keeps the old group (409)', async () => {
    let res = await request(app).put(`/api/masters/${ids.bds}`).set('Authorization', asSuper()).send({ script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'EMPTY' }] });
    expect(res.status).toBe(400);
    expect(await maxOf(ids.bds, 'ABC')).toBe(20);

    res = await request(app).put(`/api/masters/${ids.bds}`).set('Authorization', asSuper()).send({ script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'G2' }] });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.bds, 'ABC')).toBe(50);
    expect(await maxOf(ids.bds, 'GHI')).toBe(50);
    expect(await maxOf(ids.bds, 'DEF')).toBe(0); // his block survives the switch

    res = await request(app).put(`/api/masters/${ids.bds}`).set('Authorization', asSuper()).send({ script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'GDUP' }] });
    expect(res.status).toBe(409);
    const m = await db.collection('masters').findOne({ _id: ids.bds });
    expect(m.script_quantity_groups.find((g) => g.exchange_name === 'NFO-FUT').group_name).toBe('G2');
    expect(await maxOf(ids.bds, 'ABC')).toBe(50);
  });

  test('an unchanged group is not re-checked against a narrowed allotment', async () => {
    await db.collection('masters').updateOne({ _id: ids.rit }, { $set: { allotted_script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_names: ['G2'] }] } });
    let res = await request(app).put(`/api/masters/${ids.rit}`).set('Authorization', asMaster(ids.bds)).send({ name: 'RITESH K', script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'G1' }] });
    expect(res.status).toBe(200);
    res = await request(app).put(`/api/masters/${ids.rit}`).set('Authorization', asMaster(ids.bds)).send({ script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'GDUP' }] });
    expect(res.status).toBe(400); // a CHANGE outside the allotment is still refused
  });

  // ── 7. brokerage: a master's rate can't rise above an account under him
  test('raising a sub-master rate above his client: master refused with the list, admin warned', async () => {
    await db.collection('brokeragesettings').insertMany([rate(ids.bds, 'ABC', 1), rate(ids.rit, 'ABC', 1), rate(ids.c3, 'ABC', 1.5), rate(ids.rit, 'DEF', 1), rate(ids.c3, 'DEF', 3)]);
    const ritAbc = await db.collection('brokeragesettings').findOne({ user_id: ids.rit, script_name: 'ABC' });
    let res = await request(app).put(`/api/admin/brokerage-settings/${ritAbc._id}`).set('Authorization', asMaster(ids.bds)).send({ brk_value: 2 });
    expect(res.status).toBe(422);
    expect(res.body.message).toMatch(/C3 ABC 1\.5/);
    expect((await db.collection('brokeragesettings').findOne({ _id: ritAbc._id })).brk_value).toBe(1);
    // bulk-update the same
    res = await request(app).put('/api/admin/brokerage-settings/bulk-update').set('Authorization', asMaster(ids.bds)).send({ ids: [String(ritAbc._id)], brk_value: 2 });
    expect(res.status).toBe(422);
    // up to the client's rate is fine
    res = await request(app).put(`/api/admin/brokerage-settings/${ritAbc._id}`).set('Authorization', asMaster(ids.bds)).send({ brk_value: 1.5 });
    expect(res.status).toBe(200);
    // admin: saved, told
    res = await request(app).put(`/api/admin/brokerage-settings/${ritAbc._id}`).set('Authorization', asSuper()).send({ brk_value: 2 });
    expect(res.status).toBe(200);
    expect(res.body.data.children_below).toHaveLength(1);
    expect(res.body.message).toMatch(/now below/);
    // lowering never checks children
    const ritDef = await db.collection('brokeragesettings').findOne({ user_id: ids.rit, script_name: 'DEF' });
    res = await request(app).put(`/api/admin/brokerage-settings/${ritDef._id}`).set('Authorization', asMaster(ids.bds)).send({ brk_value: 2.5 });
    expect(res.status).toBe(200);
  });

  test('bulk-create rates for a sub-master: only NEW rows are checked against his clients', async () => {
    await db.collection('brokeragesettings').insertMany([rate(ids.bds, 'ABC', 1), rate(ids.rit, 'ABC', 9), rate(ids.c3, 'GHI', 0.5)]);
    let res = await request(app).post('/api/admin/brokerage-settings/bulk-create').set('Authorization', asMaster(ids.bds))
      .send({ exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', default_brk_value: 2, user_id: String(ids.rit) });
    expect(res.status).toBe(422); // GHI would be created at 2 over C3's 0.5
    expect(res.body.message).toMatch(/C3 GHI 0\.5/);
    expect(await db.collection('brokeragesettings').countDocuments({ user_id: ids.rit })).toBe(1);
    res = await request(app).post('/api/admin/brokerage-settings/bulk-create').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', default_brk_value: 2, user_id: String(ids.rit) });
    expect(res.status).toBe(201);
    expect(res.body.data.children_below).toHaveLength(1);
  });

  // ── admin platform rows: joining rule
  const adminRow = (script, max) => sq(ids.superA, 'Admin', script, max);
  const marked = async (owner, script) => (await db.collection('scriptquantities').findOne({ owner_id: owner, script_name: script, deleted_at: null }))?.blocked_by_admin === true;
  const putAdmin = async (script, body) => {
    const row = await db.collection('scriptquantities').findOne({ owner_id: ids.superA, owner_type: 'Admin', script_name: script, deleted_at: null });
    return request(app).put(`/api/admin/script-quantities/${row._id}`).set('Authorization', asSuper()).send(body);
  };

  test('admin row edit (not a block) never overwrites; only accounts with no row get it', async () => {
    await db.collection('scriptquantities').insertMany([adminRow('ABC', 100), adminRow('GHI', 100)]);
    const res = await putAdmin('ABC', { max_qty: 60, brk_qty: 60 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'ABC')).toBe(20);
    expect(await maxOf(ids.c2, 'ABC')).toBe(15);
    expect(await maxOf(ids.bds, 'ABC')).toBe(20);
    await db.collection('scriptquantities').updateOne({ owner_id: ids.cx, script_name: 'ABC' }, { $set: { deleted_at: new Date() } });
    await putAdmin('ABC', { max_qty: 70, brk_qty: 70 });
    expect(await maxOf(ids.cx, 'ABC')).toBe(70); // had no row → gets it
    expect(await maxOf(ids.c1, 'ABC')).toBe(20);
  });

  test('admin block reaches everyone, sticks on joining / group edit / master unblock, and unblock gives what joining gives', async () => {
    await db.collection('scriptquantities').insertMany([adminRow('DEF', 100)]);
    let res = await putAdmin('DEF', { max_qty: 0, brk_qty: 0 });
    expect(res.status).toBe(200);
    for (const who of [ids.c1, ids.c2, ids.c3, ids.cx, ids.rit, ids.other, ids.harry]) expect(await maxOf(who, 'DEF')).toBe(0);
    expect(await marked(ids.rit, 'DEF')).toBe(true);
    expect(await marked(ids.bds, 'DEF')).toBe(false); // his own block, left alone

    // sticks: a group edit, a client's group switch, a master's own unblock
    res = await request(app).put(`/api/admin/grouped-quantities/${(await groupRow('G2', 'DEF'))._id}`).set('Authorization', asSuper()).send({ max_qty: 45, break_qty: 45 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c3, 'DEF')).toBe(0);
    res = await request(app).put(`/api/master/users/${ids.cx}`).set('Authorization', asSuper()).send({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G2' }] });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.cx, 'DEF')).toBe(0);
    expect(await maxOf(ids.cx, 'GHI')).toBe(50);
    const bdsDef = await db.collection('scriptquantities').findOne({ owner_id: ids.bds, script_name: 'DEF', deleted_at: null });
    res = await request(app).put(`/api/admin/script-quantities/${bdsDef._id}`).set('Authorization', asSuper()).send({ max_qty: 9 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'DEF')).toBe(0); // the admin still blocks it
    await db.collection('scriptquantities').updateOne({ _id: bdsDef._id }, { $set: { max_qty: 0, brk_qty: 0 } }); // his own block again

    // a master switching group keeps the admin block (marked)
    res = await request(app).put(`/api/masters/${ids.rit}`).set('Authorization', asSuper()).send({ script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_name: 'G2' }] });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.rit, 'DEF')).toBe(0);
    expect(await marked(ids.rit, 'DEF')).toBe(true);

    // unblock: what joining gives
    res = await putAdmin('DEF', { max_qty: 30, brk_qty: 30 });
    expect(res.status).toBe(200);
    expect(await maxOf(ids.rit, 'DEF')).toBe(45); // his group (now G2, edited to 45)
    expect(await marked(ids.rit, 'DEF')).toBe(false);
    expect(await maxOf(ids.bds, 'DEF')).toBe(0); // his own block kept
    expect(await maxOf(ids.c1, 'DEF')).toBe(0); // BDS82's clients stay blocked by him
    expect(await maxOf(ids.c2, 'DEF')).toBe(0);
    expect(await maxOf(ids.c3, 'DEF')).toBe(45); // G2
    expect(await maxOf(ids.cx, 'DEF')).toBe(45); // now on G2
    expect(await maxOf(ids.harry, 'DEF')).toBe(20); // G1
  });

  test('deleting an admin row: nobody changes; deleting a block lifts it (no row where the group lacks the script)', async () => {
    await db.collection('scriptquantities').insertMany([adminRow('ABC', 100)]);
    let row = await db.collection('scriptquantities').findOne({ owner_type: 'Admin', script_name: 'ABC' });
    let res = await request(app).delete(`/api/admin/script-quantities/${row._id}`).set('Authorization', asSuper());
    expect(res.status).toBe(200);
    for (const [who, v] of [[ids.c1, 20], [ids.c2, 15], [ids.c3, 50], [ids.bds, 20]]) expect(await maxOf(who, 'ABC')).toBe(v);

    res = await request(app).post('/api/admin/script-quantities').set('Authorization', asSuper()).send({ exchange_name: 'NFO-FUT', script_name: 'GHI', lot_size: 1, max_qty: 0, brk_qty: 0 });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.c1, 'GHI')).toBe(0);
    expect(await maxOf(ids.bds, 'GHI')).toBe(0);
    row = await db.collection('scriptquantities').findOne({ owner_type: 'Admin', script_name: 'GHI', deleted_at: null });
    res = await request(app).delete(`/api/admin/script-quantities/${row._id}`).set('Authorization', asSuper());
    expect(res.status).toBe(200);
    expect(await maxOf(ids.c1, 'GHI')).toBeNull(); // G1 has no GHI
    expect(await maxOf(ids.bds, 'GHI')).toBeNull();
    expect(await maxOf(ids.c3, 'GHI')).toBe(50); // G2
    expect(await maxOf(ids.rit, 'GHI')).toBeNull();
  });

  test('admin bulk create: a 0 default blocks the NEW scripts for everyone; existing admin scripts fill with their own value', async () => {
    await db.collection('scriptquantities').insertMany([adminRow('ABC', 100), adminRow('DEF', 100)]);
    await db.collection('scriptquantities').updateOne({ owner_id: ids.cx, script_name: 'ABC' }, { $set: { deleted_at: new Date() } });
    const res = await request(app).post('/api/admin/script-quantities/bulk-create').set('Authorization', asSuper())
      .send({ exchange_name: 'NFO-FUT', default_max_qty: 0, default_brk_qty: 0 });
    expect(res.status).toBe(201);
    expect(await maxOf(ids.c3, 'GHI')).toBe(0); // new admin script GHI, blocked
    expect(await maxOf(ids.c1, 'RELIANCE')).toBe(0);
    expect(await marked(ids.rit, 'GHI')).toBe(true);
    expect(await maxOf(ids.cx, 'ABC')).toBe(100); // had no row → the admin row's own value
    expect(await maxOf(ids.c1, 'ABC')).toBe(20);
    expect(await maxOf(ids.c3, 'ABC')).toBe(50);
  });

  // ── 10. group list for another master
  test('lot names for a given master: own tree only, filtered by that master\'s allotment', async () => {
    await db.collection('masters').updateOne({ _id: ids.rit }, { $set: { allotted_script_quantity_groups: [{ exchange_name: 'NFO-FUT', group_names: ['G2'] }] } });
    let res = await request(app).get(`/api/admin/grouped-quantities/exchange/NFO-FUT/lot-names?for_master_id=${ids.rit}`).set('Authorization', asMaster(ids.bds));
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual(['G2']);
    res = await request(app).get(`/api/admin/grouped-quantities/exchange/NFO-FUT/lot-names?for_master_id=${ids.other}`).set('Authorization', asMaster(ids.bds));
    expect(res.status).toBe(403);
    res = await request(app).get('/api/admin/grouped-quantities/exchange/NFO-FUT/lot-names').set('Authorization', asMaster(ids.bds));
    expect(res.status).toBe(200);
    expect(res.body.data).toEqual(expect.arrayContaining(['G1', 'G2']));
  });
});
