'use strict';

// Live equity account (M5): per client — client money, margin used (per category),
// funded, interest so far this month (two rates, proportional split), P&L since the last
// month-end (booked + open MTM at live prices), holdings, limit use, loss alert flag;
// and the same across a master's tree. All numbers come from engine.js (Trade Terminal
// port) so they match the statement and the month-end bill.

const engine = require('./engine');
const rules = require('./rules');
const book = require('./book');
const feed = require('./feed');
const { EqClient, EqLedgerEntry, EqInstrument } = require('./models');

const LOSS_ALERT_PCT = 80; // D1: alert only (no automatic cut) when the loss reaches 80 % of client money

const r2 = engine.round2;

/** Confirmed month-ends in engine shape (eqcash_month_runs, M6). */
async function monthEnds() {
  return require('./monthEnd').confirmedSettlements();
}

function toEngineEntry(e, clientCode) {
  return { id: String(e._id), clientCode, date: e.date, kind: e.kind, amount: e.amount, narration: e.narration || '' };
}

/** Everything for one client as of `asOf` (default today, IST), with live prices. */
async function accountFor(client, { asOf } = {}) {
  const day = asOf || engine.istNow().date;
  const code = String(client._id);
  const [trades, entriesRaw, settlements] = await Promise.all([
    book.loadTrades(client._id),
    EqLedgerEntry.find({ client_id: client._id, deleted_at: null }).lean(),
    monthEnds(),
  ]);
  const calcs = book.calcsFor(client, trades);
  const entries = entriesRaw.map((e) => toEngineEntry(e, code));
  const ledger = engine.computeClientLedger(rules.toAccount(client), trades, calcs, entries, settlements, day);

  // P&L since the last month-end: carried positions + this month's trades, at live prices.
  const carried = engine.carryToSettlement(trades.filter((t) => t.date <= day), calcs, settlements, day);
  const tokenOf = new Map(trades.map((t) => [t.script, t.token]));
  const tokens = [...new Set(trades.map((t) => t.token))];
  const quotes = new Map(feed.getQuotes(tokens).map((q) => [q.instrument_token, q]));
  const live = {};
  for (const [script, token] of tokenOf) {
    const q = quotes.get(token);
    if (q?.last_price > 0) live[`NSEEQ|${script}`] = q.last_price;
  }
  const positions = engine.computePositions(carried.trades, carried.calcs, live);
  const insts = await EqInstrument.find({ instrument_token: { $in: tokens } }).select('instrument_token tradingsymbol name mtf').lean();
  const instOf = new Map(insts.map((i) => [i.tradingsymbol, i]));

  // Margin (open lots at cost/carry) per script, for limit use.
  const { holdings: lots } = book.holdingsFrom(client, trades.filter((t) => t.date <= day));
  const holdings = positions.filter((p) => p.netQty > 0).map((p) => {
    const script = p.label;
    const q = quotes.get(tokenOf.get(script));
    const margin = lots.get(script)?.value || 0;
    return {
      script,
      name: instOf.get(script)?.name || script,
      instrument_token: tokenOf.get(script),
      approved: !!instOf.get(script)?.mtf,
      qty: p.netQty,
      avg_price: r2(p.avgBuy), // net of brokerage (carry price for lots carried over a month-end)
      ltp: p.lastRate,
      live: p.live,
      change_percent: q?.change_percent ?? null,
      value: r2(p.netQty * p.lastRate),
      mtm: r2(p.mtm),
      margin: r2(margin),
      per_script_room: r2(Math.max(0, client.per_script_limit - margin)),
    };
  }).sort((a, b) => a.script.localeCompare(b.script));

  const totalPnl = positions.reduce((a, p) => a + p.realized + p.mtm, 0); // since the last month-end
  const booked = ledger.pendingPnl; // FIFO-closed lots + intraday — what the month-end posts as P&L
  const since = carried.since ? carried.since.settleDate : null;
  const brokerage = trades.filter((t) => !since || t.date >= since).reduce((a, t) => a + (calcs.get(t.id)?.brokerage || 0), 0);
  const holdingsValue = holdings.reduce((a, h) => a + h.value, 0);
  const net = totalPnl - ledger.accruedInterest;
  const lossPct = ledger.money > 0 && net < 0 ? (-net / ledger.money) * 100 : null;
  const limitTotalUsed = [...lots.values()].reduce((a, h) => a + h.value, 0);

  return {
    as_of: day,
    since_month_end: since,
    client: { _id: client._id, name: client.name, username: client.username, master_id: client.master_id, status: client.status },
    summary: {
      client_money: r2(ledger.money),
      margin_used: r2(ledger.margin),
      margin_approved: r2(ledger.marginMtf ?? ledger.margin),
      margin_non_approved: r2(ledger.marginNon ?? 0),
      funded: r2(ledger.funded),
      interest_this_month: r2(ledger.accruedInterest),
      interest_approved: r2(ledger.accruedInterestMtf ?? ledger.accruedInterest),
      interest_non_approved: r2(ledger.accruedInterestNon ?? 0),
      booked_pnl: r2(booked),
      open_mtm: r2(totalPnl - booked),
      pnl_since_month_end: r2(totalPnl),
      brokerage_this_month: r2(brokerage),
      net_equity: r2(ledger.money + net),
      holdings_value: r2(holdingsValue),
      limits: {
        per_script_limit: client.per_script_limit,
        total_limit: client.total_limit,
        total_used: r2(limitTotalUsed),
        total_room: r2(Math.max(0, client.total_limit - limitTotalUsed)),
        total_use_pct: client.total_limit > 0 ? r2((limitTotalUsed / client.total_limit) * 100) : null,
      },
      loss_pct_of_money: lossPct === null ? null : r2(lossPct),
      loss_alert: lossPct !== null && lossPct >= LOSS_ALERT_PCT,
      rates: {
        interest_approved_pct: client.interest_mtf_pct, interest_non_approved_pct: client.interest_non_pct,
      },
    },
    holdings,
    warnings: ledger.warnings,
  };
}

