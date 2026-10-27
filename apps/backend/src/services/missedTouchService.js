'use strict';

/**
 * Missed-touch checks — fill pending LIMIT/SL orders whose price really
 * traded on the exchange between two live-feed snapshots. Kite's feed is a
 * snapshot about once a second, not every trade: on 27 Oct 2026 CRUDE NOV
 * printed 9503→9501 (91 lots) inside 21:13:03 while the feed went 9507 →
 * 9503 → 9505, so a SL SELL at 9502 stayed pending. Still last-traded-price
 * triggers only (never bid/ask); still filled at the order's own price.
 *
 *  A. Day range (instant): every Kite tick carries the day's low/high. When
 *     the low fell (or the high rose) past the live price since the previous
 *     tick, a trade printed there in between — dayRangeTouch() hands that
 *     range to the price queue with the tick.
 *  B/C. Kite candles: the historical API answers any window to the second
 *     (from..to) with the low/high actually traded in it — but that data
 *     arrives 1–40 s late (measured 27 Oct). Each script with pending orders
 *     keeps a cursor, and windows are re-read until they're SETTLE_MS old,
 *     so late data is still caught.
 *       C: a script with an order within NEAR_PCT of the live price is
 *          checked every NEAR_INTERVAL_MS;
 *       B: every script with pending orders, every SWEEP_INTERVAL_MS
 *          (only while it is ticking).
 *  Cancel/modify (a client's own, tradeController): checkBeforeChange()
 *     reads that order's window first — an order the price already traded
 *     through fills instead.
 *
 * An order only fills from a window that starts after it was placed or last
 * modified (Trade.updatedAt, less CLOCK_MARGIN_MS) — a price that printed
 * before the order existed can never fill it (priceQueueService.touchVerdict).
 *
 * Kite allows 3 historical requests/s per app. These checks use at most one
 * every MIN_GAP_MS (the watchdog's fill check and charts share the rest).
 * Synthetic tokens (GIFT NIFTY, Massive-fed COMEX/global) aren't Kite's and
 * are skipped. MISSED_TOUCH=off in .env turns it all off; practice mode never
 * runs it (simulated prices).
 */

const CLOCK_MARGIN_MS = 1000;      // server vs exchange clock, and a tick's own delay
const SETTLE_MS = 90_000;          // Kite's candle data can arrive this late
const MAX_LOOKBACK_MS = 15 * 60_000;
const NEAR_PCT = 0.005;            // 0.5% of the live price
const NEAR_INTERVAL_MS = 2000;
const SWEEP_INTERVAL_MS = 60_000;
const REFRESH_MS = 2000;           // re-read which scripts have pending orders
const MIN_GAP_MS = 1000;           // ≤ 1 Kite historical request per second
const BACKOFF_429_MS = 5000;
const FETCH_TIMEOUT_MS = 3000;
const CANCEL_WAIT_MS = 1500;       // a cancel never waits longer than this for a slot
const CANCEL_FETCH_TIMEOUT_MS = 2000;
const MAX_REFINE_PER_CHECK = 2;
const DAY_RANGE_MAX_GAP_MS = 30_000; // ticks further apart: no reliable "in between"
const DAY_RANGE_MAX_PCT = 0.05;      // a range this far from the live price is a bad print/reset

const PRIO = { CANCEL: 3, REFINE: 2, NEAR: 1, SWEEP: 0 };
const SYNTHETIC_MIN = 9_900_000_000;
const IST_MS = 5.5 * 3600_000;

let _enabledCache = null;
function enabled() {
  if (_enabledCache != null) return _enabledCache;
  let practice = false;
  try { practice = !!require('../config/practice').PRACTICE; } catch (_) { practice = false; }
  _enabledCache = !practice && String(process.env.MISSED_TOUCH || '').toLowerCase() !== 'off';
  return _enabledCache;
}

const isKiteToken = (token) => {
  const n = Number(token);
  return Number.isFinite(n) && n > 0 && n < SYNTHETIC_MIN;
};
const floorSec = (ms) => Math.floor(ms / 1000) * 1000;
const ceilSec = (ms) => Math.ceil(ms / 1000) * 1000;
const istStr = (ms) => new Date(ms + IST_MS).toISOString().replace('T', ' ').slice(0, 19);
/** Kite candle dates look like 2026-10-27T21:13:03+0530. */
const candleMs = (c) => Date.parse(String(c.date).replace(/([+-]\d{2})(\d{2})$/, '$1:$2'));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ── Scripts with pending orders (from the Redis order book) ────────────────
// token -> { near: bool }
let _tracked = new Map();
// token -> { cursor, lastCheckAt, nearSince }
const _state = new Map();
// token -> { low, high, at } of the previous tick (A)
const _day = new Map();
let _lastRefreshAt = 0;

