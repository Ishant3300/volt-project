'use strict';

// GLOBAL/COMEX (Massive) prices must reach the order matcher like Kite/GIFT
// ticks do. Until 23 Oct 2026 they only updated screens/P&L, so no GLOBAL or
// COMEX limit/stop order ever filled (162038 YMZ6 BUY LIMIT 52310.7 sat with
// the price at 52305).

jest.mock('../src/services/priceQueueService', () => ({ publishPriceUpdate: jest.fn() }));
jest.mock('../src/services/metricsEngine', () => ({ onTick: jest.fn() }));
jest.mock('../src/models/KiteInstrument', () => ({}));

const priceQueueService = require('../src/services/priceQueueService');
const feed = require('../src/services/massiveFuturesFeedService');

beforeEach(() => {
  jest.clearAllMocks();
  feed.livePriceService = { latestPrices: new Map(), _broadcastToClients: jest.fn() };
  feed.tickerToToken = new Map([['YMZ6', '9000200202612']]);
  feed.tokenToLastBroadcast = new Map();
});

test('trade tick → published for order matching', () => {
  feed._handleTrade({ ev: 'T', sym: 'YMZ6', p: 52305 });
  expect(priceQueueService.publishPriceUpdate).toHaveBeenCalledWith('9000200202612', 52305);
});

test('quote tick → mid price published for order matching', () => {
  feed._handleQuote({ ev: 'Q', sym: 'YMZ6', bp: 52304, ap: 52306 });
  expect(priceQueueService.publishPriceUpdate).toHaveBeenCalledWith('9000200202612', 52305);
});

test('published even when the client broadcast is throttled', () => {
  feed._handleTrade({ ev: 'T', sym: 'YMZ6', p: 52305 });
  feed._handleTrade({ ev: 'T', sym: 'YMZ6', p: 52300 });
  expect(feed.livePriceService._broadcastToClients).toHaveBeenCalledTimes(1);
  expect(priceQueueService.publishPriceUpdate).toHaveBeenLastCalledWith('9000200202612', 52300);
});

test('unknown ticker / bad price → nothing published', () => {
  feed._handleTrade({ ev: 'T', sym: 'XXX', p: 1 });
  feed._handleTrade({ ev: 'T', sym: 'YMZ6', p: 0 });
  expect(priceQueueService.publishPriceUpdate).not.toHaveBeenCalled();
});
