const express = require('express');
const router = express.Router();
const { authenticateAdminOrMaster, authenticateAdmin } = require('../middlewares/auth');
const { rejectIfInvestor } = require('../middlewares/rejectIfInvestor');
const { requireAdminPermission } = require('../middlewares/requireAdminPermission');
const { rejectIfAdminWatchOnly } = require('../middlewares/rejectIfAdminWatchOnly');
const {
  createMaster,
  getAllMasters,
  getMasterById,
  updateMaster,
  updateMasterStatus,
  updateMasterPermissions,
  updateMasterDetails,
  updateMasterIntradaySquareoff,
  updateMasterMarginSquareoffPercentage,
  deleteMaster,
  creditMaster,
  debitMaster,
  getAllTrades,
  getMasterPosition,
  sendMessageToMaster,
  getAccountLimit,
  updateAccountLimit,
  getMasterBaseRates,
  updateMasterBaseRates
} = require('../controllers/masterController');


// Master CRUD
router.post('/', authenticateAdmin, createMaster);
router.get('/', authenticateAdminOrMaster, getAllMasters);

// Trades (admin can see all trades) — must be before /:id to avoid matching
router.get('/trades/all', authenticateAdminOrMaster, getAllTrades);

router.get('/:id', authenticateAdminOrMaster, getMasterById);
router.put('/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMaster);
router.delete('/:id', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), deleteMaster);

// Status management
router.put('/:id/status', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMasterStatus);

// Permission management
router.put('/:id/permissions', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMasterPermissions);

// Details management
router.put('/:id/details', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMasterDetails);

// Intraday Squareoff Settings
router.put('/:id/intraday-squareoff', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMasterIntradaySquareoff);

// Margin Squareoff Percentage
router.put('/:id/margin-squareoff-percentage', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMasterMarginSquareoffPercentage);

// Credit/Debit operations
router.post('/:id/credit', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), creditMaster);
router.post('/:id/debit', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), debitMaster);

// Position
router.get('/:id/position', authenticateAdminOrMaster, getMasterPosition);

// Messaging
router.post('/:id/messages', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, sendMessageToMaster);

// Account Limit
router.get('/:id/account-limit', authenticateAdminOrMaster, getAccountLimit);
router.put('/:id/account-limit', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateAccountLimit);

// Base rates
router.get('/:id/base-rates', authenticateAdminOrMaster, getMasterBaseRates);
router.put('/:id/base-rates', authenticateAdminOrMaster, rejectIfInvestor, rejectIfAdminWatchOnly, requireAdminPermission('MASTER_EDIT_ANY'), updateMasterBaseRates);

module.exports = router;
