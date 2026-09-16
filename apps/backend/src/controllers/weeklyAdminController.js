const Trade = require('../models/Trade');
const User = require('../models/User');
const Master = require('../models/Master');
const BrokerageSettings = require('../models/BrokerageSettings');
const KiteInstrument = require('../models/KiteInstrument');
const { sanitizeErrorMessage } = require('../utils/sanitizeError');

/**
 * GET /api/master/weekly-admin-report
 *
 * Multi-tier hierarchy report using per-instrument brokerage cascade
 * and P&L sharing per the spec (Sections 2.2 and 2.3).
 *
 * OPTIMIZED: Uses batch queries instead of N+1 per-user queries.
 * ~6 DB queries total regardless of user count.
 */
/**
 * Current settlement week boundaries: Monday 00:00 → now. Same Monday-start
 * logic as weeklySummaryService.js's snapshot job, so "this week" means the
 * same thing everywhere in the app.
 */
function currentWeekStart() {
  const now = new Date();
  const dayOfWeek = now.getDay(); // 0 = Sunday
  const diffToMonday = dayOfWeek === 0 ? 6 : dayOfWeek - 1;
  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - diffToMonday);
  weekStart.setHours(0, 0, 0, 0);
  return weekStart;
}

const getWeeklyAdminReport = async (req, res) => {
  // Timing breakdown — logged, not returned, so we can see exactly which
  // phase is slow instead of guessing from a single end-to-end number.
  const _t0 = Date.now();
  const _timings = {};
  const _mark = (label) => { _timings[label] = Date.now() - _t0; };

  try {
    const role = req.admin ? 'admin' : 'master';
    const callerId = req.admin?.id || req.master?.id;
    const metricsEngine = require('../services/metricsEngine');

    // requireAdminPermission('REPORTS_ACCESS') on this route is a no-op for
    // a master caller by design (see requireAdminPermission.js) — Master
    // authorization is meant to be enforced inline per-endpoint instead.
    // This one was never actually checking it: an admin can toggle a
    // specific master's own Master.permissions.weekly_admin off (only an
    // admin can — masterController.js's updateMasterPermissions blocks a
    // master from changing this on their children), and the web/mobile UI
    // hides the menu item accordingly, but nothing stopped that master from
    // calling this endpoint directly regardless.
    if (req.master) {
      const caller = await Master.findById(req.master.id).select('permissions').lean();
      if (caller?.permissions?.weekly_admin === false) {
        return res.status(403).json({ success: false, message: 'Not authorized to view the weekly admin report', data: null });
      }
    }

    // Was previously unbounded (every completed trade ever, for every user
    // in scope) despite this being a "weekly" report — the actual cause of
    // this endpoint timing out as trade history grew. Defaults to the
    // current settlement week, same as weeklySummaryService.js; callers can
    // still override with ?date_from=&date_to= like every other trade-list
    // endpoint in this codebase (masterTradeController.js, userController.js).
    const { date_from, date_to } = req.query;
    const executedAtFilter = {};
    executedAtFilter.$gte = date_from ? new Date(date_from) : currentWeekStart();
    if (date_to) executedAtFilter.$lte = new Date(date_to);

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 1: Batch-load ALL data upfront (~6 DB queries total)
    // ═══════════════════════════════════════════════════════════════════════

    // 1. Load ALL masters (we need the full tree for hierarchy walks)
    const allMasters = await Master.find({ deleted_at: null })
      .select('_id name username master_id pnl_sharing brokerage_sharing')
      .lean();

    // Build master lookup maps
    const masterMap = {};          // masterId → masterDoc
    const masterChildrenMap = {};   // masterId → [childMasterDoc, ...]
    for (const m of allMasters) {
      const mid = m._id.toString();
      masterMap[mid] = m;
      masterChildrenMap[mid] = [];
    }
    for (const m of allMasters) {
      if (m.master_id) {
        const parentId = m.master_id.toString();
        if (masterChildrenMap[parentId]) {
          masterChildrenMap[parentId].push(m);
        }
      }
    }
    _mark('1_masters');

    // 2. Determine scope based on role
    let topEntities; // masters to report on (top-level for admin, children for master)
    let callerMaster = null;

    // Per-admin master-visibility restriction — expanded once here (a Set
    // of every hidden master's full subtree) and reused for both topEntities
    // and allScopeMasterIds below.
    const { resolveHiddenMasterIds } = require('../utils/adminVisibility');
    const hiddenMasterIds = await resolveHiddenMasterIds(req);

    if (role === 'admin') {
      topEntities = allMasters.filter(m => !m.master_id && !(hiddenMasterIds && hiddenMasterIds.has(m._id.toString())));
    } else {
      callerMaster = masterMap[callerId] || null;
      topEntities = masterChildrenMap[callerId] || [];
    }

    // 3. Collect ALL master IDs in scope (for all sub-trees we need to report on)
    const allScopeMasterIds = new Set();
    if (role === 'admin') {
      // Admin sees everything, minus any hidden master's entire subtree.
      allMasters.forEach(m => {
        const mid = m._id.toString();
        if (!hiddenMasterIds || !hiddenMasterIds.has(mid)) allScopeMasterIds.add(mid);
      });
    } else {
      // Master sees their sub-tree
      const queue = [callerId];
      while (queue.length > 0) {
        const cid = queue.shift();
        allScopeMasterIds.add(cid);
        const children = masterChildrenMap[cid] || [];
        for (const child of children) {
          queue.push(child._id.toString());
        }
      }
    }

    // 4. Load ALL users under scope
    const allUsers = await User.find({
      master_id: { $in: [...allScopeMasterIds] },
      deleted_at: null
    }).select('_id name username master_id pnl_sharing brokerage_sharing').lean();

    const userMap = {};           // userId → userDoc
    const usersByMaster = {};     // masterId → [userDoc, ...]
    for (const u of allUsers) {
      const uid = u._id.toString();
      userMap[uid] = u;
      const mid = u.master_id.toString();
      if (!usersByMaster[mid]) usersByMaster[mid] = [];
      usersByMaster[mid].push(u);
    }
    _mark('2_users');

    // 5. Load trades for all users in scope.
    //
    // Default (no date_from/date_to override) means "current week" — the
    // exact window weeklyReportCache.js keeps precomputed per user, updated
    // the instant each trade completes (see metricsEngine.onTradeExecuted).
    // Only that default case can use the cache; an explicit historical
    // range always needs a live query, since the cache only ever tracks
    // the current week.
    const allUserIds = allUsers.map(u => u._id);
    const tradesByUser = {};
    const usersNeedingLiveQuery = [];

    if (!date_from && !date_to) {
      const weeklyReportCache = require('../services/weeklyReportCache');
      await Promise.all(allUserIds.map(async (uid) => {
        const cached = await weeklyReportCache.getUserWeeklyTrades(uid.toString());
        if (cached) {
          tradesByUser[uid.toString()] = cached;
        } else {
          usersNeedingLiveQuery.push(uid);
        }
      }));
    } else {
      usersNeedingLiveQuery.push(...allUserIds);
    }
    _mark('3_cacheLookup');
    _timings.cacheHits = allUserIds.length - usersNeedingLiveQuery.length;
    _timings.cacheMisses = usersNeedingLiveQuery.length;

    // Cache misses (cold start, Redis unavailable, or an explicit date
    // range) fall back to the same bounded, indexed live query as before —
    // uses the existing { user_id, status, deleted_at, executed_at } index
    // (Trade.js line 161), which an unbounded query never hit.
    if (usersNeedingLiveQuery.length > 0) {
      const liveTrades = await Trade.find({
        user_id: { $in: usersNeedingLiveQuery },
        status: 'completed',
        deleted_at: null,
        // carry_forward is a synthetic settlement marker with no real
        // brokerage — same exclusion as weeklyReportCache.js's cache path,
        // kept consistent so a cache miss doesn't silently bill brokerage
        // on a carried position's reopen leg that the cache path wouldn't.
        trade_type: { $ne: 'carry_forward' },
        executed_at: executedAtFilter
      }).select('user_id instrument_token executed_price executed_quantity pnl').lean();

      for (const t of liveTrades) {
        const uid = t.user_id.toString();
        if (!tradesByUser[uid]) tradesByUser[uid] = [];
        tradesByUser[uid].push(t);
      }
    }
    _mark('4_trades');
    _timings.tradeCount = usersNeedingLiveQuery.length > 0
      ? Object.values(tradesByUser).reduce((n, arr) => n + arr.length, 0)
      : 0;

    const allTrades = Object.values(tradesByUser).flat();

    // 6. Load ALL KiteInstruments for tokens in trades
    const allTokens = [...new Set(allTrades.map(t => t.instrument_token))];
    const kiteInstruments = await KiteInstrument.find(
      { instrument_token: { $in: allTokens } },
      'instrument_token lot_size segment raw_name exchange'
    ).lean();
    const kiteMap = {};
    for (const ki of kiteInstruments) {
      kiteMap[ki.instrument_token] = ki;
    }
    _mark('5_instruments');

    // Optional exchange/script narrowing for the Client P&L Summary screen —
    // filters which trades feed every downstream P&L/brokerage calculation
    // below, rather than filtering the already-computed report rows (a
    // per-row total is a sum across trades, so it can only be scoped to a
    // subset of trades before that sum happens, not after). Trade documents
    // don't carry exchange/raw_name directly on the ones loaded here (only
    // instrument_token, price, qty, pnl were selected above and in the
    // Redis cache) — resolved via kiteMap instead, built from the full
    // unfiltered trade set immediately above so every token is covered.
    const { exchange: exchangeFilter, script: scriptFilter } = req.query;
    if (exchangeFilter || scriptFilter) {
      for (const uid of Object.keys(tradesByUser)) {
        tradesByUser[uid] = tradesByUser[uid].filter((t) => {
          const inst = kiteMap[t.instrument_token];
          if (!inst) return false;
          if (exchangeFilter && inst.exchange !== exchangeFilter) return false;
          if (scriptFilter && inst.raw_name !== scriptFilter) return false;
          return true;
        });
      }
    }

    // 7. Load ALL BrokerageSettings (user-specific + caller's own + global)
    //
    // BUG (confirmed live, 2026-08-19 to 2026-08-26): this query's $in list
    // was built from allUserIds alone — every CLIENT under scope, but never
    // the CALLING MASTER's own id. callerRuleOwnerId (below) needs the
    // caller's own rows to compute their real per-instrument brokerage
    // rate, but since those rows were never fetched, brkRulesByUser[caller]
    // was always empty, silently falling back to the global platform rate
    // for every caller's "own rate" — inflating (or deflating) caller_brk/
    // total_caller for every master with a real custom rate, platform-wide,
    // since the batch-loading optimization (5c017b1b) introduced this
    // query. callerRuleOwnerId is computed here (moved up from just below)
    // so it can be included in the fetch, not just the later lookup.
    const callerRuleOwnerId = role === 'admin' ? null : callerId;
    // Confirmed live bug: for an ADMIN caller this previously fetched
    // `allUserIds` alone — every CLIENT under scope, but never any TOP-LEVEL
    // MASTER's own id. `masterOwnRules` (below, admin's per-master "what I
    // charge THIS specific master" rate) reads `brkRulesByUser[master._id]`
    // per row, which was therefore always empty regardless of whether that
    // master had a real individually-assigned rate on file — silently
    // falling back to the flat global default for EVERY top-level master's
    // caller_brk, platform-wide. Unlike the master-role case (a single
    // caller with one set of own rules), admin has no rules of its own —
    // every DIFFERENT top-level master's own id has to be included here, one
    // per row, not just a single "caller" id. Confirmed live: master 157459
    // has ~200 individually-assigned per-script rates (e.g. GOLD MCX-FUT at
    // their own rate), all silently ignored in favour of the global GOLD
    // rate (500/lot vs their actual ~200/lot), inflating "ADMIN BRK" from a
    // verified ~21,585 to a reported 86,184.89 for the same week's trades.
    const topEntityIds = role === 'admin' ? topEntities.map((m) => m._id.toString()) : [];
    const brkSettingsOwnerIds = callerRuleOwnerId
      ? [...allUserIds, callerRuleOwnerId]
      : [...allUserIds, ...topEntityIds];
    const allBrkSettings = await BrokerageSettings.find({
      $or: [
        { user_id: { $in: brkSettingsOwnerIds }, deleted_at: null },
        { user_id: null, deleted_at: null }
      ]
    }).lean();
    _mark('6_brokerageSettings');

    // Group brokerage rules by user_id
    const brkRulesByUser = {};   // userId → rules[]
    const globalBrkRules = [];
    for (const r of allBrkSettings) {
      if (!r.user_id) {
        globalBrkRules.push(r);
      } else {
        const uid = r.user_id.toString();
        if (!brkRulesByUser[uid]) brkRulesByUser[uid] = [];
        brkRulesByUser[uid].push(r);
      }
    }

    // Caller's rules (for caller brokerage base clearance calculation)
    let callerRules;
    if (callerRuleOwnerId === null) {
      callerRules = globalBrkRules;
    } else {
      callerRules = brkRulesByUser[callerRuleOwnerId] || [];
      if (callerRules.length === 0) callerRules = globalBrkRules;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // PHASE 2: Compute report using in-memory data (zero DB queries)
    // ═══════════════════════════════════════════════════════════════════════

    const data = [];

    if (role === 'admin') {
      for (const master of topEntities) {
        // Admin's "own rate" is NOT one flat global default shared by every
        // master — admin assigns each top-level master its own base rate
        // (stored as that master's own BrokerageSettings rows, same as any
        // other owner), and different masters are routinely given different
        // rates. Using the single request-wide `callerRules` (always
        // resolved to global for role==='admin', see callerRuleOwnerId
        // above) here meant every master's row was priced at the flat
        // global default regardless of what admin actually assigned that
        // specific master — inflating (or deflating) Master Brk for every
        // master whose own assigned rate differs from the global default.
        // Resolve per-master here instead, falling back to global only if
        // this master has no rate of their own.
        const masterOwnRules = brkRulesByUser[master._id.toString()] || globalBrkRules;
        const entry = _getAggregatedEntryBatched(
          master._id.toString(), master, metricsEngine, callerId, 'admin',
          masterMap, masterChildrenMap, usersByMaster, tradesByUser, kiteMap, brkRulesByUser, globalBrkRules, masterOwnRules
        );
        entry.parent_username = 'ADMIN';
        entry.type = 'master';
        data.push(entry);
      }
    } else {
      // Child masters
      for (const cm of topEntities) {
        const entry = _getAggregatedEntryBatched(
          cm._id.toString(), cm, metricsEngine, callerId, 'master',
          masterMap, masterChildrenMap, usersByMaster, tradesByUser, kiteMap, brkRulesByUser, globalBrkRules, callerRules
        );
        entry.parent_username = callerMaster?.username || '';
        entry.type = 'master';
        data.push(entry);
      }

      // Direct users
      const directUsers = usersByMaster[callerId] || [];
      for (const u of directUsers) {
        const entry = _getUserEntryBatched(
          u, metricsEngine, callerMaster, callerId, 'master',
          masterMap, tradesByUser, kiteMap, brkRulesByUser, globalBrkRules, callerRules
        );
        data.push(entry);
      }
    }

    _mark('7_compute');
    _timings.totalMs = Date.now() - _t0;
    _timings.masterCount = allMasters.length;
    _timings.userCount = allUsers.length;
    console.log(`[WeeklyAdminReport] ${_timings.totalMs}ms —`, JSON.stringify(_timings));

    // Distinct exchange/script values actually present in-period across the
    // caller's scope, for the Client P&L Summary screen's two filter
    // dropdowns — from kiteMap (built above from the FULL unfiltered trade
    // set, before the exchange/script narrowing above was applied), so
    // these lists don't shrink to just the currently-selected filter.
    const availableExchanges = [...new Set(kiteInstruments.map((k) => k.exchange).filter(Boolean))].sort();
    const availableScripts = [...new Set(kiteInstruments.map((k) => k.raw_name).filter(Boolean))].sort();

    res.json({
      success: true,
      data,
      totals: _sumTotals(data),
      available_exchanges: availableExchanges,
      available_scripts: availableScripts,
    });
  } catch (error) {
    console.error('[WeeklyAdminReport] Error:', error.message);
    res.status(500).json({ success: false, message: sanitizeErrorMessage(error) });
  }
};

// ═══════════════════════════════════════════════════════════════════════════
// BATCHED COMPUTATION FUNCTIONS (zero DB queries — pure in-memory)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * BFS to get all sub-master IDs under a given master (inclusive).
 * Same logic as masterHierarchyService.getAllSubMasterIds but from in-memory map.
 */
function _getAllSubMasterIdsBatched(masterId, masterChildrenMap) {
  const result = [masterId];
  const queue = [masterId];

  while (queue.length > 0) {
    const currentId = queue.shift();
    const children = masterChildrenMap[currentId] || [];
    for (const child of children) {
      const childId = child._id.toString();
      result.push(childId);
      queue.push(childId);
    }
  }

  return result;
}

/**
 * Report entry for a single user. (No DB queries)
 */
function _getUserEntryBatched(userDoc, metricsEngine, callerMaster, callerId, callerRole,
  masterMap, tradesByUser, kiteMap, brkRulesByUser, globalBrkRules, callerRules) {

  const userId = userDoc._id.toString();
  const metrics = metricsEngine.getCachedMetrics(userId);
  const floatingPnl = metrics?.position_pnl || 0;
  const grossPnl = _getGrossPnlBatched(userId, tradesByUser);
  const { brokerage: totalBrokerage, turnover, lots } = _getUserBrokerageAndTurnoverBatched(
    userId, tradesByUser, brkRulesByUser, globalBrkRules, kiteMap
  );

  // Ceiling-based sharing (see _ceilingPct) — a direct client is the bottom
  // of the chain, so the caller's own retention for THIS pool is their full
  // ceiling (nothing further was carved out below them on this line).
  const callerPnlCeiling = _ceilingPct(callerId, callerRole, masterMap, 'pnl_sharing');
  const callerBrkCeiling = _ceilingPct(callerId, callerRole, masterMap, 'brokerage_sharing');

  // Caller's brokerage share (own base rate + ceiling-based share of the spread)
  const callerBrk = _computeCallerBrkForUserBatched(
    userId, tradesByUser, callerRules, kiteMap, totalBrokerage, callerBrkCeiling
  );

  // Sharing is priced off the client's REAL total exposure (realised + still-
  // open m2m), not realised alone.
  const sharingBasis = grossPnl + floatingPnl;
  const callerProfit = _r2((-sharingBasis) * callerPnlCeiling / 100);

  // What the caller (whoever is viewing this report — a sub-master included)
  // must pass UP to their OWN parent — the complement of the caller's own
  // ceiling, applied to the same original total (not a shrinking remainder).
  const owedUpwardPnl = _r2((-sharingBasis) * (100 - callerPnlCeiling) / 100);
  // owed_upward_brk is the complement of caller_brk against this user's own
  // totalBrokerage — mirrors owed_upward_pnl's own complement pattern above.
  const owedUpwardBrk = _r2(totalBrokerage - callerBrk);

  return {
    id: userId,
    name: userDoc.name,
    username: userDoc.username,
    parent_username: callerMaster?.username || '',
    type: 'user',
    realised_pnl: _r2(grossPnl),
    m2m_pnl: _r2(floatingPnl),
    brokerage: _r2(totalBrokerage),
    turnover: _r2(turnover),
    caller_brk: _r2(callerBrk),
    // Net of BOTH realised and floating — was previously just -grossPnl,
    // silently ignoring m2m_pnl entirely, so "total" wasn't actually the
    // total. caller_profit/owed_upward_pnl above now share this same
    // realised+m2m basis (sharingBasis).
    total_pnl: _r2(-(grossPnl + floatingPnl)),
    caller_profit: callerProfit,
    total_caller: _r2(callerProfit + callerBrk),
    owed_upward_pnl: owedUpwardPnl,
    owed_upward_brk: owedUpwardBrk,
    total_owed_upward: _r2(owedUpwardPnl + owedUpwardBrk),
  };
}

/**
 * Aggregated report entry for a master and their entire sub-hierarchy. (No DB queries)
 */
function _getAggregatedEntryBatched(masterId, masterDoc, metricsEngine, callerId, callerRole,
  masterMap, masterChildrenMap, usersByMaster, tradesByUser, kiteMap, brkRulesByUser, globalBrkRules, callerRules) {

  const allMasterIds = _getAllSubMasterIdsBatched(masterId, masterChildrenMap);

  // Collect all users under this master's sub-tree
  const users = [];
  for (const mid of allMasterIds) {
    const usersForMaster = usersByMaster[mid] || [];
    users.push(...usersForMaster);
  }

  // Single pass per user for every per-user figure this row needs — raw
  // sums only (P&L, brokerage, turnover, caller's brokerage base+spread).
  // Sharing itself (caller_profit/owed_upward_pnl/owed_upward_brk) is NOT
  // computed per user — see the ceiling-based math below the loop.
  //
  // Ceiling-based sharing (see _ceilingPct): masterId (this row's own top
  // node) is ALWAYS the caller's DIRECT child on the path to every single
  // user in this row's entire sub-tree, no matter how many further tiers
  // sit between masterId and any individual user — so the caller's own
  // retention weight (their own ceiling minus masterId's ceiling) is the
  // SAME flat percentage for every user here, and can be applied to the
  // row's TOTAL pool once, rather than per user. Replaces an earlier
  // "retention of a shrinking remainder" cascade that multiplied
  // (100-share)/100 at every intermediate tier between a user and the
  // caller — confirmed wrong against a real 4-tier hierarchy where every
  // tier was supposed to keep a flat, non-cascading % of the client's
  // ORIGINAL total (10%/15%/25%/25%/25% from Admin down, summing to 100%).
  const callerPnlCeiling = _ceilingPct(callerId, callerRole, masterMap, 'pnl_sharing');
  const callerBrkCeiling = _ceilingPct(callerId, callerRole, masterMap, 'brokerage_sharing');
  const masterPnlCeiling = masterDoc.pnl_sharing || 0;
  const masterBrkCeiling = masterDoc.brokerage_sharing || 0;
  const callerPnlRetentionPct = callerPnlCeiling - masterPnlCeiling;
  const callerBrkRetentionPct = callerBrkCeiling - masterBrkCeiling;

  let totalGrossPnl = 0;
  let totalFloatingPnl = 0;
  let totalBrokerage = 0, totalTurnover = 0, callerBrk = 0;
  for (const u of users) {
    const uid = u._id.toString();

    const metrics = metricsEngine.getCachedMetrics(uid);
    const userFloatingPnl = metrics?.position_pnl || 0;
    totalFloatingPnl += userFloatingPnl;

    const userGrossPnl = _getGrossPnlBatched(uid, tradesByUser);
    totalGrossPnl += userGrossPnl;

    const { brokerage, turnover } = _getUserBrokerageAndTurnoverBatched(
      uid, tradesByUser, brkRulesByUser, globalBrkRules, kiteMap
    );
    totalBrokerage += brokerage;
    totalTurnover += turnover;
    callerBrk += _computeCallerBrkForUserBatched(
      uid, tradesByUser, callerRules, kiteMap, brokerage, callerBrkRetentionPct
    );
  }

  // Sharing is priced off the sub-tree's REAL total exposure (realised +
  // still-open m2m), not realised alone.
  const sharingBasis = totalGrossPnl + totalFloatingPnl;
  const callerProfit = _r2((-sharingBasis) * callerPnlRetentionPct / 100);
  // What the caller must pass UP to their OWN parent — the complement of
  // the caller's own ceiling (not masterId's), applied to the row's whole
  // original total.
  const owedUpwardPnl = _r2((-sharingBasis) * (100 - callerPnlCeiling) / 100);
  callerBrk = _r2(callerBrk);
  // owed_upward_brk is the complement of caller_brk against this row's own
  // totalBrokerage — mirrors owed_upward_pnl's own complement pattern above.
  const owedUpwardBrk = _r2(totalBrokerage - callerBrk);

  return {
    id: masterId,
    name: masterDoc.name,
    username: masterDoc.username,
    realised_pnl: _r2(totalGrossPnl),
    m2m_pnl: _r2(totalFloatingPnl),
    brokerage: _r2(totalBrokerage),
    turnover: _r2(totalTurnover),
    caller_brk: _r2(callerBrk),
    // Net of BOTH realised and floating. caller_profit's own basis differs
    // by caller role — see the callerProfitBasis comment in the loop above:
    // realised-only for a master's own view, realised+m2m for admin's.
    total_pnl: _r2(-(totalGrossPnl + totalFloatingPnl)),
    caller_profit: callerProfit,
    total_caller: _r2(callerProfit + callerBrk),
    owed_upward_pnl: owedUpwardPnl,
    owed_upward_brk: owedUpwardBrk,
    total_owed_upward: _r2(owedUpwardPnl + owedUpwardBrk),
  };
}

/**
 * Confirmed business rule (replaces an earlier "retention of a shrinking
 * remainder" cascade that multiplied (100-share)/100 at every intermediate
 * tier): sharing is a CEILING, not a per-hop retention rate. Each account's
 * own pnl_sharing/brokerage_sharing is the CUMULATIVE allocation their own
 * parent handed them at creation time — Admin's implicit ceiling is 100
 * (nothing sits above them). A specific master's own personal cut for a
 * given pool = their own ceiling % MINUS the ceiling % they actually handed
 * to whichever direct child sits between them and that pool (0 for a direct
 * client, since nothing further was carved out on that specific line) —
 * see _getUserEntryBatched and _getAggregatedEntryBatched for the two call
 * sites. Every tier's own cut, from Admin down to a client's direct master,
 * always sums to exactly 100% of the client's original total — confirmed
 * against a real 4-tier hierarchy where every intermediate tier's stored
 * ceiling summed correctly (Admin 10% + 15% + 25% + 25% + 25% = 100%).
 */
function _ceilingPct(id, role, masterMap, shareField) {
  if (role === 'admin') return 100;
  return masterMap[id]?.[shareField] || 0;
}

/**
 * Compute caller's brokerage share for a single user using their own
 * configured rate as a floor, plus their ceiling-based share of the spread
 * above that floor. (No DB queries)
 *
 * `userTotalBrk` is passed in rather than recomputed — every call site
 * already calls _getUserBrokerageAndTurnoverBatched for this same user a
 * few lines earlier (for the report's own `brokerage` column); this used
 * to redo that same per-trade iteration a second time internally, doubling
 * the JS-side work for every user in the report.
 *
 * `callerOwnRetentionPct` is the caller's own ceiling-based retention for
 * THIS specific pool (see _ceilingPct) — 0-100, computed once by the caller
 * (identical for every user in an aggregated sub-tree row, so it's wasteful
 * to recompute per user here).
 */
function _computeCallerBrkForUserBatched(userId, tradesByUser, callerRules, kiteMap, userTotalBrk, callerOwnRetentionPct) {
  const trades = tradesByUser[userId] || [];
  if (trades.length === 0) return 0;

  // Group trades by instrument
  const byInstrument = {};
  for (const t of trades) {
    const token = t.instrument_token;
    if (!byInstrument[token]) byInstrument[token] = { turnover: 0, lots: 0 };
    const ki = kiteMap[token];
    const lotSize = ki?.lot_size || 1;
    byInstrument[token].turnover += t.executed_price * t.executed_quantity;
    byInstrument[token].lots += lotSize > 1 ? t.executed_quantity / lotSize : t.executed_quantity;
  }

  // Compute caller's base clearance per instrument
  let callerBaseClearance = 0;
  for (const [token, data] of Object.entries(byInstrument)) {
    const ki = kiteMap[token];
    const seg = ki?.segment || '';
    const rawName = ki?.raw_name || '';

    let callerRule = _findRule(callerRules, rawName, seg);
    if (!callerRule) continue;

    if (callerRule.type === 'TURNOVER WISE') {
      callerBaseClearance += data.turnover * (callerRule.brk_value / 10000);
    } else if (callerRule.type === 'LOT WISE') {
      callerBaseClearance += data.lots * callerRule.brk_value;
    }
  }

  // Spread above caller's base = what's left after caller takes their base;
  // the caller adds their ceiling-based complement share of that spread on
  // top of their own base clearance.
  const spreadAboveCaller = Math.max(0, userTotalBrk - callerBaseClearance);
  const unpassedAmount = spreadAboveCaller * (100 - callerOwnRetentionPct) / 100;

  return callerBaseClearance + unpassedAmount;
}

/**
 * Gross realised P&L (sum of trade.pnl). Same as original _getGrossPnl but from pre-loaded array.
 */
function _getGrossPnlBatched(userId, tradesByUser) {
  const trades = tradesByUser[userId] || [];
  let total = 0;
  for (const t of trades) {
    total += t.pnl || 0;
  }
  return total;
}

/**
 * User's total brokerage, turnover, and lots from current trades. (No DB queries)
 * Same logic as original _getUserBrokerageAndTurnover.
 */
function _getUserBrokerageAndTurnoverBatched(userId, tradesByUser, brkRulesByUser, globalBrkRules, kiteMap) {
  const trades = tradesByUser[userId] || [];
  if (trades.length === 0) return { brokerage: 0, turnover: 0, lots: 0 };

  const ownRules = brkRulesByUser[userId] || [];

  let totalBrk = 0, totalTurnover = 0, totalLots = 0;
  for (const t of trades) {
    const ki = kiteMap[t.instrument_token];
    const seg = ki?.segment || '';
    const rawName = ki?.raw_name || '';
    const lotSize = ki?.lot_size || 1;
    const tradeTurnover = t.executed_price * t.executed_quantity;
    const tradeLots = lotSize > 1 ? t.executed_quantity / lotSize : t.executed_quantity;

    totalTurnover += tradeTurnover;
    totalLots += tradeLots;

    // Try the client's own custom rules first, then fall back to the global
    // rule set PER INSTRUMENT — not just when the client has zero custom
    // rules at all. A client with SOME custom rules (e.g. an NSE-only
    // override) but none matching THIS instrument (e.g. an MCX trade)
    // previously fell through silently: real turnover, zero brokerage, no
    // error, because the old code only consulted the global list when the
    // client's own rule array was completely empty.
    const brkRule = _findRule(ownRules, rawName, seg) || _findRule(globalBrkRules, rawName, seg);
    if (brkRule) {
      if (brkRule.type === 'TURNOVER WISE') {
        totalBrk += tradeTurnover * (brkRule.brk_value / 10000);
      } else if (brkRule.type === 'LOT WISE') {
        totalBrk += tradeLots * brkRule.brk_value;
      }
    }
  }

  return { brokerage: totalBrk, turnover: totalTurnover, lots: totalLots };
}

/**
 * Find a brokerage rule using 4-level matching. (Unchanged — already pure in-memory)
 */
function _findRule(rules, rawName, seg) {
  let rule = null;
  if (rawName && seg) rule = rules.find(r => r.script_name?.toUpperCase() === rawName.toUpperCase() && r.exchange_name === seg.toUpperCase());
  if (!rule && rawName) rule = rules.find(r => r.script_name?.toUpperCase() === rawName.toUpperCase());
  if (!rule && seg) rule = rules.find(r => r.exchange_name === seg.toUpperCase() && (!r.script_name || r.script_name.trim() === ''));
  // Guarded by `seg` here too — an instrument missing from kiteMap (token
  // not found) passes seg='', and `''.split('-')[0] || ''` still evaluates
  // to '', so this used to match any rule with a blank exchange_name for
  // ANY unrecognized instrument, applying an unrelated rate. No seg means
  // no rule, not a guess.
  if (!rule && seg) rule = rules.find(r => r.exchange_name === (seg.split('-')[0] || '').toUpperCase() && (!r.script_name || r.script_name.trim() === ''));
  return rule;
}

function _sumTotals(data) {
  return {
    realised_pnl: _r2(data.reduce((s, d) => s + d.realised_pnl, 0)),
    m2m_pnl: _r2(data.reduce((s, d) => s + d.m2m_pnl, 0)),
    brokerage: _r2(data.reduce((s, d) => s + d.brokerage, 0)),
    turnover: _r2(data.reduce((s, d) => s + (d.turnover || 0), 0)),
    caller_brk: _r2(data.reduce((s, d) => s + (d.caller_brk || 0), 0)),
    total_pnl: _r2(data.reduce((s, d) => s + d.total_pnl, 0)),
    caller_profit: _r2(data.reduce((s, d) => s + (d.caller_profit || 0), 0)),
    total_caller: _r2(data.reduce((s, d) => s + (d.total_caller || 0), 0)),
    owed_upward_pnl: _r2(data.reduce((s, d) => s + (d.owed_upward_pnl || 0), 0)),
    owed_upward_brk: _r2(data.reduce((s, d) => s + (d.owed_upward_brk || 0), 0)),
    total_owed_upward: _r2(data.reduce((s, d) => s + (d.total_owed_upward || 0), 0)),
  };
}

const _r2 = (n) => Math.round(n * 100) / 100;

module.exports = {
  getWeeklyAdminReport,
  _private: {
    _computeCallerBrkForUserBatched,
    _ceilingPct,
    _getUserBrokerageAndTurnoverBatched,
    _findRule,
  },
};
