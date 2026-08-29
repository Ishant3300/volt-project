const bcrypt = require('bcryptjs');
const { escapeRegex } = require('../utils/escapeRegex');
const User = require('../models/User');
const Master = require('../models/Master');
const Server = require('../models/Server');
const GroupedQuantity = require('../models/GroupedQuantity');
const ScriptQuantity = require('../models/ScriptQuantity');
const BrokerageSettings = require('../models/BrokerageSettings');
const mongoose = require('mongoose');
const Transaction = require('../models/Transaction');
const { applyWalletFunding } = require('./walletController');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

// Create User
const createUser = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const {
      username,
      password,
      server_id,
      master_id,
      credit,
      current_credit,
      balance,
      exchanges_support,
      status,
      change_pass_on_first_login,
      investor_password
    } = req.body;

    if (!username || !password || !server_id || !master_id) {
      return res.status(400).json({
        success: false,
        message: 'Username, password, server_id, and master_id are required',
        data: null
      });
    }

    let resultData;

    await session.withTransaction(async () => {
      // Check if username already exists
      const existingUser = await User.findOne({ username }).session(session);
      if (existingUser) throw new Error('Username already exists');

      // Verify server exists
      const server = await Server.findById(server_id).session(session);
      if (!server) throw new Error('Server not found');

      // Verify master exists
      const master = await Master.findById(master_id).session(session);
      if (!master) throw new Error('Master not found');

      // This route is mounted with authenticateMaster only (never admin), so
      // req.master is always set here. Without this check, a master could
      // plant a user under ANY master_id in the request body — including an
      // unrelated master's hierarchy — and the new user's initial credit was
      // never debited from anyone, i.e. free unlimited balance created from
      // nothing. Require master_id to be the caller's own hierarchy, and
      // debit the caller for the initial credit, same as masterUserController
      // .createUser (the other, correctly-guarded path to this same action).
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allMasterIds = req.master ? await getAllSubMasterIds(req.master.id) : null;
      if (allMasterIds && !allMasterIds.includes(master_id)) {
        throw new Error('Not authorized to create a user under that master');
      }

      const initialCredit = credit || 0;

      if (req.master) {
        const parentMaster = await Master.findById(req.master.id).session(session);
        if (!parentMaster) throw new Error('Calling master not found');
        if (parentMaster.equity < initialCredit) {
          throw new Error(`Insufficient balance. Available: ${parentMaster.equity}, Required: ${initialCredit}`);
        }
      }

      // Hash password
      const hashedPassword = await bcrypt.hash(password, 10);

      // Hash investor password if provided
      let hashedInvestorPassword = null;
      if (investor_password && investor_password.trim()) {
        if (investor_password === password) throw new Error('Investor password must be different from the main password');
        hashedInvestorPassword = await bcrypt.hash(investor_password, 10);
      }

      const user = new User({
        username,
        password: hashedPassword,
        investor_password: hashedInvestorPassword,
        server_id,
        master_id,
        credits: initialCredit,
        current_credit: current_credit || 0,
        equity: balance !== undefined ? balance : initialCredit,
        exchanges_support: exchanges_support || [],
        status: status || 'active',
        change_pass_on_first_login: change_pass_on_first_login !== undefined ? change_pass_on_first_login : true
      });
      await user.save({ session });

      if (initialCredit > 0) {
        const tx = new Transaction({
          transactionId: `TXN_${Date.now()}_${Math.random().toString(36).substr(2, 6)}_U`,
          userId: user._id,
          userModel: 'User',
          type: 'CREDIT',
          status: 'SUCCESS',
          amount: initialCredit,
          referenceId: req.admin ? req.admin.id : req.master.id,
          referenceModel: req.admin ? 'Admin' : 'Master',
          balanceBefore: 0,
          balanceAfter: user.equity,
          metadata: { note: req.admin ? 'Admin created user with initial credit' : 'Master created user with initial credit' }
        });
        await tx.save({ session });

        // Debit the calling master's own equity for the credit just granted
        // to the new user — the debit half of the transfer that was
        // previously missing entirely.
        if (req.master) {
          const parentMaster = await Master.findById(req.master.id).session(session);
          const prevMasterBalance = parentMaster.equity;
          parentMaster.equity -= initialCredit;
          await parentMaster.save({ session });

          const masterTx = new Transaction({
            transactionId: `TXN_${Date.now()}_${Math.random().toString(36).substr(2, 6)}_M`,
            userId: parentMaster._id,
            userModel: 'Master',
            type: 'DEBIT',
            status: 'SUCCESS',
            amount: initialCredit,
            referenceId: user._id,
            referenceModel: 'User',
            balanceBefore: prevMasterBalance,
            balanceAfter: parentMaster.equity,
            metadata: { note: `Debited for new user ${username}'s initial credit` }
          });
          await masterTx.save({ session });
        }
      }

      resultData = user.toJSON();
    });

    session.endSession();

    res.status(201).json({
      success: true,
      message: 'User created successfully',
      data: resultData
    });
  } catch (error) {
    session.endSession();

    let statusCode = 500;
    if (error.message.includes('not found')) statusCode = 404;
    else if (error.message === 'Username already exists') statusCode = 400;

    res.status(statusCode).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Get All Users
const getAllUsers = async (req, res) => {
  try {
    const { page = 1, limit = 20, status, server_id, master_id, search } = req.query;

    const filter = {};
    if (status) filter.status = status;
    if (server_id) filter.server_id = server_id;

    // A master caller is always scoped to their own subtree — master_id from
    // the query is only honoured as an additional narrowing filter WITHIN
    // that subtree, never to reach outside it. Admin is unrestricted.
    if (req.admin) {
      if (master_id) {
        const { getAllSubMasterIds } = require('../services/masterHierarchyService');
        const allMasterIds = await getAllSubMasterIds(master_id);
        filter.master_id = { $in: allMasterIds };
      }
    } else if (req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const callerSubtreeIds = await getAllSubMasterIds(req.master.id);
      if (master_id) {
        const requestedIds = await getAllSubMasterIds(master_id);
        const allowedIds = requestedIds.filter(id => callerSubtreeIds.includes(id));
        filter.master_id = { $in: allowedIds };
      } else {
        filter.master_id = { $in: callerSubtreeIds };
      }
    }

    filter.deleted_at = null;

    // Search by username or name
    if (search) {
      const safeSearch = escapeRegex(search);
      filter.$or = [
        { username: { $regex: safeSearch, $options: 'i' } },
        { name: { $regex: safeSearch, $options: 'i' } },
      ];
    }

    const users = await User.find(filter)
      .populate('server_id', 'name')
      .populate('master_id', 'username')
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ createdAt: -1 });

    const count = await User.countDocuments(filter);

    res.status(200).json({
      success: true,
      message: 'Users retrieved successfully',
      data: {
        users: users.map(user => user.toJSON()),
        total: count,
        page: parseInt(page),
        pages: Math.ceil(count / limit)
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

// Get User by ID
const getUserById = async (req, res) => {
  try {
    const { id } = req.params;

    const user = await User.findById(id)
      .populate('server_id', 'name')
      .populate('master_id', 'username');

    // Allow fetching deleted users (admin needs to see their data)
    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
        data: null
      });
    }

    if (req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const userMasterId = user.master_id?._id?.toString() || user.master_id?.toString();
      if (!userMasterId || !allowedMasterIds.includes(userMasterId)) {
        return res.status(403).json({
          success: false,
          message: 'Not authorized to view this user',
          data: null
        });
      }
    }

    res.status(200).json({
      success: true,
      message: 'User retrieved successfully',
      data: user.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Update User
const updateUser = async (req, res) => {
  try {
    const { id } = req.params;
    const {
      name,
      username,
      password,
      investor_password,
      server_id,
      master_id,
      credit,
      credits,
      current_credit,
      balance,
      exchanges_support,
      note,
      pnl_sharing,
      brokerage_sharing,
      exchanges_allowed,
      trade_limit,
      margin_square_off,
      change_pass_on_first_login,
      status
    } = req.body;

    // Scope to the caller's own hierarchy when a master calls this endpoint
    // (mounted with authenticateAdminOrMaster) — without this, any master
    // could edit any user on the platform, including reassigning them into
    // their own hierarchy via master_id below. Admins are unrestricted.
    let user;
    if (req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allMasterIds = await getAllSubMasterIds(req.master.id);
      user = await User.findOne({ _id: id, master_id: { $in: allMasterIds } });
    } else {
      user = await User.findById(id);
    }

    if (!user) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
        data: null
      });
    }

    // Check if username is being changed and if it already exists
    if (username && username !== user.username) {
      const existingUser = await User.findOne({ username });
      if (existingUser) {
        return res.status(400).json({
          success: false,
          message: 'Username already exists',
          data: null
        });
      }
      user.username = username;
    }

    if (password) {
      user.password = await bcrypt.hash(password, 10);
    }

    // Handle investor password: set if provided, clear if empty string
    if (investor_password !== undefined) {
      if (investor_password && investor_password.trim()) {
        // Compare against the account's real current password (already
        // updated above if `password` was also part of this request) —
        // NOT just a `password` resent in this same request. Editing only
        // the investor password (the normal case — the main password field
        // is left blank) previously skipped this check entirely, since
        // `password` was falsy, letting the investor password silently
        // match the real one.
        if (await bcrypt.compare(investor_password, user.password)) {
          return res.status(400).json({ success: false, message: 'Investor password must be different from the main password', data: null });
        }
        user.investor_password = await bcrypt.hash(investor_password, 10);
      } else {
        user.investor_password = null; // Clear investor password
      }
    }

    if (server_id) {
      const server = await Server.findById(server_id);
      if (!server) {
        return res.status(404).json({
          success: false,
          message: 'Server not found',
          data: null
        });
      }
      user.server_id = server_id;
    }

    if (master_id) {
      const master = await Master.findById(master_id);
      if (!master) {
        return res.status(404).json({
          success: false,
          message: 'Master not found',
          data: null
        });
      }
      // A master can only reassign a user to another master within their
      // own hierarchy — otherwise they could move a user out to an
      // unrelated master (or an admin could still reassign anywhere).
      if (req.master) {
        const { getAllSubMasterIds } = require('../services/masterHierarchyService');
        const allMasterIds = await getAllSubMasterIds(req.master.id);
        if (!allMasterIds.includes(master_id)) {
          return res.status(403).json({
            success: false,
            message: 'Not authorized to reassign this user to that master',
            data: null
          });
        }
      }
      user.master_id = master_id;
    }

    if (name) user.name = name;
    // credits is intentionally NOT settable here — a direct overwrite with
    // no balance check, no parent debit, and no audit record (the same bug
    // already fixed on masterUserController.updateUserDetails/updateMaster/
    // updateChildMasterDetails). credits is what metricsEngine reads as the
    // live trading balance. Use the dedicated credit/debit endpoints instead.
    if (note !== undefined) user.note = note;
    if (margin_square_off !== undefined) user.margin_square_off = margin_square_off;
    if (change_pass_on_first_login !== undefined) user.change_pass_on_first_login = change_pass_on_first_login;
    if (status) user.status = status;

    if (pnl_sharing !== undefined) {
      if (pnl_sharing < 0 || pnl_sharing > 100) return res.status(400).json({ success: false, message: 'P&L sharing must be between 0 and 100', data: null });
      user.pnl_sharing = pnl_sharing;
    }

    if (brokerage_sharing !== undefined) {
      if (brokerage_sharing < 0 || brokerage_sharing > 100) return res.status(400).json({ success: false, message: 'Brokerage sharing must be between 0 and 100', data: null });
      user.brokerage_sharing = brokerage_sharing;
    }

    if (exchanges_allowed) {
      if (!Array.isArray(exchanges_allowed)) return res.status(400).json({ success: false, message: 'exchanges_allowed must be an array', data: null });
      for (const exchange of exchanges_allowed) {
        if (!exchange.exchange_name || exchange.turnover === undefined || exchange.lot === undefined) return res.status(400).json({ success: false, message: 'Each exchange must have exchange_name, turnover, and lot', data: null });
      }
      user.exchanges_allowed = exchanges_allowed.map(ex => {
        let name = ex.exchange_name.toUpperCase();
        if (name === 'GLOBAL') name = 'INDICES';
        return { ...ex, exchange_name: name };
      });
    }

    if (trade_limit) {
      user.trade_limit = trade_limit.map(ex => {
        let name = ex.toUpperCase();
        if (name === 'GLOBAL') name = 'INDICES';
        return name;
      });
    }

    await user.save();

    if (req.body.wallet) {
      await applyWalletFunding({ req, targetType: 'User', targetId: user._id, walletMap: req.body.wallet });
      try {
        const metricsEngine = require('../services/metricsEngine');
        await metricsEngine.onTradeExecuted(user._id.toString());
      } catch (err) {}
    }

    res.status(200).json({
      success: true,
      message: 'User updated successfully',
      data: user.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Delete User (Soft Delete)
const deleteUser = async (req, res) => {
  try {
    const { id } = req.params;

    const user = await User.findById(id);

    if (!user || user.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'User not found',
        data: null
      });
    }

    // This route is authenticateMaster-only (req.admin never reaches here),
    // so a caller-scoped subtree check applies unconditionally — previously
    // missing entirely, letting any master soft-delete any other master's
    // client with a single request.
    const { getAllSubMasterIds } = require('../services/masterHierarchyService');
    const allowedMasterIds = await getAllSubMasterIds(req.master.id);
    if (!user.master_id || !allowedMasterIds.includes(user.master_id.toString())) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this user',
        data: null
      });
    }

    user.deleted_at = new Date();
    await user.save();

    res.status(200).json({
      success: true,
      message: 'User deleted successfully',
      data: null
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// ============================================
// Credit / Debit User (Admin only)
// ============================================

const creditUserByAdmin = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { id } = req.params;
    const { amount, note } = req.body;
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, message: 'amount must be a positive number', data: null });
    }

    let result;
    await session.withTransaction(async () => {
      const user = await User.findById(id).session(session);
      if (!user) throw new Error('User not found');

      const creditsBefore = user.credits;
      user.credits += amount;
      await user.save({ session });

      const tx = new Transaction({
        transactionId: `TXN_${Date.now()}_${Math.random().toString(36).substr(2, 6)}_AC`,
        userId: user._id,
        userModel: 'User',
        type: 'CREDIT',
        status: 'SUCCESS',
        amount,
        referenceId: req.admin ? req.admin.id : null,
        referenceModel: 'Admin',
        balanceBefore: creditsBefore,
        balanceAfter: user.credits,
        metadata: { note: note || 'Admin credit', credited_by: req.admin?.username }
      });
      await tx.save({ session });
      result = { new_balance: user.credits, amount_credited: amount, current_credits: user.credits };
    });
    session.endSession();
    
    try {
      const metricsEngine = require('../services/metricsEngine');
      metricsEngine.onTradeExecuted(id);
    } catch (e) {
      console.error('Error triggering metrics engine cache rebuild:', e);
    }

    res.status(200).json({ success: true, message: 'Amount credited successfully', data: result });
  } catch (error) {
    session.endSession();
    res.status(error.message === 'User not found' ? 404 : 500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

const debitUserByAdmin = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const { id } = req.params;
    const { amount, note } = req.body;
    if (!amount || amount <= 0) {
      return res.status(400).json({ success: false, message: 'amount must be a positive number', data: null });
    }

    let result;
    await session.withTransaction(async () => {
      const user = await User.findById(id).session(session);
      if (!user) throw new Error('User not found');

      const creditsBefore = user.credits;
      user.credits -= amount;
      await user.save({ session });

      const tx = new Transaction({
        transactionId: `TXN_${Date.now()}_${Math.random().toString(36).substr(2, 6)}_AD`,
        userId: user._id,
        userModel: 'User',
        type: 'DEBIT',
        status: 'SUCCESS',
        amount,
        referenceId: req.admin ? req.admin.id : null,
        referenceModel: 'Admin',
        balanceBefore: creditsBefore,
        balanceAfter: user.credits,
        metadata: { note: note || 'Admin debit', debited_by: req.admin?.username }
      });
      await tx.save({ session });
      result = { new_balance: user.credits, amount_debited: amount, current_credits: user.credits };
    });
    session.endSession();
    
    try {
      const metricsEngine = require('../services/metricsEngine');
      metricsEngine.onTradeExecuted(id);
    } catch (e) {
      console.error('Error triggering metrics engine cache rebuild:', e);
    }

    res.status(200).json({ success: true, message: 'Amount debited successfully', data: result });
  } catch (error) {
    session.endSession();
    res.status(error.message === 'User not found' ? 404 : 500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};



// ============================================
// Grouped Quantity CRUD Operations
// ============================================

// Create Grouped Quantity
const createGroupedQuantity = async (req, res) => {
  try {
    const { exchange_name, lot_name, instrument_id, instrument_symbol, raw_name, max_qty, break_qty, lot_size } = req.body;

    console.log('📥 Creating grouped quantity:', {
      exchange_name,
      lot_name,
      raw_name,
      instrument_id,
      instrument_symbol,
      max_qty,
      break_qty,
      lot_size
    });

    if (!exchange_name || !lot_name || max_qty === undefined || break_qty === undefined || lot_size === undefined) {
      console.log('❌ Validation failed - missing required fields');
      return res.status(400).json({
        success: false,
        message: 'exchange_name, lot_name, max_qty, break_qty, and lot_size are required',
        data: null
      });
    }

    // Use raw_name as the primary key for matching; fall back to instrument_symbol
    const matchRawName = raw_name || instrument_symbol || '';

    const groupedQty = await GroupedQuantity.findOneAndUpdate(
      { exchange_name, lot_name, raw_name: matchRawName, deleted_at: null },
      {
        exchange_name,
        lot_name,
        raw_name: matchRawName,
        instrument_id: instrument_id || '',
        instrument_symbol: instrument_symbol || matchRawName,
        max_qty,
        break_qty,
        lot_size,
        deleted_at: null
      },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    console.log('✅ Grouped quantity upserted:', groupedQty._id);

    res.status(201).json({
      success: true,
      message: 'Grouped quantity saved successfully',
      data: groupedQty.toJSON()
    });
  } catch (error) {
    console.error('❌ Error creating grouped quantity:', error);
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Get All Grouped Quantities
const getAllGroupedQuantities = async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;

    const filter = { deleted_at: null };

    const groupedQuantities = await GroupedQuantity.find(filter)
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ created_at: -1 });

    const count = await GroupedQuantity.countDocuments(filter);

    res.status(200).json({
      success: true,
      message: 'Grouped quantities retrieved successfully',
      data: {
        grouped_quantities: groupedQuantities.map(gq => gq.toJSON()),
        total: count,
        page: parseInt(page),
        pages: Math.ceil(count / limit)
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

// Get Grouped Quantity by ID
const getGroupedQuantityById = async (req, res) => {
  try {
    const { id } = req.params;

    const groupedQty = await GroupedQuantity.findById(id);

    if (!groupedQty || groupedQty.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Grouped quantity not found',
        data: null
      });
    }

    res.status(200).json({
      success: true,
      message: 'Grouped quantity retrieved successfully',
      data: groupedQty.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Update Grouped Quantity
const updateGroupedQuantity = async (req, res) => {
  try {
    const { id } = req.params;
    const { exchange_name, lot_name, instrument_id, instrument_symbol, max_qty, break_qty, lot_size } = req.body;

    const groupedQty = await GroupedQuantity.findById(id);

    if (!groupedQty || groupedQty.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Grouped quantity not found',
        data: null
      });
    }

    if (exchange_name) groupedQty.exchange_name = exchange_name;
    if (lot_name) groupedQty.lot_name = lot_name;
    if (instrument_id) groupedQty.instrument_id = instrument_id;
    if (instrument_symbol) groupedQty.instrument_symbol = instrument_symbol;
    if (max_qty !== undefined) groupedQty.max_qty = max_qty;
    if (break_qty !== undefined) groupedQty.break_qty = break_qty;
    if (lot_size !== undefined) groupedQty.lot_size = lot_size;

    await groupedQty.save();

    res.status(200).json({
      success: true,
      message: 'Grouped quantity updated successfully',
      data: groupedQty.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Delete Grouped Quantity (Soft Delete)
const deleteGroupedQuantity = async (req, res) => {
  try {
    const { id } = req.params;

    const groupedQty = await GroupedQuantity.findById(id);

    if (!groupedQty || groupedQty.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Grouped quantity not found',
        data: null
      });
    }

    groupedQty.deleted_at = new Date();
    await groupedQty.save();

    res.status(200).json({
      success: true,
      message: 'Grouped quantity deleted successfully',
      data: null
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// ============================================
// Script Quantity CRUD Operations
// ============================================

// Create Script Quantity
const createScriptQuantity = async (req, res) => {
  try {
    const { exchange_name, script_name, lot_size, max_qty, brk_qty, owner_id, owner_type } = req.body;

    if (!exchange_name || !script_name || lot_size === undefined || max_qty === undefined || brk_qty === undefined) {
      return res.status(400).json({ success: false, message: 'exchange_name, script_name, lot_size, max_qty, and brk_qty are required', data: null });
    }

    const callerId = req.admin?.id || req.master?.id;
    const callerType = req.admin ? 'Admin' : 'Master';
    const effectiveOwnerId = owner_id || callerId;
    const effectiveOwnerType = owner_id ? (owner_type || 'User') : callerType;

    if (!effectiveOwnerId) {
      return res.status(400).json({ success: false, message: 'Could not determine owner for script quantity', data: null });
    }

    if (req.master) {
      let targetUser = null;
      if (effectiveOwnerId !== req.master.id) {
        if (effectiveOwnerType !== 'User') {
          return res.status(403).json({ success: false, message: 'Not authorized to create for this owner type' });
        }
        targetUser = await User.findById(effectiveOwnerId);
        if (!targetUser || targetUser.master_id.toString() !== req.master.id) {
          return res.status(403).json({ success: false, message: 'Not authorized to create for this user' });
        }
      }

      let ceilingLimit;
      if (effectiveOwnerId === req.master.id) {
        const adminGlobal = await ScriptQuantity.findOne({ owner_type: 'Admin', exchange_name, script_name, deleted_at: null }).lean();
        if (!adminGlobal) {
          return res.status(400).json({ success: false, message: 'Admin has not set a global limit for this script' });
        }
        ceilingLimit = adminGlobal.max_qty;
      } else {
        // Ceiling is the TARGET USER's own assigned Group for this exchange
        // — not the master's own ScriptQuantity value (that was the bug:
        // it checked whatever number happened to be on the master's own
        // account, unrelated to which Group the user was actually
        // assigned). A master can lower a user's limit within their
        // group's max; raising above it requires switching the user to a
        // different group first (see reseedUserScriptQuantityForExchange).
        const normalizedExchange = exchange_name.toUpperCase();
        const userExchange = targetUser.exchanges_allowed.find(ex => ex.exchange_name === normalizedExchange);
        if (!userExchange || !userExchange.group_name) {
          return res.status(400).json({ success: false, message: 'This user has no group assigned for this exchange' });
        }
        const groupLimit = await GroupedQuantity.findOne({ exchange_name: normalizedExchange, lot_name: userExchange.group_name, raw_name: script_name, deleted_at: null }).lean();
        if (!groupLimit) {
          return res.status(400).json({ success: false, message: `No limit found in group "${userExchange.group_name}" for this script` });
        }
        ceilingLimit = groupLimit.max_qty;
      }

      if (max_qty > ceilingLimit) {
        return res.status(400).json({ success: false, message: `max_qty cannot exceed limit of ${ceilingLimit}` });
      }
    }

    const scriptQty = await ScriptQuantity.findOneAndUpdate(
      { owner_id: effectiveOwnerId, owner_type: effectiveOwnerType, exchange_name, script_name, deleted_at: null },
      { owner_id: effectiveOwnerId, owner_type: effectiveOwnerType, exchange_name, script_name, lot_size, max_qty, brk_qty, deleted_at: null },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );

    if (effectiveOwnerType === 'Master') {
      const { cascadeNewScriptToUsers } = require('../services/scriptQuantityCopyService');
      await cascadeNewScriptToUsers(effectiveOwnerId, exchange_name, script_name, { lot_size, max_qty, brk_qty });
    }

    if (effectiveOwnerType === 'Admin') {
      const { cascadeNewScriptGlobally } = require('../services/scriptQuantityCopyService');
      await cascadeNewScriptGlobally(exchange_name, script_name, { lot_size, max_qty, brk_qty }, effectiveOwnerId);
    }

    res.status(201).json({ success: true, message: 'Script quantity saved successfully', data: scriptQty.toJSON() });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// Get All Script Quantities
const getAllScriptQuantities = async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;

    const filter = { deleted_at: null };

    const scriptQuantities = await ScriptQuantity.find(filter)
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ created_at: -1 });

    const count = await ScriptQuantity.countDocuments(filter);

    res.status(200).json({
      success: true,
      message: 'Script quantities retrieved successfully',
      data: {
        script_quantities: scriptQuantities.map(sq => sq.toJSON()),
        total: count,
        page: parseInt(page),
        pages: Math.ceil(count / limit)
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

// Get Script Quantity by ID
const getScriptQuantityById = async (req, res) => {
  try {
    const { id } = req.params;

    const scriptQty = await ScriptQuantity.findById(id);

    if (!scriptQty || scriptQty.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Script quantity not found',
        data: null
      });
    }

    res.status(200).json({
      success: true,
      message: 'Script quantity retrieved successfully',
      data: scriptQty.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Update Script Quantity
const updateScriptQuantity = async (req, res) => {
  try {
    const { id } = req.params;
    const { exchange_name, script_name, lot_size, max_qty, brk_qty } = req.body;

    const scriptQty = await ScriptQuantity.findById(id);

    if (!scriptQty || scriptQty.deleted_at) {
      return res.status(404).json({ success: false, message: 'Script quantity not found', data: null });
    }

    if (req.master) {
      let targetUser = null;
      if (scriptQty.owner_id.toString() !== req.master.id) {
        if (scriptQty.owner_type !== 'User') {
          return res.status(403).json({ success: false, message: 'Not authorized to edit other masters' });
        }
        targetUser = await User.findById(scriptQty.owner_id);
        if (!targetUser || targetUser.master_id.toString() !== req.master.id) {
          return res.status(403).json({ success: false, message: 'Not authorized to edit this user' });
        }
      }

      if (max_qty !== undefined) {
        let ceilingLimit;
        const ex = exchange_name || scriptQty.exchange_name;
        const sc = script_name || scriptQty.script_name;
        if (scriptQty.owner_id.toString() === req.master.id) {
          const adminGlobal = await ScriptQuantity.findOne({ owner_type: 'Admin', exchange_name: ex, script_name: sc, deleted_at: null }).lean();
          if (!adminGlobal) {
            return res.status(400).json({ success: false, message: 'Admin has not set a global limit for this script' });
          }
          ceilingLimit = adminGlobal.max_qty;
        } else {
          // Ceiling is the TARGET USER's own assigned Group for this
          // exchange — not the master's own ScriptQuantity value. See the
          // matching comment in createScriptQuantity for why.
          const normalizedExchange = ex.toUpperCase();
          const userExchange = targetUser.exchanges_allowed.find(e => e.exchange_name === normalizedExchange);
          if (!userExchange || !userExchange.group_name) {
            return res.status(400).json({ success: false, message: 'This user has no group assigned for this exchange' });
          }
          const groupLimit = await GroupedQuantity.findOne({ exchange_name: normalizedExchange, lot_name: userExchange.group_name, raw_name: sc, deleted_at: null }).lean();
          if (!groupLimit) {
            return res.status(400).json({ success: false, message: `No limit found in group "${userExchange.group_name}" for this script` });
          }
          ceilingLimit = groupLimit.max_qty;
        }

        if (max_qty > ceilingLimit) {
          return res.status(400).json({ success: false, message: `max_qty cannot exceed limit of ${ceilingLimit}` });
        }
      }
    }

    if (exchange_name) scriptQty.exchange_name = exchange_name;
    if (script_name) scriptQty.script_name = script_name;
    if (lot_size !== undefined) scriptQty.lot_size = lot_size;
    if (max_qty !== undefined) scriptQty.max_qty = max_qty;
    if (brk_qty !== undefined) scriptQty.brk_qty = brk_qty;

    await scriptQty.save();

    if (req.admin && scriptQty.owner_type === 'Admin') {
      const { cascadeNewScriptGlobally } = require('../services/scriptQuantityCopyService');
      await cascadeNewScriptGlobally(scriptQty.exchange_name, scriptQty.script_name, { lot_size: scriptQty.lot_size, max_qty: scriptQty.max_qty, brk_qty: scriptQty.brk_qty }, req.admin.id);
    } else if (scriptQty.owner_type === 'Master') {
      const { cascadeToDirectUsers } = require('../services/scriptQuantityCopyService');
      await cascadeToDirectUsers(scriptQty.owner_id.toString(), scriptQty.exchange_name, scriptQty.script_name, { max_qty: scriptQty.max_qty, brk_qty: scriptQty.brk_qty, lot_size: scriptQty.lot_size });
    }

    res.status(200).json({ success: true, message: 'Script quantity updated successfully', data: scriptQty.toJSON() });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// Delete Script Quantity (Soft Delete)
const deleteScriptQuantity = async (req, res) => {
  try {
    const { id } = req.params;

    const scriptQty = await ScriptQuantity.findById(id);

    if (!scriptQty || scriptQty.deleted_at) {
      return res.status(404).json({ success: false, message: 'Script quantity not found', data: null });
    }

    if (req.master) {
      if (scriptQty.owner_id.toString() !== req.master.id) {
        if (scriptQty.owner_type !== 'User') {
          return res.status(403).json({ success: false, message: 'Not authorized to delete other masters' });
        }
        const user = await User.findById(scriptQty.owner_id);
        if (!user || user.master_id.toString() !== req.master.id) {
          return res.status(403).json({ success: false, message: 'Not authorized to delete this user script' });
        }
      }
    }

    scriptQty.deleted_at = new Date();
    await scriptQty.save();

    if (scriptQty.owner_type === 'Master') {
      const { cascadeDeleteScriptToUsers } = require('../services/scriptQuantityCopyService');
      await cascadeDeleteScriptToUsers(scriptQty.owner_id.toString(), scriptQty.exchange_name, scriptQty.script_name);
    }

    if (scriptQty.owner_type === 'Admin') {
      const { cascadeDeleteScriptGlobally } = require('../services/scriptQuantityCopyService');
      await cascadeDeleteScriptGlobally(scriptQty.exchange_name, scriptQty.script_name, scriptQty.owner_id.toString());
    } else if (req.admin && scriptQty.owner_type === 'Master') {
      const { cascadeDeleteScriptGlobally } = require('../services/scriptQuantityCopyService');
      await cascadeDeleteScriptGlobally(scriptQty.exchange_name, scriptQty.script_name, req.admin.id);
    }

    res.status(200).json({ success: true, message: 'Script quantity deleted successfully', data: null });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

// ==================== BROKERAGE SETTINGS ====================

// Create Brokerage Settings
/**
 * BrokerageSettings.user_id is misleadingly named — it can hold either a
 * User._id or a Master._id (global/default rules use null). Resolves it to
 * the master_id whose subtree the record actually belongs to, so callers
 * can check it against getAllSubMasterIds(caller). Returns null if the id
 * doesn't resolve to either (record already invalid/orphaned).
 */
async function resolveBrokerageOwnerMasterId(ownerId) {
  if (!ownerId) return null;
  const User = require('../models/User');
  const owner = await User.findById(ownerId).select('master_id').lean();
  if (owner) return owner.master_id?.toString() || null;
  return ownerId.toString(); // not a User — assume Master, id is its own subtree root
}

const createBrokerageSettings = async (req, res) => {
  try {
    const { type, exchange_name, script_name, brk_value, user_id } = req.body;

    if (!type || !exchange_name || !script_name || brk_value === undefined) {
      return res.status(400).json({
        success: false,
        message: 'type, exchange_name, script_name, and brk_value are required',
        data: null
      });
    }

    // Floor validation: a master creating their own rate cannot go below
    // their parent's rate — same rule already enforced on updateBrokerageSettings
    // (and the bulk-update route), just missing here. This was the actual gap:
    // a master's own rate set can be created below the floor in one call via
    // this endpoint even though editing it afterward would be blocked. Admin
    // bypasses this, same as the update path (admin can set any rate on
    // their children).
    if (user_id && req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const ownerMasterId = await resolveBrokerageOwnerMasterId(user_id);
      if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
        return res.status(403).json({ success: false, message: 'Not authorized to set brokerage for this account', data: null });
      }

      const { validateBrokerageFloor } = require('../services/brokerageCopyService');
      const User = require('../models/User');
      const ownerUser = await User.findById(user_id).select('_id').lean();
      const ownerType = ownerUser ? 'User' : 'Master';
      const floorError = await validateBrokerageFloor(user_id, ownerType, exchange_name, script_name, type, brk_value);
      if (floorError) {
        return res.status(422).json({ success: false, message: floorError, data: null });
      }
    }

    const newBrokerageSettings = await BrokerageSettings.findOneAndUpdate(
      { type, exchange_name, script_name, user_id: user_id || null, deleted_at: null },
      // effective_from stamps the moment this rate takes effect (insert or update).
      { type, exchange_name, script_name, user_id: user_id || null, brk_value, deleted_at: null, effective_from: new Date() },
      // runValidators — without it, Mongoose skips schema validation (including
      // the `type` enum) on findOneAndUpdate/upsert. A frontend that offers a
      // value outside the enum (e.g. a stale/removed brokerage type) would
      // otherwise be saved silently instead of rejected with a clear error.
      { upsert: true, new: true, setDefaultsOnInsert: true, runValidators: true }
    );

    res.status(201).json({
      success: true,
      message: 'Brokerage settings saved successfully',
      data: newBrokerageSettings.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Get All Brokerage Settings
const getAllBrokerageSettings = async (req, res) => {
  try {
    const { page = 1, limit = 20, user_id } = req.query;

    // A master requesting another account's specific rules must own that
    // account; requesting no user_id (global/default rules, user_id: null)
    // is unrestricted since those aren't account-specific data.
    if (user_id && req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const ownerMasterId = await resolveBrokerageOwnerMasterId(user_id);
      if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
        return res.status(403).json({ success: false, message: 'Not authorized to view brokerage settings for this account', data: null });
      }
    }

    const filter = { user_id: user_id || null, deleted_at: null };

    const brokerageSettings = await BrokerageSettings.find(filter)
      .limit(limit * 1)
      .skip((page - 1) * limit)
      .sort({ created_at: -1 });

    const count = await BrokerageSettings.countDocuments(filter);

    res.status(200).json({
      success: true,
      message: 'Brokerage settings retrieved successfully',
      data: {
        brokerage_settings: brokerageSettings.map(bs => bs.toJSON()),
        total: count,
        page: parseInt(page),
        pages: Math.ceil(count / limit)
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

// Get Brokerage Settings by ID
const getBrokerageSettingsById = async (req, res) => {
  try {
    const { id } = req.params;

    const brokerageSettings = await BrokerageSettings.findById(id);

    if (!brokerageSettings || brokerageSettings.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Brokerage settings not found',
        data: null
      });
    }

    if (brokerageSettings.user_id && req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const ownerMasterId = await resolveBrokerageOwnerMasterId(brokerageSettings.user_id);
      if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
        return res.status(403).json({ success: false, message: 'Not authorized to view this brokerage setting', data: null });
      }
    }

    res.status(200).json({
      success: true,
      message: 'Brokerage settings retrieved successfully',
      data: brokerageSettings.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Update Brokerage Settings
const updateBrokerageSettings = async (req, res) => {
  try {
    const { id } = req.params;
    const { type, exchange_name, script_name, brk_value } = req.body;

    const brokerageSettings = await BrokerageSettings.findById(id);

    if (!brokerageSettings || brokerageSettings.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Brokerage settings not found',
        data: null
      });
    }

    if (brokerageSettings.user_id && req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const ownerMasterId = await resolveBrokerageOwnerMasterId(brokerageSettings.user_id);
      if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
        return res.status(403).json({ success: false, message: 'Not authorized to update this brokerage setting', data: null });
      }
    }

    // Floor validation: if this record belongs to a user/master, ensure new rate >= parent's rate
    // Admin bypasses this — admin can set any rate on their children
    if (brk_value !== undefined && brokerageSettings.user_id && !req.admin) {
      const { validateBrokerageFloor } = require('../services/brokerageCopyService');
      // Determine owner type
      const User = require('../models/User');
      const Master = require('../models/Master');
      const ownerUser = await User.findById(brokerageSettings.user_id).select('_id').lean();
      const ownerType = ownerUser ? 'User' : 'Master';
      const effectiveExchange = exchange_name || brokerageSettings.exchange_name;
      const effectiveScript = script_name || brokerageSettings.script_name;
      const effectiveType = type || brokerageSettings.type;

      // Direct check: new rate must be >= caller's own rate
      const callerId = req.master.id;
      const callerRule = await BrokerageSettings.findOne({
        user_id: callerId,
        exchange_name: effectiveExchange.toUpperCase(),
        script_name: effectiveScript,
        type: effectiveType,
        deleted_at: null,
      }).lean();

      if (callerRule && brk_value < callerRule.brk_value) {
        return res.status(422).json({
          success: false,
          message: `Brokerage cannot be less than the parent limit (${callerRule.brk_value})`,
          data: null
        });
      }

      // Also run hierarchy-based validation as fallback
      const floorError = await validateBrokerageFloor(
        brokerageSettings.user_id.toString(), ownerType,
        effectiveExchange, effectiveScript, effectiveType, brk_value
      );
      if (floorError) {
        return res.status(422).json({ success: false, message: floorError, data: null });
      }
    }

    if (type) brokerageSettings.type = type;
    if (exchange_name) brokerageSettings.exchange_name = exchange_name;
    if (script_name) brokerageSettings.script_name = script_name;
    if (brk_value !== undefined) {
      brokerageSettings.brk_value = brk_value;
      // Stamp the moment this rate takes effect so historical bills use the old rate.
      brokerageSettings.effective_from = new Date();
    }

    await brokerageSettings.save();

    // Reload metricsEngine rules so brokerage calculations use the new values immediately
    try { const me = require('../services/metricsEngine'); me.reloadRules(); } catch (_) {}

    res.status(200).json({
      success: true,
      message: 'Brokerage settings updated successfully',
      data: brokerageSettings.toJSON()
    });
  } catch (error) {
    res.status(500).json({
      success: false,
      message: sanitizeErrorMessage(error),
      data: null
    });
  }
};

// Delete Brokerage Settings (Soft Delete)
const deleteBrokerageSettings = async (req, res) => {
  try {
    const { id } = req.params;

    const brokerageSettings = await BrokerageSettings.findById(id);

    if (!brokerageSettings || brokerageSettings.deleted_at) {
      return res.status(404).json({
        success: false,
        message: 'Brokerage settings not found',
        data: null
      });
    }

    if (brokerageSettings.user_id && req.master) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(req.master.id);
      const ownerMasterId = await resolveBrokerageOwnerMasterId(brokerageSettings.user_id);
      if (!ownerMasterId || !allowedMasterIds.includes(ownerMasterId)) {
        return res.status(403).json({ success: false, message: 'Not authorized to delete this brokerage setting', data: null });
      }
    }

    brokerageSettings.deleted_at = new Date();
    await brokerageSettings.save();

    // Reload metricsEngine rules
    try { const me = require('../services/metricsEngine'); me.reloadRules(); } catch (_) {}

    res.status(200).json({
      success: true,
      message: 'Brokerage settings deleted successfully',
      data: null
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
  createUser,
  getAllUsers,
  getUserById,
  updateUser,
  deleteUser,
  creditUserByAdmin,
  debitUserByAdmin,
  resolveBrokerageOwnerMasterId,
  // Grouped Quantity
  createGroupedQuantity,
  getAllGroupedQuantities,
  getGroupedQuantityById,
  updateGroupedQuantity,
  deleteGroupedQuantity,
  // Script Quantity
  createScriptQuantity,
  getAllScriptQuantities,
  getScriptQuantityById,
  updateScriptQuantity,
  deleteScriptQuantity,
  // Brokerage Settings
  createBrokerageSettings,
  getAllBrokerageSettings,
  getBrokerageSettingsById,
  updateBrokerageSettings,
  deleteBrokerageSettings
};
