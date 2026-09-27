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
// The expiring NIFTY contract stops trading at 3:40 PM IST on its expiry
// day (this platform's GIFT NIFTY session-1 close); the evening session
// that follows already trades the next month.
const EXPIRY_DAY_CUTOFF_MINUTE = (15 * 60) + 40;
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

/** Has this contract stopped trading as of `now`? (expiry day after 3:40 PM IST, or later days) */
function isPastExpiry(expiry, now = new Date()) {
  const p = getIndiaDateTimeParts(now);
  const todayKey = `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
  const key = dateKey(expiry);
  return key < todayKey || (key === todayKey && (p.hour * 60 + p.minute) >= EXPIRY_DAY_CUTOFF_MINUTE);
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

  /** The near-month row that is still trading — the next month once the expiring one stops at 3:40 PM on expiry day. */
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
      }
      const row = this._pickNearMonthFuture(rows);
      if (!row) {
        console.warn('⚠️  [GiftNiftyFeed] No NIFTY FUTIDX row in NSEIX response.');
        return;
      }

      if (row.TIMESTMP && row.TIMESTMP !== 'NA') {
        const tickAge = Date.now() - new Date(row.TIMESTMP.replace(/-/g, ' ')).getTime();
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

      lps._broadcastToClients({
        type: 'ticks',
        data: [{
          instrument_token: this.instrumentToken,
          last_price: lastPrice,
          bid_price: bidPrice,
          ask_price: askPrice,
        }],
      });
    } catch (error) {
      console.warn(`⚠️  [GiftNiftyFeed] Poll failed: ${error.message}`);
    }
  }
}

module.exports = new GiftNiftyFeedService();
module.exports._private = { parseNseixDate, isPastExpiry, listedExpiries };
