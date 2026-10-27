'use strict';

// services/missedTouchService.js — finds prices the exchange traded between
// two live-feed snapshots (27 Oct 2026: CRUDE NOV 9501 inside 21:13:03, feed
// 9507 → 9503) from (A) the day low/high on each tick and (B/C) Kite's
// to-the-second candle windows, and asks the price queue to fill the orders.

jest.mock('bullmq', () => ({ Queue: jest.fn(), Worker: jest.fn() }));
const mockProcessTouch = jest.fn();
jest.mock('../src/services/priceQueueService', () => ({
  processTouch: (...a) => mockProcessTouch(...a),
  _private: { touchVerdict: jest.requireActual('../src/services/priceQueueService')._private.touchVerdict },
}));
const mockHistorical = jest.fn();
jest.mock('../src/services/kiteService', () => ({ getHistoricalData: (...a) => mockHistorical(...a) }));
const mockLatest = new Map();
jest.mock('../src/services/livePriceService', () => ({ latestPrices: mockLatest }));
const mockRedis = { scan: jest.fn(), pipeline: jest.fn() };
jest.mock('../src/services/redisService', () => ({ isAvailable: () => true, getClient: () => mockRedis }));

const svc = require('../src/services/missedTouchService');
const { _private: P } = svc;

const T = (s) => new Date(`2026-10-27T${s}+05:30`).getTime();
/** Run fn with the clock shifted to IST time s (still moving — the request limiter needs time to pass). */
async function atClock(s, fn) {
  const realNow = Date.now.bind(Date);
  const shift = T(s) - realNow();
  const spy = jest.spyOn(Date, 'now').mockImplementation(() => realNow() + shift);
  try { return await fn(); } finally { spy.mockRestore(); }
}
const candle = (s, low, high, volume) => ({ date: `2026-10-27T${s}+0530`, open: low, high, low, close: low, volume });

beforeEach(() => {
  jest.clearAllMocks();
  P._reset();
  mockLatest.clear();
  mockProcessTouch.mockResolvedValue([]);
});

describe('A: day low/high on each tick', () => {
  beforeEach(() => P._setTracked(new Map([['146796039', { near: true }]])));

  test('a new day low below the live price since the previous tick is a touch from that tick on', () => {
    expect(svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9507, low: 9505, high: 9800 })).toBeNull(); // first tick
    const prevAt = P._day.get('146796039').at;
    const touch = svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9503, low: 9501, high: 9800 });
    expect(touch).toMatchObject({ low: 9501, high: null, source: 'day_range' });
    expect(touch.since).toBe(prevAt - P.CONST.CLOCK_MARGIN_MS);
  });

  test('the window starts at the previous snapshot\'s EXCHANGE time when that is earlier than when we got it (lagging feed)', () => {
    const exchSec = Math.floor(Date.now() / 1000) - 3; // previous snapshot taken 3 s before we received it
    svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9507, low: 9505, high: 9800, exchange_timestamp: exchSec });
    const touch = svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9503, low: 9501, high: 9800, exchange_timestamp: exchSec + 3 });
    expect(touch.since).toBe(exchSec * 1000 - P.CONST.CLOCK_MARGIN_MS);
  });

  test('a new low AT the live price is already seen by the normal tick match — no touch', () => {
    svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9507, low: 9505, high: 9800 });
    expect(svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9503, low: 9503, high: 9800 })).toBeNull();
  });

  test('a new day high above the live price is a touch on the high side', () => {
    svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9790, low: 9505, high: 9800 });
    expect(svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9795, low: 9505, high: 9803 })).toMatchObject({ low: null, high: 9803 });
  });

  test('ticks more than 30 s apart, a >5% range, or an untracked script: no touch', () => {
    svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9507, low: 9505, high: 9800 });
    P._day.get('146796039').at -= 31_000;
    expect(svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9503, low: 9501, high: 9800 })).toBeNull();
    expect(svc.dayRangeTouch({ instrument_token: 146796039, last_price: 9503, low: 8000, high: 9800 })).toBeNull();
    expect(svc.dayRangeTouch({ instrument_token: 999, last_price: 10, low: 5, high: 20 })).toBeNull();
  });
});

