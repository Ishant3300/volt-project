const mongoose = require('mongoose');

// COMEX USD→INR conversion rate (utils/comexFx.js). One document (key
// 'comex'): admin's base rate and spread, plus an append-only change log.
// Only the weekly settlement uses it — COMEX trades, brokerage, margin and
// wallets stay in dollars until then.

const changeSchema = new mongoose.Schema({
  base: Number,
  spread: Number,
  by: { type: String, default: null },
  at: { type: Date, default: Date.now },
}, { _id: false });

const comexRateSchema = new mongoose.Schema({
  key: { type: String, default: 'comex', unique: true },
  base: { type: Number, required: true, min: 0 },
  spread: { type: Number, required: true, min: 0 },
  updated_by: { type: String, default: null },
  updated_at: { type: Date, default: Date.now },
  history: { type: [changeSchema], default: [] },
});

module.exports = mongoose.model('ComexRate', comexRateSchema);
