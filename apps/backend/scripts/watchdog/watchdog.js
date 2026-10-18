#!/usr/bin/env node
'use strict';

/**
 * Health watchdog — a separate pm2 process (`health-watchdog`), never inside
 * the trading backend, so it can't slow it down or take it down. READ-ONLY:
 * it reads pm2 state, the backend + nginx logs, the server, and the database,
 * and sends alerts / summaries to Telegram (telegram.js; dry mode without a
 * token). Every 30 s (events every 5 s):
 *
 *   server   backend down / restarted / crash-loop, memory, CPU, disk, RAM,
 *            the public API answering, database ping
 *   logs     database errors, unhandled errors, Kite feed problems, stale
 *            ticks, orphans, any other backend error (new kinds flagged)
 *   nginx    bursts of 5xx, secret-file probes that got an answer, floods
 *   events   web/app order blocks + crashes + failed requests (ClientEvent),
 *            failed logins (LoginAttempt), admin logins from a new IP,
 *            EVERY rejected or blocked order (server, app, web, internal
 *            errors) within ~5 s, grouped per check,
 *            margin square-offs, negative wallets, settlement runs
 *   digests  trading-day summaries at 15:45 and 23:35 IST
 *
 * Planned restarts: `scripts/watchdog/maint.sh <minutes>` silences the
 * restart / API / 5xx / database alerts for that long.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const APP = path.resolve(__dirname, '..', '..');
require('dotenv').config({ path: path.join(APP, '.env') });
const { MongoClient, ObjectId } = require(path.join(APP, 'node_modules', 'mongoose')).mongo;
const lib = require('./lib');
const telegram = require('./telegram');
const extra = require('./extra');

const DIR = path.join(os.homedir(), 'watchdog');
const STATE_FILE = path.join(DIR, 'state.json');
const MAINT_FILE = path.join(DIR, 'maintenance-until');
const CYCLE_MS = 30_000;
const EVENT_MS = 5_000;
const API_URL = process.env.WATCHDOG_API_URL || 'https://apexlive-api.mynpe.in/';
const NGINX_LOG = '/var/log/nginx/access.log';
const MIN = 60_000;
const MUTE_STALE_QUOTE = true; // app 25 s stale-price blocks not sent to Telegram (see trades-rejected)

fs.mkdirSync(DIR, { recursive: true });

// ---------------------------------------------------------------- state ----
let state = { sent: {}, active: {}, offsets: {}, last: {}, signatures: {}, digests: {}, restartsAtDayStart: null, day: null, cpuHigh: 0, dbSlow: 0, apiFails: 0, dbFails: 0 };
try { state = { ...state, ...JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')) }; } catch (_) { /* first run */ }
const saveState = () => { try { fs.writeFileSync(STATE_FILE, JSON.stringify(state)); } catch (_) { /* ignore */ } };

const inMaintenance = () => {
  try { return Date.now() < Number(fs.readFileSync(MAINT_FILE, 'utf8').trim()); } catch (_) { return false; }
};

// --------------------------------------------------------------- alerts ----
/** Raise (or keep raising) an alert. `resolvable` alerts send ✅ when cleared. */
function raise(key, severity, title, lines = [], { cooldownMs, resolvable = false, maint = false } = {}) {
  if (maint && inMaintenance()) return;
  if (resolvable) state.active[key] = { severity, title, since: state.active[key]?.since || Date.now() };
  if (lib.shouldSend(state.sent, key, severity, Date.now(), cooldownMs)) telegram.send(lib.formatAlert(severity, title, lines));
}
function clear(key) {
  const a = state.active[key];
  if (!a) return;
  delete state.active[key];
  delete state.sent[key];
  const mins = Math.round((Date.now() - a.since) / MIN);
  telegram.send(lib.formatAlert('resolved', `Resolved: ${a.title}`, [`after ${mins} min`]));
}

// ------------------------------------------------------------ server ----
function pm2List() {
  try { return JSON.parse(execFileSync('pm2', ['jlist'], { timeout: 20000, maxBuffer: 20 * 1024 * 1024 }).toString()); } catch (_) { return null; }
}

