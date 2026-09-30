'use strict';

const { isNfoMarketOnlyWindow } = require('../src/utils/nfoMarketOnlyWindow');

const ist = (hhmm) => new Date(`2026-10-01T${hhmm}:00+05:30`);

describe('NFO market-only window (3:20-3:40 PM IST)', () => {
  test('inside the window for NFO-FUT / NFO-OPT', () => {
    expect(isNfoMarketOnlyWindow('NFO-FUT', ist('15:20'))).toBe(true);
    expect(isNfoMarketOnlyWindow('NFO-OPT', ist('15:30'))).toBe(true);
    expect(isNfoMarketOnlyWindow('nfo-opt', ist('15:39'))).toBe(true);
  });

  test('outside the window', () => {
    expect(isNfoMarketOnlyWindow('NFO-FUT', ist('15:19'))).toBe(false);
    expect(isNfoMarketOnlyWindow('NFO-FUT', ist('15:40'))).toBe(false);
    expect(isNfoMarketOnlyWindow('NFO-OPT', ist('09:30'))).toBe(false);
  });

  test('other segments never restricted', () => {
    for (const seg of ['MCX-FUT', 'MCX-OPT', 'COMEX-FUT', 'INDICES', 'GLOBAL', '', null]) {
      expect(isNfoMarketOnlyWindow(seg, ist('15:25'))).toBe(false);
    }
  });
});
