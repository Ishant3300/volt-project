'use strict';

/**
 * Rollover — close selected open futures positions and reopen the same
 * qty/direction on each one's next-expiry contract (two real trades,
 * brokerage on both). POST /trade/rollover (tradeController) delegates here.
 *
 * Built for expiry-day load (every client pressing Rollover around the same
 * time):
 *  - Everything that can be checked without writing is checked FIRST, once
 *    per request — account, permissions, each position, its next contract,
 *    quantity limits, live prices — so a rejected position costs no
 *    transaction and every rejection says exactly why (e.g. the next
 *    contract is not open for rollover yet, and when it opens).
 *  - Brokerage rules, the user, instruments and script-qty limits are loaded
 *    once per request instead of once per position (brokerage alone used to
 *    re-read the user's whole ~600-row rate table twice per position).
 *  - One user's positions run one after another: every position writes the
 *    same User document (equity, wallet) and the same trade-write lease, so
 *    running them in parallel only produced write-conflict retries.
 *  - Metrics are recomputed once per request, not once per position.
 *  - Admission control (gate below): a bounded number of rollover requests
 *    run at once; one that cannot start within MAX_WAIT_MS is answered
 *    "busy — nothing was changed" at once, instead of finishing after the
 *    app's 10 s request timeout has already reported a failure.
 */

const mongoose = require('mongoose');
const KiteInstrument = require('../models/KiteInstrument');
const ScriptQuantity = require('../models/ScriptQuantity');
const Trade = require('../models/Trade');
const Transaction = require('../models/Transaction');
const User = require('../models/User');
const walletService = require('./walletService');
const { calculateBrokerage, loadBrokerageRules } = require('./brokerageService');
const { resolveNextExpiryInstrument } = require('./rolloverInstrumentService');
const { beginTradeWrite } = require('./tradeWriteFenceService');
const { categoryForSegment, categoryLabel } = require('../utils/walletCategory');
const { computeFlatResetState } = require('../utils/walletSplit');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

const MAX_ACTIVE = Number(process.env.ROLLOVER_MAX_ACTIVE) || 16;
const MAX_WAIT_MS = Number(process.env.ROLLOVER_MAX_WAIT_MS) || 4000;

/* ------------------------------------------------------ admission gate -- */

const gate = { active: 0, waiting: [] };

function busyError() {
  const e = new Error('Rollover is busy right now — nothing was changed. Please try again in a few seconds.');
  e.status = 503;
  e.code = 'ROLLOVER_BUSY';
  return e;
}

function enterGate() {
  if (gate.active < MAX_ACTIVE) {
    gate.active++;
    return Promise.resolve();
  }
  return new Promise((resolve, reject) => {
    const entry = { resolve, timer: null };
    entry.timer = setTimeout(() => {
      const i = gate.waiting.indexOf(entry);
      if (i >= 0) gate.waiting.splice(i, 1);
      reject(busyError());
    }, MAX_WAIT_MS);
    gate.waiting.push(entry);
  });
}

function leaveGate() {
  const next = gate.waiting.shift();
  if (next) {
    clearTimeout(next.timer);
    next.resolve(); // slot handed over; active count unchanged
  } else {
    gate.active--;
  }
}

/* -------------------------------------------------------------- helpers -- */

const round2 = (n) => Math.round(n * 100) / 100;
const escapeRegex = (s) => String(s).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function rejection(token, symbol, message) {
  return { token, tradingsymbol: symbol || null, message: symbol ? `${symbol}: ${message}` : message };
}

/** "Rollover to X opens on Thu 22 Oct" when the expiry schedule has a pending OPEN for it. */
async function notOpenMessage(newInstrument) {
  const ExpiryAction = require('../models/ExpiryAction');
  const day = new Date(newInstrument.expiry);
  const next = new Date(day);
  next.setUTCDate(next.getUTCDate() + 1);
  const open = await ExpiryAction.findOne({
    kind: 'OPEN',
    status: { $in: ['planned', 'confirmed', 'paused'] },
    targets: { $elemMatch: { name: new RegExp(`^${escapeRegex(newInstrument.name)}$`, 'i'), expiry: { $gte: day, $lt: next } } },
  }).select('action_date').lean().catch(() => null);
  if (open) {
    const label = new Date(`${open.action_date}T00:00:00Z`).toLocaleDateString('en-IN', { timeZone: 'UTC', weekday: 'short', day: 'numeric', month: 'short' });
    return `Rollover to ${newInstrument.tradingsymbol} opens on ${label}. The next contract isn't open for trading yet.`;
  }
  return `The next contract ${newInstrument.tradingsymbol} isn't open for trading yet, so this position can't be rolled over.`;
}

