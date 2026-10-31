'use strict';

/**
 * Special exchange sessions on a day the platform normally treats as closed —
 * so far only Diwali Muhurat trading on Sunday 8 Nov 2026:
 *   NSE F&O 14:20–15:40 IST (NSE/FAOP/76940, 19 Oct 2026)
 *   MCX     14:20–15:30 IST (MCX/TRD/590/2026, 19 Oct 2026)
 *
 * Agreed with the business owner (30 Oct 2026), for this session only:
 *  - during it the platform trades like a normal day: live prices (the weekend
 *    settlement-price lock is released), and intraday square-off / pending
 *    order cancel run at the close exactly as on a weekday;
 *  - it belongs to the FOLLOWING week. Saturday's settlement before it is
 *    untouched; its trades are settled the next Saturday; every week-based
 *    report, bill and the ledger count it in the week of the Monday after it —
 *    that week starts at the session day's 00:00 IST instead of the Monday;
 *  - the ledger/summary snapshot of the week settled before it (normally
 *    Sunday 23:55 IST) runs before the session instead.
 *
 * No requires, so the watchdog can use it too.
 */

const IST_OFFSET_MS = 330 * 60 * 1000;
const DAY_MS = 864e5;

const SESSIONS = [
  {
    date: '2026-11-08',
    label: 'Diwali Muhurat trading',
    windows: [
      {
        key: 'NSE',
        segments: ['NFO-FUT', 'NFO-OPT'],
        exchanges: ['NFO', 'BFO', 'NSE', 'BSE'],
        open: '14:20',
        close: '15:40',
        // utils/nfoMarketOnlyWindow.js's 3:20–3:40 PM market-only rule is
        // clock-based, so it applies on this day too; its 3:20 cancel must run.
        marketOnlyCancelAt: '15:20',
      },
      { key: 'MCX', segments: ['MCX-FUT', 'MCX-OPT'], exchanges: ['MCX'], open: '14:20', close: '15:30' },
    ],
    // Snapshot of the week settled before the session (retries are harmless:
    // the ledger never writes a week twice, the summary upsert is the same).
    weekSnapshotAt: ['12:00', '13:00', '13:45'],
  },
];

/** Prices go live this long before the first open (Kite streams the pre-open). */
const PRICE_LEAD_MS = 20 * 60 * 1000;
/** The feed watchdog keeps checking this long after the last close. */
const FEED_TAIL_MS = 20 * 60 * 1000;
/** Intraday square-off this long after a window's close, once the bid/ask settled (as on a weekday). */
const SQUARE_OFF_AFTER_MIN = 15;

/** `YYYY-MM-DD` of the IST calendar day containing `now`. */
function istYmd(now = new Date()) {
  return new Date(new Date(now).getTime() + IST_OFFSET_MS).toISOString().slice(0, 10);
}

/** `HH:MM` IST of `now`. */
function istHhmm(now = new Date()) {
  return new Date(new Date(now).getTime() + IST_OFFSET_MS).toISOString().slice(11, 16);
}

/** The instant of `HH:MM` IST on `YYYY-MM-DD`. */
function istInstant(ymd, hhmm = '00:00') {
  const [y, m, d] = ymd.split('-').map(Number);
  const [hh, mm] = hhmm.split(':').map(Number);
  return new Date(Date.UTC(y, m - 1, d, hh, mm) - IST_OFFSET_MS);
}

function addMinutes(hhmm, minutes) {
  const [hh, mm] = hhmm.split(':').map(Number);
  const total = hh * 60 + mm + minutes;
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}

function sessionOn(ymd, sessions = SESSIONS) {
  return sessions.find((s) => s.date === ymd) || null;
}

function firstOpen(session) {
  return istInstant(session.date, session.windows.map((w) => w.open).sort()[0]);
}

function lastClose(session) {
  return istInstant(session.date, session.windows.map((w) => w.close).sort().slice(-1)[0]);
}

/**
 * Week boundaries around a session: S = the session day 00:00 IST (the new
 * start of the following week); M = the Monday after it at 00:00 UTC — the
 * server's own "Monday 00:00" (the process runs in UTC), the latest instant a
 * report could name as that week's start.
 */
function weekEdges(session) {
  const S = istInstant(session.date, '00:00');
  const [y, m, d] = session.date.split('-').map(Number);
  const M = new Date(Date.UTC(y, m - 1, d + 1));
  return { S, M };
}

/**
 * From 20 minutes before the first open until the end of the session day, the
 * weekend rules for prices (official settlement price locked against cached
 * ticks) do not apply: the session's ticks are real market moves, and after
 * it its closing prices stay.
 */
function isSessionPriceTime(now = new Date(), sessions = SESSIONS) {
  const session = sessionOn(istYmd(now), sessions);
  if (!session) return false;
  return new Date(now).getTime() >= firstOpen(session).getTime() - PRICE_LEAD_MS;
}

/** True while ticks are expected (the feed watchdog may reconnect a silent feed). */
function isSessionFeedWindow(now = new Date(), sessions = SESSIONS) {
  const session = sessionOn(istYmd(now), sessions);
  if (!session) return false;
  const t = new Date(now).getTime();
  return t >= firstOpen(session).getTime() - PRICE_LEAD_MS && t <= lastClose(session).getTime() + FEED_TAIL_MS;
}

