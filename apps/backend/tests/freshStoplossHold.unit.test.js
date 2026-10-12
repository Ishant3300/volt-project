const { closesInProfit, holdTimeRejection } = require('../src/utils/freshStoplossHold');

// Long 10 @ 100 (avg buy 100); short 10 @ 100 (avg sell 100).
const LONG = { netQty: 10, totalBuyQty: 10, totalBuyValue: 1000, totalSellQty: 0, totalSellValue: 0 };
const SHORT = { netQty: -10, totalBuyQty: 0, totalBuyValue: 0, totalSellQty: 10, totalSellValue: 1000 };
const FLAT = { netQty: 0, totalBuyQty: 0, totalBuyValue: 0, totalSellQty: 0, totalSellValue: 0 };

describe('closesInProfit', () => {
  test('MARKET close of a long is judged at the bid', () => {
    expect(closesInProfit({ orderType: 'MARKET', transactionType: 'SELL', state: LONG, bid: 101, ask: 102 })).toBe(true);
    expect(closesInProfit({ orderType: 'MARKET', transactionType: 'SELL', state: LONG, bid: 99, ask: 102 })).toBe(false);
  });

  test('MARKET close of a short is judged at the ask', () => {
    expect(closesInProfit({ orderType: 'MARKET', transactionType: 'BUY', state: SHORT, bid: 97, ask: 98 })).toBe(true);
    expect(closesInProfit({ orderType: 'MARKET', transactionType: 'BUY', state: SHORT, bid: 97, ask: 101 })).toBe(false);
  });

  test('LIMIT close is judged at its own price (it fills there)', () => {
    // SELL limit 105 on a long @100 books profit even while the bid is below cost
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'SELL', price: 105, state: LONG, bid: 98, ask: 99 })).toBe(true);
    // marketable SELL limit below the bid — fills now, at 101: profit
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'SELL', price: 101, state: LONG, bid: 110, ask: 111 })).toBe(true);
    // SELL limit at a loss price is allowed even though the bid is in profit
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'SELL', price: 99, state: LONG, bid: 110, ask: 111 })).toBe(false);
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'BUY', price: 95, state: SHORT })).toBe(true);
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'BUY', price: 100, state: SHORT })).toBe(false);
  });

  test('SL / SL-M closes are judged at their trigger price', () => {
    expect(closesInProfit({ orderType: 'SL', transactionType: 'SELL', price: 104, state: LONG })).toBe(true);
    expect(closesInProfit({ orderType: 'SL-M', transactionType: 'SELL', price: 96, state: LONG })).toBe(false);
    expect(closesInProfit({ orderType: 'SL-M', transactionType: 'BUY', price: 97, state: SHORT })).toBe(true);
  });

  test('opening or adding is never a close', () => {
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'BUY', price: 150, state: LONG })).toBe(false);
    expect(closesInProfit({ orderType: 'MARKET', transactionType: 'SELL', state: FLAT, bid: 150 })).toBe(false);
  });

  test('no usable price -> not treated as profit', () => {
    expect(closesInProfit({ orderType: 'MARKET', transactionType: 'SELL', state: LONG, bid: null })).toBe(false);
    expect(closesInProfit({ orderType: 'LIMIT', transactionType: 'SELL', price: 0, state: LONG })).toBe(false);
  });
});

describe('holdTimeRejection', () => {
  const now = Date.parse('2026-10-12T05:00:00Z');

  test('inside the window -> rejected with minutes remaining', () => {
    const msg = holdTimeRejection({ lastOpenedAt: new Date(now - 3 * 60000 - 30000), timeMinutes: 10, now });
    expect(msg).toBe('Fresh Stop-Loss: Cannot close this position for 7 more minute(s). Time restriction: 10 minutes.');
  });

  test('at / after the window -> allowed', () => {
    expect(holdTimeRejection({ lastOpenedAt: new Date(now - 10 * 60000), timeMinutes: 10, now })).toBeNull();
    expect(holdTimeRejection({ lastOpenedAt: new Date(now - 60 * 60000), timeMinutes: 10, now })).toBeNull();
  });

  test('no limit or no opening fill -> allowed', () => {
    expect(holdTimeRejection({ lastOpenedAt: new Date(now), timeMinutes: 0, now })).toBeNull();
    expect(holdTimeRejection({ lastOpenedAt: null, timeMinutes: 10, now })).toBeNull();
  });
});
