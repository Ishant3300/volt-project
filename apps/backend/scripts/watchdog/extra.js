'use strict';

/**
 * Watchdog checks added after the first release (all read-only):
 *
 *   internal()  every 30 s — the backend's live state via /api/auth/internal-health:
 *               Kite feed silent / down in market hours, client loss and margin
 *               risk, pending orders whose price was crossed but didn't fill,
 *               event-loop lag; Kite login check before the open
 *   events()    every 5 s  — admin money actions (credit/debit, wallet assign/
 *               withdraw, adjustments), deleted trades, brokerage / script-limit
 *               changes, unusually large orders and order bursts
 *   slow()      every 30 s, each part on its own timer — account setting changes
 *               (close-only, status, exchanges, sharing, new/deleted accounts),
 *               expiry actions failed/overdue, weekly reset + ledger snapshot,
 *               SSL certificates, database size/connections, the evening
 *               collusion digest (same IPs, opposite/copy trades, scalping)
 *
 * Thresholds can be changed in .env: WATCHDOG_LOSS_PCT (default 50 = a client
 * has lost 50% of their credit this week), WATCHDOG_MARGIN_PCT (90),
 * WATCHDOG_BIG_ORDER (1000000 = ₹10 lakh), WATCHDOG_DB_LIMIT_GB (10).
 */
const http = require('http');
const path = require('path');
const tls = require('tls');
const { execFileSync } = require('child_process');

const num = (v, d) => (Number.isFinite(Number(v)) && Number(v) > 0 ? Number(v) : d);
const LOSS_PCT = () => num(process.env.WATCHDOG_LOSS_PCT, 50);
const MARGIN_PCT = () => num(process.env.WATCHDOG_MARGIN_PCT, 90);
const BIG_ORDER = () => num(process.env.WATCHDOG_BIG_ORDER, 1_000_000);
const DB_LIMIT_GB = () => num(process.env.WATCHDOG_DB_LIMIT_GB, 10);
const rupees = (n) => `₹${Math.round(Number(n) || 0).toLocaleString('en-IN')}`;
const SSL_HOSTS = ['apexlive-api.mynpe.in', 'www.volt.camp', 'apex-web-portal-demo.vercel.app'];

// ---------------------------------------------------------------- internal ----
function fetchInternal() {
  return new Promise((resolve, reject) => {
    if (!process.env.WATCHDOG_KEY) return resolve(null);
    const req = http.get({ host: '127.0.0.1', port: Number(process.env.PORT) || 3000, path: '/api/auth/internal-health', headers: { 'X-Watchdog-Key': process.env.WATCHDOG_KEY }, timeout: 10000 }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        try { resolve(res.statusCode === 200 ? JSON.parse(body).data : null); } catch (e) { reject(e); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('internal-health timeout')));
    req.on('error', reject);
  });
}

