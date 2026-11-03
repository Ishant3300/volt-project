'use strict';

// Equity accounts: equity masters (waterfall under admin), equity clients, client money
// ledger entries. Own collections only — see models.js.

const bcrypt = require('bcryptjs');
const mongoose = require('mongoose');
const Admin = require('../models/Admin');
const Master = require('../models/Master');
const User = require('../models/User');
const { EqMaster, EqClient, EqLedgerEntry, EqAudit } = require('./models');
const rules = require('./rules');
const { istNow } = require('./engine');

const ok = (res, data, message = 'OK', status = 200) => res.status(status).json({ success: true, message, data });
const fail = (res, status, message, data = null) => res.status(status).json({ success: false, message, data });
const isId = (v) => mongoose.Types.ObjectId.isValid(String(v));

function actorOf(req) {
  return { role: req.cash.role, id: req.cash.id, username: req.cash.username };
}

async function audit(req, action, target, details = {}) {
  try {
    await EqAudit.create({ actor: actorOf(req), action, target, details });
  } catch (err) {
    console.log(`⚠️ [cashEq] audit write failed: ${err.message}`);
  }
}

/** Ids of `rootId` and every equity master below it. */
async function subtreeIds(rootId) {
  const all = await EqMaster.find({ deleted_at: null }).select('_id parent_id').lean();
  const kids = new Map();
  for (const m of all) {
    const p = m.parent_id ? String(m.parent_id) : null;
    if (!kids.has(p)) kids.set(p, []);
    kids.get(p).push(String(m._id));
  }
  const out = new Set([String(rootId)]);
  const queue = [String(rootId)];
  while (queue.length) for (const k of kids.get(queue.shift()) || []) if (!out.has(k)) { out.add(k); queue.push(k); }
  return out;
}

/** Equity masters the caller may see (admin: all). */
async function visibleMasterIds(req) {
  if (req.cash.role === 'admin') return null;
  if (req.cash.role === 'cash_master') return subtreeIds(req.cash.id);
  return new Set();
}

async function usernameTaken(username) {
  const q = { username };
  const [a, m, u, em, ec] = await Promise.all([
    Admin.exists(q), Master.exists(q), User.exists(q), EqMaster.exists(q), EqClient.exists(q),
  ]);
  return !!(a || m || u || em || ec);
}

function cleanUsername(v) {
  return typeof v === 'string' ? v.trim().toUpperCase() : '';
}

function badPassword(p) {
  return typeof p !== 'string' || p.length < 6 ? 'Password must be at least 6 characters' : null;
}

// ---------------------------------------------------------------------------
// Me
// ---------------------------------------------------------------------------

exports.me = async (req, res) => {
  if (req.cash.role === 'admin') return ok(res, { role: 'ADMIN', username: req.cash.username });
  const acc = req.cash.doc.toJSON();
  if (req.cash.role === 'cash_client') {
    const master = await EqMaster.findById(acc.master_id).select('name username').lean();
    acc.master = master ? { name: master.name, username: master.username } : null;
  }
  return ok(res, { role: req.cash.role.toUpperCase(), account: acc });
};

exports.changeOwnPassword = async (req, res) => {
  if (req.cash.role === 'admin') return fail(res, 400, 'Admins change their password in the admin settings');
  const { current_password, new_password } = req.body || {};
  const bad = badPassword(new_password);
  if (bad) return fail(res, 400, bad);
  const acc = req.cash.doc;
  if (!current_password || !(await bcrypt.compare(current_password, acc.password))) return fail(res, 400, 'Current password is wrong');
  acc.password = await bcrypt.hash(new_password, 10);
  acc.change_pass_on_first_login = false;
  await acc.save();
  await audit(req, 'password_change_own', { kind: req.cash.role, id: acc._id, username: acc.username });
  return ok(res, null, 'Password changed');
};

exports.generateUsername = async (_req, res) => {
  for (let i = 0; i < 20; i++) {
    const name = `EQ${Math.floor(100000 + Math.random() * 900000)}`;
    if (!(await usernameTaken(name))) return ok(res, { username: name });
  }
  return fail(res, 500, 'Could not find a free username, try again');
};

// ---------------------------------------------------------------------------
// Equity masters
// ---------------------------------------------------------------------------

exports.listMasters = async (req, res) => {
  const visible = await visibleMasterIds(req);
  const q = { deleted_at: null };
  if (visible) q._id = { $in: [...visible] };
  const masters = await EqMaster.find(q).sort({ createdAt: 1 }).lean();
  const counts = await EqClient.aggregate([
    { $match: { deleted_at: null, master_id: { $in: masters.map((m) => m._id) } } },
    { $group: { _id: '$master_id', n: { $sum: 1 } } },
  ]);
  const byId = new Map(counts.map((c) => [String(c._id), c.n]));
  const strip = ({ password, active_token, __v, ...m }) => ({ ...m, clients: byId.get(String(m._id)) || 0, is_self: String(m._id) === req.cash.id });
  return ok(res, masters.map(strip));
};

