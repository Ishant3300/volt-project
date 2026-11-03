// Equity waterfall rules (src/cashEq/rules.js) — two rate sets: approved (MTF) and non-approved.

const rules = require('../src/cashEq/rules');

const L = 1e5;
const CR = 1e7;
const pct = (intraday, carry, extra = {}) => ({ mode: 'PCT', intraday, carry, min_rate: 0, higher_side_only: false, ...extra });
const master = (over = {}) => ({
  username: 'EQHARRY', per_script_limit: 25 * L, total_limit: 2 * CR,
  brokerage_mtf: pct(0.02, 0.06), brokerage_non: pct(0.03, 0.1),
  interest_mtf_pct: 12, interest_non_pct: 15,
  pnl_share: 40, brokerage_share: 50, interest_share: 50, ...over,
});
const child = (over = {}) => rules.normalise({
  per_script_limit: 20 * L, total_limit: 1 * CR,
  brokerage_mtf: pct(0.03, 0.1), brokerage_non: pct(0.04, 0.15),
  interest_mtf_pct: 18, interest_non_pct: 21, ...over,
}, { master: false });
const sub = (over = {}) => rules.normalise({
  per_script_limit: 20 * L, total_limit: 1 * CR,
  brokerage_mtf: pct(0.025, 0.08), brokerage_non: pct(0.035, 0.12),
  interest_mtf_pct: 15, interest_non_pct: 18,
  pnl_share: 30, brokerage_share: 40, interest_share: 40, ...over,
}, { master: true });
const check = (c, p = master(), m = false) => rules.checkAgainstParent(c, p, { master: m });

