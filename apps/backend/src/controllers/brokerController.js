const mongoose = require('mongoose');
const Broker = require('../models/Broker');
const BrokerClientLink = require('../models/BrokerClientLink');
const User = require('../models/User');
const Master = require('../models/Master');
const Trade = require('../models/Trade');
const KiteInstrument = require('../models/KiteInstrument');
const BrokerageSettings = require('../models/BrokerageSettings');
const { computeBrokerEarnings, normSegment } = require('../services/brokerEarnings');
const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');
const { escapeRegex } = require('../utils/escapeRegex');

/**
 * Brokers page (admin only) — introducing brokers and their share of some
 * clients' brokerage. Tracking only: nothing here writes to users, trades,
 * wallets, the ledger, the weekly report or settlement; earnings are computed
 * on read from completed trades (services/brokerEarnings.js).
 */

const RATE_TYPES = ['TURNOVER WISE', 'LOT WISE'];
// Segments whose brokerage is normally per lot — the default rate type when
// the client has no brokerage rows of their own for the segment.
const LOT_SEGMENTS = new Set(['NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT']);
const MAX_RANGE_DAYS = 400;

const isId = (id) => mongoose.Types.ObjectId.isValid(String(id || ''));
const adminId = (req) => (req.admin && isId(req.admin.id) ? req.admin.id : null);
const fail = (res, status, message) => res.status(status).json({ success: false, message, data: null });

async function hiddenSet(req) {
  const hidden = await resolveHiddenMasterIds(req);
  return hidden ? new Set([...hidden].map(String)) : null;
}

function cleanRates(raw, { allowNone = false } = {}) {
  if (!Array.isArray(raw)) return { error: 'rates must be a list of { segment, type, value }' };
  const out = [];
  const seen = new Set();
  for (const r of raw) {
    const segment = normSegment(r && r.segment);
    const type = String((r && r.type) || '').toUpperCase();
    const value = Number(r && r.value);
    if (!segment) return { error: 'Each rate needs a segment' };
    if (!RATE_TYPES.includes(type)) return { error: `Rate type for ${segment} must be TURNOVER WISE or LOT WISE` };
    if (!Number.isFinite(value) || value < 0) return { error: `Rate for ${segment} must be 0 or more` };
    if (seen.has(segment)) return { error: `${segment} is listed twice` };
    seen.add(segment);
    if (value > 0) out.push({ segment, type, value });
  }
  if (out.length === 0 && !allowNone) return { error: 'Enter a broker share for at least one segment' };
  return { rates: out };
}