function _ltp(token) {
  try {
    const lps = require('./livePriceService');
    return lps.latestPrices?.get(String(token)) || lps.latestPrices?.get(Number(token)) || null;
  } catch (_) { return null; }
}

async function _refresh() {
  _lastRefreshAt = Date.now();
  const redisService = require('./redisService');
  if (!redisService.isAvailable()) return;
  const client = redisService.getClient();
  const keys = [];
  let cursor = '0';
  do {
    const [next, batch] = await client.scan(cursor, 'MATCH', 'ob:*', 'COUNT', 1000);
    cursor = next;
    keys.push(...batch);
  } while (cursor !== '0');

  const byToken = new Map();
  for (const key of keys) {
    const token = key.split(':')[1];
    if (!isKiteToken(token)) continue;
    if (!byToken.has(token)) byToken.set(token, []);
    byToken.get(token).push(key);
  }
  const next = new Map();
  const pipe = client.pipeline();
  const asked = [];
  for (const [token, tokenKeys] of byToken) {
    const ltp = _ltp(token);
    next.set(token, { near: false });
    if (!(ltp > 0)) continue;
    for (const key of tokenKeys) {
      pipe.zcount(key, ltp * (1 - NEAR_PCT), ltp * (1 + NEAR_PCT));
      asked.push(token);
    }
  }
  if (asked.length) {
    const res = await pipe.exec();
    res.forEach(([err, count], i) => { if (!err && Number(count) > 0) next.get(asked[i]).near = true; });
  }
  for (const token of _state.keys()) if (!next.has(token)) _state.delete(token);
  for (const token of _day.keys()) if (!next.has(token)) _day.delete(token);
  _tracked = next;
}

// ── A: day range on every tick ──────────────────────────────────────────────
/**
 * Called by livePriceService for every Kite tick before it is published to
 * the price queue. Returns a touch when the day's low/high moved past the
 * live price since this script's previous tick (a trade printed there in
 * between), else null. Only scripts with pending orders are followed.
 */
function dayRangeTouch(tick) {
  if (!enabled() || !tick) return null;
  const token = String(tick.instrument_token);
  if (!_tracked.has(token)) return null;
  const low = Number(tick.low);
  const high = Number(tick.high);
  const ltp = Number(tick.last_price);
  const now = Date.now();
  const prev = _day.get(token);
  if (!(low > 0) || !(high > 0) || !(ltp > 0)) return null;
  const exch = Number(tick.exchange_timestamp) > 0 ? Number(tick.exchange_timestamp) * 1000 : null;
  _day.set(token, { low, high, at: now, exch });
  if (!prev || now - prev.at > DAY_RANGE_MAX_GAP_MS) return null;
  // The new extreme printed after the previous SNAPSHOT was taken — use the
  // exchange's time for it (whole seconds, so never later), not when we
  // received it: a lagging feed must not let an order placed after the print
  // qualify.
  const prevAt = prev.exch != null ? Math.min(prev.at, prev.exch) : prev.at;
  let tLow = low < prev.low && low < ltp ? low : null;
  let tHigh = high > prev.high && high > ltp ? high : null;
  if (tLow != null && (ltp - tLow) / ltp > DAY_RANGE_MAX_PCT) tLow = null;
  if (tHigh != null && (tHigh - ltp) / ltp > DAY_RANGE_MAX_PCT) tHigh = null;
  if (tLow == null && tHigh == null) return null;
  return { low: tLow, high: tHigh, since: prevAt - CLOCK_MARGIN_MS, at: now, source: 'day_range' };
}

// ── Kite request slots (≤ 1/s, cancel checks first) ────────────────────────
let _nextFreeAt = 0;
const _waiters = [];
let _pumpTimer = null;

