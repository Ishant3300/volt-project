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

class MassiveFuturesFeedService {
  constructor() {
    this.livePriceService = null;
    this.ws = null;
    this.reconnectTimer = null;
    this.ohlcPollTimer = null;
    // ticker (Massive's `sym`, e.g. "ESU6") -> instrument_token (ours)
    this.tickerToToken = new Map();
    this._initialized = false;
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
    const entries = [...this.tickerToToken.entries()];
    await Promise.all(entries.map(async ([ticker, token]) => {
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
        await KiteInstrument.updateOne({ instrument_token: token }, { $set: update });
      } catch (err) {
        console.warn(`⚠️  [MassiveFeed] OHLC poll failed for ${ticker}: ${err.message}`);
      }
    }));
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

    const lps = this.livePriceService;
    const lastKnown = lps.latestPrices.get(token);
    const lastPrice = lastKnown || (Number.isFinite(bidPrice) ? bidPrice : askPrice);
    lps.latestPrices.set(token, lastPrice);
    lps.latestPrices.set(Number(token), lastPrice);

    const metricsEngine = require('./metricsEngine');
    metricsEngine.onTick(token, lastPrice, bidPrice, askPrice);

    lps._broadcastToClients({
      type: 'ticks',
      data: [{
        instrument_token: token,
        last_price: lastPrice,
        bid_price: Number.isFinite(bidPrice) ? bidPrice : undefined,
        ask_price: Number.isFinite(askPrice) ? askPrice : undefined,
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
    this._updateDayRange(token, lastPrice);

    const metricsEngine = require('./metricsEngine');
    metricsEngine.onTick(token, lastPrice, null, null);

    lps._broadcastToClients({
      type: 'ticks',
      data: [{ instrument_token: token, last_price: lastPrice }],
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
