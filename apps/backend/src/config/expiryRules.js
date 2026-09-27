'use strict';

/**
 * Contract-expiry rules — when the NEXT contract opens for trading and when
 * every open position in the CURRENT contract is cut (closed at the closing
 * bid/ask), counted in working days of that product's exchange calendar.
 *
 * Agreed with the business owner (2026-09-27):
 *   Base metals     open 6 working days before expiry, cut 5 before
 *   Precious metals open 6, cut 5
 *   Crude           open 2, cut 1
 *   Natural gas     open 1, cut 1 (same day)
 *   NSE futures     open on the Monday of expiry week, cut on expiry day
 *   GIFT NIFTY      cut on expiry day (a single continuous instrument here —
 *                   the live feed rolls it itself, so there is nothing to open)
 *   GLOBAL futures  open and cut on expiry day
 *   COMEX           same counts as the MCX counterpart
 * Opens run automatically; every cut needs an admin confirmation and then
 * runs just after that market's close (this platform's own close times —
 * see apps/flutter/lib/utils/market_hours.dart and cronService.js).
 *
 * `names` match KiteInstrument.name case-insensitively; `null` = every
 * future in the segments. `calendar` 'MCX'/'NSE' = that exchange's trading
 * holidays (marketCalendarService); 'WEEKDAYS' = Mon–Fri only.
 */

/** Actions dated before this are never created — the rules apply from the next contracts on. */
const EFFECTIVE_FROM = '2026-10-01';

/**
 * Contracts loaded from the feed after this instant start CLOSED until
 * their scheduled open day (new rows default to enabled). Contracts that
 * already existed are left exactly as admins set them.
 */
const NEW_CONTRACTS_CLOSED_FROM = new Date('2026-09-27T18:30:00.000Z'); // 28 Sep 2026 00:00 IST

/** Local (IST) time opens are applied — before MCX 9:00 AM / NSE 9:15 AM. */
const OPEN_TIME = '08:00';

const before = (days) => ({ type: 'WORKING_DAYS_BEFORE', days });

const GROUPS = [
  {
    key: 'MCX_BASE', label: 'Base metals', exchangeLabel: 'MCX', segments: ['MCX-FUT'],
    names: ['ALUMINI', 'ALUMINIUM', 'COPPER', 'LEAD', 'LEADMINI', 'ZINC', 'ZINCMINI'],
    calendar: 'MCX', open: before(6), cut: before(5), closeTime: '23:30',
  },
  {
    key: 'MCX_PRECIOUS', label: 'Precious metals', exchangeLabel: 'MCX', segments: ['MCX-FUT'],
    names: ['GOLD', 'GOLDM', 'GOLDTEN', 'GOLDGUINEA', 'GOLDPETAL', 'SILVER', 'SILVERM', 'SILVERMIC'],
    calendar: 'MCX', open: before(6), cut: before(5), closeTime: '23:30',
  },
  {
    key: 'MCX_CRUDE', label: 'Crude oil', exchangeLabel: 'MCX', segments: ['MCX-FUT'],
    names: ['CRUDEOIL', 'CRUDEOILM'],
    calendar: 'MCX', open: before(2), cut: before(1), closeTime: '23:30',
  },
  {
    key: 'MCX_NG', label: 'Natural gas', exchangeLabel: 'MCX', segments: ['MCX-FUT'],
    names: ['NATURALGAS', 'NATGASMINI'],
    calendar: 'MCX', open: before(1), cut: before(1), closeTime: '23:30',
  },
  {
    key: 'COMEX_BASE', label: 'COMEX base metals', exchangeLabel: 'COMEX', segments: ['COMEX-FUT'],
    names: ['COPPER'],
    calendar: 'WEEKDAYS', open: before(6), cut: before(5), closeTime: '23:30',
  },
  {
    key: 'COMEX_PRECIOUS', label: 'COMEX precious metals', exchangeLabel: 'COMEX', segments: ['COMEX-FUT'],
    names: ['GOLD', 'SILVER'],
    calendar: 'WEEKDAYS', open: before(6), cut: before(5), closeTime: '23:30',
  },
  {
    key: 'COMEX_NG', label: 'COMEX natural gas', exchangeLabel: 'COMEX', segments: ['COMEX-FUT'],
    names: ['NATURALGAS'],
    calendar: 'WEEKDAYS', open: before(1), cut: before(1), closeTime: '23:30',
  },
  {
    key: 'NSE_FUT', label: 'NSE futures', exchangeLabel: 'NSE', segments: ['NFO-FUT'],
    names: null,
    calendar: 'NSE', open: { type: 'EXPIRY_WEEK_MONDAY' }, cut: before(0), closeTime: '15:40',
  },
  {
    key: 'GIFT_NIFTY', label: 'GIFT NIFTY', exchangeLabel: 'GIFT NIFTY', segments: ['INDICES'],
    tradingsymbols: ['GIFT NIFTY'], continuous: true,
    calendar: 'NSE', open: null, cut: before(0), closeTime: '15:40',
  },
  {
    key: 'GLOBAL_FUT', label: 'GLOBAL futures', exchangeLabel: 'GLOBAL', segments: ['GLOBAL'],
    names: null,
    calendar: 'WEEKDAYS', open: before(0), cut: before(0), closeTime: '23:30',
  },
];

module.exports = { EFFECTIVE_FROM, NEW_CONTRACTS_CLOSED_FROM, OPEN_TIME, GROUPS };
