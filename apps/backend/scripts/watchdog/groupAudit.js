'use strict';

/**
 * Weekly group-trading audit (6 Nov 2026) — READ-ONLY.
 *
 * Finds accounts that are run from ONE device: the same app phone (the Volt /
 * Velo app sends its phone model in the User-Agent, e.g. "Android 13; OnePlus
 * IV2201") on the same IP, logging in or placing orders for different
 * accounts close together. Built after the BDS82 › PIYUSH case (8 clients on
 * one OnePlus, orders placed in rotation). The nightly collusion digest in
 * extra.js matches IPs per day; this adds the device, links a whole week, and
 * reports only groups worth checking, with an English + Gujarati PDF.
 *
 *   Sources (nothing is written to the database):
 *     loginhistories (time, IP, User-Agent), trades (orders, P&L), users,
 *     masters, and the nginx access log (IP + User-Agent of every
 *     POST /api/trade, matched to its order by the second; kept 10 days).
 *
 *   A link between two accounts:
 *     app device  — same phone model + same IP, both seen within one session
 *                   (gap ≤ 30 min), and either on 2+ different days or within
 *                   5 minutes of each other;
 *     browser     — identical full browser string + same IP within 10 min,
 *                   on 2+ different days (browsers alone are too common).
 *   Linked accounts form groups. Reported only when worth checking: cross
 *   trades inside the group, or 3+ accounts, or 2 accounts whose names don't
 *   match (KUNAL / KUNAL INDEX style pairs are counted, not reported).
 *   ~/watchdog/group-audit-allow.json { "groups": [["332349","784244"]] }
 *   silences known groups.
 *
 * Run:  node scripts/watchdog/groupAudit.js --dry [--to=2026-11-06T12:00:00+05:30] [--days=7]
 *       (--dry: PDFs + message in ~/watchdog/group-audit/, nothing sent)
 * pm2:  group-audit, cron_restart "30 3 * * 6" (Sat 09:00 IST), autorestart off.
 *       Under pm2 it only works on Saturday 08:55–10:00 IST and once per week,
 *       so a pm2 start/resurrect never sends an extra report.
 */

const path = require('path');
const fs = require('fs');
const zlib = require('zlib');
const https = require('https');
const { execFileSync } = require('child_process');

const APP = path.resolve(__dirname, '..', '..');
require(path.join(APP, 'node_modules', 'dotenv')).config({ path: path.join(APP, '.env') });
const mongoose = require(path.join(APP, 'node_modules', 'mongoose'));

const HOME = process.env.HOME || '/home/ec2-user';
const STATE_DIR = path.join(HOME, 'watchdog');
const OUT_DIR = path.join(STATE_DIR, 'group-audit');
const ALLOW_FILE = path.join(STATE_DIR, 'group-audit-allow.json');
const STATE_FILE = path.join(STATE_DIR, 'group-audit-state.json');
const FONT_DIR = path.join(STATE_DIR, 'fonts');
const NGINX_DIR = '/var/log/nginx';

const MIN = 60_000;
const DAY = 86_400_000;
const IST_MS = 5.5 * 3600_000;
const STRONG_GAP = 30 * MIN;
const WEAK_GAP = 10 * MIN;
const TIGHT = 5 * MIN;
const CROSS_WINDOW = 120_000;

const args = Object.fromEntries(process.argv.slice(2).map((a) => { const [k, v] = a.replace(/^--/, '').split('='); return [k, v ?? true]; }));
const DRY = Boolean(args.dry);

// ── helpers ──────────────────────────────────────────────────────────────
const istIso = (ms) => new Date(ms + IST_MS).toISOString();
const istDay = (ms) => istIso(ms).slice(0, 10);
const istHm = (ms) => istIso(ms).slice(11, 16);
const istHms = (ms) => istIso(ms).slice(11, 19);
const MON_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MON_GU = ['જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન', 'જુલાઈ', 'ઓગસ્ટ', 'સપ્ટેમ્બર', 'ઓક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર'];
const dEn = (ms) => { const s = istIso(ms); return `${+s.slice(8, 10)} ${MON_EN[+s.slice(5, 7) - 1]}`; };
const dGu = (ms) => { const s = istIso(ms); return `${+s.slice(8, 10)} ${MON_GU[+s.slice(5, 7) - 1]}`; };
const esc = (s) => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const inr = (n) => `${n >= 0 ? '+' : '−'}${Math.abs(Math.round(n)).toLocaleString('en-IN')}`;
const lakh = (n) => `${n >= 0 ? '+' : '−'}${(Math.abs(n) / 1e5).toFixed(1)}L`;
const log = (...a) => console.log(new Date().toISOString(), ...a);

