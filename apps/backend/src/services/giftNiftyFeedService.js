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

  _pickNearMonthFuture(rows) {
    const futures = rows.filter(r => r.INSTRUMENTTYPE === 'FUTIDX' && r.SYMBOL === 'NIFTY');
    if (futures.length === 0) return null;
    return futures.reduce((nearest, row) => {
      if (!nearest) return row;
      return new Date(row.EXPIRYDATE) < new Date(nearest.EXPIRYDATE) ? row : nearest;
    }, null);
  }

  async _poll() {
    if (!this._initialized) return;

    try {
      const res = await axios.get(NSEIX_URL, {
        timeout: 8000,
        headers: { 'User-Agent': BROWSER_UA },
      });

      const rows = res.data && Array.isArray(res.data.data) ? res.data.data : [];
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
