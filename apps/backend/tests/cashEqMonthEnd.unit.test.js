// Equity M6: month-end at the NSE bhav close (spec §6, worked example §8), the confirm
// rules, manual prices, delete/redo, and master sharing (ceiling P&L, rate-gap brokerage
// and interest) adding up to exactly the client's total.

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
const ADMIN_ID = '64b0000000000000000000a1';
jest.mock('../src/models/Admin', () => ({
  exists: jest.fn(async () => null),
  findById: jest.fn((id) => {
    const v = String(id) === '64b0000000000000000000a1' ? { _id: id, username: 'admin', watch_only: false } : null;
    return { select: () => ({ lean: async () => v }) };
  }),
}));
const bhavFiles = {};
jest.mock('axios', () => ({
  get: jest.fn(async (url) => {
    const m = /sec_bhavdata_full_(\d{8})\.csv$/.exec(url);
    if (m && bhavFiles[m[1]]) return { data: bhavFiles[m[1]] };
    const err = new Error('Request failed with status code 404');
    err.response = { status: 404 };
    throw err;
  }),
}));

const express = require('express');
const request = require('supertest');
const jwt = require('jsonwebtoken');
const models = require('../src/cashEq/models');
const engine = require('../src/cashEq/engine');
const cashSwitch = require('../src/cashEq/switch');
const monthEnd = require('../src/cashEq/monthEnd');
const sharing = require('../src/cashEq/sharing');

const app = express();
app.use(express.json());
app.use('/api/cash-eq', require('../src/cashEq/routes'));

const ADMIN = { Authorization: `Bearer ${jwt.sign({ id: ADMIN_ID, role: 'admin' }, process.env.JWT_SECRET)}` };
const as = (id, role) => ({ Authorization: `Bearer ${jwt.sign({ id: String(id), role }, process.env.JWT_SECRET)}` });

const HEAD = 'SYMBOL, SERIES, DATE1, PREV_CLOSE, OPEN_PRICE, HIGH_PRICE, LOW_PRICE, LAST_PRICE, CLOSE_PRICE, AVG_PRICE, TTL_TRD_QNTY, TURNOVER_LACS, NO_OF_TRADES, DELIV_QTY, DELIV_PER';
/** A bhav copy with 150 filler stocks (a real file has ~2,000) plus `rows` [symbol, close, series]. */
function bhav(rows) {
  const filler = Array.from({ length: 150 }, (_, i) => `FILL${i}, EQ, x, 1, 1, 1, 1, 1, 10.00, 1, 1, 1, 1, 1, 1`);
  return [HEAD, ...rows.map(([s, c, series = 'EQ']) => `${s}, ${series}, x, 1, 1, 1, 1, 1, ${c}, 1, 1, 1, 1, 1, 1`), ...filler].join('\n');
}

const pct = (intraday, carry) => ({ mode: 'PCT', intraday, carry });
let m1;
let m2;
let client;
let seq = 0;

async function trade(date, side, qty, price) {
  return models.EqTrade.create({
    seq: ++seq, client_id: client._id, order_id: '64b0000000000000000000ff', instrument_token: 1, tradingsymbol: 'KPIGREEN',
    mtf: false, side, qty, price, date, add_time: `${date} 10:00:00`,
  });
}