/** App User-Agents carry the phone: "Volt/1.0.53+56 (Android 13; OnePlus IV2201) Dart/3". */
function deviceOf(ua) {
  const m = /^(Volt|Velo)\/\S+ \(([^)]+)\)/.exec(ua || '');
  if (m) return { key: `${m[1]} app · ${m[2]}`, label: m[2], strong: true };
  if (!ua || /^Dart\//.test(ua)) return null; // bare Dart client: no model, can't tell phones apart
  const what = /iPhone/.test(ua) ? 'iPhone browser' : /Android/.test(ua) ? 'Android browser' : /Windows/.test(ua) ? 'Windows PC browser' : /Mac OS/.test(ua) ? 'Mac browser' : 'browser';
  return { key: `browser · ${ua}`, label: what, strong: false };
}

// ── nginx: IP + User-Agent of every POST /api/trade in the period ────────
function readNginxPosts(fromMs, toMs) {
  const sudo = (cmd, file) => execFileSync('sudo', ['-n', cmd, file], { timeout: 60_000, maxBuffer: 512 * 1024 * 1024 });
  let files = [];
  try { files = execFileSync('sudo', ['-n', 'ls', NGINX_DIR]).toString().split('\n').filter((f) => /^access\.log/.test(f)); } catch (e) { log('nginx log not readable:', e.message); return { posts: new Map(), coveredFrom: null }; }
  const firstDay = istDay(fromMs - DAY).replace(/-/g, '');
  const pick = files.filter((f) => f === 'access.log' || (/-(\d{8})/.exec(f) || [])[1] >= firstDay);
  const MON = { Jan: 0, Feb: 1, Mar: 2, Apr: 3, May: 4, Jun: 5, Jul: 6, Aug: 7, Sep: 8, Oct: 9, Nov: 10, Dec: 11 };
  const re = /^(\S+) \S+ \S+ \[(\d+)\/(\w+)\/(\d+):(\d+):(\d+):(\d+) \+0000\] "POST \/api\/trade HTTP[^"]*" (\d+) \d+ "[^"]*" "([^"]*)"/;
  const posts = new Map(); // second -> [{ip, ua}]
  let first = Infinity;
  for (const f of pick) {
    let buf;
    try { buf = /\.gz$/.test(f) ? zlib.gunzipSync(sudo('cat', path.join(NGINX_DIR, f))) : sudo('cat', path.join(NGINX_DIR, f)); } catch (e) { log('skip', f, e.message); continue; }
    for (const line of buf.toString().split('\n')) {
      if (!line.includes('POST /api/trade ')) continue;
      const x = re.exec(line); if (!x) continue;
      const t = Date.UTC(+x[4], MON[x[3]], +x[2], +x[5], +x[6], +x[7]);
      if (t < fromMs - MIN || t > toMs + MIN) continue;
      first = Math.min(first, t);
      const s = t / 1000;
      if (!posts.has(s)) posts.set(s, []);
      posts.get(s).push({ ip: x[1], ua: x[9] });
    }
  }
  return { posts, coveredFrom: Number.isFinite(first) ? first : null };
}

