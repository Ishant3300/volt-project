jest.mock('axios', () => ({ get: jest.fn() }));
jest.mock('../src/models/KiteInstrument', () => ({ find: jest.fn(), findOne: jest.fn(), updateOne: jest.fn(async () => ({})) }));

const axios = require('axios');
const KiteInstrument = require('../src/models/KiteInstrument');
const { fetchAndApplyGiftNiftyAtp } = require('../src/services/giftNiftySettlementService');
const { _private: { isBeforeEarliestStart, hasOfficialSettlementAuthority } } = require('../src/services/settlementService');

const chain = (v) => ({ select: () => ({ lean: async () => v }) });

describe('weekly settlement waits for GIFT NIFTY close (Saturday 02:50 IST)', () => {
  test('Saturday before 02:50 IST is too early; 02:50 onwards and weekdays are not', () => {
    expect(isBeforeEarliestStart(new Date('2026-10-09T18:30:00Z'))).toBe(true);  // Sat 00:00
    expect(isBeforeEarliestStart(new Date('2026-10-09T21:19:00Z'))).toBe(true);  // Sat 02:49
    expect(isBeforeEarliestStart(new Date('2026-10-09T21:20:00Z'))).toBe(false); // Sat 02:50
    expect(isBeforeEarliestStart(new Date('2026-10-10T03:00:00Z'))).toBe(false); // Sat 08:30
    expect(isBeforeEarliestStart(new Date('2026-10-09T10:00:00Z'))).toBe(false); // Fri 15:30
  });
  test('GIFT NIFTY settles only on the ATP source, not the official DSP file', () => {
    expect(hasOfficialSettlementAuthority({ exchange: 'NSEIX', settlement_price_source: 'NSEIX_ATP_SESSION_CLOSE' })).toBe(true);
    expect(hasOfficialSettlementAuthority({ exchange: 'NSEIX', settlement_price_source: 'NSEIX_OFFICIAL_DAILY_SETTLEMENT' })).toBe(false);
  });
});

describe('fetchAndApplyGiftNiftyAtp', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    KiteInstrument.find.mockReturnValue(chain([
      { instrument_token: '9920261027', tradingsymbol: 'GIFTNIFTY26OCTFUT', expiry: new Date('2026-10-27T00:00:00Z') },
      { instrument_token: '9920261123', tradingsymbol: 'GIFTNIFTY26NOVFUT', expiry: new Date('2026-11-23T00:00:00Z') },
    ]));
    KiteInstrument.findOne.mockReturnValue(chain({ instrument_token: '291849' }));
  });

  test('uses each contract\'s ATP from the night session after the price date (Fri 9 Oct -> Sat 02:45)', async () => {
    axios.get.mockResolvedValue({ data: { data: [
      { INSTRUMENTTYPE: 'FUTIDX', SYMBOL: 'NIFTY', EXPIRYDATE: '27-Oct-2026', ATP: 22601.25, TIMESTMP: '10-Oct-2026 02:44:58' },
      { INSTRUMENTTYPE: 'FUTIDX', SYMBOL: 'NIFTY', EXPIRYDATE: '23-Nov-2026', ATP: 22650.5, TIMESTMP: '09-Oct-2026 23:10:00' },
    ] } });
    const r = await fetchAndApplyGiftNiftyAtp('2026-10-09', { applyToLivePrices: false });
    expect(r.applied.map((a) => [a.symbol, a.price])).toEqual([
      ['GIFTNIFTY26OCTFUT', 22601.25], ['GIFTNIFTY26NOVFUT', 22650.5], ['GIFT NIFTY', 22601.25],
    ]);
    const set = KiteInstrument.updateOne.mock.calls[0][1].$set;
    expect(set.settlement_price_source).toBe('NSEIX_ATP_SESSION_CLOSE');
    expect(set.settlement_price_date.toISOString()).toBe('2026-10-09T00:00:00.000Z');
  });

  test('ignores an ATP from before the night session (stale) and throws when nothing valid', async () => {
    axios.get.mockResolvedValue({ data: { data: [
      { INSTRUMENTTYPE: 'FUTIDX', SYMBOL: 'NIFTY', EXPIRYDATE: '27-Oct-2026', ATP: 22500, TIMESTMP: '09-Oct-2026 15:39:00' },
    ] } });
    await expect(fetchAndApplyGiftNiftyAtp('2026-10-09', { applyToLivePrices: false })).rejects.toThrow(/No NSE IX ATP/);
    expect(KiteInstrument.updateOne).not.toHaveBeenCalled();
  });
});
