const Trade = require('../models/Trade');
const User = require('../models/User');
const Master = require('../models/Master');
const KiteInstrument = require('../models/KiteInstrument');
const SettlementHistory = require('../models/SettlementHistory');
const { getLatestQuotes } = require('../services/kiteService');
const { getAllSubMasterIds } = require('../services/masterHierarchyService');
const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
const { escapeRegex } = require('../utils/escapeRegex');
const { computeAveragePricePnl } = require('../utils/averageCostPnl');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/**
 * GET /api/master/positions/scriptwise-pnl
 * Query: from, to (required, ISO dates), exchange, tradingsymbol, user_id, search
 *
 * Two modes off the same endpoint, matching the target UI's two screens:
 *  - Summary (no tradingsymbol given): one row per script across the
 *    caller's WHOLE hierarchy (master's full subtree via
 *    getAllSubMasterIds, or everyone for admin) — realized P&L
 *    (average-cost, carry-forward seeded, same engine GET /api/trade/report
 *    uses, see utils/averageCostPnl.js), floating/M2M P&L (live open
 *    positions), brokerage, and their total.
 *  - Detail (exchange + tradingsymbol given): same figures, but one row
 *    PER USER who holds/held a position in that specific script.
 *
 * Scope decision: brokerage is summed directly from Trade.brokerage
 * (authoritative — set once at execution by the shared calculateBrokerage(),
 * brokerageService.js) rather than replicating GET /api/trade/report's
 * per-trade effective-rate recomputation, which only makes sense for a
 * SINGLE target account's own brokerage rules. Across an entire multi-user
 * subtree that would mean resolving each trade's owning user's own
 * historical rule set individually — real, but deliberately out of scope
 * for this pass; every real execution path already writes a correct
 * Trade.brokerage (confirmed against brokerageService.js's call sites), so
 * this only under-counts the rare pre-migration row still sitting at 0.
 *
 * Floating/M2M P&L uses the same naive-cumulative-average approach already
 * shipped in userwisePositionController.js's getUserwisePositions (a Mongo
 * $group over ALL completed trades ever, not reset on flat-crossings) —
 * matching that already-accepted precedent rather than doing the heavier,
 * more-correct per-trade computeFlatResetState pass across a whole subtree.
 */
