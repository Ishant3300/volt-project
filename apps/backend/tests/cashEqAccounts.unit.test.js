// Equity accounts (M2): waterfall create/edit through the real routes, sign-in, the
// on/off switch, and the separation from F&O in both directions.

process.env.JWT_SECRET = 'cash-eq-test-secret';

const redisStore = {};
jest.mock('../src/services/redisService', () => ({
  getClient: () => ({ get: async (k) => (k in redisStore ? redisStore[k] : null) }),
  isAvailable: () => true,
}));
jest.mock('../src/cashEq/models', () => {
  const actual = jest.requireActual('../src/cashEq/models');
  const { makeFake } = require('./helpers/cashEqFakeDb');
  return {
    EqMaster: makeFake(actual.EqMaster),
    EqClient: makeFake(actual.EqClient),
    EqLedgerEntry: makeFake(actual.EqLedgerEntry),
    EqAudit: makeFake(actual.EqAudit),
  };
});
const ADMIN_ID = '64b0000000000000000000a1';
const WATCH_ID = '64b0000000000000000000a2';
const lean = (v) => ({ select: () => ({ lean: async () => v }), lean: async () => v });
jest.mock('../src/models/Admin', () => ({
  exists: jest.fn(async () => null),
  findById: jest.fn((id) => lean(
    String(id) === '64b0000000000000000000a1' ? { _id: id, username: 'admin', watch_only: false }
      : String(id) === '64b0000000000000000000a2' ? { _id: id, username: 'watcher', watch_only: true } : null
  )),
}));
jest.mock('../src/models/Master', () => ({ exists: jest.fn(async (q) => (q.username === 'EQTAKEN' ? { _id: 1 } : null)), findById: jest.fn() }));
jest.mock('../src/models/User', () => ({ exists: jest.fn(async () => null), findById: jest.fn() }));

const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const models = require('../src/cashEq/models');
const cashSwitch = require('../src/cashEq/switch');
const { tryLogin } = require('../src/cashEq/auth');
const foAuth = require('../src/middlewares/auth');

const app = express();
app.use(express.json());
app.use('/api/cash-eq', require('../src/cashEq/routes'));

const L = 1e5;
const CR = 1e7;
const tok = (id, role) => jwt.sign({ id, role, investor: false }, process.env.JWT_SECRET);
const ADMIN = tok(ADMIN_ID, 'admin');
const WATCHER = tok(WATCH_ID, 'admin');
const auth = (t) => ({ Authorization: `Bearer ${t}` });
const fakeReq = (ua = 'Mozilla/5.0') => ({ ip: '1.2.3.4', headers: { 'user-agent': ua }, get: (h) => (h.toLowerCase() === 'user-agent' ? ua : undefined) });

const masterBody = (over = {}) => ({
  name: 'Harry Equity', username: 'EQHARRY', password: 'secret1',
  per_script_limit: 25 * L, total_limit: 2 * CR, interest_mtf_pct: 12, interest_non_pct: 15,
  brokerage_mtf: { mode: 'PCT', intraday: 0.02, carry: 0.06 }, brokerage_non: { mode: 'PCT', intraday: 0.03, carry: 0.1 },
  pnl_share: 40, brokerage_share: 50, interest_share: 50, ...over,
});
const clientBody = (over = {}) => ({
  name: 'Ramesh K', username: 'EQ100001', password: 'secret1', opening_balance: 10 * L, opening_type: 'Cr',
  per_script_limit: 20 * L, total_limit: 1 * CR, interest_mtf_pct: 18, interest_non_pct: 21,
  brokerage_mtf: { mode: 'PCT', intraday: 0.03, carry: 0.1 }, brokerage_non: { mode: 'PCT', intraday: 0.04, carry: 0.15 }, ...over,
});

