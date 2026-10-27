'use strict';

// Missed-touch fills in the price queue (27 Oct 2026): CRUDE NOV printed 9501
// inside one second between two feed snapshots (9507 → 9503), so a SL SELL at
// 9502 stayed pending. A "touch" — a low/high the exchange really traded in a
// window — now fills such orders at their own price, but only orders that
// existed before the window began (a price from before the order can never
// fill it), and only when the range crosses the order's CURRENT price.

jest.mock('bullmq', () => ({ Queue: jest.fn(), Worker: jest.fn() }));
jest.mock('../src/models/Trade', () => ({ findById: jest.fn(), find: jest.fn(), create: jest.fn(), exists: jest.fn() }));
jest.mock('../src/models/User', () => ({ findById: jest.fn() }));
jest.mock('../src/models/KiteInstrument', () => ({ findOne: jest.fn() }));
jest.mock('../src/models/Transaction', () => jest.fn().mockImplementation((doc) => ({ doc, save: jest.fn().mockResolvedValue(undefined) })));
jest.mock('../src/services/tradeWriteFenceService', () => ({ beginTradeWrite: jest.fn() }));
jest.mock('../src/services/marginService', () => ({ calculateMargin: jest.fn() }));
jest.mock('../src/services/brokerageService', () => ({ calculateBrokerage: jest.fn() }));
jest.mock('../src/services/walletService', () => ({ getAvailable: jest.fn(), block: jest.fn(), release: jest.fn() }));
jest.mock('../src/services/positionLimitService', () => ({ positionLimitRejection: jest.fn() }));
jest.mock('../src/services/firebaseService', () => ({ sendNotification: jest.fn() }));
jest.mock('../src/services/metricsEngine', () => ({ getCachedMetrics: jest.fn(), onTradeExecuted: jest.fn(), broadcastTradeAlert: jest.fn() }));
jest.mock('../src/services/orderBookService', () => ({
  getMatchingBuyOrders: jest.fn(),
  getMatchingSellOrders: jest.fn(),
  getMatchingStopRiseOrders: jest.fn(),
  getMatchingStopFallOrders: jest.fn(),
  removeMany: jest.fn(),
  getOrderCount: jest.fn().mockResolvedValue(1),
}));
jest.mock('../src/services/redisService', () => ({ isAvailable: jest.fn(), getClient: jest.fn() }));
jest.mock('../src/services/livePriceService', () => ({ broadcastToUser: jest.fn() }));
jest.mock('../src/services/missedTouchService', () => ({ start: jest.fn(), stop: jest.fn() }));

const mongoose = require('mongoose');
const Trade = require('../src/models/Trade');
const User = require('../src/models/User');
const KiteInstrument = require('../src/models/KiteInstrument');
const walletService = require('../src/services/walletService');
const { beginTradeWrite } = require('../src/services/tradeWriteFenceService');
const { calculateMargin } = require('../src/services/marginService');
const { calculateBrokerage } = require('../src/services/brokerageService');
const { positionLimitRejection } = require('../src/services/positionLimitService');
const orderBookService = require('../src/services/orderBookService');
const pq = require('../src/services/priceQueueService');

const { touchVerdict, mergeTouch, _processJob, _flushPendingPricePublishes, _setQueue } = pq._private;

const T = (s) => new Date(`2026-10-27T${s}+05:30`).getTime();

function chain(result) {
  const c = {};
  c.select = jest.fn(() => c);
  c.sort = jest.fn(() => c);
  c.session = jest.fn(() => c);
  c.lean = jest.fn(() => Promise.resolve(result));
  return c;
}

function makeTrade(over = {}) {
  const doc = Object.assign({
    _id: 'sl1',
    status: 'pending',
    deleted_at: null,
    transaction_type: 'SELL',
    quantity: 100,
    user_id: 'u720722',
    master_id: 'm1',
    instrument_token: '146796039',
    tradingsymbol: 'CRUDEOIL26NOVFUT',
    exchange: 'MCX',
    price: 9502,
    order_type: 'SL',
    trigger_direction: null,
    createdAt: new Date(T('20:41:48')),
    updatedAt: new Date(T('20:41:48')),
  }, over);
  doc.save = jest.fn().mockResolvedValue(doc);
  doc.toObject = jest.fn(() => ({ ...doc }));
  return doc;
}

