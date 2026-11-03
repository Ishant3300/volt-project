'use strict';

// /api/cash-eq — equity (NSE cash) routes. Mounted once in index.js; nothing else in the
// F&O app routes here. Every route checks the on/off switch first (auth.requireCash).

const express = require('express');
const { requireCash, noWatchOnly } = require('./auth');
const c = require('./controller');

const router = express.Router();

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch((err) => {
  console.log(`❌ [cashEq] ${req.method} ${req.originalUrl}: ${err.message}`);
  if (!res.headersSent) res.status(500).json({ success: false, message: 'Something went wrong', data: null });
});

const anyone = requireCash('admin', 'cash_master', 'cash_client');
const managers = requireCash('admin', 'cash_master');

router.get('/me', anyone, wrap(c.me));
router.post('/me/password', requireCash('cash_master', 'cash_client'), wrap(c.changeOwnPassword));

router.get('/username/generate', managers, wrap(c.generateUsername));

router.get('/masters', managers, wrap(c.listMasters));
router.post('/masters', managers, noWatchOnly, wrap(c.createMaster));
router.get('/masters/:id', managers, wrap(c.getMaster));
router.patch('/masters/:id', managers, noWatchOnly, wrap(c.updateMaster));
router.delete('/masters/:id', managers, noWatchOnly, wrap(c.deleteMaster));

router.get('/clients', managers, wrap(c.listClients));
router.post('/clients', managers, noWatchOnly, wrap(c.createClient));
router.get('/clients/:id', managers, wrap(c.getClient));
router.patch('/clients/:id', managers, noWatchOnly, wrap(c.updateClient));
router.delete('/clients/:id', managers, noWatchOnly, wrap(c.deleteClient));

router.get('/ledger', requireCash('cash_client'), wrap(c.listLedger)); // client's own entries
router.get('/clients/:id/ledger', managers, wrap(c.listLedger));
router.post('/clients/:id/ledger', managers, noWatchOnly, wrap(c.addLedger));
router.delete('/clients/:id/ledger/:entryId', managers, noWatchOnly, wrap(c.deleteLedger));

// Stocks, watchlist, prices (M3).
const market = require('./market');
const adminOnly = requireCash('admin');

router.get('/instruments/search', anyone, wrap(market.search));
router.get('/instruments/:token', anyone, wrap(market.getInstrument));
router.get('/watchlist', anyone, wrap(market.getWatchlist));
router.post('/watchlist', anyone, wrap(market.addToWatchlist)); // personal list: watch-only admins too
router.delete('/watchlist/:token', anyone, wrap(market.removeFromWatchlist));
router.get('/quotes', anyone, wrap(market.quotes));
router.post('/stream', anyone, wrap(market.stream));
router.get('/feed/status', adminOnly, wrap(market.feedStatus));
router.post('/instruments/sync', adminOnly, noWatchOnly, wrap(market.syncNow));

// Orders and trades (M4).
const orders = require('./orders');
const { EqSettings } = require('./models');
const liquidity = require('./liquidity');

const send = (fn, okStatus = 200) => wrap(async (req, res) => {
  try {
    const data = await fn(req);
    if (data && data.ok === false) return res.status(400).json({ success: false, message: data.message, data: data.order });
    if (data && data.ok === true) return res.status(201).json({ success: true, message: data.message, data: data.order });
    return res.status(okStatus).json({ success: true, message: 'OK', data });
  } catch (err) {
    if (err instanceof orders.HttpError) return res.status(err.status).json({ success: false, message: err.message, data: null });
    throw err;
  }
});

router.get('/orders/preview', anyone, send((req) => orders.preview(req.cash, req.query)));
router.post('/orders', anyone, send((req) => orders.placeOrder(req.cash, req.body || {})));
router.get('/orders', anyone, send((req) => orders.listOrders(req.cash, req.query)));
router.patch('/orders/:id', anyone, send((req) => orders.modifyOrder(req.cash, req.params.id, req.body || {})));
router.post('/orders/:id/cancel', anyone, send((req) => orders.cancelOrder(req.cash, req.params.id)));
router.get('/trades', anyone, send((req) => orders.listTrades(req.cash, req.query)));