describe('B/C: a script window since its cursor', () => {
  test('reads the unsettled window, passes each traded candle on as a touch, keeps re-reading the last 90 s', async () => {
    mockHistorical.mockResolvedValue([candle('21:12:00', 9506, 9520, 87), candle('21:13:00', 9501, 9510, 134), candle('21:14:00', 9507, 9507, 0)]);
    await P._checkToken('146796039', 0);
    const [token, interval, from, to] = mockHistorical.mock.calls[0];
    expect([token, interval]).toEqual(['146796039', 'minute']);
    const fromMs = Date.parse(from.replace(' ', 'T') + '+05:30');
    const toMs = Date.parse(to.replace(' ', 'T') + '+05:30');
    expect(toMs - fromMs).toBe(P.CONST.SETTLE_MS);
    // Volume 0 = nothing traded (Kite repeats the last price): skipped.
    expect(mockProcessTouch).toHaveBeenCalledTimes(2);
    expect(mockProcessTouch.mock.calls[1][1]).toMatchObject({ low: 9501, high: 9510, at: T('21:13:00'), since: T('21:13:00') - 1000, source: 'kite_window' });
    expect(P._state.get('146796039').cursor).toBe(toMs - P.CONST.SETTLE_MS);
  });

  test('a Kite error keeps the cursor, so the same window is read again', async () => {
    P._state.set('146796039', { cursor: 1000 * Math.floor(Date.now() / 1000) - 120_000, lastCheckAt: 0 });
    const before = P._state.get('146796039').cursor;
    mockHistorical.mockRejectedValue(Object.assign(new Error('boom'), { response: { status: 500 } }));
    await P._checkToken('146796039', 0);
    expect(P._state.get('146796039').cursor).toBe(before);
    expect(mockProcessTouch).not.toHaveBeenCalled();
  });

  test('an order placed inside a candle gets its own window starting after it', async () => {
    const placedAt = T('21:13:20') + 400;
    mockHistorical
      .mockResolvedValueOnce([candle('21:13:00', 9501, 9510, 134)])
      .mockResolvedValueOnce([candle('21:13:22', 9502, 9504, 12)]);
    mockProcessTouch
      .mockResolvedValueOnce([{ id: 'young', kind: 'not_eligible', reason: 'placed_after', placedAt }])
      .mockResolvedValueOnce([{ id: 'young', kind: 'completed' }]);
    // Shift the clock to 21:14:30 (not frozen — the request limiter needs time to pass).
    const realNow = Date.now.bind(Date);
    const shift = T('21:14:30') - realNow();
    jest.spyOn(Date, 'now').mockImplementation(() => realNow() + shift);
    try {
      await P._checkToken('146796039', 0);
    } finally {
      Date.now.mockRestore();
    }
    expect(mockHistorical).toHaveBeenCalledTimes(2);
    expect(mockHistorical.mock.calls[1][2]).toBe('2026-10-27 21:13:22'); // ceil(placed + 1 s)
    expect(mockHistorical.mock.calls[1][3]).toBe('2026-10-27 21:14:00'); // that candle's end
    expect(mockProcessTouch.mock.calls[1][3]).toEqual({ onlyIds: new Set(['young']) });
    expect(mockProcessTouch.mock.calls[1][1].since).toBe(T('21:13:22') - 1000);
  });
});

describe('which script is checked next', () => {
  test('near ones every 2 s first, the rest every 60 s; a script with no tick since its window is left alone', () => {
    const now = Date.now();
    P._setTracked(new Map([['1', { near: false }], ['2', { near: true }], ['3', { near: false }]]));
    P._state.set('1', { cursor: now - 90_000, lastCheckAt: now - 61_000 });
    P._state.set('2', { cursor: now - 90_000, lastCheckAt: now - 2_500 });
    P._state.set('3', { cursor: now - 90_000, lastCheckAt: now - 120_000 });
    P._day.set('1', { at: now - 1000 });
    P._day.set('2', { at: now - 1000 });
    P._day.set('3', { at: now - 200_000 }); // no tick since its cursor
    expect(P._nextDue(now)).toMatchObject({ token: '2' });
    P._state.get('2').lastCheckAt = now;
    expect(P._nextDue(now)).toMatchObject({ token: '1' });
    P._state.get('1').lastCheckAt = now;
    expect(P._nextDue(now)).toBeNull();
  });

  test('a sweep twice overdue is not starved by near scripts', () => {
    const now = Date.now();
    P._setTracked(new Map([['near', { near: true }], ['far', { near: false }]]));
    P._state.set('near', { cursor: now - 90_000, lastCheckAt: now - 2_500 });
    P._state.set('far', { cursor: now - 90_000, lastCheckAt: now - 125_000 });
    P._day.set('near', { at: now - 500 });
    P._day.set('far', { at: now - 500 });
    expect(P._nextDue(now)).toMatchObject({ token: 'far' });
  });
});

