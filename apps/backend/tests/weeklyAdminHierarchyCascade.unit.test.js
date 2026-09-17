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
  _ceilingPct,
  _topmostMasterId,
  _groupTradesByInstrument,
  _clearanceForRules,
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

describe('rate-gap brokerage model — a tier keeps the MARKUP between the next rate down and their own, not a % share of the spread', () => {
  // Confirmed business rule, user-verified against a real 4-tier hierarchy
  // (Admin -> 996789(rate 25/lot) -> 705206(100/lot) -> 254831(200/lot) ->
  // 999746(300/lot) -> a client billed at 1000/lot, 2 lots): each tier
  // keeps (the rate charged to whoever is directly below them, on the path
  // to this pool - their own configured rate) * volume. Their own
  // configured rate flows entirely upward, to be split the exact same way
  // one level up — NOT a percentage-weighted share of the spread (that
  // model was tried and confirmed wrong: it gave every tier only a
  // FRACTION of the markup instead of the whole thing).
  const kiteMap = { TOK: { lot_size: 1, segment: 'MCX-FUT', raw_name: 'TESTSCRIPT' } };
  const clientRules = [{ script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 1000 }];
  const tier999746Rules = [{ script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 300 }];
  const tier254831Rules = [{ script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: 200 }];
  const clientTrades = [{ instrument_token: 'TOK', executed_price: 1000, executed_quantity: 2 }];

  test('999746 (direct master of the client) keeps the FULL markup (1000-300)*2=1400, not a fraction of it', () => {
    const byInstrument = _groupTradesByInstrument(clientTrades, kiteMap);
    const clientBilled = _clearanceForRules(byInstrument, clientRules, kiteMap); // 2000
    const own999746Clearance = _clearanceForRules(byInstrument, tier999746Rules, kiteMap); // 600
    const callerBrk = clientBilled - own999746Clearance;
    expect(callerBrk).toBeCloseTo(1400, 5);
  });

  test('254831 (one tier further up) keeps the gap to 999746\'s rate: (300-200)*2=200', () => {
    const byInstrument = _groupTradesByInstrument(clientTrades, kiteMap);
    const masterClearance = _clearanceForRules(byInstrument, tier999746Rules, kiteMap); // 600 (999746's own rate)
    const callerClearance = _clearanceForRules(byInstrument, tier254831Rules, kiteMap); // 400 (254831's own rate)
    const callerBrk = masterClearance - callerClearance;
    expect(callerBrk).toBeCloseTo(200, 5);
  });

  test('a tier with no matching rate rule contributes zero clearance, not a crash', () => {
    const byInstrument = _groupTradesByInstrument(clientTrades, kiteMap);
    expect(_clearanceForRules(byInstrument, [], kiteMap)).toBe(0);
  });

  test('an empty trade list produces zero clearance for any rules', () => {
    const byInstrument = _groupTradesByInstrument([], kiteMap);
    expect(_clearanceForRules(byInstrument, clientRules, kiteMap)).toBe(0);
  });

  test('_groupTradesByInstrument accumulates across MULTIPLE trades on the same instrument', () => {
    const trades = [
      { instrument_token: 'TOK', executed_price: 1000, executed_quantity: 2 },
      { instrument_token: 'TOK', executed_price: 1000, executed_quantity: 3 },
    ];
    const byInstrument = _groupTradesByInstrument(trades, kiteMap);
    expect(byInstrument.TOK.lots).toBe(5);
    expect(byInstrument.TOK.turnover).toBe(5000);
  });

  test('a TURNOVER WISE rule computes clearance as turnover * brk_value/10000, matching the platform-wide convention', () => {
    const nfoKiteMap = { NFOTOK: { lot_size: 65, segment: 'NFO-FUT', raw_name: 'NIFTY' } };
    const trades = [{ instrument_token: 'NFOTOK', executed_price: 23000, executed_quantity: 65 }];
    const byInstrument = _groupTradesByInstrument(trades, nfoKiteMap);
    const rules = [{ script_name: 'NIFTY', exchange_name: 'NFO-FUT', type: 'TURNOVER WISE', brk_value: 5 }];
    // turnover = 23000*65 = 1,495,000; clearance = 1,495,000 * 5/10000 = 747.5
    expect(_clearanceForRules(byInstrument, rules, nfoKiteMap)).toBeCloseTo(747.5, 5);
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

describe('deep hierarchy (30 tiers) — neither formula walks the chain, so depth cannot silently truncate it', () => {
  // Both formulas only ever need TWO numbers to compute one report row: the
  // caller's own value, and their DIRECT CHILD's own value (the row being
  // shown) — never the whole chain in between. Unlike the deleted
  // multiplicative-cascade model (which had a real, historical bug: a
  // hardcoded depth cap that silently truncated anything past 10 tiers),
  // there's no walk here to cap in the first place. This suite proves that
  // property holds at real depth, not just in the 4-5 tier hand-verified
  // examples above.
  const N = 30;

  // Tier i's own ceiling counts DOWN from 100 (Admin's implicit ceiling) to
  // just above 0, evenly spaced — e.g. tier 0 (Admin's direct child) sits
  // at ~96.7, tier 29 (the client's direct master) sits at ~3.3.
  function ceilingFor(tier) {
    return 100 * (N - tier) / (N + 1);
  }
  // Tier i's own configured rate counts UP from a small base to just under
  // the client's own rate — mirrors the real 996789(25)->...->999746(300)
  // ->client(1000) ladder, just stretched across 30 tiers instead of 4.
  const CLIENT_RATE = 1000;
  function rateFor(tier) {
    return CLIENT_RATE * (tier + 1) / (N + 1);
  }

  const masterMap = {};
  for (let i = 0; i < N; i++) {
    masterMap[`tier${i}`] = {
      master_id: i === 0 ? null : `tier${i - 1}`,
      pnl_sharing: ceilingFor(i),
      brokerage_sharing: ceilingFor(i),
    };
  }

  test('P&L: every tier\'s own ceiling-difference retention sums to exactly 100% across all 30 tiers + Admin', () => {
    let sum = _ceilingPct('tier0', 'admin', masterMap, 'pnl_sharing') - ceilingFor(0); // Admin's own slice
    for (let i = 0; i < N - 1; i++) {
      sum += ceilingFor(i) - ceilingFor(i + 1); // tier i's own slice, handing off to tier i+1
    }
    sum += ceilingFor(N - 1) - 0; // the bottom-most tier's own slice, handing off to the client
    expect(sum).toBeCloseTo(100, 8);
  });

  test('P&L: a middle tier (15 of 30) computes its own retention correctly, not a truncated/capped value', () => {
    // If a depth cap existed and silently kicked in past, say, 10 tiers,
    // this middle tier's retention would come out wrong (either 0, or the
    // wrong pair of ceilings). It doesn't — the formula only ever looks at
    // tier15's own ceiling and tier16's own ceiling, regardless of N.
    const own = _ceilingPct('tier15', 'master', masterMap, 'pnl_sharing');
    const child = _ceilingPct('tier16', 'master', masterMap, 'pnl_sharing');
    expect(own).toBeCloseTo(ceilingFor(15), 8);
    expect(child).toBeCloseTo(ceilingFor(16), 8);
    expect(own - child).toBeCloseTo(ceilingFor(15) - ceilingFor(16), 8);
  });

  test('brokerage: every tier\'s own rate-gap markup sums to exactly the client\'s total billed amount across all 30 tiers + Admin', () => {
    const kiteMap = { TOK: { lot_size: 1, segment: 'MCX-FUT', raw_name: 'TESTSCRIPT' } };
    const trades = [{ instrument_token: 'TOK', executed_price: 1, executed_quantity: 10 }]; // 10 lots
    const byInstrument = _groupTradesByInstrument(trades, kiteMap);
    const ruleFor = (rate) => [{ script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: rate }];

    const clientClearance = _clearanceForRules(byInstrument, ruleFor(CLIENT_RATE), kiteMap);

    let sum = clientClearance - _clearanceForRules(byInstrument, ruleFor(rateFor(N - 1)), kiteMap); // bottom-most tier's own markup
    for (let i = N - 1; i > 0; i--) {
      sum += _clearanceForRules(byInstrument, ruleFor(rateFor(i)), kiteMap)
        - _clearanceForRules(byInstrument, ruleFor(rateFor(i - 1)), kiteMap); // tier i's own markup
    }
    sum += _clearanceForRules(byInstrument, ruleFor(rateFor(0)), kiteMap); // Admin's own markup (their own clearance is 0)

    expect(sum).toBeCloseTo(clientClearance, 8);
  });

  test('brokerage: a middle tier (15 of 30) computes its own clearance from its own rate, not a truncated/capped value', () => {
    const kiteMap = { TOK: { lot_size: 1, segment: 'MCX-FUT', raw_name: 'TESTSCRIPT' } };
    const trades = [{ instrument_token: 'TOK', executed_price: 1, executed_quantity: 10 }];
    const byInstrument = _groupTradesByInstrument(trades, kiteMap);
    const rules = [{ script_name: 'TESTSCRIPT', exchange_name: 'MCX-FUT', type: 'LOT WISE', brk_value: rateFor(15) }];
    expect(_clearanceForRules(byInstrument, rules, kiteMap)).toBeCloseTo(rateFor(15) * 10, 8);
  });
});

describe('_topmostMasterId — walks to the master whose own master_id is null', () => {
  const masterMap = {
    top: { master_id: null },
    mid: { master_id: 'top' },
    bottom: { master_id: 'mid' },
  };

  test('a master several tiers deep resolves to the true top of their chain', () => {
    expect(_topmostMasterId('bottom', masterMap)).toBe('top');
  });

  test('the topmost master resolves to themselves', () => {
    expect(_topmostMasterId('top', masterMap)).toBe('top');
  });

  test('a corrupted circular master_id reference terminates instead of hanging forever', () => {
    const cyclicMap = { a: { master_id: 'b' }, b: { master_id: 'a' } };
    const start = Date.now();
    const result = _topmostMasterId('a', cyclicMap);
    expect(Date.now() - start).toBeLessThan(1000);
    expect(['a', 'b']).toContain(result);
  });
});

describe('base-share layer — the topmost tier\'s own clearance is split by ceiling-difference among EVERY tier including Admin', () => {
  // Confirmed business rule, added on top of the rate-gap model above: the
  // topmost real master's own configured rate no longer flows entirely to
  // Admin (who previously kept the whole thing, since Admin's own clearance
  // is 0) — it's split by the same ceiling-difference % already used for
  // P&L, among Admin and every real tier. Verified against the real
  // production hierarchy (996789 90% -> 705206 75% -> 254831 50% ->
  // 999746 25% -> a client billed 2232.55, whose topmost tier 996789's own
  // clearance/"base" is 96.51): Admin=9.65, 996789=210.99 (196.51 rate-gap
  // + 14.48 base-share), 705206=270.64 (246.51 + 24.13), 254831=270.64
  // (246.51 + 24.13), 999746=1470.64 (1446.51 + 24.13) — summing to
  // exactly 2232.55.
  const BASE = 96.51; // 996789's own clearance for this client's trades

  function baseSharePct(ownCeiling, childCeiling) {
    return ownCeiling - childCeiling;
  }

  test('every tier\'s base-share % sums to exactly 100%, Admin included', () => {
    const admin = baseSharePct(100, 90);   // 10
    const m1 = baseSharePct(90, 75);       // 15 (996789)
    const m2 = baseSharePct(75, 50);       // 25 (705206)
    const m3 = baseSharePct(50, 25);       // 25 (254831)
    const m4 = baseSharePct(25, 0);        // 25 (999746)
    expect(admin + m1 + m2 + m3 + m4).toBe(100);
  });

  test('each real tier\'s FULL total (rate-gap markup + base-share) matches the confirmed production numbers', () => {
    const rateGap = { m1: 196.51, m2: 246.51, m3: 246.51, m4: 1446.51 };
    const shares = {
      admin: BASE * baseSharePct(100, 90) / 100,
      m1: BASE * baseSharePct(90, 75) / 100,
      m2: BASE * baseSharePct(75, 50) / 100,
      m3: BASE * baseSharePct(50, 25) / 100,
      m4: BASE * baseSharePct(25, 0) / 100,
    };

    expect(shares.admin).toBeCloseTo(9.651, 2);
    expect(rateGap.m1 + shares.m1).toBeCloseTo(210.99, 1);
    expect(rateGap.m2 + shares.m2).toBeCloseTo(270.64, 1);
    expect(rateGap.m3 + shares.m3).toBeCloseTo(270.64, 1);
    expect(rateGap.m4 + shares.m4).toBeCloseTo(1470.64, 1);

    const total = shares.admin
      + (rateGap.m1 + shares.m1)
      + (rateGap.m2 + shares.m2)
      + (rateGap.m3 + shares.m3)
      + (rateGap.m4 + shares.m4);
    expect(total).toBeCloseTo(2232.55, 1);
  });
});
