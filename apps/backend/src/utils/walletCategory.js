'use strict';

/**
 * Wallet category helpers.
 *
 * Every user/master trade wallet is split into six category pools: NSE,
 * INDEX, NSEOPT, MCX, COMEX and GLOBAL. A trade's segment (plus, for NFO
 * futures, its underlying) — and an account's allowed exchanges — map into
 * these categories via a fixed rule:
 *
 *   NFO-FUT NIFTY / BANKNIFTY / SENSEX
 *                     -> INDEX   (index futures have their own pool, the
 *                                 same way NSE options got NSEOPT — Oct 2026)
 *   NFO-FUT (others)  -> NSE     (stock futures + FINNIFTY / MIDCPNIFTY /
 *                                 BANKEX / NIFTYNXT50 futures)
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
 * re-derive the category from the instrument at close time. Changing this
 * mapping moves the margin of positions already open with it: it was blocked
 * from the old pool, shows as blocked in the new one (reconcile), and is
 * released into the new one on close. INDEX went live with open NIFTY /
 * BANKNIFTY futures that way (their margin left NSE when opened and returns
 * to INDEX); new index-future trades need INDEX funded.
 *
 * Every trade/wallet path must call categoryForSegment(segment, instrument)
 * WITH the instrument (or the trade/position carrying its tradingsymbol) —
 * without it an NFO future can't be told apart and falls back to NSE.
 */

const CATEGORY = Object.freeze({ NSE: 'NSE', INDEX: 'INDEX', NSEOPT: 'NSEOPT', MCX: 'MCX', COMEX: 'COMEX', GLOBAL: 'GLOBAL' });

// Canonical order used when returning a distinct set of categories, so callers
// (and tests) get a deterministic result regardless of input ordering.
const CATEGORY_ORDER = Object.freeze([CATEGORY.NSE, CATEGORY.INDEX, CATEGORY.NSEOPT, CATEGORY.MCX, CATEGORY.COMEX, CATEGORY.GLOBAL]);

/** Display label for a category key ("NSE OPT" for NSEOPT). */
const CATEGORY_LABEL = Object.freeze({
  NSE: 'NSE', INDEX: 'INDEX', NSEOPT: 'NSE OPT', MCX: 'MCX', COMEX: 'COMEX', GLOBAL: 'GLOBAL',
});

/** NFO futures on these underlyings use the INDEX pool. */
const INDEX_FUTURE_NAMES = Object.freeze(['NIFTY', 'BANKNIFTY', 'SENSEX']);
// NIFTY26OCTFUT / BANKNIFTY26NOVFUT / SENSEX26OCTFUT — the name must be followed
// directly by the expiry, so NIFTYNXT50…, FINNIFTY…, MIDCPNIFTY… never match.
const INDEX_FUTURE_SYMBOL = /^(NIFTY|BANKNIFTY|SENSEX)\d{2}[A-Z]{3}FUT$/;

/**
 * Whether an instrument / trade / position is an index future of the INDEX
 * pool. Accepts objects carrying `raw_name` / `name` / `tradingsymbol`, or a
 * plain name or tradingsymbol string; any ref that identifies one decides.
 */
function isIndexFuture(...refs) {
  for (const ref of refs) {
    if (ref == null) continue;
    const vals = typeof ref === 'string' ? [ref] : [ref.raw_name, ref.name, ref.tradingsymbol];
    for (const v of vals) {
      if (v == null || v === '') continue;
      const s = String(v).trim().toUpperCase();
      if (INDEX_FUTURE_NAMES.includes(s) || INDEX_FUTURE_SYMBOL.test(s)) return true;
    }
  }
  return false;
}

/**
 * Map a segment / exchange name (and, for NFO futures, the instrument) to its
 * wallet category. Case-insensitive; anything unrecognised falls back to GLOBAL.
 *
 * @param {string} [segment] - e.g. 'NFO-FUT', 'NFO-OPT', 'MCX-OPT', 'SGX', 'COMEX-FUT'
 * @param {...(object|string)} instrumentRefs - the KiteInstrument / trade /
 *   position (raw_name, name or tradingsymbol) — REQUIRED on every trade and
 *   wallet path, so NIFTY / BANKNIFTY / SENSEX futures land in INDEX
 * @returns {'NSE'|'INDEX'|'NSEOPT'|'MCX'|'COMEX'|'GLOBAL'}
 */
function categoryForSegment(segment = '', ...instrumentRefs) {
  const s = String(segment == null ? '' : segment).trim().toUpperCase();
  if (s === 'NFO-FUT') return isIndexFuture(...instrumentRefs) ? CATEGORY.INDEX : CATEGORY.NSE;
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
 * order (NSE, INDEX, NSEOPT, MCX, COMEX, GLOBAL) with duplicates removed.
 *
 * @param {Array<string|{exchange_name?: string, turnover?: boolean, lot?: boolean}>} [exchangesAllowed]
 * @returns {Array<'NSE'|'INDEX'|'NSEOPT'|'MCX'|'COMEX'|'GLOBAL'>}
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
    // NFO futures span two pools: stock futures (NSE) and index futures (INDEX).
    if (String(name).trim().toUpperCase() === 'NFO-FUT') found.add(CATEGORY.INDEX);
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
  isIndexFuture,
  INDEX_FUTURE_NAMES,
};
