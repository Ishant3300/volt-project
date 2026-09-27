const feed = require('../src/services/giftNiftyFeedService');

const { parseNseixDate, isPastExpiry, listedExpiries } = feed._private;
const d = (s) => new Date(`${s}T00:00:00.000Z`);
const ist = (s) => new Date(`${s}+05:30`);
// Shape of the real NSEIX derivatives-watch response (27 Sep 2026): each
// expiry appears twice, plus non-NIFTY rows.
const row = (expiry, last) => ({ INSTRUMENTTYPE: 'FUTIDX', SYMBOL: 'NIFTY', EXPIRYDATE: expiry, LASTPRICE: last });
const ROWS = [
  row('29-Sep-2026', 23237.5), row('29-Sep-2026', 23237.5),
  row('27-Oct-2026', 23284), row('27-Oct-2026', 23284),
  row('23-Nov-2026', 23400), row('23-Nov-2026', 23400),
  { INSTRUMENTTYPE: 'FUTSTK', SYMBOL: 'RELIANCE', EXPIRYDATE: '29-Sep-2026' },
];

describe('GIFT NIFTY expiries from NSEIX', () => {
  test('parses NSEIX dates exactly, regardless of server time zone', () => {
    expect(parseNseixDate('29-Sep-2026')).toEqual(d('2026-09-29'));
    expect(parseNseixDate('3-Nov-2026')).toEqual(d('2026-11-03'));
    expect(parseNseixDate('')).toBeNull();
    expect(parseNseixDate('2026-09-29')).toBeNull();
  });

  test('quotes stay on the expiring contract until 4:00 PM IST on its expiry day (trading stops 3:30)', () => {
    expect(isPastExpiry(d('2026-09-29'), ist('2026-09-29T15:46:00'))).toBe(false);
    expect(isPastExpiry(d('2026-09-29'), ist('2026-09-29T15:59:00'))).toBe(false);
    expect(isPastExpiry(d('2026-09-29'), ist('2026-09-29T16:00:00'))).toBe(true);
    expect(isPastExpiry(d('2026-09-29'), ist('2026-09-28T23:00:00'))).toBe(false);
    expect(isPastExpiry(d('2026-09-29'), ist('2026-09-30T09:00:00'))).toBe(true);
  });

  test('lists each NIFTY future once, dropping ones that stopped trading', () => {
    expect(listedExpiries(ROWS, ist('2026-09-27T12:00:00'))).toEqual([d('2026-09-29'), d('2026-10-27'), d('2026-11-23')]);
    expect(listedExpiries(ROWS, ist('2026-09-29T16:35:00'))).toEqual([d('2026-10-27'), d('2026-11-23')]);
  });

  test('quotes roll to the next month at 4:00 PM, before session 2 opens at 4:05', () => {
    expect(feed._pickNearMonthFuture(ROWS, ist('2026-09-29T15:31:00')).LASTPRICE).toBe(23237.5); // cut snapshot
    expect(feed._pickNearMonthFuture(ROWS, ist('2026-09-29T15:46:00')).LASTPRICE).toBe(23237.5); // expiry-day close
    expect(feed._pickNearMonthFuture(ROWS, ist('2026-09-29T16:05:00')).LASTPRICE).toBe(23284);
    expect(feed._pickNearMonthFuture([], ist('2026-09-29T16:35:00'))).toBeNull();
  });
});