test('_refresh tracks scripts with pending orders (Kite tokens only) and marks the near ones', async () => {
  mockRedis.scan.mockResolvedValueOnce(['0', ['ob:146796039:stopfall', 'ob:111:buy', 'ob:9000000202612:buy']]);
  const zcount = jest.fn().mockReturnThis();
  mockRedis.pipeline.mockReturnValue({ zcount, exec: jest.fn().mockResolvedValue([[null, 1], [null, 0]]) });
  mockLatest.set('146796039', 9503);
  mockLatest.set('111', 100);
  await P._refresh();
  const tracked = P._tracked();
  expect([...tracked.keys()].sort()).toEqual(['111', '146796039']);
  expect(tracked.get('146796039').near).toBe(true);
  expect(tracked.get('111').near).toBe(false);
  expect(zcount).toHaveBeenCalledWith('ob:146796039:stopfall', 9503 * (1 - P.CONST.NEAR_PCT), 9503 * (1 + P.CONST.NEAR_PCT));
});

describe("a client's own cancel/modify", () => {
  const pending = (over = {}) => ({
    _id: 'sl1', status: 'pending', order_type: 'SL', transaction_type: 'SELL', trigger_direction: null, price: 9502,
    instrument_token: '146796039', updatedAt: new Date(T('21:12:40') + 300), ...over,
  });

  test('the price traded through since the order was placed → it fills', async () => {
    mockHistorical.mockResolvedValue([candle('21:12:42', 9501, 9510, 134)]);
    mockProcessTouch.mockResolvedValue([{ id: 'sl1', kind: 'completed' }]);
    const r = await atClock('21:14:00', () => svc.checkBeforeChange(pending()));
    expect(r).toEqual({ checked: true, executed: true });
    expect(mockHistorical.mock.calls[0][2]).toBe('2026-10-27 21:12:42'); // window starts after the order (+1 s)
    expect(mockProcessTouch.mock.calls[0][3]).toEqual({ onlyIds: new Set(['sl1']) });
    expect(mockProcessTouch.mock.calls[0][1].source).toBe('cancel_check');
  });

  test('not crossed (or nothing traded) → the change goes ahead, no order-book call', async () => {
    mockHistorical.mockResolvedValue([candle('21:12:42', 9505, 9510, 50), candle('21:13:42', 9400, 9400, 0)]);
    expect(await svc.checkBeforeChange(pending())).toEqual({ checked: true, executed: false });
    expect(mockProcessTouch).not.toHaveBeenCalled();
  });

  test('Kite failing never blocks the change', async () => {
    mockHistorical.mockRejectedValue(new Error('down'));
    expect(await svc.checkBeforeChange(pending())).toEqual({ checked: false, executed: false });
  });

  test('MARKET, non-pending and non-Kite (COMEX/GIFT) orders are not checked', async () => {
    expect(await svc.checkBeforeChange(pending({ order_type: 'MARKET' }))).toEqual({ checked: false, executed: false });
    expect(await svc.checkBeforeChange(pending({ status: 'completed' }))).toEqual({ checked: false, executed: false });
    expect(await svc.checkBeforeChange(pending({ instrument_token: '9000000202612' }))).toEqual({ checked: false, executed: false });
    expect(mockHistorical).not.toHaveBeenCalled();
  });
});

test('Kite slots: at most one per second, a waiting cancel goes before a waiting sweep', async () => {
  const order = [];
  const t0 = Date.now();
  await P._slot(0); // takes the slot now
  const sweep = P._slot(0).then(() => order.push('sweep'));
  const cancel = P._slot(3).then(() => order.push('cancel'));
  await Promise.all([sweep, cancel]);
  expect(order).toEqual(['cancel', 'sweep']);
  expect(Date.now() - t0).toBeGreaterThanOrEqual(2 * P.CONST.MIN_GAP_MS - 50);
});

test('a slot that cannot come in time gives up (a cancel never waits long)', async () => {
  await P._slot(0);
  expect(await P._slot(3, 100)).toBe(false);
});

test('Kite candle dates parse with their +0530 offset', () => {
  expect(P.candleMs({ date: '2026-10-27T21:13:03+0530' })).toBe(T('21:13:03'));
  expect(P.istStr(T('21:13:03'))).toBe('2026-10-27 21:13:03');
});
