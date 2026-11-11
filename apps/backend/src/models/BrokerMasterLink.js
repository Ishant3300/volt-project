const mongoose = require('mongoose');

/**
 * A broker on a SUB-MASTER (owner, 11 Nov 2026): the broker sits between that
 * sub-master and its parent for every client in the sub-master's tree, like
 * one more level. Tracking only — services/brokerStatement.js reads it; the
 * ledger, weekly, settlement and brokerage code never does.
 *
 *   rates[]        per segment, what the broker GETS out of the sub-master's own
 *                  rate (same unit as that rate: paisa per ₹100 or ₹ per lot)
 *   pnl_share_pct  the broker's % of the tree's Total P&L (from the parent's part)
 *   brk_share_pct  the broker's % of the brokerage left after his own share
 *
 * A change ends the open link and starts a new one; the link in force at a
 * week's end applies to that whole week. At most one open link per sub-master.
 */
const rateSchema = new mongoose.Schema({
  segment: { type: String, required: true, trim: true, uppercase: true },
  type: { type: String, required: true, enum: ['TURNOVER WISE', 'LOT WISE'] },
  value: { type: Number, required: true, min: 0 },
}, { _id: false });

const brokerMasterLinkSchema = new mongoose.Schema({
  broker_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Broker', required: true },
  target_master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', required: true },
  // The sub-master's parent when the link was made — the master whose part pays the broker.
  parent_master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', default: null },
  rates: { type: [rateSchema], default: [] },
  pnl_share_pct: { type: Number, default: 0, min: 0, max: 100 },
  brk_share_pct: { type: Number, default: 0, min: 0, max: 100 },
  from: { type: Date, required: true },
  to: { type: Date, default: null },
  created_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
  created_by_master: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', default: null },
  ended_by: { type: mongoose.Schema.Types.ObjectId, default: null },
}, { timestamps: true });

brokerMasterLinkSchema.index({ broker_id: 1, from: 1 });
brokerMasterLinkSchema.index({ target_master_id: 1, to: 1 });

module.exports = mongoose.model('BrokerMasterLink', brokerMasterLinkSchema);
