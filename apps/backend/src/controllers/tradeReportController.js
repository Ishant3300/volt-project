const Trade = require('../models/Trade');
const User = require('../models/User');
const BrokerageSettings = require('../models/BrokerageSettings');
const KiteInstrument = require('../models/KiteInstrument');
const SettlementHistory = require('../models/SettlementHistory');
const mongoose = require('mongoose');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');
const { computeAveragePricePnl, averageCostState } = require('../utils/averageCostPnl');

/**
 * GET /api/trade/report
 * Query: from, to (ISO dates), user_id (optional, for master/admin)
 * 
 * Returns trades grouped by instrument with buy/sell sides,
 * per-instrument summary, and overall summary.
 */
const BILL_MONTHS = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

/** Live Bill script heading (reference format): `NIFTY 29SEP2026`, `NIFTY 25000 CE 29SEP2026`. */
function billScriptName(tradingsymbol, ki) {
  if (!ki || !ki.name) return tradingsymbol;
  if (!ki.expiry) return ki.name;
  const exp = new Date(ki.expiry);
  if (Number.isNaN(exp.getTime())) return ki.name;
  const expiry = `${String(exp.getUTCDate()).padStart(2, '0')}${BILL_MONTHS[exp.getUTCMonth()]}${exp.getUTCFullYear()}`;
  if (ki.instrument_type === 'CE' || ki.instrument_type === 'PE') {
    return `${ki.name} ${ki.strike || ''} ${ki.instrument_type} ${expiry}`.replace(/\s+/g, ' ');
  }
  return `${ki.name} ${expiry}`;
}

/** The Live Bill's BF rows: the position carried into the window (one row per side). */
function billBfRows(seed, meta) {
  if (!seed) return [];
  const rows = [];
  if (seed.totalBuyQty > 0) {
    rows.push({ side: 'BUY', qty: seed.totalBuyQty, rate: seed.totalBuyValue / seed.totalBuyQty, date: meta ? meta.date : null });
  }
  if (seed.totalSellQty > 0) {
    rows.push({ side: 'SELL', qty: seed.totalSellQty, rate: seed.totalSellValue / seed.totalSellQty, date: meta ? meta.date : null });
  }
  return rows;
}

