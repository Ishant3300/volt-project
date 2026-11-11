'use strict';

const { isFoPreOpenTick, isFoToken, isPreOpenTime } = require('../src/utils/nsePreOpen');

// IST wall-clock -> instant
const ist = (ymd, hhmmss) => new Date(`${ymd}T${hhmmss}+05:30`);

const ANGELONE_FUT = 15740162; // NFO (low byte 2) — the 11 Nov 2026 case
const HDFCBANK_FUT = 15764994; // NFO
const SENSEX_OPT = 0x123405; // a BFO token (low byte 5)
const NIFTY_INDEX = 256265; // NSE indices segment (9)
const MCX_FUT = 0x123407; // MCX (7)
const GIFT = 9920261123; // NSE IX synthetic token, > 32 bits
const MASSIVE = 9000100202612; // CME synthetic token

describe('nsePreOpen', () => {
  test('NFO / BFO tokens only, real 32-bit Kite tokens', () => {
    expect(isFoToken(ANGELONE_FUT)).toBe(true);
    expect(isFoToken(String(HDFCBANK_FUT))).toBe(true);
    expect(isFoToken(SENSEX_OPT)).toBe(true);
    expect(isFoToken(NIFTY_INDEX)).toBe(false);
    expect(isFoToken(MCX_FUT)).toBe(false);
    expect(isFoToken(GIFT)).toBe(false);
    expect(isFoToken(MASSIVE)).toBe(false);
    expect(isFoToken('abc')).toBe(false);
  });

  test('9:00–9:15 IST is the pre-open; 9:15:00 is the open', () => {
    expect(isPreOpenTime(ist('2026-11-11', '08:59:59'))).toBe(false);
    expect(isPreOpenTime(ist('2026-11-11', '09:00:00'))).toBe(true);
    expect(isPreOpenTime(ist('2026-11-11', '09:14:59'))).toBe(true);
    expect(isPreOpenTime(ist('2026-11-11', '09:15:00'))).toBe(false);
    expect(isPreOpenTime(ist('2026-11-11', '15:20:00'))).toBe(false);
  });

  test('the 11 Nov 2026 tick (ANGELONE fut at 09:00:00) is dropped; the same script at 9:15 is not', () => {
    expect(isFoPreOpenTick(ANGELONE_FUT, ist('2026-11-11', '09:00:00'))).toBe(true);
    expect(isFoPreOpenTick(ANGELONE_FUT, ist('2026-11-11', '09:15:01'))).toBe(false);
  });

  test('MCX, indices, GIFT and CME are never touched, even inside 9:00–9:15', () => {
    const t = ist('2026-11-11', '09:05:00');
    for (const tok of [MCX_FUT, NIFTY_INDEX, GIFT, MASSIVE]) expect(isFoPreOpenTick(tok, t)).toBe(false);
  });

  test('Muhurat 8 Nov 2026 (NSE window opens 14:20): 14:05–14:20 is the pre-open', () => {
    expect(isFoPreOpenTick(ANGELONE_FUT, ist('2026-11-08', '14:04:59'))).toBe(false);
    expect(isFoPreOpenTick(ANGELONE_FUT, ist('2026-11-08', '14:05:00'))).toBe(true);
    expect(isFoPreOpenTick(ANGELONE_FUT, ist('2026-11-08', '14:19:59'))).toBe(true);
    expect(isFoPreOpenTick(ANGELONE_FUT, ist('2026-11-08', '14:20:00'))).toBe(false);
  });
});