function checkBackend(apps) {
  if (!apps) return null;
  const p = apps.find((a) => a.name === 'stocker-backend-node');
  if (!p) {
    raise('backend-missing', 'critical', 'Backend process not found in pm2', [], { resolvable: true });
    return null;
  }
  clear('backend-missing');
  const env = p.pm2_env;
  if (env.status !== 'online') raise('backend-down', 'critical', `Backend is ${env.status}`, ['Trading is unavailable until it is back online.'], { resolvable: true, maint: true });
  else clear('backend-down');

  const restarts = env.restart_time;
  const { ymd } = lib.istParts();
  if (state.day !== ymd) { state.day = ymd; state.restartsAtDayStart = restarts; }
  if (state.lastRestarts != null && restarts > state.lastRestarts) {
    const n = restarts - state.lastRestarts;
    state.restartLog = [...(state.restartLog || []).filter((t) => Date.now() - t < 15 * MIN), ...Array(n).fill(Date.now())];
    if (state.restartLog.length >= 3) raise('crash-loop', 'critical', 'Backend is restarting repeatedly', [`${state.restartLog.length} restarts in 15 min — likely crashing. Check the error log.`]);
    else raise(`restart-${restarts}`, 'warning', 'Backend restarted', ['Apps reconnect within seconds. If this was not a planned deploy, check the error log.'], { maint: true });
  }
  state.lastRestarts = restarts;

  const memMb = Math.round(p.monit.memory / 1048576);
  if (memMb > 1500) raise('backend-mem', 'warning', 'Backend memory high', [`${memMb} MB in use`], { resolvable: true });
  else if (memMb < 1300) clear('backend-mem');
  state.cpuHigh = p.monit.cpu > 90 ? state.cpuHigh + 1 : 0;
  if (state.cpuHigh >= 4) raise('backend-cpu', 'warning', 'Backend CPU high for 2+ minutes', [`${p.monit.cpu}% CPU`], { resolvable: true });
  else if (state.cpuHigh === 0) clear('backend-cpu');
  return env;
}

function checkMachine() {
  const freeMb = Math.round(os.freemem() / 1048576);
  let availMb = freeMb;
  try { availMb = Math.round(Number(/MemAvailable:\s+(\d+)/.exec(fs.readFileSync('/proc/meminfo', 'utf8'))[1]) / 1024); } catch (_) { /* use free */ }
  if (availMb < 300) raise('ram-low', 'warning', 'Server RAM low', [`${availMb} MB available`], { resolvable: true });
  else if (availMb > 500) clear('ram-low');
  try {
    const usedPct = Number(execFileSync('df', ['--output=pcent', '/'], { timeout: 10000 }).toString().split('\n')[1].replace('%', '').trim());
    if (usedPct >= 85) raise('disk-full', 'warning', 'Server disk almost full', [`${usedPct}% used`], { resolvable: true });
    else if (usedPct < 80) clear('disk-full');
  } catch (_) { /* ignore */ }
}

async function checkApi() {
  const started = Date.now();
  let ok = false;
  let detail = '';
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 10000);
    const res = await fetch(API_URL, { signal: ctrl.signal });
    clearTimeout(t);
    ok = res.status === 200;
    detail = `answered ${res.status}`;
  } catch (e) {
    detail = e.name === 'AbortError' ? 'no answer in 10 s' : e.message;
  }
  state.apiFails = ok ? 0 : state.apiFails + 1;
  if (state.apiFails >= 2) raise('api-down', 'critical', 'Public API not responding', [`${API_URL} ${detail}`, 'Apps and web cannot reach the server.'], { resolvable: true, maint: true });
  else if (ok) clear('api-down');
  return Date.now() - started;
}

let mongo = null;
async function db() {
  if (mongo) return mongo.db('stocker');
  mongo = new MongoClient(process.env.MONGO_URI, { maxPoolSize: 3, serverSelectionTimeoutMS: 10000 });
  await mongo.connect();
  return mongo.db('stocker');
}

async function checkDb() {
  const started = Date.now();
  try {
    await (await db()).command({ ping: 1 });
    const ms = Date.now() - started;
    state.dbFails = 0;
    clear('db-down');
    state.dbSlow = ms > 500 ? state.dbSlow + 1 : 0;
    if (state.dbSlow >= 3) raise('db-slow', 'warning', 'Database slow', [`ping ${ms} ms (3 checks in a row over 500 ms)`], { resolvable: true });
    else if (state.dbSlow === 0) clear('db-slow');
    return true;
  } catch (e) {
    state.dbFails++;
    if (state.dbFails >= 2) raise('db-down', 'critical', 'Database not reachable', [String(e.message).replace(/mongodb(\+srv)?:\/\/[^@\s]+@/g, 'mongodb://***@').slice(0, 200)], { resolvable: true, maint: true });
    try { await mongo?.close(); } catch (_) { /* ignore */ }
    mongo = null;
    return false;
  }
}