/** Sign in through tryLogin and clear the first-login password change. */
async function signIn(username) {
  const r = await tryLogin(username, 'secret1', fakeReq());
  expect(r.status).toBe(200);
  let { token } = r.body.data;
  if (r.body.data.requires_password_change) {
    await request(app).post('/api/cash-eq/me/password').set(auth(token)).send({ current_password: 'secret1', new_password: 'secret2' }).expect(200);
    const again = await tryLogin(username, 'secret2', fakeReq());
    token = again.body.data.token;
  }
  return token;
}

beforeEach(() => {
  for (const m of Object.values(models)) m.reset();
  for (const k of Object.keys(redisStore)) delete redisStore[k];
  redisStore['cashEq:enabled'] = '1';
  cashSwitch._clearCache();
});

describe('on/off switch', () => {
  test('off: every route answers 404 and equity sign-in falls through (null)', async () => {
    await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody()).expect(201);
    delete redisStore['cashEq:enabled'];
    cashSwitch._clearCache();
    await request(app).get('/api/cash-eq/masters').set(auth(ADMIN)).expect(404);
    await expect(tryLogin('EQHARRY', 'secret1', fakeReq())).resolves.toBeNull();
  });
  test('non-EQ usernames never reach the equity lookup', async () => {
    await expect(tryLogin('811428', 'x', fakeReq())).resolves.toBeNull();
  });
});

describe('waterfall through the routes', () => {
  test('admin → master → sub-master → clients, every cap and floor enforced', async () => {
    const created = await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody()).expect(201);
    expect(created.body.data.password).toBeUndefined();
    expect(created.body.data.parent_id).toBeNull();

    const harry = await signIn('EQHARRY');

    // Client above the master's 25 L per script: refused.
    const tooBig = await request(app).post('/api/cash-eq/clients').set(auth(harry)).send(clientBody({ per_script_limit: 30 * L })).expect(400);
    expect(tooBig.body.message).toBe('Per-script limit can\'t be above 25 L (EQHARRY)');
    // Brokerage below the master: refused.
    await request(app).post('/api/cash-eq/clients').set(auth(harry)).send(clientBody({ brokerage_non: { mode: 'PCT', intraday: 0.02, carry: 0.15 } })).expect(400);
    const c1 = await request(app).post('/api/cash-eq/clients').set(auth(harry)).send(clientBody()).expect(201);
    expect(c1.body.data.master_id).toBe(created.body.data._id);

    // Sub-master: share above the parent refused, then created.
    await request(app).post('/api/cash-eq/masters').set(auth(harry)).send(masterBody({ username: 'EQSUB1', pnl_share: 45 })).expect(400);
    const subRes = await request(app).post('/api/cash-eq/masters').set(auth(harry))
      .send(masterBody({ username: 'EQSUB1', pnl_share: 30, per_script_limit: 20 * L, total_limit: 1 * CR, interest_mtf_pct: 15, interest_non_pct: 18, brokerage_mtf: { mode: 'PCT', intraday: 0.025, carry: 0.08 }, brokerage_non: { mode: 'PCT', intraday: 0.035, carry: 0.12 } })).expect(201);
    expect(subRes.body.data.parent_id).toBe(created.body.data._id);

    const sub = await signIn('EQSUB1');
    // Sub-master's client is capped by the sub-master (20 L), not by harry (25 L).
    const r = await request(app).post('/api/cash-eq/clients').set(auth(sub)).send(clientBody({ username: 'EQ100002', per_script_limit: 22 * L })).expect(400);
    expect(r.body.message).toMatch(/can't be above 20 L \(EQSUB1\)/);
    const c2 = await request(app).post('/api/cash-eq/clients').set(auth(sub)).send(clientBody({ username: 'EQ100002', per_script_limit: 10 * L })).expect(201);

    // Visibility: harry sees the whole tree, the sub-master only its own.
    const harryList = await request(app).get('/api/cash-eq/clients').set(auth(harry)).expect(200);
    expect(harryList.body.data.map((c) => c.username).sort()).toEqual(['EQ100001', 'EQ100002']);
    const subList = await request(app).get('/api/cash-eq/clients').set(auth(sub)).expect(200);
    expect(subList.body.data.map((c) => c.username)).toEqual(['EQ100002']);
    await request(app).get(`/api/cash-eq/clients/${c1.body.data._id}`).set(auth(sub)).expect(403);
    await request(app).get(`/api/cash-eq/clients/${c2.body.data._id}`).set(auth(harry)).expect(200);

    // A master can't edit itself; its parent (or admin) can — but not below what it gave out.
    await request(app).patch(`/api/cash-eq/masters/${created.body.data._id}`).set(auth(harry)).send({ per_script_limit: 50 * L }).expect(403);
    const lower = await request(app).patch(`/api/cash-eq/masters/${created.body.data._id}`).set(auth(ADMIN)).send({ per_script_limit: 15 * L }).expect(400);
    expect(lower.body.data.errors).toEqual(expect.arrayContaining([
      'EQSUB1: Per-script limit can\'t be above 15 L', 'EQ100001: Per-script limit can\'t be above 15 L',
    ]));
    await request(app).patch(`/api/cash-eq/masters/${created.body.data._id}`).set(auth(ADMIN)).send({ per_script_limit: 22 * L }).expect(200);
    // Sub-master tries to raise its own clients' cap above its own: refused.
    await request(app).patch(`/api/cash-eq/clients/${c2.body.data._id}`).set(auth(sub)).send({ per_script_limit: 21 * L }).expect(400);

    // Can't delete a master that still has clients / sub-masters.
    await request(app).delete(`/api/cash-eq/masters/${subRes.body.data._id}`).set(auth(harry)).expect(400);

    // Every change is in the equity audit log.
    expect([...models.EqAudit.store.values()].map((a) => a.action)).toEqual(expect.arrayContaining(['master_create', 'client_create', 'master_update']));
  });

  test('usernames: EQ prefix, unique across F&O and equity', async () => {
    await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody({ username: 'harry' })).expect(400);
    await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody({ username: 'EQTAKEN' })).expect(409);
    await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody()).expect(201);
    await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody({ name: 'again' })).expect(409);
    const g = await request(app).get('/api/cash-eq/username/generate').set(auth(ADMIN)).expect(200);
    expect(g.body.data.username).toMatch(/^EQ\d{6}$/);
  });

  test('watch-only admin can look but not change', async () => {
    await request(app).get('/api/cash-eq/masters').set(auth(WATCHER)).expect(200);
    await request(app).post('/api/cash-eq/masters').set(auth(WATCHER)).send(masterBody()).expect(403);
  });
});

