'use strict';

// NSE EQ-series stocks for equity, from Kite's NSE instrument list, into eqcash_instruments.
// The F&O instruments collection (KiteInstrument) and its 07:30 sync are not touched.

const axios = require('axios');
const zlib = require('zlib');
const { promisify } = require('util');
const { EqInstrument } = require('./models');

const gunzip = promisify(zlib.gunzip);

/** One CSV line → fields (handles "quoted, values"). */
function splitCsvLine(line) {
  const out = [];
  let cur = '';
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') { cur += '"'; i++; } else if (ch === '"') quoted = false; else cur += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { out.push(cur); cur = ''; } else cur += ch;
  }
  out.push(cur);
  return out.map((s) => s.trim());
}

/**
 * EQ-series stocks from Kite's NSE instrument CSV: exchange NSE, segment NSE, type EQ,
 * and no series suffix. Other series come as "SYMBOL-XX" with a 2-character code (BE, BZ,
 * SM, ST, SG, GS, GB, N0…), while real names can contain a hyphen (BAJAJ-AUTO, NAM-INDIA,
 * KLBRENG-B) — only a 2-character suffix is a series. Indices (segment INDICES) are left out.
 */
function parseEqSeries(csvText) {
  const lines = csvText.replace(/\r/g, '').split('\n').filter(Boolean);
  if (!lines.length) return [];
  const head = splitCsvLine(lines[0]);
  const col = (n) => head.indexOf(n);
  const iTok = col('instrument_token');
  const iEx = col('exchange_token');
  const iSym = col('tradingsymbol');
  const iName = col('name');
  const iTick = col('tick_size');
  const iType = col('instrument_type');
  const iLot = col('lot_size');
  const iSeg = col('segment');
  const iExch = col('exchange');
  if ([iTok, iSym, iType, iSeg, iExch].some((i) => i < 0)) throw new Error('Unexpected instrument CSV header');
  const out = [];
  const seen = new Set();
  for (let k = 1; k < lines.length; k++) {
    const v = splitCsvLine(lines[k]);
    if (v[iExch] !== 'NSE' || v[iSeg] !== 'NSE' || v[iType] !== 'EQ') continue;
    const sym = (v[iSym] || '').toUpperCase();
    if (!sym || /-[A-Z0-9]{2}$/.test(sym)) continue;
    if (iLot >= 0 && Number(v[iLot]) !== 1) continue; // EQ series trades in single shares
    const token = Number(v[iTok]);
    if (!Number.isInteger(token) || token <= 0 || seen.has(token)) continue;
    seen.add(token);
    out.push({
      instrument_token: token,
      exchange_token: Number(v[iEx]) || undefined,
      tradingsymbol: sym,
      name: v[iName] || sym,
      tick_size: Number(v[iTick]) > 0 ? Number(v[iTick]) : 0.05,
    });
  }
  return out;
}

async function downloadNseCsv() {
  const kiteService = require('../services/kiteService');
  const accessToken = await kiteService.getStoredAccessToken();
  if (!accessToken) throw new Error('No valid Kite access token');
  const res = await axios({
    method: 'GET',
    url: 'https://api.kite.trade/instruments/NSE',
    headers: { 'X-Kite-Version': '3', Authorization: `token ${process.env.KITE_API_KEY}:${accessToken}`, 'Accept-Encoding': 'gzip' },
    responseType: 'arraybuffer',
    timeout: 60000,
  });
  const buf = Buffer.from(res.data);
  return (res.headers['content-encoding'] === 'gzip' ? await gunzip(buf) : buf).toString('utf8');
}

/**
 * Upsert today's EQ-series list; stocks no longer listed are marked inactive (kept, so
 * old trades still have their name). Refuses a suspiciously short list.
 */
async function syncInstruments({ csvText } = {}) {
  const started = Date.now();
  const rows = parseEqSeries(csvText ?? await downloadNseCsv());
  if (rows.length < 500) throw new Error(`Only ${rows.length} EQ stocks in Kite's list — not syncing`);
  const now = new Date();
  await EqInstrument.bulkWrite(rows.map((r) => ({
    updateOne: { filter: { instrument_token: r.instrument_token }, update: { $set: { ...r, is_active: true, synced_at: now } }, upsert: true },
  })), { ordered: false });
  const gone = await EqInstrument.updateMany(
    { is_active: true, instrument_token: { $nin: rows.map((r) => r.instrument_token) } },
    { $set: { is_active: false } }
  );
  const result = { stocks: rows.length, inactivated: gone.modifiedCount || 0, ms: Date.now() - started };
  console.log(`📈 [cashEq] instruments synced: ${result.stocks} EQ stocks, ${result.inactivated} no longer listed (${result.ms} ms)`);
  return result;
}

