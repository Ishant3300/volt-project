'use strict';

// Fresh Stop-Loss ON lets an SL exceed the open position (user, 5 Nov 2026):
// real case RELIANCE26NOVFUT, long 2000, SELL SL modified to 2500 was refused.

jest.mock('../src/models/Trade', () => ({ find: jest.fn() }));
const Trade = require('../src/models/Trade');
const { _validateSingleOrderTypePerScript: check } = require('../src/controllers/tradeController')._private;

const chain = (rows) => ({ select: () => ({ session: () => ({ lean: async () => rows }) }) });
function setup({ pending = [], completed = [] }) {
  Trade.find.mockImplementation((f) => chain(f.status === 'pending' ? pending : completed));
}
const LONG_2000 = [{ transaction_type: 'BUY', executed_quantity: 2000 }];

beforeEach(() => jest.clearAllMocks());

test('Fresh SL ON: SELL SL 2500 on a 2000 long is allowed (place and modify)', async () => {
  setup({ completed: LONG_2000 });
  const user = { _id: 'u', fresh_stoploss: true };
  await expect(check(user, 't', 'SL', 'SELL', 2500, null)).resolves.toBeUndefined();
  await expect(check(user, 't', 'SL-M', 'SELL', 2500, null, 'trade1')).resolves.toBeUndefined();
});

test('Fresh SL OFF: still capped at the open position', async () => {
  setup({ completed: LONG_2000 });
  await expect(check({ _id: 'u', fresh_stoploss: false }, 't', 'SL', 'SELL', 2500, null))
    .rejects.toThrow(/would exceed your open position \(2000\)/);
  await expect(check({ _id: 'u', fresh_stoploss: false }, 't', 'SL', 'SELL', 2000, null)).resolves.toBeUndefined();
});

test('LIMIT orders keep the cap even with Fresh SL ON', async () => {
  setup({ completed: LONG_2000 });
  await expect(check({ _id: 'u', fresh_stoploss: true }, 't', 'LIMIT', 'SELL', 2500, null))
    .rejects.toThrow(/would exceed your open position/);
});

test('no LIMIT + SL mixing, whatever the toggle', async () => {
  setup({ completed: LONG_2000, pending: [{ order_type: 'LIMIT', transaction_type: 'SELL', quantity: 500 }] });
  await expect(check({ _id: 'u', fresh_stoploss: true }, 't', 'SL', 'SELL', 2500, null))
    .rejects.toThrow(/pending Limit order/);
});
