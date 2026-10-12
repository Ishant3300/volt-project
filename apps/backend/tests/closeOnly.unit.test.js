'use strict';

// Close-only = reduce only (real case: client 261897 JB012 long 750 ANGELONE —
// a SELL 1500 used to pass as "closing" and open a fresh short of 750).
const { closeOnlyRejection, CLOSE_ONLY_MESSAGE } = require('../src/utils/closeOnly');

const check = (currentNetQty, transactionType, quantity, pendingSameSide = 0) =>
  closeOnlyRejection({ currentNetQty, transactionType, quantity, pendingSameSide });

test('no position: any order is refused (new script, any exchange)', () => {
  expect(check(0, 'BUY', 1)).toBe(CLOSE_ONLY_MESSAGE);
  expect(check(0, 'SELL', 1)).toBe(CLOSE_ONLY_MESSAGE);
});

test('adding to a position is refused', () => {
  expect(check(750, 'BUY', 1)).toBe(CLOSE_ONLY_MESSAGE);
  expect(check(-750, 'SELL', 1)).toBe(CLOSE_ONLY_MESSAGE);
});

test('reducing or fully closing is allowed', () => {
  expect(check(750, 'SELL', 250)).toBeNull();
  expect(check(750, 'SELL', 750)).toBeNull();
  expect(check(-130, 'BUY', 130)).toBeNull();
});

test('oversized close that would flip the position is refused (JB012 replay)', () => {
  expect(check(750, 'SELL', 1500)).toContain('At most 750 qty can be sold here');
  expect(check(-130, 'BUY', 260)).toContain('At most 130 qty can be bought here');
});

test('pending same-side orders count: two sells cannot add up past the position', () => {
  expect(check(750, 'SELL', 750, 750)).toContain('At most 0 qty can be sold here (750 already in pending orders)');
  expect(check(750, 'SELL', 250, 500)).toBeNull();
  expect(check(750, 'SELL', 300, 500)).toContain('At most 250');
});
