const mongoose = require('mongoose');

/**
 * Tracks one admin-triggered batch square-off run (e.g. "close every open
 * MCX position system-wide" ahead of an expiry). Lightweight sibling of
 * SettlementRun — just enough to show live progress in the admin UI and
 * stop two runs for the same segment overlapping.
 */
const squareOffRunSchema = new mongoose.Schema({
  segment: { type: String, required: true }, // e.g. 'MCX' — scope of this run
  status: {
    type: String,
    enum: ['running', 'completed', 'failed'],
    default: 'running',
  },
  triggered_by_admin_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
  total_users: { type: Number, default: 0 },
  processed_users: { type: Number, default: 0 },
  positions_closed: { type: Number, default: 0 },
  failed_users: [{
    user_id: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    username: String,
    error: String,
  }],
  started_at: { type: Date, default: Date.now },
  completed_at: { type: Date, default: null },
  error: { type: String, default: null },
}, { timestamps: true });

squareOffRunSchema.index({ segment: 1, status: 1 });

module.exports = mongoose.model('SquareOffRun', squareOffRunSchema);
