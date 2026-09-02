/**
 * Middleware: block write operations for a watch-only Admin.
 *
 * Mirrors rejectIfInvestor.js's shape but for the Admin tier's own
 * read-only mode. `watch_only` is a restriction, not a grant, so it's
 * checked independently of permissions[] and overrides it — a watch-only
 * Admin is blocked here even if every permissions[] key is also granted.
 * Super Admin is never watch-only (not meaningful for the account that
 * manages every other Admin) and is not checked here at all.
 *
 * Apply AFTER authenticateAdmin/authenticateAdminOrMaster on every
 * mutating admin-reachable route, alongside (before or after,
 * order doesn't matter) any requireAdminPermission(key) on the same route.
 */
const rejectIfAdminWatchOnly = (req, res, next) => {
  if (req.admin && !req.admin.isSuperAdmin && req.admin.watchOnly === true) {
    return res.status(403).json({
      success: false,
      message: 'This action is not available in watch-only mode',
      data: { watch_only: true }
    });
  }
  next();
};

module.exports = { rejectIfAdminWatchOnly };
