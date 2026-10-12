const mongoose = require('mongoose');

/**
 * Problems the web portal / mobile app see that never reach the server as an
 * order or a log line: an order the screen refused before sending it, a page
 * or app crash, a failed request. Reported via POST /api/auth/client-events
 * and read by the watchdog (scripts/watchdog) to alert on them. Kept 60 days.
 */
const clientEventSchema = new mongoose.Schema({
  source: { type: String, enum: ['web', 'app'], required: true },
  kind: { type: String, enum: ['order_block', 'order_rejected', 'js_error', 'api_error', 'crash'], required: true },
  // Who was signed in (from the token, never from the body); null on the login page.
  account_id: { type: mongoose.Schema.Types.ObjectId, default: null },
  account_role: { type: String, default: null },
  // The client the order was for (admin/master placing on a client's behalf).
  target_user_id: { type: mongoose.Schema.Types.ObjectId, default: null },
  code: { type: String, default: '' },
  message: { type: String, default: '' },
  page: { type: String, default: '' },
  context: { type: mongoose.Schema.Types.Mixed, default: {} },
  version: { type: String, default: '' },
  user_agent: { type: String, default: '' },
  ip: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
}, { versionKey: false });

clientEventSchema.index({ createdAt: 1 }, { expireAfterSeconds: 60 * 24 * 3600 });
clientEventSchema.index({ account_id: 1, createdAt: -1 });

module.exports = mongoose.model('ClientEvent', clientEventSchema);
