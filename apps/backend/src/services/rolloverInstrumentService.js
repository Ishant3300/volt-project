/**
 * Rollover — next-expiry contract resolution.
 *
 * Given the instrument a position is currently held on, finds the next
 * contract in the same series (same underlying/strike/type/exchange, next
 * expiry after the current one) to roll the position onto.
 */

const KiteInstrument = require('../models/KiteInstrument');

/**
 * @param {object} currentInstrument - a KiteInstrument doc/lean object
 * @param {import('mongoose').ClientSession|null} [session]
 * @returns {Promise<object|null>} the next-expiry KiteInstrument (lean), or null if
 *   the current instrument has no expiry (not a derivative) or no further
 *   expiry is seeded.
 */
async function resolveNextExpiryInstrument(currentInstrument, session = null) {
  if (!currentInstrument || !currentInstrument.expiry) return null;

  const query = {
    name: currentInstrument.name,
    exchange: currentInstrument.exchange,
    instrument_type: currentInstrument.instrument_type,
    expiry: { $gt: currentInstrument.expiry },
    is_active: true,
    deleted_at: null,
  };

  // Options must roll into the SAME strike on the next expiry — a different
  // strike would silently change the position's risk profile, not just its
  // expiry.
  if (['CE', 'PE'].includes(currentInstrument.instrument_type)) {
    query.strike = currentInstrument.strike;
  }

  const q = session ? KiteInstrument.findOne(query).session(session) : KiteInstrument.findOne(query);
  return q.sort({ expiry: 1 }).lean();
}

module.exports = { resolveNextExpiryInstrument };
