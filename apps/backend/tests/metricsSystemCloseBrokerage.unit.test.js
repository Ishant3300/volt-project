'use strict';

// Live M2M counts the brokerage actually charged on system closes (trade_type
// 'margin_square_off': margin square-off, master square-off, contract-expiry
// auto-close). It used to skip them, so the app's M2M was short of the bill /
// settlement by exactly that brokerage (account 266: 3,407.55 on its GIFT
// NIFTY expiry close).

jest.mock('../src/models/Trade', () => ({ find: jest.fn() }));
const Trade = require('../src/models/Trade');
const metricsEngine = require('../src/services/metricsEngine');

const USER = 'u-syscl';
const trade = (over) => ({
  user_id: USER, instrument_token: '9001', exchange: 'NSEIX', tradingsymbol: 'GIFT NIFTY',
  status: 'completed', deleted_at: null, executed_quantity: 500, executed_price: 22717,
  transaction_type: 'SELL', pnl: 0, createdAt: new Date('2026-09-29T10:01:00Z'), ...over,
});

function mockTrades(list) {
  Trade.find.mockReturnValue({ sort: () => ({ lean: async () => list }) });
}

afterEach(() => metricsEngine._userCache.delete(USER));

test('expiry auto-close: its stored brokerage is counted', async () => {
  mockTrades([
    trade({ transaction_type: 'BUY', executed_price: 22686, trade_type: 'regular', brokerage: 0, brokerage_exempt: true }),
    trade({ trade_type: 'margin_square_off', placed_by: 'SYSTEM', brokerage: 3407.55, pnl: 15500 }),
  ]);
  await metricsEngine._rebuildUserCache(USER, 1500000, 0, null, {}, []);
  expect(metricsEngine._userCache.get(USER).brokerage).toBeCloseTo(3407.55, 2);
});

test('an admin-exempted system close stays at 0, and carry-forward markers never add brokerage', async () => {
  mockTrades([
    trade({ trade_type: 'margin_square_off', brokerage: 999, brokerage_exempt: true }),
    trade({ trade_type: 'carry_forward', brokerage: 555, transaction_type: 'BUY' }),
  ]);
  await metricsEngine._rebuildUserCache(USER, 1500000, 0, null, {}, []);
  expect(metricsEngine._userCache.get(USER).brokerage).toBe(0);
});
