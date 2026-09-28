'use strict';

// max_qty 0 = script not tradable for the account (e.g. the INDEX ONLY group
// gives every NFO script except NIFTY/BANKNIFTY a 0): opening or adding is
// refused, reducing/closing is allowed. A positive max stays a size cap and a
// script with no row stays unlimited (unchanged).

jest.mock('../src/models/KiteInstrument', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/ScriptQuantity', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/Trade', () => ({ aggregate: jest.fn() }));

const KiteInstrument = require('../src/models/KiteInstrument');
const ScriptQuantity = require('../src/models/ScriptQuantity');
const Trade = require('../src/models/Trade');
const { _validateScriptQuantityLimit: check } = require('../src/controllers/tradeController')._private;

const user = { _id: 'u1', exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true }] };
const withSession = (v) => ({ session: () => Promise.resolve(v) });
const position = (net) => withSession(net === 0 ? [] : [{ total_buy_qty: Math.max(net, 0), total_sell_qty: Math.max(-net, 0) }]);

function setup({ max, net = 0 }) {
  KiteInstrument.findOne.mockResolvedValue({ raw_name: 'RELIANCE', lot_size: 500 });
  ScriptQuantity.findOne.mockReturnValue(withSession(max === undefined ? null : { max_qty: max, brk_qty: 0, lot_size: 500 }));
  Trade.aggregate.mockReturnValue(position(net));
}

const run = (side, qty) => check(user, 't1', side, qty, 'NFO-FUT', 'NFO', 'RELIANCE26OCTFUT', null);

beforeEach(() => jest.clearAllMocks());

test('max 0, no position: opening is refused (403)', async () => {
  setup({ max: 0 });
  await expect(run('BUY', 500)).rejects.toMatchObject({ status: 403, message: expect.stringContaining('not allowed') });
  await expect(run('SELL', 500)).rejects.toMatchObject({ status: 403 });
});

test('max 0, existing long: adding refused, reducing/closing allowed, reversing past zero refused', async () => {
  setup({ max: 0, net: 1000 });
  await expect(run('BUY', 500)).rejects.toMatchObject({ status: 403 });
  await expect(run('SELL', 500)).resolves.toMatchObject({ instrumentRawName: 'RELIANCE' });
  await expect(run('SELL', 1000)).resolves.toBeDefined();
  await expect(run('SELL', 2500)).rejects.toMatchObject({ status: 403 });
});

test('no row: still unlimited (unchanged)', async () => {
  setup({ max: undefined });
  await expect(run('BUY', 100000)).resolves.toBeDefined();
});

test('positive max: still a normal size cap (unchanged)', async () => {
  setup({ max: 3000 });
  await expect(run('BUY', 3000)).resolves.toBeDefined();
  await expect(run('BUY', 3500)).rejects.toThrow('maximum position limit');
});