describe('equity clients', () => {
  async function setup() {
    const m = await request(app).post('/api/cash-eq/masters').set(auth(ADMIN)).send(masterBody()).expect(201);
    const c = await request(app).post('/api/cash-eq/clients').set(auth(ADMIN)).send(clientBody({ master_id: m.body.data._id })).expect(201);
    return { masterId: m.body.data._id, clientId: c.body.data._id };
  }

  test('ledger entries: added by the master, seen by the client, dated today or earlier', async () => {
    const { clientId } = await setup();
    const harry = await signIn('EQHARRY');
    await request(app).post(`/api/cash-eq/clients/${clientId}/ledger`).set(auth(harry)).send({ kind: 'DEPOSIT', amount: 50000, narration: 'by bank' }).expect(201);
    await request(app).post(`/api/cash-eq/clients/${clientId}/ledger`).set(auth(harry)).send({ kind: 'DEPOSIT', amount: 1, date: '2999-01-01' }).expect(400);
    await request(app).post(`/api/cash-eq/clients/${clientId}/ledger`).set(auth(harry)).send({ kind: 'BONUS', amount: 1 }).expect(400);

    const client = await signIn('EQ100001');
    const mine = await request(app).get('/api/cash-eq/ledger').set(auth(client)).expect(200);
    expect(mine.body.data).toHaveLength(1);
    expect(mine.body.data[0]).toMatchObject({ kind: 'DEPOSIT', amount: 50000 });
    // A client can't use manager routes.
    await request(app).get('/api/cash-eq/masters').set(auth(client)).expect(403);
    await request(app).get('/api/cash-eq/clients').set(auth(client)).expect(403);
  });

  test('one session per client: a new sign-in ends the old one', async () => {
    await setup();
    const first = await signIn('EQ100001');
    await request(app).get('/api/cash-eq/me').set(auth(first)).expect(200);
    await tryLogin('EQ100001', 'secret2', fakeReq());
    await request(app).get('/api/cash-eq/me').set(auth(first)).expect(401);
  });

  test('opening balance and delete are locked after the first trade', async () => {
    const { clientId } = await setup();
    await request(app).patch(`/api/cash-eq/clients/${clientId}`).set(auth(ADMIN)).send({ opening_balance: 5 * L }).expect(200);
    const doc = models.EqClient.store.get(clientId);
    doc.first_trade_at = new Date();
    await request(app).patch(`/api/cash-eq/clients/${clientId}`).set(auth(ADMIN)).send({ opening_balance: 7 * L }).expect(400);
    await request(app).delete(`/api/cash-eq/clients/${clientId}`).set(auth(ADMIN)).expect(400);
  });

  test('the app can\'t sign equity accounts in until a build is allowed', async () => {
    await setup();
    const ua = 'Volt/1.0.53+56 (Android 14; SM-A145F)';
    const r = await tryLogin('EQ100001', 'secret1', fakeReq(ua));
    expect(r.status).toBe(403);
    redisStore['cashEq:minAppBuild'] = '56';
    cashSwitch._clearCache();
    expect((await tryLogin('EQ100001', 'secret1', fakeReq(ua))).status).toBe(200);
  });
});

