'use strict';

/**
 * Master base profit book time (utils/profitBookTime.js, 25 Oct 2026).
 *   GET  /api/admin/profit-book-base/:masterId           { minutes, floor, username }
 *   GET  /api/admin/profit-book-base/:masterId/preview?minutes=N   { masters, clients } a raise would lift
 *   PUT  /api/admin/profit-book-base/:masterId  { minutes }  -> { minutes, lifted: { masters, clients } }
 * Admin: any master. A master: reads itself or its downline; sets only its own
 * sub-masters (never itself). The chain always holds: a base can't be below
 * the parent's base; raising one lifts the whole tree below it at once.
 */

const mongoose = require('mongoose');
const Master = require('../models/Master');
const { getAllSubMasterIds } = require('../services/masterHierarchyService');
const { parseProfitBookMinutes, baseOf, previewLift, liftTree } = require('../utils/profitBookTime');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/** The master + its parent's base, or an { status, message } refusal. */
async function load(req, { forWrite }) {
  const id = String(req.params.masterId || '');
  if (!mongoose.Types.ObjectId.isValid(id)) return { status: 400, message: 'Invalid master id' };
  if (req.master) {
    const own = await getAllSubMasterIds(String(req.master.id));
    const allowed = forWrite ? own.filter((x) => x !== String(req.master.id)) : own;
    if (!allowed.includes(id)) return { status: 403, message: forWrite ? 'You can only set the base of your own sub-masters' : 'Not authorized' };
  }
  const master = await Master.findOne({ _id: id, deleted_at: null }).select('username master_id profit_book_base_minutes').lean();
  if (!master) return { status: 404, message: 'Master not found' };
  const parent = master.master_id ? await Master.findById(master.master_id).select('username profit_book_base_minutes').lean() : null;
  return { master, parent, floor: parent ? baseOf(parent) : null };
}

const getProfitBookBase = async (req, res) => {
  try {
    const r = await load(req, { forWrite: false });
    if (r.status) return res.status(r.status).json({ success: false, message: r.message, data: null });
    res.json({ success: true, data: { minutes: baseOf(r.master), floor: r.floor, username: r.master.username, parent_username: r.parent?.username || null } });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
};

const previewProfitBookBase = async (req, res) => {
  try {
    const r = await load(req, { forWrite: false });
    if (r.status) return res.status(r.status).json({ success: false, message: r.message, data: null });
    const parsed = parseProfitBookMinutes(req.query.minutes, { label: 'Base profit book time' });
    if (parsed.error) return res.status(400).json({ success: false, message: parsed.error, data: null });
    res.json({ success: true, data: await previewLift(r.master._id, parsed.value) });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  }
};

const setProfitBookBase = async (req, res) => {
  const session = await mongoose.startSession();
  try {
    const r = await load(req, { forWrite: true });
    if (r.status) return res.status(r.status).json({ success: false, message: r.message, data: null });
    const parsed = parseProfitBookMinutes(req.body?.minutes, { min: r.floor, label: 'Base profit book time', minWhy: `base of ${r.parent?.username}` });
    if (parsed.error) return res.status(400).json({ success: false, message: parsed.error, data: null });
    const minutes = parsed.value;
    const before = baseOf(r.master);
    let lifted = { masters: 0, clients: 0 };
    await session.withTransaction(async () => {
      await Master.updateOne({ _id: r.master._id }, { $set: { profit_book_base_minutes: minutes } }, { session });
      lifted = await liftTree(r.master._id, minutes, session);
    });
    console.log(`⏱️  [ProfitBookBase] ${r.master.username}: ${before} -> ${minutes} min by ${req.admin ? 'admin' : 'master'} ${req.admin?.id || req.master?.id}; lifted ${lifted.masters} sub-master(s), ${lifted.clients} client(s)`);
    res.json({
      success: true,
      message: `Base profit book time set to ${minutes} min${lifted.masters || lifted.clients ? ` — raised ${lifted.clients} client(s) and ${lifted.masters} sub-master(s) to it` : ''}`,
      data: { minutes, previous: before, lifted },
    });
  } catch (e) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(e), data: null });
  } finally {
    await session.endSession();
  }
};

module.exports = { getProfitBookBase, previewProfitBookBase, setProfitBookBase };
