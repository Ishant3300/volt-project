'use strict';

/**
 * What lands in the Rejection Log (Trade rows with status 'rejected').
 *
 * 1. Server refusals of a client's own order (placeTrade's catch). Only
 *    known business refusals are saved — never an internal/infra error, whose
 *    message isn't meant for a master to read. Previously the list missed
 *    every "quiet" refusal (max 0, exchange not allowed, banned script, NFO
 *    3:20 window, ...), so a client who couldn't trade left no trace at all.
 *
 * 2. Refusals the mobile app makes BEFORE sending the order (stale quote,
 *    market closed, lot/qty limits, ...). The app reports them via
 *    POST /api/trade/app-rejection with a fixed reason code; the remark text
 *    is built here from that code, never taken verbatim from the client.
 */

/** placeTrade's refusal while GIFT NIFTY has no live NSE IX quote. */
const GIFT_NOT_LIVE_MESSAGE = 'GIFT NIFTY is not trading right now — no live NSE IX price. Orders are paused until live prices resume.';

const SERVER_REFUSAL_PATTERNS = [
  // already saved before
  'free margin',
  'Trade margin is not configured',
  'Fresh Stop-Loss',
  'close-only mode',
  'Trading is currently disabled',
  'Insufficient balance',
  'Insufficient margin',
  'wallet balance',
  'exceeds',
  'Option selling is not allowed',
  // previously unsaved
  'is not allowed for this account', // script max_qty 0
  'is not permitted to trade', // exchange not allowed / unticked
  'Trading is blocked', // margin call
  'contract has expired',
  'Only market orders are allowed in NFO', // 3:20-3:40 PM window
  'Cannot open new positions on this script', // banned / disabled / GIFT halt
  'You cannot open new positions on this script',
  'deactivated this script',
  'would create a short position',
  'would exceed your open position', // pending-order overflow
  'Could not determine price for MARKET order',
  'High-Low restriction', // limit inside the day range with High/low trade limit off
  'Price restriction', // Fresh Stop-Loss price offset
  GIFT_NOT_LIVE_MESSAGE,
];

function isLoggableTradeRefusal(message) {
  if (!message || typeof message !== 'string') return false;
  return SERVER_REFUSAL_PATTERNS.some((p) => message.includes(p));
}

/** Reason codes the app may report, and the label shown in the Rejection Log. */
const APP_BLOCK_REASONS = {
  STALE_QUOTE: 'Price not updated in the app for 25s (stale quote)',
  MARKET_CLOSED: 'Market closed for this exchange',
  MIN_QTY: 'Quantity below minimum',
  MAX_LOTS: 'Lots above the allowed maximum',
  MAX_QTY: 'Quantity above the allowed maximum',
  OPTION_SELL: 'Option sell without enough holding',
  LIMIT_PRICE: 'Limit price on the wrong side of CMP',
  CIRCUIT: 'Price outside circuit limit',
};

const MAX_DETAIL_LENGTH = 200;

/**
 * Remark for an app-side block: fixed label + the app's own message (what the
 * client actually saw), trimmed and stripped of control characters.
 * Returns null for an unknown code.
 */
function buildAppBlockRemark(code, detail) {
  const label = APP_BLOCK_REASONS[code];
  if (!label) return null;
  const clean = typeof detail === 'string'
    ? detail.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, MAX_DETAIL_LENGTH)
    : '';
  return `Blocked in app: ${label}${clean ? ` — "${clean}"` : ''}`;
}

module.exports = {
  isLoggableTradeRefusal,
  buildAppBlockRemark,
  APP_BLOCK_REASONS,
  SERVER_REFUSAL_PATTERNS,
  GIFT_NOT_LIVE_MESSAGE,
};
