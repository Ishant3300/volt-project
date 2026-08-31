const mongoose = require('mongoose');
const { ADMIN_PERMISSION_KEYS } = require('../constants/adminPermissions');

const adminSchema = new mongoose.Schema({
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
  active_token: {
    type: String,
    default: null
  },
  deleted_at: {
    type: Date,
    default: null
  },
  // Did not exist before — User/Master both already have this toggle
  // (checked in middlewares/auth.js), Admin never did. Needed so a Super
  // Admin can lock out a compromised/offboarded Admin account immediately
  // without deleting it.
  active_status: {
    type: Boolean,
    default: true
  },
  // Root of the admin hierarchy — the only role that can create other
  // Admin accounts and edit their permission sets (superAdminController.js).
  // A Super Admin is never subject to any permissions[]/watch_only check
  // (requireAdminPermission.js, rejectIfAdminWatchOnly.js bypass it
  // unconditionally) — same authority as a regular Admin plus that one
  // extra management capability, not a separate power tier.
  is_super_admin: {
    type: Boolean,
    default: false
  },
  // A restriction, not a grant — kept out of `permissions` deliberately
  // (see constants/adminPermissions.js) since it's the opposite kind of
  // flag: "never allowed to mutate," which would be easy to miss if it
  // lived inside an additive permissions.includes(key) check instead of
  // its own dedicated middleware.
  watch_only: {
    type: Boolean,
    default: false
  },
  // Only meaningful for a non-super Admin — a Super Admin bypasses every
  // permission check regardless of what's (or isn't) in this array.
  permissions: {
    type: [String],
    enum: ADMIN_PERMISSION_KEYS,
    default: []
  },
  // Audit trail — which Super Admin created this Admin account.
  created_by: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Admin',
    default: null
  },
  // Masters this Admin cannot see — every master's own record, its full
  // sub-master tree, their users, and any trade/report/ledger data
  // belonging to any of them, everywhere. Empty by default ("select all"
  // — sees everything, same as today). Never meaningful for a Super
  // Admin, who is always unrestricted regardless of this list.
  hidden_master_ids: {
    type: [{ type: mongoose.Schema.Types.ObjectId, ref: 'Master' }],
    default: []
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
  totp_enabled: {
    type: Boolean,
    default: false
  },
  totp_secret: {
    type: String,
    default: null,
    // Never returned by a plain query (find/findById/.lean()) — the toJSON
    // transform already strips it, but that only runs on a hydrated
    // document's .toJSON()/.toObject(), not on .lean() reads. Callers that
    // legitimately need it (adminOtpService.js) already explicitly opt in
    // via .select('+totp_secret').
    select: false
  }
}, {
  timestamps: true
});

// Transform _id to id and timestamps to snake_case
adminSchema.set('toJSON', {
  transform: (doc, ret) => {
    ret.id = ret._id;
    delete ret._id;
    delete ret.__v;
    delete ret.totp_secret;
    ret.created_at = ret.createdAt;
    ret.updated_at = ret.updatedAt;
    delete ret.createdAt;
    delete ret.updatedAt;
    return ret;
  }
});

// Indexes
adminSchema.index({ username: 1 }, { unique: true });

module.exports = mongoose.model('Admin', adminSchema);
