const express = require('express');
const { authenticateAdmin } = require('../middlewares/auth');
const { requireAdminPermission } = require('../middlewares/requireAdminPermission');
const { rejectIfAdminWatchOnly } = require('../middlewares/rejectIfAdminWatchOnly');
const controller = require('../controllers/accountTransferController');

// Admin → Transfer Accounts (mounted at /api/admin/account-transfers). Admin
// only — Super Admin, or an Admin granted ACCOUNT_TRANSFER; never a master.
const router = express.Router();
const gate = [authenticateAdmin, requireAdminPermission('ACCOUNT_TRANSFER')];

router.get('/preview', ...gate, controller.preview);
router.get('/', ...gate, controller.list);
router.get('/:id', ...gate, controller.detail);
router.post('/', ...gate, rejectIfAdminWatchOnly, controller.transfer);
router.post('/:id/undo', ...gate, rejectIfAdminWatchOnly, controller.undo);

module.exports = router;