// ── main analysis ────────────────────────────────────────────────────────
async function analyse(fromMs, toMs) {
  const db = mongoose.connection.db;
  const [users, masters] = await Promise.all([
    db.collection('users').find({}).project({ username: 1, name: 1, master_id: 1, deleted_at: 1 }).toArray(),
    db.collection('masters').find({}).project({ username: 1, name: 1, master_id: 1 }).toArray(),
  ]);
  const M = new Map(masters.map((m) => [String(m._id), m]));
  const U = new Map(users.map((u) => [String(u._id), u]));
  const masterPath = (mid) => { const out = []; let cur = M.get(String(mid)); let guard = 0; while (cur && guard++ < 10) { out.unshift(cur.name || cur.username); cur = cur.master_id ? M.get(String(cur.master_id)) : null; } return out.join(' › '); };
  const node = (model, id) => `${model === 'Master' ? 'M' : 'U'}:${id}`;
  const info = (n) => {
    const [k, id] = n.split(':');
    if (k === 'U') { const u = U.get(id) || {}; return { kind: 'client', username: u.username || id, name: u.name || '', master: masterPath(u.master_id), masterId: String(u.master_id || '') }; }
    const m = M.get(id) || {}; return { kind: 'master', username: m.username || id, name: m.name || '', master: masterPath(m.master_id), masterId: String(m.master_id || '') };
  };

  const from = new Date(fromMs); const to = new Date(toMs);
  const logins = await db.collection('loginhistories').find({ createdAt: { $gte: from, $lte: to }, userModel: { $in: ['User', 'Master'] } }).project({ userId: 1, userModel: 1, ip_address: 1, user_agent: 1, createdAt: 1 }).toArray();
  const orders = await db.collection('trades').find({ createdAt: { $gte: from, $lte: to }, placed_by: 'USER', trade_type: { $ne: 'carry_forward' }, rollover_group_id: null })
    .project({ user_id: 1, instrument_token: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, price: 1, status: 1, createdAt: 1, executed_at: 1 }).toArray();
  const pnlRows = await db.collection('trades').aggregate([
    { $match: { status: 'completed', executed_at: { $gte: from, $lte: to } } },
    { $group: { _id: '$user_id', pnl: { $sum: { $ifNull: ['$pnl', 0] } }, brk: { $sum: { $ifNull: ['$brokerage', 0] } } } },
  ]).toArray();
  const pnl = new Map(pnlRows.map((r) => [String(r._id), r]));

  // events: {n, t, ip, dev, kind, order?}
  const events = [];
  for (const l of logins) {
    const dev = deviceOf(l.user_agent); if (!dev || !l.ip_address) continue;
    events.push({ n: node(l.userModel, l.userId), t: new Date(l.createdAt).getTime(), ip: l.ip_address, dev, kind: 'login' });
  }
  const { posts, coveredFrom } = readNginxPosts(fromMs, toMs);
  let matched = 0;
  for (const o of orders) {
    const c = new Date(o.createdAt).getTime(); const s0 = Math.floor(c / 1000);
    const cand = []; for (let s = s0 - 1; s <= s0 + 3; s++) cand.push(...(posts.get(s) || []));
    const keys = new Set(cand.map((p) => `${p.ip}|${p.ua}`));
    if (keys.size !== 1) continue;
    const p = cand[0]; const dev = deviceOf(p.ua); if (!dev) continue;
    matched++;
    events.push({ n: node('User', o.user_id), t: c, ip: p.ip, dev, kind: 'order', order: o });
  }

  // An order is tied to a device through the nginx log by the second; a slow
  // request is logged late and can pick up another account's request (dry
  // run 6 Nov: KALP's one order "from" a Samsung that only HGHA123 used
  // chained five unrelated accounts). So a device counts for an account
  // only if it has a login from it, or 2+ orders from it, in the period.
  const perDev = new Map();
  for (const e of events) { const k = `${e.n}|${e.dev.key}`; const v = perDev.get(k) || { login: 0, order: 0 }; v[e.kind]++; perDev.set(k, v); }
  const trusted = events.filter((e) => { const v = perDev.get(`${e.n}|${e.dev.key}`); return v.login > 0 || v.order >= 2; });
  events.length = 0; events.push(...trusted);

  // sessions per (ip, device): events no further apart than the gap
  const buckets = new Map();
  for (const e of events) { const k = `${e.ip}|${e.dev.key}`; if (!buckets.has(k)) buckets.set(k, []); buckets.get(k).push(e); }
  const sessions = [];
  for (const list of buckets.values()) {
    list.sort((a, b) => a.t - b.t);
    const gap = list[0].dev.strong ? STRONG_GAP : WEAK_GAP;
    let cur = [list[0]];
    const flush = () => { if (new Set(cur.map((e) => e.n)).size >= 2) sessions.push(cur); };
    for (let i = 1; i < list.length; i++) { if (list[i].t - list[i - 1].t > gap) { flush(); cur = []; } cur.push(list[i]); }
    flush();
  }

  // edges between accounts seen in one session
  const edges = new Map();
  for (const s of sessions) {
    const nodes = [...new Set(s.map((e) => e.n))];
    for (let i = 0; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) {
      const a = s.filter((e) => e.n === nodes[i]); const b = s.filter((e) => e.n === nodes[j]);
      let best = Infinity; for (const x of a) for (const y of b) best = Math.min(best, Math.abs(x.t - y.t));
      const k = [nodes[i], nodes[j]].sort().join('|');
      if (!edges.has(k)) edges.set(k, { days: new Set(), sessions: 0, close: false, strong: false });
      const ed = edges.get(k); ed.days.add(istDay(s[0].t)); ed.sessions++; if (s[0].dev.strong) ed.strong = true;
      // one session is enough only when it's unmistakable: within 5 min and
      // either 3+ accounts on the device or 2+ actions by each of the two
      if (best <= TIGHT && (nodes.length >= 3 || (a.length >= 2 && b.length >= 2))) ed.close = true;
    }
  }
  const parent = new Map(); const find = (x) => { while (parent.get(x) !== x) { parent.set(x, parent.get(parent.get(x))); x = parent.get(x); } return x; };
  const union = (a, b) => { for (const x of [a, b]) if (!parent.has(x)) parent.set(x, x); parent.set(find(a), find(b)); };
  for (const [k, e] of edges) { const ok = e.strong ? (e.sessions >= 2 || e.close) : e.days.size >= 2; if (ok) { const [a, b] = k.split('|'); union(a, b); } }
  const comps = new Map(); for (const x of parent.keys()) { const r = find(x); if (!comps.has(r)) comps.set(r, []); comps.get(r).push(x); }

  // completed own orders of every account (for cross trades / split book)
  const ownDone = orders.filter((o) => o.status === 'completed');
  const groups = [];
  for (const members of comps.values()) {
    if (members.length < 2) continue;
    const set = new Set(members);
    const gs = sessions.filter((s) => s.filter((e) => set.has(e.n)).map((e) => e.n).filter((v, i, a) => a.indexOf(v) === i).length >= 2)
      .map((s) => s.filter((e) => set.has(e.n)));
    const devices = [...new Set(gs.map((s) => s[0].dev.label))];
    const strong = gs.some((s) => s[0].dev.strong);
    const rot = gs.filter((s) => new Set(s.filter((e) => e.kind === 'order').map((e) => e.n)).size >= 2);
    const devOrders = new Map(); for (const s of gs) for (const e of s) if (e.kind === 'order') devOrders.set(e.n, (devOrders.get(e.n) || 0) + 1);
    const devLogins = new Map(); for (const s of gs) for (const e of s) if (e.kind === 'login') devLogins.set(e.n, (devLogins.get(e.n) || 0) + 1);
    const uids = members.filter((n) => n.startsWith('U:')).map((n) => n.slice(2));
    const mine = ownDone.filter((o) => uids.includes(String(o.user_id))).map((o) => ({ ...o, ts: new Date(o.executed_at || o.createdAt).getTime() })).sort((a, b) => a.ts - b.ts);
    const cross = [];
    for (let i = 0; i < mine.length; i++) for (let j = i + 1; j < mine.length && mine[j].ts - mine[i].ts <= CROSS_WINDOW; j++) {
      const a = mine[i]; const b = mine[j];
      if (String(a.user_id) === String(b.user_id) || a.instrument_token !== b.instrument_token || a.transaction_type === b.transaction_type) continue;
      if (Math.abs(a.quantity - b.quantity) <= 0.2 * Math.max(a.quantity, b.quantity)) cross.push([a, b]);
    }
    const split = new Map();
    for (const o of mine) { const k = `${istDay(o.ts)}|${o.tradingsymbol}|${o.transaction_type}`; if (!split.has(k)) split.set(k, new Set()); split.get(k).add(String(o.user_id)); }
    const splitHits = [...split].filter(([, s]) => s.size >= 2).map(([k, s]) => ({ day: k.split('|')[0], sym: k.split('|')[1], side: k.split('|')[2], n: s.size }));
    const accounts = members.map((n) => ({ n, ...info(n), logins: devLogins.get(n) || 0, orders: devOrders.get(n) || 0, pnl: n.startsWith('U:') ? (pnl.get(n.slice(2))?.pnl || 0) : null, brk: n.startsWith('U:') ? (pnl.get(n.slice(2))?.brk || 0) : null }))
      .sort((a, b) => (b.orders + b.logins) - (a.orders + a.logins));
    const first = (s) => String(s || '').trim().split(/\s+/)[0].toUpperCase();
    const sameName = accounts.length === 2 && first(accounts[0].name) && first(accounts[0].name) === first(accounts[1].name);
    const days = new Set(gs.map((s) => istDay(s[0].t)));
    const sig = accounts.map((a) => a.username).sort().join(',');
    const score = cross.length * 10 + accounts.length * 3 + rot.length * 2 + days.size + (strong ? 3 : 0);
    groups.push({ sig, accounts, sessions: gs, rot, cross, splitHits, devices, strong, days, sameName, score,
      totPnl: accounts.reduce((s, a) => s + (a.pnl || 0), 0), totBrk: accounts.reduce((s, a) => s + (a.brk || 0), 0),
      masters: [...new Set(accounts.map((a) => a.master))] });
  }
  groups.sort((a, b) => b.score - a.score);
  return { groups, stats: { users: users.filter((u) => !u.deleted_at).length, orders: orders.length, logins: logins.length, matched, coveredFrom } };
}

