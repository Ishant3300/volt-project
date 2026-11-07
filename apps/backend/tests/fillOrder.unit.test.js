'use strict';

// Settlement / live metrics replay fills in FILL order (utils/fillOrder.js).
// Real case, 7 Nov 2026 settlement: KK (117905) GIFTNIFTY26NOVFUT, settled at
// 24,766.44. The SL BUY 50 @ 25051 was placed 21:14:40 but filled 21:37:32,
// after the MARKET SELL 50 @ 25039 at 21:36:50. Placement order booked the
// open 200 short at 24,998.875 (46,487); fill order gives 24,996.20 (45,952),
// which matches the cash flow and the web bill.

const { sortByFillTime, byFillTime } = require('../src/utils/fillOrder');
const { _private: { buildPositionGroups } } = require('../src/services/settlementService');

const T = (id, placed, filled, side, qty, price) => ({
  _id: id, user_id: 'kk', instrument_token: '9920261123', transaction_type: side,
  executed_quantity: qty, executed_price: price,
  createdAt: new Date(`2026-11-06T${placed}+05:30`), executed_at: new Date(`2026-11-06T${filled}+05:30`),
});
const fills = [
  T('a1', '20:35:28', '20:35:28', 'SELL', 100, 24935.5),
  T('a2', '20:36:09', '20:44:31', 'BUY', 100, 25006),   // SL
  T('a3', '20:37:37', '20:37:37', 'SELL', 100, 24967.5),
  T('a4', '20:37:55', '20:45:03', 'BUY', 100, 25011),   // SL
  T('a5', '20:48:08', '20:48:08', 'SELL', 100, 25006),
  T('a6', '21:03:29', '21:03:29', 'SELL', 50, 24963),
  T('a7', '21:03:57', '21:03:57', 'SELL', 50, 24967),
  T('a8', '21:14:40', '21:37:32', 'BUY', 50, 25051),    // SL placed early, filled last
  T('a9', '21:36:50', '21:36:50', 'SELL', 50, 25039),
];
const SETTLE = 24766.44;
const settlementPnl = (g) => (g.avgSell - SETTLE) * Math.abs(g.netQty);

test('placement order reproduces the wrong booked figure (46,487)', () => {
  const placed = [...fills].sort((a, b) => a.createdAt - b.createdAt);
  const [g] = buildPositionGroups(placed);
  expect(g.netQty).toBe(-200);
  expect(g.avgSell).toBeCloseTo(24998.875, 6);
  expect(settlementPnl(g)).toBeCloseTo(46487, 2);
});

test('fill order gives the real average and P&L (45,952 = cash flow)', () => {
  const [g] = buildPositionGroups(sortByFillTime([...fills].reverse()));
  expect(g.netQty).toBe(-200);
  expect(g.avgSell).toBeCloseTo(24996.2, 6);
  expect(settlementPnl(g)).toBeCloseTo(45952, 2);
  const cash = fills.reduce((s, t) => s + (t.transaction_type === 'SELL' ? 1 : -1) * t.executed_quantity * t.executed_price, 0) - 200 * SETTLE;
  expect(settlementPnl(g) + (-5450 - 5950 - 2740)).toBeCloseTo(cash, 2);
});

test('ties keep placement order, then _id; missing executed_at falls back to createdAt', () => {
  const at = new Date('2026-11-06T10:00:00Z');
  const x = { _id: 'b', createdAt: new Date('2026-11-06T09:00:00Z'), executed_at: at };
  const y = { _id: 'a', createdAt: new Date('2026-11-06T09:30:00Z'), executed_at: at };
  const legacy = { _id: 'c', createdAt: new Date('2026-11-06T09:45:00Z'), executed_at: null };
  expect([y, legacy, x].sort(byFillTime).map((t) => t._id)).toEqual(['c', 'b', 'a']);
});
