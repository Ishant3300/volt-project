const express = require('express');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');
const router = express.Router();
const { authenticateAdminOrMaster } = require('../middlewares/auth');
const { rejectIfInvestor } = require('../middlewares/rejectIfInvestor');
const { requireAdminPermission } = require('../middlewares/requireAdminPermission');
const { escapeRegex } = require('../utils/escapeRegex');
const User = require('../models/User');
const Master = require('../models/Master');
const LoginHistory = require('../models/LoginHistory');

// Import controllers
const {
  createChildMaster,
  getAllChildMasters,
  getDownlineMasters,
  getChildMasterById,
  updateChildMasterPermissions,
  updateChildMasterDetails,
  creditChildMaster,
  debitChildMaster,
  getChildMasterPosition,
  sendMessageToChildMaster,
  deleteChildMaster
} = require('../controllers/masterChildController');

const {
  createUser,
  getAllUsers,
  getUserById,
  updateUserDetails,
  updateUserIntradaySquareoff,
  updateUserMarginSquareoffPercentage,
  updateUserReportPermissions,
  creditUser,
  debitUser,
  getUserPosition,
  sendMessageToUser,
  deleteUser
} = require('../controllers/masterUserController');

const {
  getAllTrades
} = require('../controllers/masterTradeController');

const {
  getTransactionHistory
} = require('../controllers/transactionController');

const {
  getAggregatedPositions,
  getInstrumentUserBreakdown,
  getUserMetrics,
  getAdminMasterMetrics,
  getBulkEquity,
  getLiveMetrics
} = require('../controllers/masterPositionController');

const { getScriptwisePnl } = require('../controllers/scriptwisePnlController');
const { getTradeAlerts } = require('../controllers/tradeAlertController');

const { getPnlSummary } = require('../controllers/pnlSummaryController');
const { getWeeklyAdminReport } = require('../controllers/weeklyAdminController');
const { getSettlementReport } = require('../controllers/settlementController');

// Category trade-wallet funding (Task 12 / Requirements 5.1–5.7)
const {
  assign: walletAssign,
  withdraw: walletWithdraw,
  getWallet,
} = require('../controllers/walletController');

const {
  generateUsername,
  releaseUsername
} = require('../controllers/usernameController');

// All routes require admin or master authentication
router.use(authenticateAdminOrMaster);

// ============================================
// Wallet Funding Routes (master ↔ direct child)
// ============================================
// authenticateAdminOrMaster (applied above) sets req.master OR req.admin; the
// walletController resolves the actor and enforces direct-child hierarchy for
// masters (admin may act on anyone). walletService owns the Mongo transaction
// + Transaction audit, so no session handling is needed here.

// Assign (fund) a direct child's category wallet from the master's own pool
router.post('/wallet/assign', rejectIfInvestor, walletAssign);

// Withdraw from a direct child's category wallet back to the master's pool
router.post('/wallet/withdraw', rejectIfInvestor, walletWithdraw);

// Read per-category available balances (self or a direct child)
router.get('/wallet', getWallet);

// ============================================
// Username Generation Routes
// ============================================

// Generate a unique 6-digit username (reserved for 5 minutes)
router.get('/username/generate', rejectIfInvestor, generateUsername);

// Release a reserved username if not used
router.post('/username/release', rejectIfInvestor, releaseUsername);

// ============================================
// Child Master Management Routes
// ============================================

// Create child master
router.post('/masters', rejectIfInvestor, createChildMaster);

// Get all child masters
router.get('/masters', getAllChildMasters);
router.get('/downline-masters', getDownlineMasters);

// Get child master by ID
router.get('/masters/:id', getChildMasterById);

// Update child master permissions
router.put('/masters/:id/permissions', rejectIfInvestor, updateChildMasterPermissions);

// Update child master details
router.put('/masters/:id/details', rejectIfInvestor, updateChildMasterDetails);

// Credit child master
router.post('/masters/:id/credit', rejectIfInvestor, creditChildMaster);

// Debit child master
router.post('/masters/:id/debit', rejectIfInvestor, debitChildMaster);

// Get child master position
router.get('/masters/:id/position', getChildMasterPosition);

// Send message to child master
router.post('/masters/:id/messages', rejectIfInvestor, sendMessageToChildMaster);

// Delete child master
router.delete('/masters/:id', rejectIfInvestor, deleteChildMaster);

// ============================================
// User Management Routes
// ============================================

// Create user
router.post('/users', rejectIfInvestor, createUser);

// Get all users
router.get('/users', getAllUsers);

// Get user by ID
router.get('/users/:id', getUserById);

// Update user details
router.put('/users/:id/details', rejectIfInvestor, updateUserDetails);

// Update user (full update)
router.put('/users/:id', rejectIfInvestor, updateUserDetails);