async function internal(c) {
  const { state, raise, clear, lib, who, MIN } = c;
  let h;
  try { h = await fetchInternal(); } catch (_) { return; } // backend down is reported elsewhere
  if (!h) return;
  const now = Date.now();
  const market = lib.inMarketHours(now);
  const open = market.nse || market.mcx;
  const p = lib.istParts(now);

  // Kite feed: connected but silent, or disconnected, during market hours.
  const silentFor = h.kite.last_tick_at ? Math.round((now - h.kite.last_tick_at) / 1000) : null;
  const afterOpenGrace = (market.nse && p.minutes >= 560) || (!market.nse && market.mcx && p.minutes >= 545);
  if (open && afterOpenGrace && !h.kite.connected) {
    raise('kite-down', 'critical', 'Kite price feed disconnected in market hours', ['Live prices are not updating; orders may be refused or fill at stale prices.'], { resolvable: true, maint: true });
  } else clear('kite-down');
  // Silent only counts once prices have flowed today — an exchange holiday has
  // a connected feed and no ticks all day.
  state.ticked = state.ticked || {};
  if (open && silentFor != null && silentFor < 30) state.ticked[p.ymd] = true;
  for (const k of Object.keys(state.ticked)) if (k < p.ymd) delete state.ticked[k];
  if (open && afterOpenGrace && h.kite.connected && silentFor != null && silentFor > 60 && state.ticked[p.ymd]) {
    raise('kite-silent', 'critical', 'No live prices from Kite', [`Connected, but no price update for ${silentFor} s in market hours.`], { resolvable: true, maint: true });
  } else if (silentFor != null && silentFor < 30) clear('kite-silent');
  if (open && p.minutes >= 570 && !state.ticked[p.ymd] && !state.digests[`noticks ${p.ymd}`]) {
    state.digests[`noticks ${p.ymd}`] = true;
    raise(`noticks:${p.ymd}`, 'warning', 'No prices since the open', ['Kite has sent no price at all today. If today is an exchange holiday, ignore this; otherwise check the feed.'], { cooldownMs: 24 * 60 * MIN });
  }

  // Kite login before the open (08:50-09:00 IST, trading days).
  if (p.day >= 1 && p.day <= 5 && p.minutes >= 530 && p.minutes < 540 && !state.digests[`kite-am ${p.ymd}`]) {
    state.digests[`kite-am ${p.ymd}`] = true;
    // Judged from the live feed: an accepted login keeps the Kite socket open
    // and messages (ticks or heartbeats) arriving; a rejected one closes it.
    const lastMsgS = h.kite.last_message_at ? Math.round((now - h.kite.last_message_at) / 1000) : null;
    if (!h.kite.connected || lastMsgS == null || lastMsgS > 60) {
      raise(`kite-am:${p.ymd}`, 'critical', 'Kite not ready before the open', [h.kite.connected ? `Connected, but nothing received from Kite for ${lastMsgS ?? '?'} s.` : 'Kite price feed not connected — the login may have failed; prices will not start at 09:00.'], { cooldownMs: 60 * MIN });
    }
  }

  if (h.event_loop_lag_ms > 500) raise('loop-lag', 'warning', 'Backend responding slowly', [`event loop delayed ${h.event_loop_lag_ms} ms`], { cooldownMs: 15 * MIN });

  // Client loss / margin risk (live M2M from memory). First run after a
  // restart only records who is already high (they were alerted before).
  const firstMargin = !state.marginHigh;
  state.marginHigh = state.marginHigh || {};
  for (const m of h.metrics || []) {
    if (!(m.credit > 0)) continue;
    const lossPct = m.m2m_pnl < 0 ? (-m.m2m_pnl / m.credit) * 100 : 0;
    if (lossPct >= 100) {
      raise(`loss100:${m.user_id}`, 'critical', 'Client loss exceeds their credit', [who(m.user_id), `M2M ${rupees(m.m2m_pnl)} on credit ${rupees(m.credit)} (${Math.round(lossPct)}%)`], { cooldownMs: 60 * MIN });
    } else if (lossPct >= LOSS_PCT()) {
      raise(`loss:${m.user_id}`, 'warning', 'Client big loss', [who(m.user_id), `M2M ${rupees(m.m2m_pnl)} = ${Math.round(lossPct)}% of credit ${rupees(m.credit)}`], { cooldownMs: 2 * 60 * MIN });
    }
    // Once when a client crosses the threshold; again only after dropping
    // below 80% and crossing again (many clients carry at 95%+ all week).
    const usedPct = m.margin_used > 0 ? (m.margin_used / (m.margin_used + Math.max(0, m.equity))) * 100 : 0;
    if (usedPct >= MARGIN_PCT() && m.open_positions > 0) {
      if (!state.marginHigh[m.user_id]) {
        state.marginHigh[m.user_id] = true;
        if (!firstMargin) raise(`margin:${m.user_id}:${now}`, 'warning', 'Client margin almost fully used', [who(m.user_id), `${Math.round(usedPct)}% of trade wallet blocked (margin ${rupees(m.margin_used)}, free ${rupees(m.equity)})`], { cooldownMs: 0 });
      }
    } else if (usedPct < 80) delete state.marginHigh[m.user_id];
  }

  // Pending orders already crossed but not filled (3 checks in a row ≈ 1.5 min).
  state.crossed = state.crossed || {};
  const seen = new Set();
  for (const o of h.pending_crossed || []) {
    seen.add(o.trade_id);
    state.crossed[o.trade_id] = (state.crossed[o.trade_id] || 0) + 1;
    if (state.crossed[o.trade_id] === 3) {
      raise(`stuck:${o.trade_id}`, 'warning', 'Pending order not filling', [who(o.user_id), `${o.symbol} ${o.side} ${o.order_type} @ ${o.price} — price is ${o.ltp} (crossed for 1.5+ min)`, 'Check the order book / price feed for this script.'], { cooldownMs: 6 * 60 * MIN });
    }
  }
  for (const id of Object.keys(state.crossed)) if (!seen.has(id)) delete state.crossed[id];
}

// ------------------------------------------------------------------ events ----
const MONEY_TYPES = ['CREDIT', 'DEBIT', 'WALLET_ASSIGN', 'WALLET_WITHDRAW', 'ADJUSTMENT', 'REFUND', 'TRANSFER', 'BONUS', 'DEPOSIT', 'WITHDRAWAL'];
const baselines = new Map(); // user -> { median, n, at }

async function baseline(d, userId) {
  const b = baselines.get(String(userId));
  if (b && Date.now() - b.at < 6 * 3600_000) return b;
  const rows = await d.collection('trades').find({ user_id: userId, status: 'completed', executed_at: { $gte: new Date(Date.now() - 30 * 864e5) } })
    .project({ executed_price: 1, executed_quantity: 1, quantity: 1 }).sort({ _id: -1 }).limit(300).toArray();
  const vals = rows.map((t) => (t.executed_price || 0) * (t.executed_quantity ?? t.quantity ?? 0)).filter((v) => v > 0).sort((a, b) => a - b);
  const nb = { median: vals.length ? vals[Math.floor(vals.length / 2)] : 0, n: vals.length, at: Date.now() };
  baselines.set(String(userId), nb);
  return nb;
}

function actorName(c, meta) {
  const a = meta && meta.actor;
  if (!a) return '';
  const id = String(a.id || '');
  if (a.type === 'Admin') return `admin ${c.names.admins.get(id)?.username || id.slice(-6)}`;
  if (a.type === 'Master') return `master ${c.names.masters.get(id)?.username || id.slice(-6)}`;
  return a.type || '';
}

