const mongoose = require('mongoose');

// Category trade wallet — the available (spendable) balance per category pool
// (NSE, INDEX, NSEOPT, MCX, COMEX, GLOBAL). `min: 0` is a schema-level guard; the atomic `$gte` guard
// in walletService is the real never-negative enforcement (see design §D1).
const walletSchema = new mongoose.Schema({
  NSE:    { type: Number, default: 0, min: 0 },
  // Index futures — NIFTY / BANKNIFTY / SENSEX NFO futures ("INDEX"); their
  // margin is blocked/released only here (utils/walletCategory.js).
  INDEX:  { type: Number, default: 0, min: 0 },
  // NSE options ("NSE OPT") — option margin is blocked/released only here.
  NSEOPT: { type: Number, default: 0, min: 0 },
  MCX:    { type: Number, default: 0, min: 0 },
  COMEX:  { type: Number, default: 0, min: 0 },
  GLOBAL: { type: Number, default: 0, min: 0 }
}, { _id: false });

const masterSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true
  },
  username: {
    type: String,
    required: true,
    unique: true,
    trim: true
  },
  password: {
    type: String,
    required: true
  },
  credits: {
    type: Number,
    required: true,
    default: 0
  },
  equity: {
    type: Number,
    required: true,
    default: 0
  },
  note: {
    type: String,
    required: false,
    default: ''
  },
  pnl_sharing: {
    type: Number,
    required: true,
    default: 0,
    min: 0,
    max: 100
  },
  brokerage_sharing: {
    type: Number,
    required: true,
    default: 0,
    min: 0,
    max: 100
  },
  // Base profit book time (minutes): no client or sub-master under this
  // master can be given less (utils/profitBookTime.js, 25 Oct 2026).
  profit_book_base_minutes: {
    type: Number,
    min: 0,
    max: 1440,
    default: 10
  },
  exchanges_allowed: {
    type: [String],
    required: true,
    enum: ['NSE', 'NFO', 'MCX', 'SGX', 'OTHERS', 'NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'BFO-FUT', 'BFO-OPT', 'INDICES', 'GLOBAL', 'COMEX-FUT'],
    default: []
  },
  // Which GroupedQuantity "group" (lot_name) this master is on, per exchange
  // — a NEW, separate field from exchanges_allowed above, not a reshape of
  // it: exchanges_allowed is a plain string array read as such all over
  // this codebase (e.g. `master.exchanges_allowed.map(e => e.toUpperCase())`
  // in masterController.js), so changing its shape to match User's
  // {exchange_name, group_name} objects would break every one of those call
  // sites. Before this field existed, a new master's ScriptQuantity rows
  // were seeded from whichever group happened to come back first per script
  // (scriptQuantityCopyService.js's copyFromGroupedQuantityToMaster,
  // "take the first/default group's values") — there was no real group
  // selection or memory of it, unlike a User's exchanges_allowed[].group_name.
  script_quantity_groups: {
    type: [{
      exchange_name: {
        type: String,
        required: true,
        enum: ['NSE', 'NFO', 'MCX', 'SGX', 'OTHERS', 'NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'BFO-FUT', 'BFO-OPT', 'INDICES', 'GLOBAL', 'COMEX-FUT']
      },
      group_name: {
        type: String,
        required: true,
        trim: true
      }
    }],
    default: []
  },
  // Admin-controlled allow-list: which Group(s) this master may draw from,
  // per exchange, both for their OWN script_quantity_groups pick above and
  // for any group_name they hand out to a client/sub-master they create.
  // Settable ONLY by an Admin (masterController.js's createMaster/
  // updateMaster deliberately ignore this field on a req.master caller) —
  // it's a permission grant, not something a master can widen for itself.
  // An exchange with no entry here (or an empty group_names[]) is
  // unrestricted — back-compat for every master that existed before this
  // field did, so nothing broke the day this shipped.
  allotted_script_quantity_groups: {
    type: [{
      exchange_name: {
        type: String,
        required: true,
        enum: ['NSE', 'NFO', 'MCX', 'SGX', 'OTHERS', 'NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'BFO-FUT', 'BFO-OPT', 'INDICES', 'GLOBAL', 'COMEX-FUT']
      },
      group_names: {
        type: [String],
        default: []
      }
    }],
    default: []
  },
  intraday_squareoff: {
    type: [{
      exchange_name: {
        type: String,
        required: true,
        enum: ['NSE', 'NFO', 'MCX', 'SGX', 'OTHERS', 'NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'BFO-FUT', 'BFO-OPT', 'INDICES', 'GLOBAL', 'COMEX-FUT']
      },
      enabled: {
        type: Boolean,
        required: true,
        default: false
      }
    }],
    default: []
  },
  // First-class M2M auto square-off toggle, mirroring User.margin_square_off.
  // Used by shouldSquareOff (design §8); kept in parity with permissions.margin_square.
  margin_square_off: {
    type: Boolean,
    default: false
  },
  margin_square_off_percentage: {
    type: Number,
    default: 0,
    min: 0,
    max: 100
  },
  // Per-category trade wallet (available balances). Funded via the assignment
  // flow; blocked on open / released on close by walletService.
  wallet: {
    type: walletSchema,
    default: () => ({ NSE: 0, INDEX: 0, NSEOPT: 0, MCX: 0, COMEX: 0, GLOBAL: 0 })
  },
  trade_limit: {
    type: [String],
    required: true,
    enum: ['NSE', 'NFO', 'MCX', 'SGX', 'OTHERS', 'NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'BFO-FUT', 'BFO-OPT', 'INDICES', 'GLOBAL', 'COMEX-FUT'],
    default: []
  },
  server_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Server',
    required: true
  },
  max_credit: {
    type: Number,
    default: 0
  },
  status: {
    type: String,
    enum: ['active', 'inactive', 'suspended'],
    default: 'active'
  },
  active_status: {
    type: Boolean,
    default: true
  },
  last_due_bill: {
    type: Date,
    default: null
  },
  last_login: {
    type: Date,
    default: null
  },
  ip_address: {
    type: String,
    default: null
  },
  exchanges: {
    type: [String],
    enum: ['NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS', 'NCO', 'BCO', 'BCD'],
    default: []
  },
  permissions: {
    account_summary: { type: Boolean, default: true },
    pnl_summary: { type: Boolean, default: true },
    client_summary: { type: Boolean, default: true },
    settlement_report: { type: Boolean, default: true },
    generate_pdf: { type: Boolean, default: true },
    weekly_admin: { type: Boolean, default: true },
    intraday_history: { type: Boolean, default: true },
    userwise_open_position: { type: Boolean, default: true },
    script_quantity: { type: Boolean, default: true },
    deleted_trade: { type: Boolean, default: true },
    trade_account: { type: Boolean, default: true },
    close_only: { type: Boolean, default: false },
    bet: { type: Boolean, default: true },
    margin_square: { type: Boolean, default: false },
    fresh_stoploss: { type: Boolean, default: false }
  },
  admin_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin',
    required: true
  },
  master_id: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Master',
    default: null
  },
  // Display-only running total for the Master Ledger's "Ledger" column —
  // this week's Total P&L across this master's entire downline (same
  // figure/sign the live report already shows, see LedgerEntry.js) added
  // on every Sunday 23:55 weekly snapshot. Does NOT feed any sharing/
  // cascade calculation.
  ledger_balance: {
    type: Number,
    default: 0,
  },
  add_master: {
    type: Boolean,
    default: false
  },
  change_pass_on_first_login: {
    type: Boolean,
    default: false
  },
  active_token: {
    type: String,
    default: null
  },
  investor_password: {
    type: String,
    default: null
  },
  deleted_at: {
    type: Date,
    default: null
  },
  notification_settings: {
    market_order: { type: Boolean, default: false },
    pending_order: { type: Boolean, default: true },
    admin_order_execution: { type: Boolean, default: false },
    admin_order_deletion: { type: Boolean, default: true },
    trading_sound: { type: Boolean, default: false }
  },
  fcm_tokens: {
    type: [String],
    default: []
  },
  account_limit: {
    enabled: { type: Boolean, default: false },
    max_masters: { type: Number, default: 0 },
    max_users: { type: Number, default: 0 }
  },
  // ── Live Trading Metrics (aggregated from all users under this master) ──
  realised_pnl: {
    type: Number,
    default: 0
  },
  position_pnl: {
    type: Number,
    default: 0
  },
  m2m_pnl: {
    type: Number,
    default: 0
  },
  margin_used: {
    type: Number,
    default: 0
  },
  equity: {
    type: Number,
    default: 0
  },
  free_margin: {
    type: Number,
    default: 0
  },
  // Google Authenticator / TOTP — same shape as Admin.js's own fields
  // (see totpService.js, generalized from what was originally
  // adminOtpService.js so both models share one implementation).
  totp_enabled: {
    type: Boolean,
    default: false
  },
  totp_secret: {
    type: String,
    default: null,
    // Never returned by a plain query — see Admin.js's identical field for
    // the full reasoning. toJSON below also strips it defensively.
    select: false
  }
}, {
  timestamps: true
});

