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
const { getWeeklyAdminReport } = require('../src/controllers/weeklyAdminController');

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