// Live account, holdings, statement (M5).
const account = require('./account');
const readAs = (fn) => send(async (req) => {
  try {
    return await fn(req);
  } catch (err) {
    if (err.status) throw new orders.HttpError(err.status, err.message);
    throw err;
  }
});
router.get('/account', anyone, readAs(async (req) => account.accountFor(await account.clientFor(req.cash, req.query.client_id))));
router.get('/statement', anyone, readAs(async (req) => {
  const date = (v) => (v && /^\d{4}-\d{2}-\d{2}$/.test(v) ? v : undefined);
  return account.statementFor(await account.clientFor(req.cash, req.query.client_id), { from: date(req.query.from), to: date(req.query.to) });
}));
/** Master / admin: every visible client's live figures + totals (optionally one master's tree). */
router.get('/accounts', managers, readAs(async (req) => {
  const clients = await account.visibleClients(req.cash, req.query.master_id);
  if (!clients) throw new orders.HttpError(403, 'Not your equity master');
  return account.accountsFor(clients);
}));
/** Master / admin portfolio page: all holdings across the tree, with the tiles' totals. */
router.get('/holdings', managers, readAs(async (req) => {
  const clients = await account.visibleClients(req.cash, req.query.master_id);
  if (!clients) throw new orders.HttpError(403, 'Not your equity master');
  const all = await account.accountsFor(clients);
  const rows = [];
  for (const a of all.accounts) for (const h of a.holdings) rows.push({ ...h, client: { _id: a.client._id, name: a.client.name, username: a.client.username } });
  rows.sort((x, y) => x.script.localeCompare(y.script) || x.client.username.localeCompare(y.client.username));
  return { totals: all.totals, holdings: rows };
}));

// Month-end (M6): admin runs it; masters read their sharing statement.
const monthEnd = require('./monthEnd');
const meSend = (fn) => send(async (req) => {
  try {
    return await fn(req);
  } catch (err) {
    if (err instanceof monthEnd.HttpError) {
      const e = new orders.HttpError(err.status, err.message);
      throw e;
    }
    throw err;
  }
});
router.get('/month-end', adminOnly, meSend(() => monthEnd.list()));
router.post('/month-end/preview', adminOnly, noWatchOnly, meSend((req) => monthEnd.preview(req.cash, req.body || {})));
router.patch('/month-end/:id/prices', adminOnly, noWatchOnly, meSend((req) => monthEnd.setPrices(req.cash, req.params.id, req.body?.prices)));
router.post('/month-end/:id/confirm', adminOnly, noWatchOnly, meSend((req) => monthEnd.confirm(req.cash, req.params.id)));
router.delete('/month-end/:id', adminOnly, noWatchOnly, meSend((req) => monthEnd.remove(req.cash, req.params.id)));
router.get('/sharing', managers, meSend((req) => monthEnd.sharingFor(req.cash, String(req.query.month || ''))));

// Low-volume fill settings (admin).
router.get('/settings/liquidity', managers, send(async () => ({ ...(await orders.getSettings()), defaults: liquidity.DEFAULTS })));
router.patch('/settings/liquidity', adminOnly, noWatchOnly, send(async (req) => {
  const current = await orders.getSettings();
  const body = req.body || {};
  const next = liquidity.settingsWith({ ...current, ...body });
  const errs = liquidity.checkSettings(next);
  const holidays = body.holidays === undefined ? current.holidays : body.holidays;
  if (!Array.isArray(holidays) || holidays.some((d) => !/^\d{4}-\d{2}-\d{2}$/.test(d))) errs.push('holidays must be a list of YYYY-MM-DD dates');
  if (errs.length) throw new orders.HttpError(400, errs[0]);
  await EqSettings.findOneAndUpdate(
    { _id: 'liquidity' },
    { $set: { values: { ...next, holidays: [...new Set(holidays)].sort() }, updated_by: { role: req.cash.role, id: req.cash.id, username: req.cash.username } } },
    { upsert: true, new: true }
  );
  orders.clearSettingsCache();
  return orders.getSettings();
}));

module.exports = router;
