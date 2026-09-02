const Transaction = require('../models/Transaction');
const mongoose = require('mongoose');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/**
 * Get transaction history for a user or master.
 * Query params: target_id (required), target_model (User|Master), page, limit
 */
const getTransactionHistory = async (req, res) => {
  try {
    const { target_id, target_model = 'User', page = 1, limit = 50 } = req.query;

    if (!target_id) {
      return res.status(400).json({ success: false, message: 'target_id is required' });
    }

    // Found via the web portal's client-side security audit: this endpoint
    // had zero ownership check — any master could pass any target_id/
    // target_model and read that account's full credit/debit ledger,
    // including targeting 'Admin'. Admin unrestricted; master scoped to
    // their own subtree, and can never target an Admin's ledger.
    if (req.master) {
      if (target_model === 'Admin') {
        return res.status(403).json({ success: false, message: 'Not authorized to view this transaction history' });
      }
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);

      if (target_model === 'Master') {
        if (!allowedMasterIds.includes(target_id.toString())) {
          return res.status(403).json({ success: false, message: 'Not authorized to view this transaction history' });
        }
      } else {
        const User = require('../models/User');
        const targetUser = await User.findById(target_id).select('master_id').lean();
        if (!targetUser || !allowedMasterIds.includes(targetUser.master_id?.toString())) {
          return res.status(403).json({ success: false, message: 'Not authorized to view this transaction history' });
        }
      }
    }

    // Per-admin master-visibility restriction.
    if (req.admin && target_model !== 'Admin') {
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) {
        if (target_model === 'Master') {
          if (hiddenMasterIds.has(target_id.toString())) {
            return res.status(404).json({ success: false, message: 'Master not found' });
          }
        } else {
          const User = require('../models/User');
          const targetUser = await User.findById(target_id).select('master_id').lean();
          if (targetUser && hiddenMasterIds.has(targetUser.master_id?.toString())) {
            return res.status(404).json({ success: false, message: 'User not found' });
          }
        }
      }
    }

    const filter = {
      userId: new mongoose.Types.ObjectId(target_id),
      userModel: target_model,
      status: 'SUCCESS'
    };

    const skip = (parseInt(page) - 1) * parseInt(limit);
    const [transactions, total] = await Promise.all([
      Transaction.find(filter)
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(parseInt(limit))
        .lean(),
      Transaction.countDocuments(filter)
    ]);

    res.status(200).json({
      success: true,
      data: {
        transactions,
        total,
        page: parseInt(page),
        limit: parseInt(limit)
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = { getTransactionHistory };
