#!/usr/bin/env node
/**
 * Add named NFO stocks now, with the same rules the daily sync uses
 * (src/services/newNfoStockService.js). Reads the latest Kite dump in
 * scripts/downloads. Preview by default; --apply writes the rows, saves an
 * undo file in ~/backups, and adds the ready names to auto_added_nfo.csv so
 * the next sync (07:30) imports them.
 *
 *   node scripts/addNewNfoStocks.js ANANDRATHI RADICO            preview
 *   node scripts/addNewNfoStocks.js ANANDRATHI RADICO --apply    write
 */
require('dotenv').config();
const fs = require('fs');
const os = require('os');
const path = require('path');
const mongoose = require('mongoose');
const svc = require('../src/services/newNfoStockService');

(async () => {
  const args = process.argv.slice(2);
  const apply = args.includes('--apply');
  const want = args.filter((a) => !a.startsWith('--')).map((a) => a.toUpperCase());
  const dir = path.join(__dirname, 'downloads');
  const dump = fs.readdirSync(dir).filter((f) => /^raw_instruments_.*\.csv$/.test(f)).sort().pop();
  console.log(`Kite dump: ${dump}`);
  const csv = fs.readFileSync(path.join(dir, dump), 'utf8');

  const allowList = fs.readFileSync(path.join(__dirname, 'required_scripts', 'active_instruments (UPDATED).csv'), 'utf8').split('\n');
  const rawIdx = allowList[0].split(',').map((h) => h.trim()).indexOf('raw_name');
  const known = new Set([...allowList.slice(1).map((l) => (l.split(',')[rawIdx] || '').trim().toUpperCase()).filter(Boolean), ...svc.loadAutoAdded()]);
  const { stocks: all, others } = svc.findNewNfoNames(csv, known);
  const stocks = want.length ? all.filter((s) => want.includes(s.name)) : all;
  const unknown = want.filter((n) => !stocks.some((s) => s.name === n));
  if (unknown.length) console.log(`Not new NFO stocks in the dump (already listed, an index, or absent): ${unknown.join(', ')}`);
  if (!want.length) console.log(`New NFO stocks in the dump: ${all.map((s) => s.name).join(', ') || 'none'}; non-stock: ${others.map((o) => o.name).join(', ') || 'none'}`);
  if (!stocks.length) process.exit(0);

  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;
  const plan = await svc.planNewNfoStocks(db, stocks);
  console.log('\nGroup rules:'); for (const r of plan.summary.rules) console.log(`  ${r}`);
  console.log('\nAccounts with limits:'); for (const [k, n] of plan.summary.accounts) console.log(`  ${k}: ${n}`);
  console.log(`\nRows to insert: ${JSON.stringify(plan.summary.counts)}`);
  for (const p of plan.problems) console.log(`NOTE: ${p}`);
  for (const s of stocks) {
    const q = plan.rows.qty.filter((r) => r.script_name === s.name && r.exchange_name === 'NFO-FUT' && r.owner_type === 'User');
    const t = new Map(); for (const r of q) { const k = `${r._group || r._how} ${r.max_qty}/${r.brk_qty}`; t.set(k, (t.get(k) || 0) + 1); }
    console.log(`  ${s.name} lot ${s.lot} — FUT clients: ${[...t].sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} x${n}`).join(' | ')}`);
  }

  if (!apply) { console.log('\nPreview only. Add --apply to write.'); await mongoose.disconnect(); return; }

  const ids = await svc.applyPlan(db, plan);
  const undo = path.join(os.homedir(), 'backups', `new-nfo-${new Date().toISOString().replace(/[:.]/g, '-')}.json`);
  fs.mkdirSync(path.dirname(undo), { recursive: true });
  fs.writeFileSync(undo, JSON.stringify({ stocks, ids }, null, 1));
  console.log(`\nInserted: ${Object.entries(ids).map(([c, l]) => `${c} ${l.length}`).join(', ')}. Undo file: ${undo}`);
  const { ready, notReady } = await svc.verifyStocks(db, stocks.filter((s) => s.lots.length === 1), plan);
  const added = svc.appendAutoAdded(ready, 'manual (addNewNfoStocks)');
  console.log(`Ready: ${ready.map((s) => s.name).join(', ') || 'none'} (${added} added to ${path.basename(svc.AUTO_LIST)}); not ready: ${notReady.map((s) => `${s.name} [${s.missing.join('; ')}]`).join(', ') || 'none'}`);
  await mongoose.disconnect();
})().catch((e) => { console.error('ERR', e.stack); process.exit(1); });
