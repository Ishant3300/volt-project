'use strict';

/**
 * Watchdog checks added after the first release (all read-only):
 *
 *   internal()  every 30 s — the backend's live state via /api/auth/internal-health:
 *               Kite feed silent / down in market hours, client loss and margin
 *               risk, pending orders whose price was crossed but didn't fill,
 *               event-loop lag; Kite login check before the open
 *   events()    every 5 s  — admin/master changes with the person's name (backend
 *               audit records), orders placed for clients by admin/master, money
 *               actions (credit/debit, wallet assign/
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

// ------------------------------------------------- who did it (audit) ----
// Every admin/master change is recorded by the backend (adminactions, from
// middlewares/auditActions.js). Alerts name the person; changes covered by a
// more specific alert (settings diff, money, orders, deletions) carry the
// name there instead of being sent twice.
const SETTLE_MS = 4000; // let the backend write its audit record before reporting
const COVERED_ACCOUNT = /\/(users|masters)(\/[a-f0-9]{24}(\/(details|permissions|status|intraday-squareoff|margin-squareoff-percentage|report-permissions))?)?$|^\/api\/masters(\/[a-f0-9]{24}(\/(details|permissions|status|intraday-squareoff|margin-squareoff-percentage))?)?$/i;
const COVERED_MONEY = /\/(credit|debit)$|\/wallet\/(assign|withdraw)$/i;
const TRADE_PLACE = /^\/api\/trade\/?$/i;
const TRADE_EDIT = /^\/api\/trade\/([a-f0-9]{24})\/(modify|cancel)$/i;
const TRADE_DELETE = /^\/api\/trade\/([a-f0-9]{24})$/i;
const ACTION_LABELS = [
  [/brokerage-settings/, 'brokerage'], [/script-quantities/, 'script quantity limits'], [/grouped-quantities/, 'quantity groups'],
  [/fresh-stoploss-limits/, 'Fresh Stop-Loss limits'], [/instruments\/(bulk-toggle|expiry-toggle)|\/instruments\//, 'scripts open/closed'],
  [/expiry-actions/, 'expiry actions'], [/announcements/, 'announcements'], [/\/brokers/, 'Brokers page'],
  [/settlement\/start/, 'weekly settlement'], [/mcx-square-off/, 'MCX square-off'], [/bhavcopy|refresh-(close|settlement)-prices/, 'prices refresh'],
  [/totp\/(toggle|reset)/, '2-step login'], [/super-admin\/admins/, 'admin accounts'], [/\/api\/servers/, 'servers'], [/\/api\/kite\//, 'Kite login/instruments'],
  [/username\/release/, 'username release'], [/base-rates/, 'master base rates'], [/account-limit/, 'master account limit'],
  [/rollover|auto-squareoff-expired/, 'rollover / expiry square-off'],
];
const VERB = { POST: 'added/ran', PUT: 'changed', PATCH: 'changed', DELETE: 'removed' };

function actorOf(a) {
  if (!a) return '';
  return `${a.actor_type} ${a.actor_username || String(a.actor_id).slice(-6)}`;
}

async function whoFresh(c, id) {
  const s = c.who(id);
  if (s !== String(id)) return s;
  const u = await c.d.collection('users').findOne({ _id: oid(id) }, { projection: { username: 1, name: 1 } }).catch(() => null);
  if (u) return `${u.username} ${u.name || ''}`.trim();
  const m = await c.d.collection('masters').findOne({ _id: oid(id) }, { projection: { username: 1, name: 1 } }).catch(() => null);
  return m ? `master ${m.username} ${m.name || ''}`.trim() : String(id);
}

function oid(id) {
  const { ObjectId } = require('mongoose').mongo;
  try { return new ObjectId(String(id)); } catch (_) { return null; }
}

/** Like newDocs, but only documents at least SETTLE_MS old (audit record is in by then). */
async function settledDocs(c, coll, filter, projection, cursor) {
  const { ObjectId } = require('mongoose').mongo;
  const key = `id:${cursor}`;
  if (!c.state.last[key]) { c.state.last[key] = ObjectId.createFromTime(Math.floor(Date.now() / 1000)).toHexString(); return []; }
  const upTo = ObjectId.createFromTime(Math.floor((Date.now() - SETTLE_MS) / 1000));
  const docs = await c.d.collection(coll).find({ ...filter, _id: { $gt: new ObjectId(c.state.last[key]), $lte: upTo } }, { projection }).sort({ _id: 1 }).limit(2000).toArray();
  if (docs.length) c.state.last[key] = String(docs[docs.length - 1]._id);
  return docs;
}

/** The latest admin/master action touching `id` (optionally matching `pathRe`) within `withinMs`. */
async function actionFor(c, id, pathRe, withinMs = 3 * 60_000) {
  const q = { created_at: { $gte: new Date(Date.now() - withinMs) } };
  if (id) q.$or = [{ target_ids: String(id) }, { 'result.id': String(id) }];
  if (pathRe) q.path = pathRe;
  return c.d.collection('adminactions').findOne(q, { sort: { created_at: -1 } }).catch(() => null);
}

function summarizeBody(body) {
  if (!body || typeof body !== 'object') return '';
  const parts = [];
  for (const [k, v] of Object.entries(body)) {
    if (['user_id', 'userId', 'master_id', 'id', '_id'].includes(k)) continue;
    if (Array.isArray(v)) {
      const first = v[0] && typeof v[0] === 'object' ? Object.entries(v[0]).filter(([kk]) => !['_id', 'id', 'user_id'].includes(kk)).map(([kk, vv]) => `${kk}=${typeof vv === 'object' ? JSON.stringify(vv) : vv}`).join(' ') : String(v[0] ?? '');
      parts.push(`${k}: ${v.length} item${v.length === 1 ? '' : 's'}${first ? ` (e.g. ${first})` : ''}`);
    } else if (v && typeof v === 'object') {
      parts.push(`${k}: ${Object.entries(v).slice(0, 6).map(([kk, vv]) => `${kk}=${typeof vv === 'object' ? JSON.stringify(vv) : vv}`).join(' ')}`);
    } else parts.push(`${k}=${v}`);
  }
  const s = parts.join(' · ');
  return s.length > 450 ? `${s.slice(0, 450)}…` : s;
}