const getScriptwisePnl = async (req, res) => {
  try {
    const { from, to, exchange, tradingsymbol, user_id, search } = req.query;
    if (!from || !to) {
      return res.status(400).json({ success: false, message: 'from and to are required', data: null });
    }
    const fromDate = new Date(`${from}T00:00:00.000Z`);
    const toDate = new Date(`${to}T23:59:59.999Z`);
    if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) {
      return res.status(400).json({ success: false, message: 'Invalid from/to date', data: null });
    }

    const detailMode = Boolean(exchange && tradingsymbol);

    // ── Resolve the caller's user scope (whole subtree for a master, ────
    // everyone minus hidden masters for admin) — same pattern as every
    // other hierarchy-wide report in this codebase.
    let userFilter = { deleted_at: null };
    if (req.master) {
      const allMasterIds = await getAllSubMasterIds(req.master.id);
      userFilter.master_id = { $in: allMasterIds };
    } else {
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) userFilter.master_id = { $nin: [...hiddenMasterIds] };
    }
    if (user_id) userFilter._id = user_id;

    const users = await User.find(userFilter).select('_id name username master_id').lean();
    if (users.length === 0) {
      return res.status(200).json({ success: true, data: { rows: [], summary: emptySummary() } });
    }
    const userIds = users.map((u) => u._id);
    const masterIds = [...new Set(users.map((u) => u.master_id?.toString()).filter(Boolean))];
    const masters = await Master.find({ _id: { $in: masterIds } }).select('_id username').lean();
    const masterUsernameById = new Map(masters.map((m) => [m._id.toString(), m.username]));
    const userInfoById = new Map(
      users.map((u) => [
        u._id.toString(),
        { username: u.username, name: u.name, master_username: masterUsernameById.get(u.master_id?.toString()) || '' },
      ]),
    );

    // ── Realized P&L + brokerage: live trades in-window + settled ────────
    // ledger fills in-window, same live+ledger merge GET /api/trade/report
    // uses — without the ledger half, any already-settled week inside the
    // requested range would silently vanish from this report.
    const tradeMatch = {
      user_id: { $in: userIds },
      status: 'completed',
      deleted_at: null,
      trade_type: { $ne: 'carry_forward' },
      executed_at: { $gte: fromDate, $lte: toDate },
    };
    if (exchange) tradeMatch.exchange = exchange;
    if (tradingsymbol) tradeMatch.tradingsymbol = tradingsymbol;

    const liveTrades = await Trade.find(tradeMatch).lean();

    const settlementMatch = {
      user_id: { $in: userIds },
      period_from: { $lte: toDate },
      period_to: { $gte: fromDate },
    };
    const snapshots = await SettlementHistory.find(settlementMatch).lean();

    const ledgerRows = [];
    const seenSourceTradeIds = new Set();
    for (const s of snapshots) {
      if (exchange && s.exchange !== exchange) continue;
      if (tradingsymbol && s.tradingsymbol !== tradingsymbol) continue;
      for (const f of s.fills || []) {
        const sourceTradeId = f.source_trade_id?.toString();
        if (sourceTradeId) {
          if (seenSourceTradeIds.has(sourceTradeId)) continue;
          seenSourceTradeIds.add(sourceTradeId);
        }
        if (!f.executed_at) continue;
        const at = new Date(f.executed_at);
        if (at < fromDate || at > toDate) continue;
        if (f.trade_type === 'carry_forward') continue;
        ledgerRows.push({
          user_id: s.user_id,
          exchange: s.exchange,
          tradingsymbol: s.tradingsymbol,
          instrument_token: s.instrument_token,
          transaction_type: f.transaction_type,
          executed_quantity: f.executed_quantity || 0,
          executed_price: f.executed_price || 0,
          executed_at: at,
          brokerage: f.brokerage || 0,
        });
      }
      if (s.closing_qty > 0 && s.settlement_price > 0) {
        const settleDate = new Date(s.settlement_date || s.period_to);
        if (settleDate >= fromDate && settleDate <= toDate) {
          ledgerRows.push({
            user_id: s.user_id,
            exchange: s.exchange,
            tradingsymbol: s.tradingsymbol,
            instrument_token: s.instrument_token,
            transaction_type: s.closing_side || (s.carry_forward_side === 'BUY' ? 'SELL' : 'BUY'),
            executed_quantity: s.closing_qty,
            executed_price: s.settlement_price,
            executed_at: settleDate,
            brokerage: 0,
          });
        }
      }
    }

    const allWindowTrades = [...liveTrades, ...ledgerRows];

    // Group by (user_id, exchange, tradingsymbol) — the finest grain this
    // report needs; script-level (Level 1) rows are a further rollup of
    // these across users, done after the P&L math below.
    const groups = new Map(); // key -> { user_id, exchange, tradingsymbol, instrument_token, all_trades: [], brokerage }
    const keyFor = (t) => `${t.user_id}::${t.exchange}::${t.tradingsymbol}`;
    for (const t of allWindowTrades) {
      const key = keyFor(t);
      if (!groups.has(key)) {
        groups.set(key, {
          user_id: t.user_id.toString(),
          exchange: t.exchange,
          tradingsymbol: t.tradingsymbol,
          instrument_token: t.instrument_token,
          all_trades: [],
          brokerage: 0,
        });
      }
      const g = groups.get(key);
      g.all_trades.push({
        date: t.executed_at,
        buy_qty: t.transaction_type === 'BUY' ? t.executed_quantity || 0 : 0,
        sell_qty: t.transaction_type === 'SELL' ? t.executed_quantity || 0 : 0,
        rate: t.executed_price || 0,
      });
      g.brokerage += t.brokerage || 0;
    }

    // ── Carry-forward seeds, per (user, instrument) — NOT summed across ──
    // users like GET /api/trade/report's master-target branch does, since
    // this report needs to keep each user's own realized P&L separate for
    // the per-user drill-down.
    const cfMatch = {
      user_id: { $in: userIds },
      status: 'completed',
      trade_type: 'carry_forward',
      executed_at: { $lte: toDate },
    };
    if (exchange) cfMatch.exchange = exchange;
    if (tradingsymbol) cfMatch.tradingsymbol = tradingsymbol;
    const cfTrades = await Trade.find(cfMatch).lean();

    const latestSeedPerKey = new Map();
    for (const t of cfTrades) {
      if (new Date(t.executed_at) > fromDate) continue;
      const key = keyFor(t);
      const existing = latestSeedPerKey.get(key);
      if (!existing || new Date(t.executed_at) > new Date(existing.executed_at)) {
        latestSeedPerKey.set(key, t);
      }
    }
    const seeds = new Map();
    for (const [key, t] of latestSeedPerKey) {
      const qty = t.executed_quantity || 0;
      if (qty <= 0) continue;
      const price = t.executed_price || 0;
      seeds.set(
        key,
        t.transaction_type === 'BUY'
          ? { totalBuyQty: qty, totalBuyValue: qty * price, totalSellQty: 0, totalSellValue: 0 }
          : { totalBuyQty: 0, totalBuyValue: 0, totalSellQty: qty, totalSellValue: qty * price },
      );
    }

    // ── Floating/M2M P&L — same $group-over-all-completed-trades pattern ──
    // already shipped in userwisePositionController.js's getUserwisePositions.
    const floatingMatch = { user_id: { $in: userIds }, status: 'completed', deleted_at: null };
    if (exchange) floatingMatch.exchange = exchange;
    if (tradingsymbol) floatingMatch.tradingsymbol = tradingsymbol;
    const floatingAgg = await Trade.aggregate([
      { $match: floatingMatch },
      {
        $group: {
          _id: { user_id: '$user_id', instrument_token: '$instrument_token' },
          tradingsymbol: { $first: '$tradingsymbol' },
          exchange: { $first: '$exchange' },
          total_buy_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$executed_quantity', 0] } },
          total_sell_qty: { $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, '$executed_quantity', 0] } },
          total_buy_value: {
            $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, { $multiply: ['$executed_quantity', '$executed_price'] }, 0] },
          },
          total_sell_value: {
            $sum: { $cond: [{ $eq: ['$transaction_type', 'SELL'] }, { $multiply: ['$executed_quantity', '$executed_price'] }, 0] },
          },
        },
      },
    ]);
    const openFloating = floatingAgg.filter((p) => p.total_buy_qty - p.total_sell_qty !== 0);
    const openTokens = [...new Set(openFloating.map((p) => parseInt(p._id.instrument_token, 10)))];
    let ltpMap = new Map();
    if (openTokens.length > 0) {
      try {
        const quotes = await getLatestQuotes(openTokens, 100);
        quotes.forEach((q) => ltpMap.set(q.instrument_token.toString(), q.last_price));
      } catch (_) {}
    }
    const floatingByKey = new Map(); // `${user_id}::${exchange}::${tradingsymbol}` -> {net_qty, side, avg_rate, ltp, floating_pnl}
    for (const p of openFloating) {
      const netQty = p.total_buy_qty - p.total_sell_qty;
      const avgBuy = p.total_buy_qty > 0 ? p.total_buy_value / p.total_buy_qty : 0;
      const avgSell = p.total_sell_qty > 0 ? p.total_sell_value / p.total_sell_qty : 0;
      const avgRate = netQty > 0 ? avgBuy : avgSell;
      const ltp = ltpMap.get(p._id.instrument_token) || avgRate;
      const floatingPnl = netQty > 0 ? (ltp - avgBuy) * netQty : (avgSell - ltp) * Math.abs(netQty);
      const key = `${p._id.user_id}::${p.exchange}::${p.tradingsymbol}`;
      floatingByKey.set(key, {
        net_qty: netQty,
        side: netQty > 0 ? 'BUY' : 'SELL',
        avg_rate: Math.round(avgRate * 100) / 100,
        ltp: Math.round(ltp * 100) / 100,
        floating_pnl: Math.round(floatingPnl * 100) / 100,
      });
    }

    // ── Assemble per-(user, script) rows ──────────────────────────────────
    const allKeys = new Set([...groups.keys(), ...floatingByKey.keys()]);
    const perUserScriptRows = [];
    for (const key of allKeys) {
      const [uid, exch, symbol] = key.split('::');
      const g = groups.get(key);
      const realizedPnl = g ? computeAveragePricePnl(g.all_trades, seeds.get(key)) : 0;
      const brokerage = g ? Math.round(g.brokerage * 100) / 100 : 0;
      const floating = floatingByKey.get(key);
      const floatingPnl = floating?.floating_pnl || 0;
      const info = userInfoById.get(uid);
      if (!info) continue; // shouldn't happen, but don't surface a row for a user outside scope
      perUserScriptRows.push({
        user_id: uid,
        username: info.username,
        name: info.name,
        master_username: info.master_username,
        exchange: exch,
        tradingsymbol: symbol,
        instrument_token: g?.instrument_token,
        net_pnl: Math.round(realizedPnl * 100) / 100,
        brokerage,
        floating_pnl: floatingPnl,
        total: Math.round((realizedPnl - brokerage + floatingPnl) * 100) / 100,
        net_qty: floating?.net_qty ?? 0,
        side: floating?.side ?? null,
        avg_rate: floating?.avg_rate ?? null,
        ltp: floating?.ltp ?? null,
      });
    }

    // Friendly display names for whatever scripts ended up in scope.
    const tokens = [...new Set(perUserScriptRows.map((r) => r.instrument_token).filter(Boolean))];
    const kiteInstruments = await KiteInstrument.find(
      { instrument_token: { $in: tokens } },
      'instrument_token raw_name name expiry instrument_type strike',
    ).lean();
    const kiteMap = new Map(kiteInstruments.map((ki) => [ki.instrument_token, ki]));
    const displayNameFor = (row) => {
      const ki = kiteMap.get(row.instrument_token);
      if (!ki?.name) return row.tradingsymbol;
      if (!ki.expiry) return ki.name;
      const exp = new Date(ki.expiry);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      const day = exp.getDate();
      const month = months[exp.getMonth()];
      if (ki.instrument_type === 'FUT') return `${ki.name} ${day} ${month} FUT`;
      if (ki.instrument_type === 'CE' || ki.instrument_type === 'PE') {
        return `${ki.name} ${ki.strike || ''} ${ki.instrument_type} ${day} ${month}`;
      }
      return `${ki.name} ${day} ${month}`;
    };

    let rows;
    if (detailMode) {
      // Level 2 — one row per user for the one requested script.
      rows = perUserScriptRows
        .filter((r) => r.exchange === exchange && r.tradingsymbol === tradingsymbol)
        .map((r) => ({
          user_id: r.user_id,
          username: r.username,
          name: r.name,
          master_username: r.master_username,
          net_pnl: r.net_pnl,
          brokerage: r.brokerage,
          floating_pnl: r.floating_pnl,
          total: r.total,
          net_qty: r.net_qty,
          side: r.side,
          avg_rate: r.avg_rate,
          ltp: r.ltp,
        }));
      if (search) {
        const re = new RegExp(escapeRegex(search), 'i');
        rows = rows.filter((r) => re.test(r.username) || re.test(r.name || ''));
      }
    } else {
      // Level 1 — roll the per-user rows up to one row per script.
      const byScript = new Map();
      for (const r of perUserScriptRows) {
        const key = `${r.exchange}::${r.tradingsymbol}`;
        if (!byScript.has(key)) {
          byScript.set(key, {
            exchange: r.exchange,
            tradingsymbol: r.tradingsymbol,
            instrument_token: r.instrument_token,
            net_pnl: 0,
            brokerage: 0,
            floating_pnl: 0,
            total: 0,
            user_count: 0,
          });
        }
        const s = byScript.get(key);
        s.net_pnl += r.net_pnl;
        s.brokerage += r.brokerage;
        s.floating_pnl += r.floating_pnl;
        s.total += r.total;
        s.user_count += 1;
      }
      rows = [...byScript.values()].map((s) => ({
        exchange: s.exchange,
        tradingsymbol: s.tradingsymbol,
        display_name: displayNameFor(s),
        net_pnl: Math.round(s.net_pnl * 100) / 100,
        brokerage: Math.round(s.brokerage * 100) / 100,
        floating_pnl: Math.round(s.floating_pnl * 100) / 100,
        total: Math.round(s.total * 100) / 100,
        user_count: s.user_count,
      }));
      if (search) {
        const re = new RegExp(escapeRegex(search), 'i');
        rows = rows.filter((r) => re.test(r.tradingsymbol) || re.test(r.display_name));
      }
    }

    const summary = rows.reduce(
      (acc, r) => ({
        net_pnl: acc.net_pnl + r.net_pnl,
        brokerage: acc.brokerage + r.brokerage,
        floating_pnl: acc.floating_pnl + r.floating_pnl,
        total: acc.total + r.total,
      }),
      emptySummary(),
    );
    for (const k of Object.keys(summary)) summary[k] = Math.round(summary[k] * 100) / 100;

    res.status(200).json({ success: true, data: { rows, summary } });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error), data: null });
  }
};

function emptySummary() {
  return { net_pnl: 0, brokerage: 0, floating_pnl: 0, total: 0 };
}

module.exports = { getScriptwisePnl };
