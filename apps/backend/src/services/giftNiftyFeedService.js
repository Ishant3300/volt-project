/**
 * GIFT Nifty — Live Bid/Ask Feed (NSEIX)
 *
 * Kite only sends real bid/ask in "full mode" 184-byte packets, and only for
 * genuine tradable derivatives — index-type instruments (28/32-byte packets,
 * which is what GIFT Nifty's Kite symbol 'SG 30' sends, segment INDICES)
 * carry last_price/OHLC only, never market depth. That leaves the platform's
 * GIFT Nifty bid/ask frozen at whatever seed value was last set.
 *
 * NSEIX (nseix.com) publishes the real GIFT Nifty NIFTY futures book —
 * including live bid/ask — on a public, unauthenticated JSON endpoint. This
 * polls that endpoint and merges bid/ask into the same in-memory caches and
 * broadcast path bhavcopyService uses to apply settlement prices, so every
 * downstream consumer (Flutter WS clients, metricsEngine) sees it exactly
 * like a real tick.
 */

const axios = require('axios');
const KiteInstrument = require('../models/KiteInstrument');
const { dateKey, getIndiaDateTimeParts } = require('../utils/settlementDates');

const MONTHS = { JAN: 0, FEB: 1, MAR: 2, APR: 3, MAY: 4, JUN: 5, JUL: 6, AUG: 7, SEP: 8, OCT: 9, NOV: 10, DEC: 11 };
// On expiry day the expiring NIFTY contract trades 06:15–15:30 IST only
// (NSE IX consolidated circular NSEIFSC/TRADE/2129, index derivatives
// "Expiry Day - Trade timings 06.15 AM to 3.30 PM"); session 2 (16:05 IST
// onward, NSEIFSC/TRADE/2543) trades the next month. Quotes are held on the
// expiring contract until 16:00 so its closing bid/ask is what the expiry
// cut's 15:31 snapshot and the 15:46 expiry-day close price at — then roll
// before session 2 opens. (The GIFT NIFTY expiry cut runs at 15:41, the
// same time as NSE futures — config/expiryRules.js.)
const EXPIRY_DAY_CUTOFF_MINUTE = 16 * 60;
const EXPIRING_TRADING_END_MINUTE = (15 * 60) + 30;
const IST_OFFSET_MS = (5 * 60 + 30) * 60 * 1000;
// The continuous "GIFT NIFTY" instrument is closed for new trades once the
// Sep 2026 contract it tracks has expired (29 Sep; its 3:31 PM close done) —
// GIFT NIFTY trades as monthly contracts (giftNiftyContracts.js) from then.
const CONTINUOUS_RETIRE_AT = new Date('2026-09-29T10:32:00.000Z'); // 29 Sep 2026 16:02 IST
const CONTRACT_SYNC_MS = 10 * 60 * 1000;
// Re-assert the stored near-month expiry at most this often — the daily
// Kite instrument sync (fetchInstruments.js) rewrites GIFT NIFTY with
// Kite's own, expiry-less record.
const EXPIRY_RESYNC_MS = 60 * 1000;

/** NSEIX 'DD-Mon-YYYY' (e.g. '29-Sep-2026') → UTC-midnight Date, or null. */
function parseNseixDate(value) {
  const m = /^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/.exec(String(value || '').trim());
  if (!m || MONTHS[m[2].toUpperCase()] === undefined) return null;
  return new Date(Date.UTC(Number(m[3]), MONTHS[m[2].toUpperCase()], Number(m[1])));
}

