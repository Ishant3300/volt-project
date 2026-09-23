const mongoose = require('mongoose');

const tradeSchema = new mongoose.Schema({
  user_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  master_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Master',
    required: true
  },
  admin_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin',
    default: null
  },
  settlement_run_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'SettlementRun',
    default: null
  },
  settlement_period_key: {
    type: String,
    default: null
  },
  instrument_token: {
    type: String,
    required: true
  },
  tradingsymbol: {
    type: String,
    required: true
  },
  exchange: {
    type: String,
    required: true,
    enum: ['NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS', 'NSEIX', 'GLOBAL', 'SGX', 'NCO', 'BCO', 'BCD', 'COMEX']
  },
  transaction_type: {
    type: String,
    required: true,
    enum: ['BUY', 'SELL']
  },
  quantity: {
    type: Number,
    required: true
  },
  price: {
    type: Number,
    required: true
  },
  order_type: {
    type: String,
    required: true,
    enum: ['MARKET', 'LIMIT', 'SL', 'SL-M']
  },
  // For SL/SL-M only: which way the live price must move to fire this
  // order, decided ONCE at placement by comparing the trigger price to the
  // live price at that moment (trigger above live -> 'RISE', trigger below
  // live -> 'FALL') — independent of transaction_type. Replaces the old
  // hardcoded "SL BUY always fires on rise, SL SELL always fires on fall"
  // rule, which instant-fired any order whose trigger happened to already
  // be on the "wrong" side of the live price at placement. null for
  // MARKET/LIMIT, and for any SL/SL-M trade placed before this field
  // existed — orderBookService.js falls back to the old transaction_type
  // mapping whenever this is null, so pre-existing pending orders keep
  // matching exactly as they did before.
  trigger_direction: {
    type: String,
    enum: ['RISE', 'FALL', null],
    default: null
  },
  placed_by: {
    type: String,
    enum: ['USER', 'ADMIN', 'MASTER', 'SYSTEM'],
    default: 'USER'
  },
  // Trade type: 'regular' for normal trades, 'carry_forward' for ATP adjustment,
  // 'margin_square_off' for auto margin square-off trades
  // carry_forward and margin_square_off trades are hidden from orders/history page
  trade_type: {
    type: String,
    enum: ['regular', 'carry_forward', 'margin_square_off'],
    default: 'regular'
  },
  status: {
    type: String,
    required: true,
    enum: ['pending', 'completed', 'cancelled', 'rejected'],
    default: 'pending'
  },
  order_id: {
    type: String,
    default: null
  },
  executed_at: {
    type: Date,
    default: null
  },
  executed_price: {
    type: Number,
    default: null
  },
  executed_quantity: {
    type: Number,
    default: null
  },
  pnl: {
    type: Number,
    default: 0
  },
  brokerage: {
    type: Number,
    default: 0
  },
  // Admin-only "Custom" order-ticket toggle: when true, calculateBrokerage()
  // was deliberately skipped for this trade (brokerage forced to 0) rather
  // than genuinely rating to ₹0 — kept as its own flag, separate from
  // trade_type's 'carry_forward' (which hides a trade from orders/history
  // entirely), since this trade is still a normal, fully-visible trade.
  brokerage_exempt: {
    type: Boolean,
    default: false
  },
  taxes: {
    type: Number,
    default: 0
  },
  net_amount: {
    type: Number,
    default: 0
  },
  remarks: {
    type: String,
    default: ''
  },
  // Links a rollover's close leg and reopen leg together for reporting/audit.
  // Null for every other trade.
  rollover_group_id: {
    type: mongoose.Schema.Types.ObjectId,
    default: null
  },
  deleted_at: {
    type: Date,
    default: null
  }
}, {
  timestamps: true
});

// Transform _id to id and timestamps to snake_case
tradeSchema.set('toJSON', {
  transform: (doc, ret) => {
    ret.id = ret._id;
    delete ret._id;
    delete ret.__v;
    ret.created_at = ret.createdAt;
    ret.updated_at = ret.updatedAt;
    delete ret.createdAt;
    delete ret.updatedAt;
    return ret;
  }
});

// Indexes

// ─── Fixed: was `created_at` which doesn't exist (Mongoose timestamps = `createdAt`) ───
tradeSchema.index({ user_id: 1, createdAt: -1 });
tradeSchema.index({ master_id: 1, createdAt: -1 });
tradeSchema.index({ admin_id: 1, createdAt: -1 });

// ─── Single-field indexes ───
tradeSchema.index({ status: 1 });
tradeSchema.index({ instrument_token: 1 });
tradeSchema.index({ executed_at: -1 });

// ─── Existing compound ───
tradeSchema.index({ settlement_period_key: 1, status: 1, deleted_at: 1 });

// ─── NEW: Covers the #1 most-queried pattern (position aggregation per user per instrument) ───
tradeSchema.index({ user_id: 1, instrument_token: 1, status: 1, deleted_at: 1 });

// ─── NEW: metricsEngine per-user trade rebuild (sorted by createdAt ascending) ───
tradeSchema.index({ user_id: 1, status: 1, deleted_at: 1, createdAt: 1 });

// ─── NEW: Pending limit order scans (orderBookService, orderExecutionService) ───
tradeSchema.index({ status: 1, order_type: 1, deleted_at: 1 });

// ─── NEW: Positions & account summary queries (sorted by executed_at) ───
tradeSchema.index({ user_id: 1, status: 1, deleted_at: 1, executed_at: -1 });

// ─── NEW: Master trade listing with pagination ───
tradeSchema.index({ master_id: 1, status: 1, deleted_at: 1, createdAt: -1 });

// ─── NEW: Cancel pending orders by segment (cronService) ───
tradeSchema.index({ status: 1, instrument_token: 1, deleted_at: 1 });

// ─── NEW: Trade.distinct('user_id', { status, deleted_at }) in metricsEngine ───
tradeSchema.index({ status: 1, deleted_at: 1 });

// ─── NEW: Deleted trades listing ───
tradeSchema.index({ deleted_at: 1, updatedAt: -1 });

// ─── NEW: Rollover close/reopen leg pairing ───
tradeSchema.index({ rollover_group_id: 1 });

module.exports = mongoose.model('Trade', tradeSchema);
