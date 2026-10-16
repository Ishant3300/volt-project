'use strict';

/**
 * Automatic Volt notice images on Telegram (cards in noticeImages.js):
 *   new contract open   — when the expiry planner has opened contracts (one
 *                         card per open day, all of that day's opens)
 *   new F&O stocks      — after the 07:30 import added stocks (auto_added_nfo.csv)
 *   NSE F&O ban list    — weekdays after the 08:00 ban sync
 *   corporate actions   — weekdays 08:30: new upcoming actions for our F&O
 *                         stocks (NSE corporate-actions list), and a reminder
 *                         the trading day before each ex-date
 * Client details (who holds banned / split stocks) are sent as a separate
 * text, never drawn on the image, so the image can be forwarded.
 *
 * Off unless WATCHDOG_NOTICES=on in .env. `node scripts/watchdog/notices.js
 * --sample` (from the app directory) sends every card from today's data,
 * marked SAMPLE, without touching the automatic state.
 */
const fs = require('fs');
const path = require('path');
const cards = require('./noticeImages');

const APP = path.resolve(__dirname, '..', '..');
const IST_MS = 5.5 * 3600_000;
const INDEX = /^(NIFTY|BANKNIFTY|FINNIFTY|MIDCPNIFTY|NIFTYNXT50|NIFTYFPI|SENSEX|SENSEX50|BANKEX)$/;
const ist = () => {
  const d = new Date(Date.now() + IST_MS);
  return { ymd: d.toISOString().slice(0, 10), hhmm: d.toISOString().slice(11, 16), dow: d.getUTCDay() };
};
const keyOf = (date) => new Date(new Date(date).getTime() + IST_MS).toISOString().slice(0, 10);
const enabled = () => /^(on|1|true|yes)$/i.test(String(process.env.WATCHDOG_NOTICES || ''));

/** Next weekday after `ymd` (exchange holidays not considered). */
function nextTradingDay(ymd) {
  const d = new Date(`${ymd}T00:00:00Z`);
  do d.setUTCDate(d.getUTCDate() + 1); while (d.getUTCDay() === 0 || d.getUTCDay() === 6);
  return d.toISOString().slice(0, 10);
}