async function events(c) {
  const { d, raise, send, lib, who, hit, newDocs, MIN } = c;

  // Money moved by admin / master.
  const tx = await newDocs(d, 'transactions', { type: { $in: MONEY_TYPES } }, { userId: 1, userModel: 1, type: 1, amount: 1, metadata: 1, description: 1 });
  if (tx.length) {
    const lines = tx.slice(0, 12).map((t) => {
      const m = t.metadata || {};
      const cat = m.category ? ` ${m.category}` : '';
      const by = actorName(c, m);
      const after = m.targetBalanceAfter != null ? ` (now ${rupees(m.targetBalanceAfter)})` : '';
      return `${t.type.replace('_', ' ')}${cat} ${rupees(t.amount)} → ${who(t.userId)}${after}${by ? ` · by ${by}` : ''}`;
    });
    if (tx.length > 12) lines.push(`…and ${tx.length - 12} more`);
    send(lib.formatAlert('info', `Money action${tx.length > 1 ? `s (${tx.length})` : ''}`, lines));
  }
  const ctx = await newDocs(d, 'credittransactions', {}, { master_id: 1, transaction_type: 1, amount: 1, note: 1, actor_model: 1 });
  if (ctx.length) {
    send(lib.formatAlert('info', `Master credit change${ctx.length > 1 ? `s (${ctx.length})` : ''}`, ctx.slice(0, 12).map((t) => `${t.transaction_type} ${rupees(t.amount)} → ${who(t.master_id)}${t.note ? ` · ${t.note}` : ''}`)));
  }

  // Trades deleted (not weekly-settlement archiving).
  const state = c.state;
  if (!state.last.delAt) state.last.delAt = new Date().toISOString();
  const del = await d.collection('trades').find({ deleted_at: { $gt: new Date(state.last.delAt) }, settlement_period_key: null })
    .project({ user_id: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, executed_price: 1, status: 1, deleted_at: 1, remarks: 1 }).sort({ deleted_at: 1 }).limit(200).toArray();
  if (del.length) {
    state.last.delAt = new Date(del[del.length - 1].deleted_at).toISOString();
    raise(`deleted:${state.last.delAt}`, 'warning', `Trade${del.length > 1 ? `s (${del.length})` : ''} deleted`, del.slice(0, 10).map((t) => `${who(t.user_id)} · ${t.tradingsymbol} ${t.transaction_type} ${t.quantity} @ ${t.executed_price || 0} (${t.status})`), { cooldownMs: 0 });
  }

  // Brokerage and script-limit edits (grouped per account).
  for (const [coll, field, ownerField, title] of [['brokeragesettings', 'updated_at', 'user_id', 'Brokerage changed'], ['scriptquantities', 'updated_at', 'owner_id', 'Script limits changed']]) {
    const k = `upd:${coll}`;
    if (!state.last[k]) { state.last[k] = new Date().toISOString(); continue; }
    const rows = await d.collection(coll).find({ [field]: { $gt: new Date(state.last[k]) } }).project({ [field]: 1, [ownerField]: 1, exchange_name: 1, deleted_at: 1 }).sort({ [field]: 1 }).limit(5000).toArray();
    if (!rows.length) continue;
    state.last[k] = new Date(rows[rows.length - 1][field]).toISOString();
    const per = new Map();
    for (const r of rows) {
      const owner = r[ownerField] ? String(r[ownerField]) : 'platform default';
      const e = per.get(owner) || { n: 0, segs: new Set(), del: 0 };
      e.n++;
      if (r.exchange_name) e.segs.add(r.exchange_name);
      if (r.deleted_at) e.del++;
      per.set(owner, e);
    }
    send(lib.formatAlert('info', title, [...per.entries()].slice(0, 10).map(([o, e]) => `${o === 'platform default' ? o : who(o)}: ${e.n} row${e.n > 1 ? 's' : ''}${e.del ? ` (${e.del} removed)` : ''} · ${[...e.segs].join(', ')}`)));
  }

  // Unusually large orders, and order bursts.
  for (const t of await newDocs(d, 'trades', { status: 'completed' }, { user_id: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, executed_quantity: 1, executed_price: 1, placed_by: 1, trade_type: 1 }, 'trades-filled')) {
    if (t.trade_type === 'carry_forward') continue;
    const notional = (t.executed_price || 0) * (t.executed_quantity ?? t.quantity ?? 0);
    if (notional >= BIG_ORDER()) {
      const b = await baseline(d, t.user_id);
      const unusual = notional >= 10 * BIG_ORDER() || (b.n >= 10 && notional >= 5 * b.median);
      if (unusual) {
        raise(`big:${t._id}`, 'warning', 'Unusually large order', [who(t.user_id), `${t.tradingsymbol} ${t.transaction_type} ${t.executed_quantity ?? t.quantity} @ ${t.executed_price} = ${rupees(notional)}`, b.n ? `usual size ~${rupees(b.median)} (${Math.round(notional / Math.max(1, b.median))}×)` : '', t.placed_by && t.placed_by !== 'USER' ? `placed by ${t.placed_by}` : ''], { cooldownMs: 0 });
      }
    }
    if (hit(`burst:${t.user_id}`, 60_000, t).length === 10) {
      raise(`burst:${t.user_id}`, 'warning', 'Order burst', [who(t.user_id), '10+ orders filled within 1 minute.'], { cooldownMs: 30 * MIN });
    }
  }
}

