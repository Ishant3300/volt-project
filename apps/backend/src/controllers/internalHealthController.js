const Trade = require('../models/Trade');

/**
 * GET /api/auth/internal-health — live, in-memory state for the watchdog
 * (scripts/watchdog), which can't see it in the database: Kite feed timing,
 * per-client live metrics, pending orders whose price has already been
 * crossed, event-loop lag. Read-only.
 *
 * Only for the watchdog on this server: the request must carry
 * X-Watchdog-Key = WATCHDOG_KEY from .env and must not have come through
 * nginx (no X-Forwarded-For). Anything else gets a plain 404.
 */
const internalHealth = async (req, res) => {
  const key = process.env.WATCHDOG_KEY;
  if (!key || req.headers['x-watchdog-key'] !== key || req.headers['x-forwarded-for']) {
    return res.status(404).json({ success: false, message: 'Not found', data: null });
  }
  try {
    const lagStart = Date.now();
    await new Promise((r) => setImmediate(r));
    const eventLoopLagMs = Date.now() - lagStart;

    const lps = require('../services/livePriceService');
    const me = require('../services/metricsEngine');

    const metrics = [];
    for (const m of me._metricsCache?.values?.() || []) {
      metrics.push({
        user_id: m.user_id,
        credit: m.credit,
        equity: m.equity,
        m2m_pnl: m.m2m_pnl,
        margin_used: m.margin_used,
        open_positions: Array.isArray(m.positions) ? m.positions.filter((p) => p.net_qty).length : 0,
      });
    }

    const ltpOf = (token) => me._ltpMap?.get(String(token))
      || lps.latestPrices?.get(String(token))
      || lps.latestPrices?.get(Number(token))
      || null;
    const pending = await Trade.find({ status: 'pending', deleted_at: null })
      .select('user_id tradingsymbol instrument_token transaction_type order_type price trigger_direction createdAt')
      .lean();
    const crossed = [];
    for (const t of pending) {
      const ltp = ltpOf(t.instrument_token);
      if (!(ltp > 0) || !(t.price > 0)) continue;
      let hit = false;
      if (t.order_type === 'LIMIT') hit = t.transaction_type === 'BUY' ? ltp <= t.price : ltp >= t.price;
      else if (t.trigger_direction === 'RISE') hit = ltp >= t.price;
      else if (t.trigger_direction === 'FALL') hit = ltp <= t.price;
      if (hit) {
        crossed.push({ trade_id: String(t._id), user_id: String(t.user_id), symbol: t.tradingsymbol, side: t.transaction_type, order_type: t.order_type, price: t.price, ltp, placed_at: t.createdAt });
      }
    }

    res.status(200).json({
      success: true,
      data: {
        now: Date.now(),
        event_loop_lag_ms: eventLoopLagMs,
        kite: { connected: !!lps.isKiteConnected, last_message_at: lps._lastTickAt || 0, last_tick_at: lps._lastRealTickAt || 0 },
        ws_clients: lps.wss?.clients?.size ?? null,
        pending_total: pending.length,
        pending_crossed: crossed,
        metrics,
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: error.message, data: null });
  }
};

module.exports = { internalHealth };