/** Should quotes/listing have moved past this contract as of `now`? (expiry day from 4:00 PM IST, or later days) */
function isPastExpiry(expiry, now = new Date()) {
  const p = getIndiaDateTimeParts(now);
  const todayKey = `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
  const key = dateKey(expiry);
  return key < todayKey || (key === todayKey && (p.hour * 60 + p.minute) >= EXPIRY_DAY_CUTOFF_MINUTE);
}

/**
 * GIFT NIFTY on its expiry day between 3:30 PM (NSE IX stops the expiring
 * contract) and 4:00 PM (quotes roll to next month): the platform still
 * allows trading until 3:40 PM, but prices are frozen at the 3:30 last
 * quote — so only closing orders are accepted then (tradeController).
 */
function isGiftExpiryHalt(instrument, now = new Date()) {
  // Any NSE IX GIFT NIFTY contract on its own expiry day — the continuous
  // instrument or a monthly GIFTNIFTY…FUT; the next month is unaffected.
  if (!instrument || String(instrument.exchange || '').toUpperCase() !== 'NSEIX' || !instrument.expiry) return false;
  const p = getIndiaDateTimeParts(now);
  const todayKey = `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
  const mins = p.hour * 60 + p.minute;
  return dateKey(instrument.expiry) === todayKey && mins >= EXPIRING_TRADING_END_MINUTE && mins < EXPIRY_DAY_CUTOFF_MINUTE;
}

// NSE IX session break: session 1 ends 15:40 IST, session 2 opens 16:05 IST
// (NSEIFSC/TRADE/2543). No GIFT NIFTY trading in between.
const SESSION_BREAK_START_MINUTE = (15 * 60) + 40;
const SESSION_BREAK_END_MINUTE = (16 * 60) + 5;

/**
 * True during the NSE IX break between session 1 and session 2 (15:40–16:05
 * IST, Mon–Fri). The last quote is still under 5 minutes old for the first
 * minutes of the break, so isQuoteLive alone let a market order fill at the
 * closing price after NSE IX had stopped; tradeController refuses GIFT
 * orders for the whole break.
 */
function isGiftSessionBreak(now = new Date()) {
  const p = getIndiaDateTimeParts(now);
  const weekday = new Date(Date.UTC(p.year, p.month - 1, p.day)).getUTCDay(); // 0 = Sun
  if (weekday === 0 || weekday === 6) return false;
  const mins = p.hour * 60 + p.minute;
  return mins >= SESSION_BREAK_START_MINUTE && mins < SESSION_BREAK_END_MINUTE;
}

/** NSEIX 'DD-Mon-YYYY HH:MM:SS' — India time — → absolute Date (invalid Date if unparseable). */
function parseNseixTimestamp(value) {
  const m = /^(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{2}):(\d{2}):(\d{2})$/.exec(String(value || '').trim());
  if (!m || MONTHS[m[2].toUpperCase()] === undefined) return new Date(NaN);
  return new Date(Date.UTC(Number(m[3]), MONTHS[m[2].toUpperCase()], Number(m[1]), Number(m[4]), Number(m[5]), Number(m[6])) - IST_OFFSET_MS);
}

/** NIFTY FUTIDX rows → sorted distinct expiries still trading as of `now`. */
function listedExpiries(rows, now = new Date()) {
  const keys = new Map();
  for (const r of rows) {
    if (r.INSTRUMENTTYPE !== 'FUTIDX' || r.SYMBOL !== 'NIFTY') continue;
    const d = parseNseixDate(r.EXPIRYDATE);
    if (d && !isPastExpiry(d, now)) keys.set(dateKey(d), d);
  }
  return [...keys.values()].sort((a, b) => a - b);
}

const BROWSER_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const NSEIX_URL = 'https://www.nseix.com/api/derivatives-watch?inst_type1=IDX&inst_type2=STK&type=live';

/**
 * Day fields for a GIFT tick, from the contract's own NSE IX row — the same
 * open/high/low/close/change/change_percent a Kite tick carries, so the
 * watchlist shows them (ticks used to carry only last/bid/ask, leaving the
 * monthly contracts blank). NSE IX's OPEN/HIGH/LOW are the current session,
 * CLOSE is the previous settlement (matches settlement_price), and change is
 * last − close. A missing field is left out, so it never blanks a value.
 */
