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

describe('lot-aware hold (openLots + lotHoldRejection)', () => {
  const { openLots, lotHoldRejection } = require('../src/utils/freshStoplossHold');
  const at = (iso) => new Date(iso);
  const f = (side, qty, iso) => ({ transaction_type: side, executed_quantity: qty, executed_at: at(iso) });

  // GBN5 GOLD26DECFUT, 12-13 Oct 2026 (IST times as UTC+05:30)
  const gold = [
    f('BUY', 100, '2026-10-12T22:32:27+05:30'),
    f('BUY', 100, '2026-10-13T09:33:44+05:30'),
    f('SELL', 100, '2026-10-13T10:14:18+05:30'),
    f('BUY', 100, '2026-10-13T11:22:39+05:30'),
  ];
  const now = Date.parse('2026-10-13T11:22:55+05:30');

  test('openLots: a close consumes the oldest lot', () => {
    expect(openLots(gold).map((l) => [l.qty, l.openedAt.toISOString()])).toEqual([
      [100, '2026-10-13T04:03:44.000Z'],
      [100, '2026-10-13T05:52:39.000Z'],
    ]);
  });

  test('closing the older lot is allowed right after adding', () => {
    expect(lotHoldRejection({ lots: openLots(gold), closeQuantity: 100, timeMinutes: 10, now })).toBeNull();
  });

  test('closing both lots waits for the new one, and says how much can go now', () => {
    expect(lotHoldRejection({ lots: openLots(gold), closeQuantity: 200, timeMinutes: 10, now }))
      .toBe('Fresh Stop-Loss: Cannot close more than 100 qty for 10 more minute(s) — the rest was opened in the last 10 minutes. Time restriction: 10 minutes.');
    // 10 min after the add, both can go
    expect(lotHoldRejection({ lots: openLots(gold), closeQuantity: 200, timeMinutes: 10, now: Date.parse('2026-10-13T11:32:40+05:30') })).toBeNull();
  });

  test('a fresh position with nothing aged keeps the original message', () => {
    const fresh = [f('BUY', 30, '2026-10-13T09:54:45+05:30')];
    expect(lotHoldRejection({ lots: openLots(fresh), closeQuantity: 30, timeMinutes: 10, now: Date.parse('2026-10-13T09:58:45+05:30') }))
      .toBe('Fresh Stop-Loss: Cannot close this position for 6 more minute(s). Time restriction: 10 minutes.');
  });

  test('shorts work the same way; a flip only counts the closing part', () => {
    const short = [f('SELL', 30, '2026-10-12T20:57:22+05:30'), f('SELL', 30, '2026-10-12T21:24:33+05:30')];
    const t = Date.parse('2026-10-12T21:28:50+05:30');
    expect(lotHoldRejection({ lots: openLots(short), closeQuantity: 30, timeMinutes: 10, now: t })).toBeNull(); // the 20:57 lot is aged
    expect(lotHoldRejection({ lots: openLots(short), closeQuantity: 60, timeMinutes: 10, now: t })).toMatch(/Cannot close more than 30 qty for 6 more minute/);
    expect(lotHoldRejection({ lots: openLots(short), closeQuantity: 90, timeMinutes: 10, now: t })).toMatch(/more than 30 qty/); // 90 = 60 close + 30 new
  });

  test('flat after a round trip -> no lots, no hold', () => {
    expect(openLots([f('BUY', 10, '2026-10-13T09:00:00Z'), f('SELL', 10, '2026-10-13T09:01:00Z')])).toEqual([]);
    expect(lotHoldRejection({ lots: [], closeQuantity: 10, timeMinutes: 10 })).toBeNull();
  });
});
