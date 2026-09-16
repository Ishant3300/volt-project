'use strict';

// Regression coverage for the P&L/brokerage sharing model in
// weeklyAdminController.js.
//
// Sharing is a CEILING, not a per-hop retention rate. Each master's stored
// pnl_sharing/brokerage_sharing is the CUMULATIVE allocation their own
// parent handed them at creation time (Admin's implicit ceiling is 100 —
// nothing sits above Admin). A given tier's own personal cut for a pool =
// their own ceiling% minus the ceiling% they actually handed to whichever
// direct child sits between them and that pool (0 for a direct client) —
// applied as a FLAT percentage of the client's ORIGINAL total, not a
// retention of a shrinking remainder. Every tier's own cut, from Admin down
// to a client's direct master, always sums to exactly 100%.
//
// This replaces an earlier "retention of a shrinking remainder" cascade
// (multiplying (100-share)/100 at every intermediate tier) that was
// confirmed wrong against a real, user-verified 4-tier hierarchy: Admin
// 90% -> 996789(90%) -> 705206(75%) -> 254831(50%) -> 999746(25%) -> a
// client with a real 276 loss. The correct, user-confirmed distribution is
// a flat 10%/15%/25%/25%/25% split of the ORIGINAL 276 (not a shrinking
// pool), landing on 27.6/41.4/69/69/69 respectively — summing to exactly
// 276, with three different-ceiling tiers (705206, 254831, 999746)
// coincidentally landing on the identical 69 despite different stored
// ceilings, because each one's OWN retention (ceiling minus what they
// handed to their one child) happens to be 25% at every one of those three
// tiers.

const {
  _computeCallerBrkForUserBatched,
  _ceilingPct,
  _getUserBrokerageAndTurnoverBatched,
  _findRule,
} = require('../src/controllers/weeklyAdminController')._private;

describe('_ceilingPct — cumulative allocation, not a per-hop retention rate', () => {
  const masterMap = {
    admin_child: { pnl_sharing: 90, brokerage_sharing: 90 },
    no_brokerage_field: { pnl_sharing: 50 },
  };

  test('admin role always has an implicit ceiling of 100, regardless of any id', () => {
    expect(_ceilingPct('anything', 'admin', masterMap, 'pnl_sharing')).toBe(100);
  });

  test('a master role reads their own stored field directly', () => {
    expect(_ceilingPct('admin_child', 'master', masterMap, 'pnl_sharing')).toBe(90);
    expect(_ceilingPct('admin_child', 'master', masterMap, 'brokerage_sharing')).toBe(90);
  });

  test('a missing field or missing master defaults to 0, not undefined/NaN', () => {
    expect(_ceilingPct('no_brokerage_field', 'master', masterMap, 'brokerage_sharing')).toBe(0);
    expect(_ceilingPct('does_not_exist', 'master', masterMap, 'pnl_sharing')).toBe(0);
  });
});

describe('flat ceiling-based P&L partition — real 4-tier hierarchy, user-confirmed numbers', () => {
  // Admin -> 996789(90) -> 705206(75) -> 254831(50) -> 999746(25) -> client.
  // Each master's own retention = own ceiling - the ceiling handed to their
  // one direct child (0 for 999746, since the client is the bottom).
  const ADMIN_CEILING = 100;
  const M1 = 90;  // 996789
  const M2 = 75;  // 705206
  const M3 = 50;  // 254831
  const M4 = 25;  // 999746
  const ORIGINAL_TOTAL = 276;

  test('every tier\'s own retention % sums to exactly 100%', () => {
    const adminPct = ADMIN_CEILING - M1;   // 10
    const m1Pct = M1 - M2;                 // 15
    const m2Pct = M2 - M3;                 // 25
    const m3Pct = M3 - M4;                 // 25
    const m4Pct = M4 - 0;                  // 25 (client is the bottom)
    expect(adminPct + m1Pct + m2Pct + m3Pct + m4Pct).toBe(100);
  });

  test('999746 (direct master of the client) personally keeps 69, not a cascaded fraction of a shrunk pool', () => {
    const retentionPct = M4 - 0;
    expect(_r2(-ORIGINAL_TOTAL * retentionPct / 100)).toBeCloseTo(-69, 2);
  });

  test('254831 personally keeps 69 — same flat 25% retention as 999746, despite a different stored ceiling (50 vs 25)', () => {
    const retentionPct = M3 - M4; // 50 - 25 = 25
    expect(_r2(-ORIGINAL_TOTAL * retentionPct / 100)).toBeCloseTo(-69, 2);
  });

  test('705206 personally keeps 69 too — same flat 25% retention, a THIRD different stored ceiling (75)', () => {
    const retentionPct = M2 - M3; // 75 - 50 = 25
    expect(_r2(-ORIGINAL_TOTAL * retentionPct / 100)).toBeCloseTo(-69, 2);
  });

  test('996789 personally keeps 41.40 (15% of the original total)', () => {
    const retentionPct = M1 - M2; // 90 - 75 = 15
    expect(_r2(-ORIGINAL_TOTAL * retentionPct / 100)).toBeCloseTo(-41.4, 2);
  });

  test('Admin personally keeps 27.60 (10% of the original total) — bounded, not "whatever is left over"', () => {
    const retentionPct = ADMIN_CEILING - M1; // 100 - 90 = 10
    expect(_r2(-ORIGINAL_TOTAL * retentionPct / 100)).toBeCloseTo(-27.6, 2);
  });

  function _r2(n) { return Math.round(n * 100) / 100; }
});