function dayFields(row, last) {
  const num = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? n : null;
  };
  const out = {};
  const open = num(row.OPEN);
  const high = num(row.HIGH);
  const low = num(row.LOW);
  const close = num(row.CLOSE);
  if (open != null) out.open = open;
  if (high != null) out.high = high;
  if (low != null) out.low = low;
  if (close != null) {
    out.close = close;
    out.change = Math.round((last - close) * 100) / 100;
    out.change_percent = Math.max(-100, Math.min(1000, ((last - close) / close) * 100));
  }
  return out;
}
// Was 15s — average staleness of a periodic poll is ~half the interval, so a
// 15s poll meant bid/ask could lag NSEIX's own feed by up to 15s and ~7.5s on
// average, reported as a "3-5s delay" in practice. NSEIX showed no rate
// limiting at 15 rapid back-to-back requests in testing, so 2s is safe.
const POLL_INTERVAL_MS = 2_000;
const STALE_THRESHOLD_MS = 5 * 60 * 1000;
// NSE IX's public site sometimes stops publishing while GIFT NIFTY keeps trading
// (4 Nov 2026: frozen from 10:09 IST, live everywhere else). Kite streams GIFT
// NIFTY on our own feed (continuous token 291849 = the near-month future), so while
// NSE IX is stale the near-month contract is priced from that. Off: GIFT_KITE_FALLBACK=off.
const KITE_GIFT_TOKEN = 291849;
const KITE_FALLBACK = String(process.env.GIFT_KITE_FALLBACK || 'on').toLowerCase() !== 'off';
// A GIFT price more than 2% away from the last accepted one is ignored unless it
// repeats (within 0.5%) for 3 polls in a row — 4 Nov 2026 12:22:09 IST NSE IX sent
// one quote of 2375.2 (for ~23,752) and it filled 8 limit BUYs that the market never reached.
const JUMP_LIMIT = 0.02;
const JUMP_CONFIRM_POLLS = 3;

class GiftNiftyFeedService {
  constructor() {
    this.livePriceService = null;
    this.instrumentToken = null;
    this._timer = null;
    this._initialized = false;
    // Last EXPIRYDATE written to KiteInstrument — lets _poll() skip the
    // write on every single 2s tick and only touch the DB when NSEIX's own
    // near-month contract actually rolls to the next expiry.
    this._lastWrittenExpiryIso = null;
    this._lastExpirySyncAt = 0;
    // Every NIFTY future NSEIX currently lists (near, next, far) — read by
    // the contract-expiry scheduler (expiryActionService) to plan GIFT NIFTY cuts.
    this._listedExpiries = [];
    this._listedAt = 0;
    this._contractsSyncedAt = 0;
    this._contractsKey = '';
    this._continuousRetired = false;
    // Per contract token: when its last FRESH NSE IX quote arrived (ms). No
    // fresh quote for STALE_THRESHOLD_MS = NSE IX isn't trading (holiday,
    // between sessions) or the feed is down; orders are refused then — see
    // isQuoteLive and tradeController's GIFT check.
    this._freshQuoteAt = new Map();
    // Kite GIFT NIFTY: last price seen and when it last CHANGED (a price that
    // hasn't moved for STALE_THRESHOLD_MS = Kite isn't live either).
    this._kiteSeen = { price: null, changedAt: 0 };
    this._kiteFallbackOn = false;
    // Day high/low while on Kite: NSE IX's session values, widened by Kite prices.
    this._kiteDay = null;
    // Per token: a price that jumped past JUMP_LIMIT, waiting to be confirmed.
    this._suspect = new Map();
  }

  /**
   * False for a price that jumps more than JUMP_LIMIT from this token's last
   * accepted price, until the same level has repeated JUMP_CONFIRM_POLLS times
   * (a real gap gets through in ~6 s; a one-off bad quote never does).
   */
  _saneTick(token, price) {
    const key = String(token);
    const prev = Number(this.livePriceService?.latestPrices?.get(key));
    if (!(prev > 0) || Math.abs(price / prev - 1) <= JUMP_LIMIT) {
      this._suspect.delete(key);
      return true;
    }
    const s = this._suspect.get(key);
    const count = s && Math.abs(price / s.price - 1) <= 0.005 ? s.count + 1 : 1;
    this._suspect.set(key, { price, count });
    if (count >= JUMP_CONFIRM_POLLS) {
      this._suspect.delete(key);
      console.warn(`⚠️  [GiftNiftyFeed] ${key}: price moved ${prev} → ${price}, confirmed over ${count} polls — accepted`);
      return true;
    }
    console.warn(`⚠️  [GiftNiftyFeed] ${key}: price ${price} is >${JUMP_LIMIT * 100}% from ${prev} — ignored (${count}/${JUMP_CONFIRM_POLLS})`);
    return false;
  }

