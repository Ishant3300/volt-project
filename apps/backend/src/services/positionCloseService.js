'use strict';

/**
 * Close every open position on a set of instruments, across all users —
 * the closing routine that used to live inline in cronService's
 * autoSquareOffExpiredPositions (expiry-day safety net), shared now with the
 * admin-confirmed expiry cut (expiryActionService.js).
 *
 * Per (user, instrument): its own MongoDB transaction that re-reads the
 * position fresh, books the close trade at `priceFor(token, closeSide)`,
 * brokerage, wallet release of the entry notional, equity P&L and a
 * Transaction audit row, and proves the caller's trade-write lease before
 * committing. Bounded concurrency; each task has its own session and never
 * throws, so a lost lease is only acted on after the whole chunk settled.
 */

const mongoose = require('mongoose');
const Trade = require('../models/Trade');
const User = require('../models/User');
const Transaction = require('../models/Transaction');
const walletService = require('./walletService');
const { categoryForSegment } = require('../utils/walletCategory');

const CONCURRENCY = 5;

/**
 * @param {object} params
 * @param {Array<{instrument_token, tradingsymbol, exchange, segment}>} params.instruments
 * @param {(token: string, closeSide: 'BUY'|'SELL') => number} params.priceFor - closing price; <= 0 / NaN skips
 * @param {object} params.lease - active trade-write lease (tradeWriteFenceService)
 * @param {{placed_by: string, trade_type: string, remarks: (symbol: string) => string}} params.trade
 * @param {string} params.reason - Transaction metadata.reason
 * @param {string} params.txSuffix - Transaction id suffix
 * @param {(userId: string) => void} [params.onUserClosed] - after metrics refresh, per committed close
 * @param {Function} [params.faultInjector] - tests only
 * @returns {Promise<{squared: number, skipped: Array, failures: Array, openPositions: number}>}
 */
