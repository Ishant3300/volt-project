const Trade = require('../models/Trade');
const User = require('../models/User');
const mongoose = require('mongoose');
const { escapeRegex } = require('../utils/escapeRegex');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/**
 * GET /api/trade/rejection-log
 * Returns cancelled, rejected, and soft-deleted trades.
 * 
 * Role-based:
 *   User:  own trades only
 *   Master: trades of child users
 *   Admin:  all trades
 *
 * Query: page, limit, search (tradingsymbol)
 */
const getRejectionLog = async (req, res) => {
  try {
    const { page = 1, limit = 50, search, user_id } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    const role = req.admin ? 'admin' : req.master ? 'master' : 'user';
    const callerId = req.admin?.id || req.master?.id || req.user?.id;

    // Base filter: cancelled/rejected OR deleted by an admin. The weekly
    // settlement also marks every completed trade of the week deleted
    // (deleted_at + settlement_run_id — an archive, not a rejection), which
    // flooded this log with ordinary settled trades; those are left out.
    const filter = {
      $or: [
        { status: { $in: ['cancelled', 'rejected'] } },
        { deleted_at: { $ne: null }, settlement_run_id: null },
      ],
    };

    // If a specific user_id is requested (from username_view), filter to that user
    if (user_id && role === 'master') {
      // A master-supplied user_id must be in the caller's own subtree —
      // this previously had no ownership check at all, letting any master
      // read any user's rejection log platform-wide.
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(callerId);
      const targetUser = await User.findById(user_id).select('master_id').lean();
      if (!targetUser || !allowedMasterIds.includes(targetUser.master_id?.toString())) {
        return res.status(403).json({ success: false, message: 'Not authorized to view this user\'s rejection log' });
      }
      filter.user_id = new mongoose.Types.ObjectId(user_id);
    } else if (user_id && role === 'admin') {
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) {
        const targetUser = await User.findById(user_id).select('master_id').lean();
        if (targetUser && hiddenMasterIds.has(targetUser.master_id?.toString())) {
          return res.status(404).json({ success: false, message: 'User not found' });
        }
      }
      filter.user_id = new mongoose.Types.ObjectId(user_id);
    } else if (role === 'user') {
      filter.user_id = new mongoose.Types.ObjectId(callerId);
    } else if (role === 'master') {
      const childIds = await User.find({ master_id: callerId, deleted_at: null }).distinct('_id');
      filter.user_id = { $in: childIds };
    } else {
      // admin without user_id: no user filter, except to exclude hidden masters' users.
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) {
        const hiddenUserIds = await User.find({ master_id: { $in: [...hiddenMasterIds] } }).distinct('_id');
        filter.user_id = { $nin: hiddenUserIds };
      }
    }

    if (search) {
      filter.tradingsymbol = { $regex: escapeRegex(search), $options: 'i' };
    }

    const [trades, total] = await Promise.all([
      Trade.find(filter)
        .sort({ updatedAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .populate('user_id', 'username name')
        .lean(),
      Trade.countDocuments(filter),
    ]);

    const data = trades.map(t => ({
      id: t._id,
      tradingsymbol: t.tradingsymbol,
      exchange: t.exchange,
      transaction_type: t.transaction_type,
      order_type: t.order_type,
      quantity: t.quantity,
      price: t.price,
      status: t.deleted_at ? 'deleted' : t.status,
      remarks: t.remarks || '',
      username: t.user_id?.username || 'Unknown',
      name: t.user_id?.name || '',
      executed_at: t.executed_at,
      created_at: t.createdAt,
      updated_at: t.updatedAt,
      deleted_at: t.deleted_at,
    }));

    res.status(200).json({ success: true, data, total, page: parseInt(page) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = { getRejectionLog };
