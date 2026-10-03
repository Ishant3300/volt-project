'use strict';

// HTTP-handler-level coverage for GET /api/master/weekly-admin-report
// (weeklyAdminController.getWeeklyAdminReport).
//
// weeklyAdminHierarchyCascade.unit.test.js already proves the per-tier
// cascade MATH is depth-safe (via the private helper functions directly,
// exercised with up to 1000-tier synthetic chains) — but nothing previously
// called the actual exported HTTP handler at all, so a regression in the
// handler's OWN scope-building (the allScopeMasterIds BFS that decides which
// masters/users even get loaded from the DB in the first place, independent
// of the cascade math) would have gone unnoticed. This file closes that gap
// with a real 3-tier hierarchy run end-to-end through the handler: a master
// caller with one direct child, who themselves has a further child, who has
// a real trading user — same shape as apex-web-portal's Ledger & Payouts
// audit that this test was added alongside.
//
// All models/services the handler touches are mocked — no DB.

jest.mock('../src/models/Trade', () => ({ find: jest.fn() }));
jest.mock('../src/models/User', () => ({ find: jest.fn() }));
jest.mock('../src/models/Master', () => ({ find: jest.fn(), findById: jest.fn() }));
jest.mock('../src/models/BrokerageSettings', () => ({ find: jest.fn() }));
jest.mock('../src/models/KiteInstrument', () => ({ find: jest.fn() }));
jest.mock('../src/models/MasterBaseRate', () => ({ find: jest.fn() }));
jest.mock('../src/services/weeklyReportCache', () => ({ getUserWeeklyTrades: jest.fn() }));
jest.mock('../src/services/metricsEngine', () => ({ getCachedMetrics: jest.fn() }));
jest.mock('../src/utils/adminVisibility', () => ({ resolveHiddenMasterIds: jest.fn() }));

const Trade = require('../src/models/Trade');
const User = require('../src/models/User');
const Master = require('../src/models/Master');
const BrokerageSettings = require('../src/models/BrokerageSettings');
const KiteInstrument = require('../src/models/KiteInstrument');
const MasterBaseRate = require('../src/models/MasterBaseRate');
const weeklyReportCache = require('../src/services/weeklyReportCache');
const metricsEngine = require('../src/services/metricsEngine');
const { resolveHiddenMasterIds } = require('../src/utils/adminVisibility');
const { getWeeklyAdminReport, _private: { _resetBrokerageRuleCache } } = require('../src/controllers/weeklyAdminController');

function makeRes() {
  const res = {};
  res.status = jest.fn(() => res);
  res.json = jest.fn(() => res);
  return res;
}

// Chainable `.select().lean()` for Master/User/BrokerageSettings/KiteInstrument/MasterBaseRate.find().
function leanChain(rows) {
  const chain = {};
  chain.select = jest.fn(() => chain);
  chain.lean = jest.fn(() => Promise.resolve(rows));
  return chain;
}

const MASTER_A = 'masterA';   // caller
const CHILD_M = 'childM';     // masterA's direct child — the only top-level row for a master caller
const GRANDCHILD_M = 'grandchildM'; // childM's own child — 2 tiers below the caller's direct child
const DEEP_USER = 'deepUser'; // grandchildM's own user — 3 tiers below the caller

beforeEach(() => {
  _resetBrokerageRuleCache();
  jest.clearAllMocks();

  Master.find.mockReturnValue(
    leanChain([
      { _id: MASTER_A, name: 'Master A', username: 'mastera', master_id: null, pnl_sharing: 90, brokerage_sharing: 90 },
      { _id: CHILD_M, name: 'Child Master', username: 'childm', master_id: MASTER_A, pnl_sharing: 80, brokerage_sharing: 80 },
      { _id: GRANDCHILD_M, name: 'Grandchild Master', username: 'grandchildm', master_id: CHILD_M, pnl_sharing: 70, brokerage_sharing: 70 },
    ]),
  );
  Master.findById.mockReturnValue(leanChain({ permissions: { weekly_admin: true } }));

  User.find.mockReturnValue(
    leanChain([
      { _id: DEEP_USER, name: 'Deep User', username: 'deepuser', master_id: GRANDCHILD_M, pnl_sharing: 0, brokerage_sharing: 0 },
    ]),
  );

  BrokerageSettings.find.mockReturnValue(leanChain([]));
  KiteInstrument.find.mockReturnValue(leanChain([{ instrument_token: 'TOK', lot_size: 1, segment: 'MCX-FUT', raw_name: 'TESTSCRIPT', exchange: 'MCX' }]));
  MasterBaseRate.find.mockReturnValue(leanChain([]));

  // Force a cache miss for every user so the trade comes from the live
  // Trade.find fallback path instead — exercises both branches, not just
  // the Redis-cache-hit one.
  weeklyReportCache.getUserWeeklyTrades.mockResolvedValue(null);
  Trade.find.mockReturnValue(leanChain([
    { user_id: DEEP_USER, instrument_token: 'TOK', executed_price: 100, executed_quantity: 10, pnl: 5000 },
  ]));

  metricsEngine.getCachedMetrics.mockReturnValue({ position_pnl: 0 });
  resolveHiddenMasterIds.mockResolvedValue(null);
});

