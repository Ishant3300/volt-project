'use strict';

/**
 * Per-script position cap (ScriptQuantity.max_qty) at FILL time.
 *
 * placeTrade checks the cap when an order is PLACED
 * (tradeController.js, _validateScriptQuantityLimit), but a LIMIT/SL order
 * can sit pending and fill later, after other orders have already grown the
 * position. Confirmed live (client 313738, INOXWIND, max 1500, 30 Sep 2026):
 * holding 1000, a BUY 500 LIMIT was placed (1000 + 500 = 1500, allowed) and
 * left pending; a BUY 500 MARKET then filled (1500); the pending LIMIT then
 * filled too with no check, taking the position to 2000.
 *
 * Same lookup and same rule as the placement check:
 *   - the row is the client's own ScriptQuantity for the instrument's
 *     segment (GLOBAL is stored as INDICES) and raw name, else its
 *     tradingsymbol; no row = no cap;
 *   - max 0 = the script isn't tradable for the account: nothing may be
 *     opened or added (reducing/closing is allowed);
 *   - a positive max caps the position, in quantity (turnover mode) or lots
 *     (lot mode), from the client's exchanges_allowed for the segment;
 *   - only a fill that GROWS the position is refused — reducing or closing
 *     is always allowed.
 * An order placed by ADMIN or SYSTEM is not checked, same as at placement
 * (an admin order skips the per-script cap there).
 *
 * Returns the rejection remark, or null when the fill is allowed.
 */
const ScriptQuantity = require('../models/ScriptQuantity');

async function positionLimitRejection({ trade, previousNetQty, instrument, user, session = null }) {
  if (trade.placed_by === 'ADMIN' || trade.placed_by === 'SYSTEM') return null;

  const rawSegment = String(instrument?.segment || trade.exchange || '').toUpperCase();
  const exchangeName = rawSegment === 'GLOBAL' ? 'INDICES' : rawSegment;
  const userExchange = (user?.exchanges_allowed || []).find(
    (ex) => String(ex.exchange_name || '').toUpperCase() === exchangeName,
  );
  const rawName = instrument?.raw_name || instrument?.name || null;

  let row = null;
  if (rawName) {
    row = await ScriptQuantity.findOne({ owner_id: trade.user_id, exchange_name: exchangeName, script_name: rawName, deleted_at: null })
      .session(session).lean();
  }
  if (!row) {
    row = await ScriptQuantity.findOne({ owner_id: trade.user_id, exchange_name: exchangeName, script_name: trade.tradingsymbol, deleted_at: null })
      .session(session).lean();
  }
  if (!row) return null;

  const limit = row.max_qty;
  const lotSize = row.lot_size || instrument?.lot_size || 1;
  const quantity = Number(trade.quantity) || 0;
  const current = Number(previousNetQty) || 0;
  const after = trade.transaction_type === 'BUY' ? current + quantity : current - quantity;
  const absCurrent = Math.abs(current);
  const absAfter = Math.abs(after);
  const name = rawName || trade.tradingsymbol;

  if (limit === 0) {
    return absAfter > absCurrent
      ? `${name} is not allowed for this account — no quantity allotted (max 0). Existing positions can only be closed.`
      : null;
  }
  if (!(limit > 0)) return null;

  // A ticked COMEX row always trades in lots (utils/comexLots.js).
  const mode = require('../utils/comexLots').tradingModeFor(userExchange, exchangeName);
  if (mode.turnover) {
    if (absAfter > absCurrent && absAfter > limit) {
      return `Order exceeds maximum position limit at execution. Max: ${limit} qty, Position: ${absCurrent} qty, Order: ${quantity} qty.`;
    }
  } else if (mode.lot) {
    const currentLots = Math.floor(absCurrent / lotSize);
    const afterLots = Math.ceil(absAfter / lotSize);
    if (afterLots > currentLots && afterLots > limit) {
      return `Order exceeds maximum position limit at execution. Max: ${limit} lot(s), Position: ${currentLots} lot(s), Order: ${Math.ceil(quantity / lotSize)} lot(s).`;
    }
  }
  return null;
}

module.exports = { positionLimitRejection };
