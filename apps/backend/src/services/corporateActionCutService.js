'use strict';

/**
 * Corporate-action cuts — on the trading day before a split, bonus or rights
 * ex-date, every open position in that stock's F&O contracts (futures and
 * options) is closed just after the NSE close, at the closing bid/ask.
 *
 * On the ex-date NSE adjusts those contracts (price, lot size, strikes), but
 * a position here keeps its old average price and quantity — so it would
 * show a large false P&L. Closing it the day before avoids that.
 *
 * Each cut is an ExpiryAction (kind CUT, group_key CORP_ACTION) in the same
 * Expiry schedule as contract-expiry cuts, with the same rules: it closes
 * nothing until an admin confirms it, uses the closing snapshot however late
 * the confirm comes (up to the next session), and is marked missed if never
 * confirmed. Unlike an expiry cut the contracts stay open for trading and
 * watchlists are left alone — clients can re-enter at the adjusted price.
 *
 * The list comes from NSE's corporate-actions API (the same source as the
 * Telegram notices in scripts/watchdog/notices.js), refreshed by
 * cronService. Dividends are cut too, by the business owner's choice
 * (20 Oct 2026) — NSE only adjusts F&O for extraordinary ones, but every
 * dividend's ex-date is cut the same way.
 */

const ExpiryAction = require('../models/ExpiryAction');
const KiteInstrument = require('../models/KiteInstrument');
const { GROUPS } = require('../config/expiryRules');
const { istInstant, plusOneMinute } = require('./expirySchedule');
const { addUtcDays, dateKey, previousTradingDay, toIndiaDateOnly } = require('../utils/settlementDates');

const GROUP_KEY = 'CORP_ACTION';
const SEGMENTS = ['NFO-FUT', 'NFO-OPT'];
/** This platform's NSE close — the same time as the NSE futures expiry cut. */
const CLOSE_TIME = GROUPS.find((g) => g.key === 'NSE_FUT')?.closeTime || '15:40';
/** How far ahead NSE's list is read. */
const LOOKAHEAD_DAYS = 15;
const INDEX = /^(NIFTY|BANKNIFTY|FINNIFTY|MIDCPNIFTY|NIFTYNXT50|SENSEX|SENSEX50|BANKEX)$/;
const KIND_LABEL = { split: 'split', bonus: 'bonus', rights: 'rights issue', dividend: 'dividend' };

/** The kind of action an NSE subject describes, or null when no cut is needed (AGM, buy-back …). */
function kindOf(subject) {
  const s = String(subject || '');
  if (/split|sub-?division/i.test(s)) return 'split';
  if (/bonus/i.test(s)) return 'bonus';
  if (/rights/i.test(s)) return 'rights';
  if (/dividend/i.test(s)) return 'dividend';
  return null;
}

const MONTHS = { JAN: 0, FEB: 1, MAR: 2, APR: 3, MAY: 4, JUN: 5, JUL: 6, AUG: 7, SEP: 8, OCT: 9, NOV: 10, DEC: 11 };

/** NSE date '28-Oct-2026' → '2026-10-28' (null if unreadable). */
function parseNseDate(value) {
  const m = /^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/.exec(String(value || '').trim());
  if (!m || MONTHS[m[2].toUpperCase()] === undefined) return null;
  return dateKey(new Date(Date.UTC(Number(m[3]), MONTHS[m[2].toUpperCase()], Number(m[1]))));
}

/**
 * Pure planning: NSE rows → one cut per (stock, ex-date) for our F&O stocks.
 * Several subjects for the same stock and ex-date (e.g. a bonus and a split
 * together) make one cut. A cut whose day has already passed is not planned.
 *
 * @param {Array<{symbol, subject, exDate}>} rows - NSE API rows
 * @param {{ fnoNames: Set<string>, holidays: Set<string>, today: Date }} ctx
 */
