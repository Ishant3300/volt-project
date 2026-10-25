const express = require('express');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');
const router = express.Router();
const {
  createUser,
  getAllUsers,
  getUserById,
  updateUser,
  deleteUser,
  creditUserByAdmin,
  debitUserByAdmin,
  // Grouped Quantity
  createGroupedQuantity,
  getAllGroupedQuantities,
  getGroupedQuantityById,
  updateGroupedQuantity,
  deleteGroupedQuantity,
  // Script Quantity
  createScriptQuantity,
  getAllScriptQuantities,
  getScriptQuantityById,
  updateScriptQuantity,
  deleteScriptQuantity,
  // Brokerage Settings
  createBrokerageSettings,
  getAllBrokerageSettings,
  getBrokerageSettingsById,
  updateBrokerageSettings,
  deleteBrokerageSettings
} = require('../controllers/adminController');
const { getLotNamesByExchange, getUniqueRawNamesBySegment, bulkCreateGroup, getGroupInstruments, bulkCreateBrokerage, getBrokerageByExchange, bulkCreateScriptQuantity, getScriptQuantityByExchange } = require('../controllers/groupedQuantityController');
const { authenticateAdmin, authenticateAdminOrMaster, authenticateMaster, authenticateAny } = require('../middlewares/auth');
const { rejectIfInvestor } = require('../middlewares/rejectIfInvestor');
const { requireAdminPermission } = require('../middlewares/requireAdminPermission');
const { rejectIfAdminWatchOnly } = require('../middlewares/rejectIfAdminWatchOnly');
const { escapeRegex } = require('../utils/escapeRegex');

// Category trade-wallet funding (Task 12 / Requirements 5.1–5.7)
const {
  assign: walletAssign,
  withdraw: walletWithdraw,
  getWallet: walletGet,
  reconcile: walletReconcile,
} = require('../controllers/walletController');

// All routes require admin authentication


// User CRUD operations
router.post('/users', authenticateMaster, rejectIfInvestor, createUser);
router.get('/users', authenticateAdminOrMaster, getAllUsers);
router.get('/users/:id', authenticateAdminOrMaster, getUserById);
router.put('/users/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, updateUser);
router.delete('/users/:id', authenticateMaster, rejectIfInvestor, deleteUser);
// Money-moving, previously ungated — WALLET_MANAGE already gates the
// semantically identical /admin/wallet/assign|withdraw below, but these two
// (direct `credits` ledger, not the category wallet) had no permission key
// at all, letting any regular Admin move money regardless of granted keys.
router.post('/users/:id/credit', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('WALLET_MANAGE'), creditUserByAdmin);
router.post('/users/:id/debit', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('WALLET_MANAGE'), debitUserByAdmin);

// ==================== WALLET FUNDING ROUTES (admin grant/remove) ====================
// Admin is the root of funds: assign is a grant (credit only, no debit source),
// withdraw removes funds from the target. The walletController resolves req.admin
// as the actor; walletService owns the Mongo transaction + Transaction audit.
router.post('/wallet/assign', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('WALLET_MANAGE'), walletAssign);
router.post('/wallet/withdraw', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('WALLET_MANAGE'), walletWithdraw);
router.get('/wallet', authenticateAdmin, walletGet);
// Drift audit: per-category { available, blocked, total } from open positions
router.get('/wallet/reconcile', authenticateAdmin, walletReconcile);

// Grouped Quantity CRUD operations
// QUANTITY_MANAGE previously didn't exist — these writes (and Script
// Quantity's below) had no permission key at all, unlike every sibling
// CRUD surface (Brokerage/Instrument/FreshStoploss), letting any regular
// Admin mutate platform-wide quantity limits regardless of granted keys.
// requireAdminPermission is a no-op for a Master caller (see its own doc
// comment), so this doesn't affect the Master-shared script-quantity routes.
router.post('/grouped-quantities', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), createGroupedQuantity);
router.post('/grouped-quantities/bulk-create', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), bulkCreateGroup);
router.get('/grouped-quantities/unique-raw-names/:segment', authenticateAdminOrMaster, getUniqueRawNamesBySegment);
router.get('/grouped-quantities/group/:exchange_name/:lot_name', authenticateAdminOrMaster, getGroupInstruments);
router.get('/grouped-quantities/exchange/:exchange_name/lot-names', authenticateAdminOrMaster, getLotNamesByExchange);
router.get('/grouped-quantities', authenticateAdminOrMaster, getAllGroupedQuantities);
router.get('/grouped-quantities/:id', authenticateAdminOrMaster, getGroupedQuantityById);
router.put('/grouped-quantities/:id', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), updateGroupedQuantity);
router.delete('/grouped-quantities/:id', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), deleteGroupedQuantity);