async function loadManagedMaster(req, res, { allowSelf }) {
  if (!isId(req.params.id)) { fail(res, 400, 'Invalid id'); return null; }
  const m = await EqMaster.findOne({ _id: req.params.id, deleted_at: null });
  if (!m) { fail(res, 404, 'Equity master not found'); return null; }
  if (req.cash.role === 'cash_master') {
    const mine = await subtreeIds(req.cash.id);
    const isSelf = String(m._id) === req.cash.id;
    if (!mine.has(String(m._id)) || (isSelf && !allowSelf)) { fail(res, 403, 'Not your equity master'); return null; }
  }
  return m;
}

exports.getMaster = async (req, res) => {
  const m = await loadManagedMaster(req, res, { allowSelf: true });
  if (!m) return undefined;
  const [parent, subMasters, clients] = await Promise.all([
    m.parent_id ? EqMaster.findById(m.parent_id).select('name username').lean() : null,
    EqMaster.countDocuments({ parent_id: m._id, deleted_at: null }),
    EqClient.countDocuments({ master_id: m._id, deleted_at: null }),
  ]);
  return ok(res, { ...m.toJSON(), parent, sub_masters: subMasters, clients });
};

exports.createMaster = async (req, res) => {
  const body = req.body || {};
  const username = cleanUsername(body.username);
  if (!body.name || !String(body.name).trim()) return fail(res, 400, 'Name is required');
  if (!rules.USERNAME_RE.test(username)) return fail(res, 400, 'Username must start with EQ followed by 3-14 letters or digits');
  const bad = badPassword(body.password);
  if (bad) return fail(res, 400, bad);

  // Parent: an equity master creates under itself; admin creates at the top or under any equity master.
  let parent = null;
  if (req.cash.role === 'cash_master') parent = req.cash.doc;
  else if (body.parent_id) {
    if (!isId(body.parent_id)) return fail(res, 400, 'Invalid parent');
    parent = await EqMaster.findOne({ _id: body.parent_id, deleted_at: null });
    if (!parent) return fail(res, 404, 'Parent equity master not found');
  }

  const vals = rules.normalise(body, { master: true });
  const errs = rules.checkAgainstParent(vals, parent, { master: true });
  if (errs.length) return fail(res, 400, errs[0], { errors: errs });
  if (await usernameTaken(username)) return fail(res, 409, 'Username already exists');

  const m = await EqMaster.create({
    ...vals,
    name: String(body.name).trim(),
    username,
    password: await bcrypt.hash(body.password, 10),
    parent_id: parent ? parent._id : null,
    change_pass_on_first_login: body.change_pass_on_first_login !== false,
    created_by: { role: req.cash.role, id: req.cash.id },
  });
  await audit(req, 'master_create', { kind: 'cash_master', id: m._id, username }, { parent: parent?.username || 'admin', ...vals });
  return ok(res, m.toJSON(), 'Equity master created', 201);
};

exports.updateMaster = async (req, res) => {
  const m = await loadManagedMaster(req, res, { allowSelf: false });
  if (!m) return undefined;
  const body = req.body || {};
  const current = m.toObject();
  const next = rules.normalise({
    ...current,
    ...body,
    brokerage: { ...(current.brokerage || {}), ...(body.brokerage || {}) },
  }, { master: true });

  const parent = m.parent_id ? await EqMaster.findById(m.parent_id).lean() : null;
  const errs = rules.checkAgainstParent(next, parent, { master: true });
  const [subMasters, clients] = await Promise.all([
    EqMaster.find({ parent_id: m._id, deleted_at: null }).lean(),
    EqClient.find({ master_id: m._id, deleted_at: null }).lean(),
  ]);
  errs.push(...rules.checkAgainstChildren({ ...next, username: m.username }, [...subMasters, ...clients]));
  if (errs.length) return fail(res, 400, errs[0], { errors: errs });

  Object.assign(m, next);
  if (body.name && String(body.name).trim()) m.name = String(body.name).trim();
  if (body.status && ['active', 'inactive'].includes(body.status)) m.status = body.status;
  if (body.password) {
    const bad = badPassword(body.password);
    if (bad) return fail(res, 400, bad);
    m.password = await bcrypt.hash(body.password, 10);
    m.change_pass_on_first_login = true;
  }
  await m.save();
  await audit(req, 'master_update', { kind: 'cash_master', id: m._id, username: m.username }, { ...next, status: m.status, password: body.password ? '[changed]' : undefined });
  return ok(res, m.toJSON(), 'Equity master updated');
};

