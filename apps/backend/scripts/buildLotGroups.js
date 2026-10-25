#!/usr/bin/env node
'use strict';

/**
 * NSE-style lot groups for every segment (26 Oct 2026, the user's choice):
 * the same group names as NSE — 1, 2, 4, 6, 7, 8, 9, 10 LOT NEW, HRY 3 LOT,
 * HRY 5 LOT — with the same position / per-order lot counts, copied from the
 * existing NFO-OPT groups (lot counts there; NIFTY row as the reference).
 *
 *  - MCX-OPT, COMEX-FUT (lot mode): rows store lot counts, like NFO-OPT /
 *    MCX-FUT.
 *  - INDICES = GLOBAL (quantity mode): rows store quantity = lots × the
 *    segment's "1 lot" per script = HRY 5 LOT ÷ 5 (Dow 30, GIFT NIFTY 50,
 *    Nasdaq 70, Nikkei 35, S&P 250) and Russell 2000 = 50 (its contract).
 *
 * Also fills the gaps the audit found (missing row = NO limit):
 *  - NFO-OPT GOLDMIN: missing stocks at GOLDMIN's options value 5 / 2 lots,
 *    for the group and every client assigned GOLDMIN on NFO-OPT;
 *  - INDICES HRY 5 LOT: Russell 2000 at 5 lots (250 / 150) for the group and
 *    its clients.
 *
 * Only INSERTS rows that do not exist yet — never edits or deletes. New groups
 * touch no client until a client is assigned one (the group then re-seeds that
 * client's limits, as for any group). Dry run by default; --apply writes and
 * saves the new row ids to ~/backups/lot-groups-<ts>.json (undo = delete them).
 *
 *   node scripts/buildLotGroups.js            # dry run
 *   node scripts/buildLotGroups.js --apply
 */

const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const mongoose = require('mongoose');

const APPLY = process.argv.includes('--apply');
const GROUPS = ['1 LOT NEW', '2 LOT NEW', 'HRY 3 LOT', '4 LOT NEW', 'HRY 5 LOT', '6 LOT NEW', '7 LOT NEW', '8 LOT NEW', '9 LOT NEW', '10 LOT NEW'];
const LOT_SEGMENTS = ['MCX-OPT', 'COMEX-FUT'];
const GLOBAL_UNIT = { 'Dow Jones 30': 30, 'GIFT NIFTY': 50, 'Nasdaq 100': 70, 'Nikkei 225': 35, 'S&P 500': 250, 'Russell 2000': 50 };

