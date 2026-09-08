/**
 * Order Book Service  (Redis-backed)
 *
 * Uses Redis Sorted Sets to maintain an in-memory order book.
 *
 * Key schema
 * ----------
 *   ob:{instrument_token}:buy       – LIMIT buys,  score = limitPrice
 *   ob:{instrument_token}:sell      – LIMIT sells, score = limitPrice
 *   ob:{instrument_token}:stoprise  – SL/SL-M orders that fire when price RISES to/through the trigger, score = triggerPrice
 *   ob:{instrument_token}:stopfall  – SL/SL-M orders that fire when price FALLS to/through the trigger, score = triggerPrice
 *
 * Each member is the trade's MongoDB _id (string).
 *
 * Why direction (RISE/FALL), not side (BUY/SELL), for stop orders?
 *   The old schema keyed stop orders by transaction_type — SL BUY always
 *   fired on a rise, SL SELL always fired on a fall, regardless of where
 *   the trigger actually sat relative to the live price at placement. A
 *   SELL stop placed ABOVE the live price (e.g. a fresh breakout-short
 *   entry) got treated as "already true" and instant-filled, because
 *   "price <= trigger" is trivially satisfied the moment the trigger is
 *   above where price already is. The real, universal rule for a stop
 *   order is direction-agnostic to BUY/SELL: it fires once price reaches
 *   the trigger from whichever side it started on. `Trade.trigger_direction`
 *   is decided ONCE at placement (tradeController.js) by comparing the
 *   trigger to the live price at that exact moment, then stored — this
 *   service just keys off that stored decision at match time. Legacy trades
 *   placed before this field existed have `trigger_direction: null`; every
 *   function below falls back to the OLD transaction_type mapping in that
 *   case (`_legacyDirection`), so a pending order from before this change
 *   keeps matching exactly as it always did.
 *
 * Why two separate pairs of sets for LIMIT vs stop orders, not one?
 *   A LIMIT BUY and a stop RISE order trigger on OPPOSITE price movement:
 *   a LIMIT buyer wants to buy once the price falls to/below their price
 *   (an entry), while a stop-rise order fires once price rises to/above its
 *   trigger. Storing both in the same sorted set and querying with the same
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
const _stopRiseKey = (token) => `ob:${token}:stoprise`;
const _stopFallKey = (token) => `ob:${token}:stopfall`;

const _isStop = (orderType) => orderType === 'SL' || orderType === 'SL-M';

/** Pre-trigger_direction fallback: SL BUY => RISE, SL SELL => FALL (the old hardcoded rule). */
const _legacyDirection = (side) => (side === 'BUY' ? 'RISE' : 'FALL');