/** GET /admin/brokers — every broker with its client links (open and ended). */
const listBrokers = async (req, res) => {
  try {
    const hidden = await hiddenSet(req);
    const brokers = await Broker.find({ deleted_at: null }).sort({ name: 1 }).lean();
    const links = await BrokerClientLink.find({ broker_id: { $in: brokers.map((b) => b._id) } }).sort({ from: -1 }).lean();
    const masterLinks = await require('../models/BrokerMasterLink').find({ broker_id: { $in: brokers.map((b) => b._id) } }).sort({ from: -1 }).lean();
    const users = await User.find({ _id: { $in: links.map((l) => l.user_id) } }).select('username name master_id deleted_at').lean();
    const masterIds = [...new Set([
      ...users.map((u) => String(u.master_id)), ...links.map((l) => String(l.master_id)),
      ...masterLinks.map((l) => String(l.target_master_id)), ...masterLinks.map((l) => String(l.parent_master_id)),
      ...brokers.map((b) => String(b.owner_master_id)),
    ])].filter(isId);
    const masters = await Master.find({ _id: { $in: masterIds } }).select('username name').lean();
    const userById = new Map(users.map((u) => [String(u._id), u]));
    const masterById = new Map(masters.map((m) => [String(m._id), m]));
    const shape = (m) => (m ? { id: String(m._id), username: m.username, name: m.name } : null);

    const data = brokers.map((b) => ({
      id: String(b._id),
      name: b.name,
      phone: b.phone,
      note: b.note,
      status: b.status,
      created_at: b.createdAt,
      login: { username: b.username || null, enabled: !!b.login_enabled, last_login: b.last_login || null },
      links: links
        .filter((l) => String(l.broker_id) === String(b._id))
        .map((l) => {
          const u = userById.get(String(l.user_id));
          const master = masterById.get(String(u ? u.master_id : l.master_id));
          return {
            id: String(l._id),
            client: u ? { id: String(u._id), username: u.username, name: u.name, deleted: !!u.deleted_at } : { id: String(l.user_id), username: '?', name: '?' },
            master: shape(master),
            rates: l.rates,
            pnl_share_pct: Number(l.pnl_share_pct) || 0,
            brk_share_pct: Number(l.brk_share_pct) || 0,
            from: l.from,
            to: l.to,
          };
        })
        .filter((l) => !(hidden && l.master && hidden.has(l.master.id))),
      master_links: masterLinks
        .filter((l) => String(l.broker_id) === String(b._id))
        .map((l) => ({
          id: String(l._id),
          sub_master: shape(masterById.get(String(l.target_master_id))),
          master: shape(masterById.get(String(l.parent_master_id))),
          rates: l.rates,
          pnl_share_pct: Number(l.pnl_share_pct) || 0,
          brk_share_pct: Number(l.brk_share_pct) || 0,
          from: l.from,
          to: l.to,
        }))
        .filter((l) => !(hidden && ((l.master && hidden.has(l.master.id)) || (l.sub_master && hidden.has(l.sub_master.id))))),
      owner_master: shape(masterById.get(String(b.owner_master_id))),
    }));
    res.status(200).json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** POST /admin/brokers  { name, phone?, note? } */
const createBroker = async (req, res) => {
  try {
    const name = String(req.body.name || '').trim();
    if (!name) return fail(res, 400, 'Broker name is required');
    const clash = await Broker.findOne({ deleted_at: null, name: new RegExp(`^${escapeRegex(name)}$`, 'i') }).lean();
    if (clash) return fail(res, 409, `A broker named "${clash.name}" already exists`);
    const broker = await Broker.create({
      name,
      phone: String(req.body.phone || '').trim(),
      note: String(req.body.note || '').trim(),
      created_by: adminId(req),
    });
    res.status(201).json({ success: true, data: { id: String(broker._id), name: broker.name } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** PUT /admin/brokers/:id  { name?, phone?, note?, status? } */
const updateBroker = async (req, res) => {
  try {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid broker id');
    const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null });
    if (!broker) return fail(res, 404, 'Broker not found');
    if (req.body.name !== undefined) {
      const name = String(req.body.name || '').trim();
      if (!name) return fail(res, 400, 'Broker name is required');
      const clash = await Broker.findOne({ _id: { $ne: broker._id }, deleted_at: null, name: new RegExp(`^${escapeRegex(name)}$`, 'i') }).lean();
      if (clash) return fail(res, 409, `A broker named "${clash.name}" already exists`);
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
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** DELETE /admin/brokers/:id — hides the broker and ends its open links now (past amounts stay). */
const deleteBroker = async (req, res) => {
  try {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid broker id');
    const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null });
    if (!broker) return fail(res, 404, 'Broker not found');
    const now = new Date();
    await BrokerClientLink.updateMany({ broker_id: broker._id, to: null }, { $set: { to: now, ended_by: adminId(req) } });
    broker.deleted_at = now;
    await broker.save();
    res.status(200).json({ success: true, data: { id: String(broker._id) } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * POST /admin/brokers/:id/links  { user_id, rates: [{ segment, type, value }], from? }
 * Gives the client this broker from `from` (default now). The client's open
 * link, if any, ends at that moment — so a rate change is just a new link.
 */
const addLink = async (req, res) => {
  try {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid broker id');
    if (!isId(req.body.user_id)) return fail(res, 400, 'Select a client');
    const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null }).lean();
    if (!broker) return fail(res, 404, 'Broker not found');
    const user = await User.findOne({ _id: req.body.user_id, deleted_at: null }).select('master_id').lean();
    if (!user) return fail(res, 404, 'Client not found');
    const hidden = await hiddenSet(req);
    if (hidden && hidden.has(String(user.master_id))) return fail(res, 404, 'Client not found');

    // Broker share (rate field per segment, P&L %, brokerage %) inside the limits of
    // the client's master's own part (services/brokerLinks.js). view_only / all 0 =
    // the broker only sees the client. Tracking only — nothing else reads these.
    const link = await require('../services/brokerLinks').addClientLink({
      brokerId: broker._id,
      userId: user._id,
      body: req.body,
      actor: { adminId: adminId(req) },
    });
    res.status(201).json({ success: true, data: { id: String(link._id) } });
  } catch (error) {
    if (error.status) return fail(res, error.status, error.message);
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** PUT /admin/brokers/links/:linkId/end  { to? } — removes the broker from the client from `to` (default now). */
const endLink = async (req, res) => {
  try {
    if (!isId(req.params.linkId)) return fail(res, 400, 'Invalid link id');
    const link = await BrokerClientLink.findOne({ _id: req.params.linkId, to: null });
    if (!link) return fail(res, 404, 'Open broker link not found');
    const to = req.body.to ? new Date(req.body.to) : new Date();
    if (Number.isNaN(to.getTime())) return fail(res, 400, 'Invalid end date');
    if (to < link.from) return fail(res, 400, 'End date is before the link started');
    link.to = to;
    link.ended_by = adminId(req);
    await link.save();
    res.status(200).json({ success: true, data: { id: String(link._id) } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * GET /admin/brokers/client-rates/:userId — for the "add broker" preview:
 * the client's own brokerage and their master's own rate per segment
 * (min–max over the per-script rows), plus the client's open link.
 */
const clientRates = async (req, res) => {
  try {
    if (!isId(req.params.userId)) return fail(res, 400, 'Invalid client id');
    const user = await User.findOne({ _id: req.params.userId, deleted_at: null }).select('username name master_id exchanges_allowed').lean();
    if (!user) return fail(res, 404, 'Client not found');
    const hidden = await hiddenSet(req);
    if (hidden && hidden.has(String(user.master_id))) return fail(res, 404, 'Client not found');
    const master = user.master_id ? await Master.findById(user.master_id).select('username name').lean() : null;

    const ruleFields = 'type exchange_name brk_value';
    let clientRows = await BrokerageSettings.find({ user_id: user._id, deleted_at: null }).select(ruleFields).lean();
    const usesGlobal = clientRows.length === 0;
    if (usesGlobal) clientRows = await BrokerageSettings.find({ user_id: null, deleted_at: null }).select(ruleFields).lean();
    const masterRows = master ? await BrokerageSettings.find({ user_id: master._id, deleted_at: null }).select(ruleFields).lean() : [];

    const summarize = (rows, segment) => {
      const mine = rows.filter((r) => normSegment(r.exchange_name) === segment);
      if (mine.length === 0) return null;
      const types = {};
      for (const r of mine) types[r.type] = (types[r.type] || 0) + 1;
      const type = Object.entries(types).sort((a, b) => b[1] - a[1])[0][0];
      const values = mine.filter((r) => r.type === type).map((r) => Number(r.brk_value) || 0);
      return { type, min: Math.min(...values), max: Math.max(...values), scripts: values.length };
    };
    const segments = [...new Set((user.exchanges_allowed || []).map((e) => normSegment(e.exchange_name)).filter(Boolean))];
    const data = {
      client: { id: String(user._id), username: user.username, name: user.name, uses_global_brokerage: usesGlobal },
      master: master ? { id: String(master._id), username: master.username, name: master.name } : null,
      segments: segments.map((segment) => {
        const client = summarize(clientRows, segment);
        const masterOwn = summarize(masterRows, segment);
        const fallback = LOT_SEGMENTS.has(segment) ? 'LOT WISE' : 'TURNOVER WISE';
        return { segment, type: client && RATE_TYPES.includes(client.type) ? client.type : fallback, client, master: masterOwn };
      }),
      open_link: await BrokerClientLink.findOne({ user_id: user._id, to: null }).select('broker_id rates from').lean(),
    };
    res.status(200).json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * GET /admin/brokers/earnings?from=&to=&broker_id= — per broker × client ×
 * segment × week (Monday 00:00 IST) rows over [from, to). Defaults to the
 * last 8 weeks. Includes trades already archived by weekly settlement.
 */
const getEarnings = async (req, res) => {
  try {
    let to = req.query.to ? new Date(req.query.to) : new Date();
    let from = req.query.from ? new Date(req.query.from) : new Date(to.getTime() - 56 * 864e5);
    if (Number.isNaN(from.getTime()) || Number.isNaN(to.getTime()) || from >= to) return fail(res, 400, 'Invalid date range');
    // A special session (Sunday Muhurat) counts in the week after it.
    ({ from, to } = require('../utils/specialSessions').adjustReportWindow(from, to));
    if (to - from > MAX_RANGE_DAYS * 864e5) return fail(res, 400, `Choose a range of at most ${MAX_RANGE_DAYS} days`);

    const linkFilter = { from: { $lt: to }, $or: [{ to: null }, { to: { $gt: from } }] };
    if (req.query.broker_id) {
      if (!isId(req.query.broker_id)) return fail(res, 400, 'Invalid broker id');
      linkFilter.broker_id = new mongoose.Types.ObjectId(String(req.query.broker_id));
    }
    let links = await BrokerClientLink.find(linkFilter).lean();
    const hidden = await hiddenSet(req);
    if (hidden && links.length) {
      const owners = await User.find({ _id: { $in: links.map((l) => l.user_id) } }).select('master_id').lean();
      const masterOf = new Map(owners.map((u) => [String(u._id), String(u.master_id)]));
      links = links.filter((l) => !hidden.has(masterOf.get(String(l.user_id))));
    }
    if (links.length === 0) return res.status(200).json({ success: true, data: { from, to, rows: [] } });

    const trades = await Trade.find({
      user_id: { $in: [...new Set(links.map((l) => String(l.user_id)))].map((id) => new mongoose.Types.ObjectId(id)) },
      status: 'completed',
      trade_type: { $ne: 'carry_forward' },
      executed_at: { $gte: from, $lt: to },
      // Settled weeks stay in trades with deleted_at + settlement_period_key;
      // a deleted_at without a settlement key is a genuinely deleted trade.
      $or: [{ deleted_at: null }, { settlement_period_key: { $exists: true, $ne: null } }],
    }).select('user_id instrument_token segment exchange executed_price executed_quantity quantity executed_at createdAt brokerage brokerage_exempt').lean();

    const tokens = [...new Set(trades.map((t) => t.instrument_token))];
    const insts = await KiteInstrument.find({ instrument_token: { $in: tokens } }).select('instrument_token segment lot_size').lean();
    const instruments = new Map(insts.map((i) => [String(i.instrument_token), { segment: i.segment, lot_size: i.lot_size }]));

    const rows = computeBrokerEarnings({ links, trades, instruments, from, to });
    res.status(200).json({ success: true, data: { from, to, rows } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * PUT /admin/brokers/:id/login  { username?, password?, enabled? } — the broker
 * view login (brokerView/). The username must be free across every kind of
 * account; a new password or switching the login off ends the broker's sessions.
 */
const setLogin = async (req, res) => {
  try {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid broker id');
    const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null }).select('+password');
    if (!broker) return fail(res, 404, 'Broker not found');
    const { username, password, enabled } = req.body || {};
    let endSessions = false;

    if (username !== undefined) {
      const name = String(username || '').trim();
      if (!/^[A-Za-z0-9._-]{3,30}$/.test(name)) return fail(res, 400, 'Username: 3-30 letters, digits, dot, dash or underscore');
      // EQ… usernames belong to equity accounts (they have their own login) — never used here,
      // so F&O code never has to look at equity data (equity and F&O stay apart).
      if (/^EQ/i.test(name)) return fail(res, 400, 'Usernames starting with EQ are reserved for equity accounts');
      if (name !== broker.username) {
        const Admin = require('../models/Admin');
        const taken = (await Admin.exists({ username: name })) || (await Master.exists({ username: name })) || (await User.exists({ username: name }))
          || (await Broker.exists({ _id: { $ne: broker._id }, username: name }));
        if (taken) return fail(res, 409, 'That username is already used by another account');
        broker.username = name;
        endSessions = true;
      }
    }
    if (password !== undefined) {
      const pw = String(password || '');
      if (pw.length < 6) return fail(res, 400, 'Password must be at least 6 characters');
      broker.password = await require('bcryptjs').hash(pw, 10);
      endSessions = true;
    }
    if (enabled !== undefined) {
      const on = enabled === true;
      if (on && (!broker.username || !broker.password)) return fail(res, 400, 'Set a username and password before turning the login on');
      if (!on && broker.login_enabled) endSessions = true;
      broker.login_enabled = on;
    }
    if (endSessions) broker.session_since = new Date();
    await broker.save();
    res.status(200).json({ success: true, data: { id: String(broker._id), username: broker.username, enabled: !!broker.login_enabled } });
  } catch (error) {
    if (error && error.code === 11000) return fail(res, 409, 'That username is already used by another account');
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/* ---------------------------------------------------------------- broker sharing (11 Nov 2026) */

/** POST /admin/brokers/:id/master-links  { master_id, rates, pnl_share_pct, brk_share_pct, from?, view_only? } */
const addMasterLink = async (req, res) => {
  try {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid broker id');
    if (!isId(req.body.master_id)) return fail(res, 400, 'Select a sub-master');
    const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null }).lean();
    if (!broker) return fail(res, 404, 'Broker not found');
    const hidden = await hiddenSet(req);
    const sub = await Master.findOne({ _id: req.body.master_id, deleted_at: null }).select('master_id').lean();
    if (!sub || (hidden && (hidden.has(String(sub._id)) || hidden.has(String(sub.master_id))))) return fail(res, 404, 'Sub-master not found');
    const link = await require('../services/brokerLinks').addMasterLink({ brokerId: broker._id, masterId: sub._id, body: req.body, actor: { adminId: adminId(req) } });
    res.status(201).json({ success: true, data: { id: String(link._id) } });
  } catch (error) {
    if (error.status) return fail(res, error.status, error.message);
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** PUT /admin/brokers/master-links/:linkId/end  { to? } */
const endMasterLink = async (req, res) => {
  try {
    if (!isId(req.params.linkId)) return fail(res, 400, 'Invalid link id');
    const link = await require('../models/BrokerMasterLink').findOne({ _id: req.params.linkId, to: null });
    if (!link) return fail(res, 404, 'Open broker link not found');
    const to = req.body.to ? new Date(req.body.to) : new Date();
    if (Number.isNaN(to.getTime()) || to < link.from) return fail(res, 400, 'Invalid end date');
    link.to = to;
    link.ended_by = adminId(req);
    await link.save();
    res.status(200).json({ success: true, data: { id: String(link._id) } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** GET /admin/brokers/limits?user_id= | ?master_id= — what a broker may get there (for the forms). */
const getLimits = async (req, res) => {
  try {
    const svc = require('../services/brokerLinks');
    const hidden = await hiddenSet(req);
    let data;
    if (isId(req.query.user_id)) data = await svc.clientLimits(req.query.user_id);
    else if (isId(req.query.master_id)) data = await svc.subMasterLimits(req.query.master_id);
    else return fail(res, 400, 'user_id or master_id is required');
    if (hidden && (hidden.has(data.paying_master.id) || (data.kind === 'master' && hidden.has(data.target.id)))) return fail(res, 404, 'Not found');
    res.status(200).json({ success: true, data });
  } catch (error) {
    if (error.status) return fail(res, error.status, error.message);
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** GET /admin/brokers/:id/statement?weeks= — the broker's weekly statement (services/brokerStatement.js). */
const getStatement = async (req, res) => {
  try {
    if (!isId(req.params.id)) return fail(res, 400, 'Invalid broker id');
    const broker = await Broker.findOne({ _id: req.params.id, deleted_at: null }).lean();
    if (!broker) return fail(res, 404, 'Broker not found');
    const data = await statementFor({ brokerId: broker._id, weeksAsked: req.query.weeks, hidden: await hiddenSet(req) });
    res.status(200).json({ success: true, data });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** Shared by the admin, master and broker statement routes. onlyPayingMaster: a master sees only links paid from his part. */
async function statementFor({ brokerId, weeksAsked, hidden = null, onlyPayingMaster = null }) {
  const BrokerMasterLink = require('../models/BrokerMasterLink');
  const { buildStatement, weekWindows } = require('../services/brokerStatement');
  let clientLinks = await BrokerClientLink.find({ broker_id: brokerId }).lean();
  let masterLinks = await BrokerMasterLink.find({ broker_id: brokerId }).lean();
  if (hidden || onlyPayingMaster) {
    const users = await User.find({ _id: { $in: clientLinks.map((l) => l.user_id) } }).select('master_id').lean();
    const masterOf = new Map(users.map((u) => [String(u._id), String(u.master_id)]));
    const subs = await Master.find({ _id: { $in: masterLinks.map((l) => l.target_master_id) } }).select('master_id').lean();
    const parentOf = new Map(subs.map((m) => [String(m._id), String(m.master_id)]));
    clientLinks = clientLinks.filter((l) => {
      const m = masterOf.get(String(l.user_id));
      return (!hidden || !hidden.has(m)) && (!onlyPayingMaster || m === String(onlyPayingMaster));
    });
    masterLinks = masterLinks.filter((l) => {
      const p = parentOf.get(String(l.target_master_id));
      return (!hidden || (!hidden.has(p) && !hidden.has(String(l.target_master_id)))) && (!onlyPayingMaster || p === String(onlyPayingMaster));
    });
  }
  const all = [...clientLinks, ...masterLinks];
  if (all.length === 0) return { weeks: [] };
  const since = all.reduce((m, l) => (new Date(l.from) < m ? new Date(l.from) : m), new Date());
  const max = Math.min(Math.max(Number(weeksAsked) || 8, 1), 26);
  return buildStatement({ clientLinks, masterLinks, weeks: weekWindows({ since, max }) });
}

/** GET /admin/broker-access — masters allowed to use brokers. */
const listAccess = async (req, res) => {
  try {
    const rows = await require('../models/MasterBrokerAccess').find({ allowed: true }).select('master_id updatedAt').lean();
    res.status(200).json({ success: true, data: rows.map((r) => ({ master_id: String(r.master_id), since: r.updatedAt })) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/** PUT /admin/broker-access/:masterId  { allowed } — "Brokers allowed" for one master. */
const setAccess = async (req, res) => {
  try {
    if (!isId(req.params.masterId)) return fail(res, 400, 'Invalid master id');
    const master = await Master.findOne({ _id: req.params.masterId, deleted_at: null }).select('_id').lean();
    const hidden = await hiddenSet(req);
    if (!master || (hidden && hidden.has(String(master._id)))) return fail(res, 404, 'Master not found');
    const allowed = req.body.allowed === true;
    await require('../models/MasterBrokerAccess').updateOne(
      { master_id: master._id },
      { $set: { allowed, updated_by: adminId(req) } },
      { upsert: true },
    );
    res.status(200).json({ success: true, data: { master_id: String(master._id), allowed } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = {
  listBrokers, createBroker, updateBroker, deleteBroker, addLink, endLink, clientRates, getEarnings, setLogin,
  addMasterLink, endMasterLink, getLimits, getStatement, listAccess, setAccess, statementFor,
};
