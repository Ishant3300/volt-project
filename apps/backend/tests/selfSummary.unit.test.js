'use strict';

// Self Summary (scope view), 5 Nov 2026. The split is checked against the
// reference screen the user shared (ADANIGREEN 23NOV2026, week 02-07 Nov):
//   harris (direct client, viewer 94%):  total 50,066.31 → self -47,062.33, upline -3,003.98
//   (260)CHD (sub-master 80% under it):   total 67,558.87 → self -9,458.24, down -54,047.10, up -4,053.53
//   MNS2 line given fully (94%) to the sub-master → self 0.

jest.mock('../src/models/Trade', () => ({}));
jest.mock('../src/models/User', () => ({}));
jest.mock('../src/models/Master', () => ({}));
jest.mock('../src/models/KiteInstrument', () => ({}));
const { _private: { marketName, scriptName, lineFor, buildRows, totalsOf } } = require('../src/controllers/selfSummaryController');

const masterMap = {
  V: { _id: 'V', master_id: 'TOP', pnl_sharing: 94 },     // the viewer
  TOP: { _id: 'TOP', master_id: null, pnl_sharing: 100 },
  CHD: { _id: 'CHD', master_id: 'V', pnl_sharing: 80 },
  CHD2: { _id: 'CHD2', master_id: 'CHD', pnl_sharing: 50 }, // deeper under CHD
  MNS2: { _id: 'MNS2', master_id: 'V', pnl_sharing: 94 },
};
const viewer = { id: 'V', role: 'master' };

const slot = (uid, token, o) => ({ uid, token, buy_qty: 0, buy_value: 0, buy_brk: 0, sell_qty: 0, sell_value: 0, sell_brk: 0,
  brokerage: 0, realised: 0, floating: 0, ltp: 1418.3, ...o });

test('market and script names like the reference', () => {
  expect(marketName('NFO-FUT')).toBe('NSEFUT');
  expect(marketName('NFO-OPT')).toBe('NSEOPT');
  expect(marketName('MCX-FUT')).toBe('MCXFUT');
  expect(marketName('BFO-OPT')).toBe('BSEOPT');
  expect(scriptName({ name: 'ABB', expiry: '2026-11-23T00:00:00Z', instrument_type: 'FUT' }, 'ABB26NOVFUT')).toBe('ABB 23NOV2026');
  expect(scriptName({ name: 'BANKNIFTY', expiry: '2026-11-23T00:00:00Z', instrument_type: 'PE', strike: 50000 }, 'x')).toBe('BANKNIFTY 50000 PE 23NOV2026');
  expect(scriptName(null, 'RAW')).toBe('RAW');
});

test('ceiling split: direct client, sub-master line, deeper client, line given fully, admin', () => {
  expect(lineFor('V', viewer, masterMap)).toMatchObject({ selfPct: 94, downPct: 0, upPct: 6 });
  expect(lineFor('CHD', viewer, masterMap)).toMatchObject({ selfPct: 14, downPct: 80, upPct: 6 });
  expect(lineFor('CHD2', viewer, masterMap)).toMatchObject({ selfPct: 14, downPct: 80, upPct: 6 });
  expect(lineFor('MNS2', viewer, masterMap)).toMatchObject({ selfPct: 0, downPct: 94, upPct: 6 });
  expect(lineFor('CHD', { id: null, role: 'admin' }, masterMap)).toMatchObject({ selfPct: 0, downPct: 100, upPct: 0 });
});

describe('reference numbers (ADANIGREEN, 02-07 Nov)', () => {
  // Totals chosen so realised + floating - brokerage = the reference Total M2M.
  const perUserScript = new Map([
    ['harris::T', slot('harris', 'T', { buy_qty: 1600, sell_qty: 1000, realised: 6000, floating: 45000, brokerage: 933.69 })],
    ['chdClient::T', slot('chdClient', 'T', { buy_qty: 600, sell_qty: 100, realised: 8000, floating: 60000, brokerage: 441.13 })],
  ]);
  const userMaster = new Map([['harris', 'V'], ['chdClient', 'CHD']]);

  test('scope rows: direct client on its own, sub-master as one row; split matches the reference exactly', () => {
    const rows = buildRows({ perUserScript, userMaster, masterMap, viewer, tokenFilter: 'T' });
    const h = rows.find((r) => r.id === 'harris');
    const c = rows.find((r) => r.id === 'CHD');
    expect(h).toMatchObject({ kind: 'client', net_qty: 600, self_qty: 564, total_m2m: 50066.31, self_m2m: -47062.33, downline_m2m: 0, upline_m2m: -3003.98 });
    expect(c).toMatchObject({ kind: 'master', net_qty: 500, self_qty: 70, total_m2m: 67558.87, self_m2m: -9458.24, downline_m2m: -54047.1, upline_m2m: -4053.53 });
    const t = totalsOf(rows);
    expect(t).toMatchObject({ net_qty: 1100, self_qty: 634, total_m2m: 117625.18 });
    // every row: self + down + up = −total
    for (const r of rows) expect(r.self_m2m + r.downline_m2m + r.upline_m2m).toBeCloseTo(-r.total_m2m, 1);
  });

  test('level 1 rolls everything for the script into one row; drilling into CHD lists its own clients', () => {
    const l1 = buildRows({ perUserScript, userMaster, masterMap, viewer });
    expect(l1).toHaveLength(1);
    expect(l1[0]).toMatchObject({ token: 'T', buy_qty: 2200, sell_qty: 1100, net_qty: 1100, total_m2m: 117625.18 });
    const inChd = buildRows({ perUserScript, userMaster, masterMap, viewer, tokenFilter: 'T', parentId: 'CHD' });
    expect(inChd).toEqual([expect.objectContaining({ kind: 'client', id: 'chdClient', self_m2m: -9458.24 })]);
  });
});

test('avg rates carry brokerage: buy + brk/qty, sell − brk/qty', () => {
  const m = new Map([['u::T', slot('u', 'T', { buy_qty: 100, buy_value: 100000, buy_brk: 50, sell_qty: 100, sell_value: 110000, sell_brk: 50, brokerage: 100, realised: 10000 })]]);
  const [row] = buildRows({ perUserScript: m, userMaster: new Map([['u', 'V']]), masterMap, viewer });
  expect(row).toMatchObject({ buy_avg: 1000.5, sell_avg: 1099.5, total_m2m: 9900 });
});

describe('B/F and settlement-based period (5 Nov 2026)', () => {
  const { _private: p } = require('../src/controllers/selfSummaryController');
  const S = new Date('2026-10-30T22:20:00.000Z'); // Sat 31 Oct 03:50 IST
  const close = { trade_type: 'carry_forward', executed_at: S, remarks: 'Settlement 2026-10-30: position closed at official price' };
  const reopen = { trade_type: 'carry_forward', executed_at: new Date(S.getTime() + 1), remarks: 'Settlement 2026-10-30: carried forward at official price' };

  test('settlement time from either leg', () => {
    expect(p.settlementTimeOf(close)).toBe(S.getTime());
    expect(p.settlementTimeOf(reopen)).toBe(S.getTime());
  });

  test('only the reopen leg at the period start is B/F', () => {
    const start = new Date(S.getTime() + 1);
    expect(p.isBroughtForward(reopen, start)).toBe(true);
    expect(p.isBroughtForward(close, start)).toBe(false);
    expect(p.isBroughtForward({ ...reopen, executed_at: new Date(S.getTime() + 7 * 864e5 + 1) }, start)).toBe(false);
    expect(p.isBroughtForward({ trade_type: 'regular', executed_at: start }, start)).toBe(false);
  });
});
