const mongoose = require('mongoose');

/**
 * Every successful change an admin or master makes through the API (POST /
 * PUT / PATCH / DELETE), recorded by middlewares/auditActions.js: who did it,
 * which endpoint, which accounts it touched and a redacted copy of the
 * request. Read by the health watchdog to report changes on Telegram with
 * the name of the person who made them. Kept 180 days.
 */
const adminActionSchema = new mongoose.Schema({
  actor_type: { type: String, enum: ['admin', 'master'], required: true },
  actor_id: { type: String, required: true },
  actor_username: { type: String, default: null },
  method: { type: String, required: true },
  path: { type: String, required: true },
  status_code: { type: Number },
  target_ids: { type: [String], default: [] },
  body: { type: mongoose.Schema.Types.Mixed, default: null },
  result: { type: mongoose.Schema.Types.Mixed, default: null }, // { id, status } from the response
  ip: { type: String, default: null },
  created_at: { type: Date, default: Date.now },
}, { versionKey: false });

adminActionSchema.index({ created_at: 1 }, { expireAfterSeconds: 180 * 24 * 3600 });
adminActionSchema.index({ target_ids: 1, created_at: -1 });

module.exports = mongoose.model('AdminAction', adminActionSchema);
