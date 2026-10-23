/**
 * GLOBAL index futures + COMEX metal futures — live feed (Massive.com).
 *
 * Persistent WebSocket to Massive's real-time futures feed (Quotes for
 * bid/ask, Trades for last price), covering the instruments seeded by
 * scripts/seedGlobalFutures.js (segment GLOBAL / COMEX-FUT). Feeds into the
 * same shared sinks every other price source uses — livePriceService's
 * latestPrices map, metricsEngine.onTick, and the WS broadcast to clients —
 * so nothing downstream (positions, P&L, order fills, rollover, margin
 * square-off) needs to know which of Kite / NSEIX / Massive a price came
 * from.
 *
 * Docs: https://massive.com/docs/websocket/futures/quotes
 *       https://massive.com/docs/websocket/futures/trades
 */

const WebSocket = require('ws');
const axios = require('axios');
const KiteInstrument = require('../models/KiteInstrument');
const { GLOBAL_INDEX_NAMES, COMEX_METAL_SEGMENT } = require('../constants/massiveInstruments');

const API_KEY = process.env.MASSIVE_API_KEY;
const WS_URL = 'wss://socket.massive.com/futures';
const REST_BASE_URL = 'https://api.massive.com';
const RECONNECT_DELAY_MS = 10_000;
const OHLC_POLL_INTERVAL_MS = 20_000;
// _pollOhlc fires REST calls to Massive's aggs endpoint, entirely separate
// from the persistent WS connection that streams live ticks (_handleQuote/
// _handleTrade below) — this batching only paces those REST calls and has
// no bearing on live-feed latency. Firing all ~24 tracked contracts at once
// every cycle was a thundering-herd burst against Massive's API, causing
// widespread 8s timeouts (confirmed in production logs: "OHLC poll failed
// for <ticker>: timeout of 8000ms exceeded", rotating across different
// tickers each cycle — not the same ones failing every time, consistent
// with a capacity/rate-limit issue under a 24-way burst, not a per-ticker
// data gap). Small batches with a short gap between them stay well inside
// the 20s poll interval in the normal case while no longer saturating
// Massive's API in one instant.
const OHLC_POLL_BATCH_SIZE = 6;
const OHLC_POLL_BATCH_GAP_MS = 400;

// Dow/Nasdaq/gold etc print real trades multiple times per second during
// active hours — broadcasting every single one to clients made the UI flicker
// at a rate no human actually reads. This only throttles the CLIENT-FACING
// broadcast; latestPrices and metricsEngine.onTick (below) still update on
// every real tick, so P&L/order-matching accuracy is unaffected — only how
// often the price visibly refreshes on screen is capped.
const BROADCAST_THROTTLE_MS = 500;

class MassiveFuturesFeedService {
  constructor() {
    this.livePriceService = null;
    this.ws = null;
    this.reconnectTimer = null;
    this.ohlcPollTimer = null;
    // ticker (Massive's `sym`, e.g. "ESU6") -> instrument_token (ours)
    this.tickerToToken = new Map();
    // instrument_token -> previous session's official settlement price, the
    // baseline for change/change_percent (same meaning as Kite's tick-packet
    // closePrice — see livePriceService.js's _processKiteTick). Refreshed
    // alongside the OHLC poll since it only actually changes once/day.
    this.tokenToPrevClose = new Map();
    // instrument_token -> { open, high, low } for today's session, refreshed
    // alongside the OHLC poll. Real Kite tick packets carry high/low/open in
    // every single tick (see livePriceService.js's _processKiteTick), which
    // is the only reason NSE/MCX ever populate those watchlist columns —
    // Massive's own Quote/Trade WS events carry neither, so without this the
    // columns stayed blank forever for GLOBAL/COMEX no matter how long a
    // client watched.
    this.tokenToOhlc = new Map();
    this._initialized = false;
    this._ohlcPollInFlight = false;
    // instrument_token -> Date.now() of the last CLIENT broadcast (not the
    // last tick) — see BROADCAST_THROTTLE_MS above.
    this.tokenToLastBroadcast = new Map();
  }

  /** True once per token per BROADCAST_THROTTLE_MS window — records the hit as a side effect. */
  _shouldBroadcast(token) {
    const now = Date.now();
    const last = this.tokenToLastBroadcast.get(token) || 0;
    if (now - last < BROADCAST_THROTTLE_MS) return false;
    this.tokenToLastBroadcast.set(token, now);
    return true;
  }

  async init(livePriceService) {
    if (!API_KEY) {
      console.warn('⚠️  [MassiveFeed] MASSIVE_API_KEY not set — feed disabled.');
      return;
    }

    this.livePriceService = livePriceService;
    await this._loadTickerMap();

    if (this.tickerToToken.size === 0) {
      console.warn('⚠️  [MassiveFeed] No tracked instruments found — run scripts/seedGlobalFutures.js first. Feed disabled.');
      return;
    }

    this._initialized = true;
    console.log(`📡 [MassiveFeed] Tracking ${this.tickerToToken.size} contract(s) (GLOBAL index futures + ${COMEX_METAL_SEGMENT})`);
    this._connect();

    this.ohlcPollTimer = setInterval(() => this._pollOhlc(), OHLC_POLL_INTERVAL_MS);
    this._pollOhlc();
  }

