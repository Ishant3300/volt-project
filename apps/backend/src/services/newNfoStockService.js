/**
 * New NFO stock listings — set up and made tradable automatically.
 *
 * The daily instrument sync (scripts/fetchInstruments.js) only imports names
 * on a hand-kept list, so a stock NSE adds to F&O (ANANDRATHI, Oct 2026)
 * never appeared. This finds NFO underlyings in Kite's dump that we don't
 * carry yet and, for STOCKS only (an NSE equity with the same symbol exists),
 * creates every setting the stock needs before it is imported:
 *
 *  - quantity limits — every quantity group (GroupedQuantity) and every
 *    account (ScriptQuantity) that already has limits in that segment gets the
 *    value its group's rule gives: futures groups are N lots x Kite's lot size
 *    (learned from the stocks already in the group), options groups store the
 *    same lot counts on every stock, GOLDMIN futures = 1 lot / 1 lot. An
 *    account not following a group gets its own fixed value if it has one on
 *    (nearly) every stock, else 0 (not tradable) and is reported.
 *  - brokerage — every account (and the global default) with brokerage rows
 *    in that segment gets the rate it charges on most of its stocks.
 *  - Fresh Stop-Loss — one 10-minute row per segment.
 *
 * Only missing rows are inserted; nothing existing is changed. The stock is
 * imported (made tradable) only if every row is in place afterwards.
 * New index contracts (no NSE equity) are reported, never added.
 */

const INDEX_NAMES = /^(NIFTY|BANKNIFTY|FINNIFTY|MIDCPNIFTY|NIFTYNXT50|NIFTYFPI|SENSEX|SENSEX50|BANKEX)$/;
const SEGMENTS = ['NFO-FUT', 'NFO-OPT'];
// Groups not set up in lots, with the value chosen for new stocks (14 Oct 2026).
const GROUP_OVERRIDES = { 'NFO-FUT|GOLDMIN': { unit: 'lots', max: 1, brk: 1 } };
const FSL_MINUTES = 10;

function tally(values) {
  const m = new Map();
  for (const v of values) m.set(v, (m.get(v) || 0) + 1);
  return [...m.entries()].sort((a, b) => b[1] - a[1]);
}

function splitCsvLine(line) {
  return line.split(',').map((v) => v.trim().replace(/^"(.*)"$/, '$1'));
}

/**
 * NFO underlyings in Kite's instrument dump that are not in `knownNames`.
 * @returns {{ stocks: Array<{name, lot, lots:number[], fut:number, opt:number}>, others: Array<{name, fut, opt}> }}
 */
function findNewNfoNames(kiteCsv, knownNames) {
  const lines = kiteCsv.trim().split('\n');
  const h = splitCsvLine(lines[0]);
  const col = (k) => h.indexOf(k);
  const iName = col('name'); const iSym = col('tradingsymbol'); const iLot = col('lot_size');
  const iType = col('instrument_type'); const iSeg = col('segment'); const iEx = col('exchange');
  const nse = new Set();
  const nfo = new Map();
  for (let i = 1; i < lines.length; i++) {
    const v = splitCsvLine(lines[i]);
    if (v[iEx] === 'NSE' && v[iType] === 'EQ') { nse.add(v[iSym].toUpperCase()); continue; }
    if (v[iEx] !== 'NFO' || !SEGMENTS.includes(v[iSeg])) continue;
    const name = (v[iName] || '').toUpperCase();
    if (!name || knownNames.has(name)) continue;
    const n = nfo.get(name) || { name, lots: new Set(), fut: 0, opt: 0 };
    if (v[iSeg] === 'NFO-FUT') { n.fut++; n.lots.add(parseInt(v[iLot], 10)); } else n.opt++;
    nfo.set(name, n);
  }
  const stocks = []; const others = [];
  for (const n of nfo.values()) {
    const lots = [...n.lots].filter((x) => x > 0);
    if (nse.has(n.name) && !INDEX_NAMES.test(n.name) && n.fut > 0) stocks.push({ name: n.name, lot: lots[0], lots, fut: n.fut, opt: n.opt });
    else others.push({ name: n.name, fut: n.fut, opt: n.opt });
  }
  return { stocks, others };
}

