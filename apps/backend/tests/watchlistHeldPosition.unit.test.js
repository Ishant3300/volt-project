'use strict';

// A script the client holds an open position in stays on the watchlist until
// the position is closed (31 Oct 2026): removal is refused, and it isn't
// auto-removed for an expired contract / disallowed exchange or hidden below
// the minimum price.

let mockHeld = new Set();
const mockUpdate = jest.fn(async () => ({}));
const mockFindOneAndUpdate = jest.fn(async () => ({ _id: 'w1' }));
let mockWatchlist = [];
let mockInstruments = [];

jest.mock('../src/utils/heldTokens', () => ({ heldTokensFor: async () => mockHeld }));
jest.mock('../src/models/KiteInstrument', () => ({
  find: () => ({ lean: async () => mockInstruments }),
  findOne: () => ({ select: () => ({ lean: async () => ({ tradingsymbol: 'SILVER26DECFUT' }) }) }),
}));
jest.mock('../src/models/Watchlist', () => ({
  find: () => ({ sort: () => ({ lean: async () => mockWatchlist }) }),
  findOne: () => ({ select: () => ({ lean: async () => ({ instrument_token: '2002' }) }) }),
  findOneAndUpdate: (...a) => mockFindOneAndUpdate(...a),
  updateMany: (...a) => mockUpdate(...a),
  updateOne: async () => ({}),
}));
// Allowed NFO-FUT only (MCX is not), minimum NSE FUT price 500.
jest.mock('../src/models/User', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false }], min_nse_fut_price: 500 }) }) }) }));
jest.mock('../src/models/Master', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [] }) }) }) }));

const { getWatchlist, removeFromWatchlist } = require('../src/controllers/watchlistController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };

beforeEach(() => { mockUpdate.mockClear(); mockFindOneAndUpdate.mockClear(); });

test('removing a held script is refused', async () => {
  mockHeld = new Set(['2002']);
  const r = res();
  await removeFromWatchlist({ user: { id: 'u1' }, params: { id: 'w1' } }, r);
  expect(r.status).toHaveBeenCalledWith(409);
  expect(r.json.mock.calls[0][0].message).toMatch(/SILVER26DECFUT/);
  expect(mockFindOneAndUpdate).not.toHaveBeenCalled();
});

test('removing a script with no position still works', async () => {
  mockHeld = new Set();
  const r = res();
  await removeFromWatchlist({ user: { id: 'u1' }, params: { id: 'w1' } }, r);
  expect(r.status).toHaveBeenCalledWith(200);
  expect(mockFindOneAndUpdate).toHaveBeenCalled();
});

test('held scripts are kept (expired / disallowed / below min) and flagged', async () => {
  const yesterday = new Date(Date.now() - 2 * 86400000).toISOString();
  mockInstruments = [
    { _id: 'i1', instrument_token: '1001', segment: 'NFO-FUT', expiry: yesterday, last_price: 1000 },
    { _id: 'i2', instrument_token: '2002', segment: 'MCX-FUT', last_price: 168000 },
    { _id: 'i3', instrument_token: '1003', segment: 'NFO-FUT', last_price: 100, close_price: 100 },
    { _id: 'i4', instrument_token: '2004', segment: 'MCX-FUT', last_price: 5000 },
  ];
  mockWatchlist = mockInstruments.map((i, n) => ({ _id: `w${n}`, instrument_token: i.instrument_token, kite_instrument_id: i._id, order: n }));
  mockHeld = new Set(['1001', '2002', '1003']);
  const r = res();
  await getWatchlist({ user: { id: 'u1' } }, r);
  const items = r.json.mock.calls[0][0].data;
  expect(items.map((i) => i.instrument_token)).toEqual(['1001', '2002', '1003']);
  expect(items.every((i) => i.has_position)).toBe(true);
  // Only the unheld MCX script (disallowed exchange) is soft-deleted.
  const deletedIds = mockUpdate.mock.calls.flatMap((c) => c[0]._id.$in);
  expect(deletedIds).toEqual(['w3']);
});
