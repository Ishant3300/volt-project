// Equity (NSE cash) engine — the spec's worked numbers, plus the golden hashes of
// Trade Terminal's original output (tests/fixtures/cashEqGolden.json, written by
// scripts/cashEq/goldenCompare.js --write-hashes).

const crypto = require('crypto');
const engine = require('../src/cashEq/engine');
const { makeScenario, runScenario, canonical } = require('../scripts/cashEq/goldenScenarios');
const golden = require('./fixtures/cashEqGolden.json');

const slab = (over = {}) => ({
  id: 1, clientCode: 'C002', segment: 'NSEEQ', scriptWise: false, script: '', mode: 'PCT',
  delPct: 0.5, intraPct: 0, fixDel: 0, fixIntra: 0, higherSideOnly: false, minRate: 0, minPct: 0, minPctOnDel: 0, ...over,
});
const trade = (id, date, side, qty, rate, over = {}) => ({
  id, ot: 'T', date, valan: '', segment: 'NSEEQ', script: 'KPIGREEN', option: '', strike: 0, tradeType: 'NRM',
  side, lot: qty, qty, rate, clientCode: 'C002', user: '', ip: '', addTime: `${date} 10:00:00`, ...over,
});
const account = (over = {}) => ({ code: 'C002', openingBalance: 0, openingType: 'Cr', interestPct: 18, ...over });

describe('cashEq engine — spec worked example (KPIGREEN, delivery 0.5 %)', () => {
  const trades = [trade(1, '2026-09-28', 'B', 1000, 352.40), trade(2, '2026-10-06', 'B', 1000, 321.45)];
  const calcs = engine.computeTradeCalcs(trades, [slab()]);
  const settlements = [
    { segment: 'NSEEQ', settleDate: '2026-10-01', priceDate: '2026-09-30', prices: { KPIGREEN: 358.95 } },
    { segment: 'NSEEQ', settleDate: '2026-11-01', priceDate: '2026-10-30', prices: { KPIGREEN: 277.30 } },
  ];

  test('net rates fold brokerage into the price', () => {
    expect(calcs.get(1).brokerage).toBeCloseTo(1762.0, 6);
    expect(calcs.get(1).netRate).toBeCloseTo(354.162, 9);
    expect(calcs.get(2).brokerage).toBeCloseTo(1607.25, 6);
    expect(calcs.get(2).netRate).toBeCloseTo(323.05725, 9);
  });

  test('September MTM +4,788.00 and October MTM −1,27,407.25', () => {
    const l = engine.computeClientLedger(account(), trades, calcs, [], settlements, '2026-10-31');
    expect(l.settlements[0].mtm).toBe(4788.0);
    expect(l.settlements[1].mtm).toBe(-127407.25);
  });

  test('report as on 31-10: avg 341.00, P&L −1,27,407.25 at 277.30', () => {
    const c = engine.carryToSettlement(trades, calcs, settlements, '2026-10-31');
    const [p] = engine.computePositions(c.trades, c.calcs, { 'NSEEQ|KPIGREEN': 277.30 });
    expect(p.buyQty).toBe(2000);
    expect(engine.round2(p.avgBuy)).toBe(341.0);
    expect(engine.round2(p.mtm)).toBe(-127407.25);
  });

  test('from 01-11 both lots carry at 277.30', () => {
    const c = engine.carryToSettlement(trades, calcs, settlements, '2026-11-01');
    expect(c.trades.map((t) => [t.tradeType, t.qty, t.rate])).toEqual([['BF', 1000, 277.3], ['BF', 1000, 277.3]]);
  });
});

describe('cashEq engine — interest on the funded amount', () => {
  // Margin used 40,00,000 (no brokerage: no slab).
  const trades = [trade(1, '2026-09-10', 'B', 10000, 400)];
  const calcs = engine.computeTradeCalcs(trades, []);

  test('client money 10,000 Cr → funded 39,90,000 → ₹1,967.67 for the day', () => {
    const l = engine.computeClientLedger(account({ openingBalance: 10000 }), trades, calcs, [], [], '2026-09-10');
    expect(l.funded).toBe(3990000);
    expect(engine.round2(l.accruedInterest)).toBe(1967.67);
  });

  test('client money 5,00,000 Dr → funded 45,00,000 → ₹2,219.18', () => {
    const l = engine.computeClientLedger(account({ openingBalance: 500000, openingType: 'Dr' }), trades, calcs, [], [], '2026-09-10');
    expect(l.funded).toBe(4500000);
    expect(engine.round2(l.accruedInterest)).toBe(2219.18);
  });

  test('intraday round trip uses no margin and charges no interest', () => {
    const t2 = [trade(1, '2026-09-10', 'B', 100, 400), trade(2, '2026-09-10', 'S', 100, 410, { addTime: '2026-09-10 14:00:00' })];
    const l = engine.computeClientLedger(account(), t2, engine.computeTradeCalcs(t2, []), [], [], '2026-09-30');
    expect(l.margin).toBe(0);
    expect(l.accruedInterest).toBe(0);
    expect(l.pendingPnl).toBe(1000);
  });
});

