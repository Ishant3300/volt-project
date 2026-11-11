'use strict';

// Broker view end to end (src/brokerView/) on a THROWAWAY MongoDB in this PC's
// memory — never the live database:
//   node scripts/cashEq/runFnoSettlementTestsLocally.js tests/brokerView.integration.test.js
// Refuses any non-local host and any database not named stkr_broker_it_*.

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');
const express = require('express');
const request = require('supertest');
const bcrypt = require('bcryptjs');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_broker_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(120_000);
process.env.JWT_SECRET = process.env.JWT_SECRET || 'broker-view-test-secret';

const oid = () => new mongoose.Types.ObjectId();
const ids = { server: oid(), admin: oid(), harry: oid(), other: oid(), linked: oid(), ended: oid(), stranger: oid(), broker: oid(), broker2: oid() };

describeIntegration('broker view on a local MongoDB', () => {
  let app;
  let db;

  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    const host = new URL(process.env.MONGO_URI.replace(/^mongodb(\+srv)?:\/\//, 'http://').split(',')[0]).hostname;
    if (host !== '127.0.0.1' && host !== 'localhost') throw new Error(`Refusing non-local MongoDB host ${host}`);
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_broker_it_')) throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    db = mongoose.connection.db;

    const now = new Date();
    const pw = await bcrypt.hash('client-pass', 4);
    await db.collection('admins').insertOne({ _id: ids.admin, username: 'Supervolt', password: pw, is_super_admin: true, active_status: true, deleted_at: null, permissions: [], hidden_master_ids: [] });
    const master = (id, name, username) => ({ _id: id, name, username, password: pw, credits: 0, status: 'active', active_status: true, deleted_at: null, server_id: ids.server, admin_id: ids.admin, master_id: null, exchanges_allowed: [], permissions: {} });
    await db.collection('masters').insertMany([master(ids.harry, 'harry', '839276'), master(ids.other, 'OTHER', '555001')]);
    const user = (id, name, username, m) => ({ _id: id, name, username, password: pw, credits: 2000000, status: 'active', active_status: true, deleted_at: null, master_id: m, server_id: ids.server, exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G' }], wallet: { NSE: 500000 }, createdAt: now, updatedAt: now });
    await db.collection('users').insertMany([
      user(ids.linked, '(223) HITU', '192977', ids.harry),
      user(ids.ended, 'OLD CLIENT', '111111', ids.harry),
      user(ids.stranger, 'NOT MINE', '222222', ids.other),
    ]);
    await db.collection('brokers').insertMany([
      { _id: ids.broker, name: 'Rajesh K', phone: '', note: '', status: 'active', deleted_at: null, createdAt: now, updatedAt: now },
      { _id: ids.broker2, name: 'Other broker', phone: '', note: '', status: 'active', deleted_at: null, createdAt: now, updatedAt: now },
    ]);
    await db.collection('brokerclientlinks').insertMany([
      { _id: oid(), broker_id: ids.broker, user_id: ids.linked, master_id: ids.harry, rates: [], from: new Date('2026-10-01'), to: null },
      { _id: oid(), broker_id: ids.broker, user_id: ids.ended, master_id: ids.harry, rates: [], from: new Date('2026-10-01'), to: new Date('2026-11-01') },
      { _id: oid(), broker_id: ids.broker2, user_id: ids.stranger, master_id: ids.other, rates: [], from: new Date('2026-10-01'), to: null },
    ]);
    const trade = (u, sym, extra = {}) => ({ _id: oid(), user_id: u, master_id: ids.harry, instrument_token: '15736578', tradingsymbol: sym, exchange: 'NFO', transaction_type: 'BUY', quantity: 75, price: 25000, order_type: 'MARKET', status: 'completed', executed_quantity: 75, executed_price: 25000, executed_at: now, trade_type: 'regular', deleted_at: null, createdAt: now, updatedAt: now, ...extra });
    await db.collection('trades').insertMany([trade(ids.linked, 'NIFTY26NOVFUT'), trade(ids.stranger, 'NIFTY26NOVFUT')]);
    await db.collection('settlementhistories').insertOne({ _id: oid(), user_id: ids.linked, tradingsymbol: 'NIFTY26NOVFUT', exchange: 'NFO', instrument_token: '15736578', period_from: new Date('2026-11-01'), period_to: new Date('2026-11-06'), createdAt: now });
    await db.collection('kiteinstruments').insertOne({ _id: oid(), instrument_token: '15736578', tradingsymbol: 'NIFTY26NOVFUT', exchange: 'NFO', segment: 'NFO-FUT', lot_size: 75, name: 'NIFTY', is_active: true, deleted_at: null });

    app = express();
    app.use(express.json());
    app.post('/api/auth/login', require('../src/controllers/authController').universalLogin);
    app.use('/api/broker', require('../src/brokerView/routes'));
    // Admin side, as mounted in adminRoutes (the admin is supplied directly here).
    const fakeAdmin = (req, res, next) => { req.admin = { id: String(ids.admin), isSuperAdmin: true, permissions: [], hiddenMasterIds: [] }; next(); };
    const brokerCtl = require('../src/controllers/brokerController');
    app.put('/api/admin/brokers/:id/login', fakeAdmin, brokerCtl.setLogin);
    app.post('/api/admin/brokers/:id/links', fakeAdmin, brokerCtl.addLink);
    // A real F&O route with its real guard — a broker token must be refused there.
    const { authenticateAny } = require('../src/middlewares/auth');
    app.get('/api/trade/positions', authenticateAny, require('../src/controllers/tradeController').getPositions);
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_broker_it_')) await mongoose.connection.dropDatabase();
    } finally { await mongoose.disconnect(); }
  });

  let token;

  test('admin sets the login: a username used by a client is refused, a free one is saved', async () => {
    const taken = await request(app).put(`/api/admin/brokers/${ids.broker}/login`).send({ username: '192977', password: 'secret1' });
    expect(taken.status).toBe(409);
    const eq = await request(app).put(`/api/admin/brokers/${ids.broker}/login`).send({ username: 'EQ1234', password: 'secret1' });
    expect(eq.status).toBe(400);
    const early = await request(app).put(`/api/admin/brokers/${ids.broker}/login`).send({ enabled: true });
    expect(early.status).toBe(400);
    const ok = await request(app).put(`/api/admin/brokers/${ids.broker}/login`).send({ username: 'rajeshk', password: 'secret1', enabled: true });
    expect(ok.status).toBe(200);
    const doc = await db.collection('brokers').findOne({ _id: ids.broker });
    expect(doc.username).toBe('rajeshk');
    expect(doc.password).not.toBe('secret1');
    expect(doc.login_enabled).toBe(true);
  });

  test('the universal login signs the broker in with role BROKER; a client login is unchanged', async () => {
    const bad = await request(app).post('/api/auth/login').send({ username: 'rajeshk', password: 'wrong' });
    expect(bad.status).toBe(401);
    const res = await request(app).post('/api/auth/login').send({ username: 'rajeshk', password: 'secret1' });
    expect(res.status).toBe(200);
    expect(res.body.data.role).toBe('BROKER');
    expect(res.body.data.broker).toMatchObject({ name: 'Rajesh K', username: 'rajeshk' });
    expect(res.body.data.broker.password).toBeUndefined();
    token = res.body.data.token;
    const client = await request(app).post('/api/auth/login').send({ username: '192977', password: 'client-pass' });
    expect(client.status).toBe(200);
    expect(client.body.data.role).toBe('USER');
  });

  test('client list: only clients linked right now (not an ended link, not another broker\'s)', async () => {
    const res = await request(app).get('/api/broker/clients').set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.data.map((c) => c.username)).toEqual(['192977']);
    expect(res.body.data[0]).toMatchObject({ name: '(223) HITU', master: { username: '839276' }, credit: 2000000 });
  });

  test('a linked client opens; an ended-link or other broker\'s client is "not found"', async () => {
    const own = await request(app).get(`/api/broker/clients/${ids.linked}`).set('Authorization', `Bearer ${token}`);
    expect(own.status).toBe(200);
    expect(own.body.data).toMatchObject({ username: '192977', master: { name: 'harry' } });
    expect(own.body.data.metrics).toMatchObject({ credit: 2000000 });
    expect(own.body.data.metrics.wallet).toBeUndefined();
    for (const id of [ids.ended, ids.stranger, oid()]) {
      const r = await request(app).get(`/api/broker/clients/${id}`).set('Authorization', `Bearer ${token}`);
      expect(r.status).toBe(404);
    }
  });

  test('trades and bill data are that client\'s only (bill includes settled weeks + instruments)', async () => {
    const trades = await request(app).get(`/api/broker/clients/${ids.linked}/trades`).set('Authorization', `Bearer ${token}`);
    expect(trades.status).toBe(200);
    expect(trades.body.data.trades || trades.body.data).toBeTruthy();
    const list = trades.body.data.trades || trades.body.data;
    expect(list.every((t) => String(t.user_id?._id || t.user_id) === String(ids.linked))).toBe(true);
    expect(list.length).toBe(1);

    const bill = await request(app).get(`/api/broker/clients/${ids.linked}/bill-data`).set('Authorization', `Bearer ${token}`);
    expect(bill.status).toBe(200);
    expect(bill.body.data.trades.map((t) => String(t.user_id))).toEqual([String(ids.linked)]);
    expect(bill.body.data.settlement.data).toHaveLength(1);
    expect(bill.body.data.instruments.map((i) => String(i.instrument_token))).toContain('15736578');
    const other = await request(app).get(`/api/broker/clients/${ids.stranger}/bill-data`).set('Authorization', `Bearer ${token}`);
    expect(other.status).toBe(404);
  });

  test('read-only: no POST/PUT on the broker routes; a broker token is refused by F&O routes', async () => {
    const post = await request(app).post(`/api/broker/clients/${ids.linked}/trades`).set('Authorization', `Bearer ${token}`).send({});
    expect(post.status).toBe(405);
    const fno = await request(app).get('/api/trade/positions').set('Authorization', `Bearer ${token}`);
    expect([401, 403]).toContain(fno.status);
    const noToken = await request(app).get('/api/broker/clients');
    expect(noToken.status).toBe(401);
  });

  test('a view-only link needs no brokerage share', async () => {
    // 11 Nov 2026 (broker sharing): no share at all (0 / 0 / 0) is a valid view-only link now; a share
    // above the limits is refused (tests/brokerSharing.integration.test.js).
    const tooMuch = await request(app).post(`/api/admin/brokers/${ids.broker}/links`).send({ user_id: String(ids.ended), pnl_share_pct: 101 });
    expect(tooMuch.status).toBe(400);
    const viewOnly = await request(app).post(`/api/admin/brokers/${ids.broker}/links`).send({ user_id: String(ids.ended), view_only: true });
    expect(viewOnly.status).toBe(201);
    const res = await request(app).get('/api/broker/clients').set('Authorization', `Bearer ${token}`);
    expect(res.body.data.map((c) => c.username).sort()).toEqual(['111111', '192977']);
  });

  test('a new password ends the old session; turning the login off refuses it', async () => {
    await request(app).put(`/api/admin/brokers/${ids.broker}/login`).send({ password: 'secret2' });
    const old = await request(app).get('/api/broker/clients').set('Authorization', `Bearer ${token}`);
    expect(old.status).toBe(401);
    const again = await request(app).post('/api/auth/login').send({ username: 'rajeshk', password: 'secret2' });
    expect(again.status).toBe(200);
    await request(app).put(`/api/admin/brokers/${ids.broker}/login`).send({ enabled: false });
    const off = await request(app).post('/api/auth/login').send({ username: 'rajeshk', password: 'secret2' });
    expect(off.status).toBe(403);
    const used = await request(app).get('/api/broker/clients').set('Authorization', `Bearer ${again.body.data.token}`);
    expect([401, 403]).toContain(used.status);
  });
});
