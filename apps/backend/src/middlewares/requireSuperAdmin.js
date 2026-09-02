/**
 * Middleware: restrict a route to the Super Admin only.
 *
 * Apply AFTER authenticateAdmin (req.admin.isSuperAdmin is populated there
 * from the DB-fetched Admin doc, not the JWT payload). Used for the
 * admin-management endpoints themselves (superAdminController.js) — a
 * regular Admin, even with every permissions[] key granted, can never
 * create/edit/disable another Admin account.
 */
const requireSuperAdmin = (req, res, next) => {
  if (!req.admin || !req.admin.isSuperAdmin) {
    return res.status(403).json({
      success: false,
      message: 'Super Admin access required',
      data: null
    });
  }
  next();
};

module.exports = { requireSuperAdmin };