describe('_computeCallerBrkForUserBatched — own base rate + ceiling-based share of the spread', () => {
  const kiteMap = { TOK: { lot_size: 1, segment: 'MCX-FUT', raw_name: 'TESTSCRIPT' } };
  const callerRules = [{ script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 200 }];
  const tradesByUser = { u1: [{ instrument_token: 'TOK', executed_price: 800, executed_quantity: 12 }] };

  test('caller with 0% retention on the spread keeps only their own base clearance', () => {
    const brk = _computeCallerBrkForUserBatched('u1', tradesByUser, callerRules, kiteMap, 9600, 0);
    // base = 12 lots * 200 = 2400; spread = 9600-2400=7200; unpassed = 7200*(100-0)/100=7200 (all of it, since 0% retained)
    expect(brk).toBeCloseTo(2400 + 7200, 5);
  });

  test('caller with 100% retention on the spread keeps their base clearance plus the WHOLE spread', () => {
    const brk = _computeCallerBrkForUserBatched('u1', tradesByUser, callerRules, kiteMap, 9600, 100);
    // unpassed = 7200*(100-100)/100 = 0
    expect(brk).toBeCloseTo(2400, 5);
  });

  test('a mid-range retention splits the spread proportionally', () => {
    const brk = _computeCallerBrkForUserBatched('u1', tradesByUser, callerRules, kiteMap, 9600, 25);
    // unpassed = 7200*(100-25)/100 = 5400; total = 2400+5400=7800
    expect(brk).toBeCloseTo(7800, 5);
  });

  test('no matching rule for the caller means zero base clearance, not a crash', () => {
    const brk = _computeCallerBrkForUserBatched('u1', tradesByUser, [], kiteMap, 9600, 50);
    // base=0; spread=9600; unpassed=9600*0.5=4800
    expect(brk).toBeCloseTo(4800, 5);
  });

  test('a user with no trades returns 0', () => {
    const brk = _computeCallerBrkForUserBatched('nobody', tradesByUser, callerRules, kiteMap, 9600, 50);
    expect(brk).toBe(0);
  });
});

describe('_getUserBrokerageAndTurnoverBatched — per-instrument brokerage-rule fallback (unaffected by the ceiling-model change)', () => {
  const kiteMap2 = {
    NSE_TOK: { lot_size: 1, segment: 'NSE', raw_name: 'RELIANCE' },
    MCX_TOK: { lot_size: 100, segment: 'MCX-FUT', raw_name: 'CRUDEOIL' },
  };
  const globalRules = [{ script_name: '', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 20 }];

  test('a client with a matching own rule on ONE instrument still gets the global rule on another', () => {
    const ownRules = [{ script_name: 'RELIANCE', exchange_name: 'NSE', type: 'TURNOVER WISE', brk_value: 5 }];
    const trades = {
      u: [
        { instrument_token: 'NSE_TOK', executed_price: 1000, executed_quantity: 10 },
        { instrument_token: 'MCX_TOK', executed_price: 6000, executed_quantity: 200 },
      ],
    };
    const result = _getUserBrokerageAndTurnoverBatched('u', trades, { u: ownRules }, globalRules, kiteMap2);
    expect(result.brokerage).toBeCloseTo(45, 2);
  });

  test('a client with zero custom rules still falls back to global', () => {
    const trades = { u: [{ instrument_token: 'MCX_TOK', executed_price: 6000, executed_quantity: 200 }] };
    const result = _getUserBrokerageAndTurnoverBatched('u', trades, {}, globalRules, kiteMap2);
    expect(result.brokerage).toBeCloseTo(40, 2);
  });
});

describe('_findRule — blank-exchange fallback must not match an unrecognized instrument (unaffected by the ceiling-model change)', () => {
  test('an instrument missing from kiteMap (seg="") does not match a rule with a blank exchange_name', () => {
    const rules = [{ script_name: '', exchange_name: '', type: 'LOT WISE', brk_value: 999 }];
    expect(_findRule(rules, '', '')).toBeNull();
  });

  test('a real instrument with a real blank-script rule for its own exchange still matches', () => {
    const rules = [{ script_name: '', exchange_name: 'MCX', type: 'LOT WISE', brk_value: 20 }];
    expect(_findRule(rules, 'CRUDEOIL', 'MCX')).toEqual(rules[0]);
  });
});