// Transform _id to id and timestamps to snake_case
masterSchema.set('toJSON', {
  transform: (doc, ret) => {
    ret.id = ret._id;
    delete ret._id;
    delete ret.__v;
    delete ret.password;
    delete ret.investor_password;
    // The live session JWT — never belongs in a serialized response (see
    // the identical fix on User.js's toJSON for the full reasoning).
    delete ret.active_token;
    delete ret.totp_secret;
    ret.created_at = ret.createdAt;
    ret.updated_at = ret.updatedAt;
    delete ret.createdAt;
    delete ret.updatedAt;
    // Expose whether investor password is configured (without revealing the hash)
    ret.has_investor_password = !!doc.investor_password;
    return ret;
  }
});

// Indexes
masterSchema.index({ username: 1 }, { unique: true });
masterSchema.index({ server_id: 1 });
masterSchema.index({ admin_id: 1 });
masterSchema.index({ status: 1 });

// ─── NEW: Replaces { master_id: 1 } — covers hierarchy traversal with soft-delete filter ───
masterSchema.index({ master_id: 1, deleted_at: 1 });

// ─── NEW: Bulk load of all non-deleted masters (metricsEngine, weeklySummaryService) ───
masterSchema.index({ deleted_at: 1 });

module.exports = mongoose.model('Master', masterSchema);