exports.deleteMaster = async (req, res) => {
  const m = await loadManagedMaster(req, res, { allowSelf: false });
  if (!m) return undefined;
  const [subs, clients] = await Promise.all([
    EqMaster.countDocuments({ parent_id: m._id, deleted_at: null }),
    EqClient.countDocuments({ master_id: m._id, deleted_at: null }),
  ]);
  if (subs || clients) return fail(res, 400, `Move or delete its ${subs} sub-master(s) and ${clients} client(s) first`);
  m.deleted_at = new Date();
  m.active_token = null;
  await m.save();
  await audit(req, 'master_delete', { kind: 'cash_master', id: m._id, username: m.username });
  return ok(res, null, 'Equity master deleted');
};

// ---------------------------------------------------------------------------
// Equity clients
// ---------------------------------------------------------------------------

exports.listClients = async (req, res) => {
  const visible = await visibleMasterIds(req);
  const q = { deleted_at: null };
  if (req.query.master_id) {
    if (!isId(req.query.master_id)) return fail(res, 400, 'Invalid master');
    if (visible && !visible.has(String(req.query.master_id))) return fail(res, 403, 'Not your equity master');
    q.master_id = req.query.master_id;
  } else if (visible) {
    q.master_id = { $in: [...visible] };
  }
  const clients = await EqClient.find(q).sort({ createdAt: 1 }).select('-password -active_token -__v').lean();
  return ok(res, clients);
};

async function loadManagedClient(req, res, id = req.params.id) {
  if (!isId(id)) { fail(res, 400, 'Invalid id'); return null; }
  const c = await EqClient.findOne({ _id: id, deleted_at: null });
  if (!c) { fail(res, 404, 'Equity client not found'); return null; }
  if (req.cash.role === 'cash_master') {
    const mine = await subtreeIds(req.cash.id);
    if (!mine.has(String(c.master_id))) { fail(res, 403, 'Not your equity client'); return null; }
  } else if (req.cash.role !== 'admin') {
    fail(res, 403, 'Not allowed');
    return null;
  }
  return c;
}

exports.getClient = async (req, res) => {
  const c = await loadManagedClient(req, res);
  if (!c) return undefined;
  const master = await EqMaster.findById(c.master_id).select('name username').lean();
  return ok(res, { ...c.toJSON(), master });
};

function openingOf(body) {
  const amount = Number(body.opening_balance ?? 0);
  const type = body.opening_type === 'Dr' ? 'Dr' : 'Cr';
  return Number.isFinite(amount) && amount >= 0 ? { amount, type } : null;
}

exports.createClient = async (req, res) => {
  const body = req.body || {};
  const username = cleanUsername(body.username);
  if (!body.name || !String(body.name).trim()) return fail(res, 400, 'Name is required');
  if (!rules.USERNAME_RE.test(username)) return fail(res, 400, 'Username must start with EQ followed by 3-14 letters or digits');
  const bad = badPassword(body.password);
  if (bad) return fail(res, 400, bad);
  const opening = openingOf(body);
  if (!opening) return fail(res, 400, 'Opening balance must be a number, 0 or more');

  let master;
  if (req.cash.role === 'cash_master' && (!body.master_id || String(body.master_id) === req.cash.id)) {
    master = req.cash.doc;
  } else {
    if (!isId(body.master_id)) return fail(res, 400, 'Choose the equity master');
    master = await EqMaster.findOne({ _id: body.master_id, deleted_at: null });
    if (!master) return fail(res, 404, 'Equity master not found');
    if (req.cash.role === 'cash_master' && !(await subtreeIds(req.cash.id)).has(String(master._id))) {
      return fail(res, 403, 'Not your equity master');
    }
  }

  const vals = rules.normalise(body, { master: false });
  const errs = rules.checkAgainstParent(vals, master, { master: false });
  if (errs.length) return fail(res, 400, errs[0], { errors: errs });
  if (await usernameTaken(username)) return fail(res, 409, 'Username already exists');

  const c = await EqClient.create({
    ...vals,
    name: String(body.name).trim(),
    username,
    password: await bcrypt.hash(body.password, 10),
    master_id: master._id,
    opening_balance: opening.amount,
    opening_type: opening.type,
    change_pass_on_first_login: body.change_pass_on_first_login !== false,
    created_by: { role: req.cash.role, id: req.cash.id },
  });
  await audit(req, 'client_create', { kind: 'cash_client', id: c._id, username }, { master: master.username, opening, ...vals });
  return ok(res, c.toJSON(), 'Equity client created', 201);
};

