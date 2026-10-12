const mongoose = require('mongoose');

/**
 * Failed sign-ins (wrong password, unknown user, inactive account, wrong
 * TOTP, ...) — successful ones stay in LoginHistory. Never stores the typed
 * password. Read by the watchdog for login alerts. Kept 90 days.
 */
const loginAttemptSchema = new mongoose.Schema({
  route: { type: String, default: '' }, // universal | user | master | admin
  username: { type: String, default: '' },
  status: { type: Number, default: 0 },
  reason: { type: String, default: '' },
  ip: { type: String, default: '' },
  user_agent: { type: String, default: '' },
  createdAt: { type: Date, default: Date.now },
}, { versionKey: false });

loginAttemptSchema.index({ createdAt: 1 }, { expireAfterSeconds: 90 * 24 * 3600 });
loginAttemptSchema.index({ username: 1, createdAt: -1 });
loginAttemptSchema.index({ ip: 1, createdAt: -1 });

module.exports = mongoose.model('LoginAttempt', loginAttemptSchema);
