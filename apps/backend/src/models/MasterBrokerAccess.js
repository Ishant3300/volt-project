const mongoose = require('mongoose');

/**
 * "Brokers allowed" per master (owner, 11 Nov 2026): set by an admin. Without
 * it a master sees no broker option anywhere and the server refuses every
 * master broker route. Kept in its own collection — the Master document and
 * everything that reads it stay exactly as they were.
 */
const masterBrokerAccessSchema = new mongoose.Schema({
  master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', required: true },
  allowed: { type: Boolean, default: false },
  updated_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
}, { timestamps: true });

masterBrokerAccessSchema.index({ master_id: 1 }, { unique: true });

module.exports = mongoose.model('MasterBrokerAccess', masterBrokerAccessSchema);