/** Statement rows (client money ledger with daily interest) between two dates. */
async function statementFor(client, { from, to } = {}) {
  const end = to || engine.istNow().date;
  const code = String(client._id);
  const [trades, entriesRaw, settlements] = await Promise.all([
    book.loadTrades(client._id),
    EqLedgerEntry.find({ client_id: client._id, deleted_at: null }).lean(),
    monthEnds(),
  ]);
  const calcs = book.calcsFor(client, trades);
  const ledger = engine.computeClientLedger(rules.toAccount(client), trades, calcs, entriesRaw.map((e) => toEngineEntry(e, code)), settlements, end);
  const start = from || (ledger.rows[0]?.date ?? end);
  const before = ledger.rows.filter((r) => r.date < start).pop();
  return {
    client: { _id: client._id, name: client.name, username: client.username },
    from: start,
    to: end,
    opening: before ? { money: r2(before.money), margin: r2(before.margin) } : null,
    rows: ledger.rows.filter((r) => r.date >= start && r.date <= end),
    closing: { money: r2(ledger.money), margin: r2(ledger.margin), funded: r2(ledger.funded), interest_not_posted: r2(ledger.accruedInterest) },
    settlements: ledger.settlements,
  };
}

/** Every visible client's account + totals (master / admin screens). */
async function accountsFor(clients) {
  const out = [];
  for (const c of clients) out.push(await accountFor(c));
  const sum = (k) => r2(out.reduce((a, x) => a + (x.summary[k] || 0), 0));
  return {
    totals: {
      clients: out.length,
      client_money: sum('client_money'),
      holdings_value: sum('holdings_value'),
      margin_used: sum('margin_used'),
      funded: sum('funded'),
      interest_this_month: sum('interest_this_month'),
      pnl_since_month_end: sum('pnl_since_month_end'),
      open_mtm: sum('open_mtm'),
      brokerage_this_month: sum('brokerage_this_month'),
      loss_alerts: out.filter((x) => x.summary.loss_alert).length,
    },
    accounts: out,
  };
}

/** Equity clients the caller may see; `masterId` narrows to that master's tree. */
async function visibleClients(cash, masterId) {
  const { subtreeIds } = require('./controller')._internals;
  if (cash.role === 'cash_client') return [cash.doc.toObject ? cash.doc.toObject() : cash.doc];
  let masters = null;
  if (cash.role === 'cash_master') masters = await subtreeIds(cash.id);
  if (masterId) {
    if (masters && !masters.has(String(masterId))) return null;
    masters = await subtreeIds(masterId);
  }
  const q = { deleted_at: null };
  if (masters) q.master_id = { $in: [...masters] };
  return EqClient.find(q).sort({ createdAt: 1 }).lean();
}

/** One client the caller may read (watch-only admins too). Throws { status, message }. */
async function clientFor(cash, clientId) {
  const err = (status, message) => Object.assign(new Error(message), { status });
  if (cash.role === 'cash_client') {
    if (clientId && String(clientId) !== cash.id) throw err(403, 'Not your account');
    return cash.doc.toObject ? cash.doc.toObject() : cash.doc;
  }
  if (!clientId) throw err(400, 'Choose the client');
  const client = await EqClient.findOne({ _id: clientId, deleted_at: null }).lean();
  if (!client) throw err(404, 'Equity client not found');
  if (cash.role === 'cash_master') {
    const { subtreeIds } = require('./controller')._internals;
    if (!(await subtreeIds(cash.id)).has(String(client.master_id))) throw err(403, 'Not your equity client');
  }
  return client;
}

module.exports = { accountFor, statementFor, accountsFor, visibleClients, clientFor, monthEnds, LOSS_ALERT_PCT };
