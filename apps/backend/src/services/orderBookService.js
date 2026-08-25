/**
 * Order Book Service  (Redis-backed)
 *
 * Uses Redis Sorted Sets to maintain an in-memory order book.
 *
 * Key schema
 * ----------
 *   ob:{instrument_token}:buy       – LIMIT buys,  score = limitPrice
 *   ob:{instrument_token}:sell      – LIMIT sells, score = limitPrice
 *   ob:{instrument_token}:stopbuy   – SL/SL-M buys,  score = triggerPrice
 *   ob:{instrument_token}:stopsell  – SL/SL-M sells, score = triggerPrice
 *
 * Each member is the trade's MongoDB _id (string).
 *
 * Why two separate pairs of sets for LIMIT vs stop orders, not one?
 *   A LIMIT BUY and a stop (SL/SL-M) BUY trigger on OPPOSITE price movement:
 *   a LIMIT buyer wants to buy once the price falls to/below their price
 *   (an entry), while a stop buyer wants to buy once the price rises
 *   to/above their trigger (typically closing out a short before the loss
 *   grows). Storing both in the same sorted set and querying with the same
 *   ZRANGEBYSCORE direction would fire stop orders at the wrong time (e.g.
 *   immediately, or never) — this was a real bug: SL/SL-M orders were
 *   simply never registered anywhere at all (only LIMIT was), so they sat
 *   pending forever with zero stop-loss protection. Separate sets with
 *   deliberately inverted range queries fix that without disturbing the
 *   already-correct LIMIT matching.
 *
 * Why sorted sets?
 *   • ZRANGEBYSCORE lets us grab all BUY orders with price >= livePrice in O(log N + M)
 *   • ZRANGEBYSCORE lets us grab all SELL orders with price <= livePrice
 *   • Adding / removing a single order is O(log N)
 */

const redisService = require('./redisService');
const { LOG_REDIS_ORDERS } = require('../config/logFlags');

const _ts = () => new Date().toISOString();

// ─── Key helpers ────────────────────────────────────────────────────────────

const _buyKey = (token) => `ob:${token}:buy`;
const _sellKey = (token) => `ob:${token}:sell`;
const _stopBuyKey = (token) => `ob:${token}:stopbuy`;
const _stopSellKey = (token) => `ob:${token}:stopsell`;

const _isStop = (orderType) => orderType === 'SL' || orderType === 'SL-M';

const _key = (instrumentToken, side, orderType) => {
  const stop = _isStop(orderType);
  if (side === 'BUY') return stop ? _stopBuyKey(instrumentToken) : _buyKey(instrumentToken);
  return stop ? _stopSellKey(instrumentToken) : _sellKey(instrumentToken);
};

// ─── Public API ─────────────────────────────────────────────────────────────

/**
 * Register a pending order (LIMIT or SL/SL-M) in the Redis order book.
 *
 * @param {string} tradeId        – MongoDB _id of the Trade document
 * @param {string} instrumentToken
 * @param {number} limitPrice     – limit price for LIMIT, trigger price for SL/SL-M
 * @param {'BUY'|'SELL'} side
 * @param {'LIMIT'|'SL'|'SL-M'} [orderType='LIMIT']
 */
const addOrder = async (tradeId, instrumentToken, limitPrice, side, orderType = 'LIMIT') => {
  if (!redisService.isAvailable()) {
    console.log(`🔴 [OrderBook] [${_ts()}] addOrder FAILED — Redis unavailable | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} @ ${limitPrice} | diagnostics=${JSON.stringify(redisService.getDiagnostics())}`);
    return false;
  }

  try {
    const key = _key(instrumentToken, side, orderType);
    // Score = limitPrice/triggerPrice so we can range-query efficiently
    await redisService.getClient().zadd(key, limitPrice, tradeId);
    if (LOG_REDIS_ORDERS) {
      console.log(`📗 [OrderBook] [${_ts()}] addOrder OK | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} @ ${limitPrice} | key=${key}`);
    }
    return true;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] addOrder EXCEPTION | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} @ ${limitPrice} | error=${err.message}`);
    return false;
  }
};

/**
 * Remove an order from the book (on cancel or execution).
 */
const removeOrder = async (tradeId, instrumentToken, side, orderType = 'LIMIT') => {
  if (!redisService.isAvailable()) {
    if (LOG_REDIS_ORDERS) {
      console.log(`⚠️  [OrderBook] [${_ts()}] removeOrder SKIPPED — Redis unavailable | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side}`);
    }
    return false;
  }

  try {
    const key = _key(instrumentToken, side, orderType);
    const removed = await redisService.getClient().zrem(key, tradeId);
    if (LOG_REDIS_ORDERS) {
      console.log(`📕 [OrderBook] [${_ts()}] removeOrder | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} | removed=${removed} key=${key}`);
    }
    return true;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] removeOrder EXCEPTION | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} | error=${err.message}`);
    return false;
  }
};

