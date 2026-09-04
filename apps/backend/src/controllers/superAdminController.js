const bcrypt = require('bcryptjs');
const Admin = require('../models/Admin');
const { ADMIN_PERMISSION_KEYS } = require('../constants/adminPermissions');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/**
 * Admin-management surface — Super Admin only (requireSuperAdmin, mounted
 * on every route in superAdminRoutes.js). None of these endpoints ever
 * accept or return a way to set `is_super_admin` — there is exactly one
 * Super Admin (promoted once via scripts/promoteSuperAdmin.js), not a role
 * this API can grant to anyone else.
 */

// Create a new (regular) Admin. Defaults to every permission key granted —
// per the architecture decision, a new Admin starts with full access and
// the Super Admin restricts it afterward via updatePermissions, rather
// than starting scoped-down.
const createAdmin = async (req, res) => {
  try {
    const { username, password, permissions } = req.body;

    if (!username || !password) {
      return res.status(400).json({
        success: false,
        message: 'username and password are required',
        data: null
      });
    }

    const existing = await Admin.findOne({ username });
    if (existing) {
      return res.status(400).json({
        success: false,
        message: 'Username already exists',
        data: null
      });
    }

    const grantedPermissions = Array.isArray(permissions) ? permissions : [...ADMIN_PERMISSION_KEYS];
    const invalid = grantedPermissions.filter((p) => !ADMIN_PERMISSION_KEYS.includes(p));
    if (invalid.length > 0) {
      return res.status(400).json({
        success: false,
        message: `Invalid permission key(s): ${invalid.join(', ')}`,
        data: null
      });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const admin = await Admin.create({
      username,
      password: hashedPassword,
      permissions: grantedPermissions,
      created_by: req.admin.id,
    });

    res.status(201).json({
      success: true,
      message: 'Admin created successfully',
      data: admin.toJSON()
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

const getAllAdmins = async (req, res) => {
  try {
    const admins = await Admin.find({ deleted_at: null }).sort({ createdAt: -1 });
    res.status(200).json({
      success: true,
      message: 'Admins retrieved successfully',
      data: admins.map((a) => a.toJSON())
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

const getAdminById = async (req, res) => {
  try {
    const admin = await Admin.findOne({ _id: req.params.id, deleted_at: null });
    if (!admin) {
      return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    }
    res.status(200).json({ success: true, message: 'Admin retrieved successfully', data: admin.toJSON() });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// Update an admin's granted permission keys and/or watch-only flag. Never
// touches is_super_admin — see the file header.
const updateAdminPermissions = async (req, res) => {
  try {
    const { permissions, watch_only } = req.body;
    const admin = await Admin.findOne({ _id: req.params.id, deleted_at: null });
    if (!admin) {
      return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    }
    if (admin.is_super_admin) {
      return res.status(403).json({
        success: false,
        message: 'Cannot edit the Super Admin\'s own permissions',
        data: null
      });
    }

    if (permissions !== undefined) {
      if (!Array.isArray(permissions)) {
        return res.status(400).json({ success: false, message: 'permissions must be an array', data: null });
      }
      const invalid = permissions.filter((p) => !ADMIN_PERMISSION_KEYS.includes(p));
      if (invalid.length > 0) {
        return res.status(400).json({
          success: false,
          message: `Invalid permission key(s): ${invalid.join(', ')}`,
          data: null
        });
      }
      admin.permissions = permissions;
    }

    if (watch_only !== undefined) {
      admin.watch_only = !!watch_only;
    }

    await admin.save();
    res.status(200).json({ success: true, message: 'Permissions updated successfully', data: admin.toJSON() });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// Enable/disable an admin account. Guards against a Super Admin locking
// themselves out — self-status changes are never allowed through this
// endpoint, same reasoning as updateAdminPermissions blocking self-edit.
const updateAdminStatus = async (req, res) => {
  try {
    const { active_status } = req.body;
    if (active_status === undefined) {
      return res.status(400).json({ success: false, message: 'active_status is required', data: null });
    }
    if (req.params.id === req.admin.id) {
      return res.status(403).json({ success: false, message: 'Cannot change your own account status', data: null });
    }

    const admin = await Admin.findOne({ _id: req.params.id, deleted_at: null });
    if (!admin) {
      return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    }
    if (admin.is_super_admin) {
      return res.status(403).json({ success: false, message: 'Cannot disable the Super Admin', data: null });
    }

    admin.active_status = !!active_status;
    // Disabling invalidates every active session immediately — enforced via
    // active_status in middlewares/auth.js's authenticateAdmin (Admin/Master
    // are intentionally allowed multiple concurrent devices/tokens, so
    // active_token itself is no longer what's checked there). Still cleared
    // here for hygiene, not because it gates anything on its own now.
    if (admin.active_status === false) {
      admin.active_token = null;
    }
    await admin.save();

    res.status(200).json({ success: true, message: 'Admin status updated successfully', data: admin.toJSON() });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// Replace an admin's hidden-master list wholesale (matches the "select all
// by default, toggle individual ones off" UI — the client sends the full
// current OFF set each time, same pattern as updateAdminPermissions).
const updateAdminMasterVisibility = async (req, res) => {
  try {
    const { hidden_master_ids } = req.body;
    if (!Array.isArray(hidden_master_ids)) {
      return res.status(400).json({ success: false, message: 'hidden_master_ids must be an array', data: null });
    }

    const admin = await Admin.findOne({ _id: req.params.id, deleted_at: null });
    if (!admin) {
      return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    }
    if (admin.is_super_admin) {
      return res.status(403).json({
        success: false,
        message: 'Cannot restrict master visibility for the Super Admin',
        data: null
      });
    }

    admin.hidden_master_ids = hidden_master_ids;
    await admin.save();

    res.status(200).json({ success: true, message: 'Master visibility updated successfully', data: admin.toJSON() });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// Soft delete. Same self-protection as updateAdminStatus.
const deleteAdmin = async (req, res) => {
  try {
    if (req.params.id === req.admin.id) {
      return res.status(403).json({ success: false, message: 'Cannot delete your own account', data: null });
    }

    const admin = await Admin.findOne({ _id: req.params.id, deleted_at: null });
    if (!admin) {
      return res.status(404).json({ success: false, message: 'Admin not found', data: null });
    }
    if (admin.is_super_admin) {
      return res.status(403).json({ success: false, message: 'Cannot delete the Super Admin', data: null });
    }

    admin.deleted_at = new Date();
    admin.active_token = null;
    await admin.save();

    res.status(200).json({ success: true, message: 'Admin deleted successfully', data: null });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

module.exports = {
  createAdmin,
  getAllAdmins,
  getAdminById,
  updateAdminPermissions,
  updateAdminMasterVisibility,
  updateAdminStatus,
  deleteAdmin,
};