  /**
   * Day open/high/low/close for these instruments comes directly from
   * Massive's own REST aggregates endpoint, not derived from our own tick
   * stream — the current (possibly still-open) session's bar already has
   * live-updating open/high/low/close (only settlement_price stays 0 until
   * the session actually closes), so this is Massive's own authoritative
   * number, not an approximation built from whatever ticks we happened to
   * see. Kite's own OHLC quote API has no record of these non-Kite
   * instruments at all, which is why tradeController.js's High-Low
   * restriction check previously silently no-opped for everything this
   * service feeds.
   */
  async _pollOhlc() {
    // Guard against overlap: if a previous poll is still running (e.g. it's
    // eating multiple timeouts) when the next 20s interval fires, skip this
    // round rather than stacking another full pass on top of it.
    if (this._ohlcPollInFlight) return;
    this._ohlcPollInFlight = true;
    try {
      await this._refreshPrevClose();
      const entries = [...this.tickerToToken.entries()];
      for (let i = 0; i < entries.length; i += OHLC_POLL_BATCH_SIZE) {
        const batch = entries.slice(i, i + OHLC_POLL_BATCH_SIZE);
        await Promise.all(batch.map(([ticker, token]) => this._pollOneTicker(ticker, token)));
        if (i + OHLC_POLL_BATCH_SIZE < entries.length) {
          await new Promise((resolve) => setTimeout(resolve, OHLC_POLL_BATCH_GAP_MS));
        }
      }
    } finally {
      this._ohlcPollInFlight = false;
    }
  }

  async _pollOneTicker(ticker, token) {
    try {
      const { data } = await axios.get(`${REST_BASE_URL}/futures/v1/aggs/${ticker}`, {
        params: { apiKey: API_KEY, resolution: '1session', limit: 1, sort: 'window_start.desc' },
        timeout: 8000,
      });
      const bar = data.results && data.results[0];
      if (!bar) return;
      const update = {};
      if (Number(bar.open) > 0) update.ohlc_open = Number(bar.open);
      if (Number(bar.high) > 0) update.ohlc_high = Number(bar.high);
      if (Number(bar.low) > 0) update.ohlc_low = Number(bar.low);
      if (Number(bar.close) > 0) update.ohlc_close = Number(bar.close);
      if (Object.keys(update).length === 0) return;
      this.tokenToOhlc.set(token, {
        open: update.ohlc_open,
        high: update.ohlc_high,
        low: update.ohlc_low,
      });
      await KiteInstrument.updateOne({ instrument_token: token }, { $set: update });
    } catch (err) {
      console.warn(`⚠️  [MassiveFeed] OHLC poll failed for ${ticker}: ${err.message}`);
    }
  }

  async _refreshPrevClose() {
    const tokens = [...this.tickerToToken.values()];
    if (tokens.length === 0) return;
    const instruments = await KiteInstrument.find({ instrument_token: { $in: tokens } })
      .select('instrument_token settlement_price').lean();
    for (const inst of instruments) {
      if (Number(inst.settlement_price) > 0) {
        this.tokenToPrevClose.set(inst.instrument_token, Number(inst.settlement_price));
      }
    }
  }

  async _loadTickerMap() {
    // GLOBAL segment is shared with non-Massive instruments (GIFT Nifty,
    // legacy instruments) — name is the unambiguous key for "which GLOBAL
    // instruments does Massive actually feed". COMEX-FUT has no such
    // ambiguity, it's a dedicated segment.
    const instruments = await KiteInstrument.find({
      $or: [
        { segment: 'GLOBAL', name: { $in: GLOBAL_INDEX_NAMES } },
        { segment: COMEX_METAL_SEGMENT },
      ],
      deleted_at: null,
    }).select('instrument_token tradingsymbol').lean();

    this.tickerToToken.clear();
    for (const inst of instruments) {
      this.tickerToToken.set(inst.tradingsymbol, inst.instrument_token);
    }
  }

  /** Same convention as Kite's tick decoder: change = last - prevClose. */
  _changeFields(token, lastPrice) {
    const prevClose = this.tokenToPrevClose.get(token);
    if (!(prevClose > 0)) return {};
    const change = lastPrice - prevClose;
    return {
      change,
      change_percent: Math.max(-100, Math.min(1000, (change / prevClose) * 100)),
    };
  }

  /** Today's session open/high/low, refreshed every 20s by _pollOhlc. */
  _ohlcFields(token) {
    const ohlc = this.tokenToOhlc.get(token);
    if (!ohlc) return {};
    return { open: ohlc.open, high: ohlc.high, low: ohlc.low };
  }