/**
 * Find all LIMIT BUY orders whose limitPrice >= livePrice
 * (i.e. the buyer is willing to pay at least the current price).
 *
 * Returns array of tradeId strings.
 */
const getMatchingBuyOrders = async (instrumentToken, livePrice) => {
  if (!redisService.isAvailable()) return [];

  try {
    const key = _buyKey(instrumentToken);
    // BUY executes when livePrice <= limitPrice
    // So we want all orders with score (limitPrice) >= livePrice
    const tradeIds = await redisService.getClient().zrangebyscore(key, livePrice, '+inf');
    if (LOG_REDIS_ORDERS && tradeIds.length > 0) {
      console.log(`🔍 [OrderBook] [${_ts()}] getMatchingBuyOrders | token=${instrumentToken} livePrice=${livePrice} | matched=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
    return tradeIds;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] getMatchingBuyOrders error | token=${instrumentToken} livePrice=${livePrice} | ${err.message}`);
    return [];
  }
};

/**
 * Find all LIMIT SELL orders whose limitPrice <= livePrice
 * (i.e. the seller wants at least this price and the market is there).
 *
 * Returns array of tradeId strings.
 */
const getMatchingSellOrders = async (instrumentToken, livePrice) => {
  if (!redisService.isAvailable()) return [];

  try {
    const key = _sellKey(instrumentToken);
    // SELL executes when livePrice >= limitPrice
    // So we want all orders with score (limitPrice) <= livePrice
    const tradeIds = await redisService.getClient().zrangebyscore(key, '-inf', livePrice);
    if (LOG_REDIS_ORDERS && tradeIds.length > 0) {
      console.log(`🔍 [OrderBook] [${_ts()}] getMatchingSellOrders | token=${instrumentToken} livePrice=${livePrice} | matched=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
    return tradeIds;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] getMatchingSellOrders error | token=${instrumentToken} livePrice=${livePrice} | ${err.message}`);
    return [];
  }
};

/**
 * Find all stop (SL/SL-M) BUY orders whose triggerPrice <= livePrice —
 * INVERTED from a LIMIT buy. A stop BUY (typically covering a short before
 * the loss grows) triggers once the price rises to/through the trigger, so
 * it fires when livePrice >= triggerPrice, i.e. all orders with score
 * (triggerPrice) <= livePrice.
 *
 * Returns array of tradeId strings.
 */
const getMatchingStopBuyOrders = async (instrumentToken, livePrice) => {
  if (!redisService.isAvailable()) return [];

  try {
    const key = _stopBuyKey(instrumentToken);
    const tradeIds = await redisService.getClient().zrangebyscore(key, '-inf', livePrice);
    if (LOG_REDIS_ORDERS && tradeIds.length > 0) {
      console.log(`🔍 [OrderBook] [${_ts()}] getMatchingStopBuyOrders | token=${instrumentToken} livePrice=${livePrice} | matched=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
    return tradeIds;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] getMatchingStopBuyOrders error | token=${instrumentToken} livePrice=${livePrice} | ${err.message}`);
    return [];
  }
};

/**
 * Find all stop (SL/SL-M) SELL orders whose triggerPrice >= livePrice —
 * INVERTED from a LIMIT sell. A stop SELL (typically closing a long before
 * the loss grows) triggers once the price falls to/through the trigger, so
 * it fires when livePrice <= triggerPrice, i.e. all orders with score
 * (triggerPrice) >= livePrice.
 *
 * Returns array of tradeId strings.
 */
const getMatchingStopSellOrders = async (instrumentToken, livePrice) => {
  if (!redisService.isAvailable()) return [];

  try {
    const key = _stopSellKey(instrumentToken);
    const tradeIds = await redisService.getClient().zrangebyscore(key, livePrice, '+inf');
    if (LOG_REDIS_ORDERS && tradeIds.length > 0) {
      console.log(`🔍 [OrderBook] [${_ts()}] getMatchingStopSellOrders | token=${instrumentToken} livePrice=${livePrice} | matched=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
    return tradeIds;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] getMatchingStopSellOrders error | token=${instrumentToken} livePrice=${livePrice} | ${err.message}`);
    return [];
  }
};

/**
 * Bulk-remove a list of executed tradeIds from a given key.
 */
const removeMany = async (instrumentToken, side, tradeIds, orderType = 'LIMIT') => {
  if (!redisService.isAvailable() || tradeIds.length === 0) return;

  try {
    const key = _key(instrumentToken, side, orderType);
    await redisService.getClient().zrem(key, ...tradeIds);
    if (LOG_REDIS_ORDERS) {
      console.log(`📕 [OrderBook] [${_ts()}] removeMany | token=${instrumentToken} ${orderType} ${side} | removed=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] removeMany error | token=${instrumentToken} ${orderType} ${side} | ${err.message}`);
  }
};

/**
 * Bootstrap: load all pending LIMIT and SL/SL-M orders from MongoDB into
 * Redis. Called once at server startup so Redis is in sync with the DB.
 */
const syncFromDatabase = async () => {
  if (!redisService.isAvailable()) {
    console.log(`⚠️  [OrderBook] [${_ts()}] Redis unavailable – skipping bootstrap sync`);
    return;
  }

  try {
    const Trade = require('../models/Trade');
    // deleted_at: null — a trade admin-soft-deleted while still 'pending'
    // (deleteTrade only sets deleted_at, never touches status) must not be
    // revived into the live order book by this boot-time resync.
    const pendingTrades = await Trade.find({
      status: 'pending',
      order_type: { $in: ['LIMIT', 'SL', 'SL-M'] },
      deleted_at: null,
    });

    if (pendingTrades.length === 0) {
      console.log(`📗 [OrderBook] [${_ts()}] No pending orders to sync`);
      return;
    }

    const pipeline = redisService.getClient().pipeline();

    for (const trade of pendingTrades) {
      const key = _key(trade.instrument_token, trade.transaction_type, trade.order_type);
      pipeline.zadd(key, trade.price, trade._id.toString());
    }

    await pipeline.exec();
    console.log(`📗 [OrderBook] [${_ts()}] Synced ${pendingTrades.length} pending orders into Redis`);

    if (LOG_REDIS_ORDERS) {
      // Log each synced order for full traceability
      for (const trade of pendingTrades) {
        console.log(`   ↳ [OrderBook] synced tradeId=${trade._id} ${trade.order_type} ${trade.transaction_type} ${trade.tradingsymbol} @ ${trade.price} token=${trade.instrument_token}`);
      }
    }
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] syncFromDatabase error: ${err.message}`);
  }
};

/**
 * Verify a specific order exists in the Redis order book.
 * Useful for debugging "order placed but never triggered" issues.
 */
const verifyOrderExists = async (tradeId, instrumentToken, side, orderType = 'LIMIT') => {
  if (!redisService.isAvailable()) return { exists: false, reason: 'redis_unavailable' };

  try {
    const key = _key(instrumentToken, side, orderType);
    const score = await redisService.getClient().zscore(key, tradeId);
    const exists = score !== null;
    if (LOG_REDIS_ORDERS) {
      console.log(`🔎 [OrderBook] [${_ts()}] verifyOrderExists | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} | exists=${exists} score=${score}`);
    }
    return { exists, score: score ? parseFloat(score) : null, key };
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] verifyOrderExists error | tradeId=${tradeId} | ${err.message}`);
    return { exists: false, reason: 'error', error: err.message };
  }
};

/**
 * Get count of all orders in a specific key (for diagnostics).
 */
const getOrderCount = async (instrumentToken, side, orderType = 'LIMIT') => {
  if (!redisService.isAvailable()) return 0;

  try {
    const key = _key(instrumentToken, side, orderType);
    return await redisService.getClient().zcard(key);
  } catch (err) {
    return 0;
  }
};

module.exports = {
  addOrder,
  removeOrder,
  getMatchingBuyOrders,
  getMatchingSellOrders,
  getMatchingStopBuyOrders,
  getMatchingStopSellOrders,
  removeMany,
  syncFromDatabase,
  verifyOrderExists,
  getOrderCount,
};