function planCuts(rows, { fnoNames, holidays, today }) {
  const todayKey = dateKey(today);
  const bySymbolDay = new Map();
  for (const r of rows || []) {
    const symbol = String(r.symbol || '').trim().toUpperCase();
    const kind = kindOf(r.subject);
    const exDate = parseNseDate(r.exDate);
    if (!symbol || !kind || !exDate || INDEX.test(symbol) || !fnoNames.has(symbol)) continue;
    const key = `${GROUP_KEY}|${symbol}|${exDate}`;
    if (!bySymbolDay.has(key)) bySymbolDay.set(key, { key, symbol, exDate, kinds: new Set(), subjects: new Set() });
    const entry = bySymbolDay.get(key);
    entry.kinds.add(kind);
    entry.subjects.add(String(r.subject).replace(/\s+/g, ' ').trim());
  }

  const planned = [];
  for (const e of bySymbolDay.values()) {
    const cutDay = previousTradingDay(new Date(`${e.exDate}T00:00:00.000Z`), holidays);
    if (dateKey(cutDay) < todayKey) continue;
    const kinds = ['split', 'bonus', 'rights', 'dividend'].filter((k) => e.kinds.has(k));
    planned.push({
      key: e.key,
      symbol: e.symbol,
      kind: kinds.join('+'),
      label: `${e.symbol} ${kinds.map((k) => KIND_LABEL[k]).join(' + ')}`,
      subject: [...e.subjects].join('; '),
      ex_date: e.exDate,
      action_date: dateKey(cutDay),
      execute_at: istInstant(cutDay, plusOneMinute(CLOSE_TIME)),
    });
  }
  return planned.sort((a, b) => a.execute_at - b.execute_at || a.key.localeCompare(b.key));
}

/** NSE corporate actions between two India dates ('YYYY-MM-DD'), all equities. */
async function fetchNseActions(fromYmd, toYmd) {
  const axios = require('axios');
  const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124 Safari/537.36';
  // NSE's API needs the cookies its home page sets.
  const home = await axios.get('https://www.nseindia.com/', { headers: { 'User-Agent': UA, 'Accept-Language': 'en-US' }, timeout: 15000, validateStatus: () => true });
  const cookie = (home.headers['set-cookie'] || []).map((c) => c.split(';')[0]).join('; ');
  const fmt = (ymd) => ymd.split('-').reverse().join('-');
  const res = await axios.get(`https://www.nseindia.com/api/corporates-corporateActions?index=equities&from_date=${fmt(fromYmd)}&to_date=${fmt(toYmd)}`, {
    headers: { 'User-Agent': UA, Cookie: cookie, Referer: 'https://www.nseindia.com/companies-listing/corporate-filings-actions', Accept: 'application/json' },
    timeout: 20000,
  });
  if (!Array.isArray(res.data)) throw new Error('NSE returned no corporate-actions list');
  return res.data;
}

/** NSE trading holidays for every year a cut day can fall in. */
async function loadHolidays(years) {
  const { getHolidays } = require('./marketCalendarService');
  const all = new Set();
  for (const y of years) for (const k of await getHolidays('NSE', y)) all.add(k);
  return all;
}

/**
 * Read NSE's list and upsert the planned cuts. Like the expiry planner, only
 * 'planned'/'confirmed'/'paused'/'obsolete' rows are ever rewritten — a cut
 * that ran is history. A cut NSE no longer lists becomes obsolete.
 */
async function refreshPlan(now = new Date(), { fetchActions = fetchNseActions } = {}) {
  const today = toIndiaDateOnly(now);
  const todayKey = dateKey(today);
  const toKey = dateKey(addUtcDays(today, LOOKAHEAD_DAYS));
  const rows = await fetchActions(todayKey, toKey);

  const fnoNames = new Set((await KiteInstrument.distinct('name', { segment: 'NFO-FUT', is_active: true, deleted_at: null }))
    .map((n) => String(n).toUpperCase()));
  // The day before an early-January ex-date can fall in December.
  const years = new Set([today.getUTCFullYear(), addUtcDays(today, LOOKAHEAD_DAYS).getUTCFullYear()]);
  const holidays = await loadHolidays(years);
  const planned = planCuts(rows, { fnoNames, holidays, today });

  for (const p of planned) {
    const fields = {
      group_key: GROUP_KEY,
      group_label: p.label,
      exchange_label: 'NSE',
      segments: SEGMENTS,
      continuous: false,
      names: [p.symbol],
      current_expiry: new Date(`${p.ex_date}T00:00:00.000Z`),
      targets: [],
      action_date: p.action_date,
      close_time: CLOSE_TIME,
      execute_at: p.execute_at,
      corp_action: { symbol: p.symbol, kind: p.kind, subject: p.subject, ex_date: p.ex_date },
    };
    const existing = await ExpiryAction.findOne({ key: p.key }).select('status').lean();
    if (!existing) {
      await ExpiryAction.updateOne({ key: p.key }, { $setOnInsert: { key: p.key, kind: 'CUT', status: 'planned', ...fields } }, { upsert: true });
      console.log(`🗓️  [CorpActions] Cut planned: ${p.label} (ex ${p.ex_date}) on ${p.action_date} after the close`);
    } else if (['planned', 'confirmed', 'paused', 'obsolete'].includes(existing.status)) {
      const status = existing.status === 'obsolete' ? 'planned' : existing.status;
      await ExpiryAction.updateOne({ _id: existing._id }, { $set: { ...fields, status } });
    }
    await syncBanner(await ExpiryAction.findOne({ key: p.key }).lean());
  }

  // Withdrawn by the company / no longer listed. An empty answer is not
  // trusted for this — NSE sometimes returns [] when it is having trouble.
  let retired = 0;
  if (rows.length > 0) {
    const withdrawn = { group_key: GROUP_KEY, status: { $in: ['planned', 'confirmed', 'paused'] }, action_date: { $gte: todayKey }, 'corp_action.ex_date': { $lte: toKey }, key: { $nin: planned.map((p) => p.key) } };
    const gone = await ExpiryAction.find(withdrawn).lean();
    const res = await ExpiryAction.updateMany(withdrawn, { $set: { status: 'obsolete' } });
    retired = res.modifiedCount;
    for (const a of gone) await syncBanner({ ...a, status: 'obsolete' });
  }
  return { planned: planned.length, retired };
}

