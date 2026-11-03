'use strict';

// Equity stocks, watchlist and prices (M3). Own collections and the equity feed only.

const { EqInstrument, EqWatchlist, EqAudit } = require('./models');
const instruments = require('./instruments');
const feed = require('./feed');

const ok = (res, data, message = 'OK', status = 200) => res.status(status).json({ success: true, message, data });
const fail = (res, status, message, data = null) => res.status(status).json({ success: false, message, data });

const MAX_WATCHLIST = 100;

/** Watchlist / screen owner: the signed-in account (admin uses its admin id). */
const owner = (req) => ({ owner_role: req.cash.role, owner_id: req.cash.id });

function tokenList(raw, max = 200) {
  return String(raw || '').split(',').map((t) => Number(t.trim())).filter((t) => Number.isInteger(t) && t > 0).slice(0, max);
}

const withQuote = (inst) => ({ ...inst, quote: feed.getQuotes([inst.instrument_token])[0] || null });

exports.search = async (req, res) => {
  const rows = await instruments.search(req.query.q, Math.min(Number(req.query.limit) || 30, 50));
  return ok(res, rows.map(withQuote));
};

exports.getInstrument = async (req, res) => {
  const token = Number(req.params.token);
  const inst = await EqInstrument.findOne({ instrument_token: token }).select('-__v').lean();
  if (!inst) return fail(res, 404, 'Stock not found');
  return ok(res, withQuote(inst));
};

/** Watchlist A→Z with current quotes. */
exports.getWatchlist = async (req, res) => {
  const items = await EqWatchlist.find({ owner_id: req.cash.id }).select('instrument_token tradingsymbol').lean();
  const insts = await EqInstrument.find({ instrument_token: { $in: items.map((i) => i.instrument_token) } })
    .select('instrument_token tradingsymbol name mtf is_active tick_size').lean();
  const byToken = new Map(insts.map((i) => [i.instrument_token, i]));
  const list = items
    .map((i) => withQuote({ ...(byToken.get(i.instrument_token) || {}), instrument_token: i.instrument_token, tradingsymbol: i.tradingsymbol }))
    .sort((a, b) => a.tradingsymbol.localeCompare(b.tradingsymbol));
  return ok(res, list);
};

exports.addToWatchlist = async (req, res) => {
  const token = Number(req.body?.instrument_token);
  const inst = await EqInstrument.findOne({ instrument_token: token, is_active: true }).lean();
  if (!inst) return fail(res, 404, 'Stock not found');
  const o = owner(req);
  if (await EqWatchlist.exists({ owner_id: o.owner_id, instrument_token: token })) return ok(res, null, 'Already in your watchlist');
  if ((await EqWatchlist.countDocuments({ owner_id: o.owner_id })) >= MAX_WATCHLIST) {
    return fail(res, 400, `Your equity watchlist is full (${MAX_WATCHLIST} stocks)`);
  }
  if (!(await feed.hasRoomFor(token))) {
    return fail(res, 400, 'Equity live prices are full right now — remove a stock someone no longer watches, or try later');
  }
  await EqWatchlist.create({ ...o, instrument_token: token, tradingsymbol: inst.tradingsymbol });
  feed.refresh().catch(() => {});
  return ok(res, withQuote(inst), 'Added', 201);
};

exports.removeFromWatchlist = async (req, res) => {
  const token = Number(req.params.token);
  const r = await EqWatchlist.deleteOne({ owner_id: req.cash.id, instrument_token: token });
  feed.refresh().catch(() => {});
  return ok(res, { removed: r.deletedCount || 0 }, 'Removed');
};

exports.quotes = async (req, res) => ok(res, feed.getQuotes(tokenList(req.query.tokens)));

/**
 * The screen the caller has open needs live prices for these stocks: they're pushed as
 * 'cash_ticks' on the caller's live-price socket for the next 3 minutes (screens repeat
 * this every minute). Replies with the current quotes.
 */
exports.stream = async (req, res) => {
  const tokens = tokenList(req.body?.tokens);
  const known = new Set((await EqInstrument.find({ instrument_token: { $in: tokens } }).select('instrument_token').lean()).map((i) => i.instrument_token));
  const n = feed.setInterest(req.cash.id, tokens.filter((t) => known.has(t)));
  feed.refresh().catch(() => {});
  return ok(res, { streaming: n, quotes: feed.getQuotes([...known]) });
};

exports.feedStatus = async (_req, res) => {
  const [stocks, approved, last] = await Promise.all([
    EqInstrument.countDocuments({ is_active: true }),
    EqInstrument.countDocuments({ is_active: true, mtf: true }),
    EqAudit.findOne({ action: 'lists_sync' }).sort({ createdAt: -1 }).lean(),
  ]);
  return ok(res, { feed: feed.status(), stocks, approved, last_list_sync: last ? { at: last.createdAt, by: last.actor?.username, details: last.details } : null });
};

exports.syncNow = async (req, res) => {
  const { syncLists } = require('./jobs');
  try {
    const r = await syncLists(`admin ${req.cash.username}`);
    return ok(res, r, r.skipped ? 'A sync is already running' : 'Lists synced');
  } catch (err) {
    return fail(res, 502, `Sync failed: ${err.message}`);
  }
};
