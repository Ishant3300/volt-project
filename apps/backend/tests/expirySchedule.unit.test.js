const { planGroup, workingDaysBefore, expiryWeekMonday, istInstant } = require('../src/services/expirySchedule');
const { GROUPS } = require('../src/config/expiryRules');

const d = (s) => new Date(`${s}T00:00:00.000Z`);
const group = (key) => GROUPS.find((g) => g.key === key);
// Real MCX / NSE 2026 full-day trading holidays (marketCalendarService fallbacks).
const MCX = new Set(['2026-01-26', '2026-04-03', '2026-10-02', '2026-12-25']);
const NSE = new Set([
  '2026-01-15', '2026-01-26', '2026-02-15', '2026-03-03', '2026-03-21', '2026-03-26', '2026-03-31',
  '2026-04-03', '2026-04-14', '2026-05-01', '2026-05-28', '2026-06-26', '2026-08-15', '2026-09-14',
  '2026-10-02', '2026-10-20', '2026-11-08', '2026-11-10', '2026-11-24', '2026-12-25',
]);
const OPTS = { effectiveFrom: '2026-10-01', openTime: '08:00' };
const byKey = (actions) => Object.fromEntries(actions.map((a) => [a.key, a]));

describe('working-day helpers', () => {
  test('counts back over weekends and exchange holidays', () => {
    // Gold 5 Oct (Mon), 2 Oct MCX holiday: 1 Oct, 30, 29, 28 Sep, 25 Sep.
    expect(workingDaysBefore(d('2026-10-05'), 5, MCX)).toEqual(d('2026-09-25'));
    expect(workingDaysBefore(d('2026-10-05'), 6, MCX)).toEqual(d('2026-09-24'));
    expect(workingDaysBefore(d('2026-10-30'), 0, MCX)).toEqual(d('2026-10-30'));
  });

  test('expiry-week Monday falls back to the previous working day when Monday is a holiday', () => {
    expect(expiryWeekMonday(d('2026-10-27'), NSE)).toEqual(d('2026-10-26'));
    // Expiry Tue 22 Sep, Mon 21 Sep made a holiday → Fri 18 Sep.
    expect(expiryWeekMonday(d('2026-09-22'), new Set(['2026-09-21']))).toEqual(d('2026-09-18'));
    // Expiry moved to a Monday (Tue 24 Nov holiday) → open that same Monday.
    expect(expiryWeekMonday(d('2026-11-23'), NSE)).toEqual(d('2026-11-23'));
  });

  test('IST wall-clock times convert to the right instant', () => {
    expect(istInstant(d('2026-10-23'), '23:31').toISOString()).toBe('2026-10-23T18:01:00.000Z');
    expect(istInstant(d('2026-10-27'), '15:41').toISOString()).toBe('2026-10-27T10:11:00.000Z');
  });
});

