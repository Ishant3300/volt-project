'use strict';

// averageCostState: the position left after replaying fills onto a seed —
// used for the position carried INTO a report window (account 266: opening
// positions entered as ordinary trades after Saturday's settlement).

const { averageCostState, computeAveragePricePnl } = require('../src/utils/averageCostPnl');

const buy = (qty, rate, date) => ({ date, buy_qty: qty, sell_qty: 0, rate });
const sell = (qty, rate, date) => ({ date, buy_qty: 0, sell_qty: qty, rate });

test('fills alone (no carry-forward) build the opening position', () => {
  expect(averageCostState([buy(910, 23186.7, '2026-09-26T17:52:26Z')], null))
    .toEqual({ totalBuyQty: 910, totalBuyValue: 910 * 23186.7, totalSellQty: 0, totalSellValue: 0 });
});

test('fills replay on top of a carry-forward seed (average cost, partial close)', () => {
  const seed = { totalBuyQty: 100, totalBuyValue: 100 * 10, totalSellQty: 0, totalSellValue: 0 };
  const s = averageCostState([buy(100, 20, '2026-09-29'), sell(50, 30, '2026-09-30')], seed);
  expect(s.totalBuyQty).toBe(150);
  expect(s.totalBuyValue / s.totalBuyQty).toBeCloseTo(15);
});

test('a fully closed position leaves nothing carried', () => {
  const s = averageCostState([buy(10, 5, '2026-09-29'), sell(10, 6, '2026-09-30')], null);
  expect(s.totalBuyQty).toBe(0);
  expect(s.totalSellQty).toBe(0);
});

test('does not modify the trades passed in; P&L helper unchanged', () => {
  const trades = [buy(10, 5, '2026-09-29'), sell(10, 6, '2026-09-30')];
  averageCostState(trades, null);
  expect(trades[1].pnl).toBeUndefined();
  expect(computeAveragePricePnl(trades, null)).toBe(10);
});

test('266 NIFTY Sep: the 910 close is priced against the carried 23,186.70', () => {
  const seed = averageCostState([buy(910, 23186.7, '2026-09-26T17:52:26Z')], null);
  expect(computeAveragePricePnl([sell(910, 22680, '2026-09-29T09:00:32Z')], seed)).toBe(-461097);
});
