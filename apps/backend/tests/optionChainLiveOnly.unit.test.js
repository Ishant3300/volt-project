'use strict';

// The option chain lists only live contracts. It used to return every option
// still stored — expired BANKNIFTY May–Sep 2026 included — so a client opened
// JUN/JUL 2026 calls at months-old prices (938184, 26 Oct 2026).

jest.mock('../src/services/kiteService', () => ({ getStoredAccessToken: jest.fn(async () => null) }));
const mockFind = jest.fn(() => ({ sort: () => ({ lean: async () => [] }) }));
jest.mock('../src/models/KiteInstrument', () => ({ find: (...a) => mockFind(...a), aggregate: async () => [{ data: [], count: [] }] }));
// The caller's exchanges_allowed (utils/exchangeAccess.js reads it per request).
let mockRows = [];
jest.mock('../src/models/User', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: mockRows }) }) }) }));
jest.mock('../src/models/Master', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ exchanges_allowed: [] }) }) }) }));
jest.mock('../src/services/instrumentSearchService', () => ({ loadInstrumentCache: async () => {}, groupResults: () => [] }));

const { getOptionChain, browseInstruments } = require('../src/controllers/kiteController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const today = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };

beforeEach(() => { mockFind.mockClear(); mockRows = []; });
const ADMIN = { admin: { id: 'a1' } };
const CLIENT = { user: { id: 'u1' } };

test('no expiry asked → only active, not deleted, not expired', async () => {
  await getOptionChain({ ...ADMIN, params: { tradingSymbol: 'BANKNIFTY' }, query: {} }, res());
  const q = mockFind.mock.calls[0][0];
  expect(q.is_active).toBe(true);
  expect(q.deleted_at).toBeNull();
  expect(q.expiry.$gte.getTime()).toBe(today().getTime());
});

test('a live expiry asked → exactly that expiry', async () => {
  const future = new Date(today().getTime() + 30 * 864e5);
  await getOptionChain({ ...ADMIN, params: { tradingSymbol: 'BANKNIFTY' }, query: { expiry: future.toISOString() } }, res());
  expect(mockFind.mock.calls[0][0].expiry.getTime()).toBe(future.getTime());
});

test('a past expiry asked → matches nothing', async () => {
  await getOptionChain({ ...ADMIN, params: { tradingSymbol: 'BANKNIFTY' }, query: { expiry: '2026-06-30' } }, res());
  const e = mockFind.mock.calls[0][0].expiry;
  expect(e.$gte.getTime()).toBe(today().getTime());
  expect(e.$lt.getTime()).toBe(today().getTime());
});

test('client without NFO-OPT → no chain, clear message, nothing loaded', async () => {
  mockRows = [{ exchange_name: 'NFO-FUT', turnover: true, lot: false }];
  const r = res();
  await getOptionChain({ ...CLIENT, params: { tradingSymbol: 'BANKNIFTY' }, query: {} }, r);
  expect(r.status).toHaveBeenCalledWith(403);
  expect(r.json.mock.calls[0][0].message).toMatch(/not permitted to trade NFO-OPT/);
  expect(mockFind).not.toHaveBeenCalled();
});

test('client with NFO-OPT ticked → chain loads', async () => {
  mockRows = [{ exchange_name: 'NFO-OPT', turnover: false, lot: true }];
  const r = res();
  await getOptionChain({ ...CLIENT, params: { tradingSymbol: 'BANKNIFTY' }, query: {} }, r);
  expect(mockFind).toHaveBeenCalled();
});

test('browse: a tab the client is not allowed lists nothing; an allowed one queries', async () => {
  mockRows = [{ exchange_name: 'NFO-FUT', turnover: true, lot: false }, { exchange_name: 'NFO-OPT', turnover: false, lot: false }];
  const r1 = res();
  await browseInstruments({ ...CLIENT, query: { category: 'NFO-OPT' } }, r1);
  expect(r1.json.mock.calls[0][0].data).toEqual({ groups: [], total: 0, page: 1, hasMore: false });
  const r2 = res();
  await browseInstruments({ ...CLIENT, query: { category: 'NFO-FUT' } }, r2);
  expect(r2.status).toHaveBeenCalledWith(200);
  expect(r2.json.mock.calls[0][0].success).toBe(true);
});
