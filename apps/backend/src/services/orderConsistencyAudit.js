/**
 * Order Consistency Audit Service
 *
 * Periodically compares pending orders in MongoDB against what's actually
 * registered in the Redis order book. Detects "orphaned" orders — orders
 * that exist in MongoDB as 'pending' but are MISSING from Redis, meaning
 * they'll never trigger via the live BullMQ path.
 *
 * This is the exact scenario described in the bug: Redis was briefly
 * unavailable when addOrder() was called, so the order sits in Mongo as
 * 'pending' but was never registered in Redis. The DB-fallback poller
 * skips itself when Redis is back up, so the order is stuck forever.
 *
 * When orphans are found, this service:
 * 1. Logs them prominently (always — not gated by LOG_REDIS_ORDERS)
 * 2. Optionally re-registers them into Redis (auto-heal)
 */

const Trade = require('../models/Trade');
const redisService = require('./redisService');
const orderBookService = require('./orderBookService');
const { LOG_REDIS_ORDERS } = require('../config/logFlags');

const _ts = () => new Date().toISOString();

/**
 * Run the consistency audit.
 * @param {object} options
 * @param {boolean} [options.autoHeal=true] - If true, re-register orphaned orders into Redis
 * @param {boolean} [options.silent=false] - If true, suppress "all consistent" log
 * @returns {{ orphans: Array, healed: number, total: number }}
 */
const runAudit = async (options = {}) => {
  const { autoHeal = true, silent = false } = options;

  if (!redisService.isAvailable()) {
    if (!silent) {
      console.log(`⚠️  [OrderAudit] [${_ts()}] Skipped — Redis unavailable (can't verify)`);
    }
    return { orphans: [], healed: 0, total: 0, skipped: true };
  }

  try {
    // Fetch all pending limit/SL orders from MongoDB
    const pendingTrades = await Trade.find({
      status: 'pending',
      order_type: { $in: ['LIMIT', 'SL', 'SL-M'] },
      deleted_at: null,
    }).select('_id instrument_token transaction_type order_type price tradingsymbol createdAt').lean();

    if (pendingTrades.length === 0) {
      if (LOG_REDIS_ORDERS && !silent) {
        console.log(`✅ [OrderAudit] [${_ts()}] No pending orders in DB — nothing to audit`);
      }
      return { orphans: [], healed: 0, total: 0 };
    }

    const orphans = [];
    let healed = 0;

    // Check each pending trade against Redis
    for (const trade of pendingTrades) {
      const result = await orderBookService.verifyOrderExists(
        trade._id.toString(),
        trade.instrument_token,
        trade.transaction_type,
        trade.order_type
      );

      if (!result.exists) {
        orphans.push({
          tradeId: trade._id.toString(),
          instrumentToken: trade.instrument_token,
          tradingsymbol: trade.tradingsymbol,
          side: trade.transaction_type,
          orderType: trade.order_type,
          price: trade.price,
          createdAt: trade.createdAt,
          reason: result.reason || 'not_in_redis',
        });
      }
    }

    if (orphans.length > 0) {
      // Always log orphans prominently — this is the exact bug condition
      console.log(`🚨 [OrderAudit] [${_ts()}] CONSISTENCY MISMATCH: ${orphans.length}/${pendingTrades.length} pending order(s) MISSING from Redis!`);
      for (const orphan of orphans) {
        console.log(`   🔴 [OrderAudit] ORPHAN: tradeId=${orphan.tradeId} ${orphan.orderType} ${orphan.side} ${orphan.tradingsymbol} @ ${orphan.price} | token=${orphan.instrumentToken} | createdAt=${orphan.createdAt}`);
      }

      // Auto-heal: re-register orphans into Redis
      if (autoHeal) {
        // Re-registering the order into Redis alone isn't enough: price
        // ticks only reach the matcher for instruments actually subscribed
        // on the Kite feed, and the ONLY thing that adds an instrument to
        // that subscription is livePriceService.addPendingToken(), normally
        // called once at fresh order placement. A healed order that skips
        // this call sits correctly in Redis but never receives a tick, so
        // it can still never trigger — while this audit reports it as
        // healed, masking the exact failure this service exists to catch.
        const livePriceService = require('./livePriceService');
        for (const orphan of orphans) {
          const success = await orderBookService.addOrder(
            orphan.tradeId,
            orphan.instrumentToken,
            orphan.price,
            orphan.side,
            orphan.orderType
          );
          if (success) {
            livePriceService.addPendingToken(orphan.instrumentToken);
            healed++;
            console.log(`   🟢 [OrderAudit] [${_ts()}] HEALED: tradeId=${orphan.tradeId} re-registered in Redis + re-subscribed on Kite feed`);
          } else {
            console.log(`   ❌ [OrderAudit] [${_ts()}] HEAL FAILED: tradeId=${orphan.tradeId} — Redis still unavailable or error`);
          }
        }
        console.log(`📋 [OrderAudit] [${_ts()}] Audit complete: ${orphans.length} orphan(s) found, ${healed} healed, ${pendingTrades.length} total pending`);
      }
    } else if (!silent) {
      if (LOG_REDIS_ORDERS) {
        console.log(`✅ [OrderAudit] [${_ts()}] All ${pendingTrades.length} pending order(s) verified present in Redis`);
      }
    }

    return { orphans, healed, total: pendingTrades.length };
  } catch (err) {
    console.error(`❌ [OrderAudit] [${_ts()}] Audit error: ${err.message}`);
    return { orphans: [], healed: 0, total: 0, error: err.message };
  }
};

module.exports = { runAudit };
