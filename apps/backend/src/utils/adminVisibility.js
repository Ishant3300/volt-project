const { getAdminHiddenMasterIds } = require('../services/masterHierarchyService');

/**
 * Resolves the calling admin's hidden-master filter for one request.
 *
 * Returns `null` when there's nothing to filter (not an admin call at all,
 * Super Admin, or a regular Admin with no masters hidden) — every call
 * site treats `null` as "unrestricted," the same default every other
 * admin capability in this codebase already has. Returns a non-empty
 * `Set<string>` of master IDs (already expanded to include every hidden
 * master's full sub-master tree) otherwise.
 */
async function resolveHiddenMasterIds(req) {
  if (!req.admin) return null;
  const hidden = await getAdminHiddenMasterIds(req.admin);
  return hidden.size > 0 ? hidden : null;
}

module.exports = { resolveHiddenMasterIds };
