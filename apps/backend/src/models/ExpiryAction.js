const mongoose = require('mongoose');

/**
 * One scheduled contract-expiry step (config/expiryRules.js): OPEN the next
 * contract of a product group, or CUT (close every open position in, then
 * disable) the current one. Planned by expiryActionService.refreshPlan(),
 * executed by its runDue() — opens automatically, cuts only once an admin
 * has confirmed them.
 *
 * status: planned → (CUT: confirmed) → running → done | failed
 *         planned/confirmed ⇄ paused (admin); obsolete = no longer in the plan
 */
const expiryActionSchema = new mongoose.Schema({
  key: { type: String, required: true, unique: true }, // `${group}|${kind}|${expiry}`
  group_key: { type: String, required: true },
  group_label: { type: String, required: true },
  exchange_label: { type: String, required: true },
  kind: { type: String, enum: ['OPEN', 'CUT'], required: true },
  segments: [String],
  continuous: { type: Boolean, default: false },
  names: [String],
  current_expiry: { type: Date, required: true },
  targets: [{ _id: false, name: String, expiry: Date }], // OPEN: each name's next contract
  // OPEN: targets ('NAME|YYYY-MM-DD') already closed-until-open-day once — never again,
  // so an admin opening one early by hand is not fought.
  closed_targets: [String],
  action_date: { type: String, required: true }, // 'YYYY-MM-DD' (India)
  close_time: { type: String, default: null }, // 'HH:MM' IST market close (CUT)
  execute_at: { type: Date, required: true },
  status: {
    type: String,
    enum: ['planned', 'confirmed', 'paused', 'running', 'done', 'failed', 'obsolete'],
    default: 'planned',
  },
  confirmed_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
  confirmed_at: { type: Date, default: null },
  // CUT: closing bid/ask captured just after the close, used however late the confirmation comes.
  snapshot: {
    captured_at: { type: Date, default: null },
    prices: [{ _id: false, token: String, symbol: String, bid: Number, ask: Number, ltp: Number }],
  },
  started_at: { type: Date, default: null },
  executed_at: { type: Date, default: null },
  result: {
    contracts: { type: Number, default: 0 }, // enabled (OPEN) / disabled (CUT)
    open_positions: { type: Number, default: 0 },
    positions_closed: { type: Number, default: 0 },
    failures: [{ _id: false, user_id: String, symbol: String, error: String }],
  },
  error: { type: String, default: null },
}, { timestamps: true });

expiryActionSchema.index({ status: 1, execute_at: 1 });
expiryActionSchema.index({ action_date: 1 });

expiryActionSchema.set('toJSON', {
  transform: (doc, ret) => {
    ret.id = ret._id;
    delete ret._id;
    delete ret.__v;
    return ret;
  },
});

module.exports = mongoose.model('ExpiryAction', expiryActionSchema);
