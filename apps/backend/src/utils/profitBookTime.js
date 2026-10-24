'use strict';

/**
 * Profit book time (User.profit_book_minutes): a client may not close a
 * position IN PROFIT until this many minutes after opening that quantity;
 * closing at a loss is always allowed (utils/freshStoplossHold.js). Set per
 * client when the account is created — it replaced the admin's per-script
 * FreshStoplossLimit.time_minutes (10 on every script) on 20 Oct 2026.
 * 0 = no restriction (only possible while the admin minimum is 0).
 *
 * Admin minimum (24 Oct 2026, PlatformSetting 'profit_book_min_minutes',
 * default 5): a new client starts at it and no client's time may be SET
 * below it. Raising it later doesn't change existing clients — a client
 * below it keeps their time until their profit book time is changed, which
 * must then be at least the minimum (user's decision). The time a trade is
 * checked against is always the client's own value.
 */

const DEFAULT_PROFIT_BOOK_MINUTES = 5;
const MAX_PROFIT_BOOK_MINUTES = 1440; // one day
const MIN_SETTING_KEY = 'profit_book_min_minutes';
const CACHE_MS = 30 * 1000;

let cached = null; // { value, at }

/** The admin minimum (minutes), cached for 30 s; DEFAULT when never set. */
async function getMinProfitBookMinutes() {
  if (cached && Date.now() - cached.at < CACHE_MS) return cached.value;
  const PlatformSetting = require('../models/PlatformSetting');
  const doc = await PlatformSetting.findOne({ key: MIN_SETTING_KEY }).lean();
  const n = Number(doc?.value);
  const value = Number.isInteger(n) && n >= 0 && n <= MAX_PROFIT_BOOK_MINUTES ? n : DEFAULT_PROFIT_BOOK_MINUTES;
  cached = { value, at: Date.now() };
  return value;
}

function clearMinCache() { cached = null; }

/**
 * Validate a value from a request. Returns { value } (a whole number of
 * minutes) or { error } with a message for a 400. With `min`, a value below
 * it is refused — unless it equals `current` (the client's saved value, so
 * saving an unrelated field of a client below a since-raised minimum still
 * works).
 */
function parseProfitBookMinutes(raw, { min, current } = {}) {
  if (raw === null || raw === '' || raw === undefined) return { error: 'Profit book time (minutes) is required' };
  const n = Number(raw);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return { error: 'Profit book time must be a whole number of minutes' };
  if (n < 0 || n > MAX_PROFIT_BOOK_MINUTES) return { error: `Profit book time must be between 0 and ${MAX_PROFIT_BOOK_MINUTES} minutes` };
  if (min != null && n < min && n !== current) return { error: `Profit book time cannot be less than ${min} minutes (admin minimum)` };
  return { value: n };
}

/** The minutes that apply to this user now. */
function profitBookMinutesOf(user) {
  const n = Number(user?.profit_book_minutes);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_PROFIT_BOOK_MINUTES;
}

module.exports = {
  DEFAULT_PROFIT_BOOK_MINUTES,
  MAX_PROFIT_BOOK_MINUTES,
  MIN_SETTING_KEY,
  getMinProfitBookMinutes,
  clearMinCache,
  parseProfitBookMinutes,
  profitBookMinutesOf,
};