/** Each quantity group's rule, learned from the stocks already in it. */
async function groupRules(db) {
  const lotOf = new Map((await db.collection('kiteinstruments')
    .find({ segment: 'NFO-FUT', is_active: true, deleted_at: null }).project({ raw_name: 1, lot_size: 1 }).toArray())
    .map((k) => [k.raw_name, k.lot_size]));
  const G = await db.collection('groupedquantities').find({ exchange_name: { $in: SEGMENTS }, deleted_at: null }).toArray();
  const rules = new Map();
  for (const key of new Set(G.map((g) => `${g.exchange_name}|${g.lot_name}`))) {
    if (GROUP_OVERRIDES[key]) { rules.set(key, { ...GROUP_OVERRIDES[key], basis: 'set by admin' }); continue; }
    const [seg, grp] = key.split('|');
    const rs = G.filter((g) => g.exchange_name === seg && g.lot_name === grp && !INDEX_NAMES.test(g.raw_name) && lotOf.get(g.raw_name));
    if (rs.length === 0) continue;
    const [[asLots, nLots]] = tally(rs.map((r) => `${+(r.max_qty / lotOf.get(r.raw_name)).toFixed(2)}/${+(r.break_qty / lotOf.get(r.raw_name)).toFixed(2)}`));
    const [[raw, nRaw]] = tally(rs.map((r) => `${r.max_qty}/${r.break_qty}`));
    const useLots = nLots >= nRaw;
    const share = Math.max(nLots, nRaw) / rs.length;
    const [max, brk] = (useLots ? asLots : raw).split('/').map(Number);
    // A group with no clear pattern (an admin-tuned one like GOLDMIN futures)
    // needs an explicit GROUP_OVERRIDES entry; until then nothing is guessed.
    if (share < 0.9) { rules.set(key, { unclear: true, basis: `${Math.max(nLots, nRaw)} of ${rs.length} stocks agree` }); continue; }
    rules.set(key, { unit: useLots ? 'lots' : 'fixed', max, brk, basis: `${Math.max(nLots, nRaw)} of ${rs.length} stocks` });
  }
  return { rules, groups: G };
}

function ruleValue(rule, lot) {
  if (!rule || rule.unclear) return null;
  return rule.unit === 'lots' ? { max: Math.round(rule.max * lot), brk: Math.round(rule.brk * lot) } : { max: rule.max, brk: rule.brk };
}

/**
 * Build every row the stocks need (nothing written).
 * @returns {{ rows: {group:[], qty:[], brk:[], fsl:[]}, problems: string[], summary: object }}
 */