  /** Kite's GIFT NIFTY price if it moved within STALE_THRESHOLD_MS, else null. */
  _freshKitePrice(now = Date.now()) {
    const lps = this.livePriceService;
    const p = Number(lps && (lps.latestPrices.get(String(KITE_GIFT_TOKEN)) ?? lps.latestPrices.get(KITE_GIFT_TOKEN)));
    if (!Number.isFinite(p) || p <= 0) return null;
    // First sighting doesn't count (after a restart the slot can hold a seeded
    // close) — fresh only once the price has actually moved while we watch.
    if (this._kiteSeen.price == null) this._kiteSeen = { price: p, changedAt: 0 };
    else if (p !== this._kiteSeen.price) this._kiteSeen = { price: p, changedAt: now };
    return now - this._kiteSeen.changedAt <= STALE_THRESHOLD_MS ? p : null;
  }

  /** True while this GIFT contract has had a fresh NSE IX quote in the last 5 minutes. */
  isQuoteLive(instrumentToken, now = Date.now()) {
    const at = this._freshQuoteAt.get(String(instrumentToken));
    return at != null && now - at <= STALE_THRESHOLD_MS;
  }

  /** When this GIFT contract last had a fresh quote (ms), or null. */
  lastFreshQuoteAt(instrumentToken) {
    return this._freshQuoteAt.get(String(instrumentToken)) ?? null;
  }

  /** Create monthly contracts NSE IX lists that don't exist yet (throttled). */
  async _syncMonthlyContracts(expiries) {
    const key = expiries.map((e) => dateKey(e)).join(',');
    if (key === this._contractsKey && Date.now() - this._contractsSyncedAt < CONTRACT_SYNC_MS) return;
    this._contractsKey = key;
    this._contractsSyncedAt = Date.now();
    await require('./giftNiftyContracts').ensureContracts(expiries);
  }