describe('separation from F&O', () => {
  test('F&O client and master tokens are refused on every equity route', async () => {
    for (const role of ['user', 'master']) {
      const t = tok('64b0000000000000000000f1', role);
      for (const [method, path] of [['get', '/api/cash-eq/me'], ['get', '/api/cash-eq/masters'], ['post', '/api/cash-eq/clients'], ['get', '/api/cash-eq/ledger']]) {
        const r = await request(app)[method](path).set(auth(t)).send({});
        expect(r.status).toBe(403);
        expect(r.body.message).toBe('Equity is not available for this account');
      }
    }
  });

  test('equity tokens are refused by every F&O auth middleware', async () => {
    for (const role of ['cash_master', 'cash_client']) {
      const t = tok('64b0000000000000000000e1', role);
      for (const name of ['authenticateUser', 'authenticateAdmin', 'authenticateMaster', 'authenticateAny', 'authenticateAdminOrMaster']) {
        const res = { statusCode: 200, status(c) { this.statusCode = c; return this; }, json(b) { this.body = b; return this; } };
        const next = jest.fn();
        await foAuth[name]({ headers: { authorization: `Bearer ${t}` } }, res, next);
        expect({ name, role, status: res.statusCode, next: next.mock.calls.length }).toEqual({ name, role, status: 403, next: 0 });
      }
      const req = { headers: { authorization: `Bearer ${t}` } };
      const next = jest.fn();
      await foAuth.authenticateOptional(req, {}, next);
      expect([req.user, req.admin, next.mock.calls.length]).toEqual([null, null, 1]);
    }
  });

  test('equity routes never set req.admin / req.master (so the F&O action log skips them)', async () => {
    const probe = express();
    probe.use(express.json());
    const { requireCash } = require('../src/cashEq/auth');
    probe.get('/p', requireCash('admin', 'cash_master', 'cash_client'), (req, res) => res.json({ admin: req.admin ?? null, master: req.master ?? null, cash: req.cash.role }));
    const r = await request(probe).get('/p').set(auth(ADMIN)).expect(200);
    expect(r.body).toEqual({ admin: null, master: null, cash: 'admin' });
  });
});
