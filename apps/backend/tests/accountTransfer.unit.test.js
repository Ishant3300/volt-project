'use strict';

// Account transfer (services/accountTransferService.js) — the pure parts:
// the money split the preview shows (must match the Ledger's own formulas,
// weeklyAdminController), segment / rate checks, and which rows move.

const { _private: x } = require('../src/services/accountTransferService');

const m = (id, username, pnl, brk, parent = null, extra = {}) => ({ _id: id, username, name: username, pnl_sharing: pnl, brokerage_sharing: brk, master_id: parent, ...extra });

describe('brokerageSplit — same numbers as the live Ledger', () => {
  test('RITESH (0/0, rate 2) under BDS82 (18/18, rate 1) under harry (100/100): client pays 6', () => {
    const split = x.brokerageSplit(6, [{ rate: 2, sharing: 0 }, { rate: 1, sharing: 18 }, { rate: 1, sharing: 100 }]);
    expect(split.map((s) => s.keep)).toEqual([4, 1.18, 0.82, 0]);
    expect(split[3].admin).toBe(true);
    // Ledger, previous week 2-7 Nov: BDS82's brokerage from RITESH = 1.18 × (BDS82 rate-1 volume 1,04,115.93)
    expect(Math.round(1.18 * 104115.93 * 100) / 100).toBe(122856.80);
  });

  test('PIYUSH (0/0, rate 1.5) under BDS82: BDS82 keeps 0.68 per unit (= 32,676.91 last week)', () => {
    const split = x.brokerageSplit(6, [{ rate: 1.5, sharing: 0 }, { rate: 1, sharing: 18 }, { rate: 1, sharing: 100 }]);
    expect(split[1].keep).toBe(0.68);
    expect(Math.round(0.68 * 48054.28 * 100) / 100).toBe(32676.91);
  });

  test('the 4-tier example in weeklyAdminController (gm44 viewing gm55: 639.23)', () => {
    // gm55 own rate 1.25 (clearance 3995.175), ceiling 60; gm44 own rate 1 (clearance 3196.14), ceiling 70
    const split = x.brokerageSplit(2, [{ rate: 1.25, sharing: 60 }, { rate: 1, sharing: 70 }]);
    expect(Math.round(split[1].keep * 3196.14 * 100) / 100).toBe(639.23);
  });

  test('the levels always add up to what the client pays', () => {
    const cases = [
      [6, [{ rate: 2, sharing: 0 }, { rate: 1, sharing: 18 }, { rate: 1, sharing: 100 }]],
      [25, [{ rate: 20, sharing: 35 }, { rate: 10, sharing: 60 }]],
      [3, [{ rate: 3, sharing: 50 }]],
      [1, [{ rate: 2, sharing: 0 }, { rate: 1, sharing: 18 }]], // client below his master: master's keep goes negative
    ];
    for (const [c, levels] of cases) {
      const sum = x.brokerageSplit(c, levels).reduce((s, l) => s + l.keep, 0);
      expect(Math.abs(sum - c)).toBeLessThan(1e-9);
    }
    expect(x.brokerageSplit(1, [{ rate: 2, sharing: 0 }, { rate: 1, sharing: 18 }])[0].keep).toBe(-1);
  });

  test('no master in the chain: admin keeps everything', () => {
    expect(x.brokerageSplit(5, [])).toEqual([{ admin: true, keep: 5 }]);
  });
});

describe('pnlSplit — ceiling model', () => {
  test('RITESH 0 < BDS82 18 < harry 100: 0 / 18 / 82 / admin 0', () => {
    const chain = [m('r', 'RITESH', 0, 0), m('b', 'BDS82', 18, 18), m('h', 'harry', 100, 100)];
    expect(x.pnlSplit(chain).map((l) => l.pct)).toEqual([0, 18, 82, 0]);
  });
  test('a top master below 100: admin keeps the rest; always sums to 100', () => {
    const split = x.pnlSplit([m('a', 'A', 25, 0), m('b', 'B', 50, 0), m('c', 'C', 75, 0)]);
    expect(split.map((l) => l.pct)).toEqual([25, 25, 25, 25]);
    expect(split[3].admin).toBe(true);
  });
});

describe('chainOf', () => {
  test('direct master up to the top, cycle-guarded', () => {
    const byId = new Map([['r', m('r', 'RITESH', 0, 0, 'b')], ['b', m('b', 'BDS82', 18, 18, 'h')], ['h', m('h', 'harry', 100, 100, null)]]);
    expect(x.chainOf('r', byId).map((c) => c.username)).toEqual(['RITESH', 'BDS82', 'harry']);
    const loop = new Map([['a', m('a', 'A', 0, 0, 'b')], ['b', m('b', 'B', 0, 0, 'a')]]);
    expect(x.chainOf('a', loop).map((c) => c.username)).toEqual(['A', 'B']);
    expect(x.chainOf(null, byId)).toEqual([]);
  });
});

