/**
 * Master Hierarchy Service
 * Recursively resolves all sub-master IDs in the tree under a given master.
 */
const Master = require('../models/Master');

/**
 * Get all master IDs in the hierarchy under a given master (inclusive).
 * Returns: [masterId, subMaster1Id, subSubMaster1Id, ...]
 */
const getAllSubMasterIds = async (masterId) => {
  const result = [masterId];
  const queue = [masterId];

  while (queue.length > 0) {
    const currentId = queue.shift();
    const children = await Master.find(
      { master_id: currentId, deleted_at: null },
      '_id'
    ).lean();

    for (const child of children) {
      const childId = child._id.toString();
      result.push(childId);
      queue.push(childId);
    }
  }

  return result;
};

/**
 * Expands an Admin's `hidden_master_ids` (each toggled off individually by
 * a Super Admin) into the full set of master IDs that Admin must never see
 * — hiding a master hides its entire downstream tree too, not just that
 * one record, using the same subtree walk getAllSubMasterIds already does.
 *
 * Returns a Set of string master IDs. Super Admin (or an admin with
 * nothing hidden) gets an empty Set — every call site below treats an
 * empty Set as "no filter, unrestricted," matching every other admin
 * capability in this codebase defaulting to unrestricted.
 */
const getAdminHiddenMasterIds = async (admin) => {
  const result = new Set();
  if (!admin || admin.isSuperAdmin) return result;

  const hidden = admin.hiddenMasterIds || [];
  if (hidden.length === 0) return result;

  for (const id of hidden) {
    const subtree = await getAllSubMasterIds(id.toString());
    subtree.forEach((t) => result.add(t));
  }
  return result;
};

module.exports = { getAllSubMasterIds, getAdminHiddenMasterIds };