async function planNewNfoStocks(db, stocks, now = new Date()) {
  const { rules, groups: G } = await groupRules(db);
  const problems = [];
  for (const [k, r] of rules) if (r.unclear) problems.push(`group ${k} has no clear lot rule (${r.basis}) — its accounts get 0 until one is set`);
  const gIdx = new Map(G.map((g) => [`${g.exchange_name}|${g.lot_name}|${g.raw_name}`, g]));

  const Q = await db.collection('scriptquantities').find({ exchange_name: { $in: SEGMENTS }, deleted_at: null }).toArray();
  const qBy = new Map();
  for (const r of Q) { const k = `${r.owner_id}|${r.exchange_name}`; if (!qBy.has(k)) qBy.set(k, { type: r.owner_type, rows: [] }); qBy.get(k).rows.push(r); }
  const users = new Map((await db.collection('users').find({}).project({ username: 1, deleted_at: 1, exchanges_allowed: 1 }).toArray()).map((u) => [String(u._id), u]));
  const masters = new Map((await db.collection('masters').find({}).project({ username: 1, deleted_at: 1, script_quantity_groups: 1 }).toArray()).map((m) => [String(m._id), m]));

  const matchShare = (rows, seg, grp) => {
    const stockRows = rows.filter((r) => !INDEX_NAMES.test(r.script_name));
    if (!stockRows.length) return 0;
    return stockRows.filter((r) => { const g = gIdx.get(`${seg}|${grp}|${r.script_name}`); return g && g.max_qty === r.max_qty && g.break_qty === r.brk_qty; }).length / stockRows.length;
  };
  const groupNames = (seg) => [...new Set(G.filter((g) => g.exchange_name === seg).map((g) => g.lot_name))];

  // Which rule each account with limits follows.
  const owners = [];
  const skipped = [];
  for (const [key, { type, rows }] of qBy) {
    const [id, seg] = key.split('|');
    if (!['User', 'Master', 'Admin'].includes(type)) { skipped.push(`${seg} ${id} (no account type)`); continue; }
    const acct = type === 'User' ? users.get(id) : type === 'Master' ? masters.get(id) : { username: `admin ${id}` };
    if (!acct || acct.deleted_at) continue;
    let picked = null;
    if (type === 'User') picked = (acct.exchanges_allowed || []).find((e) => String(e.exchange_name).toUpperCase() === seg)?.group_name || null;
    if (type === 'Master') picked = (acct.script_quantity_groups || []).find((e) => String(e.exchange_name).toUpperCase() === seg)?.group_name || null;
    let group = picked && rules.has(`${seg}|${picked}`) && matchShare(rows, seg, picked) >= 0.8 ? picked : null;
    let how = group ? 'group' : null;
    if (!group) {
      let best = null; let bestShare = 0;
      for (const g of groupNames(seg)) { const s = matchShare(rows, seg, g); if (s > bestShare) { best = g; bestShare = s; } }
      if (best && bestShare >= 0.8 && rules.has(`${seg}|${best}`)) { group = best; how = 'group (matched)'; }
    }
    let fixed = null;
    if (!group) {
      const stockRows = rows.filter((r) => !INDEX_NAMES.test(r.script_name));
      const [[v, n] = []] = tally(stockRows.map((r) => `${r.max_qty}/${r.brk_qty}`));
      if (v && n / stockRows.length >= 0.9) { const [max, brk] = v.split('/').map(Number); fixed = { max, brk }; how = 'own fixed value'; }
    }
    owners.push({ id, raw: rows[0].owner_id, seg, type, username: acct.username, group, fixed, how: how || 'none' });
  }
  const noRule = owners.filter((o) => (!o.group || rules.get(`${o.seg}|${o.group}`)?.unclear) && !o.fixed);
  if (noRule.length) problems.push(`${noRule.length} account(s) follow no group and have no fixed value — given 0 (not tradable): ${noRule.slice(0, 10).map((o) => `${o.seg} ${o.username}`).join(', ')}`);

  // Usual brokerage per account+segment (stocks only).
  const B = await db.collection('brokeragesettings').find({ exchange_name: { $in: SEGMENTS }, deleted_at: null }).toArray();
  const bBy = new Map();
  for (const r of B) { if (INDEX_NAMES.test(r.script_name)) continue; const k = `${r.user_id || 'GLOBAL'}|${r.exchange_name}`; if (!bBy.has(k)) bBy.set(k, []); bBy.get(k).push(r); }
  const usual = [];
  for (const [k, rs] of bBy) {
    const [id, seg] = k.split('|');
    if (id !== 'GLOBAL') { const a = users.get(id) || masters.get(id); if (a?.deleted_at) continue; }
    const [type, value] = tally(rs.map((r) => `${r.type}|${r.brk_value}`))[0][0].split('|');
    usual.push({ id, raw: rs[0].user_id || null, seg, type, value: Number(value) });
  }

  // Existing rows for the new names (only missing ones are planned).
  const names = stocks.map((s) => s.name);
  const has = new Set([
    ...(await db.collection('groupedquantities').find({ raw_name: { $in: names }, exchange_name: { $in: SEGMENTS }, deleted_at: null }).project({ exchange_name: 1, lot_name: 1, raw_name: 1 }).toArray()).map((r) => `G|${r.exchange_name}|${r.lot_name}|${r.raw_name}`),
    ...(await db.collection('scriptquantities').find({ script_name: { $in: names }, exchange_name: { $in: SEGMENTS }, deleted_at: null }).project({ owner_id: 1, exchange_name: 1, script_name: 1 }).toArray()).map((r) => `Q|${r.owner_id}|${r.exchange_name}|${r.script_name}`),
    ...(await db.collection('brokeragesettings').find({ script_name: { $in: names }, exchange_name: { $in: SEGMENTS }, deleted_at: null }).project({ user_id: 1, exchange_name: 1, script_name: 1 }).toArray()).map((r) => `B|${r.user_id || 'GLOBAL'}|${r.exchange_name}|${r.script_name}`),
    ...(await db.collection('freshstoplosslimits').find({ raw_name: { $in: names }, exchange_name: { $in: SEGMENTS }, deleted_at: null }).project({ exchange_name: 1, raw_name: 1 }).toArray()).map((r) => `F|${r.exchange_name}|${r.raw_name}`),
  ]);

  const rows = { group: [], qty: [], brk: [], fsl: [] };
  for (const s of stocks) {
    if (s.lots.length !== 1) { problems.push(`${s.name}: Kite lists several lot sizes (${s.lots.join(', ')}) — skipped`); continue; }
    for (const seg of SEGMENTS) {
      if (seg === 'NFO-OPT' && !s.opt) continue;
      for (const g of groupNames(seg)) {
        const v = ruleValue(rules.get(`${seg}|${g}`), s.lot) || { max: 0, brk: 0 };
        if (!has.has(`G|${seg}|${g}|${s.name}`)) rows.group.push({ exchange_name: seg, lot_name: g, raw_name: s.name, instrument_id: '', instrument_symbol: s.name, lot_size: s.lot, max_qty: v.max, break_qty: v.brk, created_at: now, updated_at: now, deleted_at: null, __v: 0 });
      }
      for (const o of owners.filter((x) => x.seg === seg)) {
        const v = (o.group && ruleValue(rules.get(`${seg}|${o.group}`), s.lot)) || o.fixed || { max: 0, brk: 0 };
        if (!has.has(`Q|${o.id}|${seg}|${s.name}`)) rows.qty.push({ owner_id: o.raw, owner_type: o.type, exchange_name: seg, script_name: s.name, lot_size: s.lot, max_qty: v.max, brk_qty: v.brk, created_at: now, updated_at: now, deleted_at: null, __v: 0, _who: o.username, _how: o.how, _group: o.group });
      }
      for (const b of usual.filter((x) => x.seg === seg)) {
        if (!has.has(`B|${b.id}|${seg}|${s.name}`)) rows.brk.push({ user_id: b.raw, type: b.type, exchange_name: seg, script_name: s.name, brk_value: b.value, created_at: now, updated_at: now, effective_from: now, deleted_at: null, __v: 0 });
      }
      if (!has.has(`F|${seg}|${s.name}`)) rows.fsl.push({ exchange_name: seg, raw_name: s.name, time_minutes: FSL_MINUTES, price_offset: 0, created_at: now, updated_at: now, deleted_at: null, __v: 0 });
    }
  }
  const summary = {
    rules: [...rules].map(([k, r]) => `${k}: ${r.unclear ? `unclear (${r.basis})` : `${r.max}/${r.brk} ${r.unit === 'lots' ? 'lots' : 'fixed'}`}`),
    accounts: tally(owners.map((o) => `${o.seg} ${o.type} ${o.how}`)),
    counts: { group: rows.group.length, qty: rows.qty.length, brk: rows.brk.length, fsl: rows.fsl.length },
    expected: { qtyOwners: owners.length, brkOwners: usual.length },
  };
  return { rows, problems, summary, owners, usual };
}

