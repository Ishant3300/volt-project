/**
 * Admin-triggered batch square-off — closes every open position on a
 * segment (MCX, currently the only caller) system-wide, in batches, so the
 * admin can clear all client exposure ahead of manually closing that
 * segment's expiry (see the expiry-toggle endpoints in adminRoutes.js).
 *
 * Deliberately separate from marginSquareOffService.js: that one closes
 * ALL of a single user's positions in response to a live margin breach,
 * triggered per-tick. This one closes a specific SEGMENT's positions
 * across MANY users, triggered once by an admin action — different scope,
 * different trigger, but the same proven closing mechanics (real bid/ask
 * price, real P&L, wallet release, brokerage, Transaction record) are
 * reused here rather than re-derived.
 */
const mongoose = require('mongoose');
const Transaction = require('../models/Transaction');
const Trade = require('../models/Trade');
const User = require('../models/User');
const SquareOffRun = require('../models/SquareOffRun');
const { beginTradeWrite } = require('./tradeWriteFenceService');
const walletService = require('./walletService');
const { categoryForSegment } = require('../utils/walletCategory');
const { calculateBrokerage } = require('./brokerageService');

const BATCH_SIZE = 30;
const BATCH_PAUSE_MS = 500;

let _livePriceService = null;
function init(livePriceService) {
  _livePriceService = livePriceService;
}

/**
 * Closes every open MCX position for a single user, inside one transaction.
 * Mirrors marginSquareOffService.js's _squareOffAllPositions closing loop,
 * scoped to MCX-only positions (leaves any other segment's positions on
 * this same account completely untouched) and WITHOUT setting
 * margin_call_blocked — this is an expiry-driven close, not a margin
 * breach, so the account must stay free to trade other segments (or the
 * next MCX expiry once reopened) immediately after.
 */
async function _squareOffUserMcxPositions(userId, adminId) {
  const metricsEngine = require('./metricsEngine');
  const freshMetrics = await metricsEngine.getFreshMetrics(userId.toString());
  const mcxPositions = (freshMetrics?.positions || []).filter(
    (p) => (p.exchange || '').toUpperCase() === 'MCX' && Number(p.net_qty || 0) !== 0
  );
  if (mcxPositions.length === 0) return 0;

  const priceSnapshot = new Map();
  for (const position of mcxPositions) {
    priceSnapshot.set(position.instrument_token.toString(), {
      bid: Number(position.bid_price || position.cmp || position.ltp || 0),
      ask: Number(position.ask_price || position.cmp || position.ltp || 0),
      ltp: Number(position.ltp || 0),
    });
  }

  let lease = null;
  let session = null;
  let closed = 0;
  try {
    lease = await beginTradeWrite('admin_mcx_square_off');
    session = await mongoose.startSession();
    await session.withTransaction(async () => {
      await lease.assertActive({ session });
      const freshUser = await User.findById(userId).session(session);
      if (!freshUser) throw new Error('User no longer exists');

      for (const position of mcxPositions) {
        const netQty = Number(position.net_qty || 0);
        const closeType = netQty > 0 ? 'SELL' : 'BUY';
        const closeQty = Math.abs(netQty);
        const snapshot = priceSnapshot.get(position.instrument_token.toString()) || {};
        const closePrice = closeType === 'SELL'
          ? Number(snapshot.bid || snapshot.ltp || position.avg_buy_price || 0)
          : Number(snapshot.ask || snapshot.ltp || position.avg_sell_price || 0);
        if (!Number.isFinite(closePrice) || closePrice <= 0) {
          throw new Error(`No valid square-off price for ${position.tradingsymbol}`);
        }

        const pnl = netQty > 0
          ? (closePrice - position.avg_buy_price) * closeQty
          : (position.avg_sell_price - closePrice) * closeQty;
        const newTrade = new Trade({
          user_id: freshUser._id,
          master_id: freshUser.master_id,
          admin_id: freshUser.server_id,
          instrument_token: position.instrument_token,
          tradingsymbol: position.tradingsymbol,
          exchange: position.exchange,
          transaction_type: closeType,
          quantity: closeQty,
          price: closePrice,
          order_type: 'MARKET',
          placed_by: 'ADMIN',
          trade_type: 'admin_square_off',
          status: 'completed',
          executed_at: new Date(),
          executed_price: closePrice,
          executed_quantity: closeQty,
          pnl,
          brokerage: 0,
          taxes: 0,
          net_amount: pnl,
          remarks: 'ADMIN_MCX_SQUARE_OFF',
        });

        const brokerage = await calculateBrokerage(newTrade, session);
        newTrade.brokerage = brokerage;
        newTrade.net_amount = pnl - brokerage;
        await newTrade.save({ session });

        const avgEntry = netQty > 0 ? position.avg_buy_price : position.avg_sell_price;
        const releaseCategory = categoryForSegment(position.segment || position.exchange || '', position);
        if (closeQty > 0 && avgEntry > 0) {
          await walletService.release('User', freshUser._id, releaseCategory, closeQty * avgEntry, session);
        }

        const balanceBefore = Number(freshUser.equity || 0);
        const pnlNetBrokerage = pnl - brokerage;
        freshUser.equity = balanceBefore + pnlNetBrokerage;
        const transaction = new Transaction({
          transactionId: `TXN_${Date.now()}_${Math.random().toString(36).slice(2, 8)}_AMS`,
          userId: freshUser._id,
          userModel: 'User',
          type: closeType,
          status: 'SUCCESS',
          amount: closePrice * closeQty,
          referenceId: newTrade._id,
          referenceModel: 'Trade',
          balanceBefore,
          balanceAfter: freshUser.equity,
          metadata: {
            tradingsymbol: position.tradingsymbol,
            quantity: closeQty,
            executedPrice: closePrice,
            order_type: 'MARKET',
            realisedPnl: pnl,
            brokerage,
            reason: 'ADMIN_MCX_SQUARE_OFF',
            adminId: adminId ? adminId.toString() : null,
            positionClosed: true,
          },
        });
        await transaction.save({ session });
        closed++;
      }

      await lease.assertActive({ session });
      await freshUser.save({ session });
    });

    await metricsEngine.onTradeExecuted(userId.toString());
    _notifyUser(userId);
    return closed;
  } finally {
    if (session) await session.endSession();
    await lease?.release();
  }
}

