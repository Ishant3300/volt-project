'use strict';

// NSE F&O-banned scripts can be added to a client's watchlist (27 Oct 2026) —
// hidden before, so a client holding SAIL NOV during its ban couldn't even
// watch it. A contract closed for trading (expiry close, admin disable) is
// still refused. Trading a banned script stays closing-only elsewhere.

let mockInstrument = null;
const mockCreate = jest.fn(async (doc) => ({ _id: 'w1', ...doc }));
jest.mock('../src/models/KiteInstrument', () => ({ findOne: () => ({ lean: async () => mockInstrument }) }));
jest.mock('../src/models/Watchlist', () => ({
  findOne: (q) => (q.instrument_token ? Promise.resolve(null) : { sort: async () => null }),
  create: (...a) => mockCreate(...a),
}));
// The client is allowed NFO-FUT, no minimum price.
jest.mock('../src/models/User', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [{ exchange_name: 'NFO-FUT', turnover: true, lot: false }], min_nse_fut_price: 0 }) }) }) }));
jest.mock('../src/models/Master', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [] }) }) }) }));

const { addToWatchlist } = require('../src/controllers/watchlistController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const add = () => ({ user: { id: 'u1' }, body: { instrument_token: '123' } });

beforeEach(() => mockCreate.mockClear());

test('a banned script can be added', async () => {
  mockInstrument = { _id: 'i1', tradingsymbol: 'SAIL26NOVFUT', segment: 'NFO-FUT', enabled: true, nse_banned: true };
  const r = res();
  await addToWatchlist(add(), r);
  expect(r.status).toHaveBeenCalledWith(201);
  expect(mockCreate).toHaveBeenCalled();
});

test('a contract closed for trading is still refused', async () => {
  mockInstrument = { _id: 'i2', tradingsymbol: 'GOLD26OCTFUT', segment: 'NFO-FUT', enabled: false, ban_reason: 'Contract closed ahead of expiry' };
  const r = res();
  await addToWatchlist(add(), r);
  expect(r.status).toHaveBeenCalledWith(403);
  expect(mockCreate).not.toHaveBeenCalled();
});