describe('a master caller\'s report reaches 3+ tiers deep, not just direct children', () => {
  test('the direct child\'s aggregate row includes a user two tiers further down', async () => {
    const req = { master: { id: MASTER_A }, admin: null, query: {} };
    const res = makeRes();

    await getWeeklyAdminReport(req, res);

    // The success path calls res.json(...) directly with no explicit
    // .status(200) — see weeklyAdminController.js's own res.json call.
    expect(res.status).not.toHaveBeenCalled();
    const body = res.json.mock.calls[0][0];
    expect(body.success).toBe(true);
    // Only ONE top-level row — masterA's single direct child — even though
    // the real trading user sits two tiers further down inside that child's
    // own sub-tree (aggregated INTO this row, not listed as its own row,
    // which only happens for a caller's DIRECT users).
    expect(body.data).toHaveLength(1);
    const childRow = body.data[0];
    expect(childRow.id).toBe(CHILD_M);
    expect(childRow.type).toBe('master');
    // The deep user's real 5000 pnl must be visible in the aggregate — a
    // regression that silently dropped tiers below "direct children of a
    // direct child" would report 0 here instead. realised_pnl is a plain
    // sum of each in-scope user's trade pnl (weeklyAdminController.js's
    // _getAggregatedEntryBatched: `realised_pnl: _r2(totalGrossPnl)`).
    expect(childRow.realised_pnl).toBe(5000);
  });

  test('User.find is scoped across the WHOLE subtree (masterA, childM, grandchildM), not just direct children', async () => {
    const req = { master: { id: MASTER_A }, admin: null, query: {} };
    const res = makeRes();

    await getWeeklyAdminReport(req, res);

    const scopeArg = User.find.mock.calls[0][0];
    const scopedMasterIds = scopeArg.master_id.$in;
    expect(scopedMasterIds).toEqual(expect.arrayContaining([MASTER_A, CHILD_M, GRANDCHILD_M]));
  });
});