function _notifyUser(userId) {
  if (_livePriceService) {
    _livePriceService.broadcastToUser(userId.toString(), {
      type: 'admin_square_off',
      message: 'Your MCX positions were closed by the admin ahead of expiry.',
    });
  }
  try {
    const firebaseService = require('./firebaseService');
    firebaseService.sendNotification(userId.toString(), 'admin_order_execution', {
      title: 'MCX positions closed',
      body: 'Your open MCX positions were closed by the admin ahead of expiry.',
      data: { reason: 'admin_square_off' },
    });
  } catch (_) {}
}

/**
 * Every distinct user currently holding a nonzero open MCX position,
 * computed authoritatively from completed trades (not the live metrics
 * cache) so a stale/cold cache can never under-count who needs closing.
 */
async function _findUsersWithOpenMcxPositions() {
  const rows = await Trade.aggregate([
    { $match: { exchange: 'MCX', status: 'completed', deleted_at: null } },
    {
      $group: {
        _id: { user_id: '$user_id', instrument_token: '$instrument_token' },
        netQty: {
          $sum: {
            $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', { $multiply: ['$executed_quantity', -1] }],
          },
        },
      },
    },
    { $match: { netQty: { $ne: 0 } } },
    { $group: { _id: '$_id.user_id' } },
  ]);
  return rows.map((r) => r._id);
}

/**
 * Starts a batch run, processing users BATCH_SIZE at a time with a short
 * pause between batches (avoids hammering the DB/price feed with hundreds
 * of concurrent transactions at once). Runs in the background — the caller
 * gets the run id immediately and polls its status separately, since this
 * can take a while with a lot of open positions.
 */
async function startMcxSquareOff(adminId) {
  const existing = await SquareOffRun.findOne({ segment: 'MCX', status: 'running' }).lean();
  if (existing) {
    const err = new Error('An MCX square-off run is already in progress');
    err.code = 'ALREADY_RUNNING';
    err.runId = existing._id;
    throw err;
  }

  const userIds = await _findUsersWithOpenMcxPositions();
  const run = await SquareOffRun.create({
    segment: 'MCX',
    status: 'running',
    triggered_by_admin_id: adminId || null,
    total_users: userIds.length,
    processed_users: 0,
    positions_closed: 0,
  });

  // Fire and forget — the HTTP caller polls /mcx-square-off/status/:id.
  _runBatches(run._id, userIds, adminId).catch(async (err) => {
    console.error('❌ [McxSquareOff] Run failed:', err.message);
    await SquareOffRun.findByIdAndUpdate(run._id, {
      status: 'failed', error: err.message, completed_at: new Date(),
    });
  });

  return { runId: run._id, totalUsers: userIds.length };
}

async function _runBatches(runId, userIds, adminId) {
  let processed = 0;
  let positionsClosed = 0;
  const failedUsers = [];

  for (let i = 0; i < userIds.length; i += BATCH_SIZE) {
    const batch = userIds.slice(i, i + BATCH_SIZE);
    const results = await Promise.allSettled(
      batch.map((userId) => _squareOffUserMcxPositions(userId, adminId))
    );

    for (let j = 0; j < results.length; j++) {
      const result = results[j];
      const userId = batch[j];
      if (result.status === 'fulfilled') {
        positionsClosed += result.value;
      } else {
        console.error(`⚠️  [McxSquareOff] Failed for user ${userId}:`, result.reason?.message);
        const user = await User.findById(userId).select('username').lean().catch(() => null);
        failedUsers.push({ user_id: userId, username: user?.username || null, error: result.reason?.message || 'Unknown error' });
      }
    }

    processed += batch.length;
    await SquareOffRun.findByIdAndUpdate(runId, {
      processed_users: processed,
      positions_closed: positionsClosed,
      failed_users: failedUsers,
    });

    if (i + BATCH_SIZE < userIds.length) {
      await new Promise((resolve) => setTimeout(resolve, BATCH_PAUSE_MS));
    }
  }

  await SquareOffRun.findByIdAndUpdate(runId, {
    status: 'completed',
    completed_at: new Date(),
  });
  console.log(`✅ [McxSquareOff] Run ${runId} completed: ${processed} users, ${positionsClosed} positions closed, ${failedUsers.length} failed`);
}

async function getRunStatus(runId) {
  return SquareOffRun.findById(runId).lean();
}

async function getLatestRun(segment = 'MCX') {
  return SquareOffRun.findOne({ segment }).sort({ createdAt: -1 }).lean();
}

module.exports = { init, startMcxSquareOff, getRunStatus, getLatestRun };