const _key = (instrumentToken, side, orderType, direction) => {
  const stop = _isStop(orderType);
  if (!stop) return side === 'BUY' ? _buyKey(instrumentToken) : _sellKey(instrumentToken);
  const dir = direction || _legacyDirection(side);
  return dir === 'FALL' ? _stopFallKey(instrumentToken) : _stopRiseKey(instrumentToken);
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
 * @param {'RISE'|'FALL'|null} [direction=null] – SL/SL-M only; ignored for LIMIT
 */
const addOrder = async (tradeId, instrumentToken, limitPrice, side, orderType = 'LIMIT', direction = null) => {
  if (!redisService.isAvailable()) {
    console.log(`🔴 [OrderBook] [${_ts()}] addOrder FAILED — Redis unavailable | tradeId=${tradeId} token=${instrumentToken} ${orderType} ${side} @ ${limitPrice} | diagnostics=${JSON.stringify(redisService.getDiagnostics())}`);
    return false;
  }

  try {
    const key = _key(instrumentToken, side, orderType, direction);
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
 * Find all stop (SL/SL-M) orders whose trigger fires on a RISE and whose
 * triggerPrice <= livePrice — i.e. price has risen to/through the trigger.
 *
 * Returns array of tradeId strings.
 */
const getMatchingStopRiseOrders = async (instrumentToken, livePrice) => {
  if (!redisService.isAvailable()) return [];

  try {
    const key = _stopRiseKey(instrumentToken);
    const tradeIds = await redisService.getClient().zrangebyscore(key, '-inf', livePrice);
    if (LOG_REDIS_ORDERS && tradeIds.length > 0) {
      console.log(`🔍 [OrderBook] [${_ts()}] getMatchingStopRiseOrders | token=${instrumentToken} livePrice=${livePrice} | matched=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
    return tradeIds;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] getMatchingStopRiseOrders error | token=${instrumentToken} livePrice=${livePrice} | ${err.message}`);
    return [];
  }
};

/**
 * Find all stop (SL/SL-M) orders whose trigger fires on a FALL and whose
 * triggerPrice >= livePrice — i.e. price has fallen to/through the trigger.
 *
 * Returns array of tradeId strings.
 */
const getMatchingStopFallOrders = async (instrumentToken, livePrice) => {
  if (!redisService.isAvailable()) return [];

  try {
    const key = _stopFallKey(instrumentToken);
    const tradeIds = await redisService.getClient().zrangebyscore(key, livePrice, '+inf');
    if (LOG_REDIS_ORDERS && tradeIds.length > 0) {
      console.log(`🔍 [OrderBook] [${_ts()}] getMatchingStopFallOrders | token=${instrumentToken} livePrice=${livePrice} | matched=${tradeIds.length} ids=[${tradeIds.join(',')}]`);
    }
    return tradeIds;
  } catch (err) {
    console.error(`❌ [OrderBook] [${_ts()}] getMatchingStopFallOrders error | token=${instrumentToken} livePrice=${livePrice} | ${err.message}`);
    return [];
  }
};

/**
 * Bulk-remove a list of executed tradeIds from a given key.
 * @param {'RISE'|'FALL'|null} [direction=null] – SL/SL-M only; ignored for LIMIT
 */
const removeMany = async (instrumentToken, side, tradeIds, orderType = 'LIMIT', direction = null) => {
  if (!redisService.isAvailable() || tradeIds.length === 0) return;

  try {
    const key = _key(instrumentToken, side, orderType, direction);
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
      const key = _key(trade.instrument_token, trade.transaction_type, trade.order_type, trade.trigger_direction);
      pipeline.zadd(key, trade.price, trade._id.toString());
    }

    await pipeline.exec();
    console.log(`📗 [OrderBook] [${_ts()}] Synced ${pendingTrades.length} pending orders into Redis`);

    // Being present in the Redis sorted set is not enough on its own — price
    // ticks only reach the matcher for instruments actually subscribed on
    // the Kite feed, and the only thing that adds one is
    // livePriceService.addPendingToken() (normally called once at fresh
    // order placement). Without this, an order synced here after a restart
    // sits correctly in Redis but never receives a tick and can never
    // trigger, while orderConsistencyAudit reports it as consistent since
    // it IS in Redis — masking the exact gap this sync exists to close.
    const livePriceService = require('./livePriceService');
    for (const trade of pendingTrades) {
      livePriceService.addPendingToken(trade.instrument_token);
    }

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
const verifyOrderExists = async (tradeId, instrumentToken, side, orderType = 'LIMIT', direction = null) => {
  if (!redisService.isAvailable()) return { exists: false, reason: 'redis_unavailable' };

  try {
    const key = _key(instrumentToken, side, orderType, direction);
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
 * For stop orders, pass orderType='SL' and a direction ('RISE'|'FALL');
 * `side` is ignored for stop orders since the key is direction-keyed, not
 * side-keyed — pass null.
 */
const getOrderCount = async (instrumentToken, side, orderType = 'LIMIT', direction = null) => {
  if (!redisService.isAvailable()) return 0;

  try {
    const key = _key(instrumentToken, side, orderType, direction);
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
  getMatchingStopRiseOrders,
  getMatchingStopFallOrders,
  removeMany,
  syncFromDatabase,
  verifyOrderExists,
  getOrderCount,
};