  /** Each monthly contract's own live bid/ask (and day OHLC/change), from its own NSE IX row. */
  _tickMonthlyContracts(rows, now = Date.now()) {
    const { contractToken, MONTHLY_FROM } = require('./giftNiftyContracts');
    const ticks = [];
    const staleSeeds = [];
    const seen = new Set();
    const lps = this.livePriceService;
    const [nearExpiry] = listedExpiries(rows, new Date(now));
    // Not on the near month's own expiry day (Kite's continuous may roll at another time).
    const tp = getIndiaDateTimeParts(new Date(now));
    const istToday = `${tp.year}-${String(tp.month).padStart(2, '0')}-${String(tp.day).padStart(2, '0')}`;
    const nearKey = nearExpiry && dateKey(nearExpiry) !== istToday ? dateKey(nearExpiry) : null;
    const kitePrice = KITE_FALLBACK ? this._freshKitePrice(now) : null;
    let usedKite = false;
    for (const r of rows) {
      if (r.INSTRUMENTTYPE !== 'FUTIDX' || r.SYMBOL !== 'NIFTY') continue;
      const expiry = parseNseixDate(r.EXPIRYDATE);
      if (!expiry || dateKey(expiry) < MONTHLY_FROM || seen.has(dateKey(expiry))) continue;
      seen.add(dateKey(expiry));
      const last = Number(r.LASTPRICE);
      if (!Number.isFinite(last) || last <= 0) continue;
      const tick = { instrument_token: contractToken(expiry), last_price: last, bid_price: Number(r.BIDPRICE) || last, ask_price: Number(r.ASKPRICE) || last, ...dayFields(r, last) };
      const ts = parseNseixTimestamp(r.TIMESTMP);
      if (!Number.isNaN(ts.getTime()) && now - ts.getTime() > STALE_THRESHOLD_MS
          && kitePrice != null && dateKey(expiry) === nearKey) {
        // NSE IX stale but Kite's GIFT NIFTY is live: near month from Kite. Kite
        // sends no depth for it, so bid/ask = Kite price -/+ half of NSE IX's
        // last spread (kept within 0.5-5 points).
        const spread = Math.min(5, Math.max(0.5, Number(r.ASKPRICE) - Number(r.BIDPRICE) || 0.5));
        const half = Math.round((spread / 2) * 20) / 20;
        const dayKey = `${nearKey}|${istToday}`;
        if (!this._kiteDay || this._kiteDay.key !== dayKey) {
          this._kiteDay = { key: dayKey, high: Number(r.HIGH) > 0 ? Number(r.HIGH) : kitePrice, low: Number(r.LOW) > 0 ? Number(r.LOW) : kitePrice };
        }
        this._kiteDay.high = Math.max(this._kiteDay.high, kitePrice);
        this._kiteDay.low = Math.min(this._kiteDay.low, kitePrice);
        ticks.push({ instrument_token: tick.instrument_token, last_price: kitePrice, bid_price: kitePrice - half, ask_price: kitePrice + half,
          ...dayFields({ OPEN: r.OPEN, HIGH: this._kiteDay.high, LOW: this._kiteDay.low, CLOSE: r.CLOSE }, kitePrice) });
        usedKite = true;
        continue;
      }
      if (!Number.isNaN(ts.getTime()) && now - ts.getTime() > STALE_THRESHOLD_MS) {
        // Stale quote (holiday, between sessions). The price lives only in
        // memory (these contracts have no stored last_price), so after a
        // restart nothing showed at all and open positions were valued at
        // entry. Use NSE IX's last quote ONCE for display/valuation — never as
        // live: no freshness mark (orders stay refused), no order matching.
        if (!lps.latestPrices.has(tick.instrument_token)) staleSeeds.push(tick);
        continue;
      }
      ticks.push(tick);
    }
    if (usedKite !== this._kiteFallbackOn) {
      this._kiteFallbackOn = usedKite;
      console.log(usedKite
        ? `📡 [GiftNiftyFeed] NSE IX quote stale — near month now priced from Kite GIFT NIFTY (${kitePrice})`
        : '📡 [GiftNiftyFeed] Near month back on NSE IX quotes (Kite fallback off)');
    }
    if (ticks.length === 0 && staleSeeds.length === 0) return ticks;
    const metricsEngine = require('./metricsEngine');
    const priceQueueService = require('./priceQueueService');
    for (const t of staleSeeds) {
      lps.latestPrices.set(t.instrument_token, t.last_price);
      lps.latestPrices.set(Number(t.instrument_token), t.last_price);
      metricsEngine.onTick(t.instrument_token, t.last_price, t.bid_price, t.ask_price);
    }
    if (staleSeeds.length > 0) {
      console.log(`📡 [GiftNiftyFeed] No live NSE IX quote — showing last quote for ${staleSeeds.map((t) => `${t.instrument_token}@${t.last_price}`).join(', ')} (orders stay paused)`);
      lps._broadcastToClients({ type: 'ticks', data: staleSeeds });
    }
    const dayRange = require('../utils/dayRange');
    for (let i = ticks.length - 1; i >= 0; i--) {
      const t = ticks[i];
      if (!this._saneTick(t.instrument_token, t.last_price)) { ticks.splice(i, 1); continue; }
      // Outside the day's high–low without the low/high moving = bad quote (utils/dayRange.js).
      if (!dayRange.acceptTick(t.instrument_token, t.last_price, t.low, t.high)) {
        console.warn(`⚠️  [GiftNiftyFeed] ${t.instrument_token}: price ${t.last_price} outside the day's high–low ${t.low}/${t.high} — ignored`);
        ticks.splice(i, 1);
      }
    }
    if (ticks.length === 0) return ticks;
    for (const t of ticks) {
      this._freshQuoteAt.set(String(t.instrument_token), now);
      lps.latestPrices.set(t.instrument_token, t.last_price);
      lps.latestPrices.set(Number(t.instrument_token), t.last_price);
      metricsEngine.onTick(t.instrument_token, t.last_price, t.bid_price, t.ask_price);
      // Pending limit/stop orders are matched off this, exactly as for Kite ticks.
      priceQueueService.publishPriceUpdate(t.instrument_token, t.last_price);
    }
    lps._broadcastToClients({ type: 'ticks', data: ticks });
    return ticks;
  }

