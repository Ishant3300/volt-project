'use strict';

// utils/cmeHours.js — CME Globex (COMEX, GLOBAL index futures) hours in
// Chicago time: Sun–Fri 5:00 PM – 4:00 PM, daily break 4–5 PM. US daylight
// saving ends 1 Nov 2026, so in IST the break moves from 2:30–3:30 AM to
// 3:30–4:30 AM — the apps' fixed 2:00–3:30 AM IST window doesn't.

const { isCmeOpen, cmeNextOpen, cmeClosedMessage } = require('../src/utils/cmeHours');

const ist = (s) => Date.parse(`${s}+05:30`);

test('US summer time (until 31 Oct): break 2:30–3:30 AM IST', () => {
  expect(isCmeOpen(ist('2026-10-29T02:29:00'))).toBe(true);
  expect(isCmeOpen(ist('2026-10-29T02:30:00'))).toBe(false);
  expect(isCmeOpen(ist('2026-10-29T03:29:00'))).toBe(false);
  expect(isCmeOpen(ist('2026-10-29T03:30:00'))).toBe(true);
});

test('US winter time (from 2 Nov): break 3:30–4:30 AM IST — the hour the apps would reopen into', () => {
  expect(isCmeOpen(ist('2026-11-03T03:29:00'))).toBe(true);
  expect(isCmeOpen(ist('2026-11-03T03:30:00'))).toBe(false);
  expect(isCmeOpen(ist('2026-11-03T04:10:00'))).toBe(false);
  expect(isCmeOpen(ist('2026-11-03T04:30:00'))).toBe(true);
});

test('weekend: closed from Friday 4 PM Chicago to Sunday 5 PM Chicago', () => {
  expect(isCmeOpen(ist('2026-10-31T02:29:00'))).toBe(true); // Fri 3:59 PM CDT
  expect(isCmeOpen(ist('2026-10-31T02:30:00'))).toBe(false); // Fri 4:00 PM CDT
  expect(isCmeOpen(ist('2026-11-01T12:00:00'))).toBe(false); // Sunday
  expect(isCmeOpen(ist('2026-11-02T04:29:00'))).toBe(false); // Sun 4:59 PM CST
  expect(isCmeOpen(ist('2026-11-02T04:30:00'))).toBe(true); // Sun 5:00 PM CST
});

test('normal daytime India hours are open', () => {
  expect(isCmeOpen(ist('2026-10-28T18:00:00'))).toBe(true);
  expect(isCmeOpen(ist('2026-11-04T10:00:00'))).toBe(true);
});

test('next open and the message say when it reopens, in IST', () => {
  expect(cmeNextOpen(ist('2026-11-03T03:45:00'))).toBe(ist('2026-11-03T04:30:00'));
  expect(cmeNextOpen(ist('2026-10-31T03:00:00'))).toBe(ist('2026-11-02T04:30:00')); // weekend
  expect(cmeClosedMessage(ist('2026-11-03T03:45:00'))).toMatch(/opens again at Tue,? 4:30 am IST/i);
});
