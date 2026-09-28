'use strict';

/**
 * GIFT NIFTY monthly contracts — one KiteInstrument per NSE IX NIFTY futures
 * expiry (GIFTNIFTY26OCTFUT, GIFTNIFTY26NOVFUT, …), like every other futures
 * series, instead of the single continuous "GIFT NIFTY" instrument (which is
 * kept only for its history and retired for new trades — see
 * giftNiftyFeedService). Quotes come from NSE IX (giftNiftyFeedService), not
 * Kite, so the tokens live in a range Kite never uses (>= 9,900,000,000) and
 * are kept off the Kite subscription (livePriceService).
 *
 * Same name ('GIFT NIFTY'), raw_name and segment ('INDICES') as the
 * continuous instrument, so existing brokerage rates, script-quantity limits,
 * groups and exchange permissions apply to every month unchanged.
 */

const KiteInstrument = require('../models/KiteInstrument');
const { dateKey } = require('../utils/settlementDates');

const TOKEN_BASE = 9_900_000_000;
const NAME = 'GIFT NIFTY';
/** Monthly contracts are created for expiries on/after this day (the Sep 2026 month stays on the continuous instrument). */
const MONTHLY_FROM = '2026-10-01';
const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/** 27 Oct 2026 → '9920261027' */
function contractToken(expiry) {
  const d = new Date(expiry);
  return String(TOKEN_BASE + Number(`${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}`));
}

/** 27 Oct 2026 → 'GIFTNIFTY26OCTFUT' */
function contractSymbol(expiry) {
  const d = new Date(expiry);
  return `GIFTNIFTY${String(d.getUTCFullYear()).slice(2)}${MONTHS[d.getUTCMonth()]}FUT`;
}

function isGiftContractToken(token) {
  return Number(token) >= TOKEN_BASE;
}

function buildContract(expiry, enabled) {
  const d = new Date(expiry);
  const token = contractToken(d);
  return {
    instrument_token: token,
    exchange_token: token,
    tradingsymbol: contractSymbol(d),
    name: NAME,
    raw_name: NAME,
    display_name: `GIFT NIFTY FUT ${d.toLocaleDateString('en-US', { timeZone: 'UTC', month: 'short', year: 'numeric' })}`,
    expiry: d,
    strike: 0,
    tick_size: 0.5,
    lot_size: 1,
    instrument_type: 'FUT',
    segment: 'INDICES',
    exchange: 'NSEIX',
    is_active: true,
    enabled,
    ban_reason: enabled ? null : 'Opens for trading on the Monday of the expiring month\'s expiry week',
    banned_at: enabled ? null : new Date(),
  };
}

/**
 * Create any listed month that doesn't exist yet (never touches existing
 * ones). The nearest monthly contract starts open; later months start
 * closed and are opened by the expiry schedule (config/expiryRules.js,
 * Monday of the expiring month's expiry week).
 *
 * @param {Date[]} listedExpiries - NSE IX's current NIFTY futures expiries
 * @returns {Promise<string[]>} symbols created
 */
async function ensureContracts(listedExpiries) {
  const monthly = [...new Set(listedExpiries.map((e) => dateKey(e)))]
    .filter((k) => k >= MONTHLY_FROM)
    .sort()
    .map((k) => new Date(`${k}T00:00:00.000Z`));
  if (monthly.length === 0) return [];

  const existing = await KiteInstrument.find({ instrument_token: { $in: monthly.map(contractToken) } }).select('instrument_token').lean();
  const have = new Set(existing.map((e) => e.instrument_token.toString()));
  const anyExisting = existing.length > 0;
  const created = [];
  for (const [i, expiry] of monthly.entries()) {
    const token = contractToken(expiry);
    if (have.has(token)) continue;
    // Only the very first month ever created starts open; after that every
    // new month appears as the far month and waits for its scheduled open.
    const doc = buildContract(expiry, !anyExisting && i === 0);
    const res = await KiteInstrument.updateOne({ instrument_token: token }, { $setOnInsert: doc }, { upsert: true });
    if (res.upsertedCount) created.push(doc.tradingsymbol);
  }
  if (created.length) {
    console.log(`🆕 [GiftNifty] Created monthly contract(s): ${created.join(', ')}`);
    try { require('./instrumentSearchService').invalidateCache(); } catch (_) {}
  }
  return created;
}

module.exports = { ensureContracts, contractToken, contractSymbol, isGiftContractToken, buildContract, TOKEN_BASE, MONTHLY_FROM, NAME };