const getTradeReport = async (req, res) => {
  try {
    const { from, to, user_id } = req.query;
    // `bill=1` (mobile Live Bill): also return each instrument's BF rows,
    // lot_size and bill_name, and include instruments that were only carried
    // into the window (no trade in it) so their position still gets a bill
    // section. Without it the response is exactly as before.
    const billFormat = req.query.bill === '1' || req.query.bill === 'true';
    if (!from || !to) {
      return res.status(400).json({ success: false, message: 'from and to dates are required' });
    }

    const fromDate = new Date(from);
    const toDate = new Date(to);
    toDate.setHours(23, 59, 59, 999);

    const role = req.admin ? 'admin' : req.master ? 'master' : 'user';
    const callerId = req.admin?.id || req.master?.id || req.user?.id;

    // Determine target user
    let targetUserId;
    let targetIsMaster = false;
    if (role === 'user') {
      targetUserId = new mongoose.Types.ObjectId(callerId);
    } else if (user_id) {
      targetUserId = new mongoose.Types.ObjectId(user_id);
    } else {
      targetUserId = null; // admin/master without user_id = all users
    }

    // User scope (applied to both the live Trade collection and the ledger)
    const userScope = {};
    if (targetUserId) {
      // A master-supplied user_id/master_id must resolve within the caller's
      // own subtree — without this, any master could pull a full trade
      // report for any account on the platform. Admin unrestricted.
      let callerSubtreeIds = null;
      if (role === 'master') {
        const { getAllSubMasterIds } = require('../services/masterHierarchyService');
        callerSubtreeIds = await getAllSubMasterIds(callerId);
      }

      // Per-admin master-visibility restriction (independent of the master
      // subtree check above, which only applies to role === 'master').
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);

      // Check if the target is a User or a Master
      const targetUser = await User.findById(targetUserId).select('_id username name master_id').lean();
      if (targetUser) {
        if (callerSubtreeIds && !callerSubtreeIds.includes(targetUser.master_id?.toString())) {
          return res.status(403).json({ success: false, message: 'Not authorized to view this user\'s trade report' });
        }
        if (hiddenMasterIds && hiddenMasterIds.has(targetUser.master_id?.toString())) {
          return res.status(404).json({ success: false, message: 'User not found' });
        }
        // It's a user — scope to this single user
        userScope.user_id = targetUserId;
      } else {
        // It's a master — scope to all DIRECT child users of this master
        // (excludes users of sub-masters)
        const Master = require('../models/Master');
        const targetMaster = await Master.findById(targetUserId).select('_id username name').lean();
        if (targetMaster) {
          if (callerSubtreeIds && !callerSubtreeIds.includes(targetUserId.toString())) {
            return res.status(403).json({ success: false, message: 'Not authorized to view this master\'s trade report' });
          }
          if (hiddenMasterIds && hiddenMasterIds.has(targetUserId.toString())) {
            return res.status(404).json({ success: false, message: 'Master not found' });
          }
          targetIsMaster = true;
          const directChildUsers = await User.find({ master_id: targetUserId, deleted_at: null }).distinct('_id');
          if (directChildUsers.length > 0) {
            userScope.user_id = { $in: directChildUsers };
          } else {
            userScope.user_id = targetUserId; // fallback (will return empty)
          }
        } else {
          if (callerSubtreeIds) {
            return res.status(403).json({ success: false, message: 'Not authorized to view this trade report' });
          }
          userScope.user_id = targetUserId;
        }
      }
    } else if (role === 'master') {
      const childIds = await User.find({ master_id: callerId, deleted_at: null }).distinct('_id');
      userScope.user_id = { $in: childIds };
    } else if (role === 'admin') {
      // No target specified — "all users" for admin. A hidden master's
      // users must still be excluded from that platform-wide view.
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) {
        const hiddenUserIds = await User.find({ master_id: { $in: [...hiddenMasterIds] } }).distinct('_id');
        userScope.user_id = { $nin: hiddenUserIds };
      }
    }

    // Fetch user/master name for the PDF header
    let userName = 'Unknown';
    if (targetUserId) {
      if (targetIsMaster) {
        const Master = require('../models/Master');
        const m = await Master.findById(targetUserId).select('username name').lean();
        if (m) userName = m.name || m.username;
      } else {
        const u = await User.findById(targetUserId).select('username name').lean();
        if (u) userName = u.name || u.username;
      }
    }

    // ── Trade-table sources (response shape unchanged) ──
    // (1) Current/unsettled period: LIVE active regular fills within the window.
    // margin_square_off is a real, billable trade (marginSquareOffService.js
    // computes and stores real brokerage on it at execution time, and debits
    // the wallet for it immediately) — only carry_forward is a synthetic
    // marker with genuinely no brokerage. Excluding margin_square_off here
    // silently dropped a client's real forced-liquidation brokerage from
    // ever appearing in this report.
    const liveRegular = await Trade.find({
      ...userScope,
      status: 'completed',
      deleted_at: null,
      trade_type: { $ne: 'carry_forward' },
      executed_at: { $gte: fromDate, $lte: toDate },
    }).sort({ executed_at: 1 }).lean();

    // (2) Historical/settled period: immutable SettlementHistory ledger fills within the
    //     window. This is the DURABLE source of historical bills — independent of any
    //     live-table mutation. It replaces the old fragile soft-deleted "week reset"
    //     remarks matching, which could silently drop history.
    const snapshots = await SettlementHistory.find({
      ...userScope,
      period_from: { $lte: toDate },
      period_to: { $gte: fromDate },
    }).lean();

    const ledgerRows = [];
    // Fills of these SAME settlement periods dated before the window — e.g.
    // an account's opening trades entered after the previous settlement
    // (266) once this period has itself been settled. They are not shown,
    // but are replayed into the carried-in position below, exactly as their
    // live originals were before settlement archived them.
    const preWindowLedgerFills = [];
    const seenSourceTradeIds = new Set();
    for (const s of snapshots) {
      for (const f of (s.fills || [])) {
        const sourceTradeId = f.source_trade_id?.toString();
        if (sourceTradeId && seenSourceTradeIds.has(sourceTradeId)) continue;
        if (sourceTradeId) seenSourceTradeIds.add(sourceTradeId);
        if (!f.executed_at) continue;
        const at = new Date(f.executed_at);
        if (at < fromDate && f.trade_type !== 'carry_forward') {
          preWindowLedgerFills.push({
            user_id: s.user_id,
            exchange: s.exchange,
            tradingsymbol: s.tradingsymbol,
            instrument_token: s.instrument_token,
            transaction_type: f.transaction_type,
            executed_quantity: f.executed_quantity || 0,
            executed_price: f.executed_price || 0,
            executed_at: at,
          });
          continue;
        }
        if (at < fromDate || at > toDate) continue;
        // Only carry_forward is a synthetic marker (represented via the Carry
        // Forward section, not as a fill) — margin_square_off is a real,
        // billed trade and belongs in the table like any other fill.
        if (f.trade_type === 'carry_forward') continue;
        ledgerRows.push({
          exchange: s.exchange,
          tradingsymbol: s.tradingsymbol,
          instrument_token: s.instrument_token,
          transaction_type: f.transaction_type,
          executed_quantity: f.executed_quantity || 0,
          executed_price: f.executed_price || 0,
          executed_at: at,
          pnl: f.pnl || 0,
          trade_type: f.trade_type || 'regular',
          order_type: f.order_type || 'MARKET',
          placed_by: f.placed_by || 'USER',
          _stored_brokerage: f.brokerage || 0,  // brokerage calculated at settlement time
          _is_ledger: true,
        });
      }

      // Include settlement closing entry if the snapshot has a closing position.
      // This represents the unrealised P&L that was locked at settlement price.
      // Without this, the General PDF only shows booked trades but misses the
      // settlement-close P&L for open positions.
      if (s.closing_qty > 0 && s.settlement_price > 0) {
        const settleDate = new Date(s.settlement_date || s.period_to);
        if (settleDate >= fromDate && settleDate <= toDate) {
          // The closing trade: opposite side at settlement price
          ledgerRows.push({
            exchange: s.exchange,
            tradingsymbol: s.tradingsymbol,
            instrument_token: s.instrument_token,
            transaction_type: s.closing_side || (s.carry_forward_side === 'BUY' ? 'SELL' : 'BUY'),
            executed_quantity: s.closing_qty,
            executed_price: s.settlement_price,
            executed_at: settleDate,
            pnl: s.settlement_pnl || 0,
            trade_type: 'settlement_close',
            order_type: 'MARKET',
            placed_by: 'SYSTEM',
            _stored_brokerage: 0,
            _is_ledger: true,
          });
        }
      }
    }

    // Merge live (current) + ledger (historical) fills, chronologically.
    const trades = [...liveRegular, ...ledgerRows].sort(
      (a, b) => new Date(a.executed_at) - new Date(b.executed_at)
    );

    // Group by instrument key (exchange + tradingsymbol)
    const grouped = {};
    for (const t of trades) {
      const key = `${t.exchange}::${t.tradingsymbol}`;
      if (!grouped[key]) {
        grouped[key] = {
          exchange: t.exchange,
          tradingsymbol: t.tradingsymbol,
          instrument_token: t.instrument_token,
          buys: [],
          sells: [],
          all_trades: [], // chronological for advanced mode
        };
      }

      // Skip active carry_forward re-opening trades from buy/sell aggregation
      // (they only appear in the Carry Forward section via dedicated query below)
      const isActiveCarryForward = t.trade_type === 'carry_forward' && !t.deleted_at;
      if (isActiveCarryForward) continue;

      const entry = {
        date: t.executed_at,
        qty: t.executed_quantity || 0,
        price: t.executed_price || 0,
        volume: (t.executed_quantity || 0) * (t.executed_price || 0),
      };
      if (t.transaction_type === 'BUY') grouped[key].buys.push(entry);
      else grouped[key].sells.push(entry);

      grouped[key].all_trades.push({
        date: t.executed_at,
        type: t.transaction_type,
        trade_type: t.trade_type || 'regular',
        order_type: t.order_type || 'MARKET',
        placed_by: t.placed_by || 'USER',
        buy_qty: t.transaction_type === 'BUY' ? (t.executed_quantity || 0) : 0,
        sell_qty: t.transaction_type === 'SELL' ? (t.executed_quantity || 0) : 0,
        rate: t.executed_price || 0,
        brokerage: t.brokerage || 0,
        brokerage_exempt: t.brokerage_exempt || false,
        pnl: t.pnl || 0,
        order_type_label: _getOrderTypeLabel(t),
        _is_ledger: t._is_ledger || false,
        _stored_brokerage: t._stored_brokerage || t.brokerage || 0,
      });
    }

    // Load brokerage rules and instrument info for recalculation.
    // Fetch BOTH user-specific and global rules — per-trade lookup below tries
    // the user-specific rule for that trade's own script/exchange first, then
    // falls back to the global rule for that SAME script/exchange. Previously
    // this picked user rules XOR global rules for the whole account: if the
    // user had a rule for even one script, global rules were never consulted
    // for any other script/exchange the user's own rule set didn't cover,
    // silently producing 0 brokerage on those trades.
    let userBrkRules = [];
    if (targetUserId) {
      userBrkRules = await BrokerageSettings.find({ user_id: targetUserId, deleted_at: null }).lean();
    }
    const globalBrkRules = await BrokerageSettings.find({ user_id: null, deleted_at: null }).lean();

    const _findBrokerageRule = (rawName, seg, tradeDate) => {
      const pickFrom = (rules) => {
        const effectiveRules = rules.filter(r =>
          !r.effective_from || new Date(r.effective_from) <= tradeDate
        );
        const pickRule = (candidates) => candidates.sort(
          (a, b) => new Date(b.effective_from || 0) - new Date(a.effective_from || 0)
        )[0] || null;

        let rule = null;
        if (rawName && seg) rule = pickRule(effectiveRules.filter(r => r.script_name?.toUpperCase() === rawName.toUpperCase() && r.exchange_name === seg.toUpperCase()));
        if (!rule && rawName) rule = pickRule(effectiveRules.filter(r => r.script_name?.toUpperCase() === rawName.toUpperCase()));
        if (!rule && seg) rule = pickRule(effectiveRules.filter(r => r.exchange_name === seg.toUpperCase() && !r.script_name));
        if (!rule) rule = pickRule(effectiveRules.filter(r => r.exchange_name === (seg.split('-')[0] || '').toUpperCase() && !r.script_name));
        return rule;
      };
      return pickFrom(userBrkRules) || pickFrom(globalBrkRules);
    };

    // Fetch carry-forward marker records once, used both to seed each
    // instrument's starting P&L position (records dated on/before fromDate)
    // and to populate the output Carry Forward table (records dated up to
    // toDate) further below.
    let cfTrades = [];
    const carryForwardSeeds = {}; // key: `${exchange}::${tradingsymbol}` -> {totalBuyQty, totalBuyValue, totalSellQty, totalSellValue}
    const carryForwardSeedMeta = {}; // same key -> { date, exchange, tradingsymbol, instrument_token } of the latest seed record
    if (targetUserId) {
      const cfUserFilter = userScope.user_id ? { user_id: userScope.user_id } : { user_id: targetUserId };
      cfTrades = await Trade.find({
        ...cfUserFilter,
        status: 'completed',
        trade_type: 'carry_forward',
        executed_at: { $lte: toDate },
        $and: [
          {
            $or: [
              {
                settlement_run_id: { $ne: null },
                settlement_period_key: { $type: 'string' },
              },
              // Read-only compatibility for pre-migration rows.
              { remarks: 'Settlement: position carried forward at close price' },
            ],
          },
          {
            $or: [
              { deleted_at: null },
              { deleted_at: { $gt: fromDate } },
            ],
          },
        ],
      }).lean();

      // The carry_forward record embodies the WHOLE position carried into the
      // new period (not an incremental delta), so per user+instrument we only
      // want the latest one dated on/before fromDate. When target is a master
      // (multiple child users), sum each user's seed for the same instrument —
      // the report groups all of them together under one instrument row.
      const latestPerUserInstrument = {};
      for (const t of cfTrades) {
        if (new Date(t.executed_at) > fromDate) continue;
        const k = `${t.user_id}::${t.exchange}::${t.tradingsymbol}`;
        const existing = latestPerUserInstrument[k];
        if (!existing || new Date(t.executed_at) > new Date(existing.executed_at)) {
          latestPerUserInstrument[k] = t;
        }
      }
      // The position carried INTO the window = that latest carry-forward PLUS
      // every real fill after it and before fromDate that no settlement has
      // folded into a carry-forward yet (live: deleted_at null). Previously
      // those fills were dropped: confirmed real, account 266 was opened
      // after Saturday's settlement with its positions entered as ordinary
      // trades on 26-09 23:22 — no carry-forward, so the week started flat and
      // every close was priced against nothing (NIFTY's 910 close: 0.00
      // instead of -4,61,097). Same gap for a window starting mid-week.
      const preWindowFills = await Trade.find({
        ...cfUserFilter,
        status: 'completed',
        deleted_at: null,
        trade_type: { $ne: 'carry_forward' },
        executed_at: { $lt: fromDate },
      }).sort({ executed_at: 1 }).lean();
      preWindowFills.push(...preWindowLedgerFills);
      preWindowFills.sort((a, b) => new Date(a.executed_at) - new Date(b.executed_at));

      const perUserInstrument = {};
      for (const [k, marker] of Object.entries(latestPerUserInstrument)) {
        perUserInstrument[k] = { ref: marker, marker, fills: [] };
      }
      for (const t of preWindowFills) {
        const k = `${t.user_id}::${t.exchange}::${t.tradingsymbol}`;
        const entry = perUserInstrument[k] || (perUserInstrument[k] = { ref: t, marker: null, fills: [] });
        if (entry.marker && new Date(t.executed_at) <= new Date(entry.marker.executed_at)) continue;
        entry.fills.push(t);
      }

      for (const { ref, marker, fills } of Object.values(perUserInstrument)) {
        const markerQty = marker ? (marker.executed_quantity || 0) : 0;
        const markerPrice = marker ? (marker.executed_price || 0) : 0;
        const markerSeed = !marker || markerQty <= 0 ? null : marker.transaction_type === 'BUY'
          ? { totalBuyQty: markerQty, totalBuyValue: markerQty * markerPrice, totalSellQty: 0, totalSellValue: 0 }
          : { totalBuyQty: 0, totalBuyValue: 0, totalSellQty: markerQty, totalSellValue: markerQty * markerPrice };
        const state = averageCostState(
          fills.map((f) => ({
            date: f.executed_at,
            buy_qty: f.transaction_type === 'BUY' ? (f.executed_quantity || 0) : 0,
            sell_qty: f.transaction_type === 'SELL' ? (f.executed_quantity || 0) : 0,
            rate: f.executed_price || 0,
          })),
          markerSeed,
        );
        if (state.totalBuyQty <= 1e-9 && state.totalSellQty <= 1e-9) continue;

        const key = `${ref.exchange}::${ref.tradingsymbol}`;
        if (!carryForwardSeeds[key]) {
          carryForwardSeeds[key] = { totalBuyQty: 0, totalBuyValue: 0, totalSellQty: 0, totalSellValue: 0 };
        }
        carryForwardSeeds[key].totalBuyQty += state.totalBuyQty;
        carryForwardSeeds[key].totalBuyValue += state.totalBuyValue;
        carryForwardSeeds[key].totalSellQty += state.totalSellQty;
        carryForwardSeeds[key].totalSellValue += state.totalSellValue;

        const lastAt = fills.length > 0 ? fills[fills.length - 1].executed_at : marker.executed_at;
        const meta = carryForwardSeedMeta[key];
        if (!meta || new Date(lastAt) > new Date(meta.date)) {
          carryForwardSeedMeta[key] = { date: lastAt, exchange: ref.exchange, tradingsymbol: ref.tradingsymbol, instrument_token: ref.instrument_token };
        }
      }
    }

    if (billFormat) {
      for (const [key, meta] of Object.entries(carryForwardSeedMeta)) {
        if (grouped[key]) continue;
        grouped[key] = {
          exchange: meta.exchange,
          tradingsymbol: meta.tradingsymbol,
          instrument_token: meta.instrument_token,
          buys: [],
          sells: [],
          all_trades: [],
        };
      }
    }

    const allTokens = [...new Set([...trades.map(t => t.instrument_token), ...Object.values(grouped).map(g => g.instrument_token)])];
    const kiteInstruments = await KiteInstrument.find(
      { instrument_token: { $in: allTokens } },
      'instrument_token lot_size segment raw_name name expiry instrument_type strike'
    ).lean();
    const kiteMap = {};
    kiteInstruments.forEach(ki => { kiteMap[ki.instrument_token] = ki; });

    // Build per-instrument summaries
    const instruments = [];
    let grandTotalPnl = 0;
    let grandBrokerage = 0;
    const carryForward = [];

    for (const key of Object.keys(grouped)) {
      const g = grouped[key];
      const totalBuyQty = g.buys.reduce((s, b) => s + b.qty, 0);
      const totalBuyVol = g.buys.reduce((s, b) => s + b.volume, 0);
      const avgBuyPrice = totalBuyQty > 0 ? totalBuyVol / totalBuyQty : 0;

      const totalSellQty = g.sells.reduce((s, b) => s + b.qty, 0);
      const totalSellVol = g.sells.reduce((s, b) => s + b.volume, 0);
      const avgSellPrice = totalSellQty > 0 ? totalSellVol / totalSellQty : 0;

      const matchedQty = Math.min(totalBuyQty, totalSellQty);

      // ── Average-Price P&L Recomputation ──
      // Recompute P&L using the average-price method instead of stored
      // per-trade pnl values (despite the old name, this was never true
      // FIFO — see computeAveragePricePnl's own docstring, which says so
      // directly). Recomputing here — rather than trusting the stored
      // `pnl` field — correctly handles cases where the stored value was
      // computed against a running average that included prior-week buys,
      // or a settlement close was computed against an overall average
      // instead of the position actually being closed. Shared with
      // scriptwisePnlController.js via utils/averageCostPnl.js.
      const pnl = computeAveragePricePnl(g.all_trades, carryForwardSeeds[key]);

      // Per-trade brokerage in all_trades: use stored value for ledger rows,
      // recalculate with effective rules for live rows.
      const ki = kiteMap[g.instrument_token] || {};
      const seg = ki.segment || '';
      const rawName = ki.raw_name || '';
      const lotSize = ki.lot_size || 1;

      for (const at of g.all_trades) {
        if (at.trade_type === 'carry_forward') continue;

        // Ledger (settled) fill: use brokerage stored at settlement time — no recalculation.
        if (at._is_ledger) {
          at.brokerage = at._stored_brokerage || 0;
          continue;
        }

        // Live fill: use the brokerage already stored on the trade (calculated at execution time).
        // Only recalculate if the stored value is 0 and we can find an effective rule. A margin
        // square-off already has real brokerage from marginSquareOffService.js, so it naturally
        // takes this same "already >0, leave it alone" path — no separate case needed. A trade
        // the admin Custom-ticket toggle deliberately exempted is also a genuine, intentional 0 —
        // not a missing-rule gap — so it must not be recalculated either.
        if (at.brokerage > 0 || at.brokerage_exempt) continue;

        if (at.rate && (at.buy_qty || at.sell_qty)) {
          const tradeDate = new Date(at.date);
          const atRule = _findBrokerageRule(rawName, seg, tradeDate);

          if (atRule) {
            const qty = (at.buy_qty || 0) + (at.sell_qty || 0);
            const rate = at.rate || 0;
            if (atRule.type === 'TURNOVER WISE') {
              at.brokerage = Math.round(rate * qty * (atRule.brk_value / 10000) * 100) / 100;
            } else if (atRule.type === 'LOT WISE') {
              at.brokerage = Math.round((lotSize > 1 ? qty / lotSize : qty) * atRule.brk_value * 100) / 100;
            }
          }
        }
      }

      // Confirmed bug: the "Script wise total" Br figure used to come from
      // an INDEPENDENT second brokerage computation over `instrTrades`,
      // re-deriving each live trade's rate via _findBrokerageRule a second
      // time instead of reusing the per-row values just computed above —
      // so it never actually reconciled against the individual row Br cells
      // it was supposedly totaling. Confirmed live: two NFO legs correctly
      // showing 116.29 and 116.26 individually, but a "Script wise total"
      // of 30.77 instead of 232.55; two MCX legs correctly showing 1,000.00
      // each, but a script total of 400.00 instead of 2,000.00. Summing the
      // SAME g.all_trades rows the per-row loop just finalized guarantees
      // the total always reconciles with what's actually displayed above it.
      let brokerage = 0;
      for (const at of g.all_trades) {
        if (at.trade_type === 'carry_forward') continue;
        brokerage += at.brokerage || 0;
      }

      const netPnl = pnl - brokerage;

      grandTotalPnl += pnl;
      grandBrokerage += brokerage;

      // Build friendly display name from KiteInstrument data
      let displayName = g.tradingsymbol;
      if (ki.name) {
        const base = ki.name;
        if (ki.expiry) {
          const exp = new Date(ki.expiry);
          const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          const day = exp.getDate();
          const month = months[exp.getMonth()];
          if (ki.instrument_type === 'FUT') {
            displayName = `${base} ${day} ${month} FUT`;
          } else if (ki.instrument_type === 'CE' || ki.instrument_type === 'PE') {
            displayName = `${base} ${ki.strike || ''} ${ki.instrument_type} ${day} ${month}`;
          } else {
            displayName = `${base} ${day} ${month}`;
          }
        } else {
          displayName = base;
        }
      }

      instruments.push({
        exchange: g.exchange,
        tradingsymbol: g.tradingsymbol,
        display_name: displayName,
        buys: g.buys,
        sells: g.sells,
        all_trades: g.all_trades,
        total_buy_qty: totalBuyQty,
        total_sell_qty: totalSellQty,
        avg_buy_price: avgBuyPrice,
        avg_sell_price: avgSellPrice,
        total_buy_vol: totalBuyVol,
        total_sell_vol: totalSellVol,
        pnl,
        brokerage,
        net_pnl: netPnl,
        ...(billFormat ? {
          lot_size: ki.lot_size || null,
          bill_name: billScriptName(g.tradingsymbol, ki),
          bf: billBfRows(carryForwardSeeds[key], carryForwardSeedMeta[key]),
        } : {}),
      });

      // Carry forward: unmatched qty
      const diff = totalBuyQty - totalSellQty;
      if (diff !== 0) {
        carryForward.push({
          exchange: g.exchange,
          tradingsymbol: g.tradingsymbol,
          display_name: displayName,
          type: diff > 0 ? 'Buy' : 'Sell',
          quantity: Math.abs(diff),
          price: diff > 0 ? avgBuyPrice : avgSellPrice,
        });
      }
    }

    // Also include settlement carry_forward positions (reopened at settlement price).
    // Include both:
    //   - Active (deleted_at: null) → currently open carry-forwards
    //   - Soft-deleted AFTER fromDate → were open during the report period (settled mid-period)
    // This ensures positions that existed during the report window always show in Carry Forward,
    // even if they were subsequently settled by a later settlement run.
    if (targetUserId) {
      // Reuses the cfTrades already fetched above (same filter — active
      // carry-forward positions dated up to toDate) to populate the output
      // Carry Forward table.
      for (const t of cfTrades) {
        const ki = kiteMap[t.instrument_token] || {};
        let displayName = t.tradingsymbol;
        if (ki.name) {
          const base = ki.name;
          if (ki.expiry) {
            const exp = new Date(ki.expiry);
            const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
            const d = exp.getDate(), m = months[exp.getMonth()];
            if (ki.instrument_type === 'FUT') {
              displayName = `${base} ${d} ${m} FUT`;
            } else if (ki.instrument_type === 'CE' || ki.instrument_type === 'PE') {
              displayName = `${base} ${ki.strike || ''} ${ki.instrument_type} ${d} ${m}`.replace(/\s+/g, ' ').trim();
            } else {
              displayName = `${base} ${d} ${m}`;
            }
          }
        }

        // Only add if not already in carryForward from the regular trade matching
        const exists = carryForward.some(cf =>
          cf.tradingsymbol === t.tradingsymbol && cf.exchange === t.exchange
        );
        if (!exists) {
          carryForward.push({
            exchange: t.exchange,
            tradingsymbol: t.tradingsymbol,
            display_name: displayName,
            type: t.transaction_type === 'BUY' ? 'Buy' : 'Sell',
            quantity: t.executed_quantity,
            price: t.executed_price,
          });
        }
      }
    }

    res.status(200).json({
      success: true,
      data: {
        user_name: userName,
        from: fromDate,
        to: toDate,
        instruments,
        summary: {
          total_pnl: grandTotalPnl,
          total_brokerage: grandBrokerage,
          net_pnl: grandTotalPnl - grandBrokerage,
        },
        carry_forward: carryForward,
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * GET /api/trade/open-positions
 * Returns actual current open positions for a user by aggregating ALL active trades.
 * No date filter — this is the source of truth for direction and qty.
 * Query: user_id (required for admin/master, optional for user — defaults to self)
 */
const getOpenPositions = async (req, res) => {
  try {
    const { user_id } = req.query;
    const role = req.admin ? 'admin' : req.master ? 'master' : 'user';
    const callerId = req.admin?.id || req.master?.id || req.user?.id;

    let targetUserId;
    if (role === 'user') {
      targetUserId = new mongoose.Types.ObjectId(callerId);
    } else if (user_id) {
      targetUserId = new mongoose.Types.ObjectId(user_id);
    } else {
      return res.status(400).json({ success: false, message: 'user_id is required' });
    }

    // A master-supplied user_id must be in the caller's own subtree —
    // without this, any master could read any user's open positions platform-wide.
    if (role === 'master' && user_id) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(callerId);
      const targetUser = await User.findById(targetUserId).select('master_id').lean();
      if (!targetUser || !allowedMasterIds.includes(targetUser.master_id?.toString())) {
        return res.status(403).json({ success: false, message: 'Not authorized to view this user\'s open positions' });
      }
    }

    // Per-admin master-visibility restriction.
    if (role === 'admin') {
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) {
        const targetUser = await User.findById(targetUserId).select('master_id').lean();
        if (targetUser && hiddenMasterIds.has(targetUser.master_id?.toString())) {
          return res.status(404).json({ success: false, message: 'User not found' });
        }
      }
    }

    // All active (non-deleted) completed trades — no date filter
    const trades = await Trade.find({
      user_id: targetUserId,
      status: 'completed',
      deleted_at: null,
    }).lean();

    // Compute net position per instrument
    const posMap = {};
    for (const t of trades) {
      const key = `${t.exchange}::${t.tradingsymbol}`;
      if (!posMap[key]) {
        posMap[key] = {
          exchange: t.exchange,
          tradingsymbol: t.tradingsymbol,
          instrument_token: t.instrument_token,
          netQty: 0,
          totalBuyQty: 0,
          totalBuyValue: 0,
          totalSellQty: 0,
          totalSellValue: 0,
        };
      }
      const qty = t.executed_quantity || 0;
      const price = t.executed_price || 0;
      if (t.transaction_type === 'BUY') {
        posMap[key].netQty += qty;
        posMap[key].totalBuyQty += qty;
        posMap[key].totalBuyValue += qty * price;
      } else {
        posMap[key].netQty -= qty;
        posMap[key].totalSellQty += qty;
        posMap[key].totalSellValue += qty * price;
      }
    }

    const openPositions = [];
    for (const pos of Object.values(posMap)) {
      if (Math.abs(pos.netQty) > 0.001) {
        const isLong = pos.netQty > 0;
        const avgPrice = isLong
          ? (pos.totalBuyQty > 0 ? pos.totalBuyValue / pos.totalBuyQty : 0)
          : (pos.totalSellQty > 0 ? pos.totalSellValue / pos.totalSellQty : 0);
        openPositions.push({
          exchange: pos.exchange,
          tradingsymbol: pos.tradingsymbol,
          instrument_token: pos.instrument_token,
          direction: isLong ? 'BUY' : 'SELL',
          open_qty: Math.abs(pos.netQty),
          avg_price: avgPrice,
        });
      }
    }

    res.status(200).json({ success: true, data: openPositions });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * GET /api/trade/settlement-history
 * Returns immutable settlement-ledger snapshots for a user within a period.
 * This is the durable source of truth for historical bills (survives any
 * live Trade-table mutation). Query: user_id (required for admin/master,
 * optional for user — defaults to self), from, to (ISO dates, optional).
 */
const getSettlementHistory = async (req, res) => {
  try {
    const SettlementHistory = require('../models/SettlementHistory');
    const { user_id, from, to } = req.query;
    const role = req.admin ? 'admin' : req.master ? 'master' : 'user';
    const callerId = req.admin?.id || req.master?.id || req.user?.id;

    let targetUserId;
    if (role === 'user') {
      targetUserId = new mongoose.Types.ObjectId(callerId);
    } else if (user_id) {
      targetUserId = new mongoose.Types.ObjectId(user_id);
    } else {
      return res.status(400).json({ success: false, message: 'user_id is required' });
    }

    // A master-supplied user_id must be in the caller's own subtree —
    // without this, any master could read any user's settlement history platform-wide.
    if (role === 'master' && user_id) {
      const { getAllSubMasterIds } = require('../services/masterHierarchyService');
      const allowedMasterIds = await getAllSubMasterIds(callerId);
      const targetUser = await User.findById(targetUserId).select('master_id').lean();
      if (!targetUser || !allowedMasterIds.includes(targetUser.master_id?.toString())) {
        return res.status(403).json({ success: false, message: 'Not authorized to view this user\'s settlement history' });
      }
    }

    // Per-admin master-visibility restriction.
    if (role === 'admin') {
      const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
      const hiddenMasterIds = await resolveHiddenMasterIds(req);
      if (hiddenMasterIds) {
        const targetUser = await User.findById(targetUserId).select('master_id').lean();
        if (targetUser && hiddenMasterIds.has(targetUser.master_id?.toString())) {
          return res.status(404).json({ success: false, message: 'User not found' });
        }
      }
    }

    const q = { user_id: targetUserId };
    if (from || to) {
      q.period_to = {};
      if (from) q.period_to.$gte = new Date(from);
      if (to) { const t = new Date(to); t.setHours(23, 59, 59, 999); q.period_to.$lte = t; }
    }

    const snapshots = await SettlementHistory.find(q)
      .sort({ period_to: -1, tradingsymbol: 1 })
      .lean();

    res.status(200).json({ success: true, data: snapshots });
  } catch (error) {
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

/**
 * Determine the display label for the "Type" column in the M2M report.
 */
function _getOrderTypeLabel(trade) {
  const tradeType = trade.trade_type || 'regular';
  const orderType = (trade.order_type || 'MARKET').toUpperCase();
  const placedBy = (trade.placed_by || 'USER').toUpperCase();

  // Carry-forward from settlement
  if (tradeType === 'carry_forward') return 'CF';
  // Settlement closing trade: the position is carried forward to next week
  // (BF there at this same price) — shown as "CF" on the bill.
  if (tradeType === 'settlement_close') return 'CF';
  // Placed by admin
  if (placedBy === 'ADMIN') return 'ADMIN';
  // Placed by master
  if (placedBy === 'MASTER') return 'MASTER';
  // Placed by system (margin square-off, intraday square-off)
  if (placedBy === 'SYSTEM') return 'SYSTEM';
  // Limit or Stop-Loss order
  if (orderType === 'LIMIT' || orderType === 'SL' || orderType === 'SL-M') return 'LIMIT';
  // Market order by user
  return 'NORMAL';
}

module.exports = {
  _private: { billScriptName, billBfRows }, getTradeReport, getOpenPositions, getSettlementHistory };
