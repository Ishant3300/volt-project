'use strict';

/**
 * Shared exchange-permission helpers — same normalized allow-list model
 * tradeController.js's placeTrade already enforces at order time (see its
 * own "Exchange permission check" comment), now reused for the watchlist
 * (search/add/list), which never enforced this at all: a client could
 * search for, add, and see live prices on an exchange their own account
 * was never granted, even though the same segment was already correctly
 * blocked the moment they tried to actually trade it.
 *
 * `req.user`/`req.master` from authenticateAny are just decoded JWT claims
 * (no `exchanges_allowed`), so every caller here needs its own fresh
 * lookup — same reason placeTrade re-fetches its own `user` document
 * rather than trusting the token.
 */

const User = require('../models/User');
const Master = require('../models/Master');

/**
 * A client's exchanges_allowed row only grants the exchange when it is
 * actually ticked — turnover or lot on (same rule the create/edit screens
 * show). A saved row with both off means NOT allowed: the web create form
 * used to save a row for every exchange, ticked or not, and the presence of
 * the row alone let the client trade it.
 */
function isUserExchangeRowAllowed(row) {
  return !!row && (row.turnover === true || row.lot === true);
}

/** GLOBAL/INDICES are the same permission — see tradeController.js's identical note. */
function normalizeExchangeName(name) {
  const upper = String(name || '').toUpperCase();
  return upper === 'INDICES' ? 'GLOBAL' : upper;
}

/**
 * Resolves the caller's allowed-exchange set from `req` (already
 * authenticated via authenticateAny/authenticateAdminOrMaster).
 * Returns `null` for an admin caller — unrestricted, by design, same as
 * every other account-level gate in this codebase.
 */
async function getAllowedExchangeSet(req) {
  if (req.admin) return null;

  if (req.user) {
    const doc = await User.findById(req.user.id).select('exchanges_allowed').lean();
    const rows = (doc?.exchanges_allowed || []).filter(isUserExchangeRowAllowed);
    return new Set(rows.map((ex) => normalizeExchangeName(ex.exchange_name)));
  }

  if (req.master) {
    const doc = await Master.findById(req.master.id).select('exchanges_allowed').lean();
    // Master.exchanges_allowed is a plain string array — NOT the
    // {exchange_name, turnover, lot, group_name} objects User uses (see
    // Master.js's own field comment).
    const rows = doc?.exchanges_allowed || [];
    return new Set(rows.map((name) => normalizeExchangeName(name)));
  }

  // No recognized actor — treat as unrestricted rather than silently
  // hiding everything; the route's own auth middleware already rejects an
  // unauthenticated request before this ever runs.
  return null;
}

/** `allowedSet === null` means unrestricted (admin). */
function isExchangeAllowed(allowedSet, segmentOrExchange) {
  if (allowedSet === null) return true;
  return allowedSet.has(normalizeExchangeName(segmentOrExchange));
}

module.exports = { getAllowedExchangeSet, isExchangeAllowed, normalizeExchangeName, isUserExchangeRowAllowed };
