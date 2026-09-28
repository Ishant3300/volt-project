'use strict';

/**
 * One-time: create the NEW script-quantity group "INDEX ONLY" (no existing
 * group is touched) for NFO-FUT and NFO-OPT:
 *  - NIFTY and BANKNIFTY: same max/brk as GOLDMIN's rows;
 *  - every other NFO script: max 0 / brk 0 = not tradable (tradeController's
 *    limit check blocks opening/adding on a 0; closing is always allowed).
 * The script universe is every live NFO-FUT/NFO-OPT underlying (active Kite
 * instruments) plus every name any existing group has for those exchanges,
 * so nothing is left without a row (a script with no row is unlimited).
 * Dry run by default; --apply inserts.
 *   node scripts/createIndexOnlyGroup.js [--apply]
 */
require('dotenv').config();
const mongoose = require('mongoose');

const APPLY = process.argv.includes('--apply');
const GROUP = 'INDEX ONLY';
const TEMPLATE = 'GOLDMIN';
const EXCHANGES = ['NFO-FUT', 'NFO-OPT'];
const ALLOWED = ['NIFTY', 'BANKNIFTY'];

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const G = db.collection('groupedquantities');
  const K = db.collection('kiteinstruments');
  console.log(`mode: ${APPLY ? 'APPLY' : 'DRY RUN'} — group "${GROUP}"`);

  if (await G.findOne({ lot_name: GROUP, deleted_at: null })) {
    throw new Error(`Group "${GROUP}" already exists — not touching it.`);
  }

  const now = new Date();
  const docs = [];
  for (const ex of EXCHANGES) {
    const template = new Map((await G.find({ exchange_name: ex, lot_name: TEMPLATE, deleted_at: null }).toArray()).map((r) => [r.raw_name, r]));
    const groupNames = await G.distinct('raw_name', { exchange_name: ex, deleted_at: null });
    const liveInst = await K.aggregate([
      { $match: { segment: ex, is_active: true, deleted_at: null } },
      { $group: { _id: { $ifNull: ['$raw_name', '$name'] }, lot_size: { $first: '$lot_size' } } },
    ]).toArray();
    const lotOf = new Map(liveInst.map((i) => [i._id, i.lot_size]));
    const names = [...new Set([...groupNames, ...liveInst.map((i) => i._id)].filter(Boolean))].sort();

    for (const name of names) {
      const t = template.get(name);
      const allowed = ALLOWED.includes(name);
      if (allowed && !t) throw new Error(`${TEMPLATE} has no ${ex} row for ${name}`);
      docs.push({
        exchange_name: ex,
        lot_name: GROUP,
        raw_name: name,
        instrument_id: t?.instrument_id || '',
        instrument_symbol: t?.instrument_symbol || name,
        max_qty: allowed ? t.max_qty : 0,
        break_qty: allowed ? t.break_qty : 0,
        lot_size: t?.lot_size || lotOf.get(name) || 1,
        created_at: now,
        updated_at: now,
        deleted_at: null,
      });
    }
    const open = docs.filter((d) => d.exchange_name === ex && d.max_qty > 0);
    console.log(`${ex}: ${names.length} scripts (${groupNames.length} from groups, ${liveInst.length} live underlyings); tradable: ${open.map((d) => `${d.raw_name} max ${d.max_qty} brk ${d.break_qty}`).join(', ')}; every other = 0`);
  }

  if (!APPLY) { console.log(`\nDry run only — would insert ${docs.length} rows.`); await mongoose.disconnect(); process.exit(0); }
  const r = await G.insertMany(docs);
  console.log(`inserted ${r.insertedCount} rows for "${GROUP}"`);
  await mongoose.disconnect();
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