  /** One-time: close the continuous instrument for new trades after its last month expired. */
  async _retireContinuousIfDue(now = new Date()) {
    if (this._continuousRetired || now < CONTINUOUS_RETIRE_AT) return;
    this._continuousRetired = true;
    const res = await KiteInstrument.collection.updateOne(
      { instrument_token: this.instrumentToken, retired_to_monthly_at: { $exists: false } },
      { $set: {
        enabled: false,
        ban_reason: 'GIFT NIFTY now trades as monthly contracts — search GIFTNIFTY (e.g. GIFTNIFTY26OCTFUT).',
        banned_at: now,
        retired_to_monthly_at: now,
      } },
    );
    if (res.modifiedCount) {
      console.log('🔒 [GiftNiftyFeed] Continuous "GIFT NIFTY" closed for new trades — monthly contracts from now on.');
      try { require('./instrumentSearchService').invalidateCache(); } catch (_) {}
    }
  }

  /** Listed GIFT NIFTY expiries (UTC-midnight Dates), freshest known. */
  getListedExpiries() {
    return this._listedExpiries.slice();
  }

  /** One-off fetch of the listed expiries — for callers that can't wait for a poll. */
  async fetchListedExpiries() {
    const res = await axios.get(NSEIX_URL, { timeout: 8000, headers: { 'User-Agent': BROWSER_UA } });
    const rows = res.data && Array.isArray(res.data.data) ? res.data.data : [];
    const expiries = listedExpiries(rows);
    if (expiries.length) {
      this._listedExpiries = expiries;
      this._listedAt = Date.now();
    }
    return expiries.slice();
  }

  /** Keep KiteInstrument.expiry = the near-month contract, surviving the daily Kite sync. */
  async _syncStoredExpiry(nearExpiry) {
    const iso = nearExpiry.toISOString();
    if (iso === this._lastWrittenExpiryIso && Date.now() - this._lastExpirySyncAt < EXPIRY_RESYNC_MS) return;
    this._lastExpirySyncAt = Date.now();
    this._lastWrittenExpiryIso = iso;
    const res = await KiteInstrument.updateOne(
      { instrument_token: this.instrumentToken, expiry: { $ne: nearExpiry } },
      { $set: { expiry: nearExpiry } },
    );
    if (res.modifiedCount) console.log(`📅 [GiftNiftyFeed] GIFT NIFTY expiry set to ${dateKey(nearExpiry)} (NSEIX near month)`);
  }

