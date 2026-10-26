'use strict';

// Orders on an NSE future below the client's minimum price (tradeController
// _validateMinNseFutPrice, 26 Oct 2026): opening or adding is refused,
// closing / reducing an existing position always goes through; admin, other
// segments and a minimum of 0 are never affected.

jest.mock('../src/models/Trade', () => ({ aggregate: jest.fn() }));

const Trade = require('../src/models/Trade');
const { _validateMinNseFutPrice: check } = require('../src/controllers/tradeController')._private;

const IDEA = { segment: 'NFO-FUT', settlement_price: 11.36 };
const RELIANCE = { segment: 'NFO-FUT', settlement_price: 1193.4 };
const client = (min) => ({ _id: 'u1', min_nse_fut_price: min });
const holding = (buy, sell) => Trade.aggregate.mockResolvedValue(buy || sell ? [{ total_buy_qty: buy, total_sell_qty: sell }] : []);
const run = (user, inst, side, qty, isAdmin = false) => check(isAdmin, user, inst, 't1', side, qty, null);

beforeEach(() => jest.clearAllMocks());

test('below the minimum, no position: a buy is refused', async () => {
  holding(0, 0);
  await expect(run(client(100), IDEA, 'BUY', 71475)).rejects.toMatchObject({
    status: 403,
    message: 'NSE FUT scripts priced below 100 are not allowed for your account.',
  });
});

test('below the minimum, a short opened: refused too', async () => {
  holding(0, 0);
  await expect(run(client(100), IDEA, 'SELL', 71475)).rejects.toMatchObject({ status: 403 });
});

test('below the minimum: adding to a long is refused, with how much can be closed', async () => {
  holding(71475, 0);
  await expect(run(client(100), IDEA, 'BUY', 71475)).rejects.toMatchObject({
    message: 'NSE FUT scripts priced below 100 are not allowed for your account. You can only close your existing 71475 qty position.',
  });
});

test('below the minimum: closing or reducing an existing position goes through', async () => {
  holding(142950, 0);
  await expect(run(client(100), IDEA, 'SELL', 71475)).resolves.toBeUndefined();
  await expect(run(client(100), IDEA, 'SELL', 142950)).resolves.toBeUndefined();
});

test('below the minimum: closing more than held (a reversal) is refused', async () => {
  holding(71475, 0);
  await expect(run(client(100), IDEA, 'SELL', 142950)).rejects.toMatchObject({ status: 403 });
});

test('at or above the minimum, minimum 0, or admin: allowed without checking positions', async () => {
  await expect(run(client(100), RELIANCE, 'BUY', 500)).resolves.toBeUndefined();
  await expect(run(client(0), IDEA, 'BUY', 71475)).resolves.toBeUndefined();
  await expect(run(client(100), IDEA, 'BUY', 71475, true)).resolves.toBeUndefined();
  expect(Trade.aggregate).not.toHaveBeenCalled();
});

test('other segments are never affected', async () => {
  await expect(run(client(100), { segment: 'NFO-OPT', settlement_price: 5 }, 'BUY', 50)).resolves.toBeUndefined();
  await expect(run(client(100), { segment: 'MCX-FUT', settlement_price: 5 }, 'BUY', 1)).resolves.toBeUndefined();
});