  _connect() {
    if (!this._initialized) return;

    this.ws = new WebSocket(WS_URL);

    this.ws.on('open', () => {
      console.log('📡 [MassiveFeed] WebSocket connected, authenticating...');
    });

    this.ws.on('message', (raw) => this._handleMessage(raw));

    this.ws.on('error', (err) => {
      console.warn(`⚠️  [MassiveFeed] WebSocket error: ${err.message}`);
    });

    this.ws.on('close', () => {
      console.warn('⚠️  [MassiveFeed] WebSocket closed — reconnecting in 10s...');
      this._scheduleReconnect();
    });
  }

  _scheduleReconnect() {
    if (this.reconnectTimer) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      this._connect();
    }, RECONNECT_DELAY_MS);
  }

  _handleMessage(raw) {
    let events;
    try {
      const parsed = JSON.parse(raw.toString());
      events = Array.isArray(parsed) ? parsed : [parsed];
    } catch (_) {
      return;
    }

    for (const evt of events) {
      if (evt.ev === 'status') {
        if (evt.status === 'connected') {
          this.ws.send(JSON.stringify({ action: 'auth', params: API_KEY }));
        } else if (evt.status === 'auth_success') {
          console.log('✅ [MassiveFeed] Authenticated — subscribing...');
          const tickers = [...this.tickerToToken.keys()];
          const params = tickers.map(t => `Q.${t}`).concat(tickers.map(t => `T.${t}`)).join(',');
          this.ws.send(JSON.stringify({ action: 'subscribe', params }));
        } else if (evt.status === 'auth_failed') {
          console.error('❌ [MassiveFeed] Authentication failed — check MASSIVE_API_KEY.');
        }
        continue;
      }

      if (evt.ev === 'Q') this._handleQuote(evt);
      else if (evt.ev === 'T') this._handleTrade(evt);
    }
  }

  _handleQuote(evt) {
    const token = this.tickerToToken.get(evt.sym);
    if (!token) return;

    const bidPrice = Number(evt.bp);
    const askPrice = Number(evt.ap);
    if (!Number.isFinite(bidPrice) && !Number.isFinite(askPrice)) return;

    // Mid-price on every quote update — NOT "reuse the previously known
    // price if we have one", which froze the displayed price at whatever
    // the first tick happened to be and made Quote events a no-op forever
    // after. Every bid/ask move is real market movement and should show.
    const lastPrice = Number.isFinite(bidPrice) && Number.isFinite(askPrice)
      ? (bidPrice + askPrice) / 2
      : (Number.isFinite(bidPrice) ? bidPrice : askPrice);

    const lps = this.livePriceService;
    lps.latestPrices.set(token, lastPrice);
    lps.latestPrices.set(Number(token), lastPrice);

    const metricsEngine = require('./metricsEngine');
    metricsEngine.onTick(token, lastPrice, bidPrice, askPrice);
    // Pending limit/stop orders are matched off this, exactly as for Kite and
    // GIFT ticks. Missing until 23 Oct 2026, so no GLOBAL/COMEX limit or stop
    // order had ever filled (162038's YMZ6 BUY 52310.7 sat with price below it).
    require('./priceQueueService').publishPriceUpdate(token, lastPrice);

    if (!this._shouldBroadcast(token)) return;
    lps._broadcastToClients({
      type: 'ticks',
      data: [{
        instrument_token: token,
        last_price: lastPrice,
        bid_price: Number.isFinite(bidPrice) ? bidPrice : undefined,
        ask_price: Number.isFinite(askPrice) ? askPrice : undefined,
        ...this._changeFields(token, lastPrice),
        ...this._ohlcFields(token),
      }],
    });
  }

  _handleTrade(evt) {
    const token = this.tickerToToken.get(evt.sym);
    if (!token) return;

    const lastPrice = Number(evt.p);
    if (!Number.isFinite(lastPrice) || lastPrice <= 0) return;

    const lps = this.livePriceService;
    lps.latestPrices.set(token, lastPrice);
    lps.latestPrices.set(Number(token), lastPrice);

    const metricsEngine = require('./metricsEngine');
    metricsEngine.onTick(token, lastPrice, null, null);
    require('./priceQueueService').publishPriceUpdate(token, lastPrice);

    if (!this._shouldBroadcast(token)) return;
    lps._broadcastToClients({
      type: 'ticks',
      data: [{
        instrument_token: token,
        last_price: lastPrice,
        ...this._changeFields(token, lastPrice),
        ...this._ohlcFields(token),
      }],
    });
  }

  stop() {
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ohlcPollTimer) {
      clearInterval(this.ohlcPollTimer);
      this.ohlcPollTimer = null;
    }
    if (this.ws) {
      this.ws.removeAllListeners('close');
      this.ws.close();
      this.ws = null;
    }
  }
}

module.exports = new MassiveFuturesFeedService();
