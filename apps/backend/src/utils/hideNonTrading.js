'use strict';

/**
 * Settings LISTS (brokerage, script quantity, fresh stop-loss) hide rows for
 * scripts that trade nowhere — e.g. MCX agri (COTTON, KAPAS, CARDAMOM,
 * MENTHAOIL…), GOLDPETAL, NICKEL, dropped F&O stocks: on 25 Oct 2026 the user
 * asked that agri MCX scripts not show in the app. Same rule as the brokerage
 * floor (brokerageCopyService.tradingScriptNames): a name in no active
 * instrument. Only the listing changes — the rows stay in the database
 * untouched, and a script that becomes active again shows again by itself.
 * When the instrument list looks broken (tradingScriptNames → null) nothing
 * is hidden.
 */

const TTL_MS = 60 * 1000;
let cached = null; // { at, set }

async function tradingNames() {
  if (cached && Date.now() - cached.at < TTL_MS) return cached.set;
  const { tradingScriptNames } = require('../services/brokerageCopyService');
  const set = await tradingScriptNames();
  cached = { at: Date.now(), set };
  return set;
}

/** `filter` plus `{ [field]: { $nin: <non-trading names present> } }`, or `filter` as-is. */
async function withoutNonTrading(Model, filter, field) {
  const trading = await tradingNames();
  if (!trading) return filter;
  const names = await Model.distinct(field, filter);
  const dead = names.filter((n) => n && !trading.has(String(n).toUpperCase()));
  return dead.length ? { ...filter, [field]: { $nin: dead } } : filter;
}

function _resetCache() { cached = null; }

module.exports = { withoutNonTrading, _resetCache };
