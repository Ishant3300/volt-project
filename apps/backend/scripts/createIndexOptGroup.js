'use strict';

/**
 * One-time: create the NEW script-quantity group "INDEX OPT" for NFO-OPT
 * only (no existing group is touched):
 *  - NIFTY, BANKNIFTY, SENSEX options: same max/brk as GOLDMIN's rows;
 *  - every other NFO-OPT underlying (FINNIFTY, MIDCPNIFTY, all stock
 *    options): max 0 / brk 0 = not tradable (tradeController's limit check).
 * Universe = every live NFO-OPT underlying + every name any group has for
 * NFO-OPT, so nothing is left without a row (no row = unlimited).
 * Dry run by default; --apply inserts.
 *   node scripts/createIndexOptGroup.js [--apply]
 */
require('dotenv').config();
const mongoose = require('mongoose');

const APPLY = process.argv.includes('--apply');
const GROUP = 'INDEX OPT';
const TEMPLATE = 'GOLDMIN';
const EX = 'NFO-OPT';
const ALLOWED = ['NIFTY', 'BANKNIFTY', 'SENSEX'];

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const G = db.collection('groupedquantities');
  const K = db.collection('kiteinstruments');
  console.log(`mode: ${APPLY ? 'APPLY' : 'DRY RUN'} — group "${GROUP}" (${EX})`);
  if (await G.findOne({ lot_name: GROUP, deleted_at: null })) throw new Error(`Group "${GROUP}" already exists — not touching it.`);

  const template = new Map((await G.find({ exchange_name: EX, lot_name: TEMPLATE, deleted_at: null }).toArray()).map((r) => [r.raw_name, r]));
  const groupNames = await G.distinct('raw_name', { exchange_name: EX, deleted_at: null });
  const liveInst = await K.aggregate([
    { $match: { segment: EX, is_active: true, deleted_at: null } },
    { $group: { _id: { $ifNull: ['$raw_name', '$name'] }, lot_size: { $first: '$lot_size' } } },
  ]).toArray();
  const lotOf = new Map(liveInst.map((i) => [i._id, i.lot_size]));
  const names = [...new Set([...groupNames, ...liveInst.map((i) => i._id)].filter(Boolean))].sort();
  const now = new Date();
  const docs = names.map((name) => {
    const t = template.get(name);
    const allowed = ALLOWED.includes(name);
    if (allowed && !t) throw new Error(`${TEMPLATE} has no ${EX} row for ${name}`);
    return {
      exchange_name: EX, lot_name: GROUP, raw_name: name,
      instrument_id: t?.instrument_id || '', instrument_symbol: t?.instrument_symbol || name,
      max_qty: allowed ? t.max_qty : 0, break_qty: allowed ? t.break_qty : 0,
      lot_size: t?.lot_size || lotOf.get(name) || 1,
      created_at: now, updated_at: now, deleted_at: null,
    };
  });
  const open = docs.filter((d) => d.max_qty > 0).map((d) => `${d.raw_name} max ${d.max_qty} brk ${d.break_qty}`);
  console.log(`${EX}: ${names.length} underlyings; tradable: ${open.join(', ')}; every other = 0`);
  if (!APPLY) { console.log(`\nDry run only — would insert ${docs.length} rows.`); await mongoose.disconnect(); process.exit(0); }
  const r = await G.insertMany(docs);
  console.log(`inserted ${r.insertedCount} rows for "${GROUP}"`);
  await mongoose.disconnect();
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
