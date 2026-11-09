'use strict';

/**
 * Minimum NSE FUT script price, per client (User.min_nse_fut_price, 26 Oct
 * 2026): an NSE future whose last official close is below the client's
 * minimum can't be opened or added to — closing or reducing a position is
 * always allowed. Since 9 Nov 2026 (owner) such scripts stay visible: watchlist
 * (add, list), search and browse show them; only orders are limited.
 * (minPriceForReq / minPriceMongoFilter / dropBelowMinPrice are kept for a
 * listing filter but no longer used by the listings.)
 * NFO-FUT only; every other segment is untouched. 0 = off (everyone's
 * default). Admin bypasses, like every other account rule.
 *
 * The price is the contract's last official close (settlement_price — the
 * NSE bhavcopy settle price, refreshed 17:30 IST every trading day), so it
 * stays the same all day: a script trading around the limit doesn't flicker
 * in and out. The stored last_price is not used — it isn't kept current for
 * NSE futures. A contract with no close yet counts as allowed.
 */

const SEGMENT = 'NFO-FUT';
const MAX_MIN_PRICE = 1_000_000;

/** The client's minimum (0 = off). */
function minNseFutPriceOf(user) {
  const n = Number(user?.min_nse_fut_price);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

/** The contract's last official close, or 0 when unknown. */
function referencePrice(instrument) {
  const settle = Number(instrument?.settlement_price);
  return settle > 0 ? settle : 0;
}

/** True when this NSE future is below the client's minimum. */
function isBelowMinPrice(minPrice, instrument) {
  if (!(minPrice > 0) || !instrument) return false;
  if (String(instrument.segment || '').toUpperCase() !== SEGMENT) return false;
  const price = referencePrice(instrument);
  return price > 0 && price < minPrice;
}

function belowMinMessage(minPrice) {
  return `NSE FUT scripts priced below ${minPrice} are not allowed for your account.`;
}

/**
 * The caller's minimum for listing filters: a client's own value; admin and
 * master see everything (0).
 */
async function minPriceForReq(req) {
  if (!req?.user?.id || req.admin || req.master) return 0;
  const User = require('../models/User');
  const doc = await User.findById(req.user.id).select('min_nse_fut_price').lean();
  return minNseFutPriceOf(doc);
}

/**
 * Mongo condition for an instrument query that keeps only NSE futures at or
 * above the minimum (and everything that isn't an NSE future). Null when off.
 */
function minPriceMongoFilter(minPrice) {
  if (!(minPrice > 0)) return null;
  // Same rule as isBelowMinPrice: no close yet (0 / missing) counts as allowed.
  return {
    $or: [
      { segment: { $ne: SEGMENT } },
      { settlement_price: { $gte: minPrice } },
      { settlement_price: { $not: { $gt: 0 } } },
    ],
  };
}

/**
 * Drop NSE futures below the minimum from a list of search results. Results
 * from the search cache carry no close (and the cache can be a day old), so
 * the current close is read for just the NSE futures in the list.
 */
async function dropBelowMinPrice(items, minPrice) {
  if (!(minPrice > 0) || !Array.isArray(items) || items.length === 0) return items;
  const futTokens = [...new Set(items
    .filter((i) => String(i?.segment || '').toUpperCase() === SEGMENT)
    .map((i) => String(i.instrument_token)))];
  if (futTokens.length === 0) return items;
  const KiteInstrument = require('../models/KiteInstrument');
  const rows = await KiteInstrument.find({ instrument_token: { $in: [...futTokens, ...futTokens.map(Number).filter(Number.isFinite)] } })
    .select('instrument_token segment settlement_price').lean();
  const below = new Set(rows.filter((r) => isBelowMinPrice(minPrice, r)).map((r) => String(r.instrument_token)));
  return below.size === 0 ? items : items.filter((i) => !below.has(String(i.instrument_token)));
}

/** Validate a value from a request: { value } or { error }. */
function parseMinNseFutPrice(raw) {
  if (raw === null || raw === '' || raw === undefined) return { value: 0 };
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0 || n > MAX_MIN_PRICE) return { error: `Min NSE FUT price must be between 0 and ${MAX_MIN_PRICE}` };
  return { value: Math.round(n * 100) / 100 };
}

module.exports = {
  SEGMENT,
  minNseFutPriceOf,
  referencePrice,
  isBelowMinPrice,
  belowMinMessage,
  minPriceForReq,
  minPriceMongoFilter,
  dropBelowMinPrice,
  parseMinNseFutPrice,
};
