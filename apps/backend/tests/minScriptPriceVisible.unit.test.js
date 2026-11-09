'use strict';

// Owner, 9 Nov 2026: an NSE future below the client's minimum price stays
// VISIBLE — it's listed on the watchlist (held or not), can be added, and is
// returned by search / browse. Only ORDERS are limited: closing or reducing
// goes through, a fresh position is refused (minScriptPriceOrders test).

let mockHeld = new Set();
let mockWatchlist = [];
let mockInstruments = [];

jest.mock('../src/utils/heldTokens', () => ({ heldTokensFor: async () => mockHeld }));
jest.mock('../src/models/KiteInstrument', () => ({
  find: () => ({ lean: async () => mockInstruments }),
}));
jest.mock('../src/models/Watchlist', () => ({
  find: () => ({ sort: () => ({ lean: async () => mockWatchlist }) }),
  updateMany: async () => ({}),
  updateOne: async () => ({}),
}));
// Client with NFO-FUT allowed and a minimum NSE FUT price of 100.
jest.mock('../src/models/User', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false }], min_nse_fut_price: 100 }) }) }) }));
jest.mock('../src/models/Master', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [] }) }) }) }));

const fs = require('fs');
const path = require('path');
const { getWatchlist } = require('../src/controllers/watchlistController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const src = (f) => fs.readFileSync(path.join(__dirname, '..', 'src', f), 'utf8');

test('watchlist lists NSE futures below the minimum, held or not', async () => {
  mockInstruments = [
    { _id: 'i1', instrument_token: '1001', segment: 'NFO-FUT', settlement_price: 12.78, last_price: 12.8 }, // IDEA, not held
    { _id: 'i2', instrument_token: '1002', segment: 'NFO-FUT', settlement_price: 78.07, last_price: 78 }, // NBCC, held
    { _id: 'i3', instrument_token: '1003', segment: 'NFO-FUT', settlement_price: 1193.4, last_price: 1193 }, // above
  ];
  mockWatchlist = mockInstruments.map((i, n) => ({ _id: `w${n}`, instrument_token: i.instrument_token, kite_instrument_id: i._id, order: n }));
  mockHeld = new Set(['1002']);
  const r = res();
  await getWatchlist({ user: { id: 'u1' } }, r);
  const items = r.json.mock.calls[0][0].data;
  expect(items.map((i) => i.instrument_token)).toEqual(['1001', '1002', '1003']);
});

test('no listing filters on the minimum price remain (watchlist add/list, search, smart search, browse)', () => {
  const wl = src('controllers/watchlistController.js');
  const kite = src('controllers/kiteController.js');
  expect(wl).not.toMatch(/isBelowMinPrice|minPriceForReq|belowMinMessage/);
  expect(kite).not.toMatch(/dropBelowMinPrice|minPriceMongoFilter|minPriceForReq/);
});

test('every order path still enforces close-only below the minimum', () => {
  const trade = src('controllers/tradeController.js');
  // place and modify both call the check
  expect((trade.match(/await _validateMinNseFutPrice\(/g) || []).length).toBe(2);
  // rollover into a below-minimum contract is still refused
  expect(src('services/rolloverService.js')).toMatch(/isBelowMinPrice/);
});
