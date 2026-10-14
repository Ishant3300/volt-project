'use strict';

// New NFO stock listings (real case: ANANDRATHI added to F&O, Oct 2026, never
// appeared because the daily sync only imports a hand-kept list of names).
const { findNewNfoNames, describeRun } = require('../src/services/newNfoStockService');
const { parseAndFilterInstruments } = require('../scripts/fetchInstruments');

const HEAD = 'instrument_token,exchange_token,tradingsymbol,name,last_price,expiry,strike,tick_size,lot_size,instrument_type,segment,exchange';
const dump = [
  HEAD,
  '1829121,7145,ANANDRATHI,"ANAND RATHI WEALTH",0,,0,0.1,1,EQ,NSE,NSE',
  '15075586,58889,ANANDRATHI26OCTFUT,"ANANDRATHI",0,2026-10-27,0,0.1,250,FUT,NFO-FUT,NFO',
  '15075587,58890,ANANDRATHI26OCT2000CE,"ANANDRATHI",0,2026-10-27,2000,0.05,250,CE,NFO-OPT,NFO',
  '60417,236,ASIANPAINT,"ASIAN PAINTS",0,,0,0.1,1,EQ,NSE,NSE',
  '12345,1,ASIANPAINT26OCTFUT,"ASIANPAINT",0,2026-10-27,0,0.1,250,FUT,NFO-FUT,NFO',
  '22222,2,NIFTYNXT5026OCTFUT,"NIFTYNXT50",0,2026-10-27,0,0.1,25,FUT,NFO-FUT,NFO',
  '33333,3,NICKEL26OCTFUT,"NICKEL",0,2026-10-31,0,0.1,1500,FUT,MCX-FUT,MCX',
].join('\n');

test('a new NFO stock is found with its lot size; listed names are not', () => {
  const { stocks } = findNewNfoNames(dump, new Set(['ASIANPAINT']));
  expect(stocks).toEqual([{ name: 'ANANDRATHI', lot: 250, lots: [250], fut: 1, opt: 1 }]);
});

test('a new index contract (no NSE equity) is reported, never treated as a stock', () => {
  const { stocks, others } = findNewNfoNames(dump, new Set(['ASIANPAINT']));
  expect(stocks.map((s) => s.name)).not.toContain('NIFTYNXT50');
  expect(others.map((o) => o.name)).toEqual(['NIFTYNXT50']);
});

test('MCX listings are ignored entirely (NFO only)', () => {
  const { stocks, others } = findNewNfoNames(dump, new Set());
  expect([...stocks, ...others].map((x) => x.name)).not.toContain('NICKEL');
});

test('auto-added names import their NFO contracts only, not an NSE equity of the same name', () => {
  const sameNameEq = `${dump}\n9999,9,ANANDRATHI,"ANANDRATHI",0,,0,0.1,1,EQ,NSE,NSE`;
  const { instruments } = parseAndFilterInstruments(sameNameEq, new Set(['ASIANPAINT']), new Set(['ANANDRATHI']));
  const got = instruments.filter((i) => i.name === 'ANANDRATHI');
  expect(got.map((i) => i.exchange)).toEqual(['NFO', 'NFO']);
});

test('names on the hand-kept list still import across exchanges as before', () => {
  const { instruments } = parseAndFilterInstruments(dump, new Set(['ASIANPAINT']));
  expect(instruments.map((i) => i.tradingsymbol)).toEqual(['ASIANPAINT26OCTFUT']);
});

test('the Telegram text names what was added, what was held back and why', () => {
  const text = describeRun({
    ready: [{ name: 'ANANDRATHI', lot: 250 }],
    notReady: [{ name: 'RADICO', missing: ['NFO-FUT limits 100/139'] }],
    others: [{ name: 'NIFTYNXT50' }],
    counts: { qty: 278, group: 25, brk: 282, fsl: 2 },
  });
  expect(text).toContain('ANANDRATHI (lot 250)');
  expect(text).toContain('RADICO — NFO-FUT limits 100/139');
  expect(text).toContain('NIFTYNXT50');
});
