const mongoose = require('mongoose');

/**
 * One account transfer done from the admin panel (owner, 9 Nov 2026): one or
 * more clients moved to a new master (services/accountTransferService.js).
 * Kept for good — unlike AdminAction (180 days) — because it is what Undo
 * reads and what a past week's figures can be traced back to.
 *
 * Per client it records the master before, every trade row whose master was
 * changed (with that row's master before), and every brokerage rate raised
 * (with the value before), so Undo can put back exactly what was changed.
 */
const movedRowSchema = new mongoose.Schema({
  trade_id: { type: mongoose.Schema.Types.ObjectId, required: true },
  from_master_id: { type: mongoose.Schema.Types.ObjectId, default: null },
  status: { type: String, default: null }, // status when moved (completed / pending / cancelled / rejected)
}, { _id: false });

const rateChangeSchema = new mongoose.Schema({
  brokerage_id: { type: mongoose.Schema.Types.ObjectId, required: true },
  exchange_name: { type: String, required: true },
  script_name: { type: String, required: true },
  type: { type: String, required: true },
  from_value: { type: Number, required: true },
  to_value: { type: Number, required: true },
}, { _id: false });

const transferItemSchema = new mongoose.Schema({
  user_id: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  username: { type: String, default: null },
  name: { type: String, default: null },
  from_master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', required: true },
  from_master_username: { type: String, default: null },
  moved_rows: { type: [movedRowSchema], default: [] },
  // Rows placed while the transfer was committing (a race with an order) and
  // moved right after it — recorded separately so nothing is hidden.
  late_rows: { type: [movedRowSchema], default: [] },
  rate_changes: { type: [rateChangeSchema], default: [] },
  warnings: { type: [String], default: [] }, // warning codes the admin accepted for this client
}, { _id: false });

const accountTransferSchema = new mongoose.Schema({
  to_master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', required: true },
  to_master_username: { type: String, default: null },
  items: { type: [transferItemSchema], default: [] },
  raise_low_rates: { type: Boolean, default: false },
  actor_id: { type: String, required: true },
  actor_username: { type: String, default: null },
  status: { type: String, enum: ['done', 'undone'], default: 'done' },
  undone_at: { type: Date, default: null },
  undone_by_id: { type: String, default: null },
  undone_by_username: { type: String, default: null },
  undo_details: { type: mongoose.Schema.Types.Mixed, default: null },
}, { timestamps: { createdAt: 'created_at', updatedAt: 'updated_at' }, versionKey: false });

accountTransferSchema.index({ created_at: -1 });
accountTransferSchema.index({ 'items.user_id': 1, created_at: -1 });

module.exports = mongoose.model('AccountTransfer', accountTransferSchema, 'account_transfers');
