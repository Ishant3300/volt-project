// Equity waterfall rules (src/cashEq/rules.js).

const rules = require('../src/cashEq/rules');

const L = 1e5;
const CR = 1e7;
const master = (over = {}) => ({
  username: 'EQHARRY', per_script_limit: 25 * L, total_limit: 2 * CR, interest_pct: 12,
  brokerage: { mode: 'PCT', intraday: 0.02, carry: 0.06, min_rate: 0, higher_side_only: false },
  pnl_share: 40, brokerage_share: 50, interest_share: 50, ...over,
});
const child = (over = {}) => rules.normalise({
  per_script_limit: 20 * L, total_limit: 1 * CR, interest_pct: 18,
  brokerage: { mode: 'PCT', intraday: 0.03, carry: 0.1 }, ...over,
}, { master: false });
const sub = (over = {}) => rules.normalise({
  per_script_limit: 20 * L, total_limit: 1 * CR, interest_pct: 15,
  brokerage: { mode: 'PCT', intraday: 0.025, carry: 0.08 }, pnl_share: 30, brokerage_share: 40, interest_share: 40, ...over,
}, { master: true });

describe('limits: never above the parent', () => {
  test('within the parent: ok', () => {
    expect(rules.checkAgainstParent(child(), master(), { master: false })).toEqual([]);
  });
  test('per-script 30 L under a 25 L master: refused', () => {
    const e = rules.checkAgainstParent(child({ per_script_limit: 30 * L }), master(), { master: false });
    expect(e).toEqual(['Per-script limit can\'t be above 25 L (EQHARRY)']);
  });
  test('total 3 Cr under a 2 Cr master: refused', () => {
    const e = rules.checkAgainstParent(child({ total_limit: 3 * CR }), master(), { master: false });
    expect(e[0]).toMatch(/Total limit can't be above 2 Cr/);
  });
  test('equal to the parent: ok', () => {
    expect(rules.checkAgainstParent(child({ per_script_limit: 25 * L, total_limit: 2 * CR }), master(), { master: false })).toEqual([]);
  });
  test('per-script above own total: refused', () => {
    expect(rules.checkBasics(child({ per_script_limit: 25 * L, total_limit: 20 * L }), { master: false })[0]).toMatch(/can't be above the total limit/);
  });
});

describe('brokerage and interest: never below the parent', () => {
  test('intraday below the master: refused', () => {
    const e = rules.checkAgainstParent(child({ brokerage: { mode: 'PCT', intraday: 0.01, carry: 0.1 } }), master(), { master: false });
    expect(e).toEqual(['Intraday brokerage can\'t be below 0.02 % (EQHARRY)']);
  });
  test('carry forward below the master: refused', () => {
    const e = rules.checkAgainstParent(child({ brokerage: { mode: 'PCT', intraday: 0.03, carry: 0.05 } }), master(), { master: false });
    expect(e[0]).toMatch(/Carry forward brokerage can't be below 0.06/);
  });
  test('different mode from the master: refused', () => {
    const e = rules.checkAgainstParent(child({ brokerage: { mode: 'FIX', intraday: 1, carry: 1 } }), master(), { master: false });
    expect(e[0]).toMatch(/must be PCT/);
  });
  test('higher-side-only when the master charges both sides: refused', () => {
    const e = rules.checkAgainstParent(child({ brokerage: { mode: 'PCT', intraday: 0.03, carry: 0.1, higher_side_only: true } }), master(), { master: false });
    expect(e[0]).toMatch(/Higher side only/);
  });
  test('interest below the master: refused', () => {
    const e = rules.checkAgainstParent(child({ interest_pct: 10 }), master(), { master: false });
    expect(e).toEqual(['Interest can\'t be below 12 % (EQHARRY)']);
  });
  test('minimum per share below the master: refused', () => {
    const e = rules.checkAgainstParent(child({ brokerage: { mode: 'PCT', intraday: 0.03, carry: 0.1, min_rate: 0 } }), master({ brokerage: { mode: 'PCT', intraday: 0.02, carry: 0.06, min_rate: 0.05 } }), { master: false });
    expect(e[0]).toMatch(/Minimum brokerage can't be below 0.05/);
  });
});

describe('sub-masters: sharing never above the parent', () => {
  test('within the parent: ok', () => {
    expect(rules.checkAgainstParent(sub(), master(), { master: true })).toEqual([]);
  });
  test('P&L share 45 % under 40 %: refused', () => {
    const e = rules.checkAgainstParent(sub({ pnl_share: 45 }), master(), { master: true });
    expect(e).toEqual(['pnl share can\'t be above 40 % (EQHARRY)']);
  });
  test('top level (under admin): only the basic checks', () => {
    expect(rules.checkAgainstParent(sub({ per_script_limit: 50 * L, total_limit: 10 * CR, interest_pct: 1, pnl_share: 100 }), null, { master: true })).toEqual([]);
    expect(rules.checkAgainstParent(sub({ pnl_share: 101 }), null, { master: true })[0]).toMatch(/between 0 and 100/);
  });
});

describe('changing a master: not below what it already gave out', () => {
  test('lowering the per-script cap under an existing client: refused, names the client', () => {
    const e = rules.checkAgainstChildren(
      { ...master(), per_script_limit: 15 * L },
      [{ ...child(), username: 'EQ100001' }],
    );
    expect(e).toEqual(['EQ100001: Per-script limit can\'t be above 15 L']);
  });
  test('raising interest above a client\'s rate: refused', () => {
    const e = rules.checkAgainstChildren({ ...master(), interest_pct: 20 }, [{ ...child(), username: 'EQ100001' }]);
    expect(e[0]).toMatch(/^EQ100001: Interest can't be below 20 %/);
  });
  test('lowering a share under a sub-master: refused', () => {
    const e = rules.checkAgainstChildren({ ...master(), pnl_share: 20 }, [{ ...sub(), username: 'EQSUB1' }]);
    expect(e[0]).toMatch(/^EQSUB1: pnl share can't be above 20 %/);
  });
  test('a change that still covers everyone: ok', () => {
    expect(rules.checkAgainstChildren({ ...master(), per_script_limit: 30 * L }, [{ ...child(), username: 'EQ1' }, { ...sub(), username: 'EQ2' }])).toEqual([]);
  });
});

describe('engine mapping', () => {
  test('PCT client → Trade Terminal slab and account', () => {
    const c = { _id: 'abc', ...child({ brokerage: { mode: 'PCT', intraday: 0.03, carry: 0.1, min_rate: 0.05 } }), opening_balance: 10 * L, opening_type: 'Cr' };
    expect(rules.toSlab(c)).toMatchObject({ clientCode: 'abc', segment: 'NSEEQ', mode: 'PCT', intraPct: 0.03, delPct: 0.1, minRate: 0.05, fixDel: 0, fixIntra: 0 });
    expect(rules.toAccount(c)).toEqual({ code: 'abc', openingBalance: 10 * L, openingType: 'Cr', interestPct: 18 });
  });
  test('FIX client → per-share fixed brokerage', () => {
    const c = { _id: 'x', brokerage: { mode: 'FIX', intraday: 0.1, carry: 0.5 } };
    expect(rules.toSlab(c)).toMatchObject({ mode: 'FIX', fixIntra: 0.1, fixDel: 0.5, intraPct: 0, delPct: 0 });
  });
  test('usernames start with EQ', () => {
    expect(rules.USERNAME_RE.test('EQ123456')).toBe(true);
    expect(rules.USERNAME_RE.test('123456')).toBe(false);
    expect(rules.USERNAME_RE.test('harry')).toBe(false);
  });
});