// Script Quantity CRUD operations
router.post('/script-quantities/bulk-create', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), bulkCreateScriptQuantity);
router.get('/script-quantities/exchange/:exchange_name', authenticateAdminOrMaster, getScriptQuantityByExchange);
router.post('/script-quantities', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), createScriptQuantity);
router.get('/script-quantities', authenticateAdminOrMaster, getAllScriptQuantities);
router.get('/script-quantities/:id', authenticateAdminOrMaster, getScriptQuantityById);
router.put('/script-quantities/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), updateScriptQuantity);
router.delete('/script-quantities/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('QUANTITY_MANAGE'), deleteScriptQuantity);

// Brokerage Settings CRUD operations
router.post('/brokerage-settings/bulk-create', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('BROKERAGE_MANAGE'), bulkCreateBrokerage);
router.get('/brokerage-settings/exchange/:exchange_name', authenticateAdminOrMaster, getBrokerageByExchange);
router.post('/brokerage-settings', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('BROKERAGE_MANAGE'), createBrokerageSettings);
router.get('/brokerage-settings', authenticateAdminOrMaster, getAllBrokerageSettings);
router.get('/brokerage-settings/:id', authenticateAdminOrMaster, getBrokerageSettingsById);
// Bulk update brokerage settings (update multiple IDs with same value)
router.put('/brokerage-settings/bulk-update', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('BROKERAGE_MANAGE'), async (req, res) => {
  try {
    const { ids, brk_value, type } = req.body;
    if (!ids || !Array.isArray(ids) || ids.length === 0 || brk_value === undefined) {
      return res.status(400).json({ success: false, message: 'ids array and brk_value are required', data: null });
    }
    const BrokerageSettings = require('../models/BrokerageSettings');

    // Full records for every id, fetched once — used for the ownership
    // check below AND the floor check further down. A batch can mix
    // several different scripts that happen to share the same target
    // brk_value (the create-master/create-user screens group their
    // per-script overrides by value, not by script), so both checks must
    // walk every record instead of trusting one "sample" to represent the
    // whole batch — a sample-only check let a stricter script's floor slip
    // through unchecked whenever it shared a batch with a looser one.
    const records = await BrokerageSettings.find({ _id: { $in: ids }, deleted_at: null })
      .select('user_id exchange_name script_name type')
      .lean();
    if (records.length === 0) {
      return res.status(404).json({ success: false, message: 'No matching brokerage settings found', data: null });
    }

    // Both checks below used to run per record, one query at a time (~5-6
    // round trips each) — a "select all" of ~200 scripts made 1,000+
    // sequential queries and outlived the web client's 30s timeout even
    // though the update itself then went through. Same rules, same order,
    // same messages; the lookups are just batched up front.
    const userIds = [...new Set(records.filter((r) => r.user_id).map((r) => r.user_id.toString()))];

    // Ownership check: every id in the batch must belong to the caller's own
    // subtree — without this, a master could smuggle in ids belonging to
    // unrelated accounts platform-wide via this one bulk endpoint. Admin
    // unrestricted.
    if (req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const { resolveBrokerageOwnerMasterId } = require('../controllers/adminController');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const ownerMasterById = new Map();
      for (const id of userIds) ownerMasterById.set(id, await resolveBrokerageOwnerMasterId(id));
      for (const record of records) {
        const ownerMasterId = record.user_id ? ownerMasterById.get(record.user_id.toString()) : null;
        if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
          return res.status(403).json({ success: false, message: 'Not authorized to update one or more of these brokerage settings', data: null });
        }
      }
    }

    // Floor validation, per record — admin bypasses (can set any rate on
    // their children). A record with no user_id is a global/admin-owned
    // row with no floor to check against.
    if (!req.admin) {
      const User = require('../models/User');
      const Master = require('../models/Master');
      // A script that trades nowhere has no floor (brokerageCopyService.tradingScriptNames):
      // 11 dropped F&O stocks at the old default 2 blocked NBS's "1 for all" (24 Oct 2026).
      const { tradingScriptNames, isTradingName } = require('../services/brokerageCopyService');
      const trading = await tradingScriptNames();
      const floorRecords = records.filter((r) => r.user_id && isTradingName(trading, r.script_name));
      const scripts = [...new Set(floorRecords.map((r) => r.script_name))];
      const types = [...new Set(floorRecords.map((r) => type || r.type))];
      const rateKey = (ex, script, t) => `${ex}|${script}|${t}`;

      // The target's parent (validateBrokerageFloor's hierarchy lookup):
      // a User's master_id, else a Master's master_id.
      const users = await User.find({ _id: { $in: userIds } }).select('_id master_id').lean();
      const parentByTarget = new Map(users.map((u) => [u._id.toString(), u.master_id?.toString() || null]));
      const masterTargets = userIds.filter((id) => !parentByTarget.has(id));
      if (masterTargets.length) {
        const masters = await Master.find({ _id: { $in: masterTargets } }).select('_id master_id').lean();
        for (const m of masters) parentByTarget.set(m._id.toString(), m.master_id?.toString() || null);
      }
      const parentIds = [...new Set([...parentByTarget.values()].filter(Boolean))];

      const [callerRows, parentRows, globalRows] = await Promise.all([
        BrokerageSettings.find({ user_id: req.master.id, script_name: { $in: scripts }, type: { $in: types }, deleted_at: null })
          .select('exchange_name script_name type brk_value').lean(),
        parentIds.length
          ? BrokerageSettings.find({ user_id: { $in: parentIds }, script_name: { $in: scripts }, type: { $in: types }, deleted_at: null })
            .select('user_id exchange_name script_name type brk_value').lean()
          : [],
        BrokerageSettings.find({ user_id: null, script_name: { $in: scripts }, type: { $in: types }, deleted_at: null })
          .select('exchange_name script_name type brk_value').lean(),
      ]);
      // First match wins, like the findOne each of these replaced.
      const callerRate = new Map();
      for (const r of callerRows) {
        const k = rateKey(r.exchange_name, r.script_name, r.type);
        if (!callerRate.has(k)) callerRate.set(k, r.brk_value);
      }
      const parentRate = new Map();
      for (const r of parentRows) {
        const k = `${r.user_id}|${rateKey(r.exchange_name, r.script_name, r.type)}`;
        if (!parentRate.has(k)) parentRate.set(k, r.brk_value);
      }
      const globalRate = new Map();
      for (const r of globalRows) {
        const k = rateKey(r.exchange_name, r.script_name, r.type);
        if (!globalRate.has(k)) globalRate.set(k, r.brk_value);
      }

      for (const record of floorRecords) {
        const effectiveType = type || record.type;

        // The child's rate must be >= the CALLER's own rate (the logged-in
        // master) for this exact script.
        const callerValue = callerRate.get(rateKey(record.exchange_name, record.script_name, effectiveType));
        if (callerValue !== undefined && brk_value < callerValue) {
          return res.status(422).json({
            success: false,
            message: `Brokerage cannot be less than the parent limit (${callerValue}) for ${record.script_name}`,
            data: null
          });
        }

        // Hierarchy-based validation (validateBrokerageFloor): the target's
        // parent's rate, else the global rate; no rate found = no floor.
        const upperKey = rateKey(String(record.exchange_name).toUpperCase(), record.script_name, effectiveType);
        const parentId = parentByTarget.get(record.user_id.toString());
        let floor = parentId ? parentRate.get(`${parentId}|${upperKey}`) : undefined;
        if (floor === undefined) floor = globalRate.get(upperKey);
        if (floor !== undefined && floor !== null && brk_value < floor) {
          return res.status(422).json({ success: false, message: `Brokerage cannot be less than the parent limit (${floor})`, data: null });
        }
      }
    }

    // Stamp effective_from so this new rate only applies to trades from now onwards.
    const updateFields = { brk_value, effective_from: new Date() };
    if (type) updateFields.type = type;
    // runValidators — updateMany skips schema validation by default (including
    // the `type` enum), so an unsupported type (e.g. a stale/removed option
    // like the old "CRORE WISE") would otherwise save silently and then
    // brokerageService.js would silently compute 0 brokerage for it forever.
    const result = await BrokerageSettings.updateMany(
      { _id: { $in: ids }, deleted_at: null },
      { $set: updateFields },
      { runValidators: true }
    );

    // Reload metricsEngine rules so brokerage calculations use the new values immediately
    try { const me = require('../services/metricsEngine'); me.reloadRules(); } catch (_) {}

    res.json({ success: true, message: `Updated ${result.modifiedCount} brokerage setting(s)`, data: { modified: result.modifiedCount } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});
router.put('/brokerage-settings/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('BROKERAGE_MANAGE'), updateBrokerageSettings);
router.delete('/brokerage-settings/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('BROKERAGE_MANAGE'), deleteBrokerageSettings);

// Refresh close prices (admin-only, for testing / manual trigger) — feeds
// the same settlement price pipeline as /admin/settlement/start, but had
// no permission key at all, unlike that SETTLEMENT_TRIGGER-gated sibling.
router.post('/refresh-close-prices', authenticateAdmin, requireAdminPermission('SETTLEMENT_TRIGGER'), async (req, res) => {
  try {
    const livePriceService = require('../services/livePriceService');
    const result = await livePriceService.refreshClosePrices();
    res.json({ success: true, message: 'Close prices refreshed', ...result });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
});

// Refresh settlement prices via OHLC API (admin-only, for testing / manual trigger)
router.post('/refresh-settlement-prices', authenticateAdmin, requireAdminPermission('SETTLEMENT_TRIGGER'), async (req, res) => {
  try {
    const livePriceService = require('../services/livePriceService');
    const result = await livePriceService.refreshSettlementPrices();
    res.json({ success: true, message: 'Settlement prices refreshed', ...result });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
});

// ==================== ANNOUNCEMENT ROUTES ====================
const { setAnnouncement, clearAnnouncement, getActiveAnnouncement } = require('../controllers/announcementController');
router.post('/announcements', authenticateAdmin, rejectIfAdminWatchOnly, setAnnouncement);
router.delete('/announcements', authenticateAdmin, rejectIfAdminWatchOnly, clearAnnouncement);
router.get('/announcements/active', authenticateAny, getActiveAnnouncement);

// ==================== FRESH STOPLOSS LIMIT ROUTES ====================
const { getAllFreshStoplossLimits, bulkCreateFreshStoplossLimits, updateFreshStoplossLimit, deleteFreshStoplossLimit, bulkUpdateFreshStoplossLimits } = require('../controllers/freshStoplossLimitController');
router.get('/fresh-stoploss-limits', authenticateAdmin, getAllFreshStoplossLimits);
// Master base profit book time (utils/profitBookTime.js; replaces the 24 Oct platform minimum).
const { getProfitBookBase, previewProfitBookBase, setProfitBookBase } = require('../controllers/profitBookBaseController');
router.get('/profit-book-base/:masterId', authenticateAdminOrMaster, getProfitBookBase);
router.get('/profit-book-base/:masterId/preview', authenticateAdminOrMaster, previewProfitBookBase);
router.put('/profit-book-base/:masterId', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), setProfitBookBase);
router.post('/fresh-stoploss-limits/bulk-create', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('FRESH_STOPLOSS_MANAGE'), bulkCreateFreshStoplossLimits);
router.put('/fresh-stoploss-limits/bulk-update', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('FRESH_STOPLOSS_MANAGE'), bulkUpdateFreshStoplossLimits);
router.put('/fresh-stoploss-limits/:id', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('FRESH_STOPLOSS_MANAGE'), updateFreshStoplossLimit);
router.delete('/fresh-stoploss-limits/:id', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('FRESH_STOPLOSS_MANAGE'), deleteFreshStoplossLimit);

// ==================== TOTP ROUTES ====================
// Generalized totpService (was admin-only adminOtpService) — see that
// file's own header. Master's equivalent routes are in masterFlowRoutes.js,
// same service, Master model instead of Admin.
const totpService = require('../services/totpService');
const Admin = require('../models/Admin');

router.get('/totp/status', authenticateAdmin, async (req, res) => {
  try {
    const status = await totpService.getTotpStatus(Admin, req.admin.id);
    if (!status) return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    res.json({ success: true, data: status });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/generate', authenticateAdmin, async (req, res) => {
  try {
    const result = await totpService.generateSecret(Admin, req.admin.id);
    res.json({ success: true, data: { qr_data_url: result.qrDataUrl, secret: result.secret } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/verify-setup', authenticateAdmin, async (req, res) => {
  try {
    const { token } = req.body;
    if (!token) return res.status(400).json({ success: false, message: 'TOTP code required', data: null });
    const verified = await totpService.verifySetup(Admin, req.admin.id, token);
    if (!verified) return res.status(400).json({ success: false, message: 'Invalid TOTP code', data: null });
    res.json({ success: true, message: 'TOTP activated successfully' });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/toggle', authenticateAdmin, async (req, res) => {
  try {
    const { enabled } = req.body;
    if (enabled === undefined) return res.status(400).json({ success: false, message: 'enabled field required', data: null });
    await totpService.toggleTotp(Admin, req.admin.id, enabled);
    res.json({ success: true, message: `TOTP ${enabled ? 'enabled' : 'disabled'}` });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/reset', authenticateAdmin, async (req, res) => {
  try {
    await totpService.resetTotp(Admin, req.admin.id);
    res.json({ success: true, message: 'TOTP reset successfully' });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// ==================== INSTRUMENT MANAGEMENT ROUTES ====================
const KiteInstrument = require('../models/KiteInstrument');

/**
 * Cancel pending LIMIT/SL/SL-M orders on an instrument being disabled or
 * deleted. Without this, a pending order placed before the toggle would
 * still sit in the book and could fill later, opening a fresh position on
 * a script the admin just disabled — placeTrade only guarded NEW placement,
 * not orders already pending (the fill-time gate in priceQueueService.js /
 * orderExecutionService.js now also blocks this, but cancelling proactively
 * avoids relying solely on that backstop).
 *
 * `blockAll: true` (used for a full delete, matching placeTrade's blanket
 * block on deleted instruments) cancels every pending order regardless of
 * direction. Otherwise (a plain disable, which still allows closing an
 * existing position) only orders that would OPEN or exceed the closeable
 * quantity are cancelled — a protective stop-loss on an already-open
 * position is left alone, same as placeTrade's own closing allowance.
 */
async function cancelPendingOrdersForInstrument(instrumentToken, { blockAll = false } = {}) {
  const Trade = require('../models/Trade');
  const orderBookService = require('../services/orderBookService');

  const pendingOrders = await Trade.find({
    status: 'pending',
    instrument_token: instrumentToken,
    deleted_at: null,
  }).select('_id user_id instrument_token transaction_type quantity order_type trigger_direction').lean();
  if (pendingOrders.length === 0) return 0;

  let toCancel = pendingOrders;
  if (!blockAll) {
    const posAgg = await Trade.aggregate([
      { $match: { user_id: { $in: pendingOrders.map(o => o.user_id) }, instrument_token: instrumentToken, status: 'completed', deleted_at: null } },
      { $group: {
        _id: '$user_id',
        buy_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', 0] } },
        sell_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, '$executed_quantity', 0] } },
      } },
    ]);
    const netQtyByUser = new Map(posAgg.map(p => [p._id.toString(), p.buy_qty - p.sell_qty]));

    toCancel = pendingOrders.filter(order => {
      const netQty = netQtyByUser.get(order.user_id.toString()) || 0;
      const isClosing = (order.transaction_type === 'SELL' && netQty > 0) || (order.transaction_type === 'BUY' && netQty < 0);
      const staysWithinPosition = isClosing && order.quantity <= Math.abs(netQty);
      return !staysWithinPosition;
    });
  }
  if (toCancel.length === 0) return 0;

  await Trade.updateMany(
    { _id: { $in: toCancel.map(o => o._id) }, status: 'pending', deleted_at: null },
    { $set: { status: 'cancelled', remarks: blockAll ? 'Auto-cancelled: instrument deleted by admin' : 'Auto-cancelled: instrument disabled by admin' } }
  );
  for (const order of toCancel) {
    try {
      await orderBookService.removeOrder(order._id.toString(), order.instrument_token.toString(), order.transaction_type, order.order_type, order.trigger_direction);
    } catch (_) { /* best-effort — DB status is authoritative */ }
  }
  return toCancel.length;
}

/**
 * Same logic as `cancelPendingOrdersForInstrument`, but for many instrument
 * tokens in one pass — the expiry-toggle and bulk-toggle routes were calling
 * the single-instrument version in a loop, one `Trade.find` round trip per
 * instrument. Fine for a handful of ids, but a whole expiry batch can be
 * thousands of instruments (confirmed live: closing a 6822-instrument
 * NFO-OPT expiry timed out the request at 30s from this alone, since almost
 * every one of those round trips returns zero pending orders and still costs
 * a full query). Batches the find + position-aggregation across all tokens
 * at once and issues a single `updateMany` for every trade to cancel,
 * instead of one per instrument.
 */
async function cancelPendingOrdersForInstruments(instrumentTokens, { blockAll = false } = {}) {
  const Trade = require('../models/Trade');
  const orderBookService = require('../services/orderBookService');

  if (!instrumentTokens || instrumentTokens.length === 0) return 0;

  const pendingOrders = await Trade.find({
    status: 'pending',
    instrument_token: { $in: instrumentTokens },
    deleted_at: null,
  }).select('_id user_id instrument_token transaction_type quantity order_type trigger_direction').lean();
  if (pendingOrders.length === 0) return 0;

  let toCancel = pendingOrders;
  if (!blockAll) {
    const posAgg = await Trade.aggregate([
      { $match: { user_id: { $in: pendingOrders.map(o => o.user_id) }, instrument_token: { $in: instrumentTokens }, status: 'completed', deleted_at: null } },
      { $group: {
        _id: { user_id: '$user_id', instrument_token: '$instrument_token' },
        buy_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', 0] } },
        sell_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, '$executed_quantity', 0] } },
      } },
    ]);
    const netQtyByUserAndInstrument = new Map(
      posAgg.map(p => [`${p._id.user_id.toString()}:${p._id.instrument_token}`, p.buy_qty - p.sell_qty])
    );

    toCancel = pendingOrders.filter(order => {
      const netQty = netQtyByUserAndInstrument.get(`${order.user_id.toString()}:${order.instrument_token}`) || 0;
      const isClosing = (order.transaction_type === 'SELL' && netQty > 0) || (order.transaction_type === 'BUY' && netQty < 0);
      const staysWithinPosition = isClosing && order.quantity <= Math.abs(netQty);
      return !staysWithinPosition;
    });
  }
  if (toCancel.length === 0) return 0;

  await Trade.updateMany(
    { _id: { $in: toCancel.map(o => o._id) }, status: 'pending', deleted_at: null },
    { $set: { status: 'cancelled', remarks: blockAll ? 'Auto-cancelled: instrument deleted by admin' : 'Auto-cancelled: instrument disabled by admin' } }
  );
  for (const order of toCancel) {
    try {
      await orderBookService.removeOrder(order._id.toString(), order.instrument_token.toString(), order.transaction_type, order.order_type, order.trigger_direction);
    } catch (_) { /* best-effort — DB status is authoritative */ }
  }
  return toCancel.length;
}

// GET /admin/instruments/segments — get unique segments for filter dropdown
router.get('/instruments/segments', authenticateAdmin, async (req, res) => {
  try {
    const segments = await KiteInstrument.distinct('segment', { deleted_at: null });
    res.json({ success: true, data: segments.sort() });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// GET /admin/instruments/expiries?segment=NFO — distinct expiry dates for one segment
// (each segment has its own independent expiry calendar — NFO's dates are unrelated
// to MCX's or GIFT NIFTY's — so this always requires a segment, never returns a global list)
router.get('/instruments/expiries', authenticateAdmin, async (req, res) => {
  try {
    const { segment } = req.query;
    if (!segment) {
      return res.status(400).json({ success: false, message: 'segment is required', data: null });
    }
    // Only current/future expiries — matches the default (no ?expiry=) filter
    // on GET /admin/instruments, which already hides expired contracts.
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const expiries = await KiteInstrument.distinct('expiry', {
      segment,
      deleted_at: null,
      expiry: { $gte: today },
    });
    expiries.sort((a, b) => new Date(a) - new Date(b));
    res.json({ success: true, data: expiries });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// PUT /admin/instruments/bulk-toggle — enable/disable multiple instruments
router.put('/instruments/bulk-toggle', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('INSTRUMENT_MANAGE'), async (req, res) => {
  try {
    const { ids, enabled, reason } = req.body;
    if (!ids || !Array.isArray(ids) || enabled === undefined) {
      return res.status(400).json({ success: false, message: 'ids array and enabled field required', data: null });
    }
    const bulkUpdate = enabled === false
      ? { enabled, ban_reason: reason || null, banned_at: new Date() }
      : { enabled, ban_reason: null, banned_at: null };
    const result = await KiteInstrument.updateMany({ _id: { $in: ids } }, { $set: bulkUpdate });

    if (enabled === false) {
      const disabledInstruments = await KiteInstrument.find({ _id: { $in: ids } }).select('instrument_token').lean();
      try { await cancelPendingOrdersForInstruments(disabledInstruments.map(i => i.instrument_token)); } catch (_) {}
    }

    try {
      const searchService = require('../services/instrumentSearchService');
      searchService.invalidateCache();
    } catch (_) {}

    res.json({ success: true, message: `${result.modifiedCount} instrument(s) ${enabled ? 'enabled' : 'disabled'}`, data: { modified: result.modifiedCount } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// GET /admin/instruments/expiry-summary?segment=MCX-FUT — upcoming expiry
// dates for a segment, one row per expiry, with instrument count and
// current on/off state (mixed state — some enabled, some not, within the
// same expiry batch — is flagged so the UI can show it distinctly instead
// of silently picking one side).
// NOT /instruments/expiries — that path was already taken by an older,
// differently-shaped route a few lines up (a plain array of date strings,
// no count/enabled). Express matches the FIRST registered handler for a
// path, so reusing that name here would have silently made this whole
// route dead code — confirmed live: every field the Expiry Management page
// read came back blank/wrong because every request was actually hitting
// the older route the whole time.
router.get('/instruments/expiry-summary', authenticateAdmin, async (req, res) => {
  try {
    const { segment } = req.query;
    if (!segment) {
      return res.status(400).json({ success: false, message: 'segment is required', data: null });
    }
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const rows = await KiteInstrument.aggregate([
      { $match: { segment, expiry: { $gte: today }, deleted_at: null } },
      {
        $group: {
          _id: '$expiry',
          count: { $sum: 1 },
          enabledCount: { $sum: { $cond: ['$enabled', 1, 0] } },
          // $addToSet dedupes for free — an options expiry with 200+ strikes
          // of the same underlying collapses to one name (e.g. "NIFTY"), not
          // a 200-item list; an MCX expiry shared by several distinct
          // commodities shows each of them.
          rawNames: { $addToSet: '$raw_name' },
        },
      },
      { $sort: { _id: 1 } },
    ]);
    const data = rows.map((r) => ({
      expiry: r._id,
      count: r.count,
      rawNames: r.rawNames.filter(Boolean).sort(),
      enabled: r.enabledCount === r.count,
      mixed: r.enabledCount > 0 && r.enabledCount < r.count,
    }));
    res.json({ success: true, data });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// PUT /admin/instruments/expiry-toggle — bulk enable/disable every
// instrument sharing one exact expiry within a segment, in one call.
// Deliberately skips the cancel-pending-orders step bulk-toggle above does:
// expiry toggling only ever happens after market close, and the existing
// EOD job already cancels every pending order by then, so there is never
// anything left to cancel here — running that check anyway was pure
// wasted work (and, before batching, the actual cause of this endpoint
// timing out on a 6822-instrument NFO-OPT expiry).
router.put('/instruments/expiry-toggle', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('INSTRUMENT_MANAGE'), async (req, res) => {
  try {
    const { segment, expiry, enabled, reason } = req.body;
    if (!segment || !expiry || enabled === undefined) {
      return res.status(400).json({ success: false, message: 'segment, expiry, and enabled are required', data: null });
    }
    const expiryDate = new Date(expiry);
    if (Number.isNaN(expiryDate.getTime())) {
      return res.status(400).json({ success: false, message: 'Invalid expiry date', data: null });
    }
    const nextDay = new Date(expiryDate);
    nextDay.setDate(nextDay.getDate() + 1);
    const filter = { segment, expiry: { $gte: expiryDate, $lt: nextDay }, deleted_at: null };

    const bulkUpdate = enabled === false
      ? { enabled, ban_reason: reason || 'Expiry closed for trading', banned_at: new Date() }
      : { enabled, ban_reason: null, banned_at: null };
    const result = await KiteInstrument.updateMany(filter, { $set: bulkUpdate });

    try {
      const searchService = require('../services/instrumentSearchService');
      searchService.invalidateCache();
    } catch (_) {}

    // Opening a futures expiry by hand: put its contracts on the live feed
    // right away (as the automatic OPEN does) so rollover into them has a
    // price even if nobody is watching them yet. Futures only — an options
    // expiry can exceed the Kite connection's token limit.
    if (enabled !== false && (/-FUT$/.test(segment) || segment === 'GLOBAL')) {
      try {
        const opened = await KiteInstrument.find(filter).select('instrument_token').lean();
        if (opened.length <= 1000) {
          require('../services/livePriceService').ensureSubscribed(opened.map((i) => i.instrument_token));
        }
      } catch (_) {}
    }

    res.json({
      success: true,
      message: `${result.modifiedCount} instrument(s) ${enabled ? 'enabled' : 'disabled'} for ${segment} expiry ${expiryDate.toISOString().slice(0, 10)}`,
      data: { modified: result.modifiedCount },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// ==================== CONTRACT EXPIRY ACTIONS ====================
// Working-day rules for opening the next contract and cutting the current one
// (config/expiryRules.js). Opens run automatically; cuts need a confirm here
// and then run just after that market's close at the closing bid/ask.
const expiryActionService = require('../services/expiryActionService');
const expiryPerm = [authenticateAdmin, requireAdminPermission('INSTRUMENT_MANAGE')];
const expiryWrite = [authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('INSTRUMENT_MANAGE')];
const expiryError = (res, e) => res.status(e.status || 500).json({ success: false, message: sanitizeErrorMessage(e), data: null });

// GET /admin/expiry-actions?from=YYYY-MM-DD&to=YYYY-MM-DD
router.get('/expiry-actions', ...expiryPerm, async (req, res) => {
  try {
    const data = await expiryActionService.list({ from: req.query.from, to: req.query.to });
    res.json({ success: true, data });
  } catch (e) { expiryError(res, e); }
});

// GET /admin/expiry-actions/announcement?date=YYYY-MM-DD — draft "NEW CONTRACT Open" notice
router.get('/expiry-actions/announcement', ...expiryPerm, async (req, res) => {
  try {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(req.query.date || ''))) {
      return res.status(400).json({ success: false, message: 'date (YYYY-MM-DD) is required', data: null });
    }
    res.json({ success: true, data: await expiryActionService.buildAnnouncement(req.query.date) });
  } catch (e) { expiryError(res, e); }
});

// POST /admin/expiry-actions/announcement { message, push } — publish the notice
router.post('/expiry-actions/announcement', ...expiryWrite, async (req, res) => {
  try {
    const data = await expiryActionService.publishAnnouncement({ message: req.body?.message, push: !!req.body?.push, adminId: req.admin?.id, date: req.body?.date });
    res.json({ success: true, message: 'Announcement published', data });
  } catch (e) { expiryError(res, e); }
});

// POST /admin/expiry-actions/:id/(confirm|unconfirm|pause|resume)
router.post('/expiry-actions/:id/:op(confirm|unconfirm|pause|resume)', ...expiryWrite, async (req, res) => {
  try {
    const data = await expiryActionService.transition(req.params.id, req.params.op, req.admin?.id);
    res.json({ success: true, data });
  } catch (e) { expiryError(res, e); }
});

// GET /admin/instruments — list instruments with filters (paginated)
// Shows ALL instruments including soft-deleted ones (admin needs to see them to restore)
router.get('/instruments', authenticateAdmin, async (req, res) => {
  try {
    const { segment, raw_name, expiry, search, enabled, page = 1, limit = 50 } = req.query;
    const filter = {};

    // Default: only show non-expired instruments (indices have no expiry)
    if (!expiry) {
      const today = new Date();
      today.setHours(0, 0, 0, 0);
      filter.$or = filter.$or || [];
      // Will be merged with search $or below if needed
      filter.expiry = { $gte: today };
      // Also include instruments with no expiry (indices)
      delete filter.expiry;
      filter.$and = [
        { $or: [{ expiry: { $gte: today } }, { expiry: null }] }
      ];
    }

    if (segment) filter.segment = segment;
    if (raw_name) filter.raw_name = { $regex: escapeRegex(raw_name), $options: 'i' };
    if (expiry) {
      // Override default expiry filter with specific date
      delete filter.$and;
      const d = new Date(expiry);
      const nextDay = new Date(d);
      nextDay.setDate(nextDay.getDate() + 1);
      filter.expiry = { $gte: d, $lt: nextDay };
    }
    if (enabled === 'true') filter.enabled = true;
    if (enabled === 'false') filter.enabled = false;
    if (search) {
      const safeSearch = escapeRegex(search);
      const searchOr = [
        { tradingsymbol: { $regex: safeSearch, $options: 'i' } },
        { raw_name: { $regex: safeSearch, $options: 'i' } },
        { display_name: { $regex: safeSearch, $options: 'i' } },
      ];
      if (filter.$and) {
        filter.$and.push({ $or: searchOr });
      } else {
        filter.$or = searchOr;
      }
    }

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [instruments, total] = await Promise.all([
      KiteInstrument.find(filter)
        .select('instrument_token tradingsymbol raw_name display_name segment exchange instrument_type expiry strike lot_size enabled ban_reason banned_at nse_banned nse_ban_date is_active last_price deleted_at')
        .sort({ raw_name: 1, instrument_type: 1, expiry: 1 })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      KiteInstrument.countDocuments(filter),
    ]);

    res.json({
      success: true,
      data: instruments,
      pagination: { page: parseInt(page), limit: parseInt(limit), total, pages: Math.ceil(total / parseInt(limit)) },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// PUT /admin/instruments/:id/toggle — enable/disable an instrument
router.put('/instruments/:id/toggle', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('INSTRUMENT_MANAGE'), async (req, res) => {
  try {
    const { enabled, reason } = req.body;
    if (enabled === undefined) {
      return res.status(400).json({ success: false, message: 'enabled field required', data: null });
    }
    const update = enabled === false
      ? { enabled, ban_reason: reason || null, banned_at: new Date() }
      : { enabled, ban_reason: null, banned_at: null };
    const inst = await KiteInstrument.findByIdAndUpdate(req.params.id, update, { new: true });
    if (!inst) return res.status(404).json({ success: false, message: 'Instrument not found', data: null });

    if (enabled === false) {
      try { await cancelPendingOrdersForInstrument(inst.instrument_token); } catch (_) {}
    }

    // Refresh search cache so disabled instruments stop appearing
    try {
      const searchService = require('../services/instrumentSearchService');
      searchService.invalidateCache();
    } catch (_) {}

    res.json({ success: true, message: `Instrument ${enabled ? 'enabled' : 'disabled'}`, data: inst });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// POST /admin/mcx-square-off — closes every open MCX position system-wide,
// in batches, running in the background. Returns immediately with a run id;
// poll GET /admin/mcx-square-off/status/:runId for progress. A manual,
// admin-triggered counterpart to expiry-toggle above — deliberately two
// separate controls (see mcxSquareOffService.js's own header comment).
router.post('/mcx-square-off', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('SETTLEMENT_TRIGGER'), async (req, res) => {
  try {
    const mcxSquareOffService = require('../services/mcxSquareOffService');
    const { runId, totalUsers } = await mcxSquareOffService.startMcxSquareOff(req.admin.id);
    res.json({ success: true, message: `Square-off started for ${totalUsers} user(s) with open MCX positions`, data: { runId, totalUsers } });
  } catch (e) {
    if (e.code === 'ALREADY_RUNNING') {
      return res.status(409).json({ success: false, message: e.message, data: { runId: e.runId } });
    }
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// GET /admin/mcx-square-off/status/:runId — poll progress of a specific run.
router.get('/mcx-square-off/status/:runId', authenticateAdmin, async (req, res) => {
  try {
    const mcxSquareOffService = require('../services/mcxSquareOffService');
    const run = await mcxSquareOffService.getRunStatus(req.params.runId);
    if (!run) return res.status(404).json({ success: false, message: 'Run not found', data: null });
    res.json({ success: true, data: run });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// GET /admin/mcx-square-off/latest — most recent run (running or not), so
// the UI can resume showing progress after a page refresh without needing
// the runId from the original POST response.
router.get('/mcx-square-off/latest', authenticateAdmin, async (req, res) => {
  try {
    const mcxSquareOffService = require('../services/mcxSquareOffService');
    const run = await mcxSquareOffService.getLatestRun('MCX');
    res.json({ success: true, data: run || null });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// DELETE /admin/instruments/:id — soft delete an instrument
router.delete('/instruments/:id', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('INSTRUMENT_MANAGE'), async (req, res) => {
  try {
    const inst = await KiteInstrument.findByIdAndUpdate(req.params.id, { deleted_at: new Date(), enabled: false }, { new: true });
    if (!inst) return res.status(404).json({ success: false, message: 'Instrument not found', data: null });

    try { await cancelPendingOrdersForInstrument(inst.instrument_token, { blockAll: true }); } catch (_) {}

    try {
      const searchService = require('../services/instrumentSearchService');
      searchService.invalidateCache();
    } catch (_) {}

    res.json({ success: true, message: 'Instrument deleted', data: inst });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// PUT /admin/instruments/:id/restore — restore a soft-deleted instrument
router.put('/instruments/:id/restore', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('INSTRUMENT_MANAGE'), async (req, res) => {
  try {
    const inst = await KiteInstrument.findByIdAndUpdate(req.params.id, { deleted_at: null, enabled: true }, { new: true });
    if (!inst) return res.status(404).json({ success: false, message: 'Instrument not found', data: null });

    try {
      const searchService = require('../services/instrumentSearchService');
      searchService.invalidateCache();
    } catch (_) {}

    res.json({ success: true, message: 'Instrument restored', data: inst });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// Trigger bhavcopy settlement price fetch (admin-only)
router.post('/bhavcopy/fetch', authenticateAdmin, requireAdminPermission('SETTLEMENT_TRIGGER'), async (req, res) => {
  try {
    const { date } = req.body; // optional: YYYY-MM-DD string
    const { fetchAndApplyBhavcopy } = require('../services/bhavcopyService');
    const result = await fetchAndApplyBhavcopy(date || undefined);
    res.json({
      success: true,
      message: 'Bhavcopy fetch completed',
      data: {
        nse: result.nseMatched,
        mcx: result.mcxMatched,
        nse_trading_date: result.nseTradingDate,
        mcx_trading_date: result.mcxTradingDate,
        total: Object.keys(result.closePriceMap).length,
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
});

// Settlement
const { startSettlement, getSettlementStatus } = require('../controllers/settlementController');
router.post('/settlement/start', authenticateAdmin, rejectIfAdminWatchOnly, requireAdminPermission('SETTLEMENT_TRIGGER'), startSettlement);
router.get('/settlement/status', authenticateAdmin, getSettlementStatus);

// ==================== ADMIN PROFILE ROUTE ====================
router.get('/profile', authenticateAdmin, async (req, res) => {
  try {
    const Admin = require('../models/Admin');
    const Server = require('../models/Server');
    const admin = await Admin.findById(req.admin.id).lean();
    if (!admin) {
      return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    }

    // Get server info if admin has one assigned
    let serverName = null;
    if (admin.server_id) {
      const server = await Server.findById(admin.server_id).lean();
      serverName = server?.name || admin.server_id.toString();
    }

    res.json({
      success: true,
      data: {
        id: admin._id,
        username: admin.username,
        server_id: serverName || 'N/A',
        last_login: admin.last_login || null,
        created_at: admin.createdAt,
        // Added for the mobile app's Super Admin / permissions UI — the
        // login response already carries these (admin.toJSON()), but this
        // separate profile fetch (used to refresh/re-derive admin state
        // without a fresh login, e.g. after app restart) didn't.
        is_super_admin: !!admin.is_super_admin,
        watch_only: !!admin.watch_only,
        permissions: admin.permissions || [],
        active_status: admin.active_status !== false,
      }
    });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

// ==================== BROKERS (introducing-broker share tracking, admin only) ====================
// Tracking only — see brokerController.js. Static paths before /brokers/:id.
const brokerCtl = require('../controllers/brokerController');
router.get('/brokers', authenticateAdmin, brokerCtl.listBrokers);
router.get('/brokers/earnings', authenticateAdmin, brokerCtl.getEarnings);
router.get('/brokers/client-rates/:userId', authenticateAdmin, brokerCtl.clientRates);
router.put('/brokers/links/:linkId/end', authenticateAdmin, rejectIfAdminWatchOnly, brokerCtl.endLink);
router.post('/brokers', authenticateAdmin, rejectIfAdminWatchOnly, brokerCtl.createBroker);
router.put('/brokers/:id', authenticateAdmin, rejectIfAdminWatchOnly, brokerCtl.updateBroker);
router.delete('/brokers/:id', authenticateAdmin, rejectIfAdminWatchOnly, brokerCtl.deleteBroker);
router.post('/brokers/:id/links', authenticateAdmin, rejectIfAdminWatchOnly, brokerCtl.addLink);

module.exports = router;
