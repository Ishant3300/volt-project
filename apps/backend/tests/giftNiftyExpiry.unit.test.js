const feed = require('../src/services/giftNiftyFeedService');

const { parseNseixDate, parseNseixTimestamp, isPastExpiry, listedExpiries } = feed._private;
const contracts = require('../src/services/giftNiftyContracts');
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

  test('expiry day 3:30–4:00 PM is closing-only for the expiring GIFT contract only', () => {
    const gift = { tradingsymbol: 'GIFT NIFTY', exchange: 'NSEIX', expiry: d('2026-09-29') };
    const octOnSepExpiry = { tradingsymbol: 'GIFTNIFTY26OCTFUT', exchange: 'NSEIX', expiry: d('2026-10-27') };
    expect(feed.isGiftExpiryHalt(octOnSepExpiry, ist('2026-09-29T15:35:00'))).toBe(false); // next month trades on
    expect(feed.isGiftExpiryHalt({ ...octOnSepExpiry }, ist('2026-10-27T15:35:00'))).toBe(true); // on its own expiry day
    expect(feed.isGiftExpiryHalt(gift, ist('2026-09-29T15:29:00'))).toBe(false);
    expect(feed.isGiftExpiryHalt(gift, ist('2026-09-29T15:30:00'))).toBe(true);
    expect(feed.isGiftExpiryHalt(gift, ist('2026-09-29T15:39:00'))).toBe(true);
    expect(feed.isGiftExpiryHalt(gift, ist('2026-09-29T16:00:00'))).toBe(false); // next month, session 2
    expect(feed.isGiftExpiryHalt(gift, ist('2026-09-28T15:35:00'))).toBe(false); // not expiry day
    expect(feed.isGiftExpiryHalt({ tradingsymbol: 'NIFTY26SEPFUT', exchange: 'NFO', expiry: d('2026-09-29') }, ist('2026-09-29T15:35:00'))).toBe(false);
  });

  test('NSE IX timestamps are India time', () => {
    expect(parseNseixTimestamp('28-Sep-2026 10:17:09').toISOString()).toBe('2026-09-28T04:47:09.000Z');
    expect(Number.isNaN(parseNseixTimestamp('NA').getTime())).toBe(true);
  });

  test('monthly contracts: symbol like other futures, token outside the Kite range', () => {
    expect(contracts.contractSymbol(d('2026-10-27'))).toBe('GIFTNIFTY26OCTFUT');
    expect(contracts.contractSymbol(d('2027-01-26'))).toBe('GIFTNIFTY27JANFUT');
    expect(contracts.contractToken(d('2026-10-27'))).toBe('9920261027');
    expect(contracts.isGiftContractToken('9920261027')).toBe(true);
    expect(contracts.isGiftContractToken('12468226')).toBe(false); // a Kite token
    const c = contracts.buildContract(d('2026-11-23'), false);
    expect(c).toMatchObject({ name: 'GIFT NIFTY', raw_name: 'GIFT NIFTY', segment: 'INDICES', exchange: 'NSEIX', instrument_type: 'FUT', enabled: false });
  });
});

describe('GIFT tick day fields (OHLC / change) from the NSEIX row', () => {
  const { dayFields } = feed._private;
  // Real NSEIX row, 28 Sep 2026 20:55 — Oct contract.
  const oct = { OPEN: 23228, HIGH: 23237.5, LOW: 22829.5, CLOSE: 22876, CHANGE: -9.5, PERCHANGE: -0.04 };

  test('open/high/low from the session, close = previous settlement, change = last - close', () => {
    const f = dayFields(oct, 22866.5);
    expect(f).toMatchObject({ open: 23228, high: 23237.5, low: 22829.5, close: 22876, change: -9.5 });
    expect(f.change_percent).toBeCloseTo(-0.0415, 3);
  });

  test('missing / zero fields are left out, never sent as 0', () => {
    expect(dayFields({ OPEN: 0, HIGH: '', LOW: undefined, CLOSE: null }, 22866.5)).toEqual({});
    expect(dayFields({ HIGH: 23000 }, 22866.5)).toEqual({ high: 23000 });
  });
});
