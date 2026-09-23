const mongoose = require('mongoose');

/**
 * Immutable, append-only weekly ledger — one document per client/master per
 * week, written by weeklySummaryService.js's snapshotWeeklyLedger() every
 * Sunday 23:55 (same cron slot as the existing snapshotWeeklySummary(),
 * right before the Monday 00:00 weekly balance reset).
 *
 * `total_pnl_this_week` uses the exact same formula already live in the
 * Master Ledger's "Total P&L" column (weeklyAdminController.js's
 * `-(grossPnl + floatingPnl)`, plain sum over a user's own trades — or, for
 * a master, over their entire downline — no sharing/ceiling math involved).
 * Recomputed independently here from Trade + metricsEngine rather than by
 * calling into weeklyAdminController.js, so this feature can never touch
 * that file's cascade/sharing formulas.
 *
 * `running_balance_after` is the owner's ledger_balance (User.js / Master.js)
 * immediately after this entry was applied — lets a past entry be read back
 * without recomputing the running sum. Documents are never updated/deleted.
 */
const ledgerEntrySchema = new mongoose.Schema({
  owner_id: { type: mongoose.Schema.Types.ObjectId, required: true },
  owner_type: { type: String, enum: ['User', 'Master'], required: true },
  week_start: { type: Date, required: true },
  week_end: { type: Date, required: true },
  total_pnl_this_week: { type: Number, default: 0 },
  running_balance_after: { type: Number, default: 0 },
}, { timestamps: { createdAt: 'created_at', updatedAt: false } });

ledgerEntrySchema.index({ owner_id: 1, week_start: 1 }, { unique: true });
ledgerEntrySchema.index({ owner_type: 1, week_start: 1 });

module.exports = mongoose.model('LedgerEntry', ledgerEntrySchema);