/** Is a session day (any time of it). */
function isSessionDay(now = new Date(), sessions = SESSIONS) {
  return !!sessionOn(istYmd(now), sessions);
}

/**
 * The session-day jobs due at this IST minute: pending-order `cancel` two
 * minutes and intraday `squareoff` 15 minutes after each window's close (as on
 * a weekday), the NFO market-only cancel, and the pre-session week snapshot.
 */
function dueJobs(now = new Date(), sessions = SESSIONS) {
  const session = sessionOn(istYmd(now), sessions);
  if (!session) return [];
  const hhmm = istHhmm(now);
  const jobs = [];
  for (const w of session.windows) {
    if (w.marketOnlyCancelAt === hhmm) jobs.push({ type: 'marketOnlyCancel', segments: w.segments, window: w.key });
    if (addMinutes(w.close, 2) === hhmm) jobs.push({ type: 'cancel', segments: w.segments, window: w.key });
    if (addMinutes(w.close, SQUARE_OFF_AFTER_MIN) === hhmm) jobs.push({ type: 'squareoff', segments: w.segments, window: w.key });
  }
  if ((session.weekSnapshotAt || []).includes(hhmm)) jobs.push({ type: 'weekSnapshot' });
  return jobs;
}

/**
 * A report window [from, to] as asked for, moved so a session falls in the
 * week after it:
 *  - a window starting on the following week's Monday (00:00 IST or 00:00 UTC,
 *    or anywhere on the session day itself) starts at the session day 00:00 IST;
 *  - a window that starts before the session day and ends on it (the settled
 *    week asked for on the Sunday) stops just before it.
 * Any other window is returned unchanged. Never mutates its arguments.
 */
function adjustReportWindow(from, to, sessions = SESSIONS) {
  let f = from ? new Date(from) : from;
  let t = to ? new Date(to) : to;
  for (const session of sessions) {
    const { S, M } = weekEdges(session);
    if (f && f > S && f <= M) f = new Date(S);
    if (f && t && f < S && t >= S && t <= M) t = new Date(S.getTime() - 1);
  }
  return { from: f, to: t };
}

/**
 * The current week's start for code that computes "Monday 00:00" itself
 * (`rawMonday`): the session week starts at the session day 00:00 IST, and
 * from that instant on (the Sunday itself, before the server's Monday) the
 * current week is already that week.
 */
function adjustWeekStart(rawMonday, now = new Date(), sessions = SESSIONS) {
  const monday = new Date(rawMonday);
  const t = new Date(now).getTime();
  for (const session of sessions) {
    const { S, M } = weekEdges(session);
    if (monday > S && monday <= M) return new Date(S);
    if (monday < S && t >= S.getTime() && t < M.getTime()) return new Date(S);
  }
  return monday;
}

/**
 * This week's and last week's bounds from the code's own `rawMonday`:
 * { monday, thisStart, prevStart, prevEnd } — `monday` is the week's own
 * Monday (its end is monday + 7 days), prevEnd (exclusive) = thisStart.
 * Normal weeks: monday = thisStart = rawMonday, prevStart = rawMonday - 7 days.
 */
function weekBounds(rawMonday, now = new Date(), sessions = SESSIONS) {
  let monday = new Date(rawMonday);
  const t = new Date(now).getTime();
  for (const session of sessions) {
    const { S, M } = weekEdges(session);
    // On the session day (before the server's Monday) the week is already the next one.
    if (monday < S && t >= S.getTime() && t < M.getTime()) monday = new Date(M);
  }
  const thisStart = adjustWeekStart(monday, now, sessions);
  // Last week was the session week → it started on the session day too.
  const prevStart = snapshotQueryStart(new Date(monday.getTime() - 7 * DAY_MS), sessions);
  return { monday, thisStart, prevStart, prevEnd: thisStart };
}

/**
 * Where a snapshot of the week keyed `weekStart` (the Monday) starts reading
 * trades: the session day 00:00 IST for the week after a session.
 */
function snapshotQueryStart(weekStart, sessions = SESSIONS) {
  const w = new Date(weekStart);
  for (const session of sessions) {
    const { S, M } = weekEdges(session);
    if (w > S && w <= M) return new Date(S);
  }
  return w;
}

/** A fill on a session day belongs to the week of the Monday after it (IST): that Monday's `YYYY-MM-DD`, else null. */
function followingMondayYmd(at, sessions = SESSIONS) {
  const session = sessionOn(istYmd(at), sessions);
  if (!session) return null;
  const [y, m, d] = session.date.split('-').map(Number);
  const day = new Date(Date.UTC(y, m - 1, d)).getUTCDay();
  const ahead = ((8 - day) % 7) || 7;
  return new Date(Date.UTC(y, m - 1, d + ahead)).toISOString().slice(0, 10);
}

module.exports = {
  SESSIONS,
  istYmd,
  istHhmm,
  istInstant,
  sessionOn,
  isSessionDay,
  isSessionPriceTime,
  isSessionFeedWindow,
  dueJobs,
  adjustReportWindow,
  adjustWeekStart,
  weekBounds,
  snapshotQueryStart,
  followingMondayYmd,
};