// ---------------------------------------------------------------- logs ----
/** New text appended to a file since the last cycle (first sight: start at the end). */
function readNew(file, key, { sudo = false } = {}) {
  try {
    const size = sudo
      ? Number(execFileSync('sudo', ['-n', 'stat', '-c', '%s', file], { timeout: 10000 }).toString().trim())
      : fs.statSync(file).size;
    let offset = state.offsets[key];
    if (offset == null || size < offset) offset = offset == null ? size : 0; // first run / rotated
    if (size - offset > 5 * 1024 * 1024) offset = size - 5 * 1024 * 1024; // never read a huge backlog
    state.offsets[key] = size;
    if (size === offset) return '';
    if (sudo) return execFileSync('sudo', ['-n', 'tail', '-c', `+${offset + 1}`, file], { timeout: 20000, maxBuffer: 8 * 1024 * 1024 }).toString().slice(0, size - offset);
    const fd = fs.openSync(file, 'r');
    const buf = Buffer.alloc(size - offset);
    fs.readSync(fd, buf, 0, buf.length, offset);
    fs.closeSync(fd);
    return buf.toString('utf8');
  } catch (_) {
    return '';
  }
}

// Investor (read-only) logins: the login record has no investor flag before
// the 16 Oct 2026 backend change, only the log line "… investor password
// matched" at the same second. Remembered here, matched to logins in checkEvents.
let lastOutLog = null;
function investorLoginNear(ms, model) {
  if (!lastOutLog) return false;
  try {
    const size = fs.statSync(lastOutLog).size;
    const len = Math.min(size, 512 * 1024);
    const fd = fs.openSync(lastOutLog, 'r');
    const buf = Buffer.alloc(len);
    fs.readSync(fd, buf, 0, len, size - len);
    fs.closeSync(fd);
    for (const line of buf.toString('utf8').split('\n')) {
      if (!/investor password matched/i.test(line)) continue;
      if (model && !new RegExp(`\\b${model}\\b`, 'i').test(line)) continue;
      const m = line.match(/(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})/);
      if (m && Math.abs(Date.parse(`${m[1]}Z`) - ms) <= 3000) return true;
    }
  } catch (_) { /* no log — not known */ }
  return false;
}

function browserOf(ua) {
  const u = String(ua || '');
  // app 1.0.51+ sends "Volt/1.0.51+54 (Android 14; samsung SM-A546E) Dart/3"
  const app = u.match(/^(Volt|Apex)\/(\S+)\s*\(([^)]*)\)/);
  if (app) return `${app[1]} app ${app[2]}${app[3] ? ` · ${app[3]}` : ''}`;
  if (/Dart\//.test(u)) return 'Volt app';
  const os = /iPhone|iPad/.test(u) ? 'iPhone' : /Android/.test(u) ? 'Android' : /Windows/.test(u) ? 'Windows' : /Mac OS/.test(u) ? 'Mac' : '';
  const br = /Edg\/(\d+)/.test(u) ? `Edge ${u.match(/Edg\/(\d+)/)[1]}` : /Chrome\/(\d+)/.test(u) ? `Chrome ${u.match(/Chrome\/(\d+)/)[1]}` : /Safari\//.test(u) ? 'Safari' : u.slice(0, 40);
  return [br, os].filter(Boolean).join(' on ');
}

function checkLogs(env) {
  if (!env) return;
  lastOutLog = env.pm_out_log_path || lastOutLog;
  const found = new Map(); // key -> { severity, title, lines[], count, generic }
  for (const [file, isErr] of [[env.pm_out_log_path, false], [env.pm_err_log_path, true]]) {
    for (const line of readNew(file, isErr ? 'err' : 'out').split('\n')) {
      const c = lib.classifyLogLine(line, isErr);
      if (!c) continue;
      const f = found.get(c.key) || { ...c, count: 0, samples: [] };
      f.count++;
      if (f.samples.length < 2) f.samples.push(c.line);
      found.set(c.key, f);
    }
  }
  const { ymd } = lib.istParts();
  const newKinds = [];
  for (const f of found.values()) {
    if (f.generic) {
      const sig = f.key.slice(4);
      const known = state.signatures[sig];
      state.signatures[sig] = { lastSeen: Date.now(), today: (known && known.day === ymd ? known.today : 0) + f.count, day: ymd };
      if (!known) newKinds.push(`${f.count}× ${f.samples[0]}`);
      else if (f.count >= 20) raise(`${f.key}:burst`, 'warning', 'Backend error repeating', [`${f.count}× in 30 s: ${f.samples[0]}`]);
      continue;
    }
    raise(f.key, f.severity, f.title, [`${f.count}× in the last 30 s`, ...f.samples]);
  }
  // All new error kinds of this check in one message.
  if (newKinds.length) telegram.send(lib.formatAlert('warning', `New kind of backend error${newKinds.length > 1 ? ` (${newKinds.length})` : ''}`, newKinds.slice(0, 8)));
  // forget error kinds not seen for 14 days
  for (const [sig, v] of Object.entries(state.signatures)) if (Date.now() - v.lastSeen > 14 * 24 * 60 * MIN) delete state.signatures[sig];
}

