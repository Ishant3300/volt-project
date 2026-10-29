'use strict';

// metricsEngine.onTick batches ticks for at most TICK_BATCH_MS (100 ms) and
// then always processes them. It used to be a debounce — each tick restarted
// a 50 ms timer — so with ticks arriving under 50 ms apart, M2M and the margin
// square-off checks waited for a quiet gap (29 Oct 2026 scale audit).

const metricsEngine = require('../src/services/metricsEngine');

beforeEach(() => {
  jest.useFakeTimers();
  metricsEngine._initialized = true;
  metricsEngine._settledTokens = null;
  metricsEngine._tickTimer = null;
  metricsEngine._pendingTokens.clear();
});
afterEach(() => jest.useRealTimers());

test('a steady stream of ticks 20 ms apart is processed every 100 ms, never postponed', () => {
  const runs = [];
  const spy = jest.spyOn(metricsEngine, '_processPendingTicks').mockImplementation(function () {
    runs.push([...this._pendingTokens]);
    this._pendingTokens.clear();
  });
  for (let i = 0; i < 50; i++) { // 1 second of ticks
    metricsEngine.onTick(100 + (i % 5), 1000 + i, 999, 1001);
    jest.advanceTimersByTime(20);
  }
  spy.mockRestore();
  expect(runs.length).toBeGreaterThanOrEqual(9);
  expect(runs.length).toBeLessThanOrEqual(11);
  expect(runs.every((tokens) => tokens.length > 0)).toBe(true);
});

test('a single tick is processed 100 ms later', () => {
  const spy = jest.spyOn(metricsEngine, '_processPendingTicks').mockImplementation(() => {});
  metricsEngine.onTick(7, 50, 49, 51);
  jest.advanceTimersByTime(99);
  expect(spy).not.toHaveBeenCalled();
  jest.advanceTimersByTime(1);
  expect(spy).toHaveBeenCalledTimes(1);
  expect(metricsEngine._ltpMap.get('7')).toBe(50);
  expect(metricsEngine._bidMap.get('7')).toBe(49);
  spy.mockRestore();
});