beforeEach(async () => {
  for (const m of Object.values(models)) m.reset();
  for (const k of Object.keys(redisStore)) delete redisStore[k];
  for (const k of Object.keys(bhavFiles)) delete bhavFiles[k];
  redisStore['cashEq:enabled'] = '1';
  cashSwitch._clearCache();
  seq = 0;
  // admin → M1 (P&L 60 %, brokerage 50 %, interest 50 %) → M2 (30 / 40 / 40) → client
  m1 = await models.EqMaster.create({
    name: 'Top', username: 'EQTOP', password: 'x', per_script_limit: 1e7, total_limit: 1e8,
    brokerage_mtf: pct(0, 0.2), brokerage_non: pct(0, 0.2), interest_mtf_pct: 10, interest_non_pct: 10,
    pnl_share: 60, brokerage_share: 50, interest_share: 50,
  });
  m2 = await models.EqMaster.create({
    name: 'Sub', username: 'EQSUB', password: 'x', parent_id: m1._id, per_script_limit: 1e7, total_limit: 1e8,
    brokerage_mtf: pct(0, 0.3), brokerage_non: pct(0, 0.3), interest_mtf_pct: 12, interest_non_pct: 12,
    pnl_share: 30, brokerage_share: 40, interest_share: 40,
  });
  client = await models.EqClient.create({
    name: 'C002', username: 'EQC002', password: 'x', master_id: m2._id, per_script_limit: 1e7, total_limit: 1e8,
    brokerage_mtf: pct(0, 0.5), brokerage_non: pct(0, 0.5), interest_mtf_pct: 18, interest_non_pct: 18,
  });
  // Spec §8: BUY 1,000 KPIGREEN @ 352.40 on 28-09, BUY 1,000 @ 321.45 on 06-10 (delivery 0.5 %).
  await trade('2026-09-28', 'B', 1000, 352.40);
  await trade('2026-10-06', 'B', 1000, 321.45);
  bhavFiles['30092026'] = bhav([['KPIGREEN', 358.95], ['KPIGREEN', 359.5, 'BE']]);
  bhavFiles['30102026'] = bhav([['KPIGREEN', 277.30]]);
});

const previewOf = (month) => request(app).post('/api/cash-eq/month-end/preview').set(ADMIN).send({ month });
const confirmOf = (id) => request(app).post(`/api/cash-eq/month-end/${id}/confirm`).set(ADMIN);

describe('bhav copy', () => {
  test('CLOSE_PRICE, EQ series preferred over BE/SM', () => {
    const p = monthEnd.parseBhav(bhav([['ABC', 100.5, 'BE'], ['ABC', 101.25], ['XYZ', 55, 'SM'], ['BOND1', 99, 'GS']]));
    expect([p.ABC, p.XYZ, p.BOND1]).toEqual([101.25, 55, undefined]);
  });
  test('walks back from the month end to the last trading day', async () => {
    const r = await monthEnd.bhavForMonth('2026-10'); // 31-10 is a Saturday → Friday 30-10
    expect(r.price_date).toBe('2026-10-30');
  });
});

