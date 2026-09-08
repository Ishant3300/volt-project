const Trade = require('../models/Trade');
const Master = require('../models/Master');
const KiteInstrument = require('../models/KiteInstrument');
const { escapeRegex } = require('../utils/escapeRegex');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

// Enrich trades with correct lot_size from KiteInstrument
const enrichTradesWithLotSize = async (trades) => {
    const uniqueTokens = [...new Set(trades.map(t => t.instrument_token))];
    const instruments = await KiteInstrument.find(
        { instrument_token: { $in: uniqueTokens } },
        'instrument_token lot_size segment'
    );
    const lotSizeMap = {};
    instruments.forEach(inst => {
        lotSizeMap[inst.instrument_token] = { lot_size: inst.lot_size || 1, segment: inst.segment || '' };
    });
    return trades.map(plain => {
        const info = lotSizeMap[plain.instrument_token] || { lot_size: 1, segment: '' };
        plain.lot_size = info.lot_size || 1;
        if (!plain.segment) plain.segment = info.segment;
        return plain;
    });
};

// Get All Trades in Hierarchy
const getAllTrades = async (req, res) => {
  try {
    const { master_id, user_id, page = 1, limit = 50, date_from, date_to, status, exchange, tradingsymbol } = req.query;

    const filter = {
      deleted_at: null,
      trade_type: { $nin: ['carry_forward'] }, // Hide system carry-forward trades from orders
    };

    // Admin calling with master_id: fetch trades for that master and its children
    if (req.admin && master_id) {
      const targetMaster = await Master.findById(master_id);
      if (!targetMaster) {
        return res.status(404).json({ success: false, message: 'Master not found', data: null });
      }
      const childMasters = await Master.find({ master_id: master_id, deleted_at: null }).select('_id');
      const masterIds = childMasters.map(m => m._id);
      masterIds.push(targetMaster._id);
      filter.master_id = { $in: masterIds };
    } else if (req.admin) {
      // Admin without master_id: return all trades (no filter needed)
    } else {
      // Master flow
      const currentMaster = await Master.findById(req.master.id);

      if (!currentMaster) {
        return res.status(404).json({
          success: false,
          message: 'Master not found',
          data: null
        });
      }

      // Previously direct-children-only on both branches below, unlike the
      // sibling endpoint GET /api/masters/trades/all (masterController.js's
      // getAllTrades, same name, different file) which already used the
      // full recursive subtree — despite the web frontend's own api.ts
      // comment claiming these two were "the same handler." A master's
      // fraud-detection scanner and other "all my downstream trades" views
      // (which call this endpoint, not the /masters/trades/all one) never
      // saw trades placed under a grandchild+ sub-broker. Reads elsewhere
      // in this codebase (e.g. getChildMasterById) already use the full
      // subtree, so this brings the two into line rather than inventing a
      // new scoping rule.
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const subtreeMasterIds = await getAllSubMasterIds(req.master.id);

      // If specific master_id provided, verify it's in the subtree
      if (master_id) {
        if (!subtreeMasterIds.includes(master_id)) {
          return res.status(403).json({
            success: false,
            message: 'You can only view trades from masters in your own hierarchy',
            data: null
          });
        }

        filter.master_id = master_id;
      } else {
        filter.master_id = { $in: subtreeMasterIds };
      }
    }

    // Per-admin master-visibility restriction — hidden masters' trades
    // never appear here, whether reached via a bare list or a supplied master_id.
    const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
    const hiddenMasterIds = await resolveHiddenMasterIds(req);
    if (hiddenMasterIds) {
      if (master_id && hiddenMasterIds.has(master_id.toString())) {
        return res.status(404).json({ success: false, message: 'Master not found', data: null });
      }
      if (filter.master_id && filter.master_id.$in) {
        filter.master_id.$in = filter.master_id.$in.filter((id) => !hiddenMasterIds.has(id.toString()));
      } else if (!filter.master_id) {
        filter.master_id = { $nin: [...hiddenMasterIds] };
      }
    }

    if (user_id) filter.user_id = user_id;
    if (status) filter.status = status;
    if (exchange) filter.exchange = exchange;
    if (tradingsymbol) filter.tradingsymbol = { $regex: escapeRegex(tradingsymbol), $options: 'i' };
    if (date_from || date_to) {
      filter.createdAt = {};
      if (date_from) filter.createdAt.$gte = new Date(date_from);
      if (date_to) filter.createdAt.$lte = new Date(date_to);
    }

    const trades = await Trade.find(filter)
      .populate('user_id', 'name username')
      .populate('master_id', 'name username')
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ createdAt: -1 });

    const count = await Trade.countDocuments(filter);

    // Calculate summary
    const summary = await Trade.aggregate([
      { $match: filter },
      {
        $group: {
          _id: null,
          total_trades: { $sum: 1 },
          total_pnl: { $sum: '$pnl' },
          total_brokerage: { $sum: '$brokerage' }
        }
      }
    ]);

    const enrichedTrades = await enrichTradesWithLotSize(
      trades.map(trade => {
        const t = trade.toJSON();
        if (t.user_id && typeof t.user_id === 'object') {
          t.user_name = t.user_id.name || null;
          t.user_username = t.user_id.username || null;
          t.user_id = t.user_id.id || t.user_id._id || t.user_id;
        }
        if (t.master_id && typeof t.master_id === 'object') {
          t.master_name = t.master_id.name || null;
          t.master_id = t.master_id.id || t.master_id._id || t.master_id;
        }
        return t;
      })
    );

    res.status(200).json({
      success: true,
      message: 'Trades retrieved successfully',
      data: {
        trades: enrichedTrades,
        total: count,
        page: parseInt(page),
        pages: Math.ceil(count / limit),
        summary: summary[0] || { total_trades: 0, total_pnl: 0, total_brokerage: 0 }
      }
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

module.exports = {
  getAllTrades
};
