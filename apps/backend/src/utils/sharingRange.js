'use strict';

/**
 * Allowed P&L / brokerage sharing for a master (7 Nov 2026).
 *
 * Sharing is cumulative down a line (weeklyAdminController's ceiling model:
 * a master keeps its own % minus its sub-master's %). So a master's % must be
 *   at most its parent's %      — otherwise the parent's cut goes negative
 *   at least its highest direct sub-master's % — otherwise its own cut does.
 * A top-level master (no parent) can go up to 100. Creating a sub-master
 * already enforced "at most the parent"; editing enforced only 0–100.
 */
const Master = require('../models/Master');

const FIELDS = ['pnl_sharing', 'brokerage_sharing'];
const LABEL = { pnl_sharing: 'P&L sharing', brokerage_sharing: 'Brokerage sharing' };

/** { pnl_sharing: { min, max }, brokerage_sharing: { min, max }, parent, top_child } for a master doc. */
async function sharingRangeFor(master) {
  const parent = master.master_id
    ? await Master.findOne({ _id: master.master_id, deleted_at: null }).select('name username pnl_sharing brokerage_sharing').lean()
    : null;
  const children = await Master.find({ master_id: master._id, deleted_at: null }).select('name username pnl_sharing brokerage_sharing').lean();
  const out = { parent: parent ? { name: parent.name, username: parent.username } : null };
  for (const f of FIELDS) {
    const top = children.reduce((best, c) => ((Number(c[f]) || 0) > (best ? Number(best[f]) || 0 : -1) ? c : best), null);
    out[f] = {
      min: top ? Number(top[f]) || 0 : 0,
      max: parent ? Number(parent[f]) || 0 : 100,
      min_from: top ? `${top.name || top.username} (${Number(top[f]) || 0}%)` : null,
      max_from: parent ? `${parent.name || parent.username} (${Number(parent[f]) || 0}%)` : null,
    };
  }
  return out;
}

/**
 * Error message if `next` (the values being saved) breaks the range, else null.
 * Only fields that actually change are checked, so an old out-of-range value
 * never blocks an unrelated edit (name, password, limits…).
 */
async function sharingRangeError(master, next) {
  const changed = FIELDS.filter((f) => next[f] !== undefined && next[f] !== null && Number(next[f]) !== Number(master[f]));
  if (!changed.length) return null;
  const range = await sharingRangeFor(master);
  for (const f of changed) {
    const v = Number(next[f]);
    const { min, max, min_from: minFrom, max_from: maxFrom } = range[f];
    if (v > max) return `${LABEL[f]} cannot be more than ${max}% — the parent ${maxFrom} has ${max}%.`;
    if (v < min) return `${LABEL[f]} cannot be less than ${min}% — sub-master ${minFrom} has ${min}%. Lower that sub-master first.`;
  }
  return null;
}

module.exports = { sharingRangeFor, sharingRangeError };
