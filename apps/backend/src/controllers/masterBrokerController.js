'use strict';

/**
 * Brokers for masters (owner, 11 Nov 2026) — only for a master an admin has
 * allowed ("Brokers allowed", MasterBrokerAccess). A master:
 *   - sees and manages only his OWN brokers (Broker.owner_master_id = him);
 *   - adds a broker only on his DIRECT clients and DIRECT sub-masters, so the
 *     broker is always paid out of his own share (services/brokerLinks.js);
 *   - sees a broker's statement only for the links paid from his part.
 * Tracking only — nothing here touches users, masters, trades, brokerage
 * rules, the ledger or settlement.
 */

const mongoose = require('mongoose');
const Broker = require('../models/Broker');
const BrokerClientLink = require('../models/BrokerClientLink');
const BrokerMasterLink = require('../models/BrokerMasterLink');
const MasterBrokerAccess = require('../models/MasterBrokerAccess');
const User = require('../models/User');
const Master = require('../models/Master');
const brokerCtl = require('./brokerController');
const svc = require('../services/brokerLinks');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');
const { escapeRegex } = require('../utils/escapeRegex');

const isId = (id) => mongoose.Types.ObjectId.isValid(String(id || ''));
const fail = (res, status, message) => res.status(status).json({ success: false, message, data: null });
const me = (req) => String(req.master.id);
const oops = (res, error) => (error.status ? fail(res, error.status, error.message) : res.status(500).json({ success: false, message: sanitizeErrorMessage(error) }));

async function isAllowed(masterId) {
  return !!(await MasterBrokerAccess.exists({ master_id: masterId, allowed: true }));
}

/** GET /api/master/brokers/access — { allowed } (the apps hide the broker option when false). */
const getAccess = async (req, res) => {
  try {
    res.status(200).json({ success: true, data: { allowed: await isAllowed(me(req)) } });
  } catch (error) { oops(res, error); }
};

/** Guard for every other route. */
async function requireAccess(req, res, next) {
  try {
    if (!req.master) return fail(res, 403, 'Brokers are for masters only');
    if (!(await isAllowed(me(req)))) return fail(res, 403, 'Brokers are not enabled for your account. Ask the admin.');
    return next();
  } catch (error) { return oops(res, error); }
}

async function ownBroker(req, res) {
  if (!isId(req.params.id)) { fail(res, 400, 'Invalid broker id'); return null; }
  const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null, owner_master_id: me(req) });
  if (!broker) { fail(res, 404, 'Broker not found'); return null; }
  return broker;
}

/** GET /api/master/brokers — own brokers with the links paid from this master's part. */
const list = async (req, res) => {
  try {
    const brokers = await Broker.find({ deleted_at: null, owner_master_id: me(req) }).sort({ name: 1 }).lean();
    const ids = brokers.map((b) => b._id);
    const myClients = await User.find({ master_id: me(req), deleted_at: null }).select('_id username name').lean();
    const clientById = new Map(myClients.map((u) => [String(u._id), u]));
    const mySubs = await Master.find({ master_id: me(req), deleted_at: null }).select('_id username name').lean();
    const subById = new Map(mySubs.map((m) => [String(m._id), m]));
    const links = await BrokerClientLink.find({ broker_id: { $in: ids }, user_id: { $in: myClients.map((u) => u._id) } }).sort({ from: -1 }).lean();
    const mlinks = await BrokerMasterLink.find({ broker_id: { $in: ids }, target_master_id: { $in: mySubs.map((m) => m._id) } }).sort({ from: -1 }).lean();
    const shape = (x) => (x ? { id: String(x._id), username: x.username, name: x.name } : null);
    const settings = (l) => ({ rates: l.rates, pnl_share_pct: Number(l.pnl_share_pct) || 0, brk_share_pct: Number(l.brk_share_pct) || 0, from: l.from, to: l.to });
    res.status(200).json({
      success: true,
      data: brokers.map((b) => ({
        id: String(b._id),
        name: b.name,
        phone: b.phone,
        note: b.note,
        status: b.status,
        created_at: b.createdAt,
        login: { username: b.username || null, enabled: !!b.login_enabled, last_login: b.last_login || null },
        links: links.filter((l) => String(l.broker_id) === String(b._id)).map((l) => ({ id: String(l._id), client: shape(clientById.get(String(l.user_id))), ...settings(l) })),
        master_links: mlinks.filter((l) => String(l.broker_id) === String(b._id)).map((l) => ({ id: String(l._id), sub_master: shape(subById.get(String(l.target_master_id))), ...settings(l) })),
      })),
    });
  } catch (error) { oops(res, error); }
};