function _pump() {
  if (_pumpTimer || _waiters.length === 0) return;
  _pumpTimer = setTimeout(() => {
    _pumpTimer = null;
    if (Date.now() < _nextFreeAt) return _pump();
    const w = _waiters.shift();
    if (w) {
      w.done = true;
      clearTimeout(w.timer);
      _nextFreeAt = Date.now() + MIN_GAP_MS;
      w.resolve(true);
    }
    _pump();
  }, Math.max(0, _nextFreeAt - Date.now()));
}

/** Resolves true when a request may go out, false if maxWaitMs passed first. */
function _slot(prio, maxWaitMs = null) {
  return new Promise((resolve) => {
    const w = { prio, resolve, done: false, timer: null };
    let i = _waiters.findIndex((x) => x.prio < prio);
    if (i < 0) i = _waiters.length;
    _waiters.splice(i, 0, w);
    if (maxWaitMs != null) {
      w.timer = setTimeout(() => {
        if (w.done) return;
        w.done = true;
        const at = _waiters.indexOf(w);
        if (at >= 0) _waiters.splice(at, 1);
        resolve(false);
      }, maxWaitMs);
    }
    _pump();
  });
}

let _lastErrLogAt = 0;
/** Candles for [fromMs, toMs) — null on any error (the window is retried later). */
async function _fetch(token, fromMs, toMs, timeoutMs = FETCH_TIMEOUT_MS) {
  const kiteService = require('./kiteService');
  let timer = null;
  try {
    const candles = await Promise.race([
      kiteService.getHistoricalData(String(token), 'minute', istStr(fromMs), istStr(toMs), { silent: true }),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('timeout')), timeoutMs); }),
    ]);
    return Array.isArray(candles) ? candles : (candles?.candles || []);
  } catch (error) {
    if (error?.response?.status === 429) _nextFreeAt = Date.now() + BACKOFF_429_MS;
    if (Date.now() - _lastErrLogAt > 60_000) {
      _lastErrLogAt = Date.now();
      console.warn(`⚠️  [MissedTouch] Kite candles failed (token ${token}): ${error?.response?.status || ''} ${error.message}`);
    }
    return null;
  } finally {
    clearTimeout(timer);
  }
}

const _touchOf = (c, source) => {
  const s = candleMs(c);
  return { low: Number(c.low), high: Number(c.high), since: s - CLOCK_MARGIN_MS, at: s, source };
};

// ── B/C: one script's window since its cursor ───────────────────────────────
async function _checkToken(token, prio) {
  const st = _state.get(token) || { cursor: 0, lastCheckAt: 0 };
  _state.set(token, st);
  const end = floorSec(Date.now());
  if (!st.cursor) st.cursor = end - SETTLE_MS;
  const from = Math.max(st.cursor, end - MAX_LOOKBACK_MS);
  st.lastCheckAt = Date.now();
  if (end - from < 1000) return;
  if (!(await _slot(prio))) return;
  const candles = await _fetch(token, from, end);
  if (candles == null) return; // cursor kept: the same window is read again next time
  const pq = require('./priceQueueService');
  let refines = 0;
  for (const c of candles) {
    if (!(Number(c.volume) > 0)) continue; // nothing traded (Kite repeats the last price)
    const touch = _touchOf(c, 'kite_window');
    const winEnd = Math.min(touch.at + 60_000, end);
    const outcomes = await pq.processTouch(token, touch, _ltp(token));
    // Orders placed inside this candle can't use it — read a window that
    // starts after each (newest first, a few per check).
    const young = outcomes
      .filter((o) => o.kind === 'not_eligible' && o.reason === 'placed_after' && o.placedAt < winEnd - 1000)
      .sort((a, b) => b.placedAt - a.placedAt);
    for (const o of young) {
      if (refines >= MAX_REFINE_PER_CHECK) break;
      const rs = ceilSec(o.placedAt + CLOCK_MARGIN_MS + 1);
      if (winEnd - rs < 1000) continue;
      refines++;
      if (!(await _slot(PRIO.REFINE, 5000))) break;
      const sub = await _fetch(token, rs, winEnd);
      for (const c2 of sub || []) {
        if (!(Number(c2.volume) > 0)) continue;
        await pq.processTouch(token, _touchOf(c2, 'kite_window'), _ltp(token), { onlyIds: new Set(young.map((y) => y.id)) });
      }
    }
  }
  st.cursor = Math.max(st.cursor, end - SETTLE_MS);
}

