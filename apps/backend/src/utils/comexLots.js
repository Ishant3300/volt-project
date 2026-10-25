'use strict';

/**
 * COMEX trades in whole lots only, like MCX (the user, 25 Oct 2026). A lot is
 * the official contract size from Massive (KiteInstrument.lot_size: Gold 100,
 * Silver 5,000, Copper 25,000). Every COMEX order — client or admin — must be
 * a whole number of lots, and COMEX trades in lot mode (the ticket asks for
 * lots, quantity limits count lots) whatever is ticked on the client's
 * exchange row. The Lot / Turnover tick itself is the admin's choice (it
 * also picks the brokerage type) and is never changed here; an unticked row
 * still means the segment isn't allowed.
 */

const COMEX_SEGMENT = 'COMEX-FUT';
const WHOLE_LOTS_TEXT = 'COMEX trades in whole lots only';

function isComexSegment(segment, exchange) {
  const s = String(segment || '').toUpperCase();
  const e = String(exchange || '').toUpperCase();
  return s === COMEX_SEGMENT || e === 'COMEX';
}

/**
 * Trading mode for a client's exchange row: { lot, turnover } as ticked —
 * except a ticked COMEX row always trades in lots.
 */
function tradingModeFor(row, segment) {
  const lot = row?.lot === true;
  const turnover = row?.turnover === true;
  if (String(segment || row?.exchange_name || '').toUpperCase() === COMEX_SEGMENT && (lot || turnover)) {
    return { lot: true, turnover: false };
  }
  return { lot, turnover };
}

/** Throws (status 400) unless a COMEX order's quantity is a whole number of lots. */
async function validateComexWholeLots({ segment, exchange, instrument_token, quantity, session = null }) {
  if (!isComexSegment(segment, exchange)) return;
  const KiteInstrument = require('../models/KiteInstrument');
  const q = KiteInstrument.findOne({ instrument_token: String(instrument_token) }).select('lot_size name tradingsymbol segment');
  if (session) q.session(session);
  const inst = await q.lean();
  if (inst && inst.segment && inst.segment !== COMEX_SEGMENT) return;
  const lot = Number(inst?.lot_size) || 0;
  const qty = Number(quantity);
  if (lot > 1 && (!Number.isFinite(qty) || qty <= 0 || qty % lot !== 0)) {
    const error = new Error(`${WHOLE_LOTS_TEXT} — 1 lot of ${inst.name || inst.tradingsymbol} = ${lot}. Enter the quantity as lots (a multiple of ${lot}).`);
    error.status = 400;
    throw error;
  }
}

module.exports = { COMEX_SEGMENT, WHOLE_LOTS_TEXT, isComexSegment, tradingModeFor, validateComexWholeLots };
