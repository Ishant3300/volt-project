'use strict';

// Sunday 8 Nov 2026 Diwali Muhurat trading (utils/specialSessions.js) and the
// MCX close following US daylight saving (utils/mcxHours.js).

const s = require('../src/utils/specialSessions');
const { mcxCloseOn } = require('../src/utils/mcxHours');
const { isPriceWeekendInIndia, isWeekendInIndia } = require('../src/utils/settlementDates');
const { GROUPS } = require('../src/config/expiryRules');
const { closeTimeOn } = require('../src/services/expirySchedule');

const at = (iso) => new Date(iso);
const iso = (d) => (d ? d.toISOString() : d);
const S = '2026-11-07T18:30:00.000Z'; // Sun 8 Nov 00:00 IST

describe('MCX close follows US daylight saving', () => {
  test.each([
    ['2026-10-30', '23:30'], // Friday before the US change
    ['2026-11-02', '23:55'], // first Monday after it
    ['2026-11-18', '23:55'],
    ['2027-03-12', '23:55'], // last Friday of US winter time
    ['2027-03-15', '23:30'], // Monday after US summer time starts
  ])('%s closes at %s', (ymd, close) => expect(mcxCloseOn(ymd)).toBe(close));

  test('MCX and COMEX cuts run after that day\'s MCX close; NSE, GIFT and GLOBAL keep theirs', () => {
    const day = (ymd) => new Date(`${ymd}T00:00:00Z`);
    const group = (key) => GROUPS.find((g) => g.key === key);
    expect(closeTimeOn(group('MCX_CRUDE'), day('2026-10-29'))).toBe('23:30');
    expect(closeTimeOn(group('MCX_CRUDE'), day('2026-11-18'))).toBe('23:55');
    expect(closeTimeOn(group('COMEX_PRECIOUS'), day('2026-11-23'))).toBe('23:55');
    expect(closeTimeOn(group('NSE_FUT'), day('2026-11-24'))).toBe('15:40');
    expect(closeTimeOn(group('GIFT_NIFTY'), day('2026-11-24'))).toBe('15:30');
    expect(closeTimeOn(group('GLOBAL_FUT'), day('2026-12-18'))).toBe('23:30');
  });
});

describe('Muhurat session jobs', () => {
  const jobsAt = (isoTime) => s.dueJobs(at(isoTime)).map((j) => `${j.type}:${j.window || ''}`);

  test('snapshot of the settled week before the session, closes like a weekday', () => {
    expect(jobsAt('2026-11-08T06:30:00Z')).toEqual(['weekSnapshot:']); // 12:00 IST
    expect(jobsAt('2026-11-08T07:30:00Z')).toEqual(['weekSnapshot:']); // 13:00
    expect(jobsAt('2026-11-08T08:15:00Z')).toEqual(['weekSnapshot:']); // 13:45
    expect(jobsAt('2026-11-08T09:50:00Z')).toEqual(['marketOnlyCancel:NSE']); // 15:20
    expect(jobsAt('2026-11-08T10:01:00Z')).toEqual(['squareoff:MCX']); // 15:31
    expect(jobsAt('2026-11-08T10:02:00Z')).toEqual(['cancel:MCX']); // 15:32
    expect(jobsAt('2026-11-08T10:11:00Z')).toEqual(['squareoff:NSE']); // 15:41
    expect(jobsAt('2026-11-08T10:12:00Z')).toEqual(['cancel:NSE']); // 15:42
    expect(jobsAt('2026-11-08T10:13:00Z')).toEqual([]);
  });

  test('nothing on an ordinary weekend', () => {
    expect(jobsAt('2026-11-01T10:11:00Z')).toEqual([]);
    expect(jobsAt('2026-11-15T06:30:00Z')).toEqual([]);
  });

  test('weekend price lock: released from 14:00 IST to the end of the session day only', () => {
    expect(isPriceWeekendInIndia(at('2026-11-08T08:29:00Z'))).toBe(true); // 13:59
    expect(isPriceWeekendInIndia(at('2026-11-08T08:30:00Z'))).toBe(false); // 14:00
    expect(isPriceWeekendInIndia(at('2026-11-08T16:30:00Z'))).toBe(false); // 22:00
    expect(isPriceWeekendInIndia(at('2026-11-07T10:00:00Z'))).toBe(true); // Saturday
    expect(isPriceWeekendInIndia(at('2026-11-15T09:00:00Z'))).toBe(true); // next Sunday
    // settlement keeps the plain weekend
    expect(isWeekendInIndia(at('2026-11-08T09:00:00Z'))).toBe(true);
  });

  test('feed watchdog window 14:00–15:50 IST', () => {
    expect(s.isSessionFeedWindow(at('2026-11-08T08:29:00Z'))).toBe(false);
    expect(s.isSessionFeedWindow(at('2026-11-08T09:00:00Z'))).toBe(true);
    expect(s.isSessionFeedWindow(at('2026-11-08T10:20:00Z'))).toBe(true);
    expect(s.isSessionFeedWindow(at('2026-11-08T10:21:00Z'))).toBe(false);
  });
});

