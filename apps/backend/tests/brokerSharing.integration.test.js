'use strict';

// Broker sharing (owner, 11 Nov 2026) on a THROWAWAY MongoDB in this PC's memory —
// never the live database:
//   node scripts/cashEq/runFnoSettlementTestsLocally.js tests/brokerSharing.integration.test.js
// Refuses any non-local host and any database not named stkr_bshare_it_*.
//
// FIRST PRIORITY (owner): the ledger / weekly / settlement reports must not move.
// The reports are taken BEFORE any broker data exists and again AFTER brokers,
// links, sharing and statements have all been created — they must be identical.

const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../.env') });
const mongoose = require('mongoose');
const express = require('express');
const request = require('supertest');

const runIntegration = process.env.RUN_SETTLEMENT_INTEGRATION === '1';
const describeIntegration = runIntegration ? describe : describe.skip;
const databaseName = `stkr_bshare_it_${Date.now().toString(36)}_${process.pid.toString(36)}`;
jest.setTimeout(180_000);
process.env.JWT_SECRET = process.env.JWT_SECRET || 'broker-sharing-test-secret';

const oid = () => new mongoose.Types.ObjectId();
const ids = { server: oid(), admin: oid(), harish: oid(), sub: oid(), other: oid(), ab: oid(), cd: oid(), ef: oid(), run: oid() };
const TOKEN = '111';

// Weeks as the Ledger page sends them.
const { weekWindows } = require('../src/services/brokerStatement');

