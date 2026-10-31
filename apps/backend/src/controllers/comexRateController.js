'use strict';

/**
 * COMEX USD→INR rate (utils/comexFx.js): admin sets base + spread; the weekly
 * settlement converts each client's COMEX net at base + spread (debit) or
 * base − spread (credit). Read: admin and masters (bills show the estimate).
 * Write: admin only, refused while a settlement is in progress so a run never
 * sees a rate change halfway.
 */

const ComexRate = require('../models/ComexRate');
const SettlementRun = require('../models/SettlementRun');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

const IN_PROGRESS = ['running', 'committed', 'finalizing'];

function view(doc) {
  if (!doc) return { base: null, spread: null, debit_rate: null, credit_rate: null, updated_by: null, updated_at: null, history: [] };
  return {
    base: doc.base,
    spread: doc.spread,
    debit_rate: doc.base + doc.spread,
    credit_rate: doc.base - doc.spread,
    updated_by: doc.updated_by,
    updated_at: doc.updated_at,
    history: (doc.history || []).slice(-20).reverse(),
  };
}

const getComexRate = async (req, res) => {
  try {
    const doc = await ComexRate.findOne({ key: 'comex' }).lean();
    res.status(200).json({ success: true, data: view(doc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

const setComexRate = async (req, res) => {
  try {
    const base = Number(req.body?.base);
    const spread = Number(req.body?.spread);
    if (!Number.isFinite(base) || base <= 0 || base > 1000) {
      return res.status(400).json({ success: false, message: 'Base rate must be a number above 0 (e.g. 88.00)' });
    }
    if (!Number.isFinite(spread) || spread < 0 || spread >= base) {
      return res.status(400).json({ success: false, message: 'Spread must be 0 or more and less than the base rate' });
    }
    const running = await SettlementRun.findOne({ status: { $in: IN_PROGRESS } }).select('_id period_key').lean();
    if (running) {
      return res.status(409).json({ success: false, message: 'A settlement is in progress — change the COMEX rate after it finishes' });
    }
    const by = req.admin?.username || req.admin?.name || (req.admin?.id ? String(req.admin.id) : null);
    const now = new Date();
    const r2 = (n) => Math.round(n * 10000) / 10000;
    const doc = await ComexRate.findOneAndUpdate(
      { key: 'comex' },
      {
        $set: { base: r2(base), spread: r2(spread), updated_by: by, updated_at: now },
        $push: { history: { $each: [{ base: r2(base), spread: r2(spread), by, at: now }], $slice: -200 } },
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ).lean();
    res.status(200).json({ success: true, data: view(doc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

// ─── An account's own rate (1 Nov 2026) ─────────────────────────────────────
// A client or master may have their own base + spread, set where COMEX is
// ticked (create/edit). Without one an account inherits the nearest master
// above with one, else admin's default. Admin may set any account; a master
// only accounts below him (not himself), never below the rate of the master
// directly above that account. Refused while a settlement runs; every change
// logged. Removing it = inherit again. The settlement converts each CLIENT at
// that client's rate (utils/comexFx.js); ledger and sharing are unchanged.

const mongoose = require('mongoose');
const User = require('../models/User');
const Master = require('../models/Master');
const { clientKey, masterKey, belowFloorMessage, loadComexFxResolver } = require('../utils/comexFx');

const r4 = (n) => Math.round(n * 10000) / 10000;
const KINDS = {
  client: { Model: User, key: clientKey, idField: 'user_id', label: 'Client' },
  master: { Model: Master, key: masterKey, idField: 'master_id', label: 'Master' },
};

function parseRate(body) {
  const base = Number(body?.base);
  const spread = Number(body?.spread);
  if (!Number.isFinite(base) || base <= 0 || base > 1000) return { error: 'Dollar rate must be a number above 0 (e.g. 88.00)' };
  if (!Number.isFinite(spread) || spread < 0 || spread >= base) return { error: 'Spread must be 0 or more and less than the dollar rate' };
  return { base: r4(base), spread: r4(spread) };
}

function actor(req) {
  if (req.admin) return req.admin.username || req.admin.name || String(req.admin.id);
  if (req.master) return req.master.username || req.master.name || String(req.master.id);
  return null;
}

/**
 * The account, if the caller may see it (write: change it). A master: clients
 * and sub-masters in his own tree; he may read his own rate but not change
 * it. An admin: anything under masters visible to him.
 */
async function scopedAccount(req, kind, id, { write }) {
  const spec = KINDS[kind];
  if (!mongoose.isValidObjectId(id)) return { status: 400, message: `Invalid ${spec.label.toLowerCase()} id` };
  const account = await spec.Model.findOne({ _id: id, deleted_at: null }).select('_id username name master_id').lean();
  if (!account) return { status: 404, message: `${spec.label} not found` };
  const parentId = account.master_id ? String(account.master_id) : null;
  if (req.master) {
    const self = String(req.master.id);
    if (kind === 'master' && String(account._id) === self) {
      if (write) return { status: 403, message: 'Your own COMEX rate is set by the account above you' };
    } else {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowed = await getAllSubMasterIds(self);
      const inTree = kind === 'client' ? allowed.includes(parentId) : allowed.includes(String(account._id));
      if (!inTree) return { status: 403, message: `Not authorized for this ${spec.label.toLowerCase()}'s COMEX rate` };
    }
  } else if (req.admin) {
    const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
    const hidden = await resolveHiddenMasterIds(req);
    const ownerId = kind === 'client' ? parentId : String(account._id);
    if (hidden && hidden.has(ownerId)) return { status: 404, message: `${spec.label} not found` };
  } else {
    return { status: 403, message: 'Access denied' };
  }
  return { account, parentId };
}

const rateView = (f) => (f ? { base: f.base, spread: f.spread, debit_rate: f.base + f.spread, credit_rate: f.base - f.spread } : null);

/** own / effective (what applies) / floor (the master directly above — the limit for a master). */
async function accountView(kind, account, parentId, ownDoc) {
  const fxFor = await loadComexFxResolver(kind === 'client' ? [account._id] : [], null, {
    masterIds: [kind === 'master' ? account._id : null, parentId].filter(Boolean),
  });
  const effective = kind === 'client' ? fxFor(account._id) : fxFor.forMaster(account._id);
  const floor = parentId ? fxFor.forMaster(parentId) : null;
  const own = ownDoc && ownDoc.active !== false ? ownDoc : null;
  return {
    account: { id: account._id, kind, username: account.username, name: account.name },
    own: own ? { ...rateView(own), updated_by: own.updated_by, updated_at: own.updated_at } : null,
    effective: effective ? { ...rateView(effective), source: effective.source } : null,
    floor: floor ? { ...rateView(floor), source: floor.source } : null,
    history: ((ownDoc && ownDoc.history) || []).slice(-20).reverse(),
  };
}

const getAccountRate = (kind) => async (req, res) => {
  try {
    const scope = await scopedAccount(req, kind, req.params.id, { write: false });
    if (!scope.account) return res.status(scope.status).json({ success: false, message: scope.message });
    const ownDoc = await ComexRate.findOne({ key: KINDS[kind].key(scope.account._id) }).lean();
    res.status(200).json({ success: true, data: await accountView(kind, scope.account, scope.parentId, ownDoc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

const setAccountRate = (kind) => async (req, res) => {
  try {
    const rate = parseRate(req.body);
    if (rate.error) return res.status(400).json({ success: false, message: rate.error });
    const scope = await scopedAccount(req, kind, req.params.id, { write: true });
    if (!scope.account) return res.status(scope.status).json({ success: false, message: scope.message });
    if (req.master && scope.parentId) {
      const floor = (await loadComexFxResolver([], null, { masterIds: [scope.parentId] })).forMaster(scope.parentId);
      const below = belowFloorMessage(rate, floor);
      if (below) return res.status(400).json({ success: false, message: below });
    }
    const running = await SettlementRun.findOne({ status: { $in: IN_PROGRESS } }).select('_id').lean();
    if (running) {
      return res.status(409).json({ success: false, message: 'A settlement is in progress — change the COMEX rate after it finishes' });
    }
    const spec = KINDS[kind];
    const by = actor(req);
    const now = new Date();
    const ownDoc = await ComexRate.findOneAndUpdate(
      { key: spec.key(scope.account._id) },
      {
        $set: { [spec.idField]: scope.account._id, active: true, base: rate.base, spread: rate.spread, updated_by: by, updated_at: now },
        $push: { history: { $each: [{ base: rate.base, spread: rate.spread, by, at: now }], $slice: -200 } },
      },
      { upsert: true, new: true, setDefaultsOnInsert: true },
    ).lean();
    res.status(200).json({ success: true, data: await accountView(kind, scope.account, scope.parentId, ownDoc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

const clearAccountRate = (kind) => async (req, res) => {
  try {
    const scope = await scopedAccount(req, kind, req.params.id, { write: true });
    if (!scope.account) return res.status(scope.status).json({ success: false, message: scope.message });
    const running = await SettlementRun.findOne({ status: { $in: IN_PROGRESS } }).select('_id').lean();
    if (running) {
      return res.status(409).json({ success: false, message: 'A settlement is in progress — change the COMEX rate after it finishes' });
    }
    const key = KINDS[kind].key(scope.account._id);
    const by = actor(req);
    const now = new Date();
    let ownDoc = await ComexRate.findOne({ key }).lean();
    if (ownDoc && ownDoc.active !== false) {
      ownDoc = await ComexRate.findOneAndUpdate(
        { key },
        {
          $set: { active: false, updated_by: by, updated_at: now },
          $push: { history: { $each: [{ base: ownDoc.base, spread: ownDoc.spread, by, at: now, cleared: true }], $slice: -200 } },
        },
        { new: true },
      ).lean();
    }
    res.status(200).json({ success: true, data: await accountView(kind, scope.account, scope.parentId, ownDoc) });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

module.exports = {
  getComexRate,
  setComexRate,
  getClientComexRate: getAccountRate('client'),
  setClientComexRate: setAccountRate('client'),
  clearClientComexRate: clearAccountRate('client'),
  getMasterComexRate: getAccountRate('master'),
  setMasterComexRate: setAccountRate('master'),
  clearMasterComexRate: clearAccountRate('master'),
};