/** Insert the planned rows. Returns the inserted ids per collection (for undo). */
async function applyPlan(db, plan) {
  const strip = (r) => { const { _who, _how, _group, ...doc } = r; return doc; };
  const ids = {};
  const put = async (coll, docs) => {
    if (!docs.length) { ids[coll] = []; return; }
    const res = await db.collection(coll).insertMany(docs.map(strip), { ordered: true });
    ids[coll] = Object.values(res.insertedIds).map(String);
  };
  await put('groupedquantities', plan.rows.group);
  await put('scriptquantities', plan.rows.qty);
  await put('brokeragesettings', plan.rows.brk);
  await put('freshstoplosslimits', plan.rows.fsl);
  return ids;
}

/** After applying: is every account's row in place for each stock? Returns names ready to open. */
async function verifyStocks(db, stocks, plan) {
  const ready = []; const notReady = [];
  for (const s of stocks) {
    const missing = [];
    for (const seg of SEGMENTS) {
      if (seg === 'NFO-OPT' && !s.opt) continue;
      const q = await db.collection('scriptquantities').countDocuments({ exchange_name: seg, script_name: s.name, deleted_at: null });
      const b = await db.collection('brokeragesettings').countDocuments({ exchange_name: seg, script_name: s.name, deleted_at: null });
      const f = await db.collection('freshstoplosslimits').countDocuments({ exchange_name: seg, raw_name: s.name, deleted_at: null });
      const wantQ = plan.owners.filter((o) => o.seg === seg).length;
      const wantB = plan.usual.filter((u) => u.seg === seg).length;
      if (q < wantQ) missing.push(`${seg} limits ${q}/${wantQ}`);
      if (b < wantB) missing.push(`${seg} brokerage ${b}/${wantB}`);
      if (f < 1) missing.push(`${seg} fresh stop-loss`);
    }
    (missing.length ? notReady : ready).push(missing.length ? { name: s.name, missing } : s);
  }
  return { ready, notReady };
}