function decide(groups, allow) {
  const allowed = (g) => (allow.groups || []).some((set) => g.accounts.every((a) => set.map(String).includes(String(a.username))));
  const report = []; const skipped = { allow: [], sameName: [] };
  for (const g of groups) {
    if (g.accounts.filter((a) => a.kind === 'client').length < 2) continue; // masters sharing an office PC: not client group trading
    if (allowed(g)) { skipped.allow.push(g); continue; }
    if (g.cross.length) { report.push(g); continue; }
    if (g.sameName) { skipped.sameName.push(g); continue; }
    if (g.accounts.length >= 3 || (g.strong && (g.rot.length >= 1 || g.days.size >= 2)) || g.days.size >= 3) report.push(g);
  }
  return { report, skipped };
}

// ── documents ────────────────────────────────────────────────────────────
function fontCss() {
  const f = (n) => { const p = path.join(FONT_DIR, n); return fs.existsSync(p) ? fs.readFileSync(p).toString('base64') : null; };
  const r = f('NotoSansGujarati-Regular.ttf'); const b = f('NotoSansGujarati-Bold.ttf');
  return (r ? `@font-face{font-family:'Guj';src:url(data:font/ttf;base64,${r});font-weight:400}` : '') + (b ? `@font-face{font-family:'Guj';src:url(data:font/ttf;base64,${b});font-weight:700}` : '');
}
const CSS = `@page{size:A4;margin:13mm 12mm}body{font-family:'Guj','Noto Sans','DejaVu Sans',Arial,sans-serif;font-size:10pt;color:#1e293b;line-height:1.5}
h1{font-size:16pt;margin:0}.brand{float:right;font-size:17pt;font-weight:700}.sub{color:#64748b;font-size:8.5pt;margin:2px 0 10px}
h2{font-size:12pt;margin:14px 0 6px;padding:3px 8px;background:#1e293b;color:#fff;border-radius:3px}h3{font-size:10.5pt;margin:10px 0 4px}
table{border-collapse:collapse;width:100%;margin:4px 0 8px;font-size:8.5pt}tr{page-break-inside:avoid}thead{display:table-header-group}
th{background:#e2e8f0;text-align:left;padding:3px 5px;border:1px solid #94a3b8}td{padding:2px 5px;border:1px solid #cbd5e1;vertical-align:top}
.box{border:1.5px solid #b91c1c;background:#fef2f2;padding:6px 9px;border-radius:4px}.note{border:1px solid #94a3b8;background:#f8fafc;padding:6px 9px;border-radius:4px;font-size:9pt}
.tot td{font-weight:700;background:#f1f5f9}ul{margin:3px 0;padding-left:18px}.grp{page-break-before:always}.tag{display:inline-block;padding:0 6px;border-radius:3px;background:#fde68a;font-size:8pt;font-weight:700}`;

