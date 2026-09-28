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
 *   GIFT NIFTY      monthly contracts, like NSE futures: next month opens on the
 *                   Monday of expiry week; cut when NSE IX stops it (3:30 PM)
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
    // Monthly contracts GIFTNIFTY26OCTFUT… (giftNiftyContracts.js), same
    // timing as NSE futures: next month opens on the Monday of expiry week.
    key: 'GIFT_NIFTY', label: 'GIFT NIFTY', exchangeLabel: 'GIFT NIFTY', segments: ['INDICES'],
    names: ['GIFT NIFTY'],
    // NSE IX stops the expiring contract at 15:30 IST (circular 2129) — the
    // cut runs at 15:31, same moment as the automatic GIFT expiry close in
    // cronService.js. The feed holds its quotes until 16:00.
    calendar: 'NSE', open: { type: 'EXPIRY_WEEK_MONDAY' }, cut: before(0), closeTime: '15:30',
  },
  {
    // NFO options — every underlying (NIFTY weekly, other index/stock
    // monthly): only the current expiry is open; the next one opens 1
    // working day before the current expires. Nothing further out is open —
    // enforced (reconcile), incl. strikes the daily Kite sync adds later.
    // No scheduled cut: open positions close on expiry day at 3:46 PM
    // (cronService expiry close), as before.
    key: 'NFO_OPT', label: 'NFO options', exchangeLabel: 'NSE', segments: ['NFO-OPT'],
    names: null, instrumentTypes: ['CE', 'PE'], reconcile: true,
    effectiveFrom: '2026-09-28', // takes effect at once (the 29 Sep → next expiry open is due today)
    calendar: 'NSE', open: before(1), cut: null, closeTime: '15:40',
  },
  {
    key: 'GLOBAL_FUT', label: 'GLOBAL futures', exchangeLabel: 'GLOBAL', segments: ['GLOBAL'],
    names: null,
    calendar: 'WEEKDAYS', open: before(0), cut: before(0), closeTime: '23:30',
  },
];

module.exports = { EFFECTIVE_FROM, NEW_CONTRACTS_CLOSED_FROM, OPEN_TIME, GROUPS };