// -------------------------------------------------------------------- slow ----
const SETTING_FIELDS_USER = ['status', 'bet', 'close_only', 'margin_square_off', 'margin_square_off_percentage', 'fresh_stoploss', 'master_id', 'deleted_at'];
const SETTING_FIELDS_MASTER = ['status', 'pnl_sharing', 'brokerage_sharing', 'add_master', 'master_id', 'deleted_at'];
const show = (v) => (v == null ? '—' : v instanceof Date ? 'yes' : Array.isArray(v) ? v.join(',') : String(v));

async function settings(c) {
  const { d, state, send, lib, who } = c;
  const users = await d.collection('users').find({}).project(Object.fromEntries([...SETTING_FIELDS_USER, 'exchanges_allowed', 'username', 'name'].map((f) => [f, 1]))).toArray();
  const masters = await d.collection('masters').find({}).project(Object.fromEntries([...SETTING_FIELDS_MASTER, 'username', 'name'].map((f) => [f, 1]))).toArray();
  const snap = (doc, fields) => {
    const o = {};
    for (const f of fields) o[f] = doc[f] == null ? null : f === 'master_id' ? String(doc[f]) : f === 'deleted_at' ? true : doc[f];
    if (doc.exchanges_allowed) o.exchanges = doc.exchanges_allowed.map((e) => e.exchange_name).sort().join(',');
    return o;
  };
  const first = !state.settings;
  const prev = state.settings || { users: {}, masters: {} };
  const next = { users: {}, masters: {} };
  const lines = [];
  for (const [kind, list, fields] of [['users', users, SETTING_FIELDS_USER], ['masters', masters, SETTING_FIELDS_MASTER]]) {
    for (const doc of list) {
      const id = String(doc._id);
      const now = snap(doc, fields);
      next[kind][id] = now;
      if (first) continue;
      const before = prev[kind][id];
      const label = kind === 'users' ? who(id) : `master ${doc.username} ${doc.name || ''}`.trim();
      if (!before) { lines.push(`New ${kind === 'users' ? 'client' : 'master'}: ${label}`); continue; }
      const diffs = Object.keys(now).filter((f) => JSON.stringify(now[f]) !== JSON.stringify(before[f]))
        .map((f) => (f === 'master_id' ? `moved from ${who(before[f])} to ${who(now[f])}` : f === 'deleted_at' ? 'deleted' : `${f.replace(/_/g, ' ')} ${show(before[f])} → ${show(now[f])}`));
      if (diffs.length) lines.push(`${label}: ${diffs.join('; ')}`);
    }
  }
  state.settings = next;
  if (lines.length) send(lib.formatAlert('info', `Account settings changed (${lines.length})`, [...lines.slice(0, 15), lines.length > 15 ? `…and ${lines.length - 15} more` : '']));
}

async function expiry(c) {
  const { d, raise, MIN } = c;
  const failed = await d.collection('expiryactions').find({ status: 'failed', updatedAt: { $gte: new Date(Date.now() - 24 * 3600_000) } }).project({ exchange_label: 1, kind: 1, error: 1, execute_at: 1 }).toArray();
  for (const a of failed) raise(`exp-failed:${a._id}`, 'critical', 'Expiry action failed', [`${a.kind} ${a.exchange_label} (due ${new Date(a.execute_at).toISOString().slice(0, 16)}Z)`, a.error || ''], { cooldownMs: 24 * 60 * MIN });
  const overdue = await d.collection('expiryactions').find({ status: { $in: ['planned', 'confirmed'] }, execute_at: { $lt: new Date(Date.now() - 15 * MIN) } }).project({ exchange_label: 1, kind: 1, status: 1, execute_at: 1 }).toArray();
  for (const a of overdue) raise(`exp-overdue:${a._id}`, 'warning', 'Expiry action overdue', [`${a.kind} ${a.exchange_label} still ${a.status} (was due ${new Date(a.execute_at).toISOString().slice(0, 16)}Z)`, a.status === 'planned' ? 'It may need admin confirmation.' : ''], { cooldownMs: 6 * 60 * MIN });
}

async function weekly(c) {
  const { d, state, raise, lib, MIN } = c;
  const p = lib.istParts();
  if (p.day === 0 && p.minutes >= 20 && p.minutes < 60 && !state.digests[`reset ${p.ymd}`]) {
    state.digests[`reset ${p.ymd}`] = true;
    const off = await d.collection('users').countDocuments({ deleted_at: null, $expr: { $gt: [{ $abs: { $subtract: [{ $ifNull: ['$equity', 0] }, { $ifNull: ['$credits', 0] }] } }, 1] } });
    if (off > 0) raise(`reset:${p.ymd}`, 'warning', 'Weekly reset may not have run', [`${off} client(s) still have equity ≠ credit after Sunday 00:00.`], { cooldownMs: 24 * 60 * MIN });
  }
  if (p.day === 1 && p.minutes >= 20 && p.minutes < 60 && !state.digests[`ledger ${p.ymd}`]) {
    state.digests[`ledger ${p.ymd}`] = true;
    const n = await d.collection('ledgerentries').countDocuments({ created_at: { $gte: new Date(Date.now() - 3 * 3600_000) } });
    if (n === 0) raise(`ledger:${p.ymd}`, 'warning', 'Weekly ledger snapshot not written', ['No ledger entries from Sunday 23:55 — the weekly ledger may be missing.'], { cooldownMs: 24 * 60 * MIN });
  }
}