const T = {
  en: {
    title: 'Weekly group-trading audit', period: 'Period', made: 'Prepared', ist: 'all times IST',
    summary: 'Summary', none: 'Nothing worth checking this week.',
    found: (n) => `${n} group${n === 1 ? '' : 's'} worth checking — accounts that are run from one device.`,
    scanned: (s) => `Checked ${s.users} clients, ${s.logins} logins and ${s.orders} client orders (${s.matched} matched to their device).`,
    group: (i, g) => `Group ${i}: ${g.accounts.length} accounts`, isNew: 'NEW', again: 'also last week',
    acc: 'Account', master: 'Master', lg: 'Logins from shared device', od: 'Orders from shared device', pl: 'P&L (week)', brk: 'Brokerage', total: 'Total',
    ev: 'Evidence', dev: (d) => `Shared device: ${d}`,
    sess: (n, d) => `Seen together ${n} time${n === 1 ? '' : 's'} (same device + same IP), on ${d} different day${d === 1 ? '' : 's'}.`,
    rot: (n) => `Orders for different accounts from the same device within minutes: ${n} time${n === 1 ? '' : 's'}.`,
    cross: (n) => `Cross trades inside the group (one buys while another sells the same script, similar qty, within 2 min): ${n}.`,
    split: (n) => `Same script and side traded by 2+ accounts of the group on the same day: ${n} time${n === 1 ? '' : 's'}.`,
    spans: (n) => `Accounts are under ${n} different masters.`,
    sessT: 'When they were seen together', sTime: 'Time', sDev: 'Device', sIp: 'IP', sSeq: 'Accounts, in order (L = login, O = order)',
    crossT: 'Cross trades', ctTime: 'Time', ctA: 'Account A', ctB: 'Account B',
    notes: 'How to read this', n1: 'An IP alone proves nothing (mobile IPs are shared). A link needs the same device + the same IP close together, more than once or within minutes.',
    n2: 'This shows that accounts are operated from one device. It does not show who holds the device — it may be a dealer or office phone. Check with the master before acting.',
    skipped: (a, b) => `Not listed: ${a} pair${a === 1 ? '' : 's'} with matching names (same person, e.g. "KUNAL" / "KUNAL INDEX")${b ? `, ${b} known group${b === 1 ? '' : 's'} on the allow list` : ''}.`,
    logGap: (d) => `Order-device data available from ${d} (server log kept 10 days).`,
  },
  gu: {
    title: 'સાપ્તાહિક ગ્રુપ-ટ્રેડિંગ તપાસ', period: 'સમયગાળો', made: 'તારીખ', ist: 'તમામ સમય ભારતીય સમય (IST)',
    summary: 'સારાંશ', none: 'આ અઠવાડિયે તપાસવા જેવું કંઈ મળ્યું નથી.',
    found: (n) => `${n} ગ્રુપ તપાસવા જેવા મળ્યા — એવાં ખાતાં જે એક જ ડિવાઇસ પરથી ચલાવવામાં આવે છે.`,
    scanned: (s) => `${s.users} ક્લાયન્ટ, ${s.logins} લોગિન અને ${s.orders} ક્લાયન્ટ ઓર્ડર તપાસ્યા (${s.matched} ઓર્ડર તેમના ડિવાઇસ સાથે મેળવ્યા).`,
    group: (i, g) => `ગ્રુપ ${i}: ${g.accounts.length} ખાતાં`, isNew: 'નવું', again: 'ગયા અઠવાડિયે પણ',
    acc: 'ખાતું', master: 'માસ્ટર', lg: 'એ જ ડિવાઇસ પરથી લોગિન', od: 'એ જ ડિવાઇસ પરથી ઓર્ડર', pl: 'નફો / નુકસાન (અઠવાડિયું)', brk: 'બ્રોકરેજ', total: 'કુલ',
    ev: 'પુરાવા', dev: (d) => `એક જ ડિવાઇસ: ${d}`,
    sess: (n, d) => `એક જ ડિવાઇસ + એક જ IP પરથી ${n} વખત સાથે જોવા મળ્યા, ${d} જુદા દિવસે.`,
    rot: (n) => `એક જ ડિવાઇસ પરથી થોડી મિનિટોમાં જુદાં ખાતાંમાં ઓર્ડર: ${n} વખત.`,
    cross: (n) => `ગ્રુપની અંદર સામસામે ટ્રેડ (એક ખાતું ખરીદે, બીજું એ જ સ્ક્રિપ્ટ લગભગ એ જ જથ્થામાં 2 મિનિટમાં વેચે): ${n}.`,
    split: (n) => `એક જ દિવસે એક જ સ્ક્રિપ્ટ અને એક જ બાજુ ગ્રુપના 2+ ખાતાંમાં: ${n} વખત.`,
    spans: (n) => `આ ખાતાં ${n} જુદા માસ્ટર હેઠળ છે.`,
    sessT: 'ક્યારે સાથે જોવા મળ્યા', sTime: 'સમય', sDev: 'ડિવાઇસ', sIp: 'IP', sSeq: 'ખાતાં, ક્રમમાં (L = લોગિન, O = ઓર્ડર)',
    crossT: 'સામસામે ટ્રેડ', ctTime: 'સમય', ctA: 'ખાતું A', ctB: 'ખાતું B',
    notes: 'આ રિપોર્ટ કેવી રીતે વાંચવો', n1: 'ફક્ત IP પુરાવો નથી (મોબાઇલ IP ઘણા લોકો વચ્ચે વહેંચાયેલા હોય છે). જોડાણ માટે એક જ ડિવાઇસ + એક જ IP નજીકના સમયે, એકથી વધુ વખત અથવા થોડી મિનિટોમાં, જરૂરી છે.',
    n2: 'આ બતાવે છે કે ખાતાં એક જ ડિવાઇસ પરથી ચાલે છે. ડિવાઇસ કોની પાસે છે તે બતાવતું નથી — તે ડીલર કે ઓફિસનો ફોન પણ હોઈ શકે. પગલાં લેતાં પહેલાં માસ્ટર સાથે ચકાસો.',
    skipped: (a, b) => `યાદીમાં નથી: મળતાં નામવાળી ${a} જોડી (એક જ વ્યક્તિ, દા.ત. "KUNAL" / "KUNAL INDEX")${b ? `, મંજૂર યાદીમાંના ${b} જાણીતા ગ્રુપ` : ''}.`,
    logGap: (d) => `ઓર્ડર-ડિવાઇસ ડેટા ${d} થી ઉપલબ્ધ (સર્વર લોગ 10 દિવસ રહે છે).`,
  },
};