describe('cashEq engine — two interest rates, funded split in proportion (approved vs non-approved)', () => {
  // 60 L approved + 40 L non-approved held, client money 10 L Cr → funded 90 L:
  // 54 L at 15 % + 36 L at 20 % for the day.
  const trades = [
    trade(1, '2026-09-10', 'B', 6000, 1000, { script: 'RELIANCE', mtf: true }),
    trade(2, '2026-09-10', 'B', 4000, 1000, { script: 'SMALLCO', mtf: false }),
  ];
  const calcs = engine.computeTradeCalcs(trades, []);
  const acc = (over = {}) => account({ openingBalance: 1000000, interestPct: 15, interestNonPct: 20, ...over });

  test('one day: 54 L × 15 % + 36 L × 20 % ÷ 365 = ₹4,191.78', () => {
    const l = engine.computeClientLedger(acc(), trades, calcs, [], [], '2026-09-10');
    expect(l.funded).toBe(9000000);
    expect([l.marginMtf, l.marginNon]).toEqual([6000000, 4000000]);
    expect(engine.round2(l.accruedInterestMtf)).toBe(engine.round2(5400000 * 0.15 / 365));
    expect(engine.round2(l.accruedInterestNon)).toBe(engine.round2(3600000 * 0.20 / 365));
    expect(engine.round2(l.accruedInterest)).toBe(4191.78);
  });

  test('equal rates: exactly the single-rate (Trade Terminal) result', () => {
    const two = engine.computeClientLedger(acc({ interestNonPct: 15 }), trades, calcs, [], [], '2026-09-30');
    const plain = trades.map(({ mtf, ...t }) => t);
    const one = engine.computeClientLedger(account({ openingBalance: 1000000, interestPct: 15 }), plain, engine.computeTradeCalcs(plain, []), [], [], '2026-09-30');
    expect(two.accruedInterest).toBe(one.accruedInterest);
    expect(two.money).toBe(one.money);
  });

  test('only non-approved held: all funded at the non-approved rate', () => {
    const t = [trades[1]];
    const l = engine.computeClientLedger(acc({ openingBalance: 0 }), t, engine.computeTradeCalcs(t, []), [], [], '2026-09-10');
    expect(engine.round2(l.accruedInterest)).toBe(engine.round2(4000000 * 0.20 / 365));
  });

  test('selling the non-approved lot moves all funding to the approved rate from that day', () => {
    const t = [...trades, trade(3, '2026-09-11', 'S', 4000, 1000, { script: 'SMALLCO', mtf: false })];
    const l = engine.computeClientLedger(acc(), t, engine.computeTradeCalcs(t, []), [], [], '2026-09-11');
    const day1 = 5400000 * 0.15 / 365 + 3600000 * 0.20 / 365;
    const day2 = 5000000 * 0.15 / 365; // 60 L held − 10 L money, all approved
    expect(engine.round2(l.accruedInterest)).toBe(engine.round2(day1 + day2));
  });

  test('month-end: one interest row with both rates; the split is kept for sharing', () => {
    const st = [{ segment: 'NSEEQ', settleDate: '2026-10-01', priceDate: '2026-09-30', prices: { RELIANCE: 1000, SMALLCO: 1000 } }];
    const l = engine.computeClientLedger(acc(), trades, calcs, [], st, '2026-09-30');
    const row = l.rows.find((r) => r.kind === 'INTEREST');
    expect(row.particulars).toBe('Interest 10-09-2026 to 30-09-2026 @ 15% approved / 20% non-approved');
    const s = l.settlements[0];
    expect(Math.abs(s.interestMtf + s.interestNon - s.interest)).toBeLessThanOrEqual(0.01);
    expect(engine.round2(s.interest)).toBe(engine.round2(21 * (5400000 * 0.15 + 3600000 * 0.20) / 365));
  });
});

describe('cashEq engine — identical to Trade Terminal (golden hashes)', () => {
  test.each(Object.keys(golden.hashes).map(Number))('seed %i', (seed) => {
    const out = canonical(runScenario(makeScenario(seed), engine));
    expect(crypto.createHash('sha256').update(out).digest('hex')).toBe(golden.hashes[seed]);
  });
});