function certDaysLeft(host) {
  return new Promise((resolve) => {
    const s = tls.connect({ host, port: 443, servername: host, timeout: 10000 }, () => {
      const cert = s.getPeerCertificate();
      s.end();
      resolve(cert && cert.valid_to ? Math.floor((new Date(cert.valid_to) - Date.now()) / 864e5) : null);
    });
    s.on('error', () => resolve(null));
    s.on('timeout', () => { s.destroy(); resolve(null); });
  });
}

async function ssl(c) {
  const { raise, MIN } = c;
  for (const host of SSL_HOSTS) {
    const days = await certDaysLeft(host);
    if (days == null) continue;
    if (days < 3) raise(`ssl:${host}`, 'critical', 'SSL certificate about to expire', [`${host}: ${days} day(s) left — the site will show "not secure".`], { cooldownMs: 12 * 60 * MIN });
    else if (days < 14) raise(`ssl:${host}`, 'warning', 'SSL certificate expiring soon', [`${host}: ${days} days left`], { cooldownMs: 24 * 60 * MIN });
  }
}

async function dbLimits(c) {
  const { d, raise, clear } = c;
  const st = await d.stats();
  const usedGb = ((st.storageSize || 0) + (st.indexSize || 0)) / 1024 ** 3;
  const pct = (usedGb / DB_LIMIT_GB()) * 100;
  if (pct >= 70) raise('db-size', 'warning', 'Database storage filling up', [`${usedGb.toFixed(2)} GB of ${DB_LIMIT_GB()} GB (${Math.round(pct)}%)`], { resolvable: true });
  else if (pct < 65) clear('db-size');
  try {
    const ss = await d.admin().command({ serverStatus: 1 });
    const cur = ss.connections.current;
    const cpct = (cur / (cur + ss.connections.available)) * 100;
    if (cpct >= 70) raise('db-conn', 'warning', 'Database connections high', [`${cur} in use (${Math.round(cpct)}%)`], { resolvable: true });
    else if (cpct < 60) clear('db-conn');
  } catch (_) { /* not permitted on some tiers */ }
}

// Evening digest: same IPs, opposite / copy trades, scalping (today, IST).
async function collusion(c) {
  const { d, send, lib, who } = c;
  const p = lib.istParts();
  const dayStart = new Date(Date.parse(`${p.ymd}T00:00:00+05:30`));
  const trades = await d.collection('trades').find({ status: 'completed', executed_at: { $gte: dayStart }, trade_type: { $ne: 'carry_forward' } })
    .project({ user_id: 1, instrument_token: 1, tradingsymbol: 1, transaction_type: 1, executed_quantity: 1, quantity: 1, executed_price: 1, executed_at: 1, placed_by: 1, createdAt: 1 }).sort({ executed_at: 1 }).toArray();
  const own = trades.filter((t) => t.placed_by === 'USER' || t.placed_by === 'MASTER');
  const byTok = new Map();
  for (const t of own) { const k = t.instrument_token; if (!byTok.has(k)) byTok.set(k, []); byTok.get(k).push({ ...t, ts: new Date(t.executed_at).getTime(), q: t.executed_quantity ?? t.quantity }); }
  const opp = new Map();
  const copy = new Map();
  for (const list of byTok.values()) {
    for (let i = 0; i < list.length; i++) for (let j = i + 1; j < list.length; j++) {
      const a = list[i]; const b = list[j];
      if ((b.ts - a.ts) / 1000 > 120) break;
      if (String(a.user_id) === String(b.user_id)) continue;
      const k = [String(a.user_id), String(b.user_id)].sort().join('|');
      if (a.transaction_type !== b.transaction_type && Math.abs(a.q - b.q) <= 0.2 * Math.max(a.q, b.q)) opp.set(k, [...(opp.get(k) || []), a.tradingsymbol]);
      if (a.transaction_type === b.transaction_type && (b.ts - a.ts) / 1000 <= 30) copy.set(k, [...(copy.get(k) || []), a.tradingsymbol]);
    }
  }
  // Order IPs from today's nginx log, matched to orders by second.
  const ipAccts = new Map();
  try {
    const raw = execFileSync('sudo', ['-n', 'cat', '/var/log/nginx/access.log'], { timeout: 30000, maxBuffer: 64 * 1024 * 1024 }).toString();
    const posts = new Map();
    for (const line of raw.split('\n')) {
      const m = /^(\S+) \S+ \S+ \[([^\]]+)\] "POST \/api\/trade HTTP/.exec(line);
      if (!m) continue;
      const t = Date.parse(m[2].replace(/^(\d+)\/(\w+)\/(\d+):(\d+:\d+:\d+) /, '$2 $1 $3 $4 '));
      if (Number.isFinite(t)) { const s = Math.floor(t / 1000); posts.set(s, [...(posts.get(s) || []), m[1]]); }
    }
    for (const t of own) {
      if (t.placed_by !== 'USER') continue;
      const s = Math.floor(new Date(t.createdAt).getTime() / 1000);
      const ips = new Set([...(posts.get(s) || []), ...(posts.get(s + 1) || [])]);
      if (ips.size !== 1) continue;
      const ip = [...ips][0];
      ipAccts.set(ip, new Set([...(ipAccts.get(ip) || []), String(t.user_id)]));
    }
  } catch (_) { /* log not readable today */ }
  const sharedIp = [...ipAccts.entries()].filter(([, s]) => s.size >= 2);
  // Scalping: positions closed within 2 min.
  const quick = new Map();
  const perUserTok = new Map();
  for (const t of trades) { const k = `${t.user_id}|${t.instrument_token}`; if (!perUserTok.has(k)) perUserTok.set(k, []); perUserTok.get(k).push(t); }
  for (const [k, list] of perUserTok) {
    const lots = []; let side = 0;
    for (const t of list) {
      const sg = t.transaction_type === 'BUY' ? 1 : -1; let q = t.executed_quantity ?? t.quantity; const ts = new Date(t.executed_at).getTime();
      while (q > 0 && lots.length && side !== sg) { const lot = lots[0]; const m = Math.min(q, lot.q); if ((ts - lot.ts) / 1000 <= 120) quick.set(k.split('|')[0], (quick.get(k.split('|')[0]) || 0) + 1); lot.q -= m; q -= m; if (!lot.q) lots.shift(); }
      if (!lots.length) side = 0;
      if (q > 0) { side = sg; lots.push({ q, ts }); }
    }
  }
  const scalpers = [...quick.entries()].filter(([, n]) => n >= 5).sort((a, b) => b[1] - a[1]);
  const pairs = (m, min) => [...m.entries()].filter(([, v]) => v.length >= min).sort((a, b) => b[1].length - a[1].length).slice(0, 5)
    .map(([k, v]) => `${k.split('|').map(who).join(' ↔ ')} (${v.length}×: ${[...new Set(v)].slice(0, 3).join(', ')})`);
  const lines = [
    `Same order IP, 2+ clients: ${sharedIp.length ? '' : 'none'}`,
    ...sharedIp.slice(0, 5).map(([ip, s]) => `   ${ip}: ${[...s].map(who).join(', ')}`),
    `Opposite trades between clients (≤2 min): ${opp.size ? '' : 'none'}`,
    ...pairs(opp, 1).map((x) => `   ${x}`),
    `Copy trades (same side ≤30 s, 3+ times): ${pairs(copy, 3).length ? '' : 'none'}`,
    ...pairs(copy, 3).map((x) => `   ${x}`),
    `Scalping (5+ closes within 2 min): ${scalpers.length ? '' : 'none'}`,
    ...scalpers.slice(0, 5).map(([u, n]) => `   ${who(u)}: ${n}`),
    ...(() => {
      const st = (c.state.fillStats || {})[p.ymd];
      if (!st) return ['Fills vs exchange: not checked today'];
      const g = Object.entries(st.gain).sort((a, b) => b[1] - a[1]);
      return [`Fills better than the market: ${st.better} of ${st.checked} checked${g.length ? '' : ''}`, ...g.slice(0, 5).map(([u, v]) => `   ${who(u)}: ${rupees(v)}`)];
    })(),
  ];
  send(lib.formatAlert('info', `Collusion check ${p.ymd}`, lines));
}