// Update user intraday squareoff settings
router.put('/users/:id/intraday-squareoff', rejectIfInvestor, updateUserIntradaySquareoff);

// Update user margin squareoff percentage
router.put('/users/:id/margin-squareoff-percentage', rejectIfInvestor, updateUserMarginSquareoffPercentage);

// Update user report permissions
router.put('/users/:id/report-permissions', rejectIfInvestor, updateUserReportPermissions);

// Credit user
router.post('/users/:id/credit', rejectIfInvestor, creditUser);

// Debit user
router.post('/users/:id/debit', rejectIfInvestor, debitUser);

// Get user position
router.get('/users/:id/position', getUserPosition);

// Send message to user
router.post('/users/:id/messages', rejectIfInvestor, sendMessageToUser);

// Delete user
router.delete('/users/:id', rejectIfInvestor, deleteUser);

// ============================================
// Trade Management Routes
// ============================================

// Get all trades in hierarchy
router.get('/trades', getAllTrades);

// ============================================
// Transaction History Routes
// ============================================
router.get('/transactions', getTransactionHistory);

// ============================================
// Master Position Aggregation Routes
// ============================================

// Get aggregated positions across all child users
router.get('/positions/aggregated', getAggregatedPositions);

// Get full metrics per child user (6 metrics like user orders page)
router.get('/positions/user-metrics', getUserMetrics);

// Get per-user breakdown for a specific instrument
router.get('/positions/aggregated/:instrumentToken', getInstrumentUserBreakdown);

// Admin: get all masters with their users' positions for live P&L
router.get('/positions/admin-master-metrics', getAdminMasterMetrics);

// Scriptwise P&L summary (Level 1: one row per script) / detail (Level 2:
// one row per user, when exchange+tradingsymbol are both given) across the
// caller's whole hierarchy — see scriptwisePnlController.js.
router.get('/positions/scriptwise-pnl', requireAdminPermission('REPORTS_ACCESS'), getScriptwisePnl);

// Trade Alert (web-only) live-log backfill — see tradeAlertController.js.
// This route/controller existed in the older apex-backend-node repo but was
// never ported when apex-project became the real deployed backend — the web
// Trade Alert page has been calling a 404 the whole time. Restored here
// along with the metricsEngine.broadcastTradeAlert wiring (tradeController.js,
// orderExecutionService.js, priceQueueService.js) that feeds it live.
router.get('/trade-alerts', getTradeAlerts);

// Bulk computed equity for user management list view
router.get('/positions/bulk-equity', getBulkEquity);

// Live metrics from metricsEngine cache (same data as WebSocket push)
router.get('/positions/live-metrics', getLiveMetrics);

// P&L summary: Master sees per-user, Admin sees per-master
router.get('/pnl-summary', getPnlSummary);

// Weekly admin report: Master sees per-user, Admin sees per-master
router.get('/weekly-admin-report', requireAdminPermission('REPORTS_ACCESS'), getWeeklyAdminReport);

// Settlement report: per-user P&L + brokerage for a given date
router.get('/settlement-report', requireAdminPermission('REPORTS_ACCESS'), getSettlementReport);

// ============================================
// Sharing Details Route
// ============================================
router.get('/sharing-details', async (req, res) => {
  try {
    const { master_id } = req.query;
    const role = req.admin ? 'admin' : 'master';
    const callerId = req.admin ? req.admin.id : req.master.id;

    // Determine which master's children to fetch
    const targetMasterId = (role === 'admin' && master_id) ? master_id : callerId;

    // A hidden master's sharing config must never be reachable by direct ID.
    if (role === 'admin' && master_id) {
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds && hiddenMasterIds.has(targetMasterId.toString())) {
        return res.status(404).json({ success: false, message: 'Master not found', data: null });
      }
    }

    // Fetch the master itself
    const master = await Master.findOne({ _id: targetMasterId, deleted_at: null })
      .select('name username pnl_sharing brokerage_sharing')
      .lean();

    // Fetch child masters under this master
    const childMasters = await Master.find({ master_id: targetMasterId, deleted_at: null })
      .select('name username pnl_sharing brokerage_sharing')
      .sort({ createdAt: -1 })
      .lean();

    // Fetch users under this master
    const users = await User.find({ master_id: targetMasterId, deleted_at: null })
      .select('name username pnl_sharing brokerage_sharing')
      .sort({ createdAt: -1 })
      .lean();

    const formatEntry = (doc, role) => ({
      id: doc._id,
      name: doc.name,
      username: doc.username,
      role,
      pnl_sharing: doc.pnl_sharing || 0,
      brokerage_sharing: doc.brokerage_sharing || 0,
    });

    const data = {
      master: master ? formatEntry(master, 'MASTER') : null,
      children: [
        ...childMasters.map(m => formatEntry(m, 'MASTER')),
        ...users.map(u => formatEntry(u, 'USER')),
      ],
    };

    res.status(200).json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
});

