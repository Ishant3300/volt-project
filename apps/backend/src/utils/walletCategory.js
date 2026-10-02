'use strict';

/**
 * Wallet category helpers.
 *
 * Every user/master trade wallet is split into five category pools: NSE,
 * NSEOPT, MCX, COMEX and GLOBAL. A trade's segment — and an account's allowed
 * exchanges — map into exactly one of these categories via a fixed rule:
 *
 *   NFO-FUT           -> NSE
 *   NFO-OPT           -> NSEOPT  ("NSE OPT": NSE options have their own pool —
 *                                 option margin is blocked/released only here,
 *                                 never from the NSE futures pool. SENSEX/BSE
 *                                 options are stored with segment NFO-OPT too,
 *                                 see utils/platformSegment.js.)
 *   MCX-FUT, MCX-OPT  -> MCX
 *   COMEX-FUT         -> COMEX  (GC/SI/HG — no COMEX options; kept separate
 *                                 from GLOBAL by design, not lumped in with
 *                                 the CME index-futures set below)
 *   everything else   -> GLOBAL   (SGX, INDICES, GLOBAL, BFO-FUT, BFO-OPT,
 *                                  NSE, NFO, CME-FUT, OTHERS, ...)
 *
 * This is the single source of truth for the mapping, mirrored in the Flutter
 * client (utils/wallet_category.dart) and the web portal
 * (src/lib/exchangeAllow.ts) for display and funding forms.
 *
 * NOTE: nothing stores which pool paid for an open position — releases
 * re-derive the category from the instrument's segment at close time. Any
 * change to this mapping must therefore move the margin of positions already
 * open from the old pool to the new one (scripts/migrateNseOptWallet.js did
 * this for NFO-OPT: NSE -> NSEOPT).
 */

const CATEGORY = Object.freeze({ NSE: 'NSE', NSEOPT: 'NSEOPT', MCX: 'MCX', COMEX: 'COMEX', GLOBAL: 'GLOBAL' });

// Canonical order used when returning a distinct set of categories, so callers
// (and tests) get a deterministic result regardless of input ordering.
const CATEGORY_ORDER = Object.freeze([CATEGORY.NSE, CATEGORY.NSEOPT, CATEGORY.MCX, CATEGORY.COMEX, CATEGORY.GLOBAL]);

/** Display label for a category key ("NSE OPT" for NSEOPT). */
const CATEGORY_LABEL = Object.freeze({
  NSE: 'NSE', NSEOPT: 'NSE OPT', MCX: 'MCX', COMEX: 'COMEX', GLOBAL: 'GLOBAL',
});

/**
 * Map a segment / exchange name to its wallet category.
 * Case-insensitive; anything unrecognised falls back to GLOBAL.
 *
 * @param {string} [segment] - e.g. 'NFO-FUT', 'NFO-OPT', 'MCX-OPT', 'SGX', 'COMEX-FUT'
 * @returns {'NSE'|'NSEOPT'|'MCX'|'COMEX'|'GLOBAL'}
 */
function categoryForSegment(segment = '') {
  const s = String(segment == null ? '' : segment).trim().toUpperCase();
  if (s === 'NFO-FUT') return CATEGORY.NSE;
  if (s === 'NFO-OPT') return CATEGORY.NSEOPT;
  if (s === 'MCX-FUT' || s === 'MCX-OPT') return CATEGORY.MCX;
  if (s === 'COMEX-FUT') return CATEGORY.COMEX;
  return CATEGORY.GLOBAL;
}

/**
 * Distinct wallet categories an account can trade, derived from its
 * `exchanges_allowed`.
 *
 * Handles both persisted shapes:
 *   - Master: array of strings                -> ['NFO-FUT', 'MCX', ...]
 *   - User:   array of { exchange_name, turnover, lot, ... }
 *
 * A User row only counts when it is actually ticked (turnover or lot on) —
 * the same rule utils/exchangeAccess.js applies to trading: a saved row with
 * both off does not grant the exchange, so its wallet must not count either.
 * Blank/empty/malformed entries are ignored. Result is returned in canonical
 * order (NSE, NSEOPT, MCX, COMEX, GLOBAL) with duplicates removed.
 *
 * @param {Array<string|{exchange_name?: string, turnover?: boolean, lot?: boolean}>} [exchangesAllowed]
 * @returns {Array<'NSE'|'NSEOPT'|'MCX'|'COMEX'|'GLOBAL'>}
 */
function allowedCategories(exchangesAllowed = []) {
  if (!Array.isArray(exchangesAllowed)) return [];

  const found = new Set();
  for (const entry of exchangesAllowed) {
    if (entry == null) continue;
    let name;
    if (typeof entry === 'string') {
      name = entry;
    } else {
      if (entry.turnover !== true && entry.lot !== true) continue;
      name = entry.exchange_name;
    }
    if (name == null || String(name).trim() === '') continue;
    found.add(categoryForSegment(name));
  }

  return CATEGORY_ORDER.filter((category) => found.has(category));
}

/** "NSE OPT" for NSEOPT; any other key as-is. For user-facing messages. */
function categoryLabel(category) {
  return CATEGORY_LABEL[category] || String(category || '');
}

module.exports = {
  CATEGORY,
  CATEGORY_ORDER,
  CATEGORY_LABEL,
  categoryLabel,
  categoryForSegment,
  allowedCategories,
};
