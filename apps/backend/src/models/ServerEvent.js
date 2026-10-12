const mongoose = require('mongoose');

/**
 * Server-side failures a client hit that are NOT business refusals — e.g. an
 * order that failed on an internal error (those never reach the Rejection
 * Log, see utils/rejectionLog.js). Read by the watchdog. Kept 60 days.
 */
const serverEventSchema = new mongoose.Schema({
  kind: { type: String, required: true }, // order_error
  user_id: { type: mongoose.Schema.Types.ObjectId, default: null },
  caller_role: { type: String, default: '' },
  status: { type: Number, default: 0 },
  message: { type: String, default: '' },
  context: { type: mongoose.Schema.Types.Mixed, default: {} },
  createdAt: { type: Date, default: Date.now },
}, { versionKey: false });

serverEventSchema.index({ createdAt: 1 }, { expireAfterSeconds: 60 * 24 * 3600 });

module.exports = mongoose.model('ServerEvent', serverEventSchema);