// ------------------------------------------------ brokerage, readable ----
// "changed brokerage · ids: 51 items (e.g. 6ad06f…) · brk_value=1.5" told
// nobody which account or what the rate was before. A snapshot of every
// brokerage row (id → account, segment, rate) gives "JNL (833704) · NFO-FUT ·
// 228 scripts: 1 → 1.5 turnover". Loaded once, then kept current for every
// row an action touches.
const brkSnap = { rows: null, at: 0 };
const BRK_PATH = /\/brokerage-settings(\/|$)/;
const rateText = (type, v) => (v == null ? '—' : type === 'LOT WISE' ? `${v} per lot` : type === 'TURNOVER WISE' ? `${v} turnover` : `${v} ${String(type || '').toLowerCase()}`);

async function brokerageSnapshot(d) {
  if (brkSnap.rows && Date.now() - brkSnap.at < 30 * 60_000) return brkSnap.rows;
  const rows = await d.collection('brokeragesettings').find({ deleted_at: null }).project({ brk_value: 1, type: 1 }).toArray();
  brkSnap.rows = new Map(rows.map((r) => [String(r._id), { v: r.brk_value, type: r.type }]));
  brkSnap.at = Date.now();
  return brkSnap.rows;
}

/** True when `id` is a client/master created within 3 minutes before `at` (part of its creation). */
async function justCreated(c, id, at) {
  if (!id) return false;
  const acct = await c.d.collection('users').findOne({ _id: oid(id) }, { projection: { _id: 1 } }) || await c.d.collection('masters').findOne({ _id: oid(id) }, { projection: { _id: 1 } });
  const born = createdAt(acct);
  const t = new Date(at || Date.now()).getTime();
  return !!born && t - born >= -5_000 && t - born < 180_000;
}

/**
 * Readable lines for one brokerage action; null when it isn't one, [] when
 * it's part of creating an account (the new-account summary shows the rates).
 */
async function brokerageLines(c, a) {
  if (!BRK_PATH.test(a.path)) return null;
  const { d } = c;
  if (a.body && a.body.user_id && await justCreated(c, a.body.user_id, a.created_at)) return [];
  const snap = await brokerageSnapshot(d);
  const body = a.body || {};
  const listed = (Array.isArray(body.ids) ? body.ids : []).filter((x) => /^[a-f0-9]{24}$/i.test(String(x)));
  const more = (Array.isArray(body.ids) ? body.ids : []).map((x) => String(x).match(/^…(\d+) more$/)).filter(Boolean).reduce((s, m) => s + Number(m[1]), 0);
  const single = a.path.match(/\/brokerage-settings\/([a-f0-9]{24})$/i);
  const ids = single ? [single[1]] : listed;
  if (!ids.length) {
    // New rows (create / bulk-create): who and what, from the request.
    const owner = body.user_id ? await whoFresh(c, body.user_id) : 'platform default';
    const items = Array.isArray(body.settings) ? body.settings : Array.isArray(body.items) ? body.items : [body];
    const bySeg = new Map();
    for (const it of items) { const k = `${it.exchange_name || body.exchange_name || '?'}|${it.type || body.type || ''}|${it.brk_value ?? body.brk_value}`; bySeg.set(k, (bySeg.get(k) || 0) + 1); }
    return [...bySeg].map(([k, n]) => { const [seg, type, v] = k.split('|'); return `${owner} · ${seg} · ${n} script${n > 1 ? 's' : ''}: ${a.method === 'DELETE' ? 'removed' : `added at ${rateText(type, v)}`}`; });
  }
  const rows = await d.collection('brokeragesettings').find({ _id: { $in: ids.map(oid).filter(Boolean) } }).project({ user_id: 1, exchange_name: 1, script_name: 1, brk_value: 1, type: 1, deleted_at: 1 }).toArray();
  const owners = [...new Set(rows.map((r) => String(r.user_id || '')))];
  if (owners.length === 1 && owners[0] && await justCreated(c, owners[0], a.created_at)) {
    for (const r of rows) snap.set(String(r._id), { v: body.brk_value ?? r.brk_value, type: body.type || r.type });
    return [];
  }
  const groups = new Map();
  for (const r of rows) {
    const k = `${r.user_id || 'default'}|${r.exchange_name}`;
    const g = groups.get(k) || { owner: r.user_id, seg: r.exchange_name, n: 0, before: new Map(), after: new Map(), removed: 0, script: r.script_name };
    const old = snap.get(String(r._id));
    const ob = old ? rateText(old.type, old.v) : 'new';
    // The request's own value: a second edit of the same rows seconds later
    // must not show up as this one's result.
    const newV = body.brk_value != null && !single ? Number(body.brk_value) : r.brk_value;
    const newT = body.type && !single ? body.type : r.type;
    const nb = rateText(newT, newV);
    g.before.set(ob, (g.before.get(ob) || 0) + 1);
    g.after.set(nb, (g.after.get(nb) || 0) + 1);
    if (r.deleted_at) g.removed++;
    g.n++;
    groups.set(k, g);
    if (r.deleted_at) snap.delete(String(r._id)); else snap.set(String(r._id), { v: newV, type: newT });
  }
  const list = (m) => [...m].sort((x, y) => y[1] - x[1]).map(([t, n]) => (m.size > 1 ? `${t} (${n})` : t)).join(', ');
  const out = [];
  for (const g of groups.values()) {
    const owner = g.owner ? await whoFresh(c, g.owner) : 'platform default';
    const total = g.n + (groups.size === 1 ? more : 0);
    const what = g.removed === g.n ? 'removed' : `${list(g.before)} → ${list(g.after)}`;
    out.push(`${owner} · ${g.seg === 'INDICES' ? 'GLOBAL' : g.seg} · ${total === 1 && g.script ? g.script : `${total} script${total > 1 ? 's' : ''}`}: ${what}`);
  }
  return out.length ? out : null;
}