function checkNginx() {
  const lines = readNew(NGINX_LOG, 'nginx', { sudo: true }).split('\n');
  let s5 = 0;
  let s429 = 0;
  const paths5 = new Map();
  for (const raw of lines) {
    const l = lib.parseNginxLine(raw);
    if (!l) continue;
    // Order refusals come back 500 for some business rules (High-Low) — each
    // failed order is already reported with its real reason via ServerEvent.
    if (l.status >= 500 && !(l.method === 'POST' && l.path.split('?')[0] === '/api/trade' && l.status === 500)) {
      s5++;
      const p = `${l.method} ${l.path.split('?')[0]} ${l.status}`;
      paths5.set(p, (paths5.get(p) || 0) + 1);
    }
    if (l.status === 429) s429++;
    if (lib.SENSITIVE_PATH.test(l.path) && l.status === 200) {
      raise(`secret-200:${l.path}`, 'critical', 'A secret-file request got an answer', [`${l.ip} ${l.method} ${l.path} -> 200`, 'Check immediately — this path should never be served.']);
    }
  }
  if (s5 >= 5) {
    const top = [...paths5.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([p, n]) => `${n}× ${p}`);
    raise('nginx-5xx', 'critical', `${s5} server errors in 30 s`, top, { maint: true });
  }
  if (s429 >= 300) raise('nginx-429', 'info', 'Request flood blocked by the rate limit', [`${s429} requests refused (429) in 30 s — usually a scanner.`]);
}

// ------------------------------------------------------- database events ----
let names = { users: new Map(), byUsername: new Map(), mastersByUsername: new Map(), adminsByUsername: new Map(), masters: new Map(), admins: new Map(), privileged: new Set(), at: 0 };
async function refreshNames(d) {
  if (Date.now() - names.at < 10 * MIN) return;
  const [users, masters, admins] = await Promise.all([
    d.collection('users').find({}).project({ username: 1, name: 1, master_id: 1 }).toArray(),
    d.collection('masters').find({}).project({ username: 1, name: 1 }).toArray(),
    d.collection('admins').find({}).project({ username: 1 }).toArray(),
  ]);
  names = {
    users: new Map(users.map((u) => [String(u._id), u])),
    byUsername: new Map(users.map((u) => [String(u.username), u])),
    mastersByUsername: new Map(masters.map((m) => [String(m.username), m])),
    adminsByUsername: new Map(admins.map((a) => [String(a.username), a])),
    masters: new Map(masters.map((m) => [String(m._id), m])),
    admins: new Map(admins.map((a) => [String(a._id), a])),
    privileged: new Set([...masters.map((m) => String(m.username)), ...admins.map((a) => String(a.username))]),
    at: Date.now(),
  };
}
function who(id) {
  if (!id) return 'not signed in';
  const u = names.users.get(String(id));
  if (u) {
    const m = names.masters.get(String(u.master_id));
    return `${u.username} ${u.name || ''}${m ? ` [${m.name || m.username}]` : ''}`.trim();
  }
  const m = names.masters.get(String(id));
  return m ? `master ${m.username} ${m.name || ''}`.trim() : String(id);
}