exports.updateClient = async (req, res) => {
  const c = await loadManagedClient(req, res);
  if (!c) return undefined;
  const body = req.body || {};
  const current = c.toObject();
  const next = rules.normalise({
    ...current,
    ...body,
    brokerage: { ...(current.brokerage || {}), ...(body.brokerage || {}) },
  }, { master: false });
  const master = await EqMaster.findById(c.master_id).lean();
  const errs = rules.checkAgainstParent(next, master, { master: false });
  if (errs.length) return fail(res, 400, errs[0], { errors: errs });

  if (body.opening_balance !== undefined || body.opening_type !== undefined) {
    if (c.first_trade_at) return fail(res, 400, 'Opening balance can\'t change after the first trade — add a deposit or journal instead');
    const opening = openingOf({ opening_balance: body.opening_balance ?? c.opening_balance, opening_type: body.opening_type ?? c.opening_type });
    if (!opening) return fail(res, 400, 'Opening balance must be a number, 0 or more');
    c.opening_balance = opening.amount;
    c.opening_type = opening.type;
  }
  Object.assign(c, next);
  if (body.name && String(body.name).trim()) c.name = String(body.name).trim();
  if (body.status && ['active', 'inactive'].includes(body.status)) c.status = body.status;
  if (body.password) {
    const bad = badPassword(body.password);
    if (bad) return fail(res, 400, bad);
    c.password = await bcrypt.hash(body.password, 10);
    c.change_pass_on_first_login = true;
    c.active_token = null;
  }
  await c.save();
  await audit(req, 'client_update', { kind: 'cash_client', id: c._id, username: c.username }, {
    ...next, status: c.status, opening: { amount: c.opening_balance, type: c.opening_type }, password: body.password ? '[changed]' : undefined,
  });
  return ok(res, c.toJSON(), 'Equity client updated');
};

exports.deleteClient = async (req, res) => {
  const c = await loadManagedClient(req, res);
  if (!c) return undefined;
  if (c.first_trade_at) return fail(res, 400, 'This client has traded — close the holdings and settle the month first');
  c.deleted_at = new Date();
  c.active_token = null;
  await c.save();
  await audit(req, 'client_delete', { kind: 'cash_client', id: c._id, username: c.username });
  return ok(res, null, 'Equity client deleted');
};

// ---------------------------------------------------------------------------
// Client money ledger entries
// ---------------------------------------------------------------------------

const KINDS = ['DEPOSIT', 'WITHDRAWAL', 'JOURNAL_CR', 'JOURNAL_DR'];

exports.listLedger = async (req, res) => {
  const id = req.cash.role === 'cash_client' ? req.cash.id : req.params.id;
  const c = req.cash.role === 'cash_client' ? req.cash.doc : await loadManagedClient(req, res, id);
  if (!c) return undefined;
  const entries = await EqLedgerEntry.find({ client_id: c._id, deleted_at: null }).sort({ date: 1, createdAt: 1 }).lean();
  return ok(res, entries);
};

exports.addLedger = async (req, res) => {
  const c = await loadManagedClient(req, res);
  if (!c) return undefined;
  const { kind, narration } = req.body || {};
  const amount = Math.round(Number(req.body?.amount) * 100) / 100;
  const today = istNow().date;
  const date = req.body?.date || today;
  if (!KINDS.includes(kind)) return fail(res, 400, 'Kind must be DEPOSIT, WITHDRAWAL, JOURNAL_CR or JOURNAL_DR');
  if (!(amount > 0)) return fail(res, 400, 'Amount must be more than 0');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || date > today) return fail(res, 400, 'Date must be today or earlier');
  const e = await EqLedgerEntry.create({
    client_id: c._id, date, kind, amount, narration: typeof narration === 'string' ? narration.slice(0, 200) : '',
    created_by: actorOf(req),
  });
  await audit(req, 'ledger_add', { kind: 'cash_client', id: c._id, username: c.username }, { date, kind, amount, narration: e.narration });
  return ok(res, e.toJSON(), 'Entry added', 201);
};

exports.deleteLedger = async (req, res) => {
  const c = await loadManagedClient(req, res);
  if (!c) return undefined;
  if (!isId(req.params.entryId)) return fail(res, 400, 'Invalid entry');
  const e = await EqLedgerEntry.findOne({ _id: req.params.entryId, client_id: c._id, deleted_at: null });
  if (!e) return fail(res, 404, 'Entry not found');
  e.deleted_at = new Date();
  e.deleted_by = actorOf(req);
  await e.save();
  await audit(req, 'ledger_delete', { kind: 'cash_client', id: c._id, username: c.username }, { date: e.date, kind: e.kind, amount: e.amount });
  return ok(res, null, 'Entry deleted');
};

exports._internals = { subtreeIds, usernameTaken };
