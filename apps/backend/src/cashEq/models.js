'use strict';

// Equity (NSE cash) — own collections only (eqcash_*). Nothing here is read or written by
// the F&O system, and no F&O model (User, Master, Trade, LedgerEntry …) gets a new field.
// Equity masters and clients are NOT User/Master rows: the weekly F&O reset, weekly
// reports and client lists query every User/Master, so equity accounts live apart.

const mongoose = require('mongoose');

const { Schema } = mongoose;

/** Brokerage of an equity master (its floor for everyone below) or client (charged). */
const brokerageSchema = new Schema({
  mode: { type: String, enum: ['PCT', 'FIX'], default: 'PCT' },
  intraday: { type: Number, default: 0, min: 0 }, // % of value (PCT) or ₹ per share (FIX)
  carry: { type: Number, default: 0, min: 0 }, // carry forward / delivery
  min_rate: { type: Number, default: 0, min: 0 }, // ₹ per share floor (PCT)
  higher_side_only: { type: Boolean, default: false }, // intraday charged on one side only
}, { _id: false });

const accountFields = {
  name: { type: String, required: true, trim: true },
  username: { type: String, required: true, unique: true, trim: true },
  password: { type: String, required: true },
  // Caps: a master's are the most it can give anyone below; a client's are its own limits.
  per_script_limit: { type: Number, required: true, min: 0 },
  total_limit: { type: Number, required: true, min: 0 },
  // Two sets of rates: approved (MTF) scripts and non-approved scripts (the MTF list
  // comes from a broker's published list — instruments.js syncMtfList).
  brokerage_mtf: { type: brokerageSchema, default: () => ({}) },
  brokerage_non: { type: brokerageSchema, default: () => ({}) },
  interest_mtf_pct: { type: Number, required: true, min: 0, max: 100 }, // % per year
  interest_non_pct: { type: Number, required: true, min: 0, max: 100 },
  status: { type: String, enum: ['active', 'inactive'], default: 'active' },
  active_token: { type: String, default: null },
  change_pass_on_first_login: { type: Boolean, default: false },
  last_login: { type: Date, default: null },
  ip_address: { type: String, default: null },
  created_by: { role: String, id: Schema.Types.ObjectId },
  deleted_at: { type: Date, default: null },
};

const eqMasterSchema = new Schema({
  ...accountFields,
  // Top-level equity masters sit directly under admin (parent_id null).
  parent_id: { type: Schema.Types.ObjectId, ref: 'EqMaster', default: null, index: true },
  // Sharing with the level above, like F&O: P&L (ceiling model), brokerage and interest (rate gap).
  pnl_share: { type: Number, required: true, min: 0, max: 100 },
  brokerage_share: { type: Number, required: true, min: 0, max: 100 },
  interest_share: { type: Number, required: true, min: 0, max: 100 },
}, { timestamps: true });

const eqClientSchema = new Schema({
  ...accountFields,
  master_id: { type: Schema.Types.ObjectId, ref: 'EqMaster', required: true, index: true },
  // Client money at the start: Cr = client's own money (no interest up to it), Dr = owes.
  opening_balance: { type: Number, default: 0, min: 0 },
  opening_type: { type: String, enum: ['Cr', 'Dr'], default: 'Cr' },
  // Set on the first fill; opening balance can't be changed after it.
  first_trade_at: { type: Date, default: null },
}, { timestamps: true });

for (const s of [eqMasterSchema, eqClientSchema]) {
  s.set('toJSON', {
    transform: (_doc, ret) => {
      ret.id = String(ret._id); // the web portal keys saved sessions on `id`, like F&O accounts
      delete ret.password;
      delete ret.active_token;
      delete ret.__v;
      return ret;
    },
  });
}

/** Deposits, withdrawals and journals: change client money from their date. */
const eqLedgerSchema = new Schema({
  client_id: { type: Schema.Types.ObjectId, ref: 'EqClient', required: true, index: true },
  date: { type: String, required: true, match: /^\d{4}-\d{2}-\d{2}$/ }, // IST calendar date
  kind: { type: String, enum: ['DEPOSIT', 'WITHDRAWAL', 'JOURNAL_CR', 'JOURNAL_DR'], required: true },
  amount: { type: Number, required: true, min: 0.01 },
  narration: { type: String, default: '', trim: true, maxlength: 200 },
  created_by: { role: String, id: Schema.Types.ObjectId, username: String },
  deleted_at: { type: Date, default: null },
  deleted_by: { role: String, id: Schema.Types.ObjectId, username: String },
}, { timestamps: true });

