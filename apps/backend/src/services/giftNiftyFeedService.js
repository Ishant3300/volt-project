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
    const seen = new Set();
    for (const r of rows) {
      if (r.INSTRUMENTTYPE !== 'FUTIDX' || r.SYMBOL !== 'NIFTY') continue;
      const expiry = parseNseixDate(r.EXPIRYDATE);
      if (!expiry || dateKey(expiry) < MONTHLY_FROM || seen.has(dateKey(expiry))) continue;
      seen.add(dateKey(expiry));
      const ts = parseNseixTimestamp(r.TIMESTMP);
      if (!Number.isNaN(ts.getTime()) && now - ts.getTime() > STALE_THRESHOLD_MS) continue;
      const last = Number(r.LASTPRICE);
      if (!Number.isFinite(last) || last <= 0) continue;
      ticks.push({ instrument_token: contractToken(expiry), last_price: last, bid_price: Number(r.BIDPRICE) || last, ask_price: Number(r.ASKPRICE) || last, ...dayFields(r, last) });
    }
    if (ticks.length === 0) return ticks;
    const metricsEngine = require('./metricsEngine');
    const priceQueueService = require('./priceQueueService');
    const lps = this.livePriceService;
    for (const t of ticks) {
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
module.exports._private = { parseNseixDate, parseNseixTimestamp, isPastExpiry, listedExpiries, CONTINUOUS_RETIRE_AT, dayFields };
