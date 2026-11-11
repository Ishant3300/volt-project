const mongoose = require('mongoose');

/**
 * One client's broker and the broker's share of that client's brokerage, per
 * segment, for a period [from, to). A rate change ends the current link and
 * starts a new one, so earlier weeks keep the rate that applied then. At most
 * one open link (to: null) per client — enforced in brokerController.
 *
 * rates[].type follows the client's own brokerage type for the segment:
 *   TURNOVER WISE — value in paisa per ₹100 of turnover (same unit as
 *                   BrokerageSettings.brk_value: 1 = ₹1,000 per crore)
 *   LOT WISE      — value in ₹ per lot
 */
const rateSchema = new mongoose.Schema({
  segment: { type: String, required: true, trim: true, uppercase: true },
  type: { type: String, required: true, enum: ['TURNOVER WISE', 'LOT WISE'] },
  value: { type: Number, required: true, min: 0 },
  // Optional narrower scope (12 Nov 2026): an NFO Index / Stock rate, or one script's
  // rate (MCX). The most specific matching rate applies to a fill (services/brokerRates).
  category: { type: String, enum: ['INDEX', 'STOCK', null], default: null },
  script: { type: String, trim: true, uppercase: true, default: null },
}, { _id: false });

const brokerClientLinkSchema = new mongoose.Schema({
  broker_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Broker', required: true },
  user_id: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  // The client's master when the link was made — display only.
  master_id: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', default: null },
  rates: { type: [rateSchema], default: [] },
  // Broker sharing (owner, 11 Nov 2026) — tracking only, see services/brokerStatement.js:
  // the broker's % of the client's Total P&L (profit and loss) and his % of the brokerage
  // left after his own share above. Both come out of the client's master's own part;
  // nothing in the ledger, weekly, settlement or brokerage code reads them.
  pnl_share_pct: { type: Number, default: 0, min: 0, max: 100 },
  brk_share_pct: { type: Number, default: 0, min: 0, max: 100 },
  // Set when a master (allowed by admin) made the link; created_by is the admin otherwise.
  created_by_master: { type: mongoose.Schema.Types.ObjectId, ref: 'Master', default: null },
  from: { type: Date, required: true },
  to: { type: Date, default: null },
  created_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
  ended_by: { type: mongoose.Schema.Types.ObjectId, ref: 'Admin', default: null },
}, { timestamps: true });

brokerClientLinkSchema.index({ broker_id: 1, from: 1 });
brokerClientLinkSchema.index({ user_id: 1, to: 1 });

module.exports = mongoose.model('BrokerClientLink', brokerClientLinkSchema);