// ------------------------------------------------------------ fill check ----
// Every client fill vs the exchange's own 1-minute candle (Kite historical, the
// same data as the terminal's Market Movement window). A fill outside the
// [low, high] of its minute and the minutes either side never traded on the
// exchange: "better than the market" (client gained) goes into the hourly
// report (fillReport); "worse" is counted. Checked ~2.5 min after the fill,
// once those candles are complete. GIFT NIFTY / global (not on Kite) skipped.
const APP = path.resolve(__dirname, '..', '..');
const KITE_EXCHANGES = ['NFO', 'MCX', 'NSE', 'BFO', 'BSE', 'CDS'];
const IST_MS = 5.5 * 3600_000;
const istStr = (ms) => new Date(ms + IST_MS).toISOString().replace('T', ' ').slice(0, 19);
let kiteSvc = null;
async function kite() {
  if (kiteSvc) return kiteSvc;
  const mongoose = require(path.join(APP, 'node_modules', 'mongoose'));
  if (mongoose.connection.readyState !== 1) await mongoose.connect(process.env.MONGO_URI, { maxPoolSize: 2 });
  kiteSvc = require(path.join(APP, 'src', 'services', 'kiteService')); // reads the stored Kite login itself
  return kiteSvc;
}

/**
 * A LIMIT/SL fill at the very edge of a fast-moving minute: the minute moved
 * more than SPIKE_MIN_PCT (0.5%) and the fill sits in the outer 10% of that
 * minute's range on the client's good side (buy near the low, sell near the
 * high). Returns { rangePct, edgePct, volShare } or null.
 */
const SPIKE_MIN_PCT = () => num(process.env.WATCHDOG_SPIKE_PCT, 0.5);
function spikeCatch(f, own) {
  if (!own || !['LIMIT', 'SL', 'SL-M'].includes(f.ot)) return null;
  const range = own.high - own.low;
  if (!(range > 0)) return null;
  const rangePct = (range / own.open) * 100;
  if (rangePct < SPIKE_MIN_PCT()) return null;
  const edge = f.side === 'BUY' ? (f.price - own.low) / range : (own.high - f.price) / range;
  if (edge > 0.1) return null;
  return { rangePct, edgePct: Math.max(0, edge) * 100 + 0.0001, volShare: own.volume > 0 ? (Number(f.qty) / own.volume) * 100 : null };
}

