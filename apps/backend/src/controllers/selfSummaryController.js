'use strict';

/**
 * Self Summary (scope view) — GET /api/master/positions/self-summary
 *
 * REPORT-ONLY, READ-ONLY (user, 5 Nov 2026): nothing here writes to the
 * database, and no other report shares this code path — the existing
 * Scriptwise P&L endpoint (scriptwisePnlController.js, also used by the
 * mobile app), the Weekly Admin Report, the ledger, settlement and bills are
 * untouched. Helpers from those files are only *called*, never changed.
 *
 * Query: from, to (YYYY-MM-DD, required), exchange, search,
 *        tradingsymbol + script_exchange (scope level), parent_id (drill).
 *
 *  - Level 1 (no tradingsymbol): one row per script across the caller's whole
 *    hierarchy.
 *  - Scope level (tradingsymbol given): one row per DIRECT child of
 *    `parent_id` (default: the caller) for that script — each direct client
 *    on its own, each direct sub-master as ONE row covering its whole tree.
 *
 * Figures per row (all from the caller's point of view):
 *  - Buy/Sell Qty and avg rates from the period's real fills; the avg rates
 *    carry brokerage (buy + brk/qty, sell − brk/qty), like the reference.
 *  - Total M2M (client side) = realised P&L (Σ trade.pnl, the same source and
 *    trade set as the Weekly Admin Report) + open M2M (metricsEngine live
 *    position floating P&L) − brokerage charged on the period's trades.
 *  - Split by the ceiling sharing model (weeklyAdminController._ceilingPct):
 *    Self = caller% − the % handed to the sub-master on that line (all of the
 *    caller's % for a direct client), Downline = that sub-master's %,
 *    Upline = 100 − caller%. Each is applied to −Total (house side).
 *    NOTE: a plain % of the net figure, like the reference screen — the
 *    ledger's brokerage share (rate-gap rule) is not reproduced here.
 *  - Self Qty = Σ client net qty × Self%.
 */

const Trade = require('../models/Trade');
const User = require('../models/User');
const Master = require('../models/Master');
const KiteInstrument = require('../models/KiteInstrument');
const { getAllSubMasterIds } = require('../services/masterHierarchyService');
const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
const { escapeRegex } = require('../utils/escapeRegex');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;
const MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/** "NFO-FUT" → "NSEFUT", "MCX-OPT" → "MCXOPT", like the reference's Market Name. */
function marketName(segment, exchange) {
  const seg = String(segment || '').toUpperCase();
  const [ex, kind] = seg.split('-');
  const exMap = { NFO: 'NSE', BFO: 'BSE', MCX: 'MCX', COMEX: 'COMEX', CDS: 'CDS', NSE: 'NSE', BSE: 'BSE', INDICES: 'GLOBAL', GLOBAL: 'GLOBAL' };
  const base = exMap[ex] || ex || String(exchange || '').toUpperCase();
  return kind ? `${base}${kind}` : base;
}

/** "ABB 23NOV2026", "BANKNIFTY 50000 PE 23NOV2026" — the reference's Script Name. */
function scriptName(ki, tradingsymbol) {
  if (!ki?.name) return tradingsymbol;
  if (!ki.expiry) return ki.name;
  const d = new Date(ki.expiry);
  const exp = `${String(d.getUTCDate()).padStart(2, '0')}${MONTHS[d.getUTCMonth()]}${d.getUTCFullYear()}`;
  if (ki.instrument_type === 'CE' || ki.instrument_type === 'PE') {
    return `${ki.name} ${ki.strike ?? ''} ${ki.instrument_type} ${exp}`.replace(/\s+/g, ' ');
  }
  return `${ki.name} ${exp}`;
}

/**
 * Sharing split for one client, from the viewer's point of view (ceiling
 * model, same rule as weeklyAdminController._ceilingPct). Returns the client's
 * line: which direct child of `rootId` it sits under, and self/down/up %.
 *
 * masterMap: id → { master_id, pnl_sharing }. viewer: { id, role }.
 */
