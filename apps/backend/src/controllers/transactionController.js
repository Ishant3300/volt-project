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

    // Transaction.js stores Mongoose's default camelCase fields
    // (createdAt/balanceBefore/balanceAfter) with no toJSON transform, and
    // .lean() bypasses one even if it existed — every other endpoint in this
    // API returns snake_case, so the web client only ever coded against
    // created_at/balance_after/balance_before, which this endpoint never
    // actually sent (confirmed live: the web ledger's "Client credit &
    // debit history" panel showed "—" for Time and Balance after on every
    // row). Mobile's transaction_page.dart already reads the ORIGINAL
    // camelCase fields directly and is live in production today — both are
    // included here rather than renaming outright, so this fix doesn't
    // silently break the already-shipped mobile app the moment this
    // deploys.
    const mappedTransactions = transactions.map((t) => ({
      id: t._id,
      type: t.type,
      amount: t.amount,
      balanceBefore: t.balanceBefore,
      balanceAfter: t.balanceAfter,
      balance_before: t.balanceBefore,
      balance_after: t.balanceAfter,
      userId: t.userId,
      userModel: t.userModel,
      user_id: t.userId,
      user_model: t.userModel,
      createdAt: t.createdAt,
      created_at: t.createdAt,
    }));

    res.status(200).json({
      success: true,
      data: {
        transactions: mappedTransactions,
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
