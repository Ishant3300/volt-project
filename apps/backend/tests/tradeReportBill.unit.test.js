'use strict';

// GET /api/trade/report?bill=1 — Live Bill fields for the mobile app (BF rows
// = the position carried into the window, reference-style script headings).

const { _private: { billScriptName, billBfRows } } = require('../src/controllers/tradeReportController');

describe('billScriptName', () => {
  test('future: name + expiry as in the reference (NIFTY 29SEP2026)', () => {
    expect(billScriptName('NIFTY26SEPFUT', { name: 'NIFTY', expiry: new Date('2026-09-29T00:00:00Z'), instrument_type: 'FUT' }))
      .toBe('NIFTY 29SEP2026');
    expect(billScriptName('GIFTNIFTY26OCTFUT', { name: 'GIFT NIFTY', expiry: '2026-10-27T00:00:00.000Z', instrument_type: 'FUT' }))
      .toBe('GIFT NIFTY 27OCT2026');
  });
  test('option: name strike type expiry', () => {
    expect(billScriptName('NIFTY26OCT25000CE', { name: 'NIFTY', expiry: '2026-10-27', instrument_type: 'CE', strike: 25000 }))
      .toBe('NIFTY 25000 CE 27OCT2026');
  });
  test('unknown instrument falls back to the tradingsymbol', () => {
    expect(billScriptName('XYZ', undefined)).toBe('XYZ');
    expect(billScriptName('XYZ', {})).toBe('XYZ');
  });
});

describe('billBfRows', () => {
  test('a carried long → one BUY BF row at the carry price and date', () => {
    const date = new Date('2026-09-26T00:20:01Z');
    expect(billBfRows({ totalBuyQty: 200, totalBuyValue: 200 * 23186, totalSellQty: 0, totalSellValue: 0 }, { date }))
      .toEqual([{ side: 'BUY', qty: 200, rate: 23186, date }]);
  });
  test('master view: users carried both sides → one row per side', () => {
    const rows = billBfRows({ totalBuyQty: 100, totalBuyValue: 100 * 10, totalSellQty: 50, totalSellValue: 50 * 12 }, { date: null });
    expect(rows.map((r) => [r.side, r.qty, r.rate])).toEqual([['BUY', 100, 10], ['SELL', 50, 12]]);
  });
  test('nothing carried → no BF row', () => {
    expect(billBfRows(undefined, undefined)).toEqual([]);
  });
});
