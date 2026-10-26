'use strict';

// A script under NSE F&O ban can't be rolled over (26 Oct 2026, the user:
// "no rollover allow in ban script") — the reopen is a new position in the
// next month. The position can still be squared off; admin bypasses.

const { _private: { banRolloverRefusal } } = require('../src/services/rolloverService');

const OCT = { name: 'SAIL', tradingsymbol: 'SAIL26OCTFUT', nse_banned: true };
const NOV = { name: 'SAIL', tradingsymbol: 'SAIL26NOVFUT', nse_banned: true };
const client = { isAdmin: false, masterId: null };
const master = { isAdmin: false, masterId: 'm1' };
const admin = { isAdmin: true };

test('banned script: a client is refused, with a clear message', () => {
  expect(banRolloverRefusal(OCT, NOV, client)).toBe('SAIL is under NSE F&O ban — rollover is not allowed. You can square off the position instead.');
});

test('banned script: a master rolling for a client is refused too', () => {
  expect(banRolloverRefusal(OCT, NOV, master)).not.toBeNull();
});

test('either contract flagged is enough (the ban covers every month)', () => {
  expect(banRolloverRefusal(OCT, { ...NOV, nse_banned: false }, client)).not.toBeNull();
  expect(banRolloverRefusal({ ...OCT, nse_banned: false }, NOV, client)).not.toBeNull();
});

test('admin may still roll a banned script', () => {
  expect(banRolloverRefusal(OCT, NOV, admin)).toBeNull();
});

test('script not banned → no refusal', () => {
  expect(banRolloverRefusal({ ...OCT, nse_banned: false }, { ...NOV, nse_banned: false }, client)).toBeNull();
});
