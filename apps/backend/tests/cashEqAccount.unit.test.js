// Equity M5: live account — client money, margin per category, funded, two-rate interest,
// P&L since the month-end at live prices, holdings, limit use, loss alert; master totals.

process.env.JWT_SECRET = 'cash-eq-test-secret';

const redisStore = {};
jest.mock('../src/services/redisService', () => ({
  getClient: () => ({ get: async (k) => (k in redisStore ? redisStore[k] : null) }),
  isAvailable: () => true,
}));
jest.mock('../src/cashEq/models', () => {
  const actual = jest.requireActual('../src/cashEq/models');
  const { makeFake } = require('./helpers/cashEqFakeDb');
  const out = {};
  for (const [k, v] of Object.entries(actual)) out[k] = makeFake(v);
  return out;
});
jest.mock('../src/models/Admin', () => ({ exists: jest.fn(async () => null), findById: jest.fn() }));

const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const models = require('../src/cashEq/models');
const engine = require('../src/cashEq/engine');
const cashSwitch = require('../src/cashEq/switch');
const feed = require('../src/cashEq/feed');

const app = express();
app.use(express.json());
app.use('/api/cash-eq', require('../src/cashEq/routes'));

const L = 1e5;
const CR = 1e7;
const BIG = 222; // approved (MTF)
const THIN = 111; // non-approved
const today = engine.istNow().date;
const bearer = (id, role) => ({ Authorization: `Bearer ${jwt.sign({ id: String(id), role }, process.env.JWT_SECRET)}` });

let seq = 0;
async function trade(clientId, token, symbol, mtf, side, qty, price, time = '10:00:00') {
  return models.EqTrade.create({
    seq: ++seq, client_id: clientId, order_id: '64b0000000000000000000ff', instrument_token: token, tradingsymbol: symbol,
    mtf, side, qty, price, date: today, add_time: `${today} ${time}`,
  });
}
const ltp = (token, price) => feed.quotes.set(token, { instrument_token: token, last_price: price, change_percent: 1 });

let master;
let other;
let client;
let poor;
const rates = {
  brokerage_mtf: { mode: 'PCT', intraday: 0.02, carry: 0.1 }, brokerage_non: { mode: 'PCT', intraday: 0.05, carry: 0.3 },
  interest_mtf_pct: 15, interest_non_pct: 20,
};

beforeEach(async () => {
  for (const m of Object.values(models)) m.reset();
  for (const k of Object.keys(redisStore)) delete redisStore[k];
  redisStore['cashEq:enabled'] = '1';
  cashSwitch._clearCache();
  feed.quotes.clear();
  seq = 0;
  const mk = (username, extra = {}) => models.EqMaster.create({ name: username, username, password: 'x', per_script_limit: 25 * L, total_limit: 2 * CR, ...rates, pnl_share: 40, brokerage_share: 50, interest_share: 50, ...extra });
  master = await mk('EQMASTER');
  other = await mk('EQOTHER');
  const mkc = async (username, opening, masterId = master._id) => {
    const c = await models.EqClient.create({ name: username, username, password: 'x', master_id: masterId, per_script_limit: 25 * L, total_limit: 2 * CR, opening_balance: opening, opening_type: 'Cr', ...rates });
    c.active_token = jwt.sign({ id: String(c._id), role: 'cash_client' }, process.env.JWT_SECRET);
    await c.save();
    return c;
  };
  client = await mkc('EQA001', 10 * L);
  poor = await mkc('EQP001', 10000);
  await models.EqInstrument.create({ instrument_token: BIG, tradingsymbol: 'BIGCO', name: 'BIG CO', mtf: true });
  await models.EqInstrument.create({ instrument_token: THIN, tradingsymbol: 'THINCO', name: 'THIN CO', mtf: false });
});

