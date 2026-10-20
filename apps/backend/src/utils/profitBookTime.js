'use strict';

/**
 * Profit book time (User.profit_book_minutes): a client may not close a
 * position IN PROFIT until this many minutes after opening that quantity;
 * closing at a loss is always allowed (utils/freshStoplossHold.js). Set per
 * client when the account is created — it replaced the admin's per-script
 * FreshStoplossLimit.time_minutes (10 on every script) on 20 Oct 2026.
 * 0 = no restriction.
 */

/** Used when an old app sends none, and for accounts created before the field existed. */
const DEFAULT_PROFIT_BOOK_MINUTES = 10;
const MAX_PROFIT_BOOK_MINUTES = 1440; // one day

/**
 * Validate a value from a request. Returns { value } (a whole number of
 * minutes) or { error } with a message for a 400.
 */
function parseProfitBookMinutes(raw) {
  if (raw === null || raw === '' || raw === undefined) return { error: 'Profit book time (minutes) is required' };
  const n = Number(raw);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return { error: 'Profit book time must be a whole number of minutes' };
  if (n < 0 || n > MAX_PROFIT_BOOK_MINUTES) return { error: `Profit book time must be between 0 and ${MAX_PROFIT_BOOK_MINUTES} minutes` };
  return { value: n };
}

/** The minutes that apply to this user now. */
function profitBookMinutesOf(user) {
  const n = Number(user?.profit_book_minutes);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_PROFIT_BOOK_MINUTES;
}

module.exports = { DEFAULT_PROFIT_BOOK_MINUTES, MAX_PROFIT_BOOK_MINUTES, parseProfitBookMinutes, profitBookMinutesOf };
