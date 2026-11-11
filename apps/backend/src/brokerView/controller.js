'use strict';

// Broker view — read-only data for the clients currently linked to the signed-in
// broker (open BrokerClientLink, to: null) (owner, 11 Nov 2026).
//
// The figures come from the SAME handlers the admin's screens use, called for
// ONE client that has just been checked to be linked to this broker — so a
// broker sees exactly what an admin sees for that client, and the bill matches
// the client's and master's to the rupee (no second copy of any query to drift):
//   summary + positions  masterPositionController.getUserMetrics (?user_id)
//   trades               masterTradeController.getAllTrades     (?user_id)
//   bill                 tradeController.getPositions + getUserMetrics +
//                        tradeReportController.getSettlementHistory +
//                        adminController.getAllBrokerageSettings + kiteController.getInstrumentsInfo
// Those handlers branch on req.admin only to decide access and to apply an
// admin's hidden-masters filter; the context passed here has no hidden masters,
// no permissions, is watch-only and only ever reaches GET handlers.

const mongoose = require('mongoose');
const BrokerClientLink = require('../models/BrokerClientLink');
const User = require('../models/User');
const Master = require('../models/Master');
const { brokerProfile } = require('./auth');

const fail = (res, status, message) => res.status(status).json({ success: false, message, data: null });
const isId = (id) => mongoose.Types.ObjectId.isValid(String(id || ''));

/** Runs an existing GET handler for one client and returns { status, body }. */
function runHandler(handler, req, query) {
  return new Promise((resolve, reject) => {
    const ctx = {
      method: 'GET',
      query: { ...query },
      params: {},
      body: {},
      headers: {},
      // Read-only view context (see the header). id is the broker's, so any log line names him.
      admin: { id: `broker:${req.broker.id}`, isSuperAdmin: false, watchOnly: true, permissions: [], hiddenMasterIds: [] },
    };
    let status = 200;
    const res = {
      status(code) { status = code; return res; },
      json(body) { resolve({ status, body }); return res; },
      send(body) { resolve({ status, body }); return res; },
    };
    Promise.resolve(handler(ctx, res)).catch(reject);
  });
}

async function linkedUserIds(brokerId) {
  const links = await BrokerClientLink.find({ broker_id: brokerId, to: null }).select('user_id').lean();
  return links.map((l) => String(l.user_id));
}

/** The client must be linked to this broker right now — else 404 (never "exists but not yours"). */
async function assertLinked(req, res) {
  const userId = String(req.params.userId || '');
  if (!isId(userId)) { fail(res, 400, 'Invalid client'); return null; }
  const link = await BrokerClientLink.exists({ broker_id: req.broker.id, user_id: userId, to: null });
  if (!link) { fail(res, 404, 'Client not found'); return null; }
  const user = await User.findOne({ _id: userId, deleted_at: null }).select('name username master_id').lean();
  if (!user) { fail(res, 404, 'Client not found'); return null; }
  return user;
}

async function masterLabels(masterIds) {
  const masters = await Master.find({ _id: { $in: masterIds.filter(isId) } }).select('name username').lean();
  return new Map(masters.map((m) => [String(m._id), { id: String(m._id), name: m.name, username: m.username }]));
}

const metricsOf = () => require('../controllers/masterPositionController').getUserMetrics;

/** GET /api/broker/me */
const me = async (req, res) => {
  res.status(200).json({ success: true, data: brokerProfile({ _id: req.broker.id, name: req.broker.name, username: req.broker.username }) });
};

/** GET /api/broker/clients — linked clients with their live summary (no positions list). */
const clients = async (req, res) => {
  try {
    const ids = await linkedUserIds(req.broker.id);
    if (ids.length === 0) return res.status(200).json({ success: true, data: [] });
    const users = await User.find({ _id: { $in: ids }, deleted_at: null }).select('name username master_id').sort({ name: 1 }).lean();
    const masters = await masterLabels([...new Set(users.map((u) => String(u.master_id)))]);
    const rows = [];
    for (const u of users) {
      const { status, body } = await runHandler(metricsOf(), req, { user_id: String(u._id) });
      const m = status === 200 && Array.isArray(body?.data) ? body.data[0] : null;
      rows.push({
        user_id: String(u._id),
        name: u.name,
        username: u.username,
        master: masters.get(String(u.master_id)) || null,
        credit: m?.credit ?? 0,
        realised_pnl: m?.realised_pnl ?? 0,
        position_pnl: m?.position_pnl ?? 0,
        m2m_pnl: m?.m2m_pnl ?? 0,
        margin_used: m?.margin_used ?? 0,
        equity: m?.equity ?? 0,
        free_margin: m?.free_margin ?? 0,
        open_positions_count: m?.open_positions_count ?? (m?.positions?.length || 0),
      });
    }
    res.status(200).json({ success: true, data: rows });
  } catch (error) {
    console.error('[BrokerView] clients:', error.message);
    fail(res, 500, 'Could not load clients');
  }
};

