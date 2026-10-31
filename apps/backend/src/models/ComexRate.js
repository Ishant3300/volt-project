const mongoose = require('mongoose');

// COMEX USD→INR conversion rate (utils/comexFx.js). Key 'comex': admin's
// default base rate and spread. Keys 'master:<masterId>' / 'user:<userId>'
// (1 Nov 2026): that account's own rate while `active`, set where COMEX is
// ticked; accounts without one inherit from the masters above, then the
// default. Each keeps an append-only change log. Only the weekly settlement
// uses it — COMEX trades, brokerage, margin and wallets stay in dollars.

const changeSchema = new mongoose.Schema({
  base: Number,
  spread: Number,
  by: { type: String, default: null },
  at: { type: Date, default: Date.now },
  // A client's own rate removed (back to the default rate).
  cleared: { type: Boolean, default: undefined },
}, { _id: false });

const comexRateSchema = new mongoose.Schema({
  key: { type: String, default: 'comex', unique: true },
  // Set on a client's own rate (key 'user:<userId>'); null on the default.
  user_id: { type: mongoose.Schema.Types.ObjectId, ref: 'User', default: null, index: true },
  // Set on a master's own rate (key 'master:<masterId>').
  master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', default: null, index: true },
  // false = a client's own rate was removed; the default applies again.
  active: { type: Boolean, default: true },
  base: { type: Number, required: true, min: 0 },
  spread: { type: Number, required: true, min: 0 },
  updated_by: { type: String, default: null },
  updated_at: { type: Date, default: Date.now },
  history: { type: [changeSchema], default: [] },
});

module.exports = mongoose.model('ComexRate', comexRateSchema);
