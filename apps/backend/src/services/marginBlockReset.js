'use strict';

/**
 * Lift the margin-call trading block once a new settlement week has started
 * (2 Nov 2026).
 *
 * marginSquareOffService closes every position and sets
 * User.margin_call_blocked when the WEEK's live M2M loss reaches the client's
 * limit. The weekly settlement resets M2M to 0, so a block from an earlier
 * week no longer reflects any open loss — it is lifted here. A block set in
 * the current week stays until the next settlement, or until a credit
 * (creditUser / creditUserByAdmin), exactly as before.
 *
 * When the block was set = the client's latest MARGIN_SQUARE_OFF trade.
 * Touches only the flag — no ledger, wallet or settlement data.
 */
const User = require('../models/User');
const Trade = require('../models/Trade');
const SettlementRun = require('../models/SettlementRun');

async function liftBlocksFromEarlierWeeks() {
  const blocked = await User.find({ margin_call_blocked: true }).select('_id username').lean();
  if (!blocked.length) return 0;

  // Never while a settlement is in flight — wait for it to finish.
  const inFlight = await SettlementRun.exists({ status: { $in: ['running', 'committed', 'finalizing'] } });
  if (inFlight) return 0;

  const lastRun = await SettlementRun.findOne({ status: 'completed', completed_at: { $ne: null } })
    .sort({ completed_at: -1 })
    .select('period_key completed_at')
    .lean();
  if (!lastRun) return 0;
  const weekStartedAt = new Date(lastRun.completed_at);

  let lifted = 0;
  for (const u of blocked) {
    const lastSquareOff = await Trade.findOne({ user_id: u._id, remarks: 'MARGIN_SQUARE_OFF' })
      .sort({ createdAt: -1 })
      .select('createdAt')
      .lean();
    const blockedAt = lastSquareOff?.createdAt ? new Date(lastSquareOff.createdAt) : null;
    // Squared off in the current week → stays blocked until the next settlement.
    if (blockedAt && blockedAt >= weekStartedAt) continue;

    const res = await User.updateOne({ _id: u._id, margin_call_blocked: true }, { $set: { margin_call_blocked: false } });
    if (res.modifiedCount) {
      lifted++;
      console.log(`🔓 [MarginBlockReset] ${u.username}: trading block lifted — square-off ${blockedAt ? blockedAt.toISOString() : 'date unknown'} was before settlement ${lastRun.period_key}`);
    }
  }
  return lifted;
}

module.exports = { liftBlocksFromEarlierWeeks };
