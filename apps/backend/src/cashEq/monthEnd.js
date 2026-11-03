'use strict';

// Equity month-end (M6). Spec §6: bill at the end of the month's last calendar day at the
// NSE cash bhav close (CLOSE_PRICE, EQ series first) of the last trading day; P&L, MTM and
// the month's interest are posted, held lots re-open at the close from the 1st (no trade,
// no brokerage). All of that is engine.js — a confirmed run only stores the prices.
//
//   preview  (admin) — prices from the bhav copy, every client's bill, missing prices
//   prices   (admin) — enter a missing close by hand
//   confirm  (admin) — from the 1st of the next month, months in order, no missing price
//                      for a held stock, never during the F&O Saturday settlement window
//   delete   (admin) — the latest confirmed month only; everything recalculates

const axios = require('axios');
const engine = require('./engine');
const rules = require('./rules');
const book = require('./book');
const { EqMonthRun, EqClient, EqMaster, EqTrade, EqLedgerEntry, EqAudit } = require('./models');

class HttpError extends Error {
  constructor(status, message, data) { super(message); this.status = status; this.data = data; }
}

const r2 = engine.round2;
const BHAV_URL = (ddmmyyyy) => `https://nsearchives.nseindia.com/products/content/sec_bhavdata_full_${ddmmyyyy}.csv`;
const SERIES_ORDER = ['EQ', 'BE', 'BZ', 'SM', 'ST'];

/** sec_bhavdata_full CSV → { SYMBOL: CLOSE_PRICE }, EQ series first. */
function parseBhav(csv) {
  const lines = String(csv || '').replace(/\r/g, '').split('\n').filter(Boolean);
  if (!lines.length) return {};
  const head = lines[0].split(',').map((h) => h.trim().toUpperCase());
  const iSym = head.indexOf('SYMBOL');
  const iSer = head.indexOf('SERIES');
  const iClose = head.indexOf('CLOSE_PRICE');
  if (iSym < 0 || iSer < 0 || iClose < 0) throw new Error('Unexpected bhav copy header');
  const best = new Map(); // symbol -> { rank, price }
  for (let k = 1; k < lines.length; k++) {
    const v = lines[k].split(',').map((x) => x.trim());
    const rank = SERIES_ORDER.indexOf(String(v[iSer]).toUpperCase());
    const price = Number(v[iClose]);
    if (rank < 0 || !(price > 0) || !v[iSym]) continue;
    const sym = v[iSym].toUpperCase();
    const cur = best.get(sym);
    if (!cur || rank < cur.rank) best.set(sym, { rank, price });
  }
  return Object.fromEntries([...best].map(([s, x]) => [s, x.price]));
}

