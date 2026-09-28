'use strict';

/**
 * One-time: trade SENSEX (BSE) under NFO.
 *  1. Contracts: segment BFO-FUT -> NFO-FUT, BFO-OPT -> NFO-OPT (exchange stays BFO).
 *  2. Limits/brokerage: copy every NIFTY row under NFO-FUT / NFO-OPT to SENSEX
 *     (groups, each account's script quantity, every brokerage rate), where
 *     SENSEX has none yet. Futures quantities convert lot-for-lot (NIFTY qty /
 *     NIFTY lot * SENSEX lot); option limits (already in lots) and brokerage
 *     rates copy as they are.
 *  3. Open/closed per the NFO rules: futures — current month open, later
 *     months closed until the schedule opens them; options — current expiry
 *     open, next one too once its open day (1 working day before) arrived.
 * Dry run by default; --apply writes (after a JSON backup of what it changes).
 *   node scripts/migrateSensexToNfo.js [--apply]
 */
require('dotenv').config();
const fs = require('fs');
const mongoose = require('mongoose');

const APPLY = process.argv.includes('--apply');

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const K = db.collection('kiteinstruments');
  const G = db.collection('groupedquantities');
  const S = db.collection('scriptquantities');
  const B = db.collection('brokeragesettings');
  const { getHolidays } = require('../src/services/marketCalendarService');
  const { workingDaysBefore } = require('../src/services/expirySchedule');
  const { dateKey, toIndiaDateOnly } = require('../src/utils/settlementDates');
  const today = toIndiaDateOnly(new Date());
  const todayKey = dateKey(today);
  const holidays = await getHolidays('NSE', today.getUTCFullYear());

  // ── 1. contracts ──
  const bfo = await K.find({ exchange: 'BFO', segment: { $in: ['BFO-FUT', 'BFO-OPT'] }, deleted_at: null }).project({ instrument_token: 1, segment: 1, instrument_type: 1, name: 1, expiry: 1, enabled: 1, lot_size: 1, is_active: 1 }).toArray();
  const names = [...new Set(bfo.map((i) => i.name))];
  console.log(`mode: ${APPLY ? 'APPLY' : 'DRY RUN'}\n1) BFO contracts to move: ${bfo.length} (${bfo.filter((i) => i.segment === 'BFO-FUT').length} FUT, ${bfo.filter((i) => i.segment === 'BFO-OPT').length} OPT); underlyings: ${names.join(', ')}`);

  // lot sizes (live futures)
  const lotOf = async (name, segs) => {
    const i = await K.findOne({ name, segment: { $in: segs }, instrument_type: 'FUT', is_active: true, expiry: { $gte: today }, deleted_at: null }, { sort: { expiry: 1 } });
    return Number(i?.lot_size) || null;
  };
  const niftyLot = await lotOf('NIFTY', ['NFO-FUT']);
  const sensexLot = await lotOf('SENSEX', ['BFO-FUT', 'NFO-FUT']);
  if (!niftyLot || !sensexLot) throw new Error(`lot sizes missing (NIFTY ${niftyLot}, SENSEX ${sensexLot})`);
  const futQty = (v) => (Number(v) > 0 ? Math.max(1, Math.round(Number(v) / niftyLot)) * sensexLot : 0);
  console.log(`   lot sizes: NIFTY ${niftyLot}, SENSEX ${sensexLot} → futures limits convert lot-for-lot (e.g. NIFTY ${niftyLot * 3} = 3 lots → SENSEX ${sensexLot * 3})`);

  // ── 2. copies ──
  const plan = { groups: [], scriptQty: [], brokerage: [] };
  for (const seg of ['NFO-FUT', 'NFO-OPT']) {
    const isFut = seg === 'NFO-FUT';
    for (const g of await G.find({ exchange_name: seg, raw_name: 'NIFTY', deleted_at: null }).toArray()) {
      if (await G.findOne({ exchange_name: seg, lot_name: g.lot_name, raw_name: 'SENSEX', deleted_at: null })) continue;
      plan.groups.push({ ...g, _id: undefined, raw_name: 'SENSEX', instrument_symbol: 'SENSEX', instrument_id: '', lot_size: sensexLot,
        max_qty: isFut ? futQty(g.max_qty) : g.max_qty, break_qty: isFut ? futQty(g.break_qty) : g.break_qty, created_at: new Date(), updated_at: new Date() });
    }
    for (const s of await S.find({ exchange_name: seg, script_name: 'NIFTY', deleted_at: null }).toArray()) {
      if (await S.findOne({ owner_id: s.owner_id, owner_type: s.owner_type, exchange_name: seg, script_name: 'SENSEX', deleted_at: null })) continue;
      plan.scriptQty.push({ ...s, _id: undefined, script_name: 'SENSEX', lot_size: sensexLot,
        max_qty: isFut ? futQty(s.max_qty) : s.max_qty, brk_qty: isFut ? futQty(s.brk_qty) : s.brk_qty, created_at: new Date(), updated_at: new Date() });
    }
    for (const b of await B.find({ exchange_name: seg, script_name: 'NIFTY', deleted_at: null }).toArray()) {
      if (await B.findOne({ user_id: b.user_id ?? null, exchange_name: seg, script_name: 'SENSEX', type: b.type, deleted_at: null })) continue;
      plan.brokerage.push({ ...b, _id: undefined, script_name: 'SENSEX', createdAt: new Date(), updatedAt: new Date() });
    }
  }
  const strip = (arr) => arr.map(({ _id, ...rest }) => rest);
  console.log(`2) copies NIFTY → SENSEX: groups ${plan.groups.length}, account script-qty rows ${plan.scriptQty.length}, brokerage rates ${plan.brokerage.length}`);
  const sample = (a, f) => a.slice(0, 3).map(f).join(' | ');
  if (plan.groups.length) console.log('   e.g. groups:', sample(plan.groups, (g) => `${g.lot_name}/${g.exchange_name} max ${g.max_qty} brk ${g.break_qty}`));
  if (plan.brokerage.length) console.log('   e.g. brokerage:', sample(plan.brokerage, (b) => `${b.exchange_name} ${b.type} ${b.brk_value}${b.user_id ? '' : ' (global)'}`));

  // ── 3. open/closed ──
  const byType = (t) => bfo.filter((i) => (t === 'FUT' ? i.instrument_type === 'FUT' : ['CE', 'PE'].includes(i.instrument_type)) && i.is_active && dateKey(i.expiry) >= todayKey);
  const futExp = [...new Set(byType('FUT').map((i) => dateKey(i.expiry)))].sort();
  const optExp = [...new Set(byType('OPT').map((i) => dateKey(i.expiry)))].sort();
  const futOpen = futExp.slice(0, 1);
  const optOpen = optExp.slice(0, 1);
  if (optExp[1] && todayKey >= dateKey(workingDaysBefore(new Date(`${optExp[0]}T00:00:00Z`), 1, holidays))) optOpen.push(optExp[1]);
  const state = (t, openKeys) => byType(t).map((i) => ({ token: i.instrument_token, key: dateKey(i.expiry), enabled: i.enabled !== false, want: openKeys.includes(dateKey(i.expiry)) }));
  const changes = [...state('FUT', futOpen), ...state('OPT', optOpen)].filter((x) => x.enabled !== x.want);
  const summary = {};
  for (const c of changes) summary[`${c.key} → ${c.want ? 'OPEN' : 'CLOSE'}`] = (summary[`${c.key} → ${c.want ? 'OPEN' : 'CLOSE'}`] || 0) + 1;
  console.log(`3) open: futures ${futOpen.join(', ') || '-'}; options ${optOpen.join(' + ') || '-'}. Changes: ${JSON.stringify(summary)}`);

  if (!APPLY) { console.log('\nDry run only.'); await mongoose.disconnect(); process.exit(0); }

  const backupFile = `${process.env.HOME}/backups/sensex-to-nfo-${Date.now()}.json`;
  fs.mkdirSync(`${process.env.HOME}/backups`, { recursive: true });
  fs.writeFileSync(backupFile, JSON.stringify({ at: new Date(), contracts: bfo }));
  console.log(`\nbackup: ${backupFile}`);

  const r1 = await K.updateMany({ exchange: 'BFO', segment: 'BFO-FUT' }, { $set: { segment: 'NFO-FUT' } });
  const r2 = await K.updateMany({ exchange: 'BFO', segment: 'BFO-OPT' }, { $set: { segment: 'NFO-OPT' } });
  console.log(`1) moved: ${r1.modifiedCount} FUT, ${r2.modifiedCount} OPT`);
  if (plan.groups.length) await G.insertMany(strip(plan.groups));
  if (plan.scriptQty.length) await S.insertMany(strip(plan.scriptQty));
  if (plan.brokerage.length) await B.insertMany(strip(plan.brokerage));
  console.log(`2) inserted: groups ${plan.groups.length}, script-qty ${plan.scriptQty.length}, brokerage ${plan.brokerage.length}`);
  const now = new Date();
  const openTokens = changes.filter((c) => c.want).map((c) => c.token);
  const closeTokens = changes.filter((c) => !c.want).map((c) => c.token);
  if (openTokens.length) await K.updateMany({ instrument_token: { $in: openTokens } }, { $set: { enabled: true, ban_reason: null, banned_at: null } });
  if (closeTokens.length) await K.updateMany({ instrument_token: { $in: closeTokens } }, { $set: { enabled: false, ban_reason: 'Opens for trading per the NFO expiry schedule', banned_at: now } });
  console.log(`3) opened ${openTokens.length}, closed ${closeTokens.length}`);
  await mongoose.disconnect();
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