function priceOf(metricsEngine, token, side) {
  const ltp = metricsEngine._ltpMap?.get(token);
  return side === 'SELL' ? (metricsEngine._bidMap?.get(token) || ltp) : (metricsEngine._askMap?.get(token) || ltp);
}

/* ---------------------------------------------------- execution core -- */

function batchFallback(reason) {
  return Object.assign(new Error(reason), { code: 'BATCH_FALLBACK' });
}

/**
 * Roll `items` inside the caller's transaction and return the results.
 * Batch mode: any surprise (position changed, wallet short for the whole
 * batch) throws BATCH_FALLBACK so the caller retries one by one. Single
 * mode: throws the user-facing error for that one position.
 */
async function rollBatch({ user, rules, placedBy, lease }, items, session, { single = false } = {}) {
  const tokens = items.map((p) => p.token);
  const fresh = await Trade.find({ user_id: user._id, instrument_token: { $in: tokens }, status: 'completed', deleted_at: null })
    .select('instrument_token transaction_type executed_quantity executed_price executed_at createdAt')
    .sort({ executed_at: 1, createdAt: 1 })
    .session(session)
    .lean();
  const byToken = new Map();
  for (const t of fresh) {
    const k = t.instrument_token.toString();
    if (!byToken.has(k)) byToken.set(k, []);
    byToken.get(k).push(t);
  }

  const trades = [];
  const legs = [];
  const walletDelta = {}; // category -> net $inc
  const blockNeed = {}; // category -> what its balance must cover (blocks minus same-category releases)
  let equityDelta = 0;
  const baseTime = Date.now();

  for (const [i, p] of items.entries()) {
    // Re-read inside the transaction: a double tap or a trade placed
    // meanwhile must not be rolled twice or at a stale qty.
    const state = computeFlatResetState(byToken.get(p.token) || []);
    if (state.netQty === 0 || Math.sign(state.netQty) !== Math.sign(p.expectedNet)) {
      if (!single) throw batchFallback('position changed');
      throw new Error(state.netQty === 0 ? 'No open position to roll over.' : 'The position changed while rolling over. Please try again.');
    }
    const absQty = Math.abs(state.netQty);
    const originalSide = state.netQty > 0 ? 'BUY' : 'SELL';
    const closeSide = originalSide === 'BUY' ? 'SELL' : 'BUY';
    const newToken = p.newInstrument.instrument_token.toString();
    const avgBuy = state.totalBuyQty > 0 ? state.totalBuyValue / state.totalBuyQty : 0;
    const avgSell = state.totalSellQty > 0 ? state.totalSellValue / state.totalSellQty : 0;
    const closePnl = round2(originalSide === 'BUY' ? (p.closePrice - avgBuy) * absQty : (avgSell - p.closePrice) * absQty);
    const groupId = new mongoose.Types.ObjectId();
    const closeTime = new Date(baseTime + i * 2);
    const base = { user_id: user._id, master_id: user.master_id, admin_id: user.admin_id || null, order_type: 'MARKET', placed_by: placedBy, status: 'completed', rollover_group_id: groupId };

    const closeTrade = new Trade({
      ...base, instrument_token: p.token, tradingsymbol: p.oldInstrument.tradingsymbol, exchange: p.oldInstrument.exchange,
      transaction_type: closeSide, quantity: absQty, price: p.closePrice, executed_at: closeTime, executed_price: p.closePrice,
      executed_quantity: absQty, remarks: `Rollover close — reopening on ${p.newInstrument.tradingsymbol}`,
    });
    const closeBrokerage = await calculateBrokerage(closeTrade, session, { instrument: p.oldInstrument, rules });
    closeTrade.pnl = closePnl;
    closeTrade.brokerage = closeBrokerage;
    closeTrade.net_amount = round2(closePnl - closeBrokerage);

    const openTrade = new Trade({
      ...base, instrument_token: newToken, tradingsymbol: p.newInstrument.tradingsymbol, exchange: p.newInstrument.exchange,
      transaction_type: p.openSide, quantity: absQty, price: p.openPrice, executed_at: new Date(closeTime.getTime() + 1),
      executed_price: p.openPrice, executed_quantity: absQty, remarks: `Rollover reopen — closed out of ${p.oldInstrument.tradingsymbol}`,
    });
    const openBrokerage = await calculateBrokerage(openTrade, session, { instrument: p.newInstrument, rules });
    openTrade.pnl = 0;
    openTrade.brokerage = openBrokerage;
    openTrade.net_amount = round2(-openBrokerage);
    trades.push(closeTrade, openTrade);

    // The same amounts walletService.release/block would move (each rounded to paise).
    const closeCat = categoryForSegment(p.oldInstrument.segment || p.oldInstrument.exchange || '', p.oldInstrument);
    const openCat = categoryForSegment(p.newInstrument.segment || p.newInstrument.exchange || '', p.newInstrument);
    const releaseBasis = originalSide === 'BUY' ? avgBuy : avgSell;
    const releaseAmt = releaseBasis > 0 ? round2(absQty * releaseBasis) : 0;
    const blockAmt = round2(absQty * p.openPrice);
    if (!(blockAmt > 0)) throw new Error(`No valid reopen price for ${p.newInstrument.tradingsymbol}.`);
    walletDelta[closeCat] = (walletDelta[closeCat] || 0) + releaseAmt;
    walletDelta[openCat] = (walletDelta[openCat] || 0) - blockAmt;
    blockNeed[openCat] = (blockNeed[openCat] || 0) + blockAmt;
    if (releaseAmt) blockNeed[closeCat] = (blockNeed[closeCat] || 0) - releaseAmt;

    const legDelta = (closePnl - closeBrokerage) - openBrokerage;
    equityDelta += legDelta;
    legs.push({ p, absQty, closeSide, closeTrade, openTrade, closePnl, closeBrokerage, openBrokerage, legDelta, groupId, newToken });
  }

  await Trade.insertMany(trades, { session, ordered: true });

  // One guarded update for every wallet move and the equity change: a
  // category that ends up blocking more than it releases must be covered by
  // its current balance (the same guard walletService.block applies).
  const guard = { _id: user._id };
  for (const [cat, need] of Object.entries(blockNeed)) {
    if (round2(need) > 0) guard[`wallet.${cat}`] = { $gte: round2(need) };
  }
  const inc = { equity: equityDelta };
  for (const [cat, delta] of Object.entries(walletDelta)) inc[`wallet.${cat}`] = round2(delta);
  const before = await User.findOneAndUpdate(guard, { $inc: inc }, { session, new: false, projection: { equity: 1 } }).lean();
  if (!before) {
    if (!single) throw batchFallback('wallet short for the whole batch');
    const cat = Object.keys(blockNeed).find((c) => round2(blockNeed[c]) > 0) || '';
    throw Object.assign(new Error(`Insufficient ${categoryLabel(cat)} wallet balance`), { code: walletService.INSUFFICIENT_WALLET, category: cat });
  }

  let balance = Number(before.equity || 0);
  const txs = [];
  for (const l of legs) {
    const afterClose = balance + (l.closePnl - l.closeBrokerage);
    const afterOpen = balance + l.legDelta;
    txs.push({
      transactionId: `TXN_${Date.now()}_${Math.random().toString(36).slice(2, 8)}_RC`, userId: user._id, userModel: 'User', type: l.closeSide, status: 'SUCCESS',
      amount: l.p.closePrice * l.absQty, referenceId: l.closeTrade._id, referenceModel: 'Trade', balanceBefore: balance, balanceAfter: afterClose,
      metadata: { tradingsymbol: l.p.oldInstrument.tradingsymbol, quantity: l.absQty, executedPrice: l.p.closePrice, realisedPnl: l.closePnl, brokerage: l.closeBrokerage, rollover_group_id: l.groupId.toString(), rollover_leg: 'close' },
    }, {
      transactionId: `TXN_${Date.now()}_${Math.random().toString(36).slice(2, 8)}_RO`, userId: user._id, userModel: 'User', type: l.p.openSide, status: 'SUCCESS',
      amount: l.p.openPrice * l.absQty, referenceId: l.openTrade._id, referenceModel: 'Trade', balanceBefore: afterClose, balanceAfter: afterOpen,
      metadata: { tradingsymbol: l.p.newInstrument.tradingsymbol, quantity: l.absQty, executedPrice: l.p.openPrice, realisedPnl: 0, brokerage: l.openBrokerage, rollover_group_id: l.groupId.toString(), rollover_leg: 'open' },
    });
    balance = afterOpen;
  }
  await Transaction.insertMany(txs, { session, ordered: true });

  await lease.assertActive({ session });
  return legs.map((l) => ({
    rollover_group_id: l.groupId.toString(),
    old: { token: l.p.token, tradingsymbol: l.p.oldInstrument.tradingsymbol, price: l.p.closePrice, brokerage: l.closeBrokerage, pnl: l.closePnl },
    new: { token: l.newToken, tradingsymbol: l.p.newInstrument.tradingsymbol, price: l.p.openPrice, brokerage: l.openBrokerage },
    qty: l.absQty,
  }));
}

