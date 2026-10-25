'use strict';

/**
 * Profit book time (User.profit_book_minutes): a client may not close a
 * position IN PROFIT until this many minutes after opening that quantity;
 * closing at a loss is always allowed (utils/freshStoplossHold.js). Set per
 * client — it replaced the admin's per-script FreshStoplossLimit.time_minutes
 * on 20 Oct 2026. 0 = no restriction. A trade is always checked against the
 * client's own value.
 *
 * Master base (Master.profit_book_base_minutes, 25 Oct 2026 — like the
 * brokerage floor), the user's rules:
 *  - admin sets any master's base; a master sets its own sub-masters' bases
 *    (never its own);
 *  - the chain always holds, admin included: a sub-master's base >= its
 *    parent's base, a client's time >= its master's base; a top-level master
 *    has no floor;
 *  - RAISING a master's base lifts its whole tree at once: every descendant
 *    master base and every client time below the new value becomes it;
 *  - a new client / sub-master starts at its master's base.
 * Replaces the platform-wide minimum of 24 Oct 2026 (removed).
 */

const DEFAULT_PROFIT_BOOK_MINUTES = 10; // base of masters created before 25 Oct 2026, and the fallback
const MAX_PROFIT_BOOK_MINUTES = 1440; // one day

/**
 * Validate a value from a request. Returns { value } (a whole number of
 * minutes) or { error } with a message for a 400. With `min`, a value below
 * it is refused unless it equals `current` (saving an untouched field).
 */
function parseProfitBookMinutes(raw, { min, current, label = 'Profit book time', minWhy = 'base set by the upline' } = {}) {
  if (raw === null || raw === '' || raw === undefined) return { error: `${label} (minutes) is required` };
  const n = Number(raw);
  if (!Number.isFinite(n) || !Number.isInteger(n)) return { error: `${label} must be a whole number of minutes` };
  if (n < 0 || n > MAX_PROFIT_BOOK_MINUTES) return { error: `${label} must be between 0 and ${MAX_PROFIT_BOOK_MINUTES} minutes` };
  if (min != null && n < min && n !== current) return { error: `${label} cannot be less than ${min} minutes (${minWhy})` };
  return { value: n };
}

/** The minutes that apply to this user now. */
function profitBookMinutesOf(user) {
  const n = Number(user?.profit_book_minutes);
  return Number.isFinite(n) && n >= 0 ? n : DEFAULT_PROFIT_BOOK_MINUTES;
}

/** A master document's base (minutes). */
function baseOf(master) {
  const n = Number(master?.profit_book_base_minutes);
  return Number.isInteger(n) && n >= 0 ? n : DEFAULT_PROFIT_BOOK_MINUTES;
}

/** Base of the master with this id (DEFAULT if not found). */
async function masterBaseById(masterId, session = null) {
  if (!masterId) return DEFAULT_PROFIT_BOOK_MINUTES;
  const Master = require('../models/Master');
  const q = Master.findById(masterId).select('profit_book_base_minutes');
  if (session) q.session(session);
  return baseOf(await q.lean());
}

/** Every master id below this one (any depth), excluding itself. */
async function descendantMasterIds(masterId, session = null) {
  const Master = require('../models/Master');
  const out = [];
  let frontier = [masterId];
  for (let depth = 0; depth < 20 && frontier.length; depth++) {
    const q = Master.find({ master_id: { $in: frontier }, deleted_at: null }).select('_id');
    if (session) q.session(session);
    const kids = (await q.lean()).map((k) => k._id);
    out.push(...kids);
    frontier = kids;
  }
  return out;
}

/** How many sub-masters / clients in this master's tree are below `minutes` (what a raise would lift). */
async function previewLift(masterId, minutes, session = null) {
  const Master = require('../models/Master');
  const User = require('../models/User');
  const desc = await descendantMasterIds(masterId, session);
  const mq = Master.countDocuments({ _id: { $in: desc }, $or: [{ profit_book_base_minutes: { $lt: minutes } }, { profit_book_base_minutes: null }] });
  const uq = User.countDocuments({ master_id: { $in: [masterId, ...desc] }, deleted_at: null, profit_book_minutes: { $lt: minutes } });
  if (session) { mq.session(session); uq.session(session); }
  const [masters, clients] = await Promise.all([mq, uq]);
  return { masters, clients };
}

/** Raise every sub-master base and client time below `minutes` in this master's tree to it. */
async function liftTree(masterId, minutes, session = null) {
  const Master = require('../models/Master');
  const User = require('../models/User');
  const desc = await descendantMasterIds(masterId, session);
  const now = new Date();
  const opt = session ? { session } : {};
  const m = await Master.updateMany(
    { _id: { $in: desc }, $or: [{ profit_book_base_minutes: { $lt: minutes } }, { profit_book_base_minutes: null }] },
    { $set: { profit_book_base_minutes: minutes, updatedAt: now } }, opt);
  const u = await User.updateMany(
    { master_id: { $in: [masterId, ...desc] }, deleted_at: null, profit_book_minutes: { $lt: minutes } },
    { $set: { profit_book_minutes: minutes, updatedAt: now } }, opt);
  return { masters: m.modifiedCount, clients: u.modifiedCount };
}

module.exports = {
  DEFAULT_PROFIT_BOOK_MINUTES,
  MAX_PROFIT_BOOK_MINUTES,
  parseProfitBookMinutes,
  profitBookMinutesOf,
  baseOf,
  masterBaseById,
  descendantMasterIds,
  previewLift,
  liftTree,
};
