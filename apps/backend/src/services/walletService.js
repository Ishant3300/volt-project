'use strict';

/**
 * walletService — the single choke point for every category-wallet balance
 * change (design §5 / §D1 / §12).
 *
 * Each User/Master stores `wallet.{NSE,MCX,GLOBAL}` = the *available* (spendable)
 * balance for that category. This number is the source of truth for the
 * affordability gate and for displayed equity. All mutations flow through the
 * helpers below so the never-negative and atomic guarantees hold everywhere:
 *
 *   - block()   opens/reserves margin via a single guarded atomic `$inc`. This
 *               is the one write-conflict point that makes concurrent opens
 *               race-free and never-negative (design §D1).
 *   - release() returns margin on close/reduce (never guarded; always allowed).
 *   - assign()  funds a target down the hierarchy (master transfer / admin grant).
 *   - withdraw() pulls funds back from a target (guarded on the target).
 *   - getAvailable() reads the current per-category balances.
 *   - reconcile()   recomputes blocked margin from open positions (drift audit).
 *
 * Every method is session-aware: pass the caller's Mongo transaction session so
 * wallet mutations commit/roll back atomically with the trade (or transfer)
 * write. `assign`/`withdraw` will open and own a transaction if none is passed.
 *
 * All amounts are rounded to 2-decimal money precision before they touch the DB.
 *
 * @module services/walletService
 */

const mongoose = require('mongoose');
const User = require('../models/User');
const Master = require('../models/Master');
const Transaction = require('../models/Transaction');
const Trade = require('../models/Trade');
const KiteInstrument = require('../models/KiteInstrument');
const { categoryForSegment, CATEGORY_ORDER } = require('../utils/walletCategory');

/** Error `code` thrown when a guarded balance move cannot be covered. */
const INSUFFICIENT_WALLET = 'INSUFFICIENT_WALLET';

/** Valid category pools (matches the wallet sub-schema on User/Master) — the single list in utils/walletCategory.js. */
const CATEGORIES = CATEGORY_ORDER;

/** Owner/target model discriminators that resolve to a Mongoose model. */
const OWNER_MODELS = Object.freeze({ User, Master });

/**
 * Round a value to 2-decimal money precision.
 *
 * Uses the `+ Number.EPSILON` nudge before scaling so values that are a hair
 * below a cent boundary in IEEE-754 (e.g. 1.005 stored as 1.00499999…) round
 * the way a human expects rather than truncating down. Defined locally on
 * purpose so walletService owns its own money rounding.
 *
 * @param {number} value
 * @returns {number} value rounded to 2 decimals
 */
