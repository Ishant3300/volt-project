'use strict';

/**
 * Instrument tokens a client holds an open position in right now — the same
 * rule as the positions screens: completed, not-deleted trades (carry-forward
 * markers included) whose BUY qty minus SELL qty isn't zero. A held script
 * stays on the client's watchlist until the position is closed (31 Oct 2026).
 * Clients only (masters/admins don't hold positions). On any error answers
 * an empty set, i.e. the watchlist behaves as it did before.
 */
const mongoose = require('mongoose');

async function heldTokensFor(userId, ownerType = 'User') {
  if (ownerType !== 'User' || !userId || !mongoose.Types.ObjectId.isValid(String(userId))) return new Set();
  try {
    const Trade = require('../models/Trade');
    const rows = await Trade.aggregate([
      { $match: { user_id: new mongoose.Types.ObjectId(String(userId)), status: 'completed', deleted_at: null } },
      {
        $group: {
          _id: '$instrument_token',
          net: {
            $sum: {
              $cond: [
                { $eq: ['$transaction_type', 'BUY'] },
                { $ifNull: ['$executed_quantity', 0] },
                { $multiply: [{ $ifNull: ['$executed_quantity', 0] }, -1] },
              ],
            },
          },
        },
      },
      { $match: { $or: [{ net: { $gt: 1e-9 } }, { net: { $lt: -1e-9 } }] } },
    ]);
    return new Set(rows.map((r) => String(r._id)));
  } catch (err) {
    console.error('heldTokensFor failed:', err.message);
    return new Set();
  }
}

module.exports = { heldTokensFor };
