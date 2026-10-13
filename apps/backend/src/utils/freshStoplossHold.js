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

/**
 * The open position's lots, oldest first (FIFO): [{ qty, openedAt }]. Built
 * from the instrument's completed fills in execution order; a close consumes
 * the oldest lots, so what is left is exactly the quantity still held and
 * when each part of it was bought (or sold short).
 */
function openLots(fills) {
  const lots = [];
  let side = 0;
  for (const f of fills) {
    const sg = f.transaction_type === 'BUY' ? 1 : -1;
    let qty = Number(f.executed_quantity ?? f.quantity) || 0;
    const at = f.executed_at || f.createdAt;
    while (qty > 0 && lots.length && side !== sg) {
      const m = Math.min(qty, lots[0].qty);
      lots[0].qty -= m;
      qty -= m;
      if (lots[0].qty === 0) lots.shift();
    }
    if (!lots.length) side = 0;
    if (qty > 0) {
      side = sg;
      lots.push({ qty, openedAt: at });
    }
  }
  return lots;
}

/**
 * Lot-aware hold: only quantity opened within the last `timeMinutes` is held.
 * Closing up to the "aged" quantity (lots older than the hold) is allowed; an
 * add no longer locks lots the client has held for longer. Closes consume the
 * oldest lots first. Returns the rejection message or null.
 */
function lotHoldRejection({ lots, closeQuantity, timeMinutes, now = Date.now() }) {
  if (!(timeMinutes > 0) || !Array.isArray(lots) || !lots.length) return null;
  const requiredMs = timeMinutes * 60 * 1000;
  const openedMs = (l) => new Date(l.openedAt).getTime();
  const isAged = (l) => now - openedMs(l) >= requiredMs;
  const held = lots.reduce((s, l) => s + l.qty, 0);
  // Only the closing part counts — quantity beyond the position opens the other side.
  const need = Math.min(Number(closeQuantity) || 0, held);
  const aged = lots.filter(isAged).reduce((s, l) => s + l.qty, 0);
  if (need <= aged) return null;
  // Fresh lots age oldest-first: wait for the one that covers the quantity asked.
  let covered = aged;
  let releaseAt = now + requiredMs;
  for (const l of lots) {
    if (isAged(l)) continue;
    covered += l.qty;
    if (covered >= need) { releaseAt = openedMs(l) + requiredMs; break; }
  }
  const remainingMins = Math.max(1, Math.ceil((releaseAt - now) / 60000));
  return aged > 0
    ? `Fresh Stop-Loss: Cannot close more than ${aged} qty for ${remainingMins} more minute(s) — the rest was opened in the last ${timeMinutes} minutes. Time restriction: ${timeMinutes} minutes.`
    : `Fresh Stop-Loss: Cannot close this position for ${remainingMins} more minute(s). Time restriction: ${timeMinutes} minutes.`;
}

module.exports = { closesInProfit, holdTimeRejection, openLots, lotHoldRejection };