function roundMoney(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

/**
 * Resolve a `'User' | 'Master'` discriminator to its Mongoose model.
 * @param {'User'|'Master'} ownerModel
 * @returns {import('mongoose').Model<any>}
 */
function resolveModel(ownerModel) {
  const Model = OWNER_MODELS[ownerModel];
  if (!Model) {
    throw new Error(`walletService: unknown owner model "${ownerModel}" (expected 'User' or 'Master')`);
  }
  return Model;
}

/**
 * Validate a category pool name.
 * @param {'NSE'|'MCX'|'GLOBAL'} category
 */
function assertCategory(category) {
  if (!CATEGORIES.includes(category)) {
    throw new Error(`walletService: invalid category "${category}" (expected one of ${CATEGORIES.join(', ')})`);
  }
}

/**
 * Validate and round a money amount that must be strictly positive.
 * @param {number} amount
 * @returns {number} the rounded, validated amount
 */
function assertPositiveAmount(amount) {
  const rounded = roundMoney(amount);
  if (!Number.isFinite(rounded) || rounded <= 0) {
    throw new Error(`walletService: amount must be a positive number (got ${amount})`);
  }
  return rounded;
}

/** Normalise an id (string or ObjectId) to an ObjectId for aggregation `$match`. */
function toObjectId(id) {
  if (id instanceof mongoose.Types.ObjectId) return id;
  return new mongoose.Types.ObjectId(String(id));
}

/** Build an INSUFFICIENT_WALLET error carrying the category + requested amount. */
function insufficientWalletError(category, requested) {
  const err = new Error(
    `${INSUFFICIENT_WALLET}: ${category} wallet cannot cover ${requested}`
  );
  err.code = INSUFFICIENT_WALLET;
  err.category = category;
  err.requested = requested;
  return err;
}

/**
 * Read a single owner's raw wallet sub-document (session-aware).
 * @returns {Promise<{NSE:number,MCX:number,COMEX:number,GLOBAL:number}>}
 */
async function readWallet(Model, ownerId, session = null) {
  let query = Model.findById(ownerId).select('wallet');
  if (session) query = query.session(session);
  const doc = await query.lean();
  const wallet = (doc && doc.wallet) || {};
  // Every category, a missing one (e.g. NSEOPT on a document written before
  // that pool existed) reading as 0.
  return Object.fromEntries(CATEGORIES.map((cat) => [cat, Number(wallet[cat]) || 0]));
}

/**
 * Run `fn(session)` inside the caller's session, or open and own a transaction
 * when no session is supplied. Used by `assign`/`withdraw` so their two wallet
 * mutations + audit write are always atomic (both-or-neither).
 *
 * @param {import('mongoose').ClientSession|null} session
 * @param {(session: import('mongoose').ClientSession) => Promise<any>} fn
 */
async function withOptionalSession(session, fn) {
  if (session) return fn(session);

  const ownSession = await mongoose.startSession();
  try {
    let result;
    await ownSession.withTransaction(async () => {
      result = await fn(ownSession);
    });
    return result;
  } finally {
    ownSession.endSession();
  }
}

/**
 * Reserve (block) margin from a category pool via a single guarded atomic
 * update. Decrements only when the balance can still cover `amount`, so
 * concurrent opens can never drive the pool below 0 or lose a write.
 *
 * @param {'User'|'Master'} ownerModel   - owner discriminator
 * @param {string|import('mongoose').Types.ObjectId} ownerId
 * @param {'NSE'|'MCX'|'GLOBAL'} category
 * @param {number} amount                - notional to reserve (rounded internally)
 * @param {import('mongoose').ClientSession|null} [session]
 * @returns {Promise<{category:string, amount:number}>}
 * @throws error tagged `code: 'INSUFFICIENT_WALLET'` (with `.category`, `.requested`)
 *         when the pool cannot cover the amount.
 */
async function block(ownerModel, ownerId, category, amount, session = null, { allowNegative = false } = {}) {
  assertCategory(category);
  const rounded = assertPositiveAmount(amount);
  const Model = resolveModel(ownerModel);
  const field = `wallet.${category}`;
  const options = session ? { session } : {};

  // allowNegative: admin bulk import of index futures (tradeController) — the
  // pool may go below 0 and is refilled later; no balance guard.
  const result = await Model.updateOne(
    allowNegative ? { _id: ownerId } : { _id: ownerId, [field]: { $gte: rounded } },
    { $inc: { [field]: -rounded } },
    options
  );

  const matched = result && (result.matchedCount != null ? result.matchedCount : result.n);
  if (!matched) {
    // Either the pool was short, or the owner does not exist. Both mean "this
    // move cannot be applied" — surface as INSUFFICIENT_WALLET for the caller.
    throw insufficientWalletError(category, rounded);
  }

  return { category, amount: rounded };
}

/**
 * Return (release) margin to a category pool. Never guarded — releasing margin
 * on a close/reduce is always allowed and can only increase the balance.
 *
 * @param {'User'|'Master'} ownerModel
 * @param {string|import('mongoose').Types.ObjectId} ownerId
 * @param {'NSE'|'MCX'|'GLOBAL'} category
 * @param {number} amount               - entry notional to return (rounded internally)
 * @param {import('mongoose').ClientSession|null} [session]
 * @returns {Promise<{category:string, amount:number}>}
 */
async function release(ownerModel, ownerId, category, amount, session = null) {
  assertCategory(category);
  const rounded = assertPositiveAmount(amount);
  const Model = resolveModel(ownerModel);
  const field = `wallet.${category}`;
  const options = session ? { session } : {};

  await Model.updateOne(
    { _id: ownerId },
    { $inc: { [field]: rounded } },
    options
  );

  return { category, amount: rounded };
}

/**
 * Look up a prior Transaction by idempotencyKey, if one is supplied and
 * already exists — used by assign()/withdraw() to make a retried request a
 * safe no-op instead of double-applying the same funding/withdrawal.
 *
 * This is a pre-check, not a lock: it closes the common case (a caller
 * retries after a network timeout, well after the first attempt's own
 * request finished). A genuinely simultaneous double-submit with the same
 * key can still race past this check; the unique index on
 * `Transaction.idempotencyKey` is the backstop for that case — the second
 * writeFundingAudit's insert fails with a duplicate-key error rather than
 * silently creating two records, so the transaction aborts and the caller
 * sees an error instead of a double-applied balance change.
 *
 * @param {string|null} idempotencyKey
 * @param {import('mongoose').ClientSession} session
 * @returns {Promise<{category:string, amount:number, actor:string, targetModel:string, replayed:true}|null>}
 */
async function checkIdempotentReplay(idempotencyKey, session) {
  if (!idempotencyKey) return null;
  const existing = await Transaction.findOne({ idempotencyKey }).session(session).lean();
  if (!existing) return null;
  return {
    category: existing.metadata?.category,
    amount: existing.amount,
    actor: existing.metadata?.actor?.type,
    targetModel: existing.userModel,
    replayed: true,
  };
}

/**
 * Write a wallet-funding audit record (design §5, Requirement 5.5). Captures the
 * actor, target, category, amount, direction and before/after balances so every
 * assign/withdraw is fully traceable.
 *
 * @param {object} params
 * @param {'WALLET_ASSIGN'|'WALLET_WITHDRAW'} params.type
 * @param {'ASSIGN'|'WITHDRAW'} params.direction
 * @param {{type:string, id?:any}} params.actor
 * @param {'User'|'Master'} params.targetModel
 * @param {any} params.targetId
 * @param {string} params.category
 * @param {number} params.amount
 * @param {number} params.targetBefore
 * @param {number} params.targetAfter
 * @param {number|null} params.actorBefore
 * @param {number|null} params.actorAfter
 * @param {import('mongoose').ClientSession|null} params.session
 * @param {string|null} [params.idempotencyKey]
 */
/**
 * The Master whose pool actually pays for (or receives back) a Master
 * actor's assign/withdraw: the target's DIRECT parent. For the actor's own
 * client or sub-master that's the actor itself (unchanged behaviour); for an
 * account further down the actor's downline (e.g. a client or sub-master
 * belonging to the actor's sub-master) it's that account's own parent, so
 * funds always move one hierarchy level at a time instead of skipping one.
 */
async function payingMasterFor(actor, targetModel, targetId, s) {
  const Model = targetModel === 'User' ? User : Master;
  const target = await Model.findById(targetId).select('master_id').session(s);
  if (!target || !target.master_id) {
    if (targetModel === 'User') throw new Error('Client has no parent master');
    // A top-level master has no parent master — only reachable by an
    // admin, never by a master actor; keep the actor as payer defensively.
    return actor.id;
  }
  return target.master_id;
}

async function writeFundingAudit(params) {
  const {
    type, direction, actor, targetModel, targetId, category, amount,
    targetBefore, targetAfter, actorBefore, actorAfter, session, idempotencyKey,
    payerMasterId = null,
  } = params;

  const transactionId = `TXN_${Date.now()}_${Math.random().toString(36).substr(2, 6)}_W`;

  const doc = {
    transactionId,
    ...(idempotencyKey ? { idempotencyKey } : {}),
    userId: targetId,
    userModel: targetModel,
    type,
    status: 'SUCCESS',
    amount,
    referenceId: actor && actor.id ? actor.id : undefined,
    referenceModel: actor && (actor.type === 'Master' || actor.type === 'Admin') ? actor.type : undefined,
    balanceBefore: roundMoney(targetBefore),
    balanceAfter: roundMoney(targetAfter),
    metadata: {
      category,
      direction,
      actor: { type: actor ? actor.type : null, id: actor && actor.id ? actor.id : null },
      target: { type: targetModel, id: targetId },
      targetBalanceBefore: roundMoney(targetBefore),
      targetBalanceAfter: roundMoney(targetAfter),
      actorBalanceBefore: actorBefore == null ? null : roundMoney(actorBefore),
      actorBalanceAfter: actorAfter == null ? null : roundMoney(actorAfter),
      // Set when a master's action was paid by a different master (the
      // client's own parent — see payingMasterFor); the actorBalance fields
      // above are then that payer's balances, not the actor's.
      ...(payerMasterId && String(payerMasterId) !== String(actor && actor.id)
        ? { payer: { type: 'Master', id: payerMasterId } }
        : {}),
    },
  };

  await Transaction.create([doc], session ? { session } : {});
}

/**
 * Fund a target's category pool.
 *
 * - **Master actor** → a transfer: atomic guarded `block` on the master's own
 *   pool (rejected if it would go below 0) followed by `release` on the target.
 *   Because the block runs first, a failed debit never credits the target.
 * - **Admin actor, target is a User (client)** → also a transfer: same guarded
 *   `block`, but on the client's own DIRECT parent master's pool (looked up via
 *   `User.master_id`), not the admin's. Money always comes from somewhere in
 *   the tree; an admin funding a client is never a free grant.
 * - **Admin actor, target is a Master** → a true grant: `release` on the
 *   target only. This is the system's actual capital-injection point — an
 *   admin funding a master (at any depth) has no debit source, by design.
 *
 * Runs inside the caller's `session` when provided, otherwise opens and owns a
 * transaction so the debit + credit + audit are atomic.
 *
 * @param {{type:'Master'|'Admin', id?:any}} actor   - who is funding
 * @param {'User'|'Master'} targetModel              - target discriminator
 * @param {string|import('mongoose').Types.ObjectId} targetId
 * @param {'NSE'|'MCX'|'GLOBAL'} category
 * @param {number} amount
 * @param {import('mongoose').ClientSession|null} [session]
 * @param {string|null} [idempotencyKey] - if supplied and a Transaction with
 *   this key already exists, the call is a no-op replay: no balance mutation
 *   runs and the previously-recorded result is returned instead. Lets a
 *   retried request (e.g. a network timeout after the first attempt actually
 *   committed) be sent again safely without double-applying.
 * @returns {Promise<{category:string, amount:number, actor:string, targetModel:string, replayed?:boolean}>}
 */
async function assign(actor, targetModel, targetId, category, amount, session = null, idempotencyKey = null) {
  if (!actor || (actor.type !== 'Master' && actor.type !== 'Admin')) {
    throw new Error(`walletService.assign: actor.type must be 'Master' or 'Admin'`);
  }
  assertCategory(category);
  const rounded = assertPositiveAmount(amount);
  resolveModel(targetModel); // validate early

  return withOptionalSession(session, async (s) => {
    const replay = await checkIdempotentReplay(idempotencyKey, s);
    if (replay) return replay;

    const targetBefore = (await readWallet(resolveModel(targetModel), targetId, s))[category];

    let actorBefore = null;
    let actorAfter = null;
    let payerMasterId = null;

    if (actor.type === 'Master') {
      // The paying pool is the target's DIRECT parent — for a master's own
      // client that's the master itself (unchanged), but a master acting on
      // a sub-master's client (downline) funds it from that sub-master, not
      // from their own pool, so money always moves one level at a time.
      payerMasterId = await payingMasterFor(actor, targetModel, targetId, s);
      actorBefore = (await readWallet(Master, payerMasterId, s))[category];
      // Debit the payer first — throws INSUFFICIENT_WALLET (and aborts the
      // transaction) before the target is ever credited.
      await block('Master', payerMasterId, category, rounded, s);
      actorAfter = roundMoney(actorBefore - rounded);
    } else if (actor.type === 'Admin' && targetModel === 'User') {
      // Admin funding a CLIENT's wallet: debit the client's own DIRECT
      // parent master, not a free grant — same rule as every other
      // client-facing credit path (creditUserByAdmin, masterUserController's
      // createUser). Admin funding a MASTER directly stays a true grant
      // (deliberately not touched here) — that's the system's capital-
      // injection mechanism, distinct from moving money between a client
      // and its own parent.
      const clientUser = await User.findById(targetId).select('master_id').session(s);
      if (!clientUser || !clientUser.master_id) {
        throw new Error('Client has no parent master');
      }
      actorBefore = (await readWallet(Master, clientUser.master_id, s))[category];
      await block('Master', clientUser.master_id, category, rounded, s);
      actorAfter = roundMoney(actorBefore - rounded);
    }

    // Credit the target (grant for admin-funds-master, transfer leg otherwise).
    await release(targetModel, targetId, category, rounded, s);
    const targetAfter = roundMoney(targetBefore + rounded);

    await writeFundingAudit({
      type: 'WALLET_ASSIGN',
      direction: 'ASSIGN',
      actor,
      targetModel,
      targetId,
      category,
      amount: rounded,
      targetBefore,
      targetAfter,
      actorBefore,
      actorAfter,
      payerMasterId,
      session: s,
      idempotencyKey,
    });

    return { category, amount: rounded, actor: actor.type, targetModel };
  });
}

/**
 * Pull funds back from a target's category pool.
 *
 * Guarded `block` on the **target** (rejected if it would drive the target
 * below 0). When the actor is a **Master**, the withdrawn amount is `release`d
 * back to the master's own pool. When the actor is an **Admin** and the
 * target is a **User (client)**, it's `release`d to the client's own DIRECT
 * parent master instead (same rule as `assign` above) — only an admin
 * withdrawing from a **Master** target has no destination (the funds truly
 * leave the system, mirroring that target's own grant-only funding).
 *
 * Runs inside the caller's `session` when provided, otherwise opens and owns a
 * transaction so the debit + credit + audit are atomic.
 *
 * @param {{type:'Master'|'Admin', id?:any}} actor
 * @param {'User'|'Master'} targetModel
 * @param {string|import('mongoose').Types.ObjectId} targetId
 * @param {'NSE'|'MCX'|'GLOBAL'} category
 * @param {number} amount
 * @param {import('mongoose').ClientSession|null} [session]
 * @param {string|null} [idempotencyKey] - see assign()'s doc for semantics.
 * @returns {Promise<{category:string, amount:number, actor:string, targetModel:string, replayed?:boolean}>}
 * @throws error tagged `code: 'INSUFFICIENT_WALLET'` when the target cannot cover it.
 */
async function withdraw(actor, targetModel, targetId, category, amount, session = null, idempotencyKey = null) {
  if (!actor || (actor.type !== 'Master' && actor.type !== 'Admin')) {
    throw new Error(`walletService.withdraw: actor.type must be 'Master' or 'Admin'`);
  }
  assertCategory(category);
  const rounded = assertPositiveAmount(amount);
  resolveModel(targetModel); // validate early

  return withOptionalSession(session, async (s) => {
    const replay = await checkIdempotentReplay(idempotencyKey, s);
    if (replay) return replay;

    const targetBefore = (await readWallet(resolveModel(targetModel), targetId, s))[category];

    // Debit the target first (guarded) — rejects an over-withdrawal before the
    // actor is credited.
    await block(targetModel, targetId, category, rounded, s);
    const targetAfter = roundMoney(targetBefore - rounded);

    let actorBefore = null;
    let actorAfter = null;
    let payerMasterId = null;
    if (actor.type === 'Master') {
      // Mirror of assign(): withdrawn funds go back to the target's DIRECT
      // parent — the master itself for their own client, or the sub-master
      // for a downline client, never skipping a level.
      payerMasterId = await payingMasterFor(actor, targetModel, targetId, s);
      actorBefore = (await readWallet(Master, payerMasterId, s))[category];
      await release('Master', payerMasterId, category, rounded, s);
      actorAfter = roundMoney(actorBefore + rounded);
    } else if (actor.type === 'Admin' && targetModel === 'User') {
      // Mirror of assign()'s admin-funds-client branch above: withdrawing
      // from a client's wallet credits the client's own direct parent
      // master back, instead of the funds simply leaving the system.
      const clientUser = await User.findById(targetId).select('master_id').session(s);
      if (!clientUser || !clientUser.master_id) {
        throw new Error('Client has no parent master');
      }
      actorBefore = (await readWallet(Master, clientUser.master_id, s))[category];
      await release('Master', clientUser.master_id, category, rounded, s);
      actorAfter = roundMoney(actorBefore + rounded);
    }

    await writeFundingAudit({
      type: 'WALLET_WITHDRAW',
      direction: 'WITHDRAW',
      actor,
      targetModel,
      targetId,
      category,
      amount: rounded,
      targetBefore,
      targetAfter,
      actorBefore,
      actorAfter,
      payerMasterId,
      session: s,
      idempotencyKey,
    });

    return { category, amount: rounded, actor: actor.type, targetModel };
  });
}

/**
 * Read an owner's current available balances for all three pools.
 *
 * @param {'User'|'Master'} ownerModel
 * @param {string|import('mongoose').Types.ObjectId} ownerId
 * @param {import('mongoose').ClientSession|null} [session]
 * @returns {Promise<{NSE:number, MCX:number, GLOBAL:number}>}
 */
async function getAvailable(ownerModel, ownerId, session = null) {
  const Model = resolveModel(ownerModel);
  const wallet = await readWallet(Model, ownerId, session);
  return Object.fromEntries(CATEGORIES.map((cat) => [cat, roundMoney(wallet[cat])]));
}

/**
 * Drift audit (admin-only usage; endpoint auth arrives in Task 12).
 *
 * Recomputes the margin that *should* be blocked from the owner's open
 * positions — `Σ |net_qty| × avgEntry` per category, where `avgEntry` is the
 * average buy price for a long net position and the average sell price for a
 * short one (design §D3) — and reports it alongside the stored available
 * balance. `available + blocked` reconstructs the originally-funded amount, so a
 * caller can compare it against the expected funding to detect drift.
 *
 * @param {'User'|'Master'} ownerModel
 * @param {string|import('mongoose').Types.ObjectId} ownerId
 * @returns {Promise<{ownerModel:string, ownerId:string, categories:Object}>}
 */
async function reconcile(ownerModel, ownerId) {
  resolveModel(ownerModel); // validate discriminator
  const ownerField = ownerModel === 'User' ? 'user_id' : 'master_id';

  const positions = await Trade.aggregate([
    { $match: { [ownerField]: toObjectId(ownerId), status: 'completed', deleted_at: null } },
    {
      $group: {
        _id: '$instrument_token',
        total_buy_qty: {
          $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', 0] },
        },
        total_sell_qty: {
          $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, '$executed_quantity', 0] },
        },
        total_buy_value: {
          $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, { $multiply: ['$executed_quantity', '$executed_price'] }, 0] },
        },
        total_sell_value: {
          $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, { $multiply: ['$executed_quantity', '$executed_price'] }, 0] },
        },
      },
    },
  ]);

  const openPositions = [];
  for (const p of positions) {
    const buyQty = p.total_buy_qty || 0;
    const sellQty = p.total_sell_qty || 0;
    const netQty = buyQty - sellQty;
    if (netQty === 0) continue;
    const avgBuy = buyQty > 0 ? p.total_buy_value / buyQty : 0;
    const avgSell = sellQty > 0 ? p.total_sell_value / sellQty : 0;
    const avgEntry = netQty > 0 ? avgBuy : avgSell;
    openPositions.push({ token: p._id, notional: Math.abs(netQty) * avgEntry });
  }

  // Resolve each open instrument's segment → category.
  const tokens = openPositions.map((p) => p.token);
  const instruments = tokens.length
    ? await KiteInstrument.find({ instrument_token: { $in: tokens } }).select('instrument_token segment name raw_name tradingsymbol').lean()
    : [];
  const segmentByToken = {};
  const instrumentByToken = {};
  instruments.forEach((i) => { segmentByToken[i.instrument_token] = i.segment || ''; instrumentByToken[i.instrument_token] = i; });

  const blocked = {};
  for (const cat of CATEGORIES) blocked[cat] = 0;
  for (const pos of openPositions) {
    const category = categoryForSegment(segmentByToken[pos.token] || '', instrumentByToken[pos.token]);
    blocked[category] += pos.notional;
  }

  const available = await getAvailable(ownerModel, ownerId);
  const categories = {};
  for (const cat of CATEGORIES) {
    const avail = roundMoney(available[cat] || 0);
    const blk = roundMoney(blocked[cat] || 0);
    categories[cat] = { available: avail, blocked: blk, total: roundMoney(avail + blk) };
  }

  return { ownerModel, ownerId: String(ownerId), categories };
}

module.exports = {
  block,
  release,
  assign,
  withdraw,
  getAvailable,
  reconcile,
  // Exposed for callers that need to branch on the guarded-move failure.
  INSUFFICIENT_WALLET,
  CATEGORIES,
};