/** The next script due a check: near ones first, then the sweep; oldest check first. */
function _nextDue(now = Date.now()) {
  let best = null;
  for (const [token, info] of _tracked) {
    const st = _state.get(token);
    const last = st?.lastCheckAt || 0;
    // No tick since the window still to be read began: nothing traded
    // (every trade moves the volume, so Kite sends a tick) — e.g. the market
    // is closed. The first check of a script always runs.
    const tickAt = _day.get(token)?.at || 0;
    if (st?.cursor && tickAt < st.cursor) continue;
    let prio = null;
    if (info.near && now - last >= NEAR_INTERVAL_MS) prio = PRIO.NEAR;
    // A sweep twice overdue competes with the near checks (oldest first),
    // so many near scripts can't starve the others.
    else if (now - last >= SWEEP_INTERVAL_MS) prio = now - last >= 2 * SWEEP_INTERVAL_MS ? PRIO.NEAR : PRIO.SWEEP;
    if (prio == null) continue;
    if (!best || prio > best.prio || (prio === best.prio && last < best.last)) best = { token, prio, last };
  }
  return best;
}

let _running = false;
async function _loop() {
  while (_running) {
    try {
      if (Date.now() - _lastRefreshAt >= REFRESH_MS) await _refresh();
      const due = _nextDue();
      if (due) await _checkToken(due.token, due.prio);
      else await sleep(250);
    } catch (error) {
      if (Date.now() - _lastErrLogAt > 60_000) {
        _lastErrLogAt = Date.now();
        console.error(`❌ [MissedTouch] check loop: ${error.message}`);
      }
      await sleep(1000);
    }
  }
}

function start() {
  if (_running || !enabled()) return;
  _running = true;
  console.log('✅ [MissedTouch] Day-range + Kite-candle checks for prices traded between feed snapshots started');
  _loop();
}

function stop() {
  _running = false;
}

// ── A client's own cancel/modify ────────────────────────────────────────────
/**
 * Before a client's own cancel or modify: did the exchange trade through
 * this pending order's (current) price since it was placed/last modified?
 * If so it fills now, at its price. Never blocks the client for long — no
 * Kite slot within CANCEL_WAIT_MS or any error, and the change goes ahead.
 * Returns { checked, executed }.
 */
async function checkBeforeChange(trade) {
  const none = { checked: false, executed: false };
  if (!enabled() || !trade || trade.status !== 'pending') return none;
  if (!['LIMIT', 'SL', 'SL-M'].includes(trade.order_type)) return none;
  const token = String(trade.instrument_token);
  if (!isKiteToken(token)) return none;
  const end = floorSec(Date.now()) + 1000;
  const from = Math.max(ceilSec(new Date(trade.updatedAt || trade.createdAt || 0).getTime() + CLOCK_MARGIN_MS + 1), end - MAX_LOOKBACK_MS);
  if (end - from < 1000) return none;
  if (!(await _slot(PRIO.CANCEL, CANCEL_WAIT_MS))) return none;
  const candles = await _fetch(token, from, end, CANCEL_FETCH_TIMEOUT_MS);
  if (candles == null) return none;
  const pq = require('./priceQueueService');
  const id = String(trade._id);
  for (const c of candles) {
    if (!(Number(c.volume) > 0)) continue;
    const touch = _touchOf(c, 'cancel_check');
    if (pq._private.touchVerdict(trade, touch)) continue; // not crossed (or too early) — no order-book call
    const outcomes = await pq.processTouch(token, touch, _ltp(token), { onlyIds: new Set([id]) });
    if (outcomes.some((o) => o.kind === 'completed' || o.kind === 'rejected')) return { checked: true, executed: true };
  }
  return { checked: true, executed: false };
}

module.exports = {
  dayRangeTouch,
  checkBeforeChange,
  start,
  stop,
  _private: {
    _refresh, _checkToken, _nextDue, _slot, _fetch, candleMs, istStr,
    _tracked: () => _tracked,
    _setTracked: (m) => { _tracked = m; },
    _state, _day,
    _reset: () => { _tracked = new Map(); _state.clear(); _day.clear(); _waiters.length = 0; _nextFreeAt = 0; _enabledCache = null; },
    CONST: { CLOCK_MARGIN_MS, SETTLE_MS, NEAR_PCT, MIN_GAP_MS },
  },
};
