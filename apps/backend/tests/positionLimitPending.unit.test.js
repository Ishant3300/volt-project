'use strict';

// Per-script position cap with pending orders (real case: client 313738,
// INOXWIND, max 1500, 30 Sep 2026 — holding 1000, a BUY 500 LIMIT was left
// pending, a BUY 500 MARKET filled, then the LIMIT filled too: 2000).
//   1. Placement (_validateScriptQuantityLimit) counts same-side pending orders.
//   2. Fill time (positionLimitService) re-checks the cap before a pending
//      order fills.

jest.mock('../src/models/KiteInstrument', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/ScriptQuantity', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/Trade', () => ({ aggregate: jest.fn() }));

const KiteInstrument = require('../src/models/KiteInstrument');
const ScriptQuantity = require('../src/models/ScriptQuantity');
const Trade = require('../src/models/Trade');
const { _validateScriptQuantityLimit: check } = require('../src/controllers/tradeController')._private;
const { positionLimitRejection } = require('../src/services/positionLimitService');

const withSession = (v) => ({ session: () => Promise.resolve(v) });
const leanChain = (v) => ({ session: () => ({ lean: () => Promise.resolve(v) }) });

const turnoverUser = { _id: 'u1', exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true }] };
const lotUser = { _id: 'u1', exchanges_allowed: [{ exchange_name: 'NFO-FUT', lot: true }] };

// Trade.aggregate answers by the $match status: completed = position, pending = same-side pending total.
function setupPlacement({ max, brk = 0, lotSize = 1, net = 0, pending = 0 }) {
  KiteInstrument.findOne.mockResolvedValue({ raw_name: 'INOXWIND', lot_size: lotSize });
  ScriptQuantity.findOne.mockReturnValue(withSession(max === undefined ? null : { max_qty: max, brk_qty: brk, lot_size: lotSize }));
  Trade.aggregate.mockImplementation((pipeline) => {
    const status = pipeline[0].$match.status;
    if (status === 'pending') return withSession(pending > 0 ? [{ qty: pending }] : []);
    return withSession(net === 0 ? [] : [{ total_buy_qty: Math.max(net, 0), total_sell_qty: Math.max(-net, 0) }]);
  });
}

const place = (user, side, qty, excludeTradeId) =>
  check(user, 't1', side, qty, 'NFO-FUT', 'NFO', 'INOXWIND26OCTFUT', null, excludeTradeId);

beforeEach(() => jest.clearAllMocks());

describe('placement counts same-side pending orders', () => {
  test('INOXWIND replay: holding 1000 + pending BUY 500 -> BUY 500 more is refused', async () => {
    setupPlacement({ max: 1500, brk: 500, net: 1000, pending: 500 });
    await expect(place(turnoverUser, 'BUY', 500)).rejects.toThrow(
      'Max: 1500 qty, Current: 1000 qty, Pending orders: 500 qty, Remaining: 0 qty, Requested: 500 qty',
    );
  });

  test('without the pending order the same BUY 500 is still allowed (unchanged)', async () => {
    setupPlacement({ max: 1500, brk: 500, net: 1000, pending: 0 });
    await expect(place(turnoverUser, 'BUY', 500)).resolves.toBeDefined();
  });

  test('pending + new order exactly at the cap is allowed', async () => {
    setupPlacement({ max: 1500, net: 500, pending: 500 });
    await expect(place(turnoverUser, 'BUY', 500)).resolves.toBeDefined();
  });

  test('closing a long is still allowed alongside a pending SELL (stop + target)', async () => {
    setupPlacement({ max: 1500, net: 1500, pending: 1500 });
    // worst case: 1500 - 1500 - 1500 = -1500 -> not above the cap
    await expect(place(turnoverUser, 'SELL', 1500)).resolves.toBeDefined();
  });

  test('pending SELLs that could flip the position past the cap are counted', async () => {
    setupPlacement({ max: 1000, net: 500, pending: 1000 });
    // 500 - 1000 - 1000 = -1500 -> beyond 1000
    await expect(place(turnoverUser, 'SELL', 1000)).rejects.toThrow('maximum position limit');
  });

  test('modify: the order being modified is excluded from the pending total', async () => {
    setupPlacement({ max: 1500, net: 1000, pending: 0 });
    await expect(place(turnoverUser, 'BUY', 500, 'order-1')).resolves.toBeDefined();
    const pendingCall = Trade.aggregate.mock.calls.find(([p]) => p[0].$match.status === 'pending');
    expect(pendingCall[0][0].$match._id).toEqual({ $ne: 'order-1' });
    expect(pendingCall[0][0].$match.transaction_type).toBe('BUY');
  });

  test('lot mode: pending lots count too', async () => {
    setupPlacement({ max: 3, lotSize: 100, net: 100, pending: 100 });
    await expect(place(lotUser, 'BUY', 100)).resolves.toBeDefined(); // 1 + 1 + 1 = 3 lots
    setupPlacement({ max: 3, lotSize: 100, net: 100, pending: 200 });
    await expect(place(lotUser, 'BUY', 100)).rejects.toThrow('Pending orders: 2 lot(s)');
  });

  test('no limit row: unlimited, and the pending query is skipped', async () => {
    setupPlacement({ max: undefined, net: 1000, pending: 99999 });
    await expect(place(turnoverUser, 'BUY', 100000)).resolves.toBeDefined();
    expect(Trade.aggregate.mock.calls.some(([p]) => p[0].$match.status === 'pending')).toBe(false);
  });

  test('max 0: a pending opening order blocks even a small add', async () => {
    setupPlacement({ max: 0, net: 0, pending: 100 });
    await expect(place(turnoverUser, 'BUY', 1)).rejects.toMatchObject({ status: 403 });
  });
});