describe('segments', () => {
  const user = { exchanges_allowed: [
    { exchange_name: 'NFO-FUT', turnover: true, lot: false },
    { exchange_name: 'INDICES', turnover: true, lot: false },
    { exchange_name: 'MCX-FUT', turnover: false, lot: false }, // saved but not ticked
  ] };
  test('only ticked segments count', () => {
    expect(x.clientSegments(user)).toEqual(['NFO-FUT', 'INDICES']);
  });
  test('GLOBAL and INDICES are the same permission', () => {
    expect(x.segmentsNotAllowed(user, { exchanges_allowed: ['NFO-FUT', 'GLOBAL'] })).toEqual([]);
    expect(x.segmentsNotAllowed(user, { exchanges_allowed: ['NFO-FUT'] })).toEqual(['INDICES']);
    expect(x.segmentsNotAllowed(user, { exchanges_allowed: [] })).toEqual(['NFO-FUT', 'INDICES']);
  });
});

describe('usual rate / low rates (the KARAN case)', () => {
  const row = (id, ex, script, v, type = 'TURNOVER WISE') => ({ _id: id, exchange_name: ex, script_name: script, type, brk_value: v, deleted_at: null });
  const client = [
    row('c1', 'NFO-FUT', 'ABC', 6), row('c2', 'NFO-FUT', 'DEF', 6), row('c3', 'NFO-FUT', 'EXIDEIND', 1),
    row('c4', 'NFO-FUT', 'OLDNAME', 1), row('c5', 'INDICES', 'GIFTNIFTY', 6), row('c6', 'MCX-FUT', 'GOLD', 50, 'LOT WISE'),
  ];
  const master = [
    row('m1', 'NFO-FUT', 'ABC', 2), row('m2', 'NFO-FUT', 'DEF', 2), row('m3', 'NFO-FUT', 'EXIDEIND', 2),
    row('m4', 'NFO-FUT', 'OLDNAME', 2), row('m5', 'INDICES', 'GIFTNIFTY', 2), row('m6', 'MCX-FUT', 'GOLD', 50, 'LOT WISE'),
  ];
  test('usual rate = most common, ties to the higher', () => {
    expect(x.usualRate(client, 'NFO-FUT', 'TURNOVER WISE')).toBe(6);
    expect(x.usualRate([row('a', 'X', 's', 1), row('b', 'X', 't', 3)], 'X', 'TURNOVER WISE')).toBe(3);
    expect(x.usualRate(client, 'NFO-OPT', 'TURNOVER WISE')).toBeNull();
    expect(x.usualType(client, 'MCX-FUT')).toBe('LOT WISE');
  });
  test('below the new master on a tradable script → raise to his usual rate; equal is fine; dead names skipped', () => {
    const tradable = (name) => name !== 'OLDNAME';
    const low = x.lowRates(client, master, tradable);
    expect(low).toEqual([{ brokerage_id: 'c3', exchange_name: 'NFO-FUT', script_name: 'EXIDEIND', type: 'TURNOVER WISE', client_value: 1, master_value: 2, raise_to: 6 }]);
  });
  test('raise_to never below the master rate', () => {
    const c = [row('a', 'NFO-FUT', 'ABC', 1), row('b', 'NFO-FUT', 'DEF', 1)];
    const low = x.lowRates(c, [row('m', 'NFO-FUT', 'ABC', 3)]);
    expect(low[0].raise_to).toBe(3);
  });
  test('deleted rows are ignored on both sides', () => {
    const c = [{ ...row('a', 'NFO-FUT', 'ABC', 1), deleted_at: new Date() }];
    expect(x.lowRates(c, [row('m', 'NFO-FUT', 'ABC', 3)])).toEqual([]);
    expect(x.lowRates([row('a', 'NFO-FUT', 'ABC', 1)], [{ ...row('m', 'NFO-FUT', 'ABC', 3), deleted_at: new Date() }])).toEqual([]);
  });
});

describe('currentPeriodFilter — exactly the rows the next settlement reads', () => {
  test('not deleted; completed/pending any date; other statuses only since the last cutoff', () => {
    const cutoff = new Date('2026-11-06T22:16:00Z');
    expect(x.currentPeriodFilter(['u'], cutoff)).toEqual({
      user_id: { $in: ['u'] },
      deleted_at: null,
      $or: [{ status: { $in: ['completed', 'pending'] } }, { createdAt: { $gte: cutoff } }],
    });
    expect(x.currentPeriodFilter(['u'], null).$or).toEqual([{ status: { $in: ['completed', 'pending'] } }]);
  });
});

describe('previewToken', () => {
  test('stable for the same state, different when anything changes', () => {
    const a = { to: 'm', clients: [{ id: 'u', rows: [['t1', 'pending', 'b']] }] };
    expect(x.previewToken(a)).toBe(x.previewToken(JSON.parse(JSON.stringify(a))));
    expect(x.previewToken(a)).not.toBe(x.previewToken({ to: 'm', clients: [{ id: 'u', rows: [['t1', 'completed', 'b']] }] }));
  });
});