// ============================================
// Login History Route
// ============================================
router.get('/login-history', async (req, res) => {
  try {
    const { search, page = 1, limit = 50 } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    const role = req.admin ? 'admin' : 'master';
    const callerId = req.admin ? req.admin.id : req.master.id;

    // Build filter: admin sees all except hidden masters' own + their subtree's
    // history, master sees own children + self
    const filter = {};
    if (role === 'master') {
      // Get the full recursive subtree of sub-master IDs (inclusive of self)
      // and every user under any of them. Previously this queried
      // `Master.find({ parent_master_id: callerId })` — that field doesn't
      // exist on the Master schema (the real parent-link field is
      // `master_id`, per masterHierarchyService.js), so childMasterIds was
      // always empty: no sub-master's login history ever surfaced here, and
      // by extension neither did any user under a sub-master (only direct
      // child users of the calling master itself were ever included).
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const subtreeMasterIds = await getAllSubMasterIds(callerId);
      const subtreeUserIds = await User.find({ master_id: { $in: subtreeMasterIds }, deleted_at: null }).distinct('_id');
      const mongoose = require('mongoose');
      const subtreeMasterObjectIds = subtreeMasterIds.map(id => new mongoose.Types.ObjectId(id));
      filter.userId = { $in: [...subtreeMasterObjectIds, ...subtreeUserIds] };
    } else {
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds && hiddenMasterIds.size > 0) {
        const hiddenIdList = [...hiddenMasterIds];
        const hiddenUserIds = await User.find({ master_id: { $in: hiddenIdList }, deleted_at: null }).distinct('_id');
        filter.userId = { $nin: [...hiddenIdList, ...hiddenUserIds] };
      }
    }

    if (search) {
      const safeSearch = escapeRegex(search);
      filter.$or = [
        { username: { $regex: safeSearch, $options: 'i' } },
        { name: { $regex: safeSearch, $options: 'i' } },
      ];
    }

    const [entries, total] = await Promise.all([
      LoginHistory.find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      LoginHistory.countDocuments(filter)
    ]);

    // Map to consistent shape
    const data = entries.map(e => ({
      _id: e._id,
      username: e.username,
      name: e.name,
      role: e.userModel?.toUpperCase() || 'USER',
      ip_address: e.ip_address,
      logged_in_at: e.createdAt,
    }));

    res.status(200).json({ success: true, data, total, page: parseInt(page), limit: parseInt(limit) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
});

// ==================== TOTP ROUTES (master's own two-factor auth) ====================
// Same totpService adminRoutes.js uses for Admin — see that file's own
// header. Self-service only, same as Admin's equivalent routes: a master
// manages their OWN TOTP here, an admin caller is rejected rather than
// silently operating on nothing (this router mounts under
// authenticateAdminOrMaster, which admin routes also share, so req.admin
// can be set here without req.master).
const totpService = require('../services/totpService');

function requireMasterSelf(req, res, next) {
  if (!req.master || !req.master.id) {
    return res.status(403).json({ success: false, message: 'Only a master account can manage its own TOTP', data: null });
  }
  next();
}

router.get('/totp/status', requireMasterSelf, async (req, res) => {
  try {
    const status = await totpService.getTotpStatus(Master, req.master.id);
    if (!status) return res.status(404).json({ success: false, message: 'Master not found', data: null });
    res.json({ success: true, data: status });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/generate', requireMasterSelf, async (req, res) => {
  try {
    const result = await totpService.generateSecret(Master, req.master.id);
    res.json({ success: true, data: { qr_data_url: result.qrDataUrl, secret: result.secret } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/verify-setup', requireMasterSelf, async (req, res) => {
  try {
    const { token } = req.body;
    if (!token) return res.status(400).json({ success: false, message: 'TOTP code required', data: null });
    const verified = await totpService.verifySetup(Master, req.master.id, token);
    if (!verified) return res.status(400).json({ success: false, message: 'Invalid TOTP code', data: null });
    res.json({ success: true, message: 'TOTP activated successfully' });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/toggle', requireMasterSelf, async (req, res) => {
  try {
    const { enabled } = req.body;
    if (enabled === undefined) return res.status(400).json({ success: false, message: 'enabled field required', data: null });
    await totpService.toggleTotp(Master, req.master.id, enabled);
    res.json({ success: true, message: `TOTP ${enabled ? 'enabled' : 'disabled'}` });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

router.post('/totp/reset', requireMasterSelf, async (req, res) => {
  try {
    await totpService.resetTotp(Master, req.master.id);
    res.json({ success: true, message: 'TOTP reset successfully' });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
});

module.exports = router;