/** Who changed what in equity (kept apart from the F&O AdminAction log). */
const eqAuditSchema = new Schema({
  actor: { role: String, id: Schema.Types.ObjectId, username: String },
  action: { type: String, required: true },
  target: { kind: String, id: Schema.Types.ObjectId, username: String },
  details: { type: Schema.Types.Mixed, default: {} },
}, { timestamps: { createdAt: true, updatedAt: false } });

/** NSE EQ-series stocks (own list — the F&O instruments collection is not touched). */
const eqInstrumentSchema = new Schema({
  instrument_token: { type: Number, required: true, unique: true },
  exchange_token: { type: Number },
  tradingsymbol: { type: String, required: true, index: true },
  name: { type: String, default: '' },
  tick_size: { type: Number, default: 0.05 },
  is_active: { type: Boolean, default: true, index: true },
  synced_at: { type: Date },
  // Approved (MTF) script: on the broker's published MTF list at the last list sync.
  mtf: { type: Boolean, default: false, index: true },
  mtf_margin_pct: { type: Number, default: null }, // broker's margin % (kept for reference)
  mtf_category: { type: String, default: null }, // fo / non_fo / etf / non_categorized
  isin: { type: String, default: null },
  mtf_synced_at: { type: Date, default: null },
}, { timestamps: true });

/** Last known equity quote per stock (so prices show outside market hours too). */
const eqQuoteSchema = new Schema({
  instrument_token: { type: Number, required: true, unique: true },
  last_price: Number,
  bid_price: Number,
  ask_price: Number,
  open: Number,
  high: Number,
  low: Number,
  close: Number,
  change: Number,
  change_percent: Number,
  volume: Number,
  at: Date,
}, { versionKey: false });

/** Equity watchlist: one row per (owner, stock). Separate from the F&O watchlist. */
const eqWatchlistSchema = new Schema({
  owner_role: { type: String, enum: ['admin', 'cash_master', 'cash_client'], required: true },
  owner_id: { type: Schema.Types.ObjectId, required: true, index: true },
  instrument_token: { type: Number, required: true, index: true },
  tradingsymbol: { type: String, required: true },
}, { timestamps: true });
eqWatchlistSchema.index({ owner_id: 1, instrument_token: 1 }, { unique: true });

/**
 * Equity orders. A refused order is kept too (status REJECTED + reason) — that is the
 * equity rejection log. OPEN = waiting / partly filled; the rest fills as the market
 * trades (low-volume rules, liquidity.js) until FILLED, CANCELLED or EXPIRED (15:30).
 */
const eqOrderSchema = new Schema({
  client_id: { type: Schema.Types.ObjectId, ref: 'EqClient', required: true, index: true },
  master_id: { type: Schema.Types.ObjectId, ref: 'EqMaster' },
  placed_by: { role: String, id: Schema.Types.ObjectId, username: String },
  instrument_token: { type: Number, required: true, index: true },
  tradingsymbol: { type: String, required: true },
  mtf: { type: Boolean, default: false }, // category when placed: approved (MTF) or not
  side: { type: String, enum: ['B', 'S'], required: true },
  order_type: { type: String, enum: ['MARKET', 'LIMIT'], required: true },
  qty: { type: Number, required: true, min: 1 },
  limit_price: { type: Number, default: null },
  filled_qty: { type: Number, default: 0 },
  filled_value: { type: Number, default: 0 }, // Σ qty × price of the fills (exact; avg_price is for display)
  avg_price: { type: Number, default: null },
  status: { type: String, enum: ['OPEN', 'FILLED', 'CANCELLED', 'EXPIRED', 'REJECTED'], required: true, index: true },
  reason: { type: String, default: '' }, // why refused / cancelled / note on partial fill
  date: { type: String, required: true, index: true }, // IST trading day
  ref_price: { type: Number, default: null }, // LTP when placed
  reserve_price: { type: Number, default: null }, // value per share counted against limits while open
  closed_at: { type: Date, default: null },
  closed_by: { role: String, id: Schema.Types.ObjectId, username: String },
}, { timestamps: true });
eqOrderSchema.index({ status: 1, instrument_token: 1, createdAt: 1 });

