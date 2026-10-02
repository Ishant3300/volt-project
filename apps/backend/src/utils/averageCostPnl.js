/**
 * Average-cost realized P&L over a pre-merged, pre-sorted trade list for ONE
 * instrument. Extracted from tradeReportController.js's private
 * `_computeAveragePricePnl` (previously duplicated nowhere else) so
 * scriptwisePnlController.js can call the exact same verified math per
 * (user, instrument) instead of re-deriving it — see CLAUDE.md's note on
 * apex-web-portal about not letting P&L engines silently drift apart.
 *
 * Agnostic to whose trades they are — the caller decides what "allTrades"
 * means (one user's, or several merged), same as before extraction.
 */
function computeAveragePricePnl(allTrades, seed) {
  return runAverageCost(allTrades, seed).pnl;
}

/**
 * The open position left after replaying `allTrades` onto `seed` with the
 * same average-cost rules — e.g. the position carried INTO a report window
 * from the fills before it. Does not touch the passed trades.
 * @returns {{ totalBuyQty, totalBuyValue, totalSellQty, totalSellValue }}
 */
function averageCostState(allTrades, seed) {
  return runAverageCost(allTrades.map((t) => ({ ...t })), seed).state;
}

function runAverageCost(allTrades, seed) {
  const sorted = [...allTrades].sort((a, b) => new Date(a.date) - new Date(b.date));

  let totalBuyQty = seed?.totalBuyQty || 0, totalBuyValue = seed?.totalBuyValue || 0;
  let totalSellQty = seed?.totalSellQty || 0, totalSellValue = seed?.totalSellValue || 0;
  let runningNet = totalBuyQty - totalSellQty;
  let totalPnl = 0;

  for (const trade of sorted) {
    const isBuy = (trade.buy_qty || 0) > 0;
    const qty = isBuy ? trade.buy_qty : (trade.sell_qty || 0);
    if (qty <= 0) { trade.pnl = 0; continue; }

    const price = trade.rate || 0;
    const prevNet = runningNet;
    const isClosing = (isBuy && prevNet < 0) || (!isBuy && prevNet > 0);

    if (!isClosing) {
      if (isBuy) { totalBuyQty += qty; totalBuyValue += qty * price; }
      else { totalSellQty += qty; totalSellValue += qty * price; }
      trade.pnl = 0;
    } else {
      const closingQty = Math.min(qty, Math.abs(prevNet));
      let tradePnl = 0;

      if (!isBuy && prevNet > 0) {
        const avgBuy = totalBuyQty > 0 ? totalBuyValue / totalBuyQty : 0;
        tradePnl = (price - avgBuy) * closingQty;
        totalBuyQty -= closingQty;
        totalBuyValue -= closingQty * avgBuy;
      } else if (isBuy && prevNet < 0) {
        const avgSell = totalSellQty > 0 ? totalSellValue / totalSellQty : 0;
        tradePnl = (avgSell - price) * closingQty;
        totalSellQty -= closingQty;
        totalSellValue -= closingQty * avgSell;
      }

      trade.pnl = Math.round(tradePnl * 100) / 100;
      totalPnl += tradePnl;

      const excess = qty - Math.abs(prevNet);
      if (excess > 0) {
        // Same-trade flip — the excess beyond the close starts a fresh
        // position on the opposite side. The closed side is already at
        // zero from the decrement above.
        if (isBuy) { totalBuyQty = excess; totalBuyValue = excess * price; }
        else { totalSellQty = excess; totalSellValue = excess * price; }
      }
      // excess <= 0: either an exact full close (closed side already at
      // zero from the decrement above) or a partial close (remainder of
      // the position stays open at its existing average) — nothing more
      // to do in either case.
    }

    runningNet = isBuy ? runningNet + qty : runningNet - qty;
  }

  return {
    pnl: Math.round(totalPnl * 100) / 100,
    state: { totalBuyQty, totalBuyValue, totalSellQty, totalSellValue },
  };
}

module.exports = { computeAveragePricePnl, averageCostState };
