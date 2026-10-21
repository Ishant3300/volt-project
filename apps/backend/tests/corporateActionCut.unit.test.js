'use strict';

// Planning of corporate-action cuts (corporateActionCutService.js): which NSE
// rows become a cut, and on which day / time. Pure — no DB, no network.

const { _private: { kindOf, parseNseDate, planCuts, bannerFor, CLOSE_TIME } } = require('../src/services/corporateActionCutService');

const d = (s) => new Date(`${s}T00:00:00.000Z`);
const ctx = (today, holidays = []) => ({ fnoNames: new Set(['RELIANCE', 'TCS', 'INFY', 'NIFTY']), holidays: new Set(holidays), today: d(today) });

describe('kindOf', () => {
  test.each([
    ['Face Value Split (Sub-Division) - From Rs 10/- Per Share To Rs 2/- Per Share', 'split'],
    ['Sub-Division', 'split'],
    ['Bonus 1:1', 'bonus'],
    ['Rights 1:5 @ Premium Rs 100/-', 'rights'],
    ['Interim Dividend - Rs 5 Per Share', 'dividend'],
    ['Annual General Meeting/Dividend - Rs 10 Per Share', 'dividend'],
    ['Annual General Meeting', null],
    ['Buy Back', null],
    ['', null],
  ])('%s → %s', (subject, kind) => expect(kindOf(subject)).toBe(kind));
});

describe('parseNseDate', () => {
  test('reads NSE dates', () => {
    expect(parseNseDate('28-Oct-2026')).toBe('2026-10-28');
    expect(parseNseDate('5-Jan-2027')).toBe('2027-01-05');
  });
  test('rejects anything else', () => {
    expect(parseNseDate('-')).toBeNull();
    expect(parseNseDate('2026-10-28')).toBeNull();
    expect(parseNseDate(undefined)).toBeNull();
  });
});

describe('planCuts', () => {
  test('a bonus is cut the trading day before its ex-date, just after the NSE close', () => {
    // Ex-date Wednesday 28 Oct → cut Tuesday 27 Oct.
    const [cut, ...rest] = planCuts([{ symbol: 'RELIANCE', subject: 'Bonus 1:1', exDate: '28-Oct-2026' }], ctx('2026-10-19'));
    expect(rest).toEqual([]);
    expect(cut).toMatchObject({ key: 'CORP_ACTION|RELIANCE|2026-10-28', symbol: 'RELIANCE', kind: 'bonus', label: 'RELIANCE bonus', ex_date: '2026-10-28', action_date: '2026-10-27' });
    const [h, m] = CLOSE_TIME.split(':').map(Number);
    // One minute after the close, IST (UTC+5:30).
    expect(cut.execute_at).toEqual(new Date(Date.UTC(2026, 9, 27, h, m + 1) - 330 * 60_000));
  });

  test('a Monday ex-date is cut on the Friday before, skipping holidays', () => {
    expect(planCuts([{ symbol: 'TCS', subject: 'Bonus 1:1', exDate: '26-Oct-2026' }], ctx('2026-10-19'))[0].action_date).toBe('2026-10-23');
    // Friday a holiday → Thursday.
    expect(planCuts([{ symbol: 'TCS', subject: 'Bonus 1:1', exDate: '26-Oct-2026' }], ctx('2026-10-19', ['2026-10-23']))[0].action_date).toBe('2026-10-22');
  });

  test('a dividend is cut like the rest (ANGELONE, 20 Oct 2026)', () => {
    const [cut] = planCuts([{ symbol: 'INFY', subject: 'Interim Dividend - Rs 1.40 Per Share', exDate: '22-Oct-2026' }], ctx('2026-10-20'));
    expect(cut).toMatchObject({ kind: 'dividend', label: 'INFY dividend', ex_date: '2026-10-22', action_date: '2026-10-21' });
  });

  test('AGMs, non-F&O stocks and indices are not cut', () => {
    expect(planCuts([
      { symbol: 'INFY', subject: 'Annual General Meeting', exDate: '28-Oct-2026' },
      { symbol: 'SMALLCO', subject: 'Bonus 1:1', exDate: '28-Oct-2026' },
      { symbol: 'NIFTY', subject: 'Bonus 1:1', exDate: '28-Oct-2026' },
    ], ctx('2026-10-19'))).toEqual([]);
  });

  test('split, bonus and dividend on the same ex-date make one cut', () => {
    const cuts = planCuts([
      { symbol: 'RELIANCE', subject: 'Bonus 1:1', exDate: '28-Oct-2026' },
      { symbol: 'RELIANCE', subject: 'Face Value Split (Sub-Division) - From Rs 10/- To Rs 5/-', exDate: '28-Oct-2026' },
      { symbol: 'RELIANCE', subject: 'Dividend - Rs 2 Per Share', exDate: '28-Oct-2026' },
    ], ctx('2026-10-19'));
    expect(cuts).toHaveLength(1);
    expect(cuts[0]).toMatchObject({ kind: 'split+bonus+dividend', label: 'RELIANCE split + bonus + dividend' });
  });

  test('a cut whose day has passed is not planned; today still is', () => {
    const rows = [{ symbol: 'TCS', subject: 'Rights 1:5', exDate: '20-Oct-2026' }];
    expect(planCuts(rows, ctx('2026-10-19')).map((c) => c.action_date)).toEqual(['2026-10-19']);
    expect(planCuts(rows, ctx('2026-10-20'))).toEqual([]);
  });
});

describe('bannerFor (announcement bar notice)', () => {
  const base = {
    key: 'CORP_ACTION|ANGELONE|2026-10-22', group_key: 'CORP_ACTION', names: ['ANGELONE'], action_date: '2026-10-21', close_time: '15:40',
    execute_at: new Date('2026-10-21T10:11:00Z'),
    corp_action: { symbol: 'ANGELONE', kind: 'dividend', subject: 'Interim Dividend - Rs 1.40 Per Share', ex_date: '2026-10-22' },
  };
  test('confirmed: says the positions will be closed, until the cut runs', () => {
    expect(bannerFor({ ...base, status: 'confirmed' })).toEqual({
      message: 'ANGELONE — Interim Dividend - Rs 1.40 Per Share, ex-date 22 Oct: all open ANGELONE positions (futures & options) will be closed on 21 Oct at the 3:40 PM closing rate.',
      expiresAt: new Date('2026-10-21T10:11:00Z'),
    });
  });
  test('unconfirmed: information only, until the ex-date starts', () => {
    expect(bannerFor({ ...base, status: 'planned' })).toEqual({
      message: 'ANGELONE — Interim Dividend - Rs 1.40 Per Share, ex-date 22 Oct.',
      expiresAt: new Date('2026-10-21T18:30:00Z'),
    });
  });
  test('paused, done, failed, obsolete: no notice', () => {
    for (const status of ['paused', 'done', 'failed', 'obsolete']) expect(bannerFor({ ...base, status })).toBeNull();
  });
});