/*
 * Stocks added this way live in their own list (not the hand-kept
 * active_instruments CSV) and are imported for the NFO exchange only — the
 * big list matches on name across every exchange, which would also pull in
 * an NSE/BSE equity of the same name.
 */
const fs = require('fs');
const path = require('path');
const AUTO_LIST = path.join(__dirname, '../../scripts/required_scripts/auto_added_nfo.csv');

function loadAutoAdded(file = AUTO_LIST) {
  if (!fs.existsSync(file)) return new Set();
  return new Set(fs.readFileSync(file, 'utf8').split('\n').slice(1).map((l) => l.split(',')[0].trim().toUpperCase()).filter(Boolean));
}

function appendAutoAdded(stocks, how, file = AUTO_LIST, now = new Date()) {
  if (!fs.existsSync(file)) fs.writeFileSync(file, 'name,lot_size,added_at,added_by\n');
  const have = loadAutoAdded(file);
  const lines = stocks.filter((s) => !have.has(s.name)).map((s) => `${s.name},${s.lot},${now.toISOString()},${how}`);
  if (lines.length) fs.appendFileSync(file, `${lines.join('\n')}\n`);
  return lines.length;
}

/** Telegram message for a run (plain text). */
function describeRun({ ready = [], notReady = [], others = [], problems = [], counts }) {
  const out = [];
  if (ready.length) {
    out.push(`New F&O stocks added and tradable: ${ready.map((s) => `${s.name} (lot ${s.lot})`).join(', ')}.`);
    if (counts) out.push(`Set up: ${counts.qty} quantity limits, ${counts.group} group rows, ${counts.brk} brokerage rows, ${counts.fsl} Fresh Stop-Loss rows (only missing ones).`);
  }
  if (notReady.length) out.push(`NOT added (settings incomplete, stays hidden): ${notReady.map((s) => `${s.name} — ${s.missing.join('; ')}`).join(' | ')}`);
  if (others.length) out.push(`New on NFO, not a stock — NOT added, needs a decision: ${others.map((o) => o.name).join(', ')}.`);
  if (problems.length) out.push(`Notes: ${problems.join(' | ')}`);
  return out.join('\n');
}

module.exports = { loadAutoAdded, appendAutoAdded, describeRun, AUTO_LIST, findNewNfoNames, planNewNfoStocks, applyPlan, verifyStocks, groupRules, INDEX_NAMES, GROUP_OVERRIDES };
