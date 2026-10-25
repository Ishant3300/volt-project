'use strict';

// Rollover admission gate (services/rolloverService.js): with the default
// settings a request beyond MAX_ACTIVE waits for a free slot and then runs —
// it is never answered "busy" (user's decision, 25 Oct 2026).

const { _private: { gate, enterGate, leaveGate, MAX_ACTIVE, MAX_WAIT_MS } } = require('../src/services/rolloverService');

test('default: no wait limit', () => {
  expect(MAX_WAIT_MS).toBe(0);
  expect(MAX_ACTIVE).toBe(16);
});

test('a full gate makes requests wait, in order, and each one runs once a slot frees', async () => {
  gate.active = 0; gate.waiting.length = 0;
  for (let i = 0; i < MAX_ACTIVE; i++) await enterGate();
  const started = [];
  const waiters = [1, 2, 3].map((n) => enterGate().then(() => started.push(n)));
  await new Promise((r) => setTimeout(r, 50));
  expect(started).toEqual([]);           // all full: waiting, not refused
  expect(gate.waiting).toHaveLength(3);
  leaveGate(); leaveGate(); leaveGate();  // three running requests finish
  await Promise.all(waiters);
  expect(started).toEqual([1, 2, 3]);    // first come, first served
  expect(gate.active).toBe(MAX_ACTIVE);  // slots were handed over
  for (let i = 0; i < MAX_ACTIVE; i++) leaveGate();
  expect(gate.active).toBe(0);
});

test('a long wait is still not refused', async () => {
  jest.useFakeTimers();
  gate.active = MAX_ACTIVE; gate.waiting.length = 0;
  let done = false;
  const p = enterGate().then(() => { done = true; });
  jest.advanceTimersByTime(10 * 60 * 1000); // ten minutes
  await Promise.resolve();
  expect(done).toBe(false);
  expect(gate.waiting).toHaveLength(1);
  leaveGate();
  await p;
  expect(done).toBe(true);
  jest.useRealTimers();
  gate.active = 0;
});