async function auditEvents(c) {
  const { d, state, send, lib } = c;
  const actions = await c.newDocs(d, 'adminactions', {}, null, 'adminactions');
  if (!actions.length) return;
  // Account edits: let the settings diff report them (old → new) right away.
  if (actions.some((a) => COVERED_ACCOUNT.test(a.path))) await settings(c);
  const used = state.usedActions || (state.usedActions = {});
  const lines = [];
  const brkLines = [];
  for (const a of actions) {
    if (used[String(a._id)]) continue;
    const by = actorOf(a);
    const targets = (await Promise.all((a.target_ids || []).slice(0, 5).map((id) => whoFresh(c, id)))).join(', ');
    if (COVERED_MONEY.test(a.path)) continue; // money alert names the person
    if (a.method === 'POST' && CREATE_PATH.test(a.path)) continue; // new-account summary names the person
    if (TRADE_PLACE.test(a.path)) continue; // order alert below names the person
    if (TRADE_DELETE.test(a.path) && a.method === 'DELETE') continue; // deleted-trade alert names the person
    const edit = a.path.match(TRADE_EDIT);
    if (edit) {
      const t = await d.collection('trades').findOne({ _id: oid(edit[1]) }, { projection: { user_id: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, order_type: 1, price: 1, status: 1 } });
      const b = a.body || {};
      lines.push(`${by} ${edit[2] === 'cancel' ? 'cancelled' : 'modified'} an order of ${t ? await whoFresh(c, t.user_id) : targets}: ${t ? `${t.tradingsymbol} ${t.transaction_type} ${t.quantity} ${t.order_type}${t.price ? ` @ ${t.price}` : ''}` : edit[1]}${edit[2] === 'modify' ? ` → ${summarizeBody(b)}` : ''}`);
      continue;
    }
    if (COVERED_ACCOUNT.test(a.path)) {
      // No setting difference found for it — still report the action itself.
      const verb = a.method === 'POST' ? 'created/updated' : a.method === 'DELETE' ? 'deleted' : 'saved';
      lines.push(`${by} ${verb} ${targets || 'an account'} (no tracked setting changed) · ${summarizeBody(a.body)}`.trim());
      continue;
    }
    const brk = await brokerageLines(c, a);
    if (brk) { brkLines.push(...brk.map((l) => `${l} · by ${by}`)); continue; } // [] = part of an account's creation
    const label = (ACTION_LABELS.find(([re]) => re.test(a.path)) || [null, a.path.replace(/^\/api\//, '')])[1];
    lines.push(`${by} ${VERB[a.method] || a.method} ${label}${targets ? ` for ${targets}` : ''}${a.body ? ` · ${summarizeBody(a.body)}` : ''}`);
  }
  for (const k of Object.keys(used)) if (Date.now() - used[k] > 30 * 60_000) delete used[k];
  if (brkLines.length) send(lib.formatAlert('info', `Brokerage changed${brkLines.length > 1 ? ` (${brkLines.length})` : ''}`, [...brkLines.slice(0, 15), brkLines.length > 15 ? `…and ${brkLines.length - 15} more` : '']));
  if (lines.length) send(lib.formatAlert('info', `Admin / master change${lines.length > 1 ? `s (${lines.length})` : ''}`, [...lines.slice(0, 15), lines.length > 15 ? `…and ${lines.length - 15} more` : '']));
}

// ------------------------------------------------- new client / master ----
// Creating an account used to send 3 messages (settings "new master", the
// raw create request, and 3-5 money lines: parent debit, initial credit,
// wallet per category). Now one message with everything, a few seconds
// after the account appears (its brokerage / wallet rows are in by then).
const CREATE_PATH = /^\/api\/(admin\/users|master\/users|master\/masters|masters)\/?$/i;
// "Deducted balance for new child master creation" / "…for new user creation" / "Initial account creation funding"
const CREATION_NOTE = /new (child|user|client|master|sub)|account creation|initial account/i;
const NEW_ACCOUNT_WAIT_MS = 15_000;
const createdAt = (doc) => (doc && doc._id && doc._id.getTimestamp ? doc._id.getTimestamp().getTime() : 0);

/** Money rows written by the account-creation request itself (shown in the new-account message). */
async function partOfCreation(c, t) {
  const note = `${(t.metadata && t.metadata.note) || ''} ${t.description || ''} ${t.note || ''}`;
  if (CREATION_NOTE.test(note)) return true;
  const id = t.userId || t.master_id;
  if (!id) return false;
  const acct = await c.d.collection(t.master_id || t.userModel === 'Master' ? 'masters' : 'users').findOne({ _id: oid(id) }, { projection: { _id: 1 } })
    || await c.d.collection('masters').findOne({ _id: oid(id) }, { projection: { _id: 1 } });
  const born = createdAt(acct);
  return !!born && t._id.getTimestamp().getTime() - born < 60_000;
}

function brokerageText(r) {
  if (!r) return 'no brokerage set';
  if (r.type === 'LOT WISE') return `₹${r.brk_value}/lot`;
  if (r.type === 'TURNOVER WISE') return `${r.brk_value} turnover`;
  return `${r.brk_value} ${String(r.type || '').toLowerCase()}`;
}

async function newAccountMessage(c, kind, id) {
  const { d } = c;
  const doc = await d.collection(kind).findOne({ _id: oid(id) });
  if (!doc) return null;
  const isClient = kind === 'users';
  const born = createdAt(doc);
  const action = await d.collection('adminactions').findOne({ method: 'POST', path: CREATE_PATH, 'body.username': doc.username, created_at: { $gte: new Date(born - 5 * 60_000) } }, { sort: { created_at: -1 } }).catch(() => null);
  const parentId = doc.master_id ? String(doc.master_id) : null;
  const parentDebit = parentId ? await d.collection('transactions').findOne({ userId: { $in: [oid(parentId), parentId] }, type: 'DEBIT', _id: { $gte: require('mongoose').mongo.ObjectId.createFromTime(Math.floor(born / 1000) - 120) } }, { sort: { _id: -1 } }) : null;
  const brk = await d.collection('brokeragesettings').find({ user_id: { $in: [doc._id, String(doc._id)] }, deleted_at: null }).project({ exchange_name: 1, type: 1, brk_value: 1, script_name: 1 }).toArray();
  // The rate the account pays on most scripts of each segment.
  const tallies = new Map();
  for (const r of brk) {
    const raw = String(r.exchange_name).toUpperCase();
    const seg = raw === 'GLOBAL' ? 'INDICES' : raw; // GLOBAL brokerage is kept under both names
    const m = tallies.get(seg) || new Map();
    const k = `${r.type}|${r.brk_value}`;
    const e = m.get(k) || { n: 0, r };
    e.n++;
    m.set(k, e);
    tallies.set(seg, m);
  }
  const usualBrk = new Map([...tallies].map(([seg, m]) => [seg, [...m.values()].sort((a, b) => b.n - a.n)[0].r]));
  const groups = new Map((doc.script_quantity_groups || []).map((g) => [String(g.exchange_name).toUpperCase(), g.group_name]));
  const wallet = Object.entries(doc.wallet || {}).filter(([, v]) => Number(v) > 0).map(([k, v]) => `${k} ${rupees(v)}`);

  const lines = [
    `Name: ${doc.name || '—'} · ID: ${doc.username}`,
    `Under: ${parentId ? await whoFresh(c, parentId) : 'admin (top level)'}`,
    `Created by: ${action ? actorOf(action) : 'not recorded'}`,
    `Credit: ${rupees(doc.credits)}${parentDebit ? ` (taken from ${await whoFresh(c, parentId)})` : ''}`,
    `Trade wallet: ${wallet.length ? wallet.join(' · ') : 'none'}`,
    'Exchanges:',
    ...((doc.exchanges_allowed || []).map((x) => {
      const e = typeof x === 'string' ? { exchange_name: x } : x; // masters: plain names
      const seg = String(e.exchange_name).toUpperCase();
      const mode = e.lot ? 'lot' : e.turnover ? 'turnover' : '';
      const group = e.group_name || groups.get(seg);
      const rate = usualBrk.get(seg === 'GLOBAL' ? 'INDICES' : seg);
      return `  • ${seg}${mode ? ` — ${mode}` : ''}${group ? ` · group ${group}` : ''} · brokerage ${brokerageText(rate)}`;
    })),
  ];
  if ((doc.exchanges_allowed || []).length === 0) lines.push('  none');
  if (doc.pnl_sharing != null || doc.brokerage_sharing != null) lines.push(`Sharing: P&L ${doc.pnl_sharing ?? 0}% · brokerage ${doc.brokerage_sharing ?? 0}%`);
  if (!isClient) lines.push(`Can create sub-masters: ${doc.add_master ? 'yes' : 'no'}`);
  if (isClient) {
    const extra = [];
    if (doc.margin_square_off) extra.push(`margin square-off at ${doc.margin_square_off_percentage ?? '—'}%`);
    if (doc.close_only) extra.push('close-only ON');
    if (doc.fresh_stoploss) extra.push('fresh stop-loss on');
    if (doc.status && doc.status !== 'active') extra.push(`status ${doc.status}`);
    if (extra.length) lines.push(`Settings: ${extra.join(' · ')}`);
  }
  return c.lib.formatAlert('info', `New ${isClient ? 'client' : 'master'} created: ${doc.username} ${doc.name || ''}`.trim(), lines);
}

/** Send the one-message summary for accounts created at least NEW_ACCOUNT_WAIT_MS ago. */
async function newAccounts(c) {
  const pending = c.state.newAccounts || {};
  for (const [id, p] of Object.entries(pending)) {
    if (Date.now() - p.seenAt < NEW_ACCOUNT_WAIT_MS) continue;
    delete pending[id];
    try {
      const msg = await newAccountMessage(c, p.kind, id);
      if (msg) c.send(msg);
    } catch (e) { console.error('[watchdog] new account message:', e.message); }
  }
}

/** Orders an admin or master placed for a client (any outcome), with who placed them. */
async function staffOrders(c) {
  const { d, send, lib } = c;
  const trades = await settledDocs(c, 'trades', { placed_by: { $in: ['ADMIN', 'MASTER'] }, trade_type: { $ne: 'carry_forward' } },
    { user_id: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, order_type: 1, price: 1, executed_price: 1, status: 1, placed_by: 1, trade_type: 1, remarks: 1 }, 'trades-staff');
  if (!trades.length) return;
  const lines = [];
  for (const t of trades) {
    const a = await actionFor(c, t._id, TRADE_PLACE, 10 * 60_000);
    const by = a ? actorOf(a) : `${String(t.placed_by).toLowerCase()} (name not recorded)`;
    const px = t.status === 'completed' ? ` @ ${t.executed_price}` : t.price ? ` @ ${t.price}` : '';
    const kind = t.trade_type === 'admin_square_off' ? ' [square-off]' : '';
    lines.push(`${by} → ${await whoFresh(c, t.user_id)}: ${t.tradingsymbol} ${t.transaction_type} ${t.quantity} ${t.order_type}${px} · ${t.status}${kind}${t.status === 'rejected' && t.remarks ? ` (${String(t.remarks).slice(0, 120)})` : ''}`);
  }
  send(lib.formatAlert('info', `Order${lines.length > 1 ? `s (${lines.length})` : ''} placed for clients by admin / master`, [...lines.slice(0, 20), lines.length > 20 ? `…and ${lines.length - 20} more` : '']));
}

async function events(c) {
  const { d, raise, send, lib, who, hit, newDocs, MIN } = c;

  await brokerageSnapshot(d); // warm before any change is processed (old → new)
  await auditEvents(c);
  await newAccounts(c);
  await staffOrders(c);

  // Money moved by admin / master (named from the transaction, else from the
  // audit record). Rows written by an account's creation are in its summary.
  const txAll = await settledDocs(c, 'transactions', { type: { $in: MONEY_TYPES } }, { userId: 1, userModel: 1, type: 1, amount: 1, metadata: 1, description: 1 }, 'transactions');
  const tx = [];
  for (const t of txAll) if (!(await partOfCreation(c, t))) tx.push(t);
  if (tx.length) {
    const lines = [];
    for (const t of tx.slice(0, 12)) {
      const m = t.metadata || {};
      const cat = m.category ? ` ${m.category}` : '';
      let by = actorName(c, m);
      if (!by) by = actorOf(await actionFor(c, t.userId, COVERED_MONEY, 2 * 60_000)) || actorOf(await actionFor(c, t.userId, COVERED_ACCOUNT, 2 * 60_000));
      const after = m.targetBalanceAfter != null ? ` (now ${rupees(m.targetBalanceAfter)})` : '';
      const note = m.note ? ` · ${m.note}` : '';
      lines.push(`${t.type.replace('_', ' ')}${cat} ${rupees(t.amount)} → ${await whoFresh(c, t.userId)}${after}${by ? ` · by ${by}` : ''}${note}`);
    }
    if (tx.length > 12) lines.push(`…and ${tx.length - 12} more`);
    send(lib.formatAlert('info', `Money action${tx.length > 1 ? `s (${tx.length})` : ''}`, lines));
  }
  const ctxAll = await settledDocs(c, 'credittransactions', {}, { master_id: 1, admin_id: 1, transaction_type: 1, amount: 1, note: 1, actor_model: 1 }, 'credittransactions');
  const ctx = [];
  for (const t of ctxAll) if (!(await partOfCreation(c, t))) ctx.push(t);
  if (ctx.length) {
    const lines = [];
    for (const t of ctx.slice(0, 12)) {
      let by = '';
      if (t.actor_model === 'Admin' && t.admin_id) by = `admin ${c.names.admins.get(String(t.admin_id))?.username || String(t.admin_id).slice(-6)}`;
      if (!by) by = actorOf(await actionFor(c, t.master_id, COVERED_MONEY, 2 * 60_000));
      lines.push(`${t.transaction_type} ${rupees(t.amount)} → ${await whoFresh(c, t.master_id)}${by ? ` · by ${by}` : ''}${t.note ? ` · ${t.note}` : ''}`);
    }
    send(lib.formatAlert('info', `Master credit change${ctx.length > 1 ? `s (${ctx.length})` : ''}`, lines));
  }

  // Trades deleted (not weekly-settlement archiving), with who deleted them.
  const state = c.state;
  if (!state.last.delAt) state.last.delAt = new Date().toISOString();
  const del = await d.collection('trades').find({ deleted_at: { $gt: new Date(state.last.delAt), $lte: new Date(Date.now() - SETTLE_MS) }, settlement_period_key: null })
    .project({ user_id: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, executed_price: 1, status: 1, deleted_at: 1, remarks: 1 }).sort({ deleted_at: 1 }).limit(200).toArray();
  if (del.length) {
    state.last.delAt = new Date(del[del.length - 1].deleted_at).toISOString();
    const lines = [];
    for (const t of del.slice(0, 10)) {
      const a = await actionFor(c, t._id, TRADE_DELETE, 10 * 60_000);
      lines.push(`${who(t.user_id)} · ${t.tradingsymbol} ${t.transaction_type} ${t.quantity} @ ${t.executed_price || 0} (${t.status})${a ? ` · by ${actorOf(a)}` : ''}`);
    }
    raise(`deleted:${state.last.delAt}`, 'warning', `Trade${del.length > 1 ? `s (${del.length})` : ''} deleted`, lines, { cooldownMs: 0 });
  }

  // Brokerage and script-limit rows changed WITHOUT an admin/master action
  // (scripts / direct database edits). Changes made in the app are already
  // reported, with the person's name, by auditEvents.
  for (const [coll, field, ownerField, title] of [['brokeragesettings', 'updated_at', 'user_id', 'Brokerage changed'], ['scriptquantities', 'updated_at', 'owner_id', 'Script limits changed']]) {
    const k = `upd:${coll}`;
    if (!state.last[k]) { state.last[k] = new Date().toISOString(); continue; }
    const rows = await d.collection(coll).find({ [field]: { $gt: new Date(state.last[k]), $lte: new Date(Date.now() - SETTLE_MS) } }).project({ [field]: 1, [ownerField]: 1, exchange_name: 1, deleted_at: 1 }).sort({ [field]: 1 }).limit(5000).toArray();
    if (!rows.length) continue;
    state.last[k] = new Date(rows[rows.length - 1][field]).toISOString();
    if (await actionFor(c, null, null, 3 * 60_000)) continue; // made in the app — reported by auditEvents
    const per = new Map();
    for (const r of rows) {
      const owner = r[ownerField] ? String(r[ownerField]) : 'platform default';
      const e = per.get(owner) || { n: 0, segs: new Set(), del: 0 };
      e.n++;
      if (r.exchange_name) e.segs.add(r.exchange_name);
      if (r.deleted_at) e.del++;
      per.set(owner, e);
    }
    send(lib.formatAlert('info', `${title} (not from the app — script or database)`, [...per.entries()].slice(0, 10).map(([o, e]) => `${o === 'platform default' ? o : who(o)}: ${e.n} row${e.n > 1 ? 's' : ''}${e.del ? ` (${e.del} removed)` : ''} · ${[...e.segs].join(', ')}`)));
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
// Every setting an admin/master can change on an account. Not here on
// purpose: balances (money alerts cover them), live P&L/margin fields, login
// data, push tokens, passwords (an admin password reset shows as "password
// [changed]" through the audit record instead).
const SETTING_FIELDS_USER = ['name', 'note', 'status', 'active_status', 'bet', 'close_only', 'margin_square_off', 'margin_square_off_percentage', 'fresh_stoploss',
  'intraday_squareoff', 'trade_limit', 'pnl_sharing', 'brokerage_sharing', 'report_permissions', 'server_id', 'master_id', 'change_pass_on_first_login', 'deleted_at'];
const SETTING_FIELDS_MASTER = ['name', 'note', 'status', 'active_status', 'pnl_sharing', 'brokerage_sharing', 'add_master', 'master_id', 'intraday_squareoff',
  'margin_square_off', 'margin_square_off_percentage', 'trade_limit', 'server_id', 'max_credit', 'exchanges', 'permissions', 'account_limit',
  'script_quantity_groups', 'allotted_script_quantity_groups', 'totp_enabled', 'change_pass_on_first_login', 'deleted_at'];
const SETTINGS_VERSION = 2;
// The client's own first-login password change clears change_pass_on_first_login.
const SELF_PASSWORD = 'set their own password (first login)';
const show = (v) => (v == null ? '—' : v === true ? 'on' : v === false ? 'off' : Array.isArray(v) ? (v.length ? v.map((x) => (typeof x === 'object' ? JSON.stringify(x) : x)).join(',') : 'none') : typeof v === 'object' ? JSON.stringify(v) : String(v));
const strip = (v) => JSON.parse(JSON.stringify(v ?? null, (k, x) => (k === '_id' ? undefined : x)));

function exchangeDiff(before = [], after = []) {
  // Clients keep exchanges as objects, masters as plain names.
  const map = (list) => new Map((list || []).map((e) => (typeof e === 'string' ? [e, { exchange_name: e }] : [e.exchange_name, e])));
  const b = map(before); const a = map(after);
  const out = [];
  for (const [name, e] of a) {
    if (!b.has(name)) { out.push(`exchange ${name} added${e.lot != null || e.turnover != null ? ` (${e.lot ? 'lot' : 'turnover'}, group ${e.group_name || '—'})` : ''}`); continue; }
    const o = b.get(name);
    const ch = Object.keys({ ...o, ...e }).filter((k) => JSON.stringify(o[k]) !== JSON.stringify(e[k])).map((k) => `${k.replace(/_/g, ' ')} ${show(o[k])} → ${show(e[k])}`);
    if (ch.length) out.push(`${name}: ${ch.join(', ')}`);
  }
  for (const name of b.keys()) if (!a.has(name)) out.push(`exchange ${name} removed`);
  return out;
}

function fieldDiff(f, before, after, who) {
  if (f === 'master_id') return [`moved from ${who(before)} to ${who(after)}`];
  if (f === 'deleted_at') return [after ? 'deleted' : 'restored'];
  if (f === 'change_pass_on_first_login') return [after ? 'must set a new password at next login' : SELF_PASSWORD];
  if (f === 'exchanges_allowed') return exchangeDiff(before, after);
  const name = f.replace(/_/g, ' ');
  if (before && after && typeof before === 'object' && typeof after === 'object' && !Array.isArray(before) && !Array.isArray(after)) {
    return Object.keys({ ...before, ...after }).filter((k) => JSON.stringify(before[k]) !== JSON.stringify(after[k])).map((k) => `${name} ${k.replace(/_/g, ' ')} ${show(before[k])} → ${show(after[k])}`);
  }
  return [`${name} ${show(before)} → ${show(after)}`];
}

async function settings(c) {
  const { d, state, send, lib, who } = c;
  const users = await d.collection('users').find({}).project(Object.fromEntries([...SETTING_FIELDS_USER, 'exchanges_allowed', 'username'].map((f) => [f, 1]))).toArray();
  const masters = await d.collection('masters').find({}).project(Object.fromEntries([...SETTING_FIELDS_MASTER, 'exchanges_allowed', 'username'].map((f) => [f, 1]))).toArray();
  const snap = (doc, fields) => {
    const o = {};
    for (const f of [...fields, 'exchanges_allowed']) o[f] = doc[f] == null ? null : f === 'master_id' ? String(doc[f]) : f === 'deleted_at' ? true : strip(doc[f]);
    return o;
  };
  const first = !state.settings || state.settingsVersion !== SETTINGS_VERSION;
  const prev = first ? { users: {}, masters: {} } : state.settings;
  const next = { users: {}, masters: {} };
  const used = state.usedActions || (state.usedActions = {});
  const lines = [];
  for (const [kind, list, fields] of [['users', users, SETTING_FIELDS_USER], ['masters', masters, SETTING_FIELDS_MASTER]]) {
    for (const doc of list) {
      const id = String(doc._id);
      const now = snap(doc, fields);
      next[kind][id] = now;
      if (first) continue;
      const before = prev[kind][id];
      const label = kind === 'users' ? `client ${await whoFresh(c, id)}` : `master ${doc.username} ${doc.name || ''}`.trim();
      if (!before) {
        // Reported as one full summary by newAccounts() a few seconds later.
        (state.newAccounts || (state.newAccounts = {}))[id] = { kind, seenAt: Date.now() };
        continue;
      }
      const diffs = Object.keys(now).filter((f) => JSON.stringify(now[f]) !== JSON.stringify(before[f])).flatMap((f) => fieldDiff(f, before[f], now[f], who));
      if (!diffs.length) continue;
      const a = await actionFor(c, id, null, 5 * 60_000);
      if (a) used[String(a._id)] = Date.now();
      const byClient = !a && kind === 'users' && diffs.every((x) => x === SELF_PASSWORD);
      lines.push(`${label}: ${diffs.join('; ')} · by ${a ? actorOf(a) : byClient ? 'the client' : 'system / not recorded'}`);
    }
  }
  state.settings = next;
  state.settingsVersion = SETTINGS_VERSION;
  state.last['slow:settings'] = Date.now();
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
            win.spikes.push({ user: f.user, ex: { low: own.low, high: own.high, volume: own.volume }, line: `${f.sym} ${f.side} ${f.qty} ${f.ot} @ ${f.price} at ${istStr(f.at).slice(11)} · minute ${own.low}–${own.high} (${spike.rangePct.toFixed(2)}% move), fill in the outer ${Math.round(spike.edgePct)}% · exchange volume ${own.volume}${spike.volShare != null ? ` (client qty = ${spike.volShare < 10 ? spike.volShare.toFixed(1) : Math.round(spike.volShare)}% of it)` : ''}`,
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
        win.better.push({ user: f.user, ex: { low, high }, line: `${f.sym} ${f.side} ${f.qty} ${f.ot} @ ${f.price} at ${istStr(f.at).slice(11)} · exchange ${own.low}–${own.high} (±1 min ${low}–${high})`, value: gap * f.qty,
          fill: { id: f.id, token: f.token, sym: f.sym, side: f.side, qty: f.qty, ot: f.ot, price: f.price, at: f.at } });
      }
    }
  }
  state.fillQueue = state.fillQueue.filter((f) => !done.has(f.id));
  // Quick profits among the fills just checked (bounded per run).
  let qc = 0;
  for (const f of ready) {
    if (!done.has(f.id) || qc >= 15) continue;
    qc++;
    try { await quickProfitCheck(c, f, ks); } catch (e) { console.error('[watchdog] quick profit:', e.message); }
  }
}

/**
 * Quick profit: a close that books a profit within WATCHDOG_QUICK_MAX_MIN
 * (default 20) minutes of the quantity it closes being opened (FIFO lots).
 * The exchange candles for that holding window are checked for a heavy move:
 * low-to-high range >= WATCHDOG_HEAVY_MOVE_PCT (1%) or volume >= 3x the 30
 * minutes before. All quick profits are listed in the hourly report; heavy-
 * move ones are flagged and get an image.
 */
const QUICK_MAX_MIN = () => num(process.env.WATCHDOG_QUICK_MAX_MIN, 20);
const QUICK_MIN_PROFIT = () => num(process.env.WATCHDOG_QUICK_MIN_PROFIT, 1000);
const HEAVY_MOVE_PCT = () => num(process.env.WATCHDOG_HEAVY_MOVE_PCT, 1);
const HEAVY_VOL_X = () => num(process.env.WATCHDOG_HEAVY_VOL_X, 3);

/** The FIFO lots a given closing fill consumed: { consumed: [{qty, price, at}], longClosed }. */
function closedLots(fills, closeId) {
  const lots = [];
  let side = 0;
  for (const t of fills) {
    const sg = t.transaction_type === 'BUY' ? 1 : -1;
    let q = Number(t.executed_quantity ?? t.quantity) || 0;
    const at = new Date(t.executed_at).getTime();
    const consumed = [];
    while (q > 0 && lots.length && side !== sg) {
      const m = Math.min(q, lots[0].qty);
      consumed.push({ qty: m, price: lots[0].price, at: lots[0].at });
      lots[0].qty -= m;
      q -= m;
      if (!lots[0].qty) lots.shift();
    }
    if (String(t._id) === closeId) return { consumed, longClosed: sg === -1 };
    if (!lots.length) side = 0;
    if (q > 0) {
      side = sg;
      lots.push({ qty: q, price: t.executed_price, at });
    }
  }
  return { consumed: [], longClosed: false };
}

const candleMs = (cd) => Date.parse(String(cd.date).replace(/(\+\d{2})(\d{2})$/, '$1:$2'));

async function quickProfitCheck(c, f, ks) {
  const { d, state } = c;
  const { ObjectId } = require(path.join(APP, 'node_modules', 'mongoose')).mongo;
  const fills = await d.collection('trades').find({
    user_id: new ObjectId(f.user), instrument_token: { $in: [f.token, Number(f.token)] }, status: 'completed',
    executed_at: { $lte: new Date(f.at + 1000) }, trade_type: { $ne: 'carry_forward' },
    $or: [{ deleted_at: null }, { settlement_period_key: { $exists: true, $ne: null } }],
  }).project({ transaction_type: 1, executed_quantity: 1, quantity: 1, executed_price: 1, executed_at: 1 }).sort({ executed_at: 1, _id: 1 }).toArray();
  const { consumed, longClosed } = closedLots(fills, f.id);
  if (!consumed.length) return; // not a close
  const pnl = consumed.reduce((sum, l) => sum + (longClosed ? f.price - l.price : l.price - f.price) * l.qty, 0);
  const entryAt = Math.max(...consumed.map((l) => l.at)); // the most recent entry it closes
  const holdMin = (f.at - entryAt) / 60_000;
  if (!(pnl >= QUICK_MIN_PROFIT()) || holdMin > QUICK_MAX_MIN()) return;
  const firstEntry = Math.min(...consumed.map((l) => l.at));
  let candles = [];
  try {
    candles = (await ks.getHistoricalData(f.token, 'minute', `${istStr(firstEntry - 30 * 60_000).slice(0, 16)}:00`, `${istStr(f.at + 5 * 60_000).slice(0, 16)}:00`, { silent: true })) || [];
  } catch (_) { /* no candles */ }
  await new Promise((r) => setTimeout(r, 350));
  const startMin = Math.floor(firstEntry / 60_000) * 60_000;
  const endMin = Math.floor(f.at / 60_000) * 60_000;
  const inWin = candles.filter((cd) => candleMs(cd) >= startMin && candleMs(cd) <= endMin);
  const before = candles.filter((cd) => candleMs(cd) < startMin);
  let movePct = null;
  let dirPct = null;
  let volX = null;
  let hi = null;
  let lo = null;
  if (inWin.length) {
    hi = Math.max(...inWin.map((x) => x.high));
    lo = Math.min(...inWin.map((x) => x.low));
    movePct = ((hi - lo) / lo) * 100;
    dirPct = ((inWin[inWin.length - 1].close - inWin[0].open) / inWin[0].open) * 100;
    const avg = (arr) => arr.reduce((s2, x) => s2 + (x.volume || 0), 0) / Math.max(1, arr.length);
    const bAvg = avg(before);
    volX = bAvg > 0 ? avg(inWin) / bAvg : null;
  }
  const heavy = (movePct != null && movePct >= HEAVY_MOVE_PCT()) || (volX != null && volX >= HEAVY_VOL_X());
  const day = istStr(f.at).slice(0, 10);
  const st = state.fillStats[day] || (state.fillStats[day] = { checked: 0, better: 0, worse: 0, gain: {} });
  st.quick = (st.quick || 0) + 1;
  if (heavy) st.quickHeavy = (st.quickHeavy || 0) + 1;
  st.quickBy = st.quickBy || {};
  st.quickBy[f.user] = (st.quickBy[f.user] || 0) + pnl;
  const win = state.fillWindow || (state.fillWindow = { checked: 0, better: [], worse: 0 });
  win.quick = win.quick || [];
  if (win.quick.length >= 60) return;
  const qty = consumed.reduce((s2, l) => s2 + l.qty, 0);
  const entryPrice = consumed.reduce((s2, l) => s2 + l.price * l.qty, 0) / qty;
  const held = `${Math.floor(holdMin)}m ${Math.round((holdMin % 1) * 60)}s`;
  const market = movePct != null
    ? ` · market ${lo}–${hi} (${movePct.toFixed(2)}% range, ${dirPct >= 0 ? '+' : ''}${dirPct.toFixed(2)}%)${volX != null ? `, volume ${volX.toFixed(1)}× normal` : ''}`
    : '';
  win.quick.push({
    user: f.user,
    heavy,
    value: pnl,
    line: `${f.sym} ${longClosed ? 'BUY' : 'SELL'} ${qty} @ ${entryPrice.toFixed(2)} (${istStr(firstEntry).slice(11)}) → ${f.side} @ ${f.price} (${istStr(f.at).slice(11)}) · held ${held} · profit ${rupees(pnl)}${market}`,
    fill: { id: f.id, token: f.token, sym: f.sym, side: f.side, qty, ot: f.ot, price: f.price, at: f.at },
    rt: { entryAt: firstEntry, entryPrice, entrySide: longClosed ? 'BUY' : 'SELL', held, pnl, movePct, dirPct, volX, hi, lo },
  });
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
  // Plain-language report: what was checked, then only what needs a look —
  // each trade on two short lines (who / what, then the market and the money).
  const n2 = (x) => Number(x).toLocaleString('en-IN', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const hm = (ms) => istStr(ms).slice(11, 16);
  const sym = (t) => String(t).replace(/^(.*?)(\d{2})([A-Z]{3})FUT$/, '$1 $3 FUT');
  const quick = (win.quick || []).slice().sort((a, b) => Number(b.heavy) - Number(a.heavy) || b.value - a.value);
  const heavyN = quick.filter((x) => x.heavy).length;
  const gap = ' ';
  const lines = [
    `${win.checked} trade${win.checked === 1 ? '' : 's'} checked against the exchange's prices${win.better.length ? '' : ' · all at fair market prices ✅'}`,
    ...(win.better.length ? [gap, `⚠ At a price the market never traded (${win.better.length}) · ${rupees(total)} in clients' favour`,
      ...win.better.slice(0, 20).flatMap((b) => [`• ${who(b.user)} · ${sym(b.fill.sym)}`,
        `   ${b.fill.side} ${b.fill.qty} @ ${n2(b.fill.price)} at ${hm(b.fill.at)} · market was ${n2(b.ex?.low)}–${n2(b.ex?.high)} · difference ${rupees(b.value)}`]),
      win.better.length > 20 ? `…and ${win.better.length - 20} more` : ''] : []),
    ...(win.spikes.length ? [gap, `⚡ Filled at the edge of a sudden spike (${win.spikes.length})`,
      ...win.spikes.slice(0, 15).flatMap((b) => [`• ${who(b.user)} · ${sym(b.fill.sym)}`,
        `   ${b.fill.side} ${b.fill.qty} @ ${n2(b.fill.price)} at ${hm(b.fill.at)} · that minute ${n2(b.ex?.low)}–${n2(b.ex?.high)} (${b.spike.rangePct.toFixed(1)}% move)${b.spike.volShare != null ? ` · client was ${b.spike.volShare < 10 ? b.spike.volShare.toFixed(1) : Math.round(b.spike.volShare)}% of its volume` : ''}`])] : []),
    ...(quick.length ? [gap, `⏱ Quick profits — closed within ${QUICK_MAX_MIN()} min (${quick.length}) · total ${rupees(quick.reduce((s2, x) => s2 + x.value, 0))}${heavyN ? ` · ⚠ ${heavyN} in a heavy move` : ''}`,
      ...quick.slice(0, 15).flatMap((x) => {
        const r = x.rt || {};
        const exit = r.entrySide === 'BUY' ? 'Sell' : 'Buy';
        const mins = Math.max(1, Math.round((x.fill.at - r.entryAt) / 60000));
        const mkt = r.movePct == null ? '' : x.heavy
          ? `⚠ heavy move: ${r.movePct.toFixed(1)}%${r.volX != null ? `, volume ${r.volX.toFixed(1)}× normal` : ''}`
          : `normal market (moved ${r.movePct.toFixed(1)}%)`;
        return [`${x.heavy ? '⚠' : '•'} ${who(x.user)} · ${sym(x.fill.sym)} · ${x.fill.qty} qty`,
          `   ${r.entrySide === 'BUY' ? 'Buy' : 'Sell'} ${n2(r.entryPrice)} at ${hm(r.entryAt)} → ${exit} ${n2(x.fill.price)} at ${hm(x.fill.at)} (${mins} min) · profit ${rupees(x.value)}`,
          mkt ? `   ${mkt}` : ''];
      })] : []),
  ];
  send(lib.formatAlert(win.better.length || win.spikes.length || (win.quick || []).some((x) => x.heavy) ? 'warning' : 'info', `Fill check ${hhmm(prevMark)}–${hhmm(m)}`, lines));
  // One forwardable image per flagged fill (max 10 per report): exchange minutes ±12 min + the trade.
  const withFill = [...win.better, ...win.spikes, ...(win.quick || []).filter((x) => x.heavy)].filter((b) => b.fill).slice(0, 10);
  if (withFill.length) await sendFillImages(c, withFill);
}

async function sendFillImages(c, list) {
  const { who, lib } = c;
  const ks = await kite();
  const items = [];
  for (const b of list) {
    const f = b.fill;
    let candles = [];
    const fromMs = b.rt ? b.rt.entryAt - 8 * 60_000 : f.at - 12 * 60_000;
    const toMs = b.rt ? f.at + 5 * 60_000 : f.at + 12 * 60_000;
    try { candles = (await ks.getHistoricalData(f.token, 'minute', `${istStr(fromMs).slice(0, 16)}:00`, `${istStr(toMs).slice(0, 16)}:00`, { silent: true })) || []; } catch (_) { /* skip */ }
    await new Promise((r) => setTimeout(r, 350));
    if (!candles.length) continue;
    const u = c.names.users.get(String(b.user));
    items.push({ b, fill: { ...f, client: u ? `${u.username} ${u.name || ''}`.trim() : who(b.user), spike: b.spike || null, rt: b.rt || null }, candles });
  }
  if (!items.length) return;
  const { renderFillImages } = require('./fillImage');
  const pngs = await renderFillImages(items);
  pngs.forEach((png, i) => {
    const it = items[i];
    const tail = it.b.rt ? 'Quick profit during a heavy move' : it.b.spike ? 'Filled at the extreme of a fast minute' : `${rupees(it.b.value)} better than any traded price`;
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
  if (due('slow:notices', 60_000)) { try { await require('./notices').run(c); } catch (e) { console.error('[watchdog] notices:', e.message); } }
  if (due('slow:fills', 60_000)) { try { await fillCheck(c); } catch (e) { console.error('[watchdog] fill check:', e.message); } }
  try { await fillReport(c); } catch (e) { console.error('[watchdog] fill report:', e.message); }
  const p = lib.istParts();
  if (p.hhmm >= '10:05' && !state.digests[`ssl ${p.ymd}`]) { state.digests[`ssl ${p.ymd}`] = true; await ssl(c); }
  if (p.day >= 1 && p.day <= 5 && p.hhmm >= '23:40' && !state.digests[`collusion ${p.ymd}`]) { state.digests[`collusion ${p.ymd}`] = true; await collusion(c); }
}

module.exports = { internal, events, slow, sendFillImages, _test: { fillReport, brokerageLines, certDaysLeft, spikeCatch, closedLots, exchangeDiff, fieldDiff, summarizeBody, COVERED_ACCOUNT, COVERED_MONEY, TRADE_EDIT, CREATE_PATH, newAccountMessage, partOfCreation } };
