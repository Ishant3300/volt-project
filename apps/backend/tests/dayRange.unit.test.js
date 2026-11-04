'use strict';

// Bad quotes outside the day's high–low (utils/dayRange.js, 4 Nov 2026: GIFT 2375.2).
const dayRange = require('../src/utils/dayRange');

const NOW = new Date('2026-11-04T06:52:09Z');
beforeEach(() => dayRange._reset());

test('the 4 Nov GIFT case: 2375.2 with the day low unchanged is ignored', () => {
  expect(dayRange.acceptTick('G', 23739.5, 23673.5, 23971.5, NOW)).toBe(true);
  expect(dayRange.acceptTick('G', 2375.2, 23673.5, 23971.5, NOW)).toBe(false); // contradicts its own low
  expect(dayRange.acceptTick('G', 2375.2, null, null, NOW)).toBe(false); // no low/high at all: still outside the known range
  expect(dayRange.inRange('G', 2375.2, NOW)).toBe(false);
  expect(dayRange.inRange('G', 23700, NOW)).toBe(true);
});

test('a real new low (the tick moved its own low) is accepted and widens the range', () => {
  dayRange.acceptTick('N', 100, 98, 105, NOW);
  expect(dayRange.acceptTick('N', 96, 96, 105, NOW)).toBe(true);
  expect(dayRange.rangeOf('N', NOW)).toEqual({ low: 96, high: 105 });
  expect(dayRange.inRange('N', 96.5, NOW)).toBe(true);
});

test('no range known yet: everything passes; first tick sets the range', () => {
  expect(dayRange.inRange('X', 5, NOW)).toBe(true);
  expect(dayRange.acceptTick('X', 50, 0, 0, NOW)).toBe(true); // no low/high: accepted, nothing recorded
  expect(dayRange.rangeOf('X', NOW)).toBeNull();
});

test('market strict: ask above the day high / bid below the low is outside; rounding room allowed', () => {
  dayRange.acceptTick('O', 10, 10, 10, NOW); // an option traded once at 10
  expect(dayRange.inRange('O', 11, NOW)).toBe(false); // ask 11
  expect(dayRange.inRange('O', 10.05, NOW)).toBe(true); // one tick
  dayRange.acceptTick('F', 23800, 23700, 23800, NOW);
  expect(dayRange.inRange('F', 23810, NOW)).toBe(true); // within 0.05%
  expect(dayRange.inRange('F', 23830, NOW)).toBe(false);
});

test('a new day starts fresh', () => {
  dayRange.acceptTick('D', 100, 99, 101, NOW);
  const next = new Date('2026-11-05T04:00:00Z');
  expect(dayRange.inRange('D', 150, next)).toBe(true);
  expect(dayRange.acceptTick('D', 150, 149, 151, next)).toBe(true);
});