async function fillCheck(c) {
  const { d, state, raise, lib, who } = c;
  state.fillQueue = state.fillQueue || [];
  for (const t of await c.newDocs(d, 'trades', { status: 'completed', placed_by: { $in: ['USER', 'MASTER'] }, exchange: { $in: KITE_EXCHANGES }, trade_type: { $ne: 'carry_forward' } },
    { user_id: 1, instrument_token: 1, tradingsymbol: 1, transaction_type: 1, order_type: 1, executed_price: 1, executed_quantity: 1, quantity: 1, executed_at: 1 }, 'trades-fillcheck')) {
    if (!(t.executed_price > 0) || !t.executed_at) continue;
    state.fillQueue.push({ id: String(t._id), token: String(t.instrument_token), sym: t.tradingsymbol, side: t.transaction_type, ot: t.order_type, price: t.executed_price, qty: t.executed_quantity ?? t.quantity, at: new Date(t.executed_at).getTime(), user: String(t.user_id), tries: 0 });
  }
  if (state.fillQueue.length > 3000) state.fillQueue = state.fillQueue.slice(-3000);
  const now = Date.now();
  const ready = state.fillQueue.filter((f) => now - f.at >= 150_000);
  if (!ready.length) return;
  const groups = new Map();
  for (const f of ready) {
    const k = `${f.token}|${istStr(f.at).slice(0, 10)}`;
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(f);
  }
  const ks = await kite();
  const done = new Set();
  const p = lib.istParts();
  state.fillStats = state.fillStats || {};
  for (const k of Object.keys(state.fillStats)) if (k < p.ymd) delete state.fillStats[k];
  let calls = 0;
  for (const [, list] of groups) {
    if (calls >= 20) break; // the rest next minute (Kite allows 3 requests/s)
    const ts = list.map((f) => f.at);
    let candles = [];
    try {
      calls++;
      candles = (await ks.getHistoricalData(list[0].token, 'minute', `${istStr(Math.min(...ts) - 120_000).slice(0, 16)}:00`, `${istStr(Math.max(...ts) + 120_000).slice(0, 16)}:00`, { silent: true })) || [];
    } catch (_) { candles = []; }
    await new Promise((r) => setTimeout(r, 350));
    const byMin = new Map(candles.map((cd) => [String(cd.date).slice(0, 16), cd]));
    for (const f of list) {
      const key = (ms) => istStr(ms).slice(0, 16).replace(' ', 'T');
      const own = byMin.get(key(f.at));
      if (!own) {
        if (++f.tries >= 5) done.add(f.id); // no candle after ~5 min: give up on this one
        continue;
      }
      done.add(f.id);
      const cs = [byMin.get(key(f.at - 60_000)), own, byMin.get(key(f.at + 60_000))].filter(Boolean);
      const low = Math.min(...cs.map((x) => x.low));
      const high = Math.max(...cs.map((x) => x.high));
      const tol = Math.max(0.05, f.price * 0.0002);
      const day = istStr(f.at).slice(0, 10);
      const st = state.fillStats[day] || (state.fillStats[day] = { checked: 0, better: 0, worse: 0, gain: {} });
      const win = state.fillWindow || (state.fillWindow = { checked: 0, better: [], worse: 0 });
      st.checked++;
      win.checked++;
      if (f.price >= low - tol && f.price <= high + tol) {
        // Inside the range — but a LIMIT/SL filled at the very edge of a fast
        // minute "caught the spike": the exchange traded little there, we
        // filled the whole order.
        const spike = spikeCatch(f, own);
        if (spike) {
          st.spikes = (st.spikes || 0) + 1;
          win.spikes = win.spikes || [];
          if (win.spikes.length < 60) {
            win.spikes.push({ user: f.user, line: `${f.sym} ${f.side} ${f.qty} ${f.ot} @ ${f.price} at ${istStr(f.at).slice(11)} · minute ${own.low}–${own.high} (${spike.rangePct.toFixed(2)}% move), fill in the outer ${Math.round(spike.edgePct)}% · exchange volume ${own.volume}${spike.volShare != null ? ` (client qty = ${Math.round(spike.volShare)}% of it)` : ''}`,
              spike, fill: { id: f.id, token: f.token, sym: f.sym, side: f.side, qty: f.qty, ot: f.ot, price: f.price, at: f.at } });
          }
        }
        continue;
      }
      const better = (f.side === 'BUY' && f.price < low) || (f.side === 'SELL' && f.price > high);
      const gap = f.price < low ? low - f.price : f.price - high;
      if (!better) { st.worse++; win.worse++; continue; }
      st.better++;
      st.gain[f.user] = (st.gain[f.user] || 0) + gap * f.qty;
      if (win.better.length < 60) {
        win.better.push({ user: f.user, line: `${f.sym} ${f.side} ${f.qty} ${f.ot} @ ${f.price} at ${istStr(f.at).slice(11)} · exchange ${own.low}–${own.high} (±1 min ${low}–${high})`, value: gap * f.qty,
          fill: { id: f.id, token: f.token, sym: f.sym, side: f.side, qty: f.qty, ot: f.ot, price: f.price, at: f.at } });
      }
    }
  }
  state.fillQueue = state.fillQueue.filter((f) => !done.has(f.id));
}