describe('client account', () => {
  beforeEach(async () => {
    await trade(client._id, BIG, 'BIGCO', true, 'B', 1000, 1000); // carry 0.1 % → net 1001
    await trade(client._id, THIN, 'THINCO', false, 'B', 500, 200); // carry 0.3 % → net 200.6
    await models.EqLedgerEntry.create({ client_id: client._id, date: today, kind: 'DEPOSIT', amount: 50000, narration: 'bank' });
    ltp(BIG, 1010);
    ltp(THIN, 190);
  });

  test('summary: client money, margin per category, funded, two-rate interest, P&L at live prices', async () => {
    const r = await request(app).get('/api/cash-eq/account').set({ Authorization: `Bearer ${client.active_token}` }).expect(200);
    const s = r.body.data.summary;
    const marginMtf = 1000 * 1001;
    const marginNon = 500 * 200.6;
    const funded = marginMtf + marginNon - 1050000;
    const interest = funded * (marginMtf / (marginMtf + marginNon)) * 0.15 / 365 + funded * (marginNon / (marginMtf + marginNon)) * 0.20 / 365;
    expect(s).toMatchObject({
      client_money: 1050000,
      margin_used: 1101300,
      margin_approved: 1001000,
      margin_non_approved: 100300,
      funded: 51300,
      interest_this_month: engine.round2(interest),
      booked_pnl: 0,
      open_mtm: 3700, // (1010 − 1001) × 1000 + (190 − 200.6) × 500
      pnl_since_month_end: 3700,
      brokerage_this_month: 1300,
      holdings_value: 1105000,
      loss_alert: false,
      loss_pct_of_money: null,
    });
    expect(s.net_equity).toBe(engine.round2(1050000 + 3700 - interest));
    expect(s.limits).toMatchObject({ total_used: 1101300, total_room: 2 * CR - 1101300 });
  });

  test('holdings A→Z with category, net average, live price, MTM and per-script room', async () => {
    const r = await request(app).get('/api/cash-eq/account').set({ Authorization: `Bearer ${client.active_token}` }).expect(200);
    expect(r.body.data.holdings).toEqual([
      expect.objectContaining({ script: 'BIGCO', approved: true, qty: 1000, avg_price: 1001, ltp: 1010, live: true, value: 1010000, mtm: 9000, margin: 1001000, per_script_room: 25 * L - 1001000 }),
      expect.objectContaining({ script: 'THINCO', approved: false, qty: 500, avg_price: 200.6, ltp: 190, mtm: -5300, margin: 100300 }),
    ]);
  });

  test('a sale books P&L (FIFO, net of brokerage) and frees margin and limit room', async () => {
    await trade(client._id, BIG, 'BIGCO', true, 'S', 400, 1020, '11:00:00');
    const r = await request(app).get('/api/cash-eq/account').set({ Authorization: `Bearer ${client.active_token}` }).expect(200);
    const s = r.body.data.summary;
    // Same-day sale → 400 of the buy is intraday (0.02 %), 600 delivery (0.1 %). Trade Terminal
    // folds both into one net rate for the buy: (400 × 0.2 + 600 × 1) / 1000 = 0.68 → 1000.68.
    const buyNet = 1000 + (400 * 1000 * 0.0002 + 600 * 1000 * 0.001) / 1000;
    expect(r.body.data.holdings[0]).toMatchObject({ script: 'BIGCO', qty: 600 });
    expect(s.booked_pnl).toBeGreaterThan(0);
    expect(s.pnl_since_month_end).toBe(engine.round2(s.booked_pnl + s.open_mtm));
    expect(buyNet).toBeCloseTo(1000.68, 10);
    expect(s.margin_approved).toBe(engine.round2(600 * buyNet)); // the 400 sold the same day used no margin
    expect(s.booked_pnl).toBe(engine.round2(400 * ((1020 - 1020 * 0.0002) - buyNet)));
  });

  test('a manager reads a client in its tree; another tree and other clients are refused', async () => {
    await request(app).get(`/api/cash-eq/account?client_id=${client._id}`).set(bearer(master._id, 'cash_master')).expect(200);
    await request(app).get(`/api/cash-eq/account?client_id=${client._id}`).set(bearer(other._id, 'cash_master')).expect(403);
    await request(app).get(`/api/cash-eq/account?client_id=${poor._id}`).set({ Authorization: `Bearer ${client.active_token}` }).expect(403);
  });

  test('statement: opening, deposit, buys with margin, funded and closing money', async () => {
    const r = await request(app).get('/api/cash-eq/statement').set({ Authorization: `Bearer ${client.active_token}` }).expect(200);
    const kinds = r.body.data.rows.map((x) => x.kind);
    expect(kinds).toEqual(['BF', 'DEPOSIT', 'BUY', 'BUY']);
    expect(r.body.data.closing).toMatchObject({ money: 1050000, margin: 1101300, funded: 51300 });
  });
});

describe('loss alert (alert only, no cut)', () => {
  test('loss at 90 % of client money is flagged', async () => {
    await trade(poor._id, THIN, 'THINCO', false, 'B', 1000, 100); // net 100.30
    ltp(THIN, 91.3); // −9,000 on 10,000 client money
    const r = await request(app).get(`/api/cash-eq/account?client_id=${poor._id}`).set(bearer(master._id, 'cash_master')).expect(200);
    expect(r.body.data.summary.loss_alert).toBe(true);
    expect(r.body.data.summary.loss_pct_of_money).toBeGreaterThanOrEqual(90);
  });
});

describe('master screens', () => {
  beforeEach(async () => {
    await trade(client._id, BIG, 'BIGCO', true, 'B', 1000, 1000);
    await trade(poor._id, THIN, 'THINCO', false, 'B', 1000, 100);
    ltp(BIG, 1010);
    ltp(THIN, 91.3);
  });

  test('accounts: every client of the tree with totals; loss alerts counted', async () => {
    const r = await request(app).get('/api/cash-eq/accounts').set(bearer(master._id, 'cash_master')).expect(200);
    expect(r.body.data.accounts.map((a) => a.client.username)).toEqual(['EQA001', 'EQP001']);
    expect(r.body.data.totals).toMatchObject({ clients: 2, holdings_value: 1010000 + 91300, loss_alerts: 1 });
  });

  test('holdings: one list across clients, A→Z, with client names', async () => {
    const r = await request(app).get('/api/cash-eq/holdings').set(bearer(master._id, 'cash_master')).expect(200);
    expect(r.body.data.holdings.map((h) => [h.script, h.client.username, h.qty])).toEqual([['BIGCO', 'EQA001', 1000], ['THINCO', 'EQP001', 1000]]);
    expect(r.body.data.totals.clients).toBe(2);
  });

  test('another master sees none of them; a client can\'t use these screens', async () => {
    const r = await request(app).get('/api/cash-eq/accounts').set(bearer(other._id, 'cash_master')).expect(200);
    expect(r.body.data.totals.clients).toBe(0);
    await request(app).get(`/api/cash-eq/accounts?master_id=${master._id}`).set(bearer(other._id, 'cash_master')).expect(403);
    await request(app).get('/api/cash-eq/holdings').set({ Authorization: `Bearer ${client.active_token}` }).expect(403);
  });
});
