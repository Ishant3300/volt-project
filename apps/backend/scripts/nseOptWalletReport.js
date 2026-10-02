'use strict';

/**
 * READ-ONLY report for the NSE OPT wallet split (NSEOPT pool for NFO-OPT).
 *
 * For every client: the NSE wallet's available balance, the margin currently
 * held by open NSE futures and by open NSE option positions (flat-reset
 * average entry × |net qty| — exactly what a close would release, see
 * utils/walletSplit.js computeFlatResetState), and whether NFO-FUT / NFO-OPT
 * are ticked. For every master: its NSE pool and whether NFO-OPT is allowed.
 *
 * Nothing is written. No balance needs to move for correctness when NFO-OPT
 * switches to NSEOPT: option margin already left the NSE pool when it was
 * blocked, and is released into NSEOPT when the position closes. This list is
 * for deciding how much FREE NSE balance (if any) to move into NSE OPT.
 *
 *   node scripts/nseOptWalletReport.js [out.json]
 */
require('dotenv').config();
const fs = require('fs');
const mongoose = require('mongoose');
const { computeFlatResetState } = require('../src/utils/walletSplit');

const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const ticked = (row) => !!row && (row.turnover === true || row.lot === true);

(async () => {
  await mongoose.connect(process.env.MONGO_URI);
  const db = mongoose.connection.db;

  const futOpt = await db.collection('kiteinstruments')
    .find({ segment: { $in: ['NFO-FUT', 'NFO-OPT'] } })
    .project({ instrument_token: 1, segment: 1 }).toArray();
  const segOf = new Map(futOpt.map((i) => [String(i.instrument_token), i.segment]));

  const masters = await db.collection('masters').find({ deleted_at: null })
    .project({ name: 1, username: 1, master_id: 1, exchanges_allowed: 1, wallet: 1 }).toArray();
  const masterById = new Map(masters.map((m) => [String(m._id), m]));

  const users = await db.collection('users').find({ deleted_at: null })
    .project({ name: 1, username: 1, master_id: 1, exchanges_allowed: 1, wallet: 1 }).toArray();

  const trades = await db.collection('trades').find({
    status: 'completed', deleted_at: null,
    instrument_token: { $in: [...segOf.keys(), ...[...segOf.keys()].map(Number)] },
  }).project({ user_id: 1, instrument_token: 1, transaction_type: 1, executed_quantity: 1, executed_price: 1, executed_at: 1, createdAt: 1 })
    .sort({ executed_at: 1, createdAt: 1 }).toArray();

  // per user -> per token -> trades (chronological)
  const byUser = new Map();
  for (const t of trades) {
    const u = String(t.user_id);
    if (!byUser.has(u)) byUser.set(u, new Map());
    const m = byUser.get(u);
    const k = String(t.instrument_token);
    if (!m.has(k)) m.set(k, []);
    m.get(k).push(t);
  }

  const clients = [];
  for (const u of users) {
    const rows = u.exchanges_allowed || [];
    const futAllowed = ticked(rows.find((r) => r.exchange_name === 'NFO-FUT'));
    const optAllowed = ticked(rows.find((r) => r.exchange_name === 'NFO-OPT'));
    let futMargin = 0, optMargin = 0, futOpen = 0, optOpen = 0;
    for (const [token, list] of byUser.get(String(u._id)) || []) {
      const s = computeFlatResetState(list);
      if (Math.abs(s.netQty) < 1e-9) continue;
      const avg = s.netQty > 0
        ? (s.totalBuyQty > 0 ? s.totalBuyValue / s.totalBuyQty : 0)
        : (s.totalSellQty > 0 ? s.totalSellValue / s.totalSellQty : 0);
      const margin = Math.abs(s.netQty) * avg;
      if (segOf.get(token) === 'NFO-OPT') { optMargin += margin; optOpen += 1; } else { futMargin += margin; futOpen += 1; }
    }
    const nse = Number(u.wallet?.NSE) || 0;
    if (!futAllowed && !optAllowed && nse === 0 && optOpen === 0 && futOpen === 0) continue;
    const parent = masterById.get(String(u.master_id));
    clients.push({
      type: 'Client', username: u.username, name: u.name, parent: parent ? `${parent.name} (${parent.username})` : '',
      nfo_fut: futAllowed, nfo_opt: optAllowed,
      kind: optAllowed && !futAllowed ? 'OPTIONS ONLY' : optAllowed && futAllowed ? 'FUT + OPT' : futAllowed ? 'FUT ONLY' : 'NEITHER',
      nse_available: r2(nse), nseopt_existing: r2(u.wallet?.NSEOPT),
      fut_open: futOpen, fut_margin: r2(futMargin), opt_open: optOpen, opt_margin: r2(optMargin),
      nse_funded_total: r2(nse + futMargin + optMargin),
    });
  }

  const masterRows = masters
    .filter((m) => (m.exchanges_allowed || []).some((e) => e === 'NFO-OPT' || e === 'NFO-FUT') || (Number(m.wallet?.NSE) || 0) > 0)
    .map((m) => {
      const parent = m.master_id ? masterById.get(String(m.master_id)) : null;
      return {
        type: parent ? 'Sub-master' : 'Master', username: m.username, name: m.name, parent: parent ? `${parent.name} (${parent.username})` : 'ADMIN',
        nfo_fut: (m.exchanges_allowed || []).includes('NFO-FUT'), nfo_opt: (m.exchanges_allowed || []).includes('NFO-OPT'),
        nse_pool: r2(m.wallet?.NSE), nseopt_existing: r2(m.wallet?.NSEOPT),
      };
    });

  const out = { generated_at: new Date().toISOString(), clients, masters: masterRows };
  if (process.argv[2]) fs.writeFileSync(process.argv[2], JSON.stringify(out));
  const sum = (k) => r2(clients.reduce((s, c) => s + (c[k] || 0), 0));
  console.log(`clients ${clients.length} (options-only ${clients.filter((c) => c.kind === 'OPTIONS ONLY').length}, fut+opt ${clients.filter((c) => c.kind === 'FUT + OPT').length}, fut-only ${clients.filter((c) => c.kind === 'FUT ONLY').length}) | masters ${masterRows.length}`);
  console.log(`open option positions ${clients.reduce((s, c) => s + c.opt_open, 0)} holding margin ${sum('opt_margin')} | NSE available total ${sum('nse_available')}`);
  await mongoose.disconnect();
  process.exit(0);
})().catch((e) => { console.error('ERR', e.message); process.exit(1); });
