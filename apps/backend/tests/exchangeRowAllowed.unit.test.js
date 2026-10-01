'use strict';

// A client's exchanges_allowed row grants the exchange only when ticked
// (turnover or lot on). Live case: KB RAKESH had an NFO-OPT row with both
// off (saved by the web create form) and could still buy an option.
const { isUserExchangeRowAllowed } = require('../src/utils/exchangeAccess');

test('ticked rows grant the exchange', () => {
  expect(isUserExchangeRowAllowed({ exchange_name: 'NFO-FUT', turnover: true, lot: false })).toBe(true);
  expect(isUserExchangeRowAllowed({ exchange_name: 'NFO-OPT', turnover: false, lot: true })).toBe(true);
});

test('a saved row with both off does NOT grant it', () => {
  expect(isUserExchangeRowAllowed({ exchange_name: 'NFO-OPT', turnover: false, lot: false })).toBe(false);
  expect(isUserExchangeRowAllowed({ exchange_name: 'MCX-FUT' })).toBe(false);
  expect(isUserExchangeRowAllowed(null)).toBe(false);
});
