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

/**
 * "Create account for" — a master creating a client or sub-master ON BEHALF
 * of a master in their own downline (e.g. harry creating a client that
 * belongs to his sub-master vijay). Resolves which master becomes the new
 * account's parent: `req.body.for_master_id` when given, else the caller.
 * Everything downstream (balance debit, account limit, brokerage copy/floor,
 * group allotment, sharing caps) then keys off this id, so the account is
 * owned by — and funded by — that master, not the one who pressed Create.
 * Throws an Error with `status: 403` if the target isn't in the caller's
 * downline.
 */
async function resolveCreateParentId(req) {
  const selfId = String(req.master.id);
  const forId = req.body && req.body.for_master_id ? String(req.body.for_master_id) : null;
  if (!forId || forId === selfId) return selfId;
  const downline = await getAllSubMasterIds(selfId);
  if (!downline.includes(forId)) {
    const err = new Error('Not authorized to create accounts for this master');
    err.status = 403;
    throw err;
  }
  return forId;
}

module.exports = { getAllSubMasterIds, getAdminHiddenMasterIds, resolveCreateParentId };
