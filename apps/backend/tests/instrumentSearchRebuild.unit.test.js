// Search list rebuild after an expiry is opened/closed: searches keep being
// answered from the current list meanwhile, and a slower, older rebuild can
// never overwrite a newer one.

jest.mock('../src/models/KiteInstrument', () => ({ find: jest.fn() }));
const KiteInstrument = require('../src/models/KiteInstrument');
const search = require('../src/services/instrumentSearchService');

const fut = (token, symbol, expiry) => ({
  instrument_token: token, tradingsymbol: symbol, name: 'NIFTY', raw_name: 'NIFTY', segment: 'NFO-FUT', exchange: 'NFO',
  instrument_type: 'FUT', expiry: new Date(expiry), strike: 0, lot_size: 65,
});
const SEP = fut('1', 'NIFTY26SEPFUT', '2026-10-06');
const OCT = fut('2', 'NIFTY26OCTFUT', '2026-11-03');

function respondWith(rows, delayMs) {
  return { lean: () => new Promise((resolve) => setTimeout(() => resolve(rows), delayMs)) };
}
const symbols = async () => (await search.smartSearch('NIFTY', 'ALL', 50)).groups
  .flatMap((g) => (g.items || g.instruments || g.results || []).map((i) => i.tradingsymbol));

describe('search list rebuild', () => {
  beforeEach(async () => {
    search.clearCache();
    KiteInstrument.find.mockReturnValueOnce(respondWith([SEP], 0));
    await search.loadInstrumentCache();
  });

  test('searches keep working while a rebuild runs, and see the new contract once it lands', async () => {
    KiteInstrument.find.mockReturnValueOnce(respondWith([SEP, OCT], 50));
    search.invalidateCache();
    const during = await search.smartSearch('NIFTY', 'ALL', 50);
    expect(during.total).toBeGreaterThan(0); // not the empty "loading" answer
    await new Promise((r) => setTimeout(r, 120));
    expect((await search.smartSearch('NIFTY', 'ALL', 50)).total).toBe(2);
  });

  test('an older, slower rebuild cannot overwrite a newer one', async () => {
    KiteInstrument.find
      .mockReturnValueOnce(respondWith([SEP], 150)) // started first, finishes last (stale)
      .mockReturnValueOnce(respondWith([SEP, OCT], 20)); // started second, has the new contract
    search.invalidateCache();
    search.invalidateCache();
    await new Promise((r) => setTimeout(r, 250));
    expect((await search.smartSearch('NIFTY', 'ALL', 50)).total).toBe(2);
  });
});
