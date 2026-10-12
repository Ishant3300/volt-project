const mongoose = require('mongoose');

/**
 * An introducing broker who is owed a share of some clients' brokerage.
 * Tracking only — a broker has no login, no wallet and no place in the
 * master hierarchy; nothing here feeds the ledger, the weekly report or
 * settlement. See BrokerClientLink for which clients and at what rate.
 */
const brokerSchema = new mongoose.Schema({
  name: { type: String, required: true, trim: true },
  phone: { type: String, trim: true, default: '' },
  note: { type: String, trim: true, default: '' },
  status: { type: String, enum: ['active', 'inactive'], default: 'active' },
  created_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
  deleted_at: { type: Date, default: null },
}, { timestamps: true });

brokerSchema.index({ deleted_at: 1, name: 1 });

module.exports = mongoose.model('Broker', brokerSchema);