function lineFor(userMasterId, viewer, masterMap) {
  const viewerPct = viewer.role === 'admin' ? 100 : Number(masterMap[viewer.id]?.pnl_sharing) || 0;
  // Walk up from the client's master to the master directly below the viewer.
  const chain = []; // client's master first, up to (excluding) the viewer
  let cur = userMasterId ? String(userMasterId) : null;
  const seen = new Set();
  while (cur && !seen.has(cur)) {
    seen.add(cur);
    if (viewer.role !== 'admin' && cur === String(viewer.id)) break;
    chain.push(cur);
    const parent = masterMap[cur]?.master_id ? String(masterMap[cur].master_id) : null;
    cur = parent;
  }
  // chain[last] is the viewer's direct child master on this line (none = direct client).
  const childUnderViewer = chain.length > 0 ? chain[chain.length - 1] : null;
  const downPct = childUnderViewer ? Number(masterMap[childUnderViewer]?.pnl_sharing) || 0 : 0;
  return {
    chain, // client's master … viewer's direct child
    selfPct: Math.max(0, viewerPct - downPct),
    downPct,
    upPct: Math.max(0, 100 - viewerPct),
  };
}

function emptyAgg() {
  return { buy_qty: 0, buy_value: 0, buy_brk: 0, sell_qty: 0, sell_value: 0, sell_brk: 0, net_qty: 0,
    self_qty: 0, brokerage: 0, realised: 0, floating: 0, total_m2m: 0, self_m2m: 0, downline_m2m: 0, upline_m2m: 0, ltp: null };
}

/** Adds one client's per-script figures (already split) into an aggregate. */
function addInto(agg, f) {
  for (const k of ['buy_qty', 'buy_value', 'buy_brk', 'sell_qty', 'sell_value', 'sell_brk', 'net_qty', 'self_qty',
    'brokerage', 'realised', 'floating', 'total_m2m', 'self_m2m', 'downline_m2m', 'upline_m2m']) agg[k] += f[k] || 0;
  if (f.ltp != null) agg.ltp = f.ltp;
}

/** Final shape of a row (rates carry brokerage, everything rounded). */
function finish(agg) {
  return {
    buy_qty: r2(agg.buy_qty),
    buy_avg: agg.buy_qty > 0 ? r2((agg.buy_value + agg.buy_brk) / agg.buy_qty) : 0,
    sell_qty: r2(agg.sell_qty),
    sell_avg: agg.sell_qty > 0 ? r2((agg.sell_value - agg.sell_brk) / agg.sell_qty) : 0,
    net_qty: r2(agg.net_qty),
    self_qty: r2(agg.self_qty),
    ltp: agg.ltp != null ? r2(agg.ltp) : null,
    brokerage: r2(agg.brokerage),
    realised_pnl: r2(agg.realised),
    m2m_pnl: r2(agg.floating),
    self_m2m: r2(agg.self_m2m),
    downline_m2m: r2(agg.downline_m2m),
    upline_m2m: r2(agg.upline_m2m),
    total_m2m: r2(agg.total_m2m),
  };
}

/**
 * Pure core (no DB): per (client, script) figures → split → rows.
 *
 * perUserScript: Map `${uid}::${token}` → { uid, token, buy_qty, buy_value, buy_brk,
 *   sell_qty, sell_value, sell_brk, brokerage, realised, floating, ltp }
 */
