const express = require('express');
const router = express.Router();
const {
  createAdmin,
  getAllAdmins,
  getAdminById,
  updateAdminPermissions,
  updateAdminMasterVisibility,
  updateAdminStatus,
  resetAdminPassword,
  deleteAdmin,
} = require('../controllers/superAdminController');
const { authenticateAdmin } = require('../middlewares/auth');
const { requireSuperAdmin } = require('../middlewares/requireSuperAdmin');

// Every route here requires an authenticated Admin AND the is_super_admin
// flag — a regular Admin, even with every permissions[] key granted, gets
// a 403 from requireSuperAdmin on all of these.
router.use(authenticateAdmin, requireSuperAdmin);

router.post('/admins', createAdmin);
router.get('/admins', getAllAdmins);
router.get('/admins/:id', getAdminById);
router.put('/admins/:id/permissions', updateAdminPermissions);
router.put('/admins/:id/master-visibility', updateAdminMasterVisibility);
router.put('/admins/:id/status', updateAdminStatus);
router.put('/admins/:id/password', resetAdminPassword);
router.delete('/admins/:id', deleteAdmin);

module.exports = router;