/** Clients with an open position in any of `names` → ['DS2 (759044): SAIL26OCTFUT +2,700', …] */
async function holders(d, names, who) {
  if (!names.length) return [];
  const insts = await d.collection('kiteinstruments').find({ name: { $in: names }, segment: { $in: ['NFO-FUT', 'NFO-OPT'] } }).project({ instrument_token: 1, tradingsymbol: 1 }).toArray();
  const sym = new Map(insts.map((i) => [String(i.instrument_token), i.tradingsymbol]));
  if (!sym.size) return [];
  const rows = await d.collection('trades').aggregate([
    { $match: { status: 'completed', deleted_at: null, instrument_token: { $in: [...sym.keys(), ...[...sym.keys()].map(Number)] } } },
    { $group: { _id: { u: '$user_id', t: '$instrument_token' }, net: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', { $multiply: ['$executed_quantity', -1] }] } } } },
    { $match: { net: { $ne: 0 } } },
  ]).toArray();
  return rows.map((r) => `${who(r._id.u)}: ${sym.get(String(r._id.t))} ${r.net > 0 ? '+' : ''}${r.net.toLocaleString('en-IN')}`).sort();
}

// ------------------------------------------------------------- data ----
async function expiryOpenData(d, date) {
  const opens = await d.collection('expiryactions').find({ kind: 'OPEN', action_date: date, status: { $ne: 'obsolete' } }).toArray();
  if (!opens.length) return null;
  const cuts = await d.collection('expiryactions').find({ kind: 'CUT', status: { $ne: 'obsolete' }, $or: opens.map((o) => ({ group_key: o.group_key, current_expiry: o.current_expiry })) }).toArray();
  const list = opens.map((o) => {
    const names = [...new Set((o.targets || []).map((t) => String(t.name).toUpperCase()))];
    const newExpiries = [...new Set((o.targets || []).map((t) => keyOf(t.expiry)))].sort().slice(0, 3);
    // Options say so — "NIFTY weekly options" — weekly when the new expiry is
    // within ~a week of the current one (16 Oct 2026: the card said just "NIFTY").
    const isOpt = /OPT/i.test(o.group_key || '') || /option/i.test(o.group_label || '');
    const gapDays = o.current_expiry && newExpiries[0] ? (Date.parse(`${newExpiries[0]}T00:00:00Z`) - new Date(o.current_expiry).getTime()) / 864e5 : null;
    const kind = isOpt ? (gapDays != null && gapDays <= 9 ? ' weekly options' : ' options') : '';
    const shown = names.map((n) => `${n}${kind}`);
    return { exchange: o.exchange_label, label: o.group_label, names: names.length && names.length <= 12 ? shown : null, allLabel: `All ${o.group_label}`, newExpiries, isOpt };
  });
  const seen = new Set();
  const settlements = cuts.filter((c) => { const k = `${c.action_date}|${c.close_time}`; if (seen.has(k)) return false; seen.add(k); return true; })
    // A cut covering only a few names is labelled with them (SENSEX is its own
    // cut inside "NSE futures", on a different day).
    .map((c) => ({ date: c.action_date, time: c.close_time || '', label: (c.names || []).length && c.names.length <= 3 ? c.names.join(', ') : c.group_label }))
    .sort((a, b) => a.date.localeCompare(b.date) || a.label.localeCompare(b.label));
  return { date, opens: list, settlements };
}

function companyNames(names) {
  try {
    const dir = path.join(APP, 'scripts', 'downloads');
    const dump = fs.readdirSync(dir).filter((f) => /^raw_instruments_.*\.csv$/.test(f)).sort().pop();
    const want = new Set(names);
    const out = new Map();
    for (const line of fs.readFileSync(path.join(dir, dump), 'utf8').split('\n')) {
      const c = line.split(',');
      if (c[10] === 'NSE' && c[9] === 'EQ' && want.has(c[2])) out.set(c[2], c[3].replace(/"/g, ''));
    }
    return out;
  } catch (_) { return new Map(); }
}

async function newStocksData(d, names, date) {
  const company = companyNames(names);
  const stocks = [];
  for (const name of names) {
    const futs = await d.collection('kiteinstruments').find({ name, segment: 'NFO-FUT', is_active: true, enabled: { $ne: false } }).project({ expiry: 1, lot_size: 1 }).sort({ expiry: 1 }).toArray();
    if (!futs.length) continue;
    const opts = await d.collection('kiteinstruments').countDocuments({ name, segment: 'NFO-OPT', is_active: true });
    stocks.push({ name, company: company.get(name) || '', lot: futs[0].lot_size, current: keyOf(futs[0].expiry), options: opts > 0, from: date });
  }
  return stocks.length ? { date, stocks } : null;
}

async function banData(d, prev) {
  const banned = (await d.collection('kiteinstruments').distinct('name', { nse_banned: true, segment: { $in: ['NFO-FUT', 'NFO-OPT'] } })).map(String).sort();
  const before = new Set(prev || []);
  return { banned, newToday: prev ? banned.filter((s) => !before.has(s)) : [], removed: prev ? [...before].filter((s) => !banned.includes(s)).sort() : [] };
}

/** NSE corporate actions between two dates, our F&O stocks only. */
async function corpActions(d, fromYmd, toYmd) {
  const axios = require(path.join(APP, 'node_modules', 'axios'));
  const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36';
  const home = await axios.get('https://www.nseindia.com/', { headers: { 'User-Agent': UA, 'Accept-Language': 'en-US' }, timeout: 15000, validateStatus: () => true });
  const cookie = (home.headers['set-cookie'] || []).map((c) => c.split(';')[0]).join('; ');
  const fmt = (ymd) => ymd.split('-').reverse().join('-');
  const res = await axios.get(`https://www.nseindia.com/api/corporates-corporateActions?index=equities&from_date=${fmt(fromYmd)}&to_date=${fmt(toYmd)}`, {
    headers: { 'User-Agent': UA, Cookie: cookie, Referer: 'https://www.nseindia.com/companies-listing/corporate-filings-actions', Accept: 'application/json' }, timeout: 20000,
  });
  if (!Array.isArray(res.data)) throw new Error('NSE returned no list');
  const fno = new Set((await d.collection('kiteinstruments').distinct('name', { segment: 'NFO-FUT', is_active: true })).map(String));
  const toYmdKey = (s) => { const t = Date.parse(`${s} UTC`); return Number.isNaN(t) ? null : new Date(t).toISOString().slice(0, 10); };
  return res.data.filter((r) => fno.has(String(r.symbol)) && !INDEX.test(r.symbol)).map((r) => {
    const s = String(r.subject || '');
    const kind = /split|sub-division/i.test(s) ? 'split' : /bonus/i.test(s) ? 'bonus' : /dividend/i.test(s) ? 'dividend' : /rights/i.test(s) ? 'rights' : 'other';
    return { symbol: r.symbol, company: r.comp, kind, subject: s.replace(/\s+/g, ' ').trim(), exDate: toYmdKey(r.exDate), recDate: toYmdKey(r.recDate) };
  }).filter((a) => a.exDate).sort((a, b) => a.exDate.localeCompare(b.exDate) || a.symbol.localeCompare(b.symbol));
}

// ------------------------------------------------------------- send ----
async function sendCard(c, html, caption, filename) {
  const [png] = await cards.render([html]);
  await c.sendPhoto(png, caption, filename);
}

async function sendHolders(c, title, list) {
  if (!list.length) return;
  c.send(c.lib.formatAlert('info', title, [...list.slice(0, 25), list.length > 25 ? `…and ${list.length - 25} more` : '']));
}

// ------------------------------------------------------------- run ----
async function run(c) {
  if (!enabled()) return;
  const { d, state } = c;
  const n = state.notices || (state.notices = { expiry: {}, stocks: [], ban: {}, corp: { sent: {}, remind: {} } });
  const t = ist();
  const weekday = t.dow >= 1 && t.dow <= 5;

  // 1. New contract open — every open of the day done, last one 2+ minutes ago.
  const recent = await d.collection('expiryactions').find({ kind: 'OPEN', status: 'done', executed_at: { $gte: new Date(Date.now() - 12 * 3600_000) } }).project({ action_date: 1, executed_at: 1 }).toArray();
  for (const date of new Set(recent.map((a) => a.action_date))) {
    if (n.expiry[date]) continue;
    const pending = await d.collection('expiryactions').countDocuments({ kind: 'OPEN', action_date: date, status: { $in: ['planned', 'confirmed', 'running'] }, execute_at: { $lte: new Date() } });
    const last = Math.max(...recent.filter((a) => a.action_date === date).map((a) => new Date(a.executed_at).getTime()));
    if (pending || Date.now() - last < 2 * 60_000) continue;
    n.expiry[date] = true;
    const data = await expiryOpenData(d, date);
    if (data) await sendCard(c, cards.expiryOpenCard(data), `New contract open — ${date}`, `new-contract-${date}.png`);
  }
  for (const k of Object.keys(n.expiry)) if (k < new Date(Date.now() - 20 * 864e5).toISOString().slice(0, 10)) delete n.expiry[k];

  // 2. New F&O stocks — after the 07:30 import.
  if (t.hhmm >= '07:40') {
    const svc = require(path.join(APP, 'src', 'services', 'newNfoStockService'));
    const fresh = svc.loadAutoAddedDates().filter((x) => !n.stocks.includes(x.name) && Date.now() - x.at.getTime() < 3 * 864e5).map((x) => x.name);
    if (fresh.length) {
      const data = await newStocksData(d, fresh, t.ymd);
      if (data) {
        await sendCard(c, cards.newStocksCard(data), `New F&O stocks — ${data.stocks.map((s) => s.name).join(', ')}`, `new-fno-stocks-${t.ymd}.png`);
        n.stocks.push(...data.stocks.map((s) => s.name));
      }
    }
  }

  // 3. Ban list — weekdays after the 08:00 sync.
  if (weekday && t.hhmm >= '08:05' && n.ban.day !== t.ymd) {
    n.ban.day = t.ymd;
    const data = await banData(d, n.ban.prev);
    n.ban.prev = data.banned;
    if (data.banned.length || data.removed.length) {
      await sendCard(c, cards.banCard({ date: t.ymd, ...data }), `NSE F&O ban list — ${t.ymd}`, `fno-ban-${t.ymd}.png`);
      await sendHolders(c, 'Clients holding stocks in ban (internal)', await holders(d, data.banned, c.who));
    }
  }

  // 4. Corporate actions — weekdays 08:30: new ones, and reminders for the next trading day.
  if (weekday && t.hhmm >= '08:30' && n.corp.day !== t.ymd) {
    n.corp.day = t.ymd;
    let list;
    try {
      const to = new Date(Date.now() + 10 * 864e5).toISOString().slice(0, 10);
      list = await corpActions(d, t.ymd, to);
    } catch (e) {
      c.send(c.lib.formatAlert('warning', 'Corporate actions not checked today', [`NSE list could not be read: ${e.message}`, 'Check splits/bonus/dividends on nseindia.com by hand today.']));
      return;
    }
    const key = (a) => `${a.symbol}|${a.exDate}|${a.subject}`;
    const fresh = list.filter((a) => a.exDate > t.ymd && !n.corp.sent[key(a)]);
    const tomorrow = nextTradingDay(t.ymd);
    const remind = list.filter((a) => a.exDate === tomorrow && !n.corp.remind[key(a)] && !fresh.includes(a));
    if (fresh.length) {
      await sendCard(c, cards.corpActionsCard({ date: t.ymd, actions: fresh }), `Corporate actions — ${fresh.length} upcoming`, `corporate-actions-${t.ymd}.png`);
      for (const a of fresh) n.corp.sent[key(a)] = t.ymd;
    }
    if (remind.length) {
      await sendCard(c, cards.corpActionsCard({ date: t.ymd, actions: remind, title: 'Ex-date Tomorrow' }), `Ex-date tomorrow (${tomorrow})`, `ex-date-${tomorrow}.png`);
      for (const a of remind) n.corp.remind[key(a)] = t.ymd;
    }
    const adjust = [...new Set([...fresh, ...remind].filter((a) => a.kind === 'split' || a.kind === 'bonus').map((a) => a.symbol))];
    await sendHolders(c, 'Clients holding stocks with a split/bonus coming (internal)', await holders(d, adjust, c.who));
    for (const m of [n.corp.sent, n.corp.remind]) for (const [k, v] of Object.entries(m)) if (v < new Date(Date.now() - 40 * 864e5).toISOString().slice(0, 10)) delete m[k];
  }
}

module.exports = { run, expiryOpenData, newStocksData, banData, corpActions, holders, nextTradingDay };

// ------------------------------------------------------- --sample CLI ----
if (require.main === module) {
  require('dotenv').config();
  (async () => {
    const { MongoClient } = require(path.join(APP, 'node_modules', 'mongoose')).mongo;
    const telegram = require('./telegram');
    const lib = require('./lib');
    const cl = await MongoClient.connect(process.env.MONGO_URI);
    const d = cl.db('stocker');
    const users = new Map((await d.collection('users').find({}).project({ username: 1, name: 1 }).toArray()).map((u) => [String(u._id), u]));
    const who = (id) => { const u = users.get(String(id)); return u ? `${u.username} ${u.name || ''}`.trim() : String(id); };
    const t = ist();
    const sent = [];
    const send = async (html, caption, fn) => { const [png] = await cards.render([html]); await telegram.sendPhoto(png, `SAMPLE — ${caption}`, fn); sent.push(caption); };

    const lastOpen = (await d.collection('expiryactions').find({ kind: 'OPEN', status: 'done' }).sort({ executed_at: -1 }).limit(1).toArray())[0];
    if (lastOpen) { const data = await expiryOpenData(d, lastOpen.action_date); if (data) await send(cards.expiryOpenCard(data), `New contract open (${lastOpen.action_date})`, 'sample-new-contract.png'); }
    const svc = require(path.join(APP, 'src', 'services', 'newNfoStockService'));
    const st = await newStocksData(d, svc.loadAutoAddedDates().map((x) => x.name), t.ymd);
    if (st) await send(cards.newStocksCard(st), 'New F&O stocks', 'sample-new-stocks.png');
    const ban = await banData(d, null);
    await send(cards.banCard({ date: t.ymd, ...ban }), 'NSE F&O ban list', 'sample-ban.png');
    const bh = await holders(d, ban.banned, who);
    if (bh.length) await telegram.send(lib.formatAlert('info', 'SAMPLE — Clients holding stocks in ban (internal)', bh.slice(0, 25)));
    try {
      const to = new Date(Date.now() + 10 * 864e5).toISOString().slice(0, 10);
      const ca = await corpActions(d, t.ymd, to);
      if (ca.length) await send(cards.corpActionsCard({ date: t.ymd, actions: ca }), `Corporate actions (${ca.length})`, 'sample-corporate-actions.png');
      else console.log('no corporate actions for our F&O stocks in the next 10 days');
    } catch (e) { console.log('corporate actions fetch failed:', e.message); }
    console.log('sent:', sent.join(' | '));
    await new Promise((r) => setTimeout(r, 4000));
    await cl.close();
    process.exit(0);
  })().catch((e) => { console.error('ERR', e.stack); process.exit(1); });
}