describe('spec worked example through the month-end', () => {
  test('September MTM +4,788.00, October MTM −1,27,407.25; carried at 358.95 then 277.30', async () => {
    const sep = await previewOf('2026-09').expect(200);
    expect(sep.body.data.run.price_date).toBe('2026-09-30');
    expect(sep.body.data.clients[0]).toMatchObject({ username: 'EQC002', mtm: 4788, realized: 0, missing_prices: [] });
    await confirmOf(sep.body.data.run._id).expect(200);

    const oct = await previewOf('2026-10').expect(200);
    expect(oct.body.data.clients[0].mtm).toBe(-127407.25);
    // Interest for October is posted with the bill and kept per category for sharing.
    const c = oct.body.data.clients[0];
    expect(c.interest).toBeGreaterThan(0);
    expect(c.interest_non + c.interest_mtf).toBeCloseTo(c.interest, 2);
    await confirmOf(oct.body.data.run._id).expect(200);

    // The client's statement now carries the month-end rows; lots re-open at the close.
    const st = await request(app).get(`/api/cash-eq/statement?client_id=${client._id}&from=2026-09-01&to=2026-11-02`).set(ADMIN).expect(200);
    const kinds = st.body.data.rows.map((r) => [r.kind, r.date]);
    expect(kinds).toEqual(expect.arrayContaining([['MTM', '2026-09-30'], ['INTEREST', '2026-09-30'], ['REVALUE', '2026-10-01'], ['MTM', '2026-10-31'], ['REVALUE', '2026-11-01']]));
    const mtmRows = st.body.data.rows.filter((r) => r.kind === 'MTM').map((r) => r.credit - r.debit);
    expect(mtmRows).toEqual([4788, -127407.25]);
    const carry = engine.carryToSettlement(
      (await require('../src/cashEq/book').loadTrades(client._id)), new Map(), await monthEnd.confirmedSettlements(), '2026-11-02'
    );
    expect(carry.trades.map((t) => [t.tradeType, t.qty, t.rate])).toEqual([['BF', 1000, 277.3], ['BF', 1000, 277.3]]);
  });

  test('months go in order; not before the 1st of the next month; not twice', async () => {
    const oct = await previewOf('2026-10').expect(200);
    expect((await confirmOf(oct.body.data.run._id).expect(400)).body.message).toBe('Confirm 2026-09 first (months go in order)');
    const sep = await previewOf('2026-09').expect(200);
    await confirmOf(sep.body.data.run._id).expect(200);
    expect((await previewOf('2026-09').expect(400)).body.message).toMatch(/already confirmed/);
    const future = engine.istNow().date.slice(0, 7);
    const later = monthEnd.monthBounds(future);
    expect(later.settle > engine.istNow().date).toBe(true);
  });

  test('a held stock without a close blocks confirm until it is entered by hand', async () => {
    bhavFiles['30092026'] = bhav([['OTHER', 10]]);
    const sep = await previewOf('2026-09').expect(200);
    expect(sep.body.data.missing_prices).toEqual(['KPIGREEN']);
    expect((await confirmOf(sep.body.data.run._id).expect(400)).body.message).toBe('No close price for KPIGREEN — enter it first');
    const p = await request(app).patch(`/api/cash-eq/month-end/${sep.body.data.run._id}/prices`).set(ADMIN).send({ prices: { KPIGREEN: 358.95 } }).expect(200);
    expect(p.body.data.missing_prices).toEqual([]);
    expect(p.body.data.run.manual_prices).toEqual([{ symbol: 'KPIGREEN', price: 358.95 }]);
    const done = await confirmOf(sep.body.data.run._id).expect(200);
    expect(done.body.data.clients[0].mtm).toBe(4788);
  });

  test('delete: only the latest confirmed month; everything recalculates', async () => {
    const sep = await previewOf('2026-09').expect(200);
    await confirmOf(sep.body.data.run._id).expect(200);
    const oct = await previewOf('2026-10').expect(200);
    await confirmOf(oct.body.data.run._id).expect(200);
    await request(app).delete(`/api/cash-eq/month-end/${sep.body.data.run._id}`).set(ADMIN).expect(400);
    await request(app).delete(`/api/cash-eq/month-end/${oct.body.data.run._id}`).set(ADMIN).expect(200);
    expect((await monthEnd.confirmedSettlements()).map((s) => s.settleDate)).toEqual(['2026-10-01']);
    // October can be previewed and confirmed again.
    const again = await previewOf('2026-10').expect(200);
    expect(again.body.data.clients[0].mtm).toBe(-127407.25);
  });

  test('only admin runs it; masters and clients are refused', async () => {
    await request(app).post('/api/cash-eq/month-end/preview').set(as(m1._id, 'cash_master')).send({ month: '2026-09' }).expect(403);
    await request(app).get('/api/cash-eq/month-end').set(as(client._id, 'cash_client')).expect(403);
  });

  test('the F&O Saturday settlement window blocks confirm', () => {
    expect(monthEnd.inFnoSettlementWindow(new Date('2026-11-06T22:00:00Z'))).toBe(true); // Sat 03:30 IST
    expect(monthEnd.inFnoSettlementWindow(new Date('2026-11-07T01:00:00Z'))).toBe(false); // Sat 06:30 IST
    expect(monthEnd.inFnoSettlementWindow(new Date('2026-11-04T22:00:00Z'))).toBe(false); // Thu
  });
});