function buildRows({ perUserScript, userMaster, masterMap, viewer, tokenFilter = null, parentId = null }) {
  const splitOf = new Map(); // uid → line
  const lineOf = (uid) => {
    if (!splitOf.has(uid)) splitOf.set(uid, lineFor(userMaster.get(uid), viewer, masterMap));
    return splitOf.get(uid);
  };

  const perClient = []; // [{ uid, token, figures }]
  for (const v of perUserScript.values()) {
    if (tokenFilter && v.token !== tokenFilter) continue;
    const line = lineOf(v.uid);
    const net = v.buy_qty - v.sell_qty;
    const total = v.realised + v.floating - v.brokerage;
    perClient.push({
      uid: v.uid,
      token: v.token,
      f: {
        buy_qty: v.buy_qty, buy_value: v.buy_value, buy_brk: v.buy_brk,
        sell_qty: v.sell_qty, sell_value: v.sell_value, sell_brk: v.sell_brk,
        net_qty: net,
        self_qty: net * line.selfPct / 100,
        brokerage: v.brokerage, realised: v.realised, floating: v.floating,
        total_m2m: total,
        self_m2m: -total * line.selfPct / 100,
        downline_m2m: -total * line.downPct / 100,
        upline_m2m: -total * line.upPct / 100,
        ltp: v.ltp,
      },
    });
  }

  if (!tokenFilter) {
    const byToken = new Map();
    for (const c of perClient) {
      if (!byToken.has(c.token)) byToken.set(c.token, emptyAgg());
      addInto(byToken.get(c.token), c.f);
    }
    return [...byToken.entries()].map(([token, agg]) => ({ token, ...finish(agg) }));
  }

  // Scope level: group the clients by the direct child of `root` on their line.
  const root = parentId ? String(parentId) : (viewer.role === 'admin' ? null : String(viewer.id));
  const byChild = new Map(); // key → { kind, id, agg }
  for (const c of perClient) {
    const own = userMaster.get(c.uid) ? String(userMaster.get(c.uid)) : null;
    let key = null;
    let kind = null;
    if (own === root) {
      key = `user:${c.uid}`; kind = 'client';
    } else {
      // Walk up from the client's master to the master whose parent is `root`.
      let cur = own;
      const seen = new Set();
      let found = null;
      while (cur && !seen.has(cur)) {
        seen.add(cur);
        const parent = masterMap[cur]?.master_id ? String(masterMap[cur].master_id) : null;
        if (parent === root) { found = cur; break; }
        cur = parent;
      }
      if (!found) continue; // not under this parent
      key = `master:${found}`; kind = 'master';
    }
    if (!byChild.has(key)) byChild.set(key, { kind, id: key.split(':')[1], agg: emptyAgg() });
    addInto(byChild.get(key).agg, c.f);
  }
  return [...byChild.values()].map((x) => ({ kind: x.kind, id: x.id, ...finish(x.agg) }));
}

function totalsOf(rows) {
  const t = emptyAgg();
  for (const r of rows) {
    t.buy_qty += r.buy_qty; t.sell_qty += r.sell_qty; t.net_qty += r.net_qty; t.self_qty += r.self_qty;
    t.brokerage += r.brokerage; t.realised += r.realised_pnl; t.floating += r.m2m_pnl;
    t.self_m2m += r.self_m2m; t.downline_m2m += r.downline_m2m; t.upline_m2m += r.upline_m2m; t.total_m2m += r.total_m2m;
  }
  return {
    buy_qty: r2(t.buy_qty), sell_qty: r2(t.sell_qty), net_qty: r2(t.net_qty), self_qty: r2(t.self_qty),
    brokerage: r2(t.brokerage), realised_pnl: r2(t.realised), m2m_pnl: r2(t.floating),
    self_m2m: r2(t.self_m2m), downline_m2m: r2(t.downline_m2m), upline_m2m: r2(t.upline_m2m), total_m2m: r2(t.total_m2m),
  };
}

