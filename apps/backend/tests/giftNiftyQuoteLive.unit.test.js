'use strict';

// GIFT NIFTY orders are refused while NSE IX has no fresh quote (holiday,
// between sessions, feed down). Live case, 2 Oct 2026: NSE IX's last quote was
// 2:43 AM IST, the app showed buy = sell = that frozen price, and an order
// would have filled at it.

jest.mock('../src/services/metricsEngine', () => ({ onTick: jest.fn() }));
jest.mock('../src/services/priceQueueService', () => ({ publishPriceUpdate: jest.fn() }));

const feed = require('../src/services/giftNiftyFeedService');
const { isLoggableTradeRefusal, GIFT_NOT_LIVE_MESSAGE } = require('../src/utils/rejectionLog');
const { contractToken } = require('../src/services/giftNiftyContracts');

const OCT = contractToken(new Date('2026-10-27T00:00:00.000Z'));
const nseixTs = (date) => {
  const p = new Date(date.getTime() + 5.5 * 3600e3);
  const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][p.getUTCMonth()];
  const z = (n) => String(n).padStart(2, '0');
  return `${z(p.getUTCDate())}-${mon}-${p.getUTCFullYear()} ${z(p.getUTCHours())}:${z(p.getUTCMinutes())}:${z(p.getUTCSeconds())}`;
};
const row = (ts, last = 22491) => ({
  INSTRUMENTTYPE: 'FUTIDX', SYMBOL: 'NIFTY', EXPIRYDATE: '27-Oct-2026',
  LASTPRICE: last, BIDPRICE: last - 0.5, ASKPRICE: last + 0.5, TIMESTMP: nseixTs(ts),
});

beforeEach(() => {
  feed._freshQuoteAt.clear();
  feed.livePriceService = { latestPrices: new Map(), _broadcastToClients: jest.fn() };
});

test('no quote ever received → not live (orders refused)', () => {
  expect(feed.isQuoteLive(OCT)).toBe(false);
});

test('a fresh NSE IX quote makes the contract live', () => {
  const now = Date.now();
  feed._tickMonthlyContracts([row(new Date(now - 3000))], now);
  expect(feed.isQuoteLive(OCT, now)).toBe(true);
  expect(feed.isQuoteLive(Number(OCT), now)).toBe(true); // token type doesn't matter
});

test('a stale NSE IX quote (holiday: last quote hours old) does not', () => {
  const now = Date.now();
  feed._tickMonthlyContracts([row(new Date(now - 7 * 3600e3))], now);
  expect(feed.isQuoteLive(OCT, now)).toBe(false);
});

test('live becomes not-live 5 minutes after the last fresh quote', () => {
  const t0 = Date.now();
  feed._tickMonthlyContracts([row(new Date(t0))], t0);
  expect(feed.isQuoteLive(OCT, t0 + 4.9 * 60e3)).toBe(true);
  expect(feed.isQuoteLive(OCT, t0 + 5.1 * 60e3)).toBe(false);
});

describe('after a restart with only a stale quote (holiday)', () => {
  const metricsEngine = require('../src/services/metricsEngine');
  const priceQueueService = require('../src/services/priceQueueService');
  beforeEach(() => jest.clearAllMocks());

  test('shows NSE IX last quote once, for display and position value only', () => {
    const now = Date.now();
    feed._tickMonthlyContracts([row(new Date(now - 7 * 3600e3), 22385)], now);
    expect(feed.livePriceService.latestPrices.get(OCT)).toBe(22385);
    expect(metricsEngine.onTick).toHaveBeenCalledWith(OCT, 22385, 22384.5, 22385.5);
    expect(feed.livePriceService._broadcastToClients).toHaveBeenCalledTimes(1);
    // never treated as live
    expect(priceQueueService.publishPriceUpdate).not.toHaveBeenCalled();
    expect(feed.isQuoteLive(OCT, now)).toBe(false);
  });

  test('is not re-sent on every poll once a price is held', () => {
    const now = Date.now();
    feed._tickMonthlyContracts([row(new Date(now - 7 * 3600e3))], now);
    feed._tickMonthlyContracts([row(new Date(now - 7 * 3600e3))], now + 2000);
    expect(metricsEngine.onTick).toHaveBeenCalledTimes(1);
    expect(feed.livePriceService._broadcastToClients).toHaveBeenCalledTimes(1);
  });
});

test('the refusal is saved to the Rejection Log', () => {
  expect(isLoggableTradeRefusal(GIFT_NOT_LIVE_MESSAGE)).toBe(true);
});