/** Equity fills. `seq` is the numeric trade id the engine sorts on. */
const eqTradeSchema = new Schema({
  seq: { type: Number, required: true, unique: true },
  client_id: { type: Schema.Types.ObjectId, ref: 'EqClient', required: true, index: true },
  order_id: { type: Schema.Types.ObjectId, ref: 'EqOrder', required: true, index: true },
  instrument_token: { type: Number, required: true },
  tradingsymbol: { type: String, required: true },
  mtf: { type: Boolean, default: false },
  side: { type: String, enum: ['B', 'S'], required: true },
  qty: { type: Number, required: true, min: 1 },
  price: { type: Number, required: true },
  date: { type: String, required: true, index: true }, // IST
  add_time: { type: String, required: true }, // 'YYYY-MM-DD HH:MM:SS' IST
  deleted_at: { type: Date, default: null },
}, { timestamps: true });
eqTradeSchema.index({ client_id: 1, date: 1 });

const eqCounterSchema = new Schema({ _id: String, seq: { type: Number, default: 0 } }, { versionKey: false });

/** Admin settings (one document per key, e.g. 'liquidity'). */
const eqSettingsSchema = new Schema({
  _id: String,
  values: { type: Schema.Types.Mixed, default: {} },
  updated_by: { role: String, id: Schema.Types.ObjectId, username: String },
}, { timestamps: true, versionKey: false });

/**
 * Monthly settlement (month-end). Only the prices are needed to bill — every ledger figure
 * is derived from trades + entries + confirmed month-ends (engine.js). The per-client
 * figures and each master's rate-gap clearances are saved at confirm, so the sharing
 * statement stays as confirmed even if rates change later.
 */
const eqMonthRunSchema = new Schema({
  month: { type: String, required: true, index: true }, // 'YYYY-MM'
  settle_date: { type: String, required: true }, // 1st of the next month
  price_date: { type: String, required: true }, // bhav date (last trading day)
  prices: { type: Schema.Types.Mixed, default: {} }, // SYMBOL -> close
  sources: { type: Schema.Types.Mixed, default: {} }, // SYMBOL -> 'bhav' | 'manual'
  status: { type: String, enum: ['PREVIEW', 'CONFIRMED', 'DELETED'], required: true, index: true },
  clients: { type: [Schema.Types.Mixed], default: [] }, // per-client snapshot (confirm)
  masters: { type: [Schema.Types.Mixed], default: [] }, // equity master tree + shares at confirm
  created_by: { role: String, id: Schema.Types.ObjectId, username: String },
  confirmed_by: { role: String, id: Schema.Types.ObjectId, username: String },
  confirmed_at: { type: Date, default: null },
  deleted_by: { role: String, id: Schema.Types.ObjectId, username: String },
  deleted_at: { type: Date, default: null },
}, { timestamps: true });

const model = (name, schema, collection) => mongoose.models[name] || mongoose.model(name, schema, collection);

module.exports = {
  EqMaster: model('EqMaster', eqMasterSchema, 'eqcash_masters'),
  EqClient: model('EqClient', eqClientSchema, 'eqcash_clients'),
  EqLedgerEntry: model('EqLedgerEntry', eqLedgerSchema, 'eqcash_ledger'),
  EqAudit: model('EqAudit', eqAuditSchema, 'eqcash_audit'),
  EqInstrument: model('EqInstrument', eqInstrumentSchema, 'eqcash_instruments'),
  EqQuote: model('EqQuote', eqQuoteSchema, 'eqcash_quotes'),
  EqWatchlist: model('EqWatchlist', eqWatchlistSchema, 'eqcash_watchlist'),
  EqOrder: model('EqOrder', eqOrderSchema, 'eqcash_orders'),
  EqTrade: model('EqTrade', eqTradeSchema, 'eqcash_trades'),
  EqCounter: model('EqCounter', eqCounterSchema, 'eqcash_counters'),
  EqSettings: model('EqSettings', eqSettingsSchema, 'eqcash_settings'),
  EqMonthRun: model('EqMonthRun', eqMonthRunSchema, 'eqcash_month_runs'),
};
