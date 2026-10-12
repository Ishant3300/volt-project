'use strict';

/**
 * Close-only mode (User.close_only): an order may only REDUCE an existing
 * position — never open one, add to one, or go through zero into the other
 * side. Checking the direction alone let an oversized order flip the
 * position (long 750, SELL 1500 -> a fresh short of 750).
 *
 * `pendingSameSide` is the quantity of this account's other pending orders on
 * the same side for the instrument (placement only — they may fill too); at
 * fill time pass 0.
 *
 * Returns the rejection message, or null when the order is allowed.
 */
const CLOSE_ONLY_MESSAGE = 'Your account is in close-only mode. You can only close existing positions.';

function closeOnlyRejection({ currentNetQty, transactionType, quantity, pendingSameSide = 0 }) {
  const net = Number(currentNetQty) || 0;
  const isClosing = (transactionType === 'SELL' && net > 0) || (transactionType === 'BUY' && net < 0);
  if (!isClosing) return CLOSE_ONLY_MESSAGE;
  const room = Math.abs(net) - (Number(pendingSameSide) || 0);
  if (Number(quantity) > room) {
    const pendingNote = pendingSameSide > 0 ? ` (${pendingSameSide} already in pending orders)` : '';
    return `${CLOSE_ONLY_MESSAGE} At most ${Math.max(0, room)} qty can be ${transactionType === 'SELL' ? 'sold' : 'bought'} here${pendingNote}.`;
  }
  return null;
}

module.exports = { closeOnlyRejection, CLOSE_ONLY_MESSAGE };