function buildHtml(lang, res, fromMs, toMs, prev) {
  const t = T[lang]; const d = lang === 'gu' ? dGu : dEn;
  const { report, skipped } = res.decision;
  const head = `<div class="brand">VOLT</div><h1>${t.title}</h1><div class="sub">${t.period}: ${d(fromMs)} – ${d(toMs)} ${istIso(toMs).slice(0, 4)} &nbsp;|&nbsp; ${t.ist} &nbsp;|&nbsp; ${t.made}: ${d(Date.now())} ${istHm(Date.now())}</div>`;
  const summary = `<h2>${t.summary}</h2><div class="${report.length ? 'box' : 'note'}">${report.length ? t.found(report.length) : t.none}</div>
    <ul>${report.map((g, i) => `<li><b>${t.group(i + 1, g)}</b> ${prev.has(g.sig) ? `(${t.again})` : `<span class="tag">${t.isNew}</span>`} — ${esc(g.masters.join('; '))} — ${esc(g.devices.join(', '))} — ${t.pl}: ${inr(g.totPnl)}${g.cross.length ? ` — <b>${t.crossT}: ${g.cross.length}</b>` : ''}</li>`).join('')}</ul>
    <p style="font-size:9pt;color:#475569">${t.scanned(res.stats)}${res.stats.coveredFrom && res.stats.coveredFrom > fromMs + DAY ? ' ' + t.logGap(d(res.stats.coveredFrom)) : ''}<br>${(skipped.sameName.length || skipped.allow.length) ? t.skipped(skipped.sameName.length, skipped.allow.length) : ''}</p>
    <div class="note"><b>${t.notes}</b><ul><li>${t.n1}</li><li>${t.n2}</li></ul></div>`;
  const body = report.map((g, i) => {
    const rows = g.accounts.map((a) => `<tr><td>${esc(a.username)} ${esc(a.name)}${a.kind === 'master' ? ' (master)' : ''}</td><td>${esc(a.master)}</td><td>${a.logins}</td><td>${a.orders}</td><td>${a.pnl == null ? '—' : inr(a.pnl)}</td><td>${a.brk == null ? '—' : inr(a.brk).replace('+', '')}</td></tr>`).join('');
    const tot = `<tr class="tot"><td>${t.total}</td><td></td><td>${g.accounts.reduce((s, a) => s + a.logins, 0)}</td><td>${g.accounts.reduce((s, a) => s + a.orders, 0)}</td><td>${inr(g.totPnl)}</td><td>${inr(g.totBrk).replace('+', '')}</td></tr>`;
    const nm = (n) => { const a = g.accounts.find((x) => x.n === n); return a ? `${a.username} ${a.name}` : n; };
    const sess = g.sessions.slice().sort((a, b) => a[0].t - b[0].t).map((s) => {
      const seq = []; for (const e of s) { const lab = `${nm(e.n)} ${e.kind === 'login' ? 'L' : 'O'}`; if (seq[seq.length - 1]?.lab !== lab) seq.push({ lab, k: 1 }); else seq[seq.length - 1].k++; }
      return `<tr><td>${d(s[0].t)} ${istHms(s[0].t)}–${istHm(s[s.length - 1].t)}</td><td>${esc(s[0].dev.label)}</td><td>${esc(s[0].ip)}</td><td>${seq.map((x) => esc(x.lab) + (x.k > 1 ? `×${x.k}` : '')).join(' → ')}</td></tr>`;
    }).join('');
    const cross = g.cross.slice(0, 30).map(([a, b]) => `<tr><td>${d(a.ts)} ${istHms(a.ts)}</td><td>${esc(nm('U:' + a.user_id))}: ${a.transaction_type} ${a.quantity} ${esc(a.tradingsymbol)} @ ${a.price}</td><td>${esc(nm('U:' + b.user_id))}: ${b.transaction_type} ${b.quantity} ${esc(b.tradingsymbol)} @ ${b.price} (${istHms(b.ts)})</td></tr>`).join('');
    return `<div class="grp"><h2>${t.group(i + 1, g)} ${prev.has(g.sig) ? `(${t.again})` : `<span class="tag">${t.isNew}</span>`}</h2>
      <table><thead><tr><th>${t.acc}</th><th>${t.master}</th><th>${t.lg}</th><th>${t.od}</th><th>${t.pl}</th><th>${t.brk}</th></tr></thead><tbody>${rows}${tot}</tbody></table>
      <h3>${t.ev}</h3><ul><li>${esc(t.dev(g.devices.join(', ')))}</li><li>${t.sess(g.sessions.length, g.days.size)}</li><li>${t.rot(g.rot.length)}</li>
      ${g.cross.length ? `<li><b>${t.cross(g.cross.length)}</b></li>` : ''}${g.splitHits.length ? `<li>${t.split(g.splitHits.length)}</li>` : ''}${g.masters.length > 1 ? `<li>${t.spans(g.masters.length)}</li>` : ''}</ul>
      ${cross ? `<h3>${t.crossT}</h3><table><thead><tr><th>${t.ctTime}</th><th>${t.ctA}</th><th>${t.ctB}</th></tr></thead><tbody>${cross}</tbody></table>` : ''}
      <h3>${t.sessT}</h3><table><thead><tr><th>${t.sTime}</th><th>${t.sDev}</th><th>${t.sIp}</th><th>${t.sSeq}</th></tr></thead><tbody>${sess}</tbody></table></div>`;
  }).join('');
  return `<!doctype html><html lang="${lang}"><head><meta charset="utf-8"><style>${fontCss()}${CSS}</style></head><body>${head}${summary}${body}</body></html>`;
}