describe('the session counts in the week after it', () => {
  const win = (f, t) => {
    const r = s.adjustReportWindow(f && at(f), t && at(t));
    return [iso(r.from), iso(r.to)];
  };

  test('the 9 Nov week starts on Sunday 8 Nov 00:00 IST however it is asked for', () => {
    expect(win('2026-11-09', '2026-11-13T23:59:59.999Z')[0]).toBe(S); // YYYY-MM-DD (UTC midnight)
    expect(win('2026-11-08T18:30:00Z', '2026-11-14T18:29:59Z')[0]).toBe(S); // Monday 00:00 IST
    expect(win('2026-11-08', '2026-11-08T23:59:59.999Z')[0]).toBe(S); // the Sunday itself
  });

  test('the settled 2 Nov week never includes the session', () => {
    expect(win('2026-11-02', '2026-11-08T23:59:59.999Z')).toEqual(['2026-11-02T00:00:00.000Z', '2026-11-07T18:29:59.999Z']);
    expect(win('2026-11-01T18:30:00Z', '2026-11-08T18:30:00Z')).toEqual(['2026-11-01T18:30:00.000Z', '2026-11-07T18:29:59.999Z']);
    expect(win('2026-11-02', '2026-11-06T23:59:59.999Z')).toEqual(['2026-11-02T00:00:00.000Z', '2026-11-06T23:59:59.999Z']);
  });

  test('other windows are untouched', () => {
    expect(win('2026-11-02', '2026-11-13T23:59:59.999Z')).toEqual(['2026-11-02T00:00:00.000Z', '2026-11-13T23:59:59.999Z']);
    expect(win('2026-11-16', '2026-11-20T23:59:59.999Z')).toEqual(['2026-11-16T00:00:00.000Z', '2026-11-20T23:59:59.999Z']);
    expect(win('2026-10-26', '2026-10-30T23:59:59.999Z')).toEqual(['2026-10-26T00:00:00.000Z', '2026-10-30T23:59:59.999Z']);
  });

  test('current/previous week as computed from the server Monday', () => {
    const b = (monday, now) => {
      const r = s.weekBounds(at(monday), at(now));
      return [iso(r.thisStart), iso(r.prevStart), iso(r.prevEnd)];
    };
    expect(b('2026-11-02T00:00:00Z', '2026-11-07T10:00:00Z')).toEqual(['2026-11-02T00:00:00.000Z', '2026-10-26T00:00:00.000Z', '2026-11-02T00:00:00.000Z']);
    expect(b('2026-11-02T00:00:00Z', '2026-11-08T09:30:00Z')).toEqual([S, '2026-11-02T00:00:00.000Z', S]); // on the Sunday
    expect(b('2026-11-09T00:00:00Z', '2026-11-11T09:30:00Z')).toEqual([S, '2026-11-02T00:00:00.000Z', S]);
    expect(b('2026-11-16T00:00:00Z', '2026-11-18T09:30:00Z')).toEqual(['2026-11-16T00:00:00.000Z', S, '2026-11-16T00:00:00.000Z']);
    expect(b('2026-11-23T00:00:00Z', '2026-11-25T09:30:00Z')).toEqual(['2026-11-23T00:00:00.000Z', '2026-11-16T00:00:00.000Z', '2026-11-23T00:00:00.000Z']);
  });

  test('weekly snapshots: the 2 Nov week as always, the 9 Nov week from the Sunday', () => {
    expect(iso(s.snapshotQueryStart(at('2026-11-02T00:00:00Z')))).toBe('2026-11-02T00:00:00.000Z');
    expect(iso(s.snapshotQueryStart(at('2026-11-09T00:00:00Z')))).toBe(S);
    expect(iso(s.snapshotQueryStart(at('2026-11-16T00:00:00Z')))).toBe('2026-11-16T00:00:00.000Z');
  });

  test('broker earnings bucket a session fill into the following Monday', () => {
    expect(s.followingMondayYmd(at('2026-11-08T09:00:00Z'))).toBe('2026-11-09');
    expect(s.followingMondayYmd(at('2026-11-09T09:00:00Z'))).toBeNull();
    expect(s.followingMondayYmd(at('2026-11-01T09:00:00Z'))).toBeNull();
  });
});