describe('planGroup against the real upcoming contracts', () => {
  test('base metals: Oct contract opens next on 22 Oct and is cut on 23 Oct after the 11:30 PM close', () => {
    const contracts = ['COPPER', 'ZINC'].flatMap((name) =>
      ['2026-09-30', '2026-10-30', '2026-11-30'].map((e) => ({ name, expiry: d(e) })));
    const a = byKey(planGroup(group('MCX_BASE'), contracts, MCX, OPTS));
    // Sep contract: 22/23 Sep are before the rules take effect — nothing planned.
    expect(a['MCX_BASE|OPEN|2026-09-30']).toBeUndefined();
    expect(a['MCX_BASE|CUT|2026-09-30']).toBeUndefined();
    expect(a['MCX_BASE|OPEN|2026-10-30']).toMatchObject({ action_date: '2026-10-22', names: ['COPPER', 'ZINC'] });
    expect(a['MCX_BASE|OPEN|2026-10-30'].targets.map((t) => t.expiry)).toEqual([d('2026-11-30'), d('2026-11-30')]);
    expect(a['MCX_BASE|OPEN|2026-10-30'].execute_at.toISOString()).toBe('2026-10-22T02:30:00.000Z'); // 08:00 IST
    expect(a['MCX_BASE|CUT|2026-10-30']).toMatchObject({ action_date: '2026-10-23' });
    expect(a['MCX_BASE|CUT|2026-10-30'].execute_at.toISOString()).toBe('2026-10-23T18:01:00.000Z'); // 23:31 IST
    // The last known contract has nothing to open next, but is still cut.
    expect(a['MCX_BASE|OPEN|2026-11-30']).toBeUndefined();
    expect(a['MCX_BASE|CUT|2026-11-30']).toMatchObject({ action_date: '2026-11-23' });
  });

  test('precious metals: each name opens its own next contract', () => {
    const contracts = [
      { name: 'GOLD', expiry: d('2026-10-05') }, { name: 'GOLD', expiry: d('2026-12-04') },
      { name: 'GOLDM', expiry: d('2026-10-05') }, { name: 'GOLDM', expiry: d('2026-11-05') },
      { name: 'GOLDM', expiry: d('2026-12-04') },
    ];
    const a = byKey(planGroup(group('MCX_PRECIOUS'), contracts, MCX, OPTS));
    expect(a['MCX_PRECIOUS|CUT|2026-10-05']).toBeUndefined(); // 25 Sep — already past
    expect(a['MCX_PRECIOUS|OPEN|2026-11-05']).toMatchObject({ action_date: '2026-10-28', names: ['GOLDM'] });
    expect(a['MCX_PRECIOUS|CUT|2026-11-05']).toMatchObject({ action_date: '2026-10-29' });
    expect(a['MCX_PRECIOUS|OPEN|2026-12-04']).toBeUndefined(); // no known next contract yet
    expect(a['MCX_PRECIOUS|CUT|2026-12-04']).toMatchObject({ action_date: '2026-11-27' });
  });

  test('crude opens 2 and is cut 1 working day before; natural gas opens and is cut the same day', () => {
    const crude = byKey(planGroup(group('MCX_CRUDE'), [
      { name: 'CRUDEOIL', expiry: d('2026-10-19') }, { name: 'CRUDEOIL', expiry: d('2026-11-19') },
    ], MCX, OPTS));
    expect(crude['MCX_CRUDE|OPEN|2026-10-19'].action_date).toBe('2026-10-15');
    expect(crude['MCX_CRUDE|CUT|2026-10-19'].action_date).toBe('2026-10-16');

    const ng = byKey(planGroup(group('MCX_NG'), [
      { name: 'NATURALGAS', expiry: d('2026-10-27') }, { name: 'NATURALGAS', expiry: d('2026-11-24') },
    ], MCX, OPTS));
    expect(ng['MCX_NG|OPEN|2026-10-27'].action_date).toBe('2026-10-26');
    expect(ng['MCX_NG|CUT|2026-10-27'].action_date).toBe('2026-10-26');
    expect(ng['MCX_NG|OPEN|2026-10-27'].execute_at < ng['MCX_NG|CUT|2026-10-27'].execute_at).toBe(true);
  });

  test('NSE futures: open on Monday of expiry week, cut on expiry day after the 3:40 PM close', () => {
    const a = byKey(planGroup(group('NSE_FUT'), ['2026-09-29', '2026-10-27', '2026-11-23'].map((e) => ({ name: 'NIFTY', expiry: d(e) })), NSE, OPTS));
    expect(a['NSE_FUT|OPEN|2026-09-29']).toBeUndefined(); // this week stays manual
    expect(a['NSE_FUT|CUT|2026-09-29']).toBeUndefined();
    expect(a['NSE_FUT|OPEN|2026-10-27'].action_date).toBe('2026-10-26');
    expect(a['NSE_FUT|CUT|2026-10-27'].action_date).toBe('2026-10-27');
    expect(a['NSE_FUT|CUT|2026-10-27'].execute_at.toISOString()).toBe('2026-10-27T10:11:00.000Z'); // 15:41 IST
  });

  test('GLOBAL futures open and cut on expiry day; GIFT NIFTY is cut only', () => {
    const g = byKey(planGroup(group('GLOBAL_FUT'), [
      { name: 'S&P 500', expiry: d('2026-12-18') }, { name: 'S&P 500', expiry: d('2027-03-19') },
    ], null, OPTS));
    expect(g['GLOBAL_FUT|OPEN|2026-12-18'].action_date).toBe('2026-12-18');
    expect(g['GLOBAL_FUT|CUT|2026-12-18'].action_date).toBe('2026-12-18');

    const gift = planGroup(group('GIFT_NIFTY'), [{ name: 'GIFT NIFTY', expiry: d('2026-10-27') }], NSE, OPTS);
    expect(gift.map((x) => x.kind)).toEqual(['CUT']);
    expect(gift[0].action_date).toBe('2026-10-27');
    expect(gift[0].execute_at.toISOString()).toBe('2026-10-27T10:11:00.000Z'); // 15:41 IST, same as NSE futures
  });
});
