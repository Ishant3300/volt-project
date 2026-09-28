'use strict';

/**
 * Master caller setting a script-quantity row: may it, and up to what max?
 * Shared by the single create/update (adminController) and bulk-create
 * (groupedQuantityController) routes so web and mobile get the same rule.
 *
 * A master may set limits for itself, for any sub-broker anywhere below it,
 * and for any client anywhere in its tree (sub-brokers' clients included),
 * not only its direct clients. The cap on max_qty:
 *   - itself: Admin's global limit for the script;
 *   - a client: that client's own Group for the exchange — not the master's
 *     own ScriptQuantity value; a master can lower a client's limit within
 *     the group's max, raising above it needs a group switch first (see
 *     reseedUserScriptQuantityForExchange);
 *   - a sub-broker: its own Group for the exchange (script_quantity_groups),
 *     else Admin's global limit when it has none.
 * Returns { error: { status, message } } or { ceiling }.
 */
const User = require('../models/User');
const Master = require('../models/Master');
const GroupedQuantity = require('../models/GroupedQuantity');
const ScriptQuantity = require('../models/ScriptQuantity');
const { getAllSubMasterIds } = require('./masterHierarchyService');

async function masterScriptQtyGate(masterId, ownerId, ownerType, exchangeName, scriptName) {
  const ownerIdStr = ownerId.toString();
  const normalizedExchange = exchangeName.toUpperCase();
  const adminCeiling = async () => {
    const adminGlobal = await ScriptQuantity.findOne({ owner_type: 'Admin', exchange_name: exchangeName, script_name: scriptName, deleted_at: null }).lean();
    if (!adminGlobal) return { error: { status: 400, message: 'Admin has not set a global limit for this script' } };
    return { ceiling: adminGlobal.max_qty };
  };
  const groupCeiling = async (groupName) => {
    const groupLimit = await GroupedQuantity.findOne({ exchange_name: normalizedExchange, lot_name: groupName, raw_name: scriptName, deleted_at: null }).lean();
    if (!groupLimit) return { error: { status: 400, message: `No limit found in group "${groupName}" for this script` } };
    return { ceiling: groupLimit.max_qty };
  };

  if (ownerIdStr === masterId.toString()) return adminCeiling();

  const subtree = (await getAllSubMasterIds(masterId)).map(String);

  if (ownerType === 'User') {
    const targetUser = await User.findById(ownerIdStr).select('master_id exchanges_allowed').lean();
    if (!targetUser || !targetUser.master_id || !subtree.includes(targetUser.master_id.toString())) {
      return { error: { status: 403, message: 'Not authorized to edit this user' } };
    }
    const userExchange = (targetUser.exchanges_allowed || []).find(ex => ex.exchange_name === normalizedExchange);
    if (!userExchange || !userExchange.group_name) {
      return { error: { status: 400, message: 'This user has no group assigned for this exchange' } };
    }
    return groupCeiling(userExchange.group_name);
  }

  if (ownerType === 'Master') {
    if (!subtree.includes(ownerIdStr)) {
      return { error: { status: 403, message: 'Not authorized to edit this master' } };
    }
    const subMaster = await Master.findById(ownerIdStr).select('script_quantity_groups').lean();
    const own = (subMaster?.script_quantity_groups || []).find(g => g.exchange_name === normalizedExchange);
    return own && own.group_name ? groupCeiling(own.group_name) : adminCeiling();
  }

  return { error: { status: 403, message: 'Not authorized to edit this owner type' } };
}

module.exports = { masterScriptQtyGate };
