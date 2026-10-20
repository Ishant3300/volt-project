'use strict';

// livePriceService.isExchangeLive: an exchange counts as trading only while
// a Kite full-mode tick on its segment carries a recent exchange timestamp.

const livePriceService = require('../src/services/livePriceService');

const MCX_TOKEN = (123456 << 8) | 7; // Kite: segment = token & 0xFF, MCX = 7
const NFO_TOKEN = (654321 << 8) | 2; // NFO = 2

function fullPacket(token, exchangeEpochSeconds) {
  const b = Buffer.alloc(184);
  b.writeInt32BE(token, 0);
  b.writeInt32BE(910000, 4); // ltp 9100.00
  b.writeInt32BE(exchangeEpochSeconds, 60);
  return b;
}

beforeEach(() => { livePriceService._exchangeTickAt = new Map(); });
afterAll(() => { jest.restoreAllMocks(); });

test('unknown segment counts as live (never blocks on a feed change)', () => {
  expect(livePriceService.isExchangeLive(MCX_TOKEN)).toBe(true);
});

test('a snapshot with an old exchange time (closed session) is not live', () => {
  jest.spyOn(console, 'log').mockImplementation(() => {});
  const now = Date.now();
  livePriceService._parseTick(fullPacket(MCX_TOKEN, Math.floor((now - 18 * 3600_000) / 1000)));
  expect(livePriceService.isExchangeLive(MCX_TOKEN, now)).toBe(false);
  // Another segment is unaffected.
  expect(livePriceService.isExchangeLive(NFO_TOKEN, now)).toBe(true);
});

test('a fresh exchange time makes it live; it lapses after 3 minutes', () => {
  jest.spyOn(console, 'log').mockImplementation(() => {});
  const now = Date.now();
  livePriceService._parseTick(fullPacket(MCX_TOKEN, Math.floor((now - 18 * 3600_000) / 1000)));
  livePriceService._parseTick(fullPacket(MCX_TOKEN, Math.floor(now / 1000)));
  expect(livePriceService.isExchangeLive(MCX_TOKEN, now)).toBe(true);
  expect(livePriceService.isExchangeLive(String(MCX_TOKEN), now + 2 * 60_000)).toBe(true);
  expect(livePriceService.isExchangeLive(MCX_TOKEN, now + 4 * 60_000)).toBe(false);
  // An older snapshot arriving later never moves the time back.
  livePriceService._parseTick(fullPacket(MCX_TOKEN, Math.floor((now - 3600_000) / 1000)));
  expect(livePriceService.isExchangeLive(MCX_TOKEN, now)).toBe(true);
});

test('a holiday snapshot with exchange time 0 is not live, until a real tick', () => {
  jest.spyOn(console, 'log').mockImplementation(() => {});
  const now = Date.now();
  livePriceService._parseTick(fullPacket(NFO_TOKEN, 0));
  expect(livePriceService.isExchangeLive(NFO_TOKEN, now)).toBe(false);
  livePriceService._parseTick(fullPacket(NFO_TOKEN, Math.floor(now / 1000)));
  expect(livePriceService.isExchangeLive(NFO_TOKEN, now)).toBe(true);
  // A later 0 snapshot doesn't undo a real tick.
  livePriceService._parseTick(fullPacket(NFO_TOKEN, 0));
  expect(livePriceService.isExchangeLive(NFO_TOKEN, now)).toBe(true);
});
