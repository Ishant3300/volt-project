'use strict';

// Min NSE FUT script price per client (utils/minScriptPrice.js, 26 Oct 2026):
// an NSE future whose last official close is below the client's minimum can't
// be opened or added to; closing is always allowed. NFO-FUT only, 0 = off.
// Since 9 Nov 2026 the listings show such scripts (minScriptPriceVisible test).

const mockFind = jest.fn();
jest.mock('../src/models/KiteInstrument', () => ({ find: (...a) => mockFind(...a) }));
jest.mock('../src/models/User', () => ({ findById: () => ({ select: () => ({ lean: async () => ({ min_nse_fut_price: 100 }) }) }) }));

const m = require('../src/utils/minScriptPrice');

const fut = (settlement_price, extra = {}) => ({ segment: 'NFO-FUT', settlement_price, ...extra });

describe('isBelowMinPrice', () => {
  test('NSE future below the minimum → below', () => expect(m.isBelowMinPrice(100, fut(69.08))).toBe(true));
  test('at or above → allowed', () => {
    expect(m.isBelowMinPrice(100, fut(100))).toBe(false);
    expect(m.isBelowMinPrice(100, fut(164.02))).toBe(false);
  });
  test('minimum 0 (off) → everything allowed', () => expect(m.isBelowMinPrice(0, fut(11.36))).toBe(false));
  test('other segments are never affected', () => {
    expect(m.isBelowMinPrice(100, { segment: 'NFO-OPT', settlement_price: 5 })).toBe(false);
    expect(m.isBelowMinPrice(100, { segment: 'MCX-FUT', settlement_price: 5 })).toBe(false);
  });
  test('no official close yet → allowed (never blocks on unknown)', () => {
    expect(m.isBelowMinPrice(100, fut(0))).toBe(false);
    expect(m.isBelowMinPrice(100, { segment: 'NFO-FUT' })).toBe(false);
  });
  test('the stored last_price is ignored (not kept current for NSE futures)', () =>
    expect(m.isBelowMinPrice(100, fut(15.82, { last_price: 5217.5 }))).toBe(true));
});

describe('parseMinNseFutPrice', () => {
  test('empty → 0 (off)', () => expect(m.parseMinNseFutPrice('')).toEqual({ value: 0 }));
  test('number → rounded to paise', () => expect(m.parseMinNseFutPrice('99.999')).toEqual({ value: 100 }));
  test('negative / text → error', () => {
    expect(m.parseMinNseFutPrice(-1).error).toBeTruthy();
    expect(m.parseMinNseFutPrice('abc').error).toBeTruthy();
  });
});

describe('minPriceForReq', () => {
  test('client → their value; admin and master → 0 (see everything)', async () => {
    expect(await m.minPriceForReq({ user: { id: 'u1' } })).toBe(100);
    expect(await m.minPriceForReq({ admin: { id: 'a1' } })).toBe(0);
    expect(await m.minPriceForReq({ master: { id: 'm1' } })).toBe(0);
  });
});

describe('dropBelowMinPrice', () => {
  test('drops only NSE futures below the minimum, using the current close', async () => {
    mockFind.mockReturnValue({ select: () => ({ lean: async () => [
      { instrument_token: '1', segment: 'NFO-FUT', settlement_price: 69.08 },
      { instrument_token: '2', segment: 'NFO-FUT', settlement_price: 1193.4 },
    ] }) });
    const items = [
      { instrument_token: '1', segment: 'NFO-FUT' },
      { instrument_token: '2', segment: 'NFO-FUT' },
      { instrument_token: '3', segment: 'NFO-OPT' },
    ];
    const out = await m.dropBelowMinPrice(items, 100);
    expect(out.map((i) => i.instrument_token)).toEqual(['2', '3']);
  });
  test('off → list untouched, no lookup', async () => {
    mockFind.mockClear();
    const items = [{ instrument_token: '1', segment: 'NFO-FUT' }];
    expect(await m.dropBelowMinPrice(items, 0)).toBe(items);
    expect(mockFind).not.toHaveBeenCalled();
  });
});

describe('minPriceMongoFilter', () => {
  test('off → null; on → keeps other segments, at/above the minimum, and unknown closes', () => {
    expect(m.minPriceMongoFilter(0)).toBeNull();
    expect(m.minPriceMongoFilter(100)).toEqual({ $or: [
      { segment: { $ne: 'NFO-FUT' } },
      { settlement_price: { $gte: 100 } },
      { settlement_price: { $not: { $gt: 0 } } },
    ] });
  });
});