async function toPdf(htmls) {
  const puppeteer = require(path.join(APP, 'node_modules', 'puppeteer'));
  const browser = await puppeteer.launch({ headless: 'new', args: ['--no-sandbox', '--disable-dev-shm-usage', '--disable-gpu'] });
  try {
    const out = [];
    for (const h of htmls) { const page = await browser.newPage(); await page.setContent(h, { waitUntil: 'load' }); out.push(await page.pdf({ format: 'A4', printBackground: true })); await page.close(); }
    return out;
  } finally { await browser.close(); }
}

// ── Telegram ─────────────────────────────────────────────────────────────
function tg(method, fields, file) {
  return new Promise((resolve, reject) => {
    const b = `----ga${Date.now().toString(16)}`; const CRLF = '\r\n';
    const parts = Object.entries(fields).map(([k, v]) => Buffer.from(`--${b}${CRLF}Content-Disposition: form-data; name="${k}"${CRLF}${CRLF}${v}${CRLF}`));
    if (file) parts.push(Buffer.from(`--${b}${CRLF}Content-Disposition: form-data; name="document"; filename="${file.name}"${CRLF}Content-Type: application/pdf${CRLF}${CRLF}`), file.data, Buffer.from(CRLF));
    parts.push(Buffer.from(`--${b}--${CRLF}`));
    const body = Buffer.concat(parts);
    const req = https.request({ hostname: 'api.telegram.org', path: `/bot${process.env.TELEGRAM_BOT_TOKEN}/${method}`, method: 'POST', timeout: 60_000,
      headers: { 'Content-Type': `multipart/form-data; boundary=${b}`, 'Content-Length': body.length } }, (res) => {
      let d = ''; res.on('data', (c) => { d += c; }); res.on('end', () => (res.statusCode === 200 ? resolve() : reject(new Error(`Telegram ${res.statusCode}: ${d.slice(0, 200)}`))));
    });
    req.on('timeout', () => req.destroy(new Error('Telegram timeout'))); req.on('error', reject); req.end(body);
  });
}

