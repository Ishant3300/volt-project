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
      // The master's WHOLE tree (sub-brokers' clients too, any depth) — same
      // scope as Trade Alert; direct clients only left a master whose
      // clients all sit under sub-brokers with an empty log.
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const subtree = await getAllSubMasterIds(callerId);
      const childIds = await User.find({ master_id: { $in: subtree }, deleted_at: null }).distinct('_id');
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

const APP_REJECTION_DEDUP_MS = 10 * 1000;
const APP_REJECTION_PER_MINUTE = 30;

/**
 * POST /api/trade/app-rejection
 * A client's mobile app blocked an order before sending it (stale quote,
 * market closed, lot/qty limit, ...). Saved as a rejected trade so it shows in
 * the Rejection Log like a server-side refusal. Clients only; the remark is
 * built server-side from a fixed reason code. Symbol/exchange come from the
 * instrument record, not the request. A repeat of the same block within 10s
 * is not stored again, and at most 30 are stored per user per minute.
 * Always answers 200 for a well-formed request — the app fires and forgets.
 *
 * Body: { instrument_token, transaction_type, quantity, order_type, price, code, message }
 */
const recordAppRejection = async (req, res) => {
  try {
    if (!req.user) {
      return res.status(403).json({ success: false, message: 'Clients only', data: null });
    }
    const { buildAppBlockRemark } = require('../utils/rejectionLog');
    const KiteInstrument = require('../models/KiteInstrument');
    const { instrument_token, transaction_type, quantity, order_type, price, code, message } = req.body || {};

    const remarks = buildAppBlockRemark(code, message);
    const side = String(transaction_type || '').toUpperCase();
    const token = instrument_token != null ? String(instrument_token) : '';
    if (!remarks || !['BUY', 'SELL'].includes(side) || !/^\d{1,20}$/.test(token)) {
      return res.status(400).json({ success: false, message: 'Invalid app rejection', data: null });
    }

    const instrument = await KiteInstrument.findOne({ instrument_token: { $in: [token, Number(token)] } })
      .select('tradingsymbol exchange').lean();
    if (!instrument?.tradingsymbol || !Trade.schema.path('exchange').enumValues.includes(instrument.exchange)) {
      return res.status(400).json({ success: false, message: 'Unknown instrument', data: null });
    }

    const userId = new mongoose.Types.ObjectId(req.user.id);
    const now = Date.now();
    const recent = await Trade.find({
      user_id: userId,
      status: 'rejected',
      remarks: /^Blocked in app:/,
      createdAt: { $gte: new Date(now - 60 * 1000) },
    }).select('instrument_token remarks createdAt').lean();
    const duplicate = recent.some((t) => t.instrument_token === token && t.remarks === remarks
      && now - new Date(t.createdAt).getTime() < APP_REJECTION_DEDUP_MS);
    if (duplicate || recent.length >= APP_REJECTION_PER_MINUTE) {
      return res.status(200).json({ success: true, message: 'Not stored (repeat)', data: null });
    }

    const rejUser = await User.findById(userId).select('master_id server_id').lean();
    if (!rejUser) return res.status(404).json({ success: false, message: 'User not found', data: null });

    const qty = Number(quantity);
    const px = Number(price);
    const type = String(order_type || 'MARKET').toUpperCase();
    await Trade.create({
      user_id: userId,
      master_id: rejUser.master_id || null,
      // same admin_id fallback as placeTrade's own rejection save
      admin_id: rejUser.server_id || rejUser.master_id || userId,
      instrument_token: token,
      tradingsymbol: instrument.tradingsymbol,
      exchange: instrument.exchange,
      transaction_type: side,
      order_type: ['MARKET', 'LIMIT', 'SL', 'SL-M'].includes(type) ? type : 'MARKET',
      quantity: Number.isFinite(qty) && qty >= 0 ? qty : 0,
      price: Number.isFinite(px) && px >= 0 ? px : 0,
      executed_quantity: 0,
      executed_price: 0,
      status: 'rejected',
      remarks,
    });
    console.log(`📝 [RejectionLog] App-side block saved for user ${req.user.id}: ${remarks.substring(0, 80)}`);
    return res.status(201).json({ success: true, message: 'Saved', data: null });
  } catch (error) {
    return res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

module.exports = { getRejectionLog, recordAppRejection };