let tradeDoc;
beforeEach(() => {
  jest.clearAllMocks();
  jest.spyOn(mongoose, 'startSession').mockResolvedValue({
    withTransaction: jest.fn(async (fn) => { await fn(); }),
    endSession: jest.fn().mockResolvedValue(undefined),
  });
  beginTradeWrite.mockResolvedValue({ assertActive: jest.fn().mockResolvedValue(undefined), release: jest.fn().mockResolvedValue(undefined) });
  tradeDoc = makeTrade();
  Trade.findById.mockImplementation(() => ({ session: jest.fn().mockResolvedValue(tradeDoc) }));
  // Long 100 @ 9533 — the SL SELL closes it.
  Trade.find.mockReturnValue(chain([{ transaction_type: 'BUY', executed_quantity: 100, executed_price: 9533, executed_at: new Date(T('20:40:35')) }]));
  Trade.create.mockResolvedValue([{}]);
  Trade.exists.mockReturnValue({ session: jest.fn().mockResolvedValue(null) }); // no trade since the window
  KiteInstrument.findOne.mockImplementation(() => chain({ segment: 'MCX-FUT', enabled: true }));
  const gateUser = { bet: true, close_only: false, exchanges_allowed: [{ exchange_name: 'MCX-FUT', turnover: true }], credits: 100000 };
  const userDoc = { equity: 100000, save: jest.fn().mockResolvedValue(undefined) };
  User.findById.mockImplementation(() => ({
    select: () => chain(gateUser),
    session: jest.fn().mockResolvedValue(userDoc),
  }));
  positionLimitRejection.mockResolvedValue(null);
  calculateBrokerage.mockResolvedValue(0);
  calculateMargin.mockResolvedValue(9502);
  walletService.getAvailable.mockResolvedValue({ NSE: 0, MCX: 1e9, GLOBAL: 0 });
  walletService.release.mockResolvedValue({});
  walletService.block.mockResolvedValue({});
  orderBookService.getMatchingBuyOrders.mockResolvedValue([]);
  orderBookService.getMatchingSellOrders.mockResolvedValue([]);
  orderBookService.getMatchingStopRiseOrders.mockResolvedValue([]);
  orderBookService.getMatchingStopFallOrders.mockResolvedValue([]);
  orderBookService.removeMany.mockResolvedValue(undefined);
  orderBookService.getOrderCount.mockResolvedValue(1);
});

afterEach(() => jest.restoreAllMocks());

describe('touchVerdict — who may fill from a touched range', () => {
  const touch = { low: 9501, high: 9510, since: T('21:13:02'), at: T('21:13:03') };

  test('the 27 Oct case: SL SELL 9502 (legacy null direction = FALL) placed 20:41 fills from low 9501', () => {
    expect(touchVerdict(makeTrade(), touch)).toBeNull();
  });
  test('an order placed (or modified) after the window began never fills from it', () => {
    expect(touchVerdict(makeTrade({ updatedAt: new Date(T('21:13:02')) }), touch)).toBe('placed_after');
    expect(touchVerdict(makeTrade({ updatedAt: new Date(T('21:13:05')) }), touch)).toBe('placed_after');
  });
  test('range not crossing the order price', () => {
    expect(touchVerdict(makeTrade({ price: 9500 }), touch)).toBe('price');
  });
  test('LIMIT BUY by the low, LIMIT SELL by the high', () => {
    expect(touchVerdict(makeTrade({ order_type: 'LIMIT', transaction_type: 'BUY', price: 9501 }), touch)).toBeNull();
    expect(touchVerdict(makeTrade({ order_type: 'LIMIT', transaction_type: 'BUY', price: 9500.5 }), touch)).toBe('price');
    expect(touchVerdict(makeTrade({ order_type: 'LIMIT', transaction_type: 'SELL', price: 9510 }), touch)).toBeNull();
    expect(touchVerdict(makeTrade({ order_type: 'LIMIT', transaction_type: 'SELL', price: 9511 }), touch)).toBe('price');
  });
  test('stops follow trigger_direction, not the side', () => {
    expect(touchVerdict(makeTrade({ transaction_type: 'SELL', trigger_direction: 'RISE', price: 9509 }), touch)).toBeNull();
    expect(touchVerdict(makeTrade({ transaction_type: 'BUY', trigger_direction: 'FALL', price: 9502 }), touch)).toBeNull();
    // Legacy (null) SL BUY = RISE: decided by the high (9510).
    expect(touchVerdict(makeTrade({ transaction_type: 'BUY', trigger_direction: null, price: 9505 }), touch)).toBeNull();
    expect(touchVerdict(makeTrade({ transaction_type: 'BUY', trigger_direction: null, price: 9512 }), touch)).toBe('price');
  });
  test('a side the touch did not cover (high only) cannot fill a FALL stop', () => {
    expect(touchVerdict(makeTrade(), { low: null, high: 9600, since: touch.since })).toBe('price');
  });
});

test('mergeTouch keeps the widest range and the earlier since', () => {
  const m = mergeTouch({ low: 9503, high: null, since: 2000, at: 3000, source: 'day_range' }, { low: 9501, high: 9520, since: 1000, at: 4000, source: 'day_range' });
  expect(m).toEqual({ low: 9501, high: 9520, since: 1000, at: 4000, source: 'day_range' });
  expect(mergeTouch(null, { low: 1 })).toEqual({ low: 1 });
});

