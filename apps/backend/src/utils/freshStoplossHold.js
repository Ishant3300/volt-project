'use strict';

/**
 * Fresh Stop-Loss hold time (FreshStoplossLimit.time_minutes): a position may
 * not be closed IN PROFIT until that many minutes after its last opening fill.
 * Closing at a loss is always allowed.
 *
 * Applies to every order type. Was MARKET-only, which let a client book the
 * profit inside the window with a LIMIT (a SELL limit at/below the bid fills
 * at once) or a stop. LIMIT/SL/SL-M fill at exactly their own price (see
 * priceQueueService: executed_price = trade.price), so for them the order's
 * price decides profit; a MARKET close is judged at the bid (closing a long)
 * or the ask (closing a short), as before.
 *
 * `state` is computeFlatResetState() of the account's completed trades on the
 * instrument.
 */
function closesInProfit({ orderType, transactionType, price, state, bid, ask }) {
  const net = Number(state?.netQty) || 0;
  const isClosing = (transactionType === 'SELL' && net > 0) || (transactionType === 'BUY' && net < 0);
  if (!isClosing) return false;

  const closePrice = orderType === 'MARKET'
    ? Number(transactionType === 'SELL' ? bid : ask)
    : Number(price);
  if (!(closePrice > 0)) return false;

  if (net > 0) {
    const avgBuy = state.totalBuyQty > 0 ? state.totalBuyValue / state.totalBuyQty : 0;
    return closePrice > avgBuy;
  }
  const avgSell = state.totalSellQty > 0 ? state.totalSellValue / state.totalSellQty : 0;
  return closePrice < avgSell;
}

/** Rejection message while the hold time since `lastOpenedAt` is running, else null. */
function holdTimeRejection({ lastOpenedAt, timeMinutes, now = Date.now() }) {
  if (!(timeMinutes > 0) || !lastOpenedAt) return null;
  const elapsedMs = now - new Date(lastOpenedAt).getTime();
  const requiredMs = timeMinutes * 60 * 1000;
  if (!(elapsedMs < requiredMs)) return null;
  const remainingMins = Math.ceil((requiredMs - elapsedMs) / 60000);
  return `Fresh Stop-Loss: Cannot close this position for ${remainingMins} more minute(s). Time restriction: ${timeMinutes} minutes.`;
}

module.exports = { closesInProfit, holdTimeRejection };
