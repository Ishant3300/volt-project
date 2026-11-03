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

describe('cashEq engine — identical to Trade Terminal (golden hashes)', () => {
  test.each(Object.keys(golden.hashes).map(Number))('seed %i', (seed) => {
    const out = canonical(runScenario(makeScenario(seed), engine));
    expect(crypto.createHash('sha256').update(out).digest('hex')).toBe(golden.hashes[seed]);
  });
});