describeIntegration('broker sharing on a local MongoDB', () => {
  let db;
  let app;
  let weeks;

  const report = (q) => require('../src/services/brokerStatement')._private.runWeeklyReport(q);
  async function allReports() {
    const out = {};
    for (const w of weeks) {
      out[`admin:${w.key}`] = await report({ ...w.query });
      out[`harish:${w.key}`] = await report({ ...w.query, as_master_id: String(ids.harish) });
      out[`sub:${w.key}`] = await report({ ...w.query, as_master_id: String(ids.sub) });
    }
    const { buildSettlementReport } = require('../src/services/settlementReportService');
    const Master = require('../src/models/Master');
    const harish = await Master.findById(ids.harish).lean();
    out.settlement = await buildSettlementReport('Master', harish, weeks[1].start, weeks[0].end, true);
    out.users = await db.collection('users').find({}).sort({ _id: 1 }).toArray();
    out.masters = await db.collection('masters').find({}).sort({ _id: 1 }).toArray();
    out.trades = await db.collection('trades').find({}).sort({ _id: 1 }).toArray();
    out.brokerage = await db.collection('brokeragesettings').find({}).sort({ _id: 1 }).toArray();
    return JSON.parse(JSON.stringify(out));
  }

  let before;

  beforeAll(async () => {
    if (!process.env.MONGO_URI) throw new Error('MONGO_URI is required');
    const host = new URL(process.env.MONGO_URI.replace(/^mongodb(\+srv)?:\/\//, 'http://').split(',')[0]).hostname;
    if (host !== '127.0.0.1' && host !== 'localhost') throw new Error(`Refusing non-local MongoDB host ${host}`);
    await mongoose.connect(process.env.MONGO_URI, { dbName: databaseName, autoIndex: false, autoCreate: true, serverSelectionTimeoutMS: 30_000 });
    if (!mongoose.connection.name.startsWith('stkr_bshare_it_')) throw new Error(`Refusing to test against ${mongoose.connection.name}`);
    db = mongoose.connection.db;

    const now = new Date();
    weeks = weekWindows({ since: new Date(now.getTime() - 14 * 864e5), now, max: 2 });
    const thisWeek = weeks[0];
    const lastWeek = weeks[1];
    const inWeek = (w, hours) => new Date(w.start.getTime() + hours * 3600e3);

    await db.collection('admins').insertOne({ _id: ids.admin, username: 'Supervolt', password: 'x', is_super_admin: true, active_status: true, deleted_at: null, permissions: [], hidden_master_ids: [] });
    const master = (id, name, username, parent, pnl, brk) => ({ _id: id, name, username, password: 'x', credits: 0, pnl_sharing: pnl, brokerage_sharing: brk, exchanges_allowed: ['NFO-FUT'], trade_limit: ['NFO-FUT'], server_id: ids.server, admin_id: ids.admin, master_id: parent, status: 'active', active_status: true, deleted_at: null, ledger_balance: 0 });
    await db.collection('masters').insertMany([
      master(ids.harish, 'Harish', '695209', null, 90, 60),
      master(ids.sub, 'S', '700001', ids.harish, 30, 40),
      master(ids.other, 'OTHER', '555001', null, 80, 50),
    ]);
    const user = (id, name, username, m) => ({ _id: id, name, username, password: 'x', credits: 1000000, pnl_sharing: 0, brokerage_sharing: 0, exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false, group_name: 'G' }], server_id: ids.server, master_id: m, status: 'active', active_status: true, deleted_at: null, ledger_balance: 0 });
    await db.collection('users').insertMany([user(ids.ab, 'AB', '100001', ids.harish), user(ids.cd, 'CD', '100002', ids.sub), user(ids.ef, 'EF', '100003', ids.other)]);
    const rate = (owner, v) => ({ _id: oid(), user_id: owner, exchange_name: 'NFO-FUT', script_name: 'NIFTY', type: 'TURNOVER WISE', brk_value: v, deleted_at: null });
    await db.collection('brokeragesettings').insertMany([rate(ids.harish, 2), rate(ids.sub, 5), rate(ids.ab, 8), rate(ids.cd, 8), rate(ids.ef, 8), rate(ids.other, 2)]);
    await db.collection('kiteinstruments').insertOne({ _id: oid(), instrument_token: TOKEN, tradingsymbol: 'NIFTY26NOVFUT', exchange: 'NFO', segment: 'NFO-FUT', raw_name: 'NIFTY', name: 'NIFTY', lot_size: 50, is_active: true, deleted_at: null });

    // A round trip: BUY 1000 @ 100, SELL 1000 @ 95 -> loss 5,000; brokerage at 8 paisa = 80 + 76.
    const fills = (u, m, w, settled) => {
      const base = { user_id: u, master_id: m, instrument_token: TOKEN, tradingsymbol: 'NIFTY26NOVFUT', exchange: 'NFO', order_type: 'MARKET', status: 'completed', trade_type: 'regular', createdAt: inWeek(w, 30), updatedAt: inWeek(w, 30) };
      const s = settled ? { deleted_at: new Date(w.end.getTime() - 3600e3), settlement_run_id: ids.run, settlement_period_key: 'p' } : { deleted_at: null };
      return [
        { _id: oid(), ...base, ...s, transaction_type: 'BUY', quantity: 1000, price: 100, executed_quantity: 1000, executed_price: 100, executed_at: inWeek(w, 30), pnl: 0, brokerage: 80 },
        { _id: oid(), ...base, ...s, transaction_type: 'SELL', quantity: 1000, price: 95, executed_quantity: 1000, executed_price: 95, executed_at: inWeek(w, 31), pnl: -5000, brokerage: 76 },
      ];
    };
    await db.collection('trades').insertMany([
      ...fills(ids.ab, ids.harish, thisWeek, false), ...fills(ids.cd, ids.sub, thisWeek, false), ...fills(ids.ef, ids.other, thisWeek, false),
      ...fills(ids.ab, ids.harish, lastWeek, true), ...fills(ids.cd, ids.sub, lastWeek, true),
    ]);
    for (const c of ['brokers', 'brokerclientlinks', 'brokermasterlinks', 'masterbrokeraccesses']) await db.createCollection(c).catch(() => {});

    before = await allReports();

    app = express();
    app.use(express.json());
    const asAdmin = (req, res, next) => { req.admin = { id: String(ids.admin), isSuperAdmin: true, permissions: [], hiddenMasterIds: [] }; next(); };
    const asMaster = (id) => (req, res, next) => { req.master = { id: String(id), role: 'master' }; next(); };
    const admin = require('../src/controllers/brokerController');
    app.post('/admin/brokers', asAdmin, admin.createBroker);
    app.post('/admin/brokers/:id/links', asAdmin, admin.addLink);
    app.post('/admin/brokers/:id/master-links', asAdmin, admin.addMasterLink);
    app.get('/admin/brokers/limits', asAdmin, admin.getLimits);
    app.get('/admin/brokers/:id/statement', asAdmin, admin.getStatement);
    app.put('/admin/broker-access/:masterId', asAdmin, admin.setAccess);
    const m = require('../src/controllers/masterBrokerController');
    for (const [who, id] of [['harish', ids.harish], ['sub', ids.sub]]) {
      const r = express.Router();
      r.use(asMaster(id));
      r.get('/access', m.getAccess);
      r.use(m.requireAccess);
      r.get('/', m.list);
      r.post('/', m.create);
      r.post('/:id/links', m.addLink);
      r.post('/:id/master-links', m.addMasterLink);
      r.get('/:id/statement', m.getStatement);
      app.use(`/${who}/brokers`, r);
    }
  });

  afterAll(async () => {
    try {
      if (mongoose.connection.readyState === 1 && mongoose.connection.name.startsWith('stkr_bshare_it_')) await mongoose.connection.dropDatabase();
    } finally { await mongoose.disconnect(); }
  });

  let adminBroker;
  let harishBroker;

  test('the ledger rows the statement reads: AB Total P&L 5,000, brokerage 156; S tree 5,000 / 156 / own 97.5', () => {
    const ab = before[`harish:${weeks[0].key}`].find((r) => r.id === String(ids.ab));
    const s = before[`harish:${weeks[0].key}`].find((r) => r.id === String(ids.sub));
    expect(ab).toMatchObject({ total_pnl: 5000, brokerage: 156 });
    expect(s).toMatchObject({ total_pnl: 5000, brokerage: 156, own_brokerage: 97.5 });
  });

  test('limits: rate above the markup, P&L above the master, or above master minus the sub-master are refused', async () => {
    adminBroker = (await request(app).post('/admin/brokers').send({ name: 'Rajesh K' })).body.data.id;
    const lim = await request(app).get('/admin/brokers/limits').query({ user_id: String(ids.ab) });
    expect(lim.body.data).toMatchObject({ pnl_max: 90, brk_max: 60, paying_master: { username: '695209' } });
    expect(lim.body.data.segments[0]).toMatchObject({ segment: 'NFO-FUT', type: 'TURNOVER WISE', x_max: 6 });
    const tooMuchRate = await request(app).post(`/admin/brokers/${adminBroker}/links`).send({ user_id: String(ids.ab), rates: [{ segment: 'NFO-FUT', value: 7 }] });
    expect(tooMuchRate.status).toBe(400);
    const tooMuchPnl = await request(app).post(`/admin/brokers/${adminBroker}/links`).send({ user_id: String(ids.ab), pnl_share_pct: 95 });
    expect(tooMuchPnl.status).toBe(400);
    const tooMuchBrk = await request(app).post(`/admin/brokers/${adminBroker}/links`).send({ user_id: String(ids.ab), brk_share_pct: 61 });
    expect(tooMuchBrk.status).toBe(400);
    const subLim = await request(app).get('/admin/brokers/limits').query({ master_id: String(ids.sub) });
    // ledger ceilings are cumulative: brokerage max = Harish 60 - S 40, P&L max = 90 - 30
    expect(subLim.body.data).toMatchObject({ pnl_max: 60, brk_max: 20, below_pnl_pct: 30, below_brk_pct: 40 });
    expect(subLim.body.data.segments[0].x_max).toBe(3);
    const subTooMuch = await request(app).post(`/admin/brokers/${adminBroker}/master-links`).send({ master_id: String(ids.sub), pnl_share_pct: 61 });
    expect(subTooMuch.status).toBe(400);
    const subTooMuchBrk = await request(app).post(`/admin/brokers/${adminBroker}/master-links`).send({ master_id: String(ids.sub), brk_share_pct: 21 });
    expect(subTooMuchBrk.status).toBe(400);
  });

  test('admin: broker on client AB (3 paisa, 20% brokerage, 30% P&L) and on sub-master S (2 paisa, 10%, 20%)', async () => {
    const from = new Date(weeks[1].start.getTime() - 864e5).toISOString();
    const a = await request(app).post(`/admin/brokers/${adminBroker}/links`).send({ user_id: String(ids.ab), rates: [{ segment: 'NFO-FUT', value: 3 }], brk_share_pct: 20, pnl_share_pct: 30, from });
    expect(a.status).toBe(201);
    const s = await request(app).post(`/admin/brokers/${adminBroker}/master-links`).send({ master_id: String(ids.sub), rates: [{ segment: 'NFO-FUT', value: 2 }], brk_share_pct: 10, pnl_share_pct: 20, from });
    expect(s.status).toBe(201);
  });

  test('statement: the agreed numbers, both weeks', async () => {
    const res = await request(app).get(`/admin/brokers/${adminBroker}/statement`).query({ weeks: 2 });
    expect(res.status).toBe(200);
    expect(res.body.data.weeks).toHaveLength(2);
    for (const w of res.body.data.weeks) {
      const ab = w.rows.find((r) => r.target.id === String(ids.ab));
      const s = w.rows.find((r) => r.target.id === String(ids.sub));
      // AB: x = 3 paisa x 1,95,000 = 58.5; self = 58.5 + 20% x (156 - 58.5) = 78; P&L 30% of 5,000.
      expect(ab.pnl).toEqual({ total: 5000, below: 0, self: 1500, upline: 3500 });
      expect(ab.brokerage).toMatchObject({ total: 156, below: 0, self: 78, upline: 78, from_rate: 58.5 });
      expect(ab.net).toBe(1578);
      // S: below 30% = 1,500, broker 20% = 1,000; brokerage incoming 97.5 x 60% = 58.5,
      // x = 2 paisa x 1,95,000 = 39; the broker's ceiling is cumulative (S 40% + his 10%):
      // self = 58.5 - (97.5 - 39) x (1 - 50%) = 29.25. Harish alone would keep 58.5 - 39 x 40% = 42.9;
      // with the broker 29.25 - 15.6 = 13.65 -> the broker's 29.25 is exactly what Harish gives up.
      expect(s.pnl).toEqual({ total: 5000, below: 1500, self: 1000, upline: 2500 });
      expect(s.brokerage).toMatchObject({ total: 156, below: 97.5, self: 29.25, upline: 29.25 });
      expect(w.totals.net).toBeCloseTo(1578 + 1029.25, 2);
    }
  });

  test('split maths: 0/0/0 = nothing; the broker never takes more than the paying master own part', () => {
    const { brokerWeekSplit } = require('../src/services/brokerStatement');
    // sub-master S (own clear 97.5, 40%) under M (own clear 39, 60%), Total brokerage 156, P&L 5,000
    const base = { totalPnl: 5000, totalBrk: 156, belowClear: 97.5, belowBrkPct: 40, belowPnlPct: 30 };
    const zero = brokerWeekSplit(base);
    expect(zero.brokerage.self).toBe(0);
    expect(zero.pnl.self).toBe(0);
    expect(zero.net).toBe(0);
    const mAlone = 97.5 * 0.6 - 39 * 0.4; // the ledger's caller_brk for M on S's row
    for (const x of [0, 19.5, 39, 58.5]) {
      for (const brkPct of [0, 10, 20]) {
        const sp = brokerWeekSplit({ ...base, x, brkPct });
        expect(sp.brokerage.self).toBeGreaterThanOrEqual(0);
        expect(sp.brokerage.upline - 39 * 0.4).toBeGreaterThanOrEqual(-1e-9); // M keeps >= 0
        expect(sp.brokerage.self + (sp.brokerage.upline - 39 * 0.4)).toBeCloseTo(mAlone, 6);
      }
    }
    // a client: only the field -> exactly the field
    expect(brokerWeekSplit({ totalPnl: 0, totalBrk: 156, belowClear: 156, x: 58.5 }).brokerage.self).toBe(58.5);
  });

  test('masters: refused until admin allows; then own broker, own DIRECT accounts only', async () => {
    expect((await request(app).get('/harish/brokers')).status).toBe(403);
    expect((await request(app).get('/harish/brokers/access')).body.data.allowed).toBe(false);
    await request(app).put(`/admin/broker-access/${ids.harish}`).send({ allowed: true });
    expect((await request(app).get('/harish/brokers/access')).body.data.allowed).toBe(true);
    harishBroker = (await request(app).post('/harish/brokers').send({ name: 'Harish broker' })).body.data.id;
    // Direct client: fine. A client of his sub-master S (not direct): refused.
    expect((await request(app).post(`/harish/brokers/${harishBroker}/links`).send({ user_id: String(ids.cd), view_only: true })).status).toBe(404);
    // Another master's client: refused. The admin's broker: not his.
    expect((await request(app).post(`/harish/brokers/${harishBroker}/links`).send({ user_id: String(ids.ef), view_only: true })).status).toBe(404);
    expect((await request(app).post(`/harish/brokers/${adminBroker}/links`).send({ user_id: String(ids.ab), view_only: true })).status).toBe(404);
    // Sub-master S is his direct sub-master; S itself is not allowed.
    expect((await request(app).post(`/harish/brokers/${harishBroker}/master-links`).send({ master_id: String(ids.sub), pnl_share_pct: 10 })).status).toBe(201);
    expect((await request(app).get('/sub/brokers')).status).toBe(403);
    const list = await request(app).get('/harish/brokers');
    expect(list.body.data.map((b) => b.name)).toEqual(['Harish broker']);
    const st = await request(app).get(`/harish/brokers/${harishBroker}/statement`).query({ weeks: 1 });
    expect(st.body.data.weeks[0].rows[0].pnl).toEqual({ total: 5000, below: 1500, self: 500, upline: 3000 });
  });

  test('FIRST PRIORITY: every report is exactly the same after all of the above', async () => {
    const after = await allReports();
    expect(after).toEqual(before);
  });

  test('code guard: the ledger, weekly, settlement, sharing, brokerage and metrics code never reads broker data', () => {
    const fs = require('fs');
    const protectedFiles = [
      'controllers/weeklyAdminController.js', 'controllers/settlementController.js', 'services/settlementService.js',
      'services/settlementReportService.js', 'services/weeklySummaryService.js', 'services/weeklyReportCache.js',
      'services/brokerageService.js', 'services/metricsEngine.js', 'services/hierarchySettlementCalcService.js',
      'models/LedgerEntry.js', 'models/WeeklySummary.js', 'models/User.js', 'models/Master.js', 'models/Trade.js',
    ];
    for (const f of protectedFiles) {
      const src = fs.readFileSync(path.join(__dirname, '../src', f), 'utf8');
      expect([f, /BrokerClientLink|BrokerMasterLink|MasterBrokerAccess|brokerStatement|brokerLinks|brokerEarnings|models\/Broker\b/.test(src)]).toEqual([f, false]);
    }
  });
});