describe('processTouch', () => {
  let touch;
  beforeEach(() => { touch = { low: 9501, high: null, since: Date.now() - 31_000, at: Date.now() - 30_000, source: 'kite_window' }; });

  test('fills the SL at its own price, records when the price traded, cleans it from the stop-fall book', async () => {
    orderBookService.getMatchingStopFallOrders.mockResolvedValue(['sl1']);
    const out = await pq.processTouch('146796039', touch, 9530);
    expect(orderBookService.getMatchingStopFallOrders).toHaveBeenCalledWith('146796039', 9501);
    expect(orderBookService.getMatchingBuyOrders).toHaveBeenCalledWith('146796039', 9501);
    expect(orderBookService.getMatchingSellOrders).not.toHaveBeenCalled(); // no high in this touch
    expect(orderBookService.getMatchingStopRiseOrders).not.toHaveBeenCalled();
    expect(out).toEqual([expect.objectContaining({ id: 'sl1', kind: 'completed' })]);
    expect(tradeDoc.status).toBe('completed');
    expect(tradeDoc.executed_price).toBe(9502);
    expect(tradeDoc.price_touched_at).toEqual(new Date(touch.at));
    expect(tradeDoc.pnl).toBe((9502 - 9533) * 100);
    expect(orderBookService.removeMany).toHaveBeenCalledWith('146796039', null, ['sl1'], 'SL', 'FALL');
  });

  test('an order placed after the window began stays pending and stays in the book', async () => {
    const placed = Date.now() - 10_000;
    tradeDoc = makeTrade({ updatedAt: new Date(placed) });
    orderBookService.getMatchingStopFallOrders.mockResolvedValue(['sl1']);
    const out = await pq.processTouch('146796039', touch, 9530);
    expect(out).toEqual([expect.objectContaining({ id: 'sl1', kind: 'not_eligible', reason: 'placed_after', placedAt: placed })]);
    expect(tradeDoc.status).toBe('pending');
    expect(tradeDoc.save).not.toHaveBeenCalled();
    expect(orderBookService.removeMany).not.toHaveBeenCalled();
  });

  test('the client traded this script after the price touched: no late fill on a changed position', async () => {
    Trade.exists.mockReturnValue({ session: jest.fn().mockResolvedValue({ _id: 'manualClose' }) });
    orderBookService.getMatchingStopFallOrders.mockResolvedValue(['sl1']);
    const out = await pq.processTouch('146796039', touch, 9530);
    expect(out).toEqual([expect.objectContaining({ id: 'sl1', kind: 'not_eligible', reason: 'position_changed' })]);
    expect(Trade.exists).toHaveBeenCalledWith(expect.objectContaining({ user_id: 'u720722', instrument_token: '146796039', status: 'completed', executed_at: { $gte: new Date(touch.since) } }));
    expect(tradeDoc.status).toBe('pending');
    expect(orderBookService.removeMany).not.toHaveBeenCalled();
  });

  test("a window over 3 minutes old fills nothing — except for the client's own cancel check", async () => {
    orderBookService.getMatchingStopFallOrders.mockResolvedValue(['sl1']);
    const old = { ...touch, since: Date.now() - 241_000, at: Date.now() - 240_000 };
    expect(await pq.processTouch('146796039', old, 9530)).toEqual([expect.objectContaining({ kind: 'not_eligible', reason: 'too_old' })]);
    expect(await pq.processTouch('146796039', { ...old, source: 'cancel_check' }, 9530)).toEqual([expect.objectContaining({ kind: 'completed' })]);
  });

  test('onlyIds limits it to the given orders', async () => {
    orderBookService.getMatchingStopFallOrders.mockResolvedValue(['sl1', 'other']);
    const out = await pq.processTouch('146796039', touch, 9530, { onlyIds: new Set(['other']) });
    expect(out.map((o) => o.id)).toEqual(['other']);
  });
});

describe('_processJob with a day-range touch', () => {
  test('no live-price match, but the touch fills the stop', async () => {
    orderBookService.getMatchingStopFallOrders.mockImplementation(async (_t, price) => (price <= 9502 ? ['sl1'] : []));
    await _processJob({ data: { instrument_token: '146796039', live_price: 9503, timestamp: Date.now(), touch: { low: 9501, high: null, since: Date.now() - 2000, at: Date.now(), source: 'day_range' } } });
    expect(tradeDoc.status).toBe('completed');
    expect(tradeDoc.executed_price).toBe(9502);
  });

  test('a tick without a touch behaves exactly as before (no match → nothing)', async () => {
    await _processJob({ data: { instrument_token: '146796039', live_price: 9503, timestamp: Date.now() } });
    expect(Trade.findById).not.toHaveBeenCalled();
  });
});

test('publishPriceUpdate carries merged touches into the coalesced job', async () => {
  const add = jest.fn().mockResolvedValue(undefined);
  _setQueue({ add });
  await pq.publishPriceUpdate('146796039', 9505, { low: 9503, high: null, since: 2000, at: 3000, source: 'day_range' });
  await pq.publishPriceUpdate('146796039', 9504, { low: 9501, high: null, since: 1000, at: 3500, source: 'day_range' });
  await pq.publishPriceUpdate('256265', 25000);
  await _flushPendingPricePublishes();
  const jobs = Object.fromEntries(add.mock.calls.map(([, data]) => [data.instrument_token, data]));
  expect(jobs['146796039']).toMatchObject({ live_price: 9504, touch: { low: 9501, since: 1000, at: 3500 } });
  expect(jobs['256265'].touch).toBeUndefined();
  _setQueue(null);
});
