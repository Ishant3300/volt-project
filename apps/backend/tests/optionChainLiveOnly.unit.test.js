'use strict';

// The option chain lists only live contracts. It used to return every option
// still stored — expired BANKNIFTY May–Sep 2026 included — so a client opened
// JUN/JUL 2026 calls at months-old prices (938184, 26 Oct 2026).

jest.mock('../src/services/kiteService', () => ({ getStoredAccessToken: jest.fn(async () => null) }));
const mockFind = jest.fn(() => ({ sort: () => ({ lean: async () => [] }) }));
jest.mock('../src/models/KiteInstrument', () => ({ find: (...a) => mockFind(...a) }));

const { getOptionChain } = require('../src/controllers/kiteController');

const res = () => { const r = {}; r.status = jest.fn(() => r); r.json = jest.fn(() => r); return r; };
const today = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };

beforeEach(() => mockFind.mockClear());

test('no expiry asked → only active, not deleted, not expired', async () => {
  await getOptionChain({ params: { tradingSymbol: 'BANKNIFTY' }, query: {} }, res());
  const q = mockFind.mock.calls[0][0];
  expect(q.is_active).toBe(true);
  expect(q.deleted_at).toBeNull();
  expect(q.expiry.$gte.getTime()).toBe(today().getTime());
});

test('a live expiry asked → exactly that expiry', async () => {
  const future = new Date(today().getTime() + 30 * 864e5);
  await getOptionChain({ params: { tradingSymbol: 'BANKNIFTY' }, query: { expiry: future.toISOString() } }, res());
  expect(mockFind.mock.calls[0][0].expiry.getTime()).toBe(future.getTime());
});

test('a past expiry asked → matches nothing', async () => {
  await getOptionChain({ params: { tradingSymbol: 'BANKNIFTY' }, query: { expiry: '2026-06-30' } }, res());
  const e = mockFind.mock.calls[0][0].expiry;
  expect(e.$gte.getTime()).toBe(today().getTime());
  expect(e.$lt.getTime()).toBe(today().getTime());
});
