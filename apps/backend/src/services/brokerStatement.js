'use strict';

/**
 * Broker statement (owner, 11 Nov 2026) — what a broker earns from the clients
 * (or the sub-master's tree) linked to him: his share of the brokerage and of
 * the Total P&L, week by week, shown as Total / Below / Self / Upline.
 *
 * TRACKING ONLY. This file never writes anything, and NOTHING in the ledger,
 * weekly report, settlement, sharing or brokerage code reads it or the broker
 * settings — those reports stay exactly as they are; the broker is settled
 * with outside the system, like the Brokers page's brokerage share always was.
 *
 * The "Total" figures are NOT recomputed here: each week's client / sub-master
 * row is read from the SAME weekly report the Ledger page shows
 * (weeklyAdminController.getWeeklyAdminReport, called read-only with the very
 * same query the Ledger page sends: as_master_id = the paying master, date_from
 * = the week's first day 00:00 IST, date_to = the Sunday for a past week, none
 * for the current one). So Total P&L and Total brokerage are the ledger's own.
 *
 * The broker sits between the level below him (the client, or the sub-master S)
 * and the paying master M (the client's master, or S's parent) — the same flat
 * ceiling rule the ledger uses for every level:
 *   P&L        below = Total × below%  (0 for a client, S's own pnl_sharing)
 *              self  = Total × broker%       upline = Total − below − self
 *   Brokerage  incoming = belowClear × (1 − belowBrk%)   (what flows past the
 *              level below: a client's whole brokerage; S's own-rate brokerage
 *              less S's own brokerage-sharing part)
 *              below = Total − incoming
 *              x     = what the broker GETS per his rate field (per fill)
 *              self  = incoming − (belowClear − x) × (1 − (belowBrk% + brokerBrk%))
 *              upline = Total − below − self
 *   i.e. the broker is one more level of the ledger's own chain between S and
 *   M: his rate = the level below's rate − his field, and his ceiling is
 *   CUMULATIVE like every ledger ceiling (S's % + his own %), so 0 / 0 / 0
 *   gives exactly 0 and he is paid only out of M's part (limits: field ≤ S's
 *   rate − M's rate, brokerage % ≤ M's % − S's %, P&L % ≤ M's % − S's %).
 *   Checked by hand against the ledger's own sub-master formula
 *   (weeklyAdminController: incoming pool − own owed-upward).
 * With 0 / 0 / 0 the broker gets nothing; with only the rate field he gets
 * exactly x (client pays 8 paisa, field 3 → broker 3, M keeps 5).
 */

const mongoose = require('mongoose');
const { brokerShare, normSegment, weekStartIST } = require('./brokerEarnings');

const DAY_MS = 864e5;
const IST_OFFSET_MS = 330 * 60 * 1000;
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;

/* -------------------------------------------------------------------- split */

/**
 * One week of one link — pure arithmetic.
 *   totalPnl    the row's Total P&L (house view: a client's loss is positive)
 *   totalBrk    the row's Total brokerage
 *   belowClear  a client: totalBrk; a sub-master S: S's own-rate brokerage (own_brokerage)
 *   belowBrkPct a client: 0; S: S's brokerage_sharing
 *   belowPnlPct a client: 0; S: S's pnl_sharing
 *   x           what the broker gets from his rate field this week (already summed per fill)
 *   pnlPct / brkPct  the broker's two percentages
 */
function brokerWeekSplit({ totalPnl, totalBrk, belowClear, belowBrkPct = 0, belowPnlPct = 0, x = 0, pnlPct = 0, brkPct = 0 }) {
  const T = Number(totalPnl) || 0;
  const B = Number(totalBrk) || 0;
  const clear = Math.max(0, Number(belowClear) || 0);
  const pnlBelow = T * (Number(belowPnlPct) || 0) / 100;
  const pnlSelf = T * (Number(pnlPct) || 0) / 100;

  const incoming = clear * (1 - (Number(belowBrkPct) || 0) / 100);
  const xCapped = Math.min(Math.max(0, Number(x) || 0), clear);
  const brkBelow = B - incoming;
  // Cumulative ceiling, like the ledger: the level below's own % plus the broker's own %.
  const brkSelf = incoming - (clear - xCapped) * (1 - ((Number(belowBrkPct) || 0) + (Number(brkPct) || 0)) / 100);

  return {
    pnl: { total: r2(T), below: r2(pnlBelow), self: r2(pnlSelf), upline: r2(T - pnlBelow - pnlSelf) },
    brokerage: { total: r2(B), below: r2(brkBelow), self: r2(brkSelf), upline: r2(B - brkBelow - brkSelf), from_rate: r2(xCapped) },
    net: r2(pnlSelf + brkSelf),
  };
}