/* ------------------------------------------------------------ rollover -- */

/**
 * @param {object} params
 * @param {string} params.targetUserId
 * @param {string[]} params.tokens
 * @param {{isAdmin: boolean, masterId: string|null}} params.actor
 * @returns {Promise<{rolled_over: object[], errors: object[]}>}
 */
async function rolloverPositions({ targetUserId, tokens, actor }) {
  await enterGate();
  let lease = null;
  try {
    const metricsEngine = require('./metricsEngine');
    const livePriceService = require('./livePriceService');
    const uniqueTokens = [...new Set(tokens.map((t) => t.toString()))];
    const errors = [];
    const rolled = [];
    const placedBy = actor.isAdmin ? 'ADMIN' : (actor.masterId ? 'MASTER' : 'USER');

    const user = await User.findById(targetUserId).lean();
    if (!user) throw Object.assign(new Error('User not found'), { status: 404 });
    if (actor.masterId) {
      const { getAllSubMasterIds } = require('./masterHierarchyService');
      const allowed = await getAllSubMasterIds(actor.masterId);
      if (!user.master_id || !allowed.includes(user.master_id.toString())) {
        throw Object.assign(new Error('Not authorized to roll over a position for this user'), { status: 403 });
      }
    }

    // ── Load everything once ──────────────────────────────────────────────
    const oldInstruments = new Map(
      (await KiteInstrument.find({ instrument_token: { $in: uniqueTokens } }).lean()).map((i) => [i.instrument_token.toString(), i]),
    );
    const tradesByToken = new Map();
    for (const t of await Trade.find({ user_id: user._id, instrument_token: { $in: uniqueTokens }, status: 'completed', deleted_at: null })
      .select('instrument_token transaction_type executed_quantity executed_price executed_at createdAt')
      .sort({ executed_at: 1, createdAt: 1 })
      .lean()) {
      const k = t.instrument_token.toString();
      if (!tradesByToken.has(k)) tradesByToken.set(k, []);
      tradesByToken.get(k).push(t);
    }

    // ── Validate each position; build the plan ────────────────────────────
    const accountBlock = (() => {
      if (actor.isAdmin) return null;
      if (user.bet === false) return 'Trading is currently disabled for your account.';
      if (user.close_only === true) return 'Your account is in close-only mode. You can only close existing positions.';
      if (user.margin_call_blocked === true) return 'Trading is blocked: a margin square-off already closed all your positions. Contact your master/admin to add credit and resume.';
      // Not applied here: placeTrade's "live M2M loss has reached your full
      // credit" block. With a negative balance new orders stay blocked
      // (closing only), but Rollover is still allowed — it only moves an
      // existing open position to the next contract at the same qty and
      // side, never adds exposure. The wallet check on the reopen leg still
      // applies (a position whose new contract the wallet can't cover is
      // refused with the reason; the others still roll).
      return null;
    })();

    const plan = [];
    for (const token of uniqueTokens) {
      const oldInstrument = oldInstruments.get(token);
      if (!oldInstrument) { errors.push(rejection(token, null, 'Instrument not found.')); continue; }
      const sym = oldInstrument.tradingsymbol;
      const state = computeFlatResetState(tradesByToken.get(token) || []);
      if (state.netQty === 0) { errors.push(rejection(token, sym, 'No open position to roll over.')); continue; }
      if (!oldInstrument.expiry || String(sym).toUpperCase() === 'GIFT NIFTY') {
        errors.push(rejection(token, sym, 'This is a continuous contract — it moves to the next month by itself, no rollover needed.'));
        continue;
      }
      const newInstrument = await resolveNextExpiryInstrument(oldInstrument);
      if (!newInstrument) { errors.push(rejection(token, sym, "The next contract isn't available yet, so this position can't be rolled over.")); continue; }
      if (newInstrument.deleted_at) { errors.push(rejection(token, sym, 'Admin has deactivated the next-expiry script. Rollover is not allowed.')); continue; }
      if (newInstrument.enabled === false) { errors.push(rejection(token, sym, await notOpenMessage(newInstrument))); continue; }
      if (accountBlock) { errors.push(rejection(token, sym, accountBlock)); continue; }

      const rawSegment = (newInstrument.segment || newInstrument.exchange || '').toUpperCase();
      if (!actor.isAdmin) {
        const candidates = new Set([rawSegment]);
        if (rawSegment === 'GLOBAL') candidates.add('INDICES');
        if (rawSegment === 'INDICES') candidates.add('GLOBAL');
        // Only a ticked row (turnover or lot on) grants the exchange.
        const { isUserExchangeRowAllowed } = require('../utils/exchangeAccess');
        const hasAccess = (user.exchanges_allowed || []).some((ex) => {
          if (!isUserExchangeRowAllowed(ex)) return false;
          const name = (ex.exchange_name || '').toUpperCase();
          return candidates.has(name) || candidates.has(name === 'INDICES' ? 'GLOBAL' : name);
        });
        if (!hasAccess) { errors.push(rejection(token, sym, `Your account is not permitted to trade ${rawSegment || 'this instrument'}. Contact your master/admin.`)); continue; }
      }
      const openSide = state.netQty > 0 ? 'BUY' : 'SELL';
      if (['CE', 'PE'].includes(newInstrument.instrument_type) && openSide === 'SELL') {
        errors.push(rejection(token, sym, 'Option selling is not allowed. You must own this option before you can sell it — a short option position cannot be rolled over.'));
        continue;
      }
      plan.push({ token, oldInstrument, newInstrument, rawSegment, openSide, expectedNet: state.netQty });
    }

    // Script-quantity max_qty gate — the reopen leg is a fresh position, so the whole qty counts.
    if (plan.length) {
      const exchanges = [...new Set(plan.map((p) => (p.rawSegment === 'GLOBAL' ? 'INDICES' : p.rawSegment)))];
      const names = [...new Set(plan.flatMap((p) => [p.newInstrument.raw_name || p.newInstrument.name, p.newInstrument.tradingsymbol].filter(Boolean)))];
      const limits = await ScriptQuantity.find({ owner_id: user._id, exchange_name: { $in: exchanges }, script_name: { $in: names }, deleted_at: null }).lean();
      const limitFor = (ex, name) => limits.find((l) => l.exchange_name === ex && l.script_name === name);
      for (let i = plan.length - 1; i >= 0; i--) {
        const p = plan[i];
        const ex = p.rawSegment === 'GLOBAL' ? 'INDICES' : p.rawSegment;
        const cfg = user.exchanges_allowed?.find((e) => (e.exchange_name || '').toUpperCase() === ex);
        const rawName = p.newInstrument.raw_name || p.newInstrument.name || null;
        const sq = (rawName && limitFor(ex, rawName)) || limitFor(ex, p.newInstrument.tradingsymbol);
        const limit = sq?.max_qty ?? null;
        // max_qty 0 = script not tradable for this account (same rule as placeTrade) —
        // the reopen would be a fresh position, so it's refused and the old one kept.
        if (limit === 0) {
          errors.push(rejection(p.token, p.oldInstrument.tradingsymbol, `${rawName || p.newInstrument.tradingsymbol} is not allowed for this account — no quantity allotted (max 0). Square it off instead of rolling over.`));
          plan.splice(i, 1);
          continue;
        }
        if (!(cfg?.turnover === true || cfg?.lot === true)) continue;
        if (limit === null || !(limit > 0)) continue;
        const absQty = Math.abs(p.expectedNet);
        const lotSize = sq?.lot_size || p.newInstrument.lot_size || 1;
        const requested = cfg.lot === true ? Math.ceil(absQty / lotSize) : absQty;
        if (requested > limit) {
          const unit = cfg.lot === true ? 'lot(s)' : 'qty';
          errors.push(rejection(p.token, p.oldInstrument.tradingsymbol, `Rollover exceeds the current maximum position limit for ${p.newInstrument.tradingsymbol}. Max: ${limit} ${unit}, Requested: ${requested} ${unit}. Square off the excess manually before rolling over.`));
          plan.splice(i, 1);
        }
      }
    }

    // Live prices — the new contract must be on the feed.
    for (let i = plan.length - 1; i >= 0; i--) {
      const p = plan[i];
      const closeSide = p.openSide === 'BUY' ? 'SELL' : 'BUY';
      const newToken = p.newInstrument.instrument_token.toString();
      p.closePrice = priceOf(metricsEngine, p.token, closeSide);
      p.openPrice = priceOf(metricsEngine, newToken, p.openSide);
      if (!p.closePrice || p.closePrice <= 0) {
        errors.push(rejection(p.token, p.oldInstrument.tradingsymbol, 'No live price available right now. Please try again in a few seconds.'));
        plan.splice(i, 1);
      } else if (!p.openPrice || p.openPrice <= 0) {
        livePriceService.ensureSubscribed([newToken]);
        errors.push(rejection(p.token, p.oldInstrument.tradingsymbol, `No live price for ${p.newInstrument.tradingsymbol} yet. Please try again in a few seconds.`));
        plan.splice(i, 1);
      }
    }

    if (plan.length === 0) return { rolled_over: rolled, errors };

    // ── Execute ──────────────────────────────────────────────────────────
    // Fast path: every position in ONE transaction (~5 database operations
    // for the whole request instead of ~9 per position — what matters when
    // the database caps operations per second). If the batch can't go as a
    // whole (a position changed meanwhile, or the wallet can't cover all the
    // reopens together), fall back to one transaction per position so each
    // gets its own exact result.
    const rules = await loadBrokerageRules(user._id);
    lease = await beginTradeWrite('rollover');
    const ctx = { user, rules, placedBy, lease };

    let batchDone = false;
    if (plan.length > 1) {
      const session = await mongoose.startSession();
      try {
        let committed = null;
        await session.withTransaction(async () => {
          committed = await rollBatch(ctx, plan, session);
        });
        if (committed) { rolled.push(...committed); batchDone = true; }
      } catch (error) {
        if (error.code === 'TRADE_WRITE_LEASE_LOST') throw error;
        // BATCH_FALLBACK or any other failure: retry position by position below.
      } finally {
        await session.endSession();
      }
    }

    if (!batchDone) {
      for (const p of plan) {
        const session = await mongoose.startSession();
        try {
          let committed = null;
          await session.withTransaction(async () => {
            committed = await rollBatch(ctx, [p], session, { single: true });
          });
          if (committed) rolled.push(...committed);
        } catch (error) {
          if (error.code === 'TRADE_WRITE_LEASE_LOST') throw error;
          const message = error.code === walletService.INSUFFICIENT_WALLET
            ? `Insufficient ${error.category || ''} wallet balance to reopen on ${p.newInstrument.tradingsymbol}.`.replace('  ', ' ')
            : sanitizeErrorMessage(error);
          errors.push(rejection(p.token, p.oldInstrument.tradingsymbol, message));
        } finally {
          await session.endSession();
        }
      }
    }

    if (rolled.length) {
      await metricsEngine.onTradeExecuted(targetUserId.toString());
      for (const r of rolled) {
        livePriceService.broadcastToUser(targetUserId.toString(), {
          type: 'rollover_executed',
          rollover_group_id: r.rollover_group_id,
          old_instrument_token: r.old.token,
          new_instrument_token: r.new.token,
          new_tradingsymbol: r.new.tradingsymbol,
          quantity: r.qty,
        });
      }
    }
    return { rolled_over: rolled, errors };
  } finally {
    await lease?.release();
    leaveGate();
  }
}

module.exports = { rolloverPositions, _private: { gate, enterGate, leaveGate, MAX_ACTIVE, MAX_WAIT_MS } };
