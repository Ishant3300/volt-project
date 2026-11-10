'use strict';

// Startup price (utils/startupPrice.js, 10 Nov 2026): a stored last_price far
// from the official close (the bad 07:30 import on the NSE holiday) is never
// used to start a position or the watchlist.
const { startupPrice } = require('../src/utils/startupPrice');

test('weekday: the 10 Nov wrong prices are replaced by the official close', () => {
  expect(startupPrice({ last_price: 0.2, ohlc_close: 1915.3, settlement_price: 1915.3 }, { weekend: false })).toEqual({ price: 1915.3, replaced: true });
  expect(startupPrice({ last_price: 5708.25, ohlc_close: 1042.25, settlement_price: 1042.25 }, { weekend: false })).toEqual({ price: 1042.25, replaced: true });
  expect(startupPrice({ last_price: 6667.9, settlement_price: 334.5 }, { weekend: false })).toEqual({ price: 334.5, replaced: true });
});

test('weekday: a normal stored price is used as before; no stored price = nothing seeded', () => {
  expect(startupPrice({ last_price: 1585.7, ohlc_close: 1585.7 }, { weekend: false })).toEqual({ price: 1585.7, replaced: false });
  expect(startupPrice({ last_price: 1700, ohlc_close: 1585.7 }, { weekend: false })).toEqual({ price: 1700, replaced: false }); // within 25%
  expect(startupPrice({ last_price: 0, ohlc_close: 897 }, { weekend: false })).toEqual({ price: 0, replaced: false });
  expect(startupPrice({ last_price: 412 }, { weekend: false })).toEqual({ price: 412, replaced: false }); // no official close stored
});

test('weekend: settlement price as before', () => {
  expect(startupPrice({ last_price: 0.2, ohlc_close: 1915, settlement_price: 1915.3 }, { weekend: true, settlementIsCurrent: true }).price).toBe(1915.3);
  expect(startupPrice({ last_price: 10, ohlc_close: 1915, settlement_price: 1900 }, { weekend: true, settlementIsCurrent: false }).price).toBe(1915);
});