const getSelfSummary = async (req, res) => {
  try {
    const { from, to, exchange, search, tradingsymbol, script_exchange: scriptExchange, parent_id: parentId } = req.query;
    if (!from || !to) return res.status(400).json({ success: false, message: 'from and to are required', data: null });
    let fromDate = new Date(`${from}T00:00:00.000Z`);
    let toDate = new Date(`${to}T23:59:59.999Z`);
    if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) {
      return res.status(400).json({ success: false, message: 'Invalid from/to date', data: null });
    }
    ({ from: fromDate, to: toDate } = require('../utils/specialSessions').adjustReportWindow(fromDate, toDate));

    const viewer = req.master ? { id: String(req.master.id), role: 'master' } : { id: null, role: 'admin' };

    // ── Scope: the caller's whole tree (same as the Scriptwise report). ──
    const userFilter = { deleted_at: null };
    let allowedMasterIds = null;
    if (req.master) {
      allowedMasterIds = (await getAllSubMasterIds(req.master.id)).map(String);
      userFilter.master_id = { $in: allowedMasterIds };
    } else {
      const hidden = await resolveHiddenMasterIds(req);
      if (hidden) userFilter.master_id = { $nin: [...hidden] };
    }
    if (parentId) {
      const ok = req.master ? allowedMasterIds.includes(String(parentId)) : true;
      if (!ok) return res.status(403).json({ success: false, message: 'Not in your hierarchy', data: null });
    }

    const users = await User.find(userFilter).select('_id name username master_id').lean();
    const masters = await Master.find({}).select('_id name username master_id pnl_sharing').lean();
    const masterMap = Object.fromEntries(masters.map((m) => [String(m._id), m]));
    const userMaster = new Map(users.map((u) => [String(u._id), u.master_id ? String(u.master_id) : null]));
    if (users.length === 0) return res.status(200).json({ success: true, data: { rows: [], totals: totalsOf([]) } });
    const userIds = users.map((u) => u._id);

    // ── The period's trades — the same set as the Weekly Admin Report: live
    // trades (no carry_forward marker) + trades of already-settled weeks
    // (incl. settlement's close/reopen legs, which carry the week-end P&L).
    const trades = await Trade.find({
      user_id: { $in: userIds },
      status: 'completed',
      executed_at: { $gte: fromDate, $lte: toDate },
      $or: [
        { deleted_at: null, trade_type: { $ne: 'carry_forward' } },
        { deleted_at: { $ne: null }, settlement_run_id: { $ne: null } },
      ],
    }).select('user_id instrument_token exchange tradingsymbol transaction_type executed_price executed_quantity pnl brokerage brokerage_exempt trade_type settlement_run_id').lean();

    const metricsEngine = require('../services/metricsEngine');
    const positionsByUser = new Map();
    for (const u of users) {
      const m = metricsEngine.getCachedMetrics(String(u._id));
      if (m?.positions?.length) positionsByUser.set(String(u._id), m.positions);
    }

    const tokens = new Set(trades.map((t) => String(t.instrument_token)));
    for (const list of positionsByUser.values()) for (const p of list) tokens.add(String(p.instrument_token));
    const kis = await KiteInstrument.find({ instrument_token: { $in: [...tokens] } })
      .select('instrument_token tradingsymbol name raw_name expiry instrument_type strike segment exchange lot_size').lean();
    const kiteMap = Object.fromEntries(kis.map((k) => [String(k.instrument_token), k]));

    // Settled COMEX weeks count in rupees, exactly as the Weekly Admin Report
    // does (its own helper, called on an in-memory copy).
    const tradesByUser = {};
    for (const t of trades) {
      const uid = String(t.user_id);
      (tradesByUser[uid] = tradesByUser[uid] || []).push({ ...t, instrument_token: String(t.instrument_token) });
    }
    await require('./weeklyAdminController')._private._applyComexSettlementRates(tradesByUser, kiteMap);

    const keep = (token) => {
      const ki = kiteMap[token];
      if (exchange && (ki?.exchange || '') !== exchange) return false;
      if (tradingsymbol) {
        if ((ki?.tradingsymbol || '') !== tradingsymbol) return false;
        if (scriptExchange && (ki?.exchange || '') !== scriptExchange) return false;
      }
      return true;
    };

    const perUserScript = new Map();
    const slot = (uid, token) => {
      const key = `${uid}::${token}`;
      if (!perUserScript.has(key)) {
        perUserScript.set(key, { uid, token, buy_qty: 0, buy_value: 0, buy_brk: 0, sell_qty: 0, sell_value: 0, sell_brk: 0,
          brokerage: 0, realised: 0, floating: 0, ltp: null });
      }
      return perUserScript.get(key);
    };
    for (const [uid, list] of Object.entries(tradesByUser)) {
      for (const t of list) {
        if (!keep(t.instrument_token)) continue;
        const s = slot(uid, t.instrument_token);
        s.realised += Number(t.pnl) || 0;
        if (t.trade_type === 'carry_forward') continue; // settlement legs: P&L only, not a real fill
        const qty = Number(t.executed_quantity) || 0;
        const val = qty * (Number(t.executed_price) || 0);
        const brk = t.brokerage_exempt ? 0 : Number(t.brokerage) || 0;
        s.brokerage += brk;
        if (t.transaction_type === 'BUY') { s.buy_qty += qty; s.buy_value += val; s.buy_brk += brk; }
        else { s.sell_qty += qty; s.sell_value += val; s.sell_brk += brk; }
      }
    }
    for (const [uid, list] of positionsByUser) {
      for (const p of list) {
        const token = String(p.instrument_token);
        if (!keep(token) || !p.net_qty) continue;
        const s = slot(uid, token);
        s.floating += Number(p.floating_pnl) || 0;
        s.ltp = p.ltp;
      }
    }
    for (const s of perUserScript.values()) {
      if (s.ltp == null) {
        const l = metricsEngine._ltpMap?.get(s.token);
        if (l) s.ltp = l;
      }
    }

    // Level 1 or scope level.
    let tokenFilter = null;
    if (tradingsymbol) {
      // keep() already narrowed every slot to this one script.
      tokenFilter = [...perUserScript.values()][0]?.token || '__none__';
    }
    let rows = buildRows({ perUserScript, userMaster, masterMap, viewer, tokenFilter, parentId });

    if (!tokenFilter) {
      rows = rows.map((r) => {
        const ki = kiteMap[r.token];
        return { ...r, market: marketName(ki?.segment, ki?.exchange), exchange: ki?.exchange || '',
          tradingsymbol: ki?.tradingsymbol || r.token, script: scriptName(ki, ki?.tradingsymbol || r.token) };
      });
      if (search) {
        const re = new RegExp(escapeRegex(search), 'i');
        rows = rows.filter((r) => re.test(r.script) || re.test(r.tradingsymbol));
      }
      rows.sort((a, b) => a.market.localeCompare(b.market) || a.script.localeCompare(b.script));
    } else {
      const ki = kiteMap[tokenFilter];
      const usersById = new Map(users.map((u) => [String(u._id), u]));
      rows = rows.map((r) => {
        const acct = r.kind === 'client' ? usersById.get(r.id) : masterMap[r.id];
        return { ...r, name: acct?.name || '', username: acct?.username || '',
          market: marketName(ki?.segment, ki?.exchange), script: scriptName(ki, ki?.tradingsymbol || tradingsymbol) };
      });
      if (search) {
        const re = new RegExp(escapeRegex(search), 'i');
        rows = rows.filter((r) => re.test(r.name) || re.test(r.username));
      }
      rows.sort((a, b) => (a.kind === b.kind ? 0 : a.kind === 'client' ? -1 : 1) || String(a.name).localeCompare(String(b.name)));
    }

    const parent = parentId ? masterMap[String(parentId)] : null;
    res.status(200).json({
      success: true,
      data: {
        rows,
        totals: totalsOf(rows),
        parent: parent ? { id: String(parent._id), name: parent.name, username: parent.username, master_id: parent.master_id ? String(parent.master_id) : null } : null,
      },
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

module.exports = { getSelfSummary, _private: { marketName, scriptName, lineFor, buildRows, totalsOf } };