/** [account line, reason line, IP line] for a failed sign-in, in plain words. */
const ipNotes = new Map();
async function explainLoginFailure(d, a) {
  const user = String(a.username || '').trim();
  const client = names.byUsername.get(user);
  const master = names.mastersByUsername.get(user);
  const admin = names.adminsByUsername.get(user);
  const accountId = client?._id || master?._id || admin?._id || null;
  const account = !user ? 'empty username' : client ? who(client._id) : master ? `master ${master.username} ${master.name || ''}`.trim() : admin ? `admin ${admin.username}` : `"${user}" — no such account`;
  const r = String(a.reason || '');
  const reason = !user ? 'no username entered'
    : /invalid credentials/i.test(r) ? (accountId ? 'wrong password' : "username doesn't exist")
    : /password is required/i.test(r) ? 'no password entered'
    : /username is required/i.test(r) ? 'no username entered'
    : /inactive|deactivated|suspended|blocked|disabled/i.test(r) ? `account blocked/inactive (${r})`
    : /totp|2fa|otp/i.test(r) ? 'wrong 2FA code'
    : r || `refused (${a.status})`;
  const key = `${a.ip}|${accountId || ''}`;
  let note = ipNotes.get(key);
  if (!note || Date.now() - note.at > 10 * MIN) {
    const since = new Date(Date.now() - 60 * 24 * 60 * MIN);
    const adminIp = await d.collection('loginhistories').countDocuments({ userModel: 'Admin', ip_address: a.ip, createdAt: { $gte: since } });
    const ownIp = accountId ? await d.collection('loginhistories').countDocuments({ userId: accountId, ip_address: a.ip, createdAt: { $gte: since } }) : 0;
    note = { at: Date.now(), text: adminIp ? 'office/admin IP (admin has logged in from it)' : ownIp ? "this account's usual IP" : accountId ? 'new IP for this account' : 'IP not seen with any admin login' };
    ipNotes.set(key, note);
    if (ipNotes.size > 2000) ipNotes.clear();
  }
  return [account, `Reason: ${reason}`, `From ${a.ip} — ${note.text}`];
}

/** New docs since the last cycle (first run: start from now). */
async function newDocs(d, coll, filter = {}, projection, cursor = coll) {
  const lastKey = `id:${cursor}`;
  if (!state.last[lastKey]) {
    state.last[lastKey] = ObjectId.createFromTime(Math.floor(Date.now() / 1000)).toHexString();
    return [];
  }
  const docs = await d.collection(coll).find({ ...filter, _id: { $gt: new ObjectId(state.last[lastKey]) } }, projection ? { projection } : {}).sort({ _id: 1 }).limit(2000).toArray();
  if (docs.length) state.last[lastKey] = String(docs[docs.length - 1]._id);
  return docs;
}

// short rolling windows in memory (reset on watchdog restart — fine)
const windows = new Map();
function hit(key, windowMs, item) {
  const now = Date.now();
  const list = (windows.get(key) || []).filter((x) => now - x.t < windowMs);
  list.push({ t: now, item });
  windows.set(key, list);
  if (windows.size > 20000) for (const [k, v] of windows) if (!v.length || now - v[v.length - 1].t > 60 * MIN) windows.delete(k);
  return list;
}