describe('master sharing (ceiling P&L, rate-gap brokerage and interest)', () => {
  let run;
  beforeEach(async () => {
    const sep = await previewOf('2026-09').expect(200);
    await confirmOf(sep.body.data.run._id).expect(200);
    run = await models.EqMonthRun.findOne({ month: '2026-09', status: 'CONFIRMED' }).lean();
  });

  test('the client\'s snapshot: gross P&L before brokerage, clearances at each master\'s own rates', () => {
    const c = run.clients[0];
    expect(c.brokerage).toBe(1762); // 0.5 % of 3,52,400
    expect(c.gross_pnl).toBe(4788 + 1762); // (358.95 − 352.40) × 1,000
    expect(c.chain).toEqual([String(m2._id), String(m1._id)]);
    expect(c.clearances[String(m2._id)].brokerage).toBe(engine.round2(352400 * 0.003));
    expect(c.clearances[String(m1._id)].brokerage).toBe(engine.round2(352400 * 0.002));
    // All held stock is non-approved: the interest is all in the non-approved part.
    expect([c.interest_mtf, c.interest_non]).toEqual([0, c.interest]);
    expect(c.clearances[String(m2._id)].interest).toBe(engine.round2(c.interest * 12 / 18));
    expect(c.clearances[String(m2._id)].brokerage).toBeGreaterThan(0);
  });

  test('M2 (direct master): keeps its markup + 40 % of its own clearance; 30 % of the P&L', async () => {
    const r = await request(app).get('/api/cash-eq/sharing?month=2026-09').set(as(m2._id, 'cash_master')).expect(200);
    const row = r.body.data.rows[0];
    const c = run.clients[0];
    const cl = c.clearances[String(m2._id)];
    expect(row).toMatchObject({ type: 'client', username: 'EQC002', total_pnl: -6550 });
    expect(row.caller_pnl).toBe(engine.round2(-6550 * 0.30));
    expect(row.caller_brk).toBe(engine.round2(1762 - cl.brokerage + cl.brokerage * 0.40));
    expect(row.owed_up_brk).toBe(engine.round2(cl.brokerage * 0.60));
    expect(row.caller_int).toBe(engine.round2(c.interest - cl.interest + cl.interest * 0.40));
  });

  test('every level\'s cut adds up to the client\'s total — P&L, brokerage and interest', async () => {
    const view = async (h) => (await request(app).get('/api/cash-eq/sharing?month=2026-09').set(h).expect(200)).body.data.totals;
    const a = await view(ADMIN);
    const t1 = await view(as(m1._id, 'cash_master'));
    const t2 = await view(as(m2._id, 'cash_master'));
    const c = run.clients[0];
    expect(engine.round2(a.caller_pnl + t1.caller_pnl + t2.caller_pnl)).toBe(-c.gross_pnl);
    expect(engine.round2(a.caller_brk + t1.caller_brk + t2.caller_brk)).toBeCloseTo(c.brokerage, 1);
    expect(engine.round2(a.caller_int + t1.caller_int + t2.caller_int)).toBeCloseTo(c.interest, 1);
    expect(a.owed_up_total).toBe(0); // admin owes nobody
    // P&L by the ceiling model: admin 40 %, top master 30 % (60 − 30), sub-master 30 %.
    expect([a.caller_pnl, t1.caller_pnl, t2.caller_pnl]).toEqual([-2620, -1965, -1965]);
  });

  test('a master outside the chain sees nothing; a month not confirmed is refused', async () => {
    const other = await models.EqMaster.create({ name: 'O', username: 'EQOTH', password: 'x', per_script_limit: 1, total_limit: 1, interest_mtf_pct: 0, interest_non_pct: 0, pnl_share: 10, brokerage_share: 10, interest_share: 10 });
    const r = await request(app).get('/api/cash-eq/sharing?month=2026-09').set(as(other._id, 'cash_master')).expect(200);
    expect(r.body.data.rows).toEqual([]);
    await request(app).get('/api/cash-eq/sharing?month=2026-10').set(ADMIN).expect(404);
  });

  test('pure: shares stay as confirmed even if a master\'s share changes later', () => {
    const changed = { ...run, masters: run.masters.map((m) => ({ ...m })) };
    const before = sharing.statement({ role: 'cash_master', id: String(m2._id) }, changed);
    expect(before.shares).toEqual({ pnl: 30, brokerage: 40, interest: 40 });
  });
});