function message(res, fromMs, toMs, prev) {
  const { report, skipped } = res.decision;
  const L = [`🔎 <b>Weekly group-trading audit</b> — ${dEn(fromMs)} – ${dEn(toMs)}`, ''];
  if (!report.length) L.push('Nothing worth checking this week.');
  else {
    L.push(`<b>${report.length} group${report.length === 1 ? '' : 's'} worth checking</b> (accounts run from one device):`);
    report.slice(0, 8).forEach((g, i) => L.push(`${i + 1}. ${prev.has(g.sig) ? '' : '🆕 '}${g.accounts.length} accounts — ${esc(g.masters.join('; '))}\n    ${esc(g.devices.join(', '))} · seen together ${g.sessions.length}× on ${g.days.size} day${g.days.size === 1 ? '' : 's'} · rotation ${g.rot.length}×${g.cross.length ? ` · <b>cross trades ${g.cross.length}</b>` : ''} · P&amp;L ${lakh(g.totPnl)}`));
    if (report.length > 8) L.push(`…and ${report.length - 8} more in the PDF.`);
  }
  L.push('', `Checked ${res.stats.users} clients, ${res.stats.logins} logins, ${res.stats.orders} orders.`);
  if (skipped.sameName.length) L.push(`Not listed: ${skipped.sameName.length} same-name pair${skipped.sameName.length === 1 ? '' : 's'} (${esc(skipped.sameName.slice(0, 3).map((g) => g.accounts.map((a) => a.name).join(' / ')).join(', '))}).`);
  if (report.length) L.push('Full details: PDFs below (English + ગુજરાતી).');
  return L.join('\n');
}

// ── run ──────────────────────────────────────────────────────────────────
(async () => {
  const underPm2 = process.env.pm_id != null;
  const nowIst = new Date(Date.now() + IST_MS);
  const state = fs.existsSync(STATE_FILE) ? JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')) : { runs: [] };
  if (underPm2) {
    const hm = nowIst.toISOString().slice(11, 16);
    if (nowIst.getUTCDay() !== 6 || hm < '08:55' || hm > '10:00') { log('not the Saturday 09:00 slot — nothing to do'); return; }
    if ((state.runs || []).some((r) => r.day === istDay(Date.now()))) { log('already ran today'); return; }
  }
  const toMs = args.to ? Date.parse(args.to) : Date.now();
  const fromMs = toMs - Number(args.days || 7) * DAY;
  await mongoose.connect(process.env.MONGO_URI, { maxPoolSize: 2 });
  try {
    const res = await analyse(fromMs, toMs);
    const allow = fs.existsSync(ALLOW_FILE) ? JSON.parse(fs.readFileSync(ALLOW_FILE, 'utf8')) : { groups: [] };
    res.decision = decide(res.groups, allow);
    const last = (state.runs || []).slice(-1)[0];
    const prev = new Set(last ? last.sigs : []);
    const msg = message(res, fromMs, toMs, prev);
    const stamp = istDay(toMs);
    const docs = res.decision.report.length ? await toPdf([buildHtml('en', res, fromMs, toMs, prev), buildHtml('gu', res, fromMs, toMs, prev)]) : [];
    fs.mkdirSync(OUT_DIR, { recursive: true });
    fs.writeFileSync(path.join(OUT_DIR, `${stamp}-message.txt`), msg);
    const names = [`group-audit-${stamp}-English.pdf`, `group-audit-${stamp}-Gujarati.pdf`];
    docs.forEach((d, i) => fs.writeFileSync(path.join(OUT_DIR, names[i]), d));
    log(`groups found ${res.groups.length}, reported ${res.decision.report.length}, skipped same-name ${res.decision.skipped.sameName.length}, allow ${res.decision.skipped.allow.length}; orders matched ${res.stats.matched}/${res.stats.orders}`);
    if (DRY || !process.env.TELEGRAM_BOT_TOKEN || !process.env.TELEGRAM_CHAT_ID) { log('dry run — files in', OUT_DIR); console.log(msg); return; }
    await tg('sendMessage', { chat_id: process.env.TELEGRAM_CHAT_ID, text: msg, parse_mode: 'HTML', disable_web_page_preview: 'true' });
    for (let i = 0; i < docs.length; i++) await tg('sendDocument', { chat_id: process.env.TELEGRAM_CHAT_ID, caption: i ? 'ગુજરાતી રિપોર્ટ' : 'English report' }, { name: names[i], data: docs[i] });
    state.runs = [...(state.runs || []), { day: istDay(Date.now()), from: fromMs, to: toMs, sigs: res.decision.report.map((g) => g.sig) }].slice(-20);
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 1));
    log('sent');
  } finally {
    await mongoose.disconnect();
  }
})().catch((e) => { console.error(e); process.exitCode = 1; });