async function closeOpenPositions({ instruments, priceFor, lease, trade, reason, txSuffix, onUserClosed, faultInjector }) {
  const metricsEngine = require('./metricsEngine');
  const { calculateBrokerage } = require('./brokerageService');
  const infoByToken = new Map(instruments.map((i) => [i.instrument_token.toString(), i]));
  const tokens = [...infoByToken.keys()];
  const result = { squared: 0, skipped: [], failures: [], openPositions: 0 };
  if (tokens.length === 0) return result;

  const openPositions = await Trade.aggregate([
    { $match: { instrument_token: { $in: tokens }, status: 'completed', deleted_at: null } },
    { $group: {
      _id: { user_id: '$user_id', instrument_token: '$instrument_token' },
      net_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', { $multiply: ['$executed_quantity', -1] }] } },
    } },
    { $match: { net_qty: { $ne: 0 } } },
  ]);
  result.openPositions = openPositions.length;

  const processCandidate = async (candidate) => {
    const token = candidate._id.instrument_token.toString();
    const userId = candidate._id.user_id;
    const inst = infoByToken.get(token);
    const expectedSide = candidate.net_qty > 0 ? 'SELL' : 'BUY';
    const expectedPrice = Number(priceFor(token, expectedSide));
    if (!Number.isFinite(expectedPrice) || expectedPrice <= 0) return { skipped: true, userId, inst };

    const session = await mongoose.startSession();
    let committed = null;
    try {
      await session.withTransaction(async () => {
        committed = null;
        await lease.assertActive({ session });
        const fresh = await Trade.aggregate([
          { $match: { user_id: userId, instrument_token: token, status: 'completed', deleted_at: null } },
          { $group: {
            _id: null,
            net_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', { $multiply: ['$executed_quantity', -1] }] } },
            total_buy_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', 0] } },
            total_sell_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, '$executed_quantity', 0] } },
            total_buy_value: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, { $multiply: ['$executed_quantity', '$executed_price'] }, 0] } },
            total_sell_value: { $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, { $multiply: ['$executed_quantity', '$executed_price'] }, 0] } },
          } },
        ]).session(session);
        const netQty = Number(fresh[0]?.net_qty || 0);
        if (netQty === 0) return;

        // Avg entry from the trade legs — releases the ENTRY notional
        // (independent of the exit price) and gives the real realised P&L.
        const buyQty = Number(fresh[0]?.total_buy_qty || 0);
        const sellQty = Number(fresh[0]?.total_sell_qty || 0);
        const avgBuy = buyQty > 0 ? Number(fresh[0].total_buy_value || 0) / buyQty : 0;
        const avgSell = sellQty > 0 ? Number(fresh[0].total_sell_value || 0) / sellQty : 0;
        const avgEntry = netQty > 0 ? avgBuy : avgSell;
        const releaseCategory = categoryForSegment(inst.segment || inst.exchange || '', inst);

        const user = await User.findById(userId).session(session);
        if (!user) throw new Error(`User ${userId} not found`);
        const absQty = Math.abs(netQty);
        const closeSide = netQty > 0 ? 'SELL' : 'BUY';
        const price = closeSide === expectedSide ? expectedPrice : Number(priceFor(token, closeSide));
        if (!Number.isFinite(price) || price <= 0) throw new Error(`No valid closing price for ${inst.tradingsymbol}`);

        const pnl = netQty > 0 ? (price - avgBuy) * absQty : (avgSell - price) * absQty;

        const newTrade = new Trade({
          user_id: userId,
          master_id: user.master_id,
          admin_id: user.admin_id || null,
          instrument_token: token,
          tradingsymbol: inst.tradingsymbol,
          exchange: inst.exchange,
          transaction_type: closeSide,
          quantity: absQty,
          price,
          order_type: 'MARKET',
          placed_by: trade.placed_by,
          trade_type: trade.trade_type,
          status: 'completed',
          executed_at: new Date(),
          executed_price: price,
          executed_quantity: absQty,
          pnl,
          remarks: trade.remarks(inst.tradingsymbol),
        });
        const brokerage = await calculateBrokerage(newTrade, session);
        newTrade.brokerage = brokerage;
        newTrade.net_amount = pnl - brokerage;
        await newTrade.save({ session });

        if (absQty > 0 && avgEntry > 0) {
          await walletService.release('User', userId, releaseCategory, absQty * avgEntry, session);
        }

        const balanceBefore = Number(user.equity || 0);
        user.equity = balanceBefore + (pnl - brokerage);
        await user.save({ session });

        await new Transaction({
          transactionId: `TXN_${Date.now()}_${Math.random().toString(36).slice(2, 8)}_${txSuffix}`,
          userId,
          userModel: 'User',
          type: closeSide,
          status: 'SUCCESS',
          amount: price * absQty,
          referenceId: newTrade._id,
          referenceModel: 'Trade',
          balanceBefore,
          balanceAfter: user.equity,
          metadata: {
            tradingsymbol: inst.tradingsymbol,
            quantity: absQty,
            executedPrice: price,
            order_type: 'MARKET',
            realisedPnl: pnl,
            brokerage,
            reason,
            positionClosed: true,
          },
        }).save({ session });

        if (faultInjector) {
          await faultInjector({ phase: 'before_final_lease_proof', lease, session, userId, instrumentToken: token });
        }
        await lease.assertActive({ session });
        committed = { absQty, closeSide, pnl, price };
      });
      return { committed, userId, inst, error: null, leaseLost: false };
    } catch (error) {
      return { committed: null, userId, inst, error, leaseLost: error.code === 'TRADE_WRITE_LEASE_LOST' };
    } finally {
      await session.endSession();
    }
  };

  for (let i = 0; i < openPositions.length; i += CONCURRENCY) {
    const outcomes = await Promise.all(openPositions.slice(i, i + CONCURRENCY).map(processCandidate));
    for (const outcome of outcomes) {
      if (outcome.skipped) {
        result.skipped.push({ user_id: outcome.userId, symbol: outcome.inst.tradingsymbol, error: 'No valid closing price' });
        continue;
      }
      if (outcome.committed) {
        await metricsEngine.onTradeExecuted(outcome.userId.toString());
        result.squared++;
        if (onUserClosed) onUserClosed(outcome.userId.toString());
        console.log(`   ✅ Squared off ${outcome.inst.tradingsymbol}: ${outcome.committed.closeSide} ${outcome.committed.absQty} @ ${outcome.committed.price} for user ${outcome.userId}, P&L: ₹${outcome.committed.pnl.toFixed(2)}`);
      } else if (outcome.leaseLost) {
        throw outcome.error;
      } else if (outcome.error) {
        console.error(`   ❌ Failed to square off ${outcome.inst.tradingsymbol} for user ${outcome.userId}: ${outcome.error.message}`);
        result.failures.push({ user_id: outcome.userId, symbol: outcome.inst.tradingsymbol, error: outcome.error.message });
      }
    }
  }
  return result;
}

/**
 * Closing price: a long closes by SELLING at the bid, a short by BUYING at
 * the ask; the last traded price when that side has no quote.
 */
function bidAskPrice(quote, closeSide) {
  if (!quote) return 0;
  const side = closeSide === 'SELL' ? quote.bid : quote.ask;
  return Number(side) > 0 ? Number(side) : Number(quote.ltp) || 0;
}

module.exports = { closeOpenPositions, bidAskPrice };