/** Every contract (futures and options) of the stock that can still hold a position. */
function resolveInstruments(action) {
  const names = (action.names || []).map((n) => String(n).toUpperCase());
  return KiteInstrument.find({
    segment: { $in: action.segments },
    name: { $in: names },
    expiry: { $gte: toIndiaDateOnly(action.execute_at) },
    deleted_at: null,
  }).select('instrument_token tradingsymbol exchange segment last_price name expiry').lean();
}

function isCorporateCut(action) {
  return action?.group_key === GROUP_KEY;
}

const MONTH_SHORT = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** '2026-10-22' → '22 Oct' */
const dayLabel = (ymd) => `${Number(ymd.slice(8, 10))} ${MONTH_SHORT[Number(ymd.slice(5, 7)) - 1]}`;
/** '15:40' → '3:40 PM' */
function timeLabel(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return `${h % 12 || 12}:${String(m).padStart(2, '0')} ${h < 12 ? 'AM' : 'PM'}`;
}

/**
 * The announcement-bar notice for a cut (pure). A confirmed cut says the
 * positions will be closed and stays up until it runs; an unconfirmed one
 * only announces the action, until the ex-date starts. Null = no notice
 * (cut ran, paused, obsolete …).
 */
function bannerFor(action) {
  const ca = action?.corp_action;
  if (!ca?.ex_date || !ca.symbol) return null;
  const head = `${ca.symbol} — ${ca.subject || describe(action)}, ex-date ${dayLabel(ca.ex_date)}`;
  if (action.status === 'confirmed' || action.status === 'running') {
    return {
      message: `${head}: all open ${ca.symbol} positions (futures & options) will be closed on ${dayLabel(action.action_date)} at the ${timeLabel(action.close_time || CLOSE_TIME)} closing rate.`,
      expiresAt: new Date(action.execute_at),
    };
  }
  if (action.status === 'planned') {
    return { message: `${head}.`, expiresAt: new Date(`${ca.ex_date}T00:00:00+05:30`) };
  }
  return null;
}

/** Post, update or remove this cut's section of the announcement bar. Never throws. */
async function syncBanner(action) {
  if (!isCorporateCut(action) || !action.corp_action) return;
  try {
    const board = require('./announcementBoard');
    const ref = `${action.corp_action.symbol}|${action.corp_action.ex_date}`;
    const notice = bannerFor(action);
    if (notice && notice.expiresAt > new Date()) await board.postSection('corp', notice.message, { ref, expiresAt: notice.expiresAt });
    else await board.clearSection('corp', ref);
  } catch (e) {
    console.error(`❌ [CorpActions] Announcement bar update failed for ${action.key}: ${e.message}`);
  }
}

/** Words for messages: 'bonus', 'split + bonus', 'rights issue'. */
function describe(action) {
  return String(action.corp_action?.kind || '').split('+').filter(Boolean).map((k) => KIND_LABEL[k] || k).join(' + ') || 'corporate action';
}

module.exports = {
  GROUP_KEY,
  SEGMENTS,
  refreshPlan,
  resolveInstruments,
  isCorporateCut,
  describe,
  syncBanner,
  _private: { kindOf, parseNseDate, planCuts, fetchNseActions, loadHolidays, bannerFor, CLOSE_TIME },
};