async function checkEvents() {
  const d = await db();
  await refreshNames(d);
  // Every refused / blocked order this cycle (server, app, web) -> one message.
  const rejections = [];
  const orderText = (x) => [x.symbol, x.side, x.quantity, x.order_type].filter((v) => v !== undefined && v !== null && v !== '').join(' ');

  // Web / app problems the server never saw as an order.
  for (const e of await newDocs(d, 'clientevents')) {
    const target = e.target_user_id || e.account_id;
    const src = e.source === 'app' ? 'App' : 'Web';
    const ctx = e.context || {};
    if (e.kind === 'order_block' || e.kind === 'order_rejected') {
      const by = e.account_role && e.account_role !== 'user' ? ` (placed by ${e.account_role})` : '';
      rejections.push(`[${src.toLowerCase()}${e.kind === 'order_block' ? ' blocked' : ''}] ${who(target)}${by} · ${orderText(ctx)} · ${e.message}`);
    } else if ((e.kind === 'js_error' || e.kind === 'crash') && /Failed host lookup|SocketException|Connection (refused|reset|closed|timed out)|HandshakeException|Network is unreachable/i.test(e.message || '')) {
      // The phone's connection dropped (no internet / DNS) — not an app crash.
      // App 1.0.51+54 still reports these; newer builds don't.
      continue;
    } else if (e.kind === 'js_error' || e.kind === 'crash') {
      const sig = `ce:${e.source}:${lib.signature(e.message)}`;
      const known = state.signatures[sig];
      state.signatures[sig] = { lastSeen: Date.now(), today: (known?.today || 0) + 1, day: lib.istParts().ymd };
      if (!known) raise(sig, 'warning', `New ${src.toLowerCase()} ${e.kind === 'crash' ? 'crash' : 'error'}`, [`${who(e.account_id)} on ${e.page || '?'}`, e.message, [e.version ? `version ${e.version}` : '', ctx.device ? `phone ${ctx.device}` : ''].filter(Boolean).join(' · ')], { cooldownMs: 24 * 60 * MIN });
      if (hit(`storm:${sig}`, 10 * MIN, e).length >= 10) raise(`storm:${sig}`, 'warning', `${src} error repeating`, [`10+ times in 10 min: ${e.message}`]);
    } else if (e.kind === 'api_error') {
      const list = hit(`apierr:${e.source}`, 5 * MIN, e);
      if (list.length >= 5) {
        const top = new Map();
        for (const x of list) top.set(`${x.item.context?.method || ''} ${x.item.context?.url || ''} ${x.item.code || ''}`, (top.get(`${x.item.context?.method || ''} ${x.item.context?.url || ''} ${x.item.code || ''}`) || 0) + 1);
        raise(`apierr:${e.source}`, 'warning', `${src}: requests failing`, [...top.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([k, n]) => `${n}× ${k.trim()}`), { cooldownMs: 15 * MIN });
      }
    }
  }

  // Failed logins — with whose account it is (or that none exists), the
  // plain reason, and what the IP is (office/admin, the account's usual, new).
  for (const a of await newDocs(d, 'loginattempts')) {
    const user = String(a.username || '').trim();
    const why = await explainLoginFailure(d, a);
    if (user && (a.route === 'admin' || a.route === 'master' || names.privileged.has(user))) {
      raise(`lf-priv:${user}`, 'warning', 'Failed login on an admin/master account', why, { cooldownMs: 15 * MIN });
    }
    const perUser = user ? hit(`lf-user:${user}`, 10 * MIN, a) : [];
    if (perUser.length >= 3) {
      raise(`lf-user:${user}`, 'warning', 'Repeated failed logins', [...why, `${perUser.length} failures in 10 min`], { cooldownMs: 30 * MIN });
    }
    const perIp = hit(`lf-ip:${a.ip}`, 10 * MIN, user);
    const distinct = new Set(perIp.map((x) => x.item).filter(Boolean));
    if (distinct.size >= 3) raise(`lf-ip:${a.ip}`, 'critical', 'Possible password guessing', [`${a.ip} failed on ${distinct.size} accounts in 10 min: ${[...distinct].slice(0, 6).join(', ')}`, why[2]], { cooldownMs: 30 * MIN });
  }

  // Successful logins: investor (read-only) logins; admin from a new IP; success right after failures.
  for (const l of await newDocs(d, 'loginhistories')) {
    if (l.userModel !== 'Admin') {
      const at = new Date(l.createdAt || l._id.getTimestamp()).getTime();
      if (l.investor === true || investorLoginNear(at, l.userModel)) {
        const prev = await d.collection('loginhistories').countDocuments({ userId: l.userId, ip_address: l.ip_address, _id: { $lt: l._id } });
        raise(`investor:${l._id}`, 'warning', `Investor (read-only) login — ${l.userModel === 'Master' ? 'master' : 'client'}`,
          [`${l.userModel === 'Master' ? 'master ' : ''}${l.username} ${l.name || ''}`.trim(), `IP ${l.ip_address || '?'}${prev ? '' : ' (new IP for this account)'} · ${browserOf(l.user_agent)}`],
          { cooldownMs: 0 });
      }
    }
    if (l.userModel === 'Admin') {
      const seen = await d.collection('loginhistories').countDocuments({ userId: l.userId, ip_address: l.ip_address, _id: { $lt: l._id }, createdAt: { $gte: new Date(Date.now() - 60 * 24 * 60 * MIN) } });
      if (!seen) raise(`admin-ip:${l.userId}:${l.ip_address}`, 'warning', 'Admin login from a new IP', [`${l.username} from ${l.ip_address}`, 'If this was not you, change the password now.'], { cooldownMs: 24 * 60 * MIN });
    }
    const fails = await d.collection('loginattempts').countDocuments({ username: l.username, createdAt: { $gte: new Date(Date.now() - 30 * MIN) } });
    if (fails >= 3) raise(`lf-then-ok:${l.username}`, 'warning', 'Login succeeded after several failures', [`${l.username} (${l.userModel}) from ${l.ip_address} after ${fails} failures in 30 min`], { cooldownMs: 60 * MIN });
  }

  // Server refusals saved to the Rejection Log (incl. app-side blocks).
  for (const t of await newDocs(d, 'trades', { status: 'rejected' }, { user_id: 1, tradingsymbol: 1, transaction_type: 1, quantity: 1, order_type: 1, remarks: 1 }, 'trades-rejected')) {
    const remarks = String(t.remarks || '');
    // App 25 s stale-price blocks: muted on Telegram at the user's request
    // (14 Oct 2026) until the app fix ships; still in the Rejection Log and
    // the daily digest counts. Set MUTE_STALE_QUOTE = false to bring back.
    if (MUTE_STALE_QUOTE && /stale quote/i.test(remarks)) continue;
    const inApp = remarks.startsWith('Blocked in app:');
    const tag = inApp ? '[app blocked]' : lib.isRuleRefusal(remarks) ? '[server]' : '[server ⚠ unusual]';
    rejections.push(`${tag} ${who(t.user_id)} · ${orderText({ symbol: t.tradingsymbol, side: t.transaction_type, quantity: t.quantity, order_type: t.order_type })} · ${remarks.replace(/^Blocked in app:\s*/, '').slice(0, 220)}`);
    if (/stale quote/i.test(remarks) && hit('stale-app', 5 * MIN, t).length >= 5) {
      raise('stale-app', 'warning', 'Many app stale-price blocks', ['5+ clients blocked by the 25 s stale-price check in 5 min — feed or app connection problem.'], { cooldownMs: 30 * MIN });
    }
  }

  // Internal order failures (not business refusals).
  for (const s of await newDocs(d, 'serverevents')) {
    const ctx = s.context || {};
    rejections.push(`[‼ server error ${s.status}] ${who(s.user_id)}${s.caller_role && s.caller_role !== 'user' ? ` (placed by ${s.caller_role})` : ''} · ${orderText(ctx)} · ${s.message}`);
  }

  if (rejections.length) {
    const lines = rejections.slice(0, 20);
    if (rejections.length > 20) lines.push(`…and ${rejections.length - 20} more (see the Rejection Log)`);
    telegram.send(lib.formatAlert('warning', `Rejected order${rejections.length > 1 ? `s (${rejections.length})` : ''}`, lines));
  }

  // Margin square-offs.
  for (const t of await newDocs(d, 'trades', { trade_type: 'margin_square_off' }, { user_id: 1, tradingsymbol: 1, quantity: 1 }, 'trades-msq')) {
    raise(`msq:${t.user_id}`, 'warning', 'Margin square-off executed', [who(t.user_id), `${t.tradingsymbol} ${t.quantity}`], { cooldownMs: 30 * MIN });
  }

  await extra.events(ctx(d));

  // Every 5 minutes: negative wallets, settlement runs.
  if (Date.now() - (state.last.slowAt || 0) > 5 * MIN) {
    state.last.slowAt = Date.now();
    const cats = ['NSE', 'INDEX', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL'];
    const neg = await d.collection('users').find({ deleted_at: null, $or: cats.map((c) => ({ [`wallet.${c}`]: { $lt: 0 } })) }).project({ username: 1, wallet: 1 }).limit(20).toArray();
    for (const u of neg) raise(`negw:${u._id}`, 'warning', 'Client wallet negative', [who(u._id), cats.filter((c) => u.wallet?.[c] < 0).map((c) => `${c} ${u.wallet[c]}`).join(', ')], { cooldownMs: 6 * 60 * MIN });
    const runs = await d.collection('settlementruns').find({ $or: [{ started_at: { $gte: new Date(Date.now() - 3 * 24 * 60 * MIN) } }, { status: { $in: ['running', 'failed', 'blocked'] } }] }).project({ period_key: 1, status: 1, error: 1 }).toArray();
    state.runs = state.runs || {};
    for (const r of runs) {
      if (state.runs[r.period_key] === r.status) continue;
      state.runs[r.period_key] = r.status;
      if (r.status === 'failed' || r.status === 'blocked') raise(`settle:${r.period_key}`, 'critical', `Weekly settlement ${r.status}`, [`period ${r.period_key}`, r.error || ''], { cooldownMs: 60 * MIN });
      else if (r.status === 'completed') telegram.send(lib.formatAlert('info', 'Weekly settlement completed', [`period ${r.period_key}`]));
    }
  }
}

// -------------------------------------------------------------- digests ----
async function maybeDigest() {
  const p = lib.istParts();
  if (p.day < 1 || p.day > 5) return;
  for (const at of ['15:45', '23:35']) {
    const key = `${p.ymd} ${at}`;
    if (p.hhmm < at || state.digests[key]) continue;
    state.digests[key] = true;
    for (const k of Object.keys(state.digests)) if (k < p.ymd) delete state.digests[k];
    const d = await db();
    const dayStart = new Date(Date.parse(`${p.ymd}T00:00:00+05:30`));
    const since = { createdAt: { $gte: dayStart } };
    const [completed, rejected, ce, lf, se] = await Promise.all([
      d.collection('trades').countDocuments({ ...since, status: 'completed' }),
      d.collection('trades').find({ ...since, status: 'rejected' }).project({ user_id: 1, remarks: 1 }).toArray(),
      d.collection('clientevents').aggregate([{ $match: since }, { $group: { _id: { s: '$source', k: '$kind' }, n: { $sum: 1 } } }]).toArray(),
      d.collection('loginattempts').countDocuments(since),
      d.collection('serverevents').countDocuments(since),
    ]);
    const reasons = new Map();
    const clients = new Map();
    for (const r of rejected) {
      const s = lib.signature(String(r.remarks || '').replace(/\(short .*$/, '')).slice(0, 70);
      reasons.set(s, (reasons.get(s) || 0) + 1);
      clients.set(String(r.user_id), (clients.get(String(r.user_id)) || 0) + 1);
    }
    const top = (m, n) => [...m.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);
    const errorsToday = Object.values(state.signatures).filter((v) => v.day === p.ymd).reduce((s, v) => s + (v.today || 0), 0);
    const lines = [
      `Orders filled: ${completed} · refused: ${rejected.length}`,
      ...top(reasons, 5).map(([r, n]) => `   ${n}× ${r}`),
      rejected.length ? `Most refused: ${top(clients, 3).map(([u, n]) => `${who(u)} (${n})`).join(', ')}` : '',
      `Web/app reports: ${ce.length ? ce.map((x) => `${x._id.s} ${x._id.k} ${x.n}`).join(', ') : 'none'}`,
      `Failed logins: ${lf} · internal order errors: ${se} · backend errors: ${errorsToday}`,
      (() => { const st = (state.fillStats || {})[p.ymd]; return st ? `Fills vs exchange candles: ${st.checked} checked · ${st.better} better than market · ${st.worse} worse` : ''; })(),
      `Backend restarts today: ${state.lastRestarts != null && state.restartsAtDayStart != null ? state.lastRestarts - state.restartsAtDayStart : '?'}`,
    ];
    telegram.send(lib.formatAlert('info', `Day summary ${p.ymd} ${at} IST`, lines));
  }
}

/** What the extra checks (extra.js) need from here. */
function ctx(d) {
  return { d, state, raise, clear, send: (t) => telegram.send(t), sendPhoto: (p, cap, fn) => telegram.sendPhoto(p, cap, fn), lib, who, names, hit, newDocs, inMaintenance, MIN };
}

// ----------------------------------------------------------------- main ----
async function cycle() {
  const apps = pm2List();
  const env = checkBackend(apps);
  checkMachine();
  await checkApi();
  checkLogs(env);
  checkNginx();
  const dbOk = await checkDb();
  // Names first, so every alert below shows "username name [master]", not ids.
  if (dbOk) { try { await refreshNames(await db()); } catch (_) { /* labels fall back to ids */ } }
  try { await extra.internal(ctx(dbOk ? await db() : null)); } catch (e) { console.error('[watchdog] internal check:', e.message); }
  if (dbOk) {
    try { await extra.slow(ctx(await db())); } catch (e) { console.error('[watchdog] slow checks:', e.message); }
    try { await checkEvents(); } catch (e) { raise('watchdog-events', 'info', 'Watchdog could not read events', [e.message.slice(0, 200)], { cooldownMs: 60 * MIN }); }
    try { await maybeDigest(); } catch (_) { /* next cycle */ }
  }
  saveState();
}

async function main() {
  if (lib.shouldSend(state.sent, 'watchdog-start', 'info', Date.now(), 60 * MIN)) {
    telegram.send(lib.formatAlert('info', 'Watchdog started', [`watching ${os.hostname()} every ${CYCLE_MS / 1000} s${telegram.configured() ? '' : ' (dry mode — no Telegram token yet)'}`]));
  }
  // Server / logs / nginx every 30 s; logins, orders and web/app reports every
  // 5 s (small indexed reads of new documents only) so those alerts are quick.
  let lastFull = 0;
  for (;;) {
    const started = Date.now();
    try {
      if (started - lastFull >= CYCLE_MS) {
        lastFull = started;
        await cycle();
      } else if (!state.active['db-down']) {
        await checkEvents();
        saveState();
      }
    } catch (e) {
      console.error('[watchdog] cycle failed:', e.message);
    }
    await new Promise((r) => setTimeout(r, Math.max(500, EVENT_MS - (Date.now() - started))));
  }
}

main();