describe('fill-time re-check (positionLimitService)', () => {
  const instrument = { segment: 'NFO-FUT', raw_name: 'INOXWIND', lot_size: 6400 };
  const trade = (o = {}) => ({ user_id: 'u1', tradingsymbol: 'INOXWIND26OCTFUT', exchange: 'NFO', transaction_type: 'BUY', quantity: 500, placed_by: 'USER', ...o });
  const row = (r) => ScriptQuantity.findOne.mockReturnValue(leanChain(r));

  test('INOXWIND replay: position 1500, pending BUY 500 fills -> rejected', async () => {
    row({ max_qty: 1500, lot_size: 6400 });
    const remark = await positionLimitRejection({ trade: trade(), previousNetQty: 1500, instrument, user: turnoverUser });
    expect(remark).toBe('Order exceeds maximum position limit at execution. Max: 1500 qty, Position: 1500 qty, Order: 500 qty.');
  });

  test('fill that stays within the cap is allowed', async () => {
    row({ max_qty: 1500, lot_size: 6400 });
    expect(await positionLimitRejection({ trade: trade(), previousNetQty: 1000, instrument, user: turnoverUser })).toBeNull();
  });

  test('a reducing / closing fill is always allowed, even over the cap', async () => {
    row({ max_qty: 1500, lot_size: 6400 });
    expect(await positionLimitRejection({ trade: trade({ transaction_type: 'SELL' }), previousNetQty: 2000, instrument, user: turnoverUser })).toBeNull();
  });

  test('orders placed by ADMIN or SYSTEM are not checked (same as at placement)', async () => {
    row({ max_qty: 1500, lot_size: 6400 });
    expect(await positionLimitRejection({ trade: trade({ placed_by: 'ADMIN' }), previousNetQty: 1500, instrument, user: turnoverUser })).toBeNull();
    expect(await positionLimitRejection({ trade: trade({ placed_by: 'SYSTEM' }), previousNetQty: 1500, instrument, user: turnoverUser })).toBeNull();
    expect(ScriptQuantity.findOne).not.toHaveBeenCalled();
  });

  test('no limit row: allowed', async () => {
    row(null);
    expect(await positionLimitRejection({ trade: trade({ quantity: 99999 }), previousNetQty: 0, instrument, user: turnoverUser })).toBeNull();
  });

  test('max 0: opening rejected, closing allowed', async () => {
    row({ max_qty: 0 });
    expect(await positionLimitRejection({ trade: trade(), previousNetQty: 0, instrument, user: turnoverUser })).toContain('not allowed for this account');
    expect(await positionLimitRejection({ trade: trade({ transaction_type: 'SELL' }), previousNetQty: 500, instrument, user: turnoverUser })).toBeNull();
  });

  test('lot mode counts lots', async () => {
    row({ max_qty: 2, lot_size: 100 });
    expect(await positionLimitRejection({ trade: trade({ quantity: 100 }), previousNetQty: 100, instrument, user: lotUser })).toBeNull();
    expect(await positionLimitRejection({ trade: trade({ quantity: 100 }), previousNetQty: 200, instrument, user: lotUser })).toContain('Max: 2 lot(s)');
  });

  test('looks the row up by raw name on the instrument segment, falling back to the tradingsymbol', async () => {
    ScriptQuantity.findOne.mockReturnValueOnce(leanChain(null)).mockReturnValueOnce(leanChain({ max_qty: 1000 }));
    const remark = await positionLimitRejection({ trade: trade({ quantity: 600 }), previousNetQty: 500, instrument, user: turnoverUser });
    expect(remark).toContain('Max: 1000 qty');
    expect(ScriptQuantity.findOne.mock.calls[0][0]).toMatchObject({ owner_id: 'u1', exchange_name: 'NFO-FUT', script_name: 'INOXWIND' });
    expect(ScriptQuantity.findOne.mock.calls[1][0]).toMatchObject({ script_name: 'INOXWIND26OCTFUT' });
  });
});