/** POST /api/master/brokers  { name, phone?, note? } */
const create = async (req, res) => {
  try {
    const name = String(req.body.name || '').trim();
    if (!name) return fail(res, 400, 'Broker name is required');
    const clash = await Broker.findOne({ deleted_at: null, owner_master_id: me(req), name: new RegExp(`^${escapeRegex(name)}$`, 'i') }).lean();
    if (clash) return fail(res, 409, `You already have a broker named "${clash.name}"`);
    const broker = await Broker.create({ name, phone: String(req.body.phone || '').trim(), note: String(req.body.note || '').trim(), owner_master_id: me(req) });
    res.status(201).json({ success: true, data: { id: String(broker._id), name: broker.name } });
  } catch (error) { oops(res, error); }
};

/** PUT /api/master/brokers/:id  { name?, phone?, note?, status? } */
const update = async (req, res) => {
  try {
    const broker = await ownBroker(req, res);
    if (!broker) return;
    if (req.body.name !== undefined) {
      const name = String(req.body.name || '').trim();
      if (!name) return fail(res, 400, 'Broker name is required');
      const clash = await Broker.findOne({ _id: { $ne: broker._id }, deleted_at: null, owner_master_id: me(req), name: new RegExp(`^${escapeRegex(name)}$`, 'i') }).lean();
      if (clash) return fail(res, 409, `You already have a broker named "${clash.name}"`);
      broker.name = name;
    }
    if (req.body.phone !== undefined) broker.phone = String(req.body.phone || '').trim();
    if (req.body.note !== undefined) broker.note = String(req.body.note || '').trim();
    if (req.body.status !== undefined) {
      if (!['active', 'inactive'].includes(req.body.status)) return fail(res, 400, 'status must be active or inactive');
      broker.status = req.body.status;
    }
    await broker.save();
    res.status(200).json({ success: true, data: { id: String(broker._id) } });
  } catch (error) { oops(res, error); }
};

/** DELETE /api/master/brokers/:id — hides the broker and ends its open links (past weeks stay). */
const remove = async (req, res) => {
  try {
    const broker = await ownBroker(req, res);
    if (!broker) return;
    const now = new Date();
    await BrokerClientLink.updateMany({ broker_id: broker._id, to: null }, { $set: { to: now, ended_by: me(req) } });
    await BrokerMasterLink.updateMany({ broker_id: broker._id, to: null }, { $set: { to: now, ended_by: me(req) } });
    broker.deleted_at = now;
    await broker.save();
    res.status(200).json({ success: true, data: { id: String(broker._id) } });
  } catch (error) { oops(res, error); }
};

/** PUT /api/master/brokers/:id/login — same as the admin's (brokerController.setLogin), own brokers only. */
const setLogin = async (req, res) => {
  try {
    const broker = await ownBroker(req, res);
    if (!broker) return;
    return brokerCtl.setLogin(req, res);
  } catch (error) { oops(res, error); }
};

/** POST /api/master/brokers/:id/links  { user_id, rates, pnl_share_pct, brk_share_pct, from?, view_only? } — a DIRECT client. */
const addLink = async (req, res) => {
  try {
    const broker = await ownBroker(req, res);
    if (!broker) return;
    if (!isId(req.body.user_id)) return fail(res, 400, 'Select a client');
    const user = await User.findOne({ _id: req.body.user_id, deleted_at: null, master_id: me(req) }).select('_id').lean();
    if (!user) return fail(res, 404, 'Only your own direct clients can get a broker');
    const link = await svc.addClientLink({ brokerId: broker._id, userId: user._id, body: req.body, actor: { masterId: me(req) } });
    res.status(201).json({ success: true, data: { id: String(link._id) } });
  } catch (error) { oops(res, error); }
};