// Approved (MTF) scripts: Zerodha's published MTF list — the JSON behind
// https://zerodha.com/mtf-approved-securities/ ([{ isin, tradingsymbol, category, margin, leverage }]).
const MTF_URL = process.env.CASH_EQ_MTF_URL || 'https://public.zrd.sh/crux/approved-mtf-securities.json';
const MTF_MIN_ROWS = 500; // a shorter list is treated as broken: yesterday's flags are kept

/** Validate and index the broker's list by symbol. Throws on anything that looks wrong. */
function parseMtfList(data) {
  const rows = Array.isArray(data) ? data : null;
  if (!rows) throw new Error('MTF list is not a list');
  const bySymbol = new Map();
  for (const r of rows) {
    const sym = typeof r?.tradingsymbol === 'string' ? r.tradingsymbol.trim().toUpperCase() : '';
    if (!sym) continue;
    const margin = Number(r.margin);
    bySymbol.set(sym, {
      mtf_margin_pct: Number.isFinite(margin) && margin > 0 && margin <= 100 ? margin : null,
      mtf_category: typeof r.category === 'string' ? r.category : null,
      isin: typeof r.isin === 'string' ? r.isin : null,
    });
  }
  if (bySymbol.size < MTF_MIN_ROWS) throw new Error(`MTF list has only ${bySymbol.size} scripts — keeping the previous list`);
  return bySymbol;
}

/**
 * Mark approved scripts. A script is approved when its symbol is on the broker's list.
 * Returns what changed (newly approved / no longer approved), for the audit log.
 * Trades keep the category they were bought under — this only affects new trades.
 */
async function syncMtfList({ json } = {}) {
  let data = json;
  if (data === undefined) {
    const res = await axios.get(MTF_URL, { timeout: 30000, headers: { 'User-Agent': 'Mozilla/5.0' } });
    data = res.data;
  }
  const bySymbol = parseMtfList(data);
  const now = new Date();
  const ours = await EqInstrument.find({}).select('instrument_token tradingsymbol mtf').lean();
  const ops = [];
  const added = [];
  const removed = [];
  const matched = new Set();
  for (const inst of ours) {
    const hit = bySymbol.get(inst.tradingsymbol);
    if (hit) {
      matched.add(inst.tradingsymbol);
      if (!inst.mtf) added.push(inst.tradingsymbol);
      ops.push({ updateOne: { filter: { _id: inst._id }, update: { $set: { mtf: true, ...hit, mtf_synced_at: now } } } });
    } else {
      if (inst.mtf) removed.push(inst.tradingsymbol);
      ops.push({ updateOne: { filter: { _id: inst._id }, update: { $set: { mtf: false, mtf_margin_pct: null, mtf_category: null, mtf_synced_at: now } } } });
    }
  }
  if (ops.length) await EqInstrument.bulkWrite(ops, { ordered: false });
  const notListed = [...bySymbol.keys()].filter((s) => !matched.has(s));
  const result = { approved: matched.size, on_broker_list: bySymbol.size, not_in_nse_eq: notListed.length, added: added.sort(), removed: removed.sort() };
  console.log(`📈 [cashEq] MTF list synced: ${result.approved} approved (${result.added.length} new, ${result.removed.length} removed); ${result.not_in_nse_eq} on the broker list aren't NSE EQ-series`);
  return result;
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/** Search active stocks: symbol prefix first, then name contains. */
async function search(q, limit = 30) {
  const text = String(q || '').trim().toUpperCase().slice(0, 30);
  if (!text) return [];
  const fields = 'instrument_token tradingsymbol name tick_size mtf';
  const prefix = await EqInstrument.find({ is_active: true, tradingsymbol: { $regex: `^${escapeRe(text)}` } })
    .select(fields).sort({ tradingsymbol: 1 }).limit(limit).lean();
  if (prefix.length >= limit) return prefix;
  const have = new Set(prefix.map((p) => p.instrument_token));
  const byName = await EqInstrument.find({ is_active: true, name: { $regex: escapeRe(text), $options: 'i' } })
    .select(fields).sort({ tradingsymbol: 1 }).limit(limit).lean();
  return [...prefix, ...byName.filter((r) => !have.has(r.instrument_token))].slice(0, limit);
}

module.exports = { splitCsvLine, parseEqSeries, syncInstruments, parseMtfList, syncMtfList, search, MTF_URL };
