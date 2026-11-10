'use strict';

/**
 * The price a position / watchlist starts with when the server starts, before
 * the first live tick (metricsEngine.init, livePriceService._preloadSettlementPrices).
 *
 * Weekend: the official settlement price (unchanged).
 * Weekday: the stored last_price — but NOT when it is far from the official
 * close stored on the same record. 10 Nov 2026 (NSE holiday): the 07:30 IST
 * instrument import saved other instruments' prices in last_price for ~14,500
 * NFO contracts (SUNPHARMA fut 0.20 vs close 1915.30, SBIN fut 5708.25 vs
 * 1042.25); a restart that morning seeded them, no live NFO tick came to
 * correct them, and 10 clients were margin squared-off at those prices.
 * last_price and the official close are both the previous session's close on
 * a normal day, so they agree; more than 25% apart means last_price is wrong.
 *
 * @param {{last_price?:number, ohlc_close?:number, settlement_price?:number}} inst
 * @param {{weekend:boolean, settlementIsCurrent?:boolean}} opts
 * @returns {{price:number, replaced:boolean}} price 0 = nothing to seed
 */
const MAX_DRIFT = 0.25;

function startupPrice(inst, { weekend, settlementIsCurrent = true }) {
  const num = (v) => (Number(v) > 0 ? Number(v) : 0);
  if (weekend) {
    return { price: (settlementIsCurrent ? num(inst.settlement_price) : 0) || num(inst.ohlc_close) || num(inst.last_price), replaced: false };
  }
  const last = num(inst.last_price);
  if (!last) return { price: 0, replaced: false }; // as before: no stored price, nothing seeded
  const official = num(inst.ohlc_close) || num(inst.settlement_price);
  if (official && Math.abs(last - official) / official > MAX_DRIFT) return { price: official, replaced: true };
  return { price: last, replaced: false };
}

module.exports = { startupPrice, MAX_DRIFT };
