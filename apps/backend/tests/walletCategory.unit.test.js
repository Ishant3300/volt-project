'use strict';

// Validates: Requirement 2.2 (segment -> category mapping) and the
// allowedCategories derivation used by metrics / wallet funding.
// NSE options have their own pool, NSEOPT ("NSE OPT"): option margin is
// blocked/released only there, never from the NSE (futures) pool. NIFTY /
// BANKNIFTY / SENSEX futures have their own pool too, INDEX (Oct 2026).

const {
  CATEGORY,
  CATEGORY_ORDER,
  categoryForSegment,
  categoryLabel,
  allowedCategories,
  isIndexFuture,
} = require('../src/utils/walletCategory');

const ticked = (exchange_name) => ({ exchange_name, turnover: true, lot: false, group_name: '' });

describe('categoryForSegment', () => {
  test.each([
    ['NFO-FUT', 'NSE'],
    ['NFO-OPT', 'NSEOPT'],
    ['MCX-FUT', 'MCX'],
    ['MCX-OPT', 'MCX'],
    ['COMEX-FUT', 'COMEX'],
    // "everything else" -> GLOBAL
    ['SGX', 'GLOBAL'],
    ['INDICES', 'GLOBAL'],
    ['GLOBAL', 'GLOBAL'],
    ['BFO-FUT', 'GLOBAL'],
    ['BFO-OPT', 'GLOBAL'],
    ['NSE', 'GLOBAL'],
    ['NFO', 'GLOBAL'],
    ['OTHERS', 'GLOBAL'],
  ])('maps %s -> %s', (segment, expected) => {
    expect(categoryForSegment(segment)).toBe(expected);
  });

  test('is case-insensitive and trims surrounding whitespace', () => {
    expect(categoryForSegment('nfo-fut')).toBe('NSE');
    expect(categoryForSegment('  mcx-opt  ')).toBe('MCX');
    expect(categoryForSegment('Nfo-Opt')).toBe('NSEOPT');
  });

  test('defaults unknown / empty / nullish input to GLOBAL', () => {
    expect(categoryForSegment('')).toBe('GLOBAL');
    expect(categoryForSegment()).toBe('GLOBAL');
    expect(categoryForSegment(null)).toBe('GLOBAL');
    expect(categoryForSegment('SOMETHING-NEW')).toBe('GLOBAL');
  });

  test('exposes the canonical category constants, order and labels', () => {
    expect(CATEGORY).toEqual({ NSE: 'NSE', INDEX: 'INDEX', NSEOPT: 'NSEOPT', MCX: 'MCX', COMEX: 'COMEX', GLOBAL: 'GLOBAL' });
    expect(CATEGORY_ORDER).toEqual(['NSE', 'INDEX', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL']);
    expect(categoryLabel('NSEOPT')).toBe('NSE OPT');
    expect(categoryLabel('INDEX')).toBe('INDEX');
    expect(categoryLabel('MCX')).toBe('MCX');
  });
});

describe('INDEX pool — NIFTY / BANKNIFTY / SENSEX futures', () => {
  test.each([
    [{ name: 'NIFTY' }], [{ raw_name: 'BANKNIFTY' }], [{ name: 'SENSEX' }],
    [{ tradingsymbol: 'NIFTY26OCTFUT' }], [{ tradingsymbol: 'BANKNIFTY26NOVFUT' }], [{ tradingsymbol: 'SENSEX26OCTFUT' }],
    ['NIFTY'], ['NIFTY26DECFUT'],
  ])('NFO-FUT %j -> INDEX', (ref) => {
    expect(categoryForSegment('NFO-FUT', ref)).toBe('INDEX');
  });

  test.each([
    [{ name: 'RELIANCE' }], [{ tradingsymbol: 'TCS26OCTFUT' }],
    // other index futures stay on NSE — only the three named ones move
    [{ name: 'FINNIFTY' }], [{ name: 'MIDCPNIFTY' }], [{ name: 'NIFTYNXT50' }], [{ name: 'BANKEX' }],
    [{ tradingsymbol: 'NIFTYNXT5026OCTFUT' }], [{ tradingsymbol: 'FINNIFTY26OCTFUT' }], [{ tradingsymbol: 'MIDCPNIFTY26OCTFUT' }],
  ])('NFO-FUT %j -> NSE', (ref) => {
    expect(categoryForSegment('NFO-FUT', ref)).toBe('NSE');
  });

  test('options and other segments are unaffected by the underlying', () => {
    expect(categoryForSegment('NFO-OPT', { name: 'NIFTY' })).toBe('NSEOPT');
    expect(categoryForSegment('NFO-OPT', { tradingsymbol: 'NIFTY26OCT25000CE' })).toBe('NSEOPT');
    expect(categoryForSegment('MCX-FUT', { name: 'NIFTY' })).toBe('MCX');
    expect(categoryForSegment('GLOBAL', { name: 'SENSEX' })).toBe('GLOBAL');
  });

  test('any of several refs can identify it (instrument first, then the trade)', () => {
    expect(categoryForSegment('NFO-FUT', null, { tradingsymbol: 'NIFTY26OCTFUT' })).toBe('INDEX');
    expect(categoryForSegment('NFO-FUT', { segment: 'NFO-FUT' }, { tradingsymbol: 'BANKNIFTY26OCTFUT' })).toBe('INDEX');
    expect(isIndexFuture()).toBe(false);
  });
});

describe('allowedCategories', () => {
  test('derives distinct categories from the Master shape (array of strings)', () => {
    expect(allowedCategories(['NFO-FUT', 'MCX-FUT', 'SGX'])).toEqual(['NSE', 'INDEX', 'MCX', 'GLOBAL']);
  });

  test('derives distinct categories from the User shape (array of objects)', () => {
    const exchangesAllowed = [
      { exchange_name: 'NFO-OPT', turnover: false, lot: true, group_name: '' },
      { exchange_name: 'MCX-OPT', turnover: false, lot: true, group_name: '' },
    ];
    expect(allowedCategories(exchangesAllowed)).toEqual(['NSEOPT', 'MCX']);
  });

  test('NSE futures and NSE options are separate pools; NFO futures span NSE + INDEX', () => {
    expect(allowedCategories(['NFO-FUT', 'NFO-OPT'])).toEqual(['NSE', 'INDEX', 'NSEOPT']);
    expect(allowedCategories(['NFO-OPT'])).toEqual(['NSEOPT']);
    expect(allowedCategories(['NFO-FUT'])).toEqual(['NSE', 'INDEX']);
  });

  test('deduplicates categories that share a mapping', () => {
    expect(allowedCategories(['MCX-FUT', 'MCX-OPT'])).toEqual(['MCX']);
  });

  test('returns categories in canonical order regardless of input order', () => {
    expect(allowedCategories(['SGX', 'MCX-FUT', 'NFO-OPT', 'NFO-FUT'])).toEqual(['NSE', 'INDEX', 'NSEOPT', 'MCX', 'GLOBAL']);
  });

  test('a User row only counts when ticked (turnover or lot on)', () => {
    expect(allowedCategories([
      { exchange_name: 'NFO-FUT', turnover: true, lot: false },
      { exchange_name: 'NFO-OPT', turnover: false, lot: false },
      { exchange_name: 'MCX-FUT' },
    ])).toEqual(['NSE', 'INDEX']);
  });

  test('ignores blank, null and malformed entries', () => {
    expect(allowedCategories(['NFO-FUT', '', null, {}, { exchange_name: '  ', turnover: true }])).toEqual(['NSE', 'INDEX']);
  });

  test('is case-insensitive for entry names', () => {
    expect(allowedCategories(['nfo-fut', ticked('mcx-opt'), ticked('nfo-opt')])).toEqual(['NSE', 'INDEX', 'NSEOPT', 'MCX']);
  });

  test('returns an empty array for empty or non-array input', () => {
    expect(allowedCategories([])).toEqual([]);
    expect(allowedCategories()).toEqual([]);
    expect(allowedCategories(null)).toEqual([]);
    expect(allowedCategories('NFO-FUT')).toEqual([]);
  });
});
