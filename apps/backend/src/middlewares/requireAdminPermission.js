/**
 * Middleware factory: gate a route behind one of ADMIN_PERMISSION_KEYS.
 *
 * Apply AFTER authenticateAdmin/authenticateAdminOrMaster on an
 * admin-reachable route that also needs a Master to pass through
 * unaffected — this middleware only ever rejects an Admin, never a Master
 * (Master's own authority is governed entirely by the existing
 * getAllSubMasterIds subtree checks elsewhere, unrelated to this system).
 *
 * Super Admin bypasses unconditionally — same authority as a regular
 * Admin plus admin-management, not gated by permissions[] at all. A
 * regular Admin needs `key` in their permissions[] array (set by a Super
 * Admin, defaults to every key at creation per the architecture plan).
 */
const requireAdminPermission = (key) => (req, res, next) => {
  if (!req.admin) return next(); // not an admin route at all — nothing to gate
  if (req.admin.isSuperAdmin) return next();
  if (Array.isArray(req.admin.permissions) && req.admin.permissions.includes(key)) return next();

  return res.status(403).json({
    success: false,
    message: `Missing required permission: ${key}`,
    data: null
  });
};

module.exports = { requireAdminPermission };