/* -------------------------------------------------------------------- weeks */

function ymdOf(instant) {
  return new Date(new Date(instant).getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}
function addDays(ymd, days) {
  const [y, m, d] = ymd.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}
function istStart(ymd) {
  return new Date(`${ymd}T00:00:00+05:30`);
}

/**
 * The settlement weeks from the one containing `since` to the current one
 * (newest first, at most `max`), each with the exact query the Ledger page
 * sends for it (web lib/settlement.ts currentWeekRange / previousWeekRange and
 * MasterLedger.tsx): from = Monday — or the special session Sunday that opens
 * that week — at 00:00 IST; a past week sends date_to = its Sunday, the
 * current week none.
 */
function weekWindows({ since, now = new Date(), max = 12, sessions }) {
  const sessionDays = new Set((sessions || require('../utils/specialSessions').SESSIONS).map((s) => s.date));
  // On a special session day the running week is already the next one.
  const today = ymdOf(now);
  const anchor = sessionDays.has(today) ? new Date(istStart(addDays(today, 1)).getTime() + 1) : now;
  const currentMonday = ymdOf(weekStartIST(anchor));
  const firstMonday = ymdOf(weekStartIST(since || now));
  const out = [];
  for (let monday = currentMonday; monday >= firstMonday && out.length < max; monday = addDays(monday, -7)) {
    const fromYmd = sessionDays.has(addDays(monday, -1)) ? addDays(monday, -1) : monday;
    const nextMonday = addDays(monday, 7);
    const nextFrom = sessionDays.has(addDays(nextMonday, -1)) ? addDays(nextMonday, -1) : nextMonday;
    const current = monday === currentMonday;
    out.push({
      key: fromYmd,
      label: current ? `This week (from ${fromYmd})` : `${fromYmd} to ${addDays(monday, 5)}`,
      current,
      query: current ? { date_from: istStart(fromYmd).toISOString() } : { date_from: istStart(fromYmd).toISOString(), date_to: addDays(monday, 6) },
      start: istStart(fromYmd),
      end: current ? new Date(now) : istStart(nextFrom),
    });
  }
  return out;
}

/** The link that applies to a week: the latest one overlapping it (a change applies to that whole week). */
function linkForWeek(links, week) {
  const s = week.start.getTime();
  const e = week.end.getTime();
  return links
    .filter((l) => new Date(l.from).getTime() < e && (l.to == null || new Date(l.to).getTime() > s))
    .sort((a, b) => new Date(b.from) - new Date(a.from))[0] || null;
}

/* ------------------------------------------------------------- report rows */

/** Runs the weekly report handler read-only (no auth middleware, no writes) and returns its rows. */
function runWeeklyReport(query) {
  const handler = require('../controllers/weeklyAdminController').getWeeklyAdminReport;
  return new Promise((resolve, reject) => {
    const req = {
      method: 'GET',
      query: { ...query },
      params: {},
      body: {},
      headers: {},
      // A read-only admin context with nothing hidden — the handler then
      // switches to as_master_id's own view, exactly as for the Ledger page.
      admin: { id: 'broker-statement', isSuperAdmin: false, watchOnly: true, permissions: [], hiddenMasterIds: [] },
    };
    let status = 200;
    const res = {
      status(code) { status = code; return res; },
      json(body) {
        if (status !== 200 || !body || body.success === false) reject(new Error(body?.message || `weekly report ${status}`));
        else resolve(Array.isArray(body.data) ? body.data : []);
        return res;
      },
    };
    Promise.resolve(handler(req, res)).catch(reject);
  });
}

/* ------------------------------------------------------------ x from fills */

/** The same completed fills the weekly report reads for a window (live + settled), minus carry-forward legs. */
async function fillsFor(userIds, query) {
  if (userIds.length === 0) return [];
  const Trade = require('../models/Trade');
  const { adjustReportWindow } = require('../utils/specialSessions');
  let from = new Date(query.date_from);
  let to = query.date_to ? new Date(query.date_to) : undefined;
  const adj = adjustReportWindow(from, to);
  from = adj.from;
  if (adj.to) to = adj.to;
  const executed_at = { $gte: from };
  if (to) executed_at.$lte = to;
  return Trade.find({
    user_id: { $in: userIds.map((id) => new mongoose.Types.ObjectId(String(id))) },
    status: 'completed',
    executed_at,
    $or: [
      { deleted_at: null, trade_type: { $ne: 'carry_forward' } },
      { deleted_at: { $ne: null }, settlement_run_id: { $ne: null } },
    ],
  }).select('user_id instrument_token executed_price executed_quantity brokerage brokerage_exempt trade_type').lean();
}

/** What the broker's rate field gives on these fills. `capPerFill`: never more than the fill's own brokerage (a client link). */
function xFromFills(fills, rates, instruments, capPerFill) {
  let x = 0;
  for (const t of fills) {
    if (t.trade_type === 'carry_forward' || t.brokerage_exempt) continue;
    const inst = instruments.get(String(t.instrument_token)) || {};
    const segment = normSegment(inst.segment || '');
    const rate = (rates || []).find((r) => normSegment(r.segment) === segment);
    if (!rate || !(rate.value > 0)) continue;
    x += brokerShare({
      type: rate.type,
      value: rate.value,
      price: t.executed_price,
      quantity: t.executed_quantity,
      lotSize: inst.lot_size,
      brokerage: capPerFill ? t.brokerage : undefined,
      exempt: false,
    }).amount;
  }
  return x;
}

/* ---------------------------------------------------------------- statement */

/**
 * The statement for some links over some weeks. Read-only.
 *   clientLinks  BrokerClientLink docs (lean)
 *   masterLinks  BrokerMasterLink docs (lean)
 * Returns { weeks: [{ key, label, current, rows: [...], totals }] }.
 */
async function buildStatement({ clientLinks = [], masterLinks = [], weeks }) {
  const User = require('../models/User');
  const Master = require('../models/Master');
  const KiteInstrument = require('../models/KiteInstrument');
  const { getAllSubMasterIds } = require('./masterHierarchyService');

  const users = await User.find({ _id: { $in: clientLinks.map((l) => l.user_id) } }).select('name username master_id').lean();
  const userById = new Map(users.map((u) => [String(u._id), u]));
  const subMasters = await Master.find({ _id: { $in: masterLinks.map((l) => l.target_master_id) } }).select('name username master_id pnl_sharing brokerage_sharing').lean();
  const subById = new Map(subMasters.map((m) => [String(m._id), m]));
  const payingIds = [...new Set([...users.map((u) => String(u.master_id)), ...subMasters.map((m) => String(m.master_id))].filter((id) => id && id !== 'null' && id !== 'undefined'))];
  const paying = await Master.find({ _id: { $in: payingIds } }).select('name username').lean();
  const payingById = new Map(paying.map((m) => [String(m._id), m]));
  // Clients of each linked sub-master's tree (for the broker's rate field on its fills).
  const treeUsers = new Map();
  for (const m of subMasters) {
    const ids = await getAllSubMasterIds(String(m._id));
    const u = await User.find({ master_id: { $in: ids }, deleted_at: null }).select('_id').lean();
    treeUsers.set(String(m._id), u.map((x) => String(x._id)));
  }

  const out = [];
  for (const week of weeks) {
    const rowsByMaster = new Map();
    const reportRows = async (masterId) => {
      if (!rowsByMaster.has(masterId)) {
        const rows = await runWeeklyReport({ ...week.query, as_master_id: masterId });
        rowsByMaster.set(masterId, new Map(rows.map((r) => [String(r.id), r])));
      }
      return rowsByMaster.get(masterId);
    };

    const weekRows = [];
    // Clients
    const byUser = new Map();
    for (const l of clientLinks) {
      const k = String(l.user_id);
      if (!byUser.has(k)) byUser.set(k, []);
      byUser.get(k).push(l);
    }
    for (const [uid, links] of byUser) {
      const link = linkForWeek(links, week);
      const u = userById.get(uid);
      if (!link || !u || !u.master_id) continue;
      const row = (await reportRows(String(u.master_id))).get(uid) || {};
      const fills = await fillsFor([uid], week.query);
      const instruments = await instrumentMap(KiteInstrument, fills);
      const totalBrk = Number(row.brokerage) || 0;
      const split = brokerWeekSplit({
        totalPnl: row.total_pnl,
        totalBrk,
        belowClear: totalBrk,
        x: xFromFills(fills, link.rates, instruments, true),
        pnlPct: link.pnl_share_pct,
        brkPct: link.brk_share_pct,
      });
      weekRows.push({
        target: { type: 'client', id: uid, name: u.name, username: u.username },
        paying_master: shape(payingById.get(String(u.master_id))),
        broker_id: String(link.broker_id),
        settings: settingsOf(link),
        ...split,
      });
    }
    // Sub-masters
    const byMaster = new Map();
    for (const l of masterLinks) {
      const k = String(l.target_master_id);
      if (!byMaster.has(k)) byMaster.set(k, []);
      byMaster.get(k).push(l);
    }
    for (const [mid, links] of byMaster) {
      const link = linkForWeek(links, week);
      const s = subById.get(mid);
      if (!link || !s || !s.master_id) continue;
      const row = (await reportRows(String(s.master_id))).get(mid) || {};
      const fills = await fillsFor(treeUsers.get(mid) || [], week.query);
      const instruments = await instrumentMap(KiteInstrument, fills);
      const split = brokerWeekSplit({
        totalPnl: row.total_pnl,
        totalBrk: row.brokerage,
        belowClear: row.own_brokerage,
        belowBrkPct: s.brokerage_sharing,
        belowPnlPct: s.pnl_sharing,
        x: xFromFills(fills, link.rates, instruments, false),
        pnlPct: link.pnl_share_pct,
        brkPct: link.brk_share_pct,
      });
      weekRows.push({
        target: { type: 'master', id: mid, name: s.name, username: s.username },
        paying_master: shape(payingById.get(String(s.master_id))),
        broker_id: String(link.broker_id),
        settings: settingsOf(link),
        ...split,
      });
    }

    const sum = (path) => r2(weekRows.reduce((acc, r) => acc + path(r), 0));
    out.push({
      key: week.key,
      label: week.label,
      current: week.current,
      rows: weekRows,
      totals: {
        pnl: { total: sum((r) => r.pnl.total), below: sum((r) => r.pnl.below), self: sum((r) => r.pnl.self), upline: sum((r) => r.pnl.upline) },
        brokerage: { total: sum((r) => r.brokerage.total), below: sum((r) => r.brokerage.below), self: sum((r) => r.brokerage.self), upline: sum((r) => r.brokerage.upline) },
        net: sum((r) => r.net),
      },
    });
  }
  return { weeks: out };
}

async function instrumentMap(KiteInstrument, fills) {
  const tokens = [...new Set(fills.map((t) => t.instrument_token))];
  if (tokens.length === 0) return new Map();
  const insts = await KiteInstrument.find({ instrument_token: { $in: tokens } }).select('instrument_token segment lot_size').lean();
  return new Map(insts.map((i) => [String(i.instrument_token), { segment: i.segment, lot_size: i.lot_size }]));
}
const shape = (m) => (m ? { id: String(m._id), name: m.name, username: m.username } : null);
const settingsOf = (l) => ({ rates: l.rates || [], pnl_share_pct: Number(l.pnl_share_pct) || 0, brk_share_pct: Number(l.brk_share_pct) || 0, from: l.from, to: l.to });

module.exports = { brokerWeekSplit, weekWindows, linkForWeek, xFromFills, buildStatement, _private: { runWeeklyReport, fillsFor } };