describe('a 30-tier hierarchy computes correctly end-to-end through the real HTTP handler', () => {
  // weeklyAdminHierarchyCascade.unit.test.js already proves the per-tier
  // math itself is depth-independent (only ever needs a tier's own value
  // and their direct child's) using the private helpers directly. This
  // closes the remaining gap: running an actual 30-tier chain through the
  // real exported handler, including the scope-building BFS and the DB
  // query construction, not just the isolated formulas.
  const N = 30;
  const CLIENT_RATE = 1000;
  const tierId = (i) => `t${i}`;
  const ceilingFor = (i) => Math.round((100 * (N - i) / (N + 1)) * 100) / 100;
  const rateFor = (i) => Math.round((CLIENT_RATE * (i + 1) / (N + 1)) * 100) / 100;

  const CLIENT_ID = 'deepClient30';
  const TOP_TIER = tierId(0);       // Admin's direct child
  const BOTTOM_TIER = tierId(N - 1); // the client's direct master

  beforeEach(() => {
    const masters = [];
    for (let i = 0; i < N; i++) {
      masters.push({
        _id: tierId(i),
        name: `Tier ${i}`,
        username: `tier${i}`,
        master_id: i === 0 ? null : tierId(i - 1),
        pnl_sharing: ceilingFor(i),
        brokerage_sharing: ceilingFor(i),
      });
    }
    Master.find.mockReturnValue(leanChain(masters));
    Master.findById.mockReturnValue(leanChain({ permissions: { weekly_admin: true } }));

    User.find.mockReturnValue(leanChain([
      { _id: CLIENT_ID, name: 'Deep Client', username: 'deepclient30', master_id: BOTTOM_TIER, pnl_sharing: 0, brokerage_sharing: 0 },
    ]));

    const kiteMap = [{ instrument_token: 'TOK30', lot_size: 1, segment: 'MCX-FUT', raw_name: 'TESTSCRIPT', exchange: 'MCX' }];
    KiteInstrument.find.mockReturnValue(leanChain(kiteMap));

    // One BrokerageSettings row per tier (own configured rate) plus the client's.
    const brkRows = [];
    for (let i = 0; i < N; i++) {
      brkRows.push({ user_id: tierId(i), script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: rateFor(i) });
    }
    brkRows.push({ user_id: CLIENT_ID, script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: CLIENT_RATE });
    BrokerageSettings.find.mockReturnValue(leanChain(brkRows));
    MasterBaseRate.find.mockReturnValue(leanChain([]));

    weeklyReportCache.getUserWeeklyTrades.mockResolvedValue(null);
    Trade.find.mockReturnValue(leanChain([
      { user_id: CLIENT_ID, instrument_token: 'TOK30', executed_price: 1, executed_quantity: 10, pnl: -1000 },
    ]));

    metricsEngine.getCachedMetrics.mockReturnValue({ position_pnl: 0 });
    resolveHiddenMasterIds.mockResolvedValue(null);
  });

  test('the top tier\'s own row (viewed by Admin) matches the ceiling-difference P&L and rate-gap brokerage formulas at real depth', async () => {
    const req = { admin: { id: 'ADMIN' }, master: null, query: {} };
    const res = makeRes();

    await getWeeklyAdminReport(req, res);

    const body = res.json.mock.calls[0][0];
    const row = body.data.find((r) => r.id === TOP_TIER);
    expect(row).toBeDefined();

    // caller_profit = (Admin's implicit 100 - TOP_TIER's own ceiling) * total P&L
    const expectedPnl = Math.round((100 - ceilingFor(0)) / 100 * 1000 * 100) / 100;
    expect(row.caller_profit).toBeCloseTo(expectedPnl, 1);

    // caller_brk = tier0's own owed-upward pool (their own clearance *
    // (100-their ceiling)/100) minus Admin's own owed-upward (0, since
    // Admin's own clearance is always 0 — no BrokerageSettings rows).
    const incomingPool = rateFor(0) * 10 * (100 - ceilingFor(0)) / 100;
    const expectedBrk = incomingPool;
    expect(row.caller_brk).toBeCloseTo(expectedBrk, 1);
  });

  test('a master caller 15 tiers down still gets the exact rate-gap markup on their direct child\'s row, not a truncated depth-capped value', async () => {
    const CALLER = tierId(14);
    const CHILD = tierId(15);
    const req = { admin: null, master: { id: CALLER }, query: {} };
    const res = makeRes();

    await getWeeklyAdminReport(req, res);

    const body = res.json.mock.calls[0][0];
    const row = body.data.find((r) => r.id === CHILD);
    expect(row).toBeDefined();

    // caller_brk = CHILD's own owed-upward pool (their own clearance *
    // (100-their ceiling)/100) minus CALLER's own owed-upward (same
    // formula, their own clearance and ceiling) — each computed
    // independently off that tier's own rate, never by comparing adjacent
    // tiers' rates directly. See _getAggregatedEntryBatched.
    const incomingPool = rateFor(15) * 10 * (100 - ceilingFor(15)) / 100;
    const callerOwedUpward = rateFor(14) * 10 * (100 - ceilingFor(14)) / 100;
    const expectedBrk = incomingPool - callerOwedUpward;
    expect(row.caller_brk).toBeCloseTo(expectedBrk, 1);

    // caller_profit = (CALLER's own ceiling - CHILD's own ceiling) * total P&L
    const expectedPnl = (ceilingFor(14) - ceilingFor(15)) / 100 * 1000;
    expect(row.caller_profit).toBeCloseTo(expectedPnl, 1);
  });

  test('the bottom-most tier (29 of 30, the client\'s direct master) keeps the full client-facing markup', async () => {
    const req = { admin: null, master: { id: tierId(N - 2) }, query: {} };
    const res = makeRes();

    await getWeeklyAdminReport(req, res);

    const body = res.json.mock.calls[0][0];
    const directUserRow = body.data.find((r) => r.type === 'user' && r.id === CLIENT_ID);
    // The bottom-most master's own users only appear as direct-user rows on
    // THEIR OWN dashboard, not on an ancestor's — this caller (tier N-2) is
    // the bottom tier's direct parent, so the client shows up nested inside
    // BOTTOM_TIER's aggregate row instead.
    expect(directUserRow).toBeUndefined();
    const bottomRow = body.data.find((r) => r.id === BOTTOM_TIER);
    const incomingPool = rateFor(N - 1) * 10 * (100 - ceilingFor(N - 1)) / 100;
    const callerOwedUpward = rateFor(N - 2) * 10 * (100 - ceilingFor(N - 2)) / 100;
    const expectedBrk = incomingPool - callerOwedUpward;
    expect(bottomRow.caller_brk).toBeCloseTo(expectedBrk, 1);
  });

  test('caller_brk + owed_upward_brk always reconstructs exactly the incoming pool from the child\'s own owed-upward, no leakage', async () => {
    // Structural proof: caller_brk = incomingPool - callerOwedUpward, and
    // owed_upward_brk = callerOwedUpward — so their sum must always equal
    // incomingPool exactly, for every row, at any depth.
    const CALLER = tierId(14);
    const CHILD = tierId(15);
    const req = { admin: null, master: { id: CALLER }, query: {} };
    const res = makeRes();

    await getWeeklyAdminReport(req, res);

    const body = res.json.mock.calls[0][0];
    const row = body.data.find((r) => r.id === CHILD);
    const incomingPool = rateFor(15) * 10 * (100 - ceilingFor(15)) / 100;
    expect(row.caller_brk + row.owed_upward_brk).toBeCloseTo(incomingPool, 1);
  });
});