async function main() {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const GQ = db.collection('groupedquantities');
  const SQ = db.collection('scriptquantities');
  const KI = db.collection('kiteinstruments');
  const now = new Date();
  const created = { group: [], client: [] };
  const report = [];

  // Reference lot counts per group, from the NFO-OPT groups (NIFTY row).
  const ref = {};
  for (const g of GROUPS) {
    const r = await GQ.findOne({ exchange_name: 'NFO-OPT', lot_name: g, raw_name: 'NIFTY', deleted_at: null });
    if (!r) throw new Error(`reference NFO-OPT ${g} NIFTY row missing`);
    ref[g] = { max: r.max_qty, brk: r.break_qty };
  }
  report.push('Lot counts (position / per order): ' + GROUPS.map((g) => `${g} ${ref[g].max}/${ref[g].brk}`).join(', '));

  // Tradable names + contract lot per segment.
  const contract = async (match) => {
    const rows = await KI.aggregate([{ $match: { ...match, is_active: true } }, { $group: { _id: { $ifNull: ['$raw_name', '$name'] }, lot: { $first: '$lot_size' } } }]).toArray();
    return Object.fromEntries(rows.map((r) => [String(r._id), r.lot || 1]));
  };
  const names = {
    'MCX-OPT': await contract({ segment: 'MCX-OPT' }),
    'COMEX-FUT': await contract({ segment: 'COMEX-FUT' }),
    INDICES: Object.fromEntries(Object.entries(await contract({ segment: { $in: ['GLOBAL', 'INDICES'] } })).filter(([n]) => GLOBAL_UNIT[n])),
  };

  const insertGroupRow = async (seg, group, raw, lotSize, max, brk) => {
    if (await GQ.findOne({ exchange_name: seg, lot_name: group, raw_name: raw, deleted_at: null })) return false;
    const tpl = await GQ.findOne({ exchange_name: seg, deleted_at: null });
    const { _id, ...rest } = tpl || {};
    const doc = { ...rest, exchange_name: seg, lot_name: group, raw_name: raw, instrument_symbol: raw, instrument_id: '', lot_size: lotSize, max_qty: max, break_qty: brk, created_at: now, updated_at: now, deleted_at: null };
    if (APPLY) created.group.push({ _id: (await GQ.insertOne(doc)).insertedId, seg, group, raw });
    return true;
  };

  // 1) Build the lot groups.
  for (const seg of [...LOT_SEGMENTS, 'INDICES']) {
    let added = 0, had = 0;
    for (const g of GROUPS) {
      for (const [raw, lot] of Object.entries(names[seg])) {
        const unit = seg === 'INDICES' ? GLOBAL_UNIT[raw] : 1;
        (await insertGroupRow(seg, g, raw, lot, ref[g].max * unit, ref[g].brk * unit)) ? added++ : had++;
      }
    }
    report.push(`${seg}: ${Object.keys(names[seg]).length} scripts × ${GROUPS.length} groups → ${added} rows to add, ${had} already exist`);
  }
  report.push('GLOBAL examples (qty): ' + Object.keys(names.INDICES).map((n) => `${n} 1 LOT ${GLOBAL_UNIT[n]}, 10 LOT ${GLOBAL_UNIT[n] * 10}/${GLOBAL_UNIT[n] * 5}`).join('; '));

  // 2) Gap fill for clients of a group: add a row where the client has none.
  const fillClients = async (seg, group, raw, lotSize, max, brk) => {
    const users = await db.collection('users').find({ deleted_at: null, exchanges_allowed: { $elemMatch: { exchange_name: seg, group_name: group } } }).project({ _id: 1, username: 1 }).toArray();
    let added = 0;
    for (const u of users) {
      if (await SQ.findOne({ owner_id: u._id, exchange_name: seg, script_name: raw, deleted_at: null })) continue;
      const tpl = await SQ.findOne({ owner_id: u._id, exchange_name: seg, deleted_at: null });
      if (!tpl) continue;
      const { _id, ...rest } = tpl;
      const doc = { ...rest, script_name: raw, lot_size: lotSize, max_qty: max, brk_qty: brk, created_at: now, updated_at: now };
      if ('createdAt' in tpl) doc.createdAt = now;
      if ('updatedAt' in tpl) doc.updatedAt = now;
      if (APPLY) created.client.push({ _id: (await SQ.insertOne(doc)).insertedId, username: u.username, seg, raw });
      added++;
    }
    return { clients: users.length, added };
  };

  // NFO-OPT GOLDMIN: every tradable option underlying missing from the group, at 5 / 2 lots.
  const optNames = await contract({ segment: 'NFO-OPT' });
  const goldOpt = new Set((await GQ.find({ exchange_name: 'NFO-OPT', lot_name: 'GOLDMIN', deleted_at: null }).project({ raw_name: 1 }).toArray()).map((r) => r.raw_name));
  const optMissing = Object.keys(optNames).filter((n) => !goldOpt.has(n));
  let optRows = 0, optClients = 0;
  for (const raw of optMissing) {
    await insertGroupRow('NFO-OPT', 'GOLDMIN', raw, optNames[raw], 5, 2);
    const r = await fillClients('NFO-OPT', 'GOLDMIN', raw, optNames[raw], 5, 2);
    optRows += r.added; optClients = r.clients;
  }
  report.push(`NFO-OPT GOLDMIN gap: ${optMissing.join(', ') || 'none'} at 5/2 lots → group rows ${optMissing.length}, client rows ${optRows} (${optClients} clients on the group)`);

  // INDICES HRY 5 LOT: Russell 2000 at 5 lots = 250 / 150.
  const rus = names.INDICES['Russell 2000'];
  if (rus) {
    const hadGroup = !(await insertGroupRow('INDICES', 'HRY 5 LOT', 'Russell 2000', rus, 5 * 50, 3 * 50));
    const r = await fillClients('INDICES', 'HRY 5 LOT', 'Russell 2000', rus, 250, 150);
    report.push(`INDICES HRY 5 LOT gap: Russell 2000 250/150 → group row ${hadGroup ? 'already there' : 'added'}, client rows ${r.added} (${r.clients} clients)`);
  }

  console.log((APPLY ? 'APPLIED' : 'DRY RUN — nothing written') + '\n' + report.map((l) => ' - ' + l).join('\n'));
  if (APPLY) {
    const file = path.join(process.env.HOME || '.', 'backups', `lot-groups-${Date.now()}.json`);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(created));
    console.log(`group rows inserted: ${created.group.length}, client rows inserted: ${created.client.length}\nundo file: ${file}`);
  }
  await mongoose.disconnect();
}

main().catch((e) => { console.error(e.message); process.exit(1); });
