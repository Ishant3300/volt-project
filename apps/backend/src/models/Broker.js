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
  // The master who owns this broker (created it) — null = an admin's broker.
  // A master sees and uses only his own brokers (owner, 11 Nov 2026).
  owner_master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', default: null },
  deleted_at: { type: Date, default: null },
  // Broker view login (owner, 11 Nov 2026) — view only: the clients linked to
  // this broker (open BrokerClientLink), their positions, trades and bills.
  // Set by an admin on the Brokers page (brokerController.setLogin); unique
  // across admins, masters, clients, equity accounts and brokers. The login is
  // tried last by the universal login (brokerView/auth.js), so it can never
  // shadow another account. No wallet, no trading, no place in the hierarchy.
  username: { type: String, trim: true, default: null },
  password: { type: String, default: null, select: false },
  login_enabled: { type: Boolean, default: false },
  // Changing the password or disabling the login ends every session:
  // tokens carry this time and the guard refuses an older one.
  session_since: { type: Date, default: null },
  last_login: { type: Date, default: null },
  ip_address: { type: String, default: null },
}, { timestamps: true });

brokerSchema.index({ deleted_at: 1, name: 1 });
brokerSchema.index({ username: 1 }, { unique: true, partialFilterExpression: { username: { $type: 'string' } } });

// Never send the password hash, whatever the query selected.
brokerSchema.set('toJSON', {
  transform: (doc, ret) => {
    delete ret.password;
    return ret;
  },
});

module.exports = mongoose.model('Broker', brokerSchema);