/** POST /api/master/brokers/:id/master-links  { master_id, ... } — a DIRECT sub-master. */
const addMasterLink = async (req, res) => {
  try {
    const broker = await ownBroker(req, res);
    if (!broker) return;
    if (!isId(req.body.master_id)) return fail(res, 400, 'Select a sub-master');
    const sub = await Master.findOne({ _id: req.body.master_id, deleted_at: null, master_id: me(req) }).select('_id').lean();
    if (!sub) return fail(res, 404, 'Only your own direct sub-masters can get a broker');
    const link = await svc.addMasterLink({ brokerId: broker._id, masterId: sub._id, body: req.body, actor: { masterId: me(req) } });
    res.status(201).json({ success: true, data: { id: String(link._id) } });
  } catch (error) { oops(res, error); }
};

async function endOwn(req, res, Model, targetCheck) {
  if (!isId(req.params.linkId)) return fail(res, 400, 'Invalid link id');
  const link = await Model.findOne({ _id: req.params.linkId, to: null });
  if (!link) return fail(res, 404, 'Open broker link not found');
  const broker = await Broker.exists({ _id: link.broker_id, owner_master_id: me(req) });
  if (!broker || !(await targetCheck(link))) return fail(res, 404, 'Open broker link not found');
  const to = req.body.to ? new Date(req.body.to) : new Date();
  if (Number.isNaN(to.getTime()) || to < link.from) return fail(res, 400, 'Invalid end date');
  link.to = to;
  link.ended_by = me(req);
  await link.save();
  return res.status(200).json({ success: true, data: { id: String(link._id) } });
}

/** PUT /api/master/brokers/links/:linkId/end */
const endLink = async (req, res) => {
  try {
    await endOwn(req, res, BrokerClientLink, async (l) => !!(await User.exists({ _id: l.user_id, master_id: me(req) })));
  } catch (error) { oops(res, error); }
};

/** PUT /api/master/brokers/master-links/:linkId/end */
const endMasterLink = async (req, res) => {
  try {
    await endOwn(req, res, BrokerMasterLink, async (l) => !!(await Master.exists({ _id: l.target_master_id, master_id: me(req) })));
  } catch (error) { oops(res, error); }
};

/** GET /api/master/brokers/limits?user_id= | ?master_id= — direct client / sub-master only. */
const getLimits = async (req, res) => {
  try {
    if (isId(req.query.user_id)) {
      if (!(await User.exists({ _id: req.query.user_id, master_id: me(req), deleted_at: null }))) return fail(res, 404, 'Not your direct client');
      return res.status(200).json({ success: true, data: await svc.clientLimits(req.query.user_id) });
    }
    if (isId(req.query.master_id)) {
      if (!(await Master.exists({ _id: req.query.master_id, master_id: me(req), deleted_at: null }))) return fail(res, 404, 'Not your direct sub-master');
      return res.status(200).json({ success: true, data: await svc.subMasterLimits(req.query.master_id) });
    }
    return fail(res, 400, 'user_id or master_id is required');
  } catch (error) { oops(res, error); }
};

/** GET /api/master/brokers/:id/statement?weeks= — only the links paid from this master's part. */
const getStatement = async (req, res) => {
  try {
    const broker = await ownBroker(req, res);
    if (!broker) return;
    const data = await brokerCtl.statementFor({ brokerId: broker._id, weeksAsked: req.query.weeks, onlyPayingMaster: me(req) });
    res.status(200).json({ success: true, data });
  } catch (error) { oops(res, error); }
};

module.exports = { getAccess, requireAccess, list, create, update, remove, setLogin, addLink, addMasterLink, endLink, endMasterLink, getLimits, getStatement, _private: { isAllowed } };