async function downloadBhav(date) {
  const [y, m, d] = date.split('-');
  try {
    const res = await axios.get(BHAV_URL(`${d}${m}${y}`), {
      timeout: 30000, responseType: 'text', headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)', Accept: 'text/csv,*/*' },
    });
    return res.data;
  } catch (err) {
    if (err.response?.status === 404) return null;
    throw new Error(`Bhav copy download failed for ${date}: ${err.message}`);
  }
}

function monthBounds(month) {
  if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) throw new HttpError(400, 'Month must be YYYY-MM');
  const [y, m] = month.split('-').map(Number);
  const first = `${month}-01`;
  const settle = m === 12 ? `${y + 1}-01-01` : `${y}-${String(m + 1).padStart(2, '0')}-01`;
  return { first, last: engine.addDays(settle, -1), settle };
}

/** Bhav copy of the last trading day on or before the month end (walks back up to 10 days). */
async function bhavForMonth(month, { download = downloadBhav, priceDate } = {}) {
  const { last, first } = monthBounds(month);
  const days = priceDate ? [priceDate] : Array.from({ length: 11 }, (_, i) => engine.addDays(last, -i));
  for (const d of days) {
    if (d < first || d > last) continue;
    const weekday = new Date(`${d}T00:00:00Z`).getUTCDay();
    if (!priceDate && (weekday === 0 || weekday === 6)) continue;
    const csv = await download(d);
    if (csv) {
      const prices = parseBhav(csv);
      if (Object.keys(prices).length > 100) return { price_date: d, prices };
    }
  }
  throw new HttpError(502, `No NSE bhav copy found for ${month} (tried back to 10 days before the month end)`);
}

/** Confirmed month-ends in engine shape (account.js, statements). */
async function confirmedSettlements() {
  const runs = await EqMonthRun.find({ status: 'CONFIRMED' }).sort({ settle_date: 1 }).lean();
  return runs.map(toSettlement);
}

function toSettlement(run) {
  return { id: String(run._id), segment: 'NSEEQ', settleDate: run.settle_date, priceDate: run.price_date, prices: run.prices || {}, sources: run.sources || {} };
}

/** Master chain of a client: [direct master, its parent, …, top]. */
function chainOf(masterId, mastersById) {
  const out = [];
  const seen = new Set();
  let cur = masterId ? String(masterId) : null;
  while (cur && !seen.has(cur)) {
    seen.add(cur);
    out.push(cur);
    const m = mastersById.get(cur);
    cur = m?.parent_id ? String(m.parent_id) : null;
  }
  return out;
}

/**
 * Every client's bill for `run` (with the earlier confirmed months), plus what each master
 * in its chain would have charged at its own rates (rate-gap clearances for sharing).
 */
async function computeClients(run) {
  const { first, last } = monthBounds(run.month);
  const earlier = (await confirmedSettlements()).filter((s) => s.settleDate < run.settle_date);
  const settlements = [...earlier, toSettlement(run)];
  const masters = await EqMaster.find({}).lean();
  const mastersById = new Map(masters.map((m) => [String(m._id), m]));
  const clients = await EqClient.find({}).lean();
  const out = [];
  for (const client of clients) {
    const trades = await book.loadTrades(client._id);
    const entries = await EqLedgerEntry.find({ client_id: client._id, deleted_at: null }).lean();
    if (!trades.length && !entries.length && !(client.opening_balance > 0 && !client.deleted_at)) continue;
    const calcs = book.calcsFor(client, trades);
    const code = String(client._id);
    const ledger = engine.computeClientLedger(
      rules.toAccount(client), trades, calcs,
      entries.map((e) => ({ id: String(e._id), clientCode: code, date: e.date, kind: e.kind, amount: e.amount, narration: e.narration || '' })),
      settlements, last
    );
    const bill = ledger.settlements.find((s) => s.settlement.settleDate === run.settle_date) || { realized: 0, mtm: 0, interest: 0, missingPrices: [] };
    const monthTrades = trades.filter((t) => t.date >= first && t.date <= last);
    const brokerage = monthTrades.reduce((a, t) => a + (calcs.get(t.id)?.brokerage || 0), 0);
    const chain = chainOf(client.master_id, mastersById);
    const interestMtf = bill.interestMtf ?? bill.interest;
    const interestNon = bill.interestNon ?? 0;
    const clearances = {};
    for (const mid of chain) {
      const m = mastersById.get(mid);
      if (!m) continue;
      const mc = book.calcsFor({ ...m, _id: client._id }, monthTrades);
      const scale = (num, den) => (den > 0 ? num / den : 0);
      clearances[mid] = {
        brokerage: r2(monthTrades.reduce((a, t) => a + (mc.get(t.id)?.brokerage || 0), 0)),
        interest: r2(interestMtf * scale(m.interest_mtf_pct, client.interest_mtf_pct) + interestNon * scale(m.interest_non_pct, client.interest_non_pct)),
      };
    }
    out.push({
      client_id: String(client._id), username: client.username, name: client.name, master_id: client.master_id ? String(client.master_id) : null,
      chain,
      clearances,
      realized: bill.realized, mtm: bill.mtm, interest: bill.interest, interest_mtf: r2(interestMtf), interest_non: r2(interestNon),
      brokerage: r2(brokerage),
      gross_pnl: r2(bill.realized + bill.mtm + brokerage), // before brokerage (it is inside the net-rate P&L)
      money_after: r2(ledger.money),
      missing_prices: bill.missingPrices || [],
    });
  }
  return { clients: out, masters };
}

const actorOf = (cash) => ({ role: cash.role, id: cash.id, username: cash.username });

async function audit(cash, action, run, details = {}) {
  await EqAudit.create({ actor: actorOf(cash), action, target: { kind: 'month_run', id: run._id, username: run.month }, details });
}

/** Create or refresh the month's preview (prices from the bhav copy unless given). */
async function preview(cash, { month, price_date: priceDate } = {}, deps = {}) {
  const { settle } = monthBounds(month);
  if (await EqMonthRun.exists({ month, status: 'CONFIRMED' })) throw new HttpError(400, `${month} is already confirmed — delete it first to redo`);
  const { price_date, prices } = await bhavForMonth(month, { ...deps, priceDate });
  let run = await EqMonthRun.findOne({ month, status: 'PREVIEW' });
  const manual = run && run.price_date === price_date ? Object.entries(run.sources || {}).filter(([, s]) => s === 'manual') : [];
  const mergedPrices = { ...prices };
  const sources = Object.fromEntries(Object.keys(prices).map((s) => [s, 'bhav']));
  for (const [sym] of manual) { mergedPrices[sym] = run.prices[sym]; sources[sym] = 'manual'; }
  if (!run) {
    run = await EqMonthRun.create({ month, settle_date: settle, status: 'PREVIEW', created_by: actorOf(cash), price_date, prices: mergedPrices, sources });
  } else {
    Object.assign(run, { price_date, prices: mergedPrices, sources });
    run.markModified?.('prices');
    run.markModified?.('sources');
    await run.save();
  }
  return withBill(run);
}

async function withBill(run) {
  const plain = run.toObject ? run.toObject() : run;
  const { clients } = await computeClients(plain);
  const missing = [...new Set(clients.flatMap((c) => c.missing_prices))].sort();
  const sum = (k) => r2(clients.reduce((a, c) => a + (c[k] || 0), 0));
  const { prices, sources, ...rest } = plain;
  return {
    run: { ...rest, prices_count: Object.keys(prices || {}).length, manual_prices: Object.entries(sources || {}).filter(([, s]) => s === 'manual').map(([s]) => ({ symbol: s, price: prices[s] })) },
    clients,
    missing_prices: missing,
    totals: { clients: clients.length, realized: sum('realized'), mtm: sum('mtm'), interest: sum('interest'), brokerage: sum('brokerage'), gross_pnl: sum('gross_pnl') },
  };
}

/** Enter closes by hand for scripts the bhav copy didn't have (preview only). */
async function setPrices(cash, id, prices) {
  const run = await EqMonthRun.findOne({ _id: id, status: 'PREVIEW' });
  if (!run) throw new HttpError(404, 'Preview not found (only a preview can change prices)');
  const entries = Object.entries(prices || {});
  if (!entries.length) throw new HttpError(400, 'Give at least one SYMBOL: price');
  for (const [sym, p] of entries) {
    const price = Number(p);
    if (!/^[A-Z0-9&-]{1,20}$/.test(sym) || !(price > 0)) throw new HttpError(400, `Bad price for ${sym}`);
    run.prices = { ...run.prices, [sym]: r2(price) };
    run.sources = { ...run.sources, [sym]: 'manual' };
  }
  run.markModified?.('prices');
  run.markModified?.('sources');
  await run.save();
  await audit(cash, 'month_prices_manual', run, { prices });
  return withBill(run);
}

/** Saturday 03:00–05:30 IST: the F&O weekly settlement runs then — equity month-end waits. */
function inFnoSettlementWindow(at = new Date()) {
  const ist = new Date(at.getTime() + 5.5 * 3600_000);
  const minutes = ist.getUTCHours() * 60 + ist.getUTCMinutes();
  return ist.getUTCDay() === 6 && minutes >= 180 && minutes < 330;
}

async function firstActivityDate() {
  const [t, e] = await Promise.all([
    EqTrade.find({ deleted_at: null }).sort({ date: 1 }).limit(1).lean(),
    EqLedgerEntry.find({ deleted_at: null }).sort({ date: 1 }).limit(1).lean(),
  ]);
  return [t[0]?.date, e[0]?.date].filter(Boolean).sort()[0] || null;
}

async function confirm(cash, id, { now = new Date() } = {}) {
  const run = await EqMonthRun.findOne({ _id: id, status: 'PREVIEW' });
  if (!run) throw new HttpError(404, 'Preview not found');
  const today = engine.istNow(now).date;
  if (today < run.settle_date) throw new HttpError(400, `${run.month} can be confirmed from ${run.settle_date} (after the month's last day)`);
  if (inFnoSettlementWindow(now)) throw new HttpError(409, 'The F&O weekly settlement runs now (Saturday 03:00–05:30) — confirm after it');
  if (await EqMonthRun.exists({ status: 'CONFIRMED', month: { $gt: run.month } })) throw new HttpError(400, 'A later month is already confirmed');
  const first = await firstActivityDate();
  if (first) {
    const confirmed = new Set((await EqMonthRun.find({ status: 'CONFIRMED' }).lean()).map((r) => r.month));
    for (let m = first.slice(0, 7); m < run.month; m = monthBounds(m).settle.slice(0, 7)) {
      if (!confirmed.has(m)) throw new HttpError(400, `Confirm ${m} first (months go in order)`);
    }
  }
  const { clients, masters } = await computeClients(run.toObject ? run.toObject() : run);
  const missing = [...new Set(clients.flatMap((c) => c.missing_prices))].sort();
  if (missing.length) throw new HttpError(400, `No close price for ${missing.join(', ')} — enter it first`, { missing_prices: missing });
  run.clients = clients;
  run.masters = masters.map((m) => ({
    _id: String(m._id), parent_id: m.parent_id ? String(m.parent_id) : null, username: m.username, name: m.name,
    pnl_share: m.pnl_share, brokerage_share: m.brokerage_share, interest_share: m.interest_share,
  }));
  run.status = 'CONFIRMED';
  run.confirmed_by = actorOf(cash);
  run.confirmed_at = new Date();
  await run.save();
  await audit(cash, 'month_confirm', run, { clients: clients.length, price_date: run.price_date });
  return withBill(run);
}

async function remove(cash, id) {
  const run = await EqMonthRun.findOne({ _id: id, status: 'CONFIRMED' });
  if (!run) throw new HttpError(404, 'Confirmed month not found');
  if (await EqMonthRun.exists({ status: 'CONFIRMED', month: { $gt: run.month } })) throw new HttpError(400, 'Only the latest confirmed month can be deleted');
  run.status = 'DELETED';
  run.deleted_by = actorOf(cash);
  run.deleted_at = new Date();
  await run.save();
  await audit(cash, 'month_delete', run);
  return { deleted: run.month };
}

async function list() {
  const runs = await EqMonthRun.find({ status: { $in: ['PREVIEW', 'CONFIRMED'] } }).sort({ month: -1 }).lean();
  return runs.map(({ prices, sources, clients, masters, ...r }) => ({ ...r, clients: (clients || []).length, prices_count: Object.keys(prices || {}).length }));
}

/** Sharing statement for a confirmed month, from the caller's point of view. */
async function sharingFor(cash, month) {
  monthBounds(month);
  const run = await EqMonthRun.findOne({ month, status: 'CONFIRMED' }).lean();
  if (!run) throw new HttpError(404, `${month} is not confirmed yet`);
  return require('./sharing').statement({ role: cash.role, id: cash.id }, run);
}

module.exports = {
  HttpError, parseBhav, downloadBhav, bhavForMonth, monthBounds, confirmedSettlements, preview, setPrices, confirm, remove, list,
  sharingFor, inFnoSettlementWindow, computeClients,
};