/** GET /api/broker/clients/:userId — summary + open positions (same as the admin's Position tab). */
const clientMetrics = async (req, res) => {
  try {
    const user = await assertLinked(req, res);
    if (!user) return;
    const { status, body } = await runHandler(metricsOf(), req, { user_id: String(user._id) });
    if (status !== 200) return res.status(status).json(body);
    const masters = await masterLabels([String(user.master_id)]);
    const m = Array.isArray(body?.data) ? body.data[0] : null;
    res.status(200).json({
      success: true,
      data: {
        user_id: String(user._id),
        name: user.name,
        username: user.username,
        master: masters.get(String(user.master_id)) || null,
        metrics: m ? { ...m, wallet: undefined } : null,
      },
    });
  } catch (error) {
    console.error('[BrokerView] client:', error.message);
    fail(res, 500, 'Could not load the client');
  }
};

/** GET /api/broker/clients/:userId/trades?page&limit&date_from&date_to&status&exchange&tradingsymbol */
const clientTrades = async (req, res) => {
  try {
    const user = await assertLinked(req, res);
    if (!user) return;
    const q = { user_id: String(user._id) };
    for (const k of ['page', 'limit', 'date_from', 'date_to', 'status', 'exchange', 'tradingsymbol']) {
      if (req.query[k] !== undefined && req.query[k] !== '') q[k] = String(req.query[k]);
    }
    q.limit = String(Math.min(Math.max(Number(q.limit) || 50, 1), 500));
    const handler = require('../controllers/masterTradeController').getAllTrades;
    const { status, body } = await runHandler(handler, req, q);
    res.status(status).json(body);
  } catch (error) {
    console.error('[BrokerView] trades:', error.message);
    fail(res, 500, 'Could not load trades');
  }
};

/**
 * GET /api/broker/clients/:userId/bill-data — everything the web's Live Bill
 * needs, in the shapes the web already reads (lib/clientBill.ts): every week.
 */
const clientBillData = async (req, res) => {
  try {
    const user = await assertLinked(req, res);
    if (!user) return;
    const uid = String(user._id);
    const [positions, metrics, settlement] = await Promise.all([
      runHandler(require('../controllers/tradeController').getPositions, req, { user_id: uid }),
      runHandler(metricsOf(), req, { user_id: uid }),
      runHandler(require('../controllers/tradeReportController').getSettlementHistory, req, { user_id: uid }),
    ]);
    for (const r of [positions, metrics, settlement]) if (r.status !== 200) return res.status(r.status).json(r.body);
    const settings = require('../controllers/adminController').getAllBrokerageSettings;
    const [userRules, globalRules] = await Promise.all([
      runHandler(settings, req, { user_id: uid, limit: '2000' }),
      runHandler(settings, req, { limit: '2000' }),
    ]);
    const trades = Array.isArray(positions.body?.data) ? positions.body.data : [];
    const held = Array.isArray(metrics.body?.data) && metrics.body.data[0] ? metrics.body.data[0].positions || [] : [];
    const settled = Array.isArray(settlement.body?.data) ? settlement.body.data : [];
    const tokens = [...new Set([...trades, ...held, ...settled].map((t) => t.instrument_token).filter((t) => t != null).map(String))];
    const instruments = tokens.length > 0
      ? await runHandler(require('../controllers/kiteController').getInstrumentsInfo, req, { tokens: tokens.join(',') })
      : { status: 200, body: { data: [] } };
    res.status(200).json({
      success: true,
      data: {
        trades,
        metrics: metrics.body?.data ?? [],
        settlement: { data: settled, comex_fx: settlement.body?.comex_fx ?? null },
        brokerage: {
          user: userRules.body?.data ?? null,
          global: globalRules.body?.data ?? null,
        },
        instruments: instruments.body?.data ?? [],
      },
    });
  } catch (error) {
    console.error('[BrokerView] bill:', error.message);
    fail(res, 500, 'Could not load the bill');
  }
};

module.exports = { me, clients, clientMetrics, clientTrades, clientBillData, _private: { runHandler } };