describe('limits: never above the parent', () => {
  test('within the parent: ok', () => {
    expect(check(child())).toEqual([]);
  });
  test('per-script 30 L under a 25 L master: refused', () => {
    expect(check(child({ per_script_limit: 30 * L }))).toEqual(['Per-script limit can\'t be above 25 L (EQHARRY)']);
  });
  test('total 3 Cr under a 2 Cr master: refused', () => {
    expect(check(child({ total_limit: 3 * CR }))[0]).toMatch(/Total limit can't be above 2 Cr/);
  });
  test('equal to the parent: ok', () => {
    expect(check(child({ per_script_limit: 25 * L, total_limit: 2 * CR }))).toEqual([]);
  });
  test('per-script above own total: refused', () => {
    expect(rules.checkBasics(child({ per_script_limit: 25 * L, total_limit: 20 * L }), { master: false })[0]).toMatch(/can't be above the total limit/);
  });
});

describe('brokerage and interest of each set: never below the parent', () => {
  test('approved intraday below the master: refused', () => {
    expect(check(child({ brokerage_mtf: pct(0.01, 0.1) }))).toEqual(['Intraday brokerage for approved scripts can\'t be below 0.02 % (EQHARRY)']);
  });
  test('non-approved carry below the master (approved is fine): refused', () => {
    expect(check(child({ brokerage_non: pct(0.04, 0.09) }))).toEqual(['Carry forward brokerage for non-approved scripts can\'t be below 0.1 % (EQHARRY)']);
  });
  test('the non-approved floor is its own: approved rate above it is not enough', () => {
    // 0.025 % is above the master's approved floor (0.02 %) but below its non-approved floor (0.03 %).
    expect(check(child({ brokerage_non: pct(0.025, 0.15) }))[0]).toMatch(/Intraday brokerage for non-approved scripts can't be below 0.03/);
  });
  test('different mode from the master: refused', () => {
    expect(check(child({ brokerage_mtf: { mode: 'FIX', intraday: 1, carry: 1 } }))[0]).toMatch(/approved scripts must be PCT/);
  });
  test('higher-side-only when the master charges both sides: refused', () => {
    expect(check(child({ brokerage_non: pct(0.04, 0.15, { higher_side_only: true }) }))[0]).toMatch(/"Higher side only" for non-approved scripts/);
  });
  test('interest below the master, per set: refused', () => {
    expect(check(child({ interest_mtf_pct: 10 }))).toEqual(['Interest for approved scripts can\'t be below 12 % (EQHARRY)']);
    expect(check(child({ interest_non_pct: 14 }))).toEqual(['Interest for non-approved scripts can\'t be below 15 % (EQHARRY)']);
  });
  test('minimum per share below the master: refused', () => {
    const p = master({ brokerage_mtf: pct(0.02, 0.06, { min_rate: 0.05 }) });
    expect(check(child(), p)[0]).toMatch(/Minimum brokerage for approved scripts can't be below 0.05/);
  });
  test('missing interest for a set: refused', () => {
    expect(rules.checkBasics(rules.normalise({ ...child(), interest_non_pct: undefined }, { master: false }), { master: false }))
      .toEqual(['Interest for non-approved scripts must be between 0 and 100 %']);
  });
});

describe('sub-masters: sharing never above the parent', () => {
  test('within the parent: ok', () => {
    expect(check(sub(), master(), true)).toEqual([]);
  });
  test('P&L share 45 % under 40 %: refused', () => {
    expect(check(sub({ pnl_share: 45 }), master(), true)).toEqual(['pnl share can\'t be above 40 % (EQHARRY)']);
  });
  test('top level (under admin): only the basic checks', () => {
    expect(check(sub({ per_script_limit: 50 * L, total_limit: 10 * CR, interest_mtf_pct: 1, pnl_share: 100 }), null, true)).toEqual([]);
    expect(check(sub({ pnl_share: 101 }), null, true)[0]).toMatch(/between 0 and 100/);
  });
});

describe('changing a master: not below what it already gave out', () => {
  test('lowering the per-script cap under an existing client: refused, names the client', () => {
    expect(rules.checkAgainstChildren({ ...master(), per_script_limit: 15 * L }, [{ ...child(), username: 'EQ100001' }]))
      .toEqual(['EQ100001: Per-script limit can\'t be above 15 L']);
  });
  test('raising the non-approved interest above a client\'s rate: refused', () => {
    const e = rules.checkAgainstChildren({ ...master(), interest_non_pct: 22 }, [{ ...child(), username: 'EQ100001' }]);
    expect(e[0]).toMatch(/^EQ100001: Interest for non-approved scripts can't be below 22 %/);
  });
  test('lowering a share under a sub-master: refused', () => {
    expect(rules.checkAgainstChildren({ ...master(), pnl_share: 20 }, [{ ...sub(), username: 'EQSUB1' }])[0]).toMatch(/^EQSUB1: pnl share can't be above 20 %/);
  });
  test('a change that still covers everyone: ok', () => {
    expect(rules.checkAgainstChildren({ ...master(), per_script_limit: 30 * L }, [{ ...child(), username: 'EQ1' }, { ...sub(), username: 'EQ2' }])).toEqual([]);
  });
});

describe('engine mapping', () => {
  const c = { _id: 'abc', ...child({ brokerage_mtf: pct(0.03, 0.1, { min_rate: 0.05 }), brokerage_non: { mode: 'PCT', intraday: 0.04, carry: 0.15 } }), opening_balance: 10 * L, opening_type: 'Cr' };
  test('each set → its own Trade Terminal slab', () => {
    expect(rules.toSlab(c, 'mtf')).toMatchObject({ clientCode: 'abc', segment: 'NSEEQ', mode: 'PCT', intraPct: 0.03, delPct: 0.1, minRate: 0.05 });
    expect(rules.toSlab(c, 'non')).toMatchObject({ intraPct: 0.04, delPct: 0.15, minRate: 0 });
    expect(() => rules.toSlab(c, 'x')).toThrow();
  });
  test('account carries both interest rates', () => {
    expect(rules.toAccount(c)).toEqual({ code: 'abc', openingBalance: 10 * L, openingType: 'Cr', interestPct: 18, interestNonPct: 21 });
  });
  test('FIX set → per-share fixed brokerage', () => {
    expect(rules.toSlab({ _id: 'x', brokerage_non: { mode: 'FIX', intraday: 0.1, carry: 0.5 } }, 'non')).toMatchObject({ mode: 'FIX', fixIntra: 0.1, fixDel: 0.5, intraPct: 0 });
  });
  test('usernames start with EQ', () => {
    expect(rules.USERNAME_RE.test('EQ123456')).toBe(true);
    expect(rules.USERNAME_RE.test('123456')).toBe(false);
    expect(rules.USERNAME_RE.test('harry')).toBe(false);
  });
});