// Hourly report of the fill check, trading days: 10:15, 11:15 … 23:15 (each
// covering the hour before) and 23:35 after MCX closes. Lists every fill
// better than the market with the client and ₹; counts the rest.
const FILL_REPORT_MINUTES = [...Array.from({ length: 14 }, (_, i) => 615 + i * 60), 1415];
async function fillReport(c) {
  const { state, lib, who, send } = c;
  const p = lib.istParts();
  if (p.day < 1 || p.day > 5) return;
  const due = FILL_REPORT_MINUTES.filter((m) => p.minutes >= m + 3 && !state.digests[`fillrep ${p.ymd} ${m}`]);
  if (!due.length) return;
  for (const m of due) state.digests[`fillrep ${p.ymd} ${m}`] = true;
  const m = due[due.length - 1];
  const hhmm = (x) => `${String(Math.floor(x / 60)).padStart(2, '0')}:${String(x % 60).padStart(2, '0')}`;
  const prevMark = [...FILL_REPORT_MINUTES].reverse().find((x) => x < m) ?? 555;
  const win = state.fillWindow || { checked: 0, better: [], worse: 0 };
  state.fillWindow = { checked: 0, better: [], worse: 0 };
  win.spikes = win.spikes || [];
  if (!win.checked && !win.better.length) return; // nothing traded on Kite exchanges this hour
  const total = win.better.reduce((s2, b) => s2 + b.value, 0);
  const lines = [
    `Checked ${win.checked} fill(s) against the exchange's 1-minute candles.`,
    win.better.length ? `Better than the market: ${win.better.length} — ${rupees(total)} in clients' favour` : '✅ No fill better than the market.',
    ...win.better.slice(0, 20).map((b) => `• ${who(b.user)} · ${b.line} · ${rupees(b.value)}`),
    win.better.length > 20 ? `…and ${win.better.length - 20} more` : '',
    win.worse ? `Worse than the market: ${win.worse} (normal for market orders in a thin minute)` : '',
    win.spikes.length ? `Caught a spike edge (LIMIT/SL filled at the extreme of a fast minute): ${win.spikes.length}` : '',
    ...win.spikes.slice(0, 15).map((b) => `• ${who(b.user)} · ${b.line}`),
  ];
  send(lib.formatAlert(win.better.length || win.spikes.length ? 'warning' : 'info', `Fill check ${hhmm(prevMark)}–${hhmm(m)}`, lines));
  // One forwardable image per flagged fill (max 10 per report): exchange minutes ±12 min + the trade.
  const withFill = [...win.better, ...win.spikes].filter((b) => b.fill).slice(0, 10);
  if (withFill.length) await sendFillImages(c, withFill);
}

async function sendFillImages(c, list) {
  const { who, lib } = c;
  const ks = await kite();
  const items = [];
  for (const b of list) {
    const f = b.fill;
    let candles = [];
    try { candles = (await ks.getHistoricalData(f.token, 'minute', `${istStr(f.at - 12 * 60_000).slice(0, 16)}:00`, `${istStr(f.at + 12 * 60_000).slice(0, 16)}:00`, { silent: true })) || []; } catch (_) { /* skip */ }
    await new Promise((r) => setTimeout(r, 350));
    if (!candles.length) continue;
    const u = c.names.users.get(String(b.user));
    items.push({ b, fill: { ...f, client: u ? `${u.username} ${u.name || ''}`.trim() : who(b.user), spike: b.spike || null }, candles });
  }
  if (!items.length) return;
  const { renderFillImages } = require('./fillImage');
  const pngs = await renderFillImages(items);
  pngs.forEach((png, i) => {
    const it = items[i];
    const tail = it.b.spike ? 'Filled at the extreme of a fast minute' : `${rupees(it.b.value)} better than any traded price`;
    c.sendPhoto(png, lib.escapeHtml(`${who(it.b.user)}
${it.b.line}
${tail}`), `fill-${it.fill.sym}-${it.fill.id}.png`);
  });
}

async function slow(c) {
  const { state, lib, MIN } = c;
  const due = (key, everyMs) => {
    if (Date.now() - (state.last[key] || 0) < everyMs) return false;
    state.last[key] = Date.now();
    return true;
  };
  if (due('slow:settings', 30_000)) await settings(c);
  if (due('slow:expiry', 5 * MIN)) await expiry(c);
  if (due('slow:weekly', 5 * MIN)) await weekly(c);
  if (due('slow:db', 30 * MIN)) await dbLimits(c);
  if (due('slow:fills', 60_000)) { try { await fillCheck(c); } catch (e) { console.error('[watchdog] fill check:', e.message); } }
  try { await fillReport(c); } catch (e) { console.error('[watchdog] fill report:', e.message); }
  const p = lib.istParts();
  if (p.hhmm >= '10:05' && !state.digests[`ssl ${p.ymd}`]) { state.digests[`ssl ${p.ymd}`] = true; await ssl(c); }
  if (p.day >= 1 && p.day <= 5 && p.hhmm >= '23:40' && !state.digests[`collusion ${p.ymd}`]) { state.digests[`collusion ${p.ymd}`] = true; await collusion(c); }
}

module.exports = { internal, events, slow, sendFillImages, _test: { certDaysLeft, spikeCatch } };
