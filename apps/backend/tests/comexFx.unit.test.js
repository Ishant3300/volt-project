'use strict';

// COMEX in dollars, billed in rupees (utils/comexFx.js, 25 Oct 2026): the
// weekly settlement converts each client's COMEX net at base + spread when the
// client owes (debit) and base − spread when owed (credit).

jest.mock('../src/models/SettlementHistory', () => ({ find: jest.fn() }));
jest.mock('../src/models/SettlementRun', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/ComexRate', () => ({ findOne: jest.fn(), findOneAndUpdate: jest.fn() }));

const SettlementHistory = require('../src/models/SettlementHistory');
const SettlementRun = require('../src/models/SettlementRun');
const ComexRate = require('../src/models/ComexRate');
const fx = require('../src/utils/comexFx');
const { _private } = require('../src/controllers/weeklyAdminController');
const { setComexRate } = require('../src/controllers/comexRateController');

const FX = { base: 88, spread: 1 };
const lean = (v) => { const c = {}; c.select = jest.fn(() => c); c.session = jest.fn(() => c); c.lean = jest.fn(async () => v); return c; };
const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const snap = (user, exchange, total, brk) => ({ user_id: user, exchange, realized_pnl: total, settlement_pnl: 0, total_pnl: total, brokerage: brk, net_pnl: total - brk });

beforeEach(() => jest.clearAllMocks());

test('debit uses base + spread, credit base − spread', () => {
  expect(fx.rateForNet(-10000, FX)).toBe(89);
  expect(fx.rateForNet(10000, FX)).toBe(87);
  expect(fx.rateForNet(0, FX)).toBe(88);
  expect(fx.rateForNet(5, null)).toBeNull();
});

test('settlement converts each client at one rate from their COMEX net; other segments untouched', () => {
  const loser = [snap('u1', 'COMEX', -12000, 50), snap('u1', 'COMEX', 2000, 10)]; // net −10,060 → 89
  const winner = [snap('u2', 'COMEX', 10000, 40)]; // net 9,960 → 87
  const nfo = snap('u1', 'NFO', 5000, 100);
  const all = [...loser, ...winner, nfo];
  const out = fx.convertComexSnapshots(all, FX);
  expect(out.rates).toEqual({ u1: 89, u2: 87 });
  expect(loser[0]).toMatchObject({ usd_total_pnl: -12000, total_pnl: -12000 * 89, usd_brokerage: 50, brokerage: 50 * 89, net_pnl: -12050 * 89, fx_rate: 89, fx_base: 88, fx_spread: 1, currency: 'USD' });
  expect(loser[1].fx_rate).toBe(89); // the gain line goes at the client's debit rate too
  expect(winner[0]).toMatchObject({ net_pnl: 9960 * 87, usd_net_pnl: 9960, fx_rate: 87 });
  expect(nfo).toEqual(snap('u1', 'NFO', 5000, 100)); // unchanged
  // $10,000 debit = ₹8,90,000; $10,000 credit = ₹8,70,000
  expect(fx.convertComexSnapshots([snap('a', 'COMEX', -10000, 0)], FX).rates.a * 10000).toBe(890000);
});

test('no rate set: refuses to book dollars as rupees, but a COMEX line with no amounts passes', () => {
  expect(() => fx.convertComexSnapshots([snap('u1', 'COMEX', 100, 0)], null)).toThrow(/rate is not set/);
  const flat = [snap('u1', 'COMEX', 0, 0)];
  expect(fx.convertComexSnapshots(flat, null).users).toBe(0);
  expect(flat[0].fx_rate).toBeUndefined();
});

test('bill block: settled week at its booked rate, the unsettled rest as an estimate at today’s rate', () => {
  const instruments = [
    { exchange: 'COMEX', pnl: 7000, brokerage: 60 }, // whole window in $
    { exchange: 'NFO', pnl: 999, brokerage: 9 },
  ];
  const settledSnap = { exchange: 'COMEX', settlement_period_key: 'W43', fx_rate: 87, usd_total_pnl: 10000, usd_brokerage: 40, total_pnl: 870000, brokerage: 3480 };
  const b = fx.comexBillBlock(instruments, [settledSnap], FX);
  expect(b.usd_net).toBe(6940);
  expect(b.settled).toEqual([expect.objectContaining({ period_key: 'W43', fx_rate: 87, usd_net: 9960, inr_net: 866520 })]);
  expect(b.estimate).toEqual({ usd_pnl: -3000, usd_brokerage: 20, usd_net: -3020, fx_rate: 89, inr_net: -268780 });
  expect(b.inr_net).toBe(866520 - 268780);
  expect(fx.comexBillBlock([{ exchange: 'NFO', pnl: 1 }], [], FX)).toBeNull();
  expect(fx.comexBillBlock(instruments, [], null).inr_net).toBeNull(); // no rate: no rupee figure invented
});

test('weekly report: a settled COMEX trade counts in rupees at its settlement rate; unsettled and non-COMEX stay', async () => {
  SettlementHistory.find.mockReturnValue(lean([{ user_id: 'u1', settlement_run_id: 'run1', fx_rate: 89 }]));
  const kiteMap = { g: { exchange: 'COMEX', lot_size: 100 }, n: { exchange: 'NFO', lot_size: 1 } };
  const settled = { instrument_token: 'g', executed_price: 4000, executed_quantity: 100, pnl: -500, settlement_run_id: 'run1' };
  const live = { instrument_token: 'g', executed_price: 4100, executed_quantity: 100, pnl: 0 };
  const nfo = { instrument_token: 'n', executed_price: 100, executed_quantity: 10, pnl: 50, settlement_run_id: 'run1' };
  const tradesByUser = { u1: [settled, live, nfo] };
  await _private._applyComexSettlementRates(tradesByUser, kiteMap);
  const [a, b, c] = tradesByUser.u1;
  expect(a).toMatchObject({ executed_price: 4000 * 89, pnl: -500 * 89, _fx: 89 });
  expect(b).toBe(live);
  expect(c).toBe(nfo);
  // lot-wise brokerage ($/lot) scales with the rate; turnover via the scaled price
  const byInst = _private._groupTradesByInstrument([a], kiteMap);
  expect(byInst.g).toEqual({ turnover: 4000 * 89 * 100, lots: 89 });
});

test('rate endpoint: validates, refuses during a settlement, logs the change', async () => {
  let r = res();
  await setComexRate({ body: { base: 88, spread: 90 }, admin: { username: 'admin' } }, r);
  expect(r.status).toHaveBeenCalledWith(400);

  SettlementRun.findOne.mockReturnValue(lean({ _id: 'x' }));
  r = res();
  await setComexRate({ body: { base: 88, spread: 1 }, admin: { username: 'admin' } }, r);
  expect(r.status).toHaveBeenCalledWith(409);

  SettlementRun.findOne.mockReturnValue(lean(null));
  ComexRate.findOneAndUpdate.mockReturnValue({ lean: async () => ({ base: 88, spread: 1, history: [{ base: 88, spread: 1, by: 'admin' }] }) });
  r = res();
  await setComexRate({ body: { base: '88', spread: '1' }, admin: { username: 'admin' } }, r);
  expect(r.json.mock.calls[0][0].data).toMatchObject({ base: 88, spread: 1, debit_rate: 89, credit_rate: 87 });
  const [, update] = ComexRate.findOneAndUpdate.mock.calls[0];
  expect(update.$push.history.$each[0]).toMatchObject({ base: 88, spread: 1, by: 'admin' });
});
