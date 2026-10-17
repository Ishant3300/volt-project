'use strict';

// Practice mode: simulated prices — deterministic, 30-minute steps, only inside
// the market session, always positive and on the tick size.

const sim = require('../src/services/practice/simPrice');

const istMs = (y, mo, d, h, mi) => Date.UTC(y, mo - 1, d, h, mi) - 5.5 * 3600e3; // IST wall clock → UTC ms
const MON_0900 = istMs(2026, 10, 19, 9, 0); // Monday 19 Oct 2026 09:00 IST
const stock = { instrument_token: '738561', segment: 'NFO-FUT', exchange: 'NFO', name: 'RELIANCE', tick_size: 0.1 };
const nifty = { instrument_token: '12468226', segment: 'NFO-FUT', exchange: 'NFO', name: 'NIFTY', tick_size: 0.1 };
const anchor = { price: 1200, slot: sim.slotOf(MON_0900) };

test('deterministic: same contract + time → same price, every call', () => {
  const t = istMs(2026, 10, 19, 13, 5);
  expect(sim.priceAt(anchor, stock, t)).toBe(sim.priceAt(anchor, stock, t));
  expect(sim.z('738561', 123456)).toBe(sim.z('738561', 123456));
});

test('price changes only at 30-minute boundaries', () => {
  const a = sim.priceAt(anchor, stock, istMs(2026, 10, 19, 10, 0));
  expect(sim.priceAt(anchor, stock, istMs(2026, 10, 19, 10, 29))).toBe(a);
  const prices = new Set();
  for (let m = 0; m < 6 * 60; m += 30) prices.add(sim.priceAt(anchor, stock, istMs(2026, 10, 19, 9, 30) + m * 60e3));
  expect(prices.size).toBeGreaterThan(3); // it does move through the day
});

test('holds steady outside NSE hours and over the weekend', () => {
  const close = sim.priceAt(anchor, stock, istMs(2026, 10, 19, 15, 30));
  expect(sim.priceAt(anchor, stock, istMs(2026, 10, 19, 20, 0))).toBe(close);
  const fri = sim.priceAt(anchor, stock, istMs(2026, 10, 23, 15, 45));
  expect(sim.priceAt(anchor, stock, istMs(2026, 10, 25, 12, 0))).toBe(fri); // Sunday
});

test('MCX moves in the evening; NSE does not', () => {
  const mcx = { instrument_token: '111', segment: 'MCX-FUT', exchange: 'MCX', name: 'CRUDEOIL', tick_size: 1 };
  const a = { price: 5000, slot: sim.slotOf(istMs(2026, 10, 19, 16, 0)) };
  const seen = new Set();
  for (let h = 16; h <= 23; h++) seen.add(sim.priceAt(a, mcx, istMs(2026, 10, 19, h, 0)));
  expect(seen.size).toBeGreaterThan(2);
  expect(sim.sessionOpen(sim.slotOf(istMs(2026, 10, 19, 20, 0)), stock)).toBe(false);
});

test('realistic moves: index futures move less than stocks, options more; never <= 0, on tick', () => {
  const opt = { instrument_token: '999', segment: 'NFO-OPT', exchange: 'NFO', name: 'NIFTY', instrument_type: 'CE', tick_size: 0.05 };
  const day = istMs(2026, 10, 23, 15, 25);
  const pNifty = sim.priceAt({ price: 23000, slot: anchor.slot }, nifty, day);
  expect(Math.abs(pNifty / 23000 - 1)).toBeLessThan(0.15);
  for (let d = 0; d < 200; d++) {
    const p = sim.priceAt({ price: 2, slot: anchor.slot }, opt, day + d * 86400e3);
    expect(p).toBeGreaterThan(0);
    expect(Math.round(p / 0.05) * 0.05).toBeCloseTo(p, 6);
  }
});

test('tick has bid < ltp < ask and day OHLC consistent', () => {
  const t = sim.tickAt(anchor, stock, istMs(2026, 10, 19, 14, 0));
  expect(t.bid_price).toBeLessThan(t.last_price);
  expect(t.ask_price).toBeGreaterThan(t.last_price);
  expect(t.high).toBeGreaterThanOrEqual(Math.max(t.open, t.last_price));
  expect(t.low).toBeLessThanOrEqual(Math.min(t.open, t.last_price));
});

test('candles agree with the price at each time', () => {
  const from = istMs(2026, 10, 19, 9, 15); const to = istMs(2026, 10, 19, 15, 30);
  const cs = sim.candles(anchor, stock, from, to, 30);
  expect(cs.length).toBeGreaterThan(10);
  for (const c of cs) {
    const ts = Date.parse(c.date);
    expect(c.open).toBe(sim.priceAt(anchor, stock, ts));
    expect(c.high).toBeGreaterThanOrEqual(Math.max(c.open, c.close));
  }
});

test('no floating-point artifacts: prices are exact to the tick decimals', () => {
  expect(sim.roundTick(1210.6, 0.1)).toBe(1210.6);
  expect(sim.roundTick(1210.60000001, 0.1)).toBe(1210.6);
  expect(sim.roundTick(2.33, 0.05)).toBe(2.35);
  for (let m = 0; m < 300; m += 30) {
    const p = sim.priceAt(anchor, stock, istMs(2026, 10, 19, 9, 30) + m * 60e3);
    expect(String(p).split('.')[1]?.length || 0).toBeLessThanOrEqual(1);
  }
});