  async init(livePriceService) {
    this.livePriceService = livePriceService;

    const inst = await KiteInstrument.findOne({
      $or: [{ tradingsymbol: 'GIFT NIFTY' }, { name: 'GIFT NIFTY' }, { display_name: 'GIFT NIFTY' }],
      is_active: true,
    }).lean();

    if (!inst) {
      console.warn('⚠️  [GiftNiftyFeed] "GIFT NIFTY" instrument not found — feed disabled.');
      return;
    }

    this.instrumentToken = inst.instrument_token.toString();
    this._lastWrittenExpiryIso = inst.expiry ? new Date(inst.expiry).toISOString() : null;
    this._initialized = true;
    console.log(`📡 [GiftNiftyFeed] "GIFT NIFTY" → token ${this.instrumentToken}, polling NSEIX every ${POLL_INTERVAL_MS / 1000}s`);

    this._timer = setInterval(() => this._poll(), POLL_INTERVAL_MS);
    this._poll();
  }

  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
    }
  }

  /** The near-month row — the next month from 4:00 PM on expiry day (the expiring one stops at 3:30 PM). */
  _pickNearMonthFuture(rows, now = new Date()) {
    const [near] = listedExpiries(rows, now);
    if (!near) return null;
    const key = dateKey(near);
    return rows.find(r => r.INSTRUMENTTYPE === 'FUTIDX' && r.SYMBOL === 'NIFTY' && dateKey(parseNseixDate(r.EXPIRYDATE) || 0) === key) || null;
  }

  async _poll() {
    if (!this._initialized) return;

    try {
      const res = await axios.get(NSEIX_URL, {
        timeout: 8000,
        headers: { 'User-Agent': BROWSER_UA },
      });

      const rows = res.data && Array.isArray(res.data.data) ? res.data.data : [];
      const expiries = listedExpiries(rows);
      if (expiries.length) {
        this._listedExpiries = expiries;
        this._listedAt = Date.now();
        // Before the staleness check below — the expiry is a fact about the
        // contract, valid even when there's no fresh quote (weekends, nights).
        await this._syncStoredExpiry(expiries[0])
          .catch((err) => console.warn(`⚠️  [GiftNiftyFeed] Failed to persist expiry: ${err.message}`));
        await this._syncMonthlyContracts(expiries)
          .catch((err) => console.warn(`⚠️  [GiftNiftyFeed] Monthly contract sync failed: ${err.message}`));
      }
      this._tickMonthlyContracts(rows);
      await this._retireContinuousIfDue()
        .catch((err) => { this._continuousRetired = false; console.warn(`⚠️  [GiftNiftyFeed] Retire failed: ${err.message}`); });
      const row = this._pickNearMonthFuture(rows);
      if (!row) {
        console.warn('⚠️  [GiftNiftyFeed] No NIFTY FUTIDX row in NSEIX response.');
        return;
      }

      if (row.TIMESTMP && row.TIMESTMP !== 'NA') {
        const tickAge = Date.now() - parseNseixTimestamp(row.TIMESTMP).getTime();
        if (Number.isFinite(tickAge) && tickAge > STALE_THRESHOLD_MS) {
          console.warn(`⚠️  [GiftNiftyFeed] NSEIX tick stale (${Math.round(tickAge / 1000)}s old) — skipping.`);
          return;
        }
      }

      const lastPrice = Number(row.LASTPRICE);
      const bidPrice = Number(row.BIDPRICE) || lastPrice;
      const askPrice = Number(row.ASKPRICE) || lastPrice;
      if (!Number.isFinite(lastPrice) || lastPrice <= 0) return;
      if (!this._saneTick(this.instrumentToken, lastPrice)) return;
      if (!require('../utils/dayRange').acceptTick(this.instrumentToken, lastPrice, Number(row.LOW), Number(row.HIGH))) return;

      this._freshQuoteAt.set(String(this.instrumentToken), Date.now());
      const lps = this.livePriceService;
      lps.latestPrices.set(this.instrumentToken, lastPrice);
      lps.latestPrices.set(Number(this.instrumentToken), lastPrice);

      const metricsEngine = require('./metricsEngine');
      metricsEngine.onTick(this.instrumentToken, lastPrice, bidPrice, askPrice);
      // Pending limit/stop orders on GIFT NIFTY were never matched — only Kite
      // ticks fed the order-matching queue (livePriceService). Same call here.
      require('./priceQueueService').publishPriceUpdate(this.instrumentToken, lastPrice);

      lps._broadcastToClients({
        type: 'ticks',
        data: [{
          instrument_token: this.instrumentToken,
          last_price: lastPrice,
          bid_price: bidPrice,
          ask_price: askPrice,
          ...dayFields(row, lastPrice),
        }],
      });
    } catch (error) {
      console.warn(`⚠️  [GiftNiftyFeed] Poll failed: ${error.message}`);
    }
  }
}

module.exports = new GiftNiftyFeedService();
module.exports.isGiftExpiryHalt = isGiftExpiryHalt;
module.exports.isGiftSessionBreak = isGiftSessionBreak;
module.exports._private = { parseNseixDate, parseNseixTimestamp, isPastExpiry, listedExpiries, CONTINUOUS_RETIRE_AT, dayFields };
