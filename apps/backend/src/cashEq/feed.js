'use strict';

// Equity live prices — its OWN Kite WebSocket connection (Kite allows 3 per API key; the
// F&O feed uses 1). Equity ticks never enter the F&O tick path (metricsEngine, BullMQ
// order matching, missed-touch, the broadcast to every connected app): they're kept here
// and sent only to the people looking at equity screens ('cash_ticks' messages through
// livePriceService.broadcastToUser — the only F&O method used).
//
//   • Reads the stored Kite access token; never runs the Kite auto-login (F&O owns that).
//   • Subscribes to what equity needs (sources registered in priority order), capped at
//     MAX_TOKENS. Disconnects when equity is switched off or nothing needs prices.
//   • No self-reconnect loop: refresh() (every 30 s from jobs.js) reconnects if needed.

const WebSocket = require('ws');
const { EqQuote } = require('./models');
const { enabled } = require('./switch');

const MAX_TOKENS = Number(process.env.CASH_EQ_MAX_TOKENS) || 800;
const MAX_INTEREST_TOKENS = 200; // per viewer
const INTEREST_TTL_MS = 3 * 60 * 1000; // screens re-register every minute
const PUSH_MS = 1000;
const PERSIST_MS = 60 * 1000;

/**
 * Parse one Kite binary packet (NSE equity: prices in paise).
 *   0 token · 4 LTP · 8 last traded qty · 12 avg traded price · 16 day volume ·
 *   20 total buy qty · 24 total sell qty · 28 open · 32 high · 36 low · 40 close ·
 *   44 last trade time · 60 exchange time · 64.. market depth: 10 × (qty 4, price 4,
 *   orders 2, pad 2) — 5 buy levels then 5 sell levels.
 * Depth and volume feed the low-volume fill rules (orders fill only against real depth
 * and a share of the volume the exchange actually trades).
 */
function parseTick(p) {
  if (p.length < 8) return null;
  const token = p.readInt32BE(0);
  const t = { instrument_token: token, last_price: p.readInt32BE(4) / 100 };
  if (p.length >= 44) {
    t.last_qty = p.readInt32BE(8);
    t.avg_price = p.readInt32BE(12) / 100;
    t.volume = p.readInt32BE(16);
    t.total_buy_qty = p.readInt32BE(20);
    t.total_sell_qty = p.readInt32BE(24);
    t.open = p.readInt32BE(28) / 100;
    t.high = p.readInt32BE(32) / 100;
    t.low = p.readInt32BE(36) / 100;
    t.close = p.readInt32BE(40) / 100;
    t.change = Math.round((t.last_price - t.close) * 100) / 100;
    t.change_percent = t.close > 0.01 ? Math.round(((t.last_price - t.close) / t.close) * 10000) / 100 : 0;
  }
  if (p.length >= 64) {
    t.last_trade_ts = p.readInt32BE(44);
    t.exchange_ts = p.readInt32BE(60);
  }
  if (p.length >= 184) {
    const level = (i) => {
      const o = 64 + i * 12;
      return { qty: p.readInt32BE(o), price: p.readInt32BE(o + 4) / 100, orders: p.readInt16BE(o + 8) };
    };
    const real = (l) => l.qty > 0 && l.price > 0;
    t.depth = {
      buy: [0, 1, 2, 3, 4].map(level).filter(real),
      sell: [5, 6, 7, 8, 9].map(level).filter(real),
    };
    if (t.depth.buy[0]) t.bid_price = t.depth.buy[0].price;
    if (t.depth.sell[0]) t.ask_price = t.depth.sell[0].price;
  }
  return t;
}

/** Split one Kite binary message into ticks (1-byte messages are heartbeats). */
function parseMessage(buf) {
  if (!Buffer.isBuffer(buf) || buf.length < 2) return [];
  const n = buf.readInt16BE(0);
  const ticks = [];
  let off = 2;
  for (let i = 0; i < n && off + 2 <= buf.length; i++) {
    const len = buf.readInt16BE(off);
    off += 2;
    if (off + len > buf.length) break;
    const t = parseTick(buf.subarray(off, off + len));
    if (t) ticks.push(t);
    off += len;
  }
  return ticks;
}

class CashFeed {
  constructor() {
    this.ws = null;
    this.open = false;
    this.subscribed = new Set();
    this.quotes = new Map(); // token -> quote
    this.changed = new Set(); // tokens with a new tick since the last push
    this.unsaved = new Set(); // tokens with a new tick since the last save
    this.interest = new Map(); // viewer id -> { tokens:Set, until }
    this.sources = []; // [{ name, fn }] in priority order
    this.listeners = []; // equity order matcher (orders.onTicks)
    this.lastTickAt = 0;
    this.lastError = null;
    this.fails = 0; // connections that closed before any tick — backs off
    this.nextConnectAt = 0;
    this.dropped = 0; // tokens left out by the cap at the last refresh
    this.lps = null;
    this._refreshing = null;
    this._timers = [];
    // Injectable for tests.
    this.getAccessToken = async () => require('../services/kiteService').getStoredAccessToken();
    this.wsUrl = (token) => `wss://ws.kite.trade?api_key=${process.env.KITE_API_KEY}&access_token=${token}`;
  }

  /**
   * `fn` returns token numbers. Lower `priority` wins when the cap is reached (held and
   * pending scripts come before watchlists, watchlists before screens being viewed).
   */
  registerSource(name, fn, priority = 50) {
    this.sources = this.sources.filter((s) => s.name !== name).concat({ name, fn, priority }).sort((x, y) => x.priority - y.priority);
  }

  /** A viewer (equity screen) wants live prices for these tokens. */
  setInterest(viewerId, tokens) {
    const set = new Set((tokens || []).map(Number).filter((t) => Number.isInteger(t) && t > 0).slice(0, MAX_INTEREST_TOKENS));
    if (!set.size) this.interest.delete(String(viewerId));
    else this.interest.set(String(viewerId), { tokens: set, until: Date.now() + INTEREST_TTL_MS });
    return set.size;
  }

  _interestTokens() {
    const now = Date.now();
    const out = [];
    for (const [id, v] of this.interest) {
      if (v.until < now) this.interest.delete(id);
      else out.push(...v.tokens);
    }
    return out;
  }

  /** Tokens to subscribe: sources in priority order, then viewers' interest; capped. */
  async wantedTokens() {
    const ordered = [];
    const seen = new Set();
    const add = (t) => {
      const n = Number(t);
      if (Number.isInteger(n) && n > 0 && !seen.has(n)) { seen.add(n); ordered.push(n); }
    };
    for (const s of this.sources) {
      try {
        for (const t of (await s.fn()) || []) add(t);
      } catch (err) {
        console.log(`⚠️ [cashEq feed] source ${s.name} failed: ${err.message}`);
      }
    }
    for (const t of this._interestTokens()) add(t);
    this.dropped = Math.max(0, ordered.length - MAX_TOKENS);
    if (this.dropped) console.log(`⚠️ [cashEq feed] ${ordered.length} scripts wanted, cap ${MAX_TOKENS}: ${this.dropped} left out`);
    return ordered.slice(0, MAX_TOKENS);
  }

  /** Is there room for one more token (watchlist add)? */
  async hasRoomFor(token) {
    const wanted = await this.wantedTokens();
    return wanted.includes(Number(token)) || wanted.length < MAX_TOKENS;
  }

  refresh() {
    if (!this._refreshing) {
      this._refreshing = this._refresh().finally(() => { this._refreshing = null; });
    }
    return this._refreshing;
  }

  async _refresh() {
    if (!(await enabled())) return this.stop('equity switched off');
    const wanted = await this.wantedTokens();
    if (!wanted.length) return this.stop('nothing to watch');
    if (!this.ws) return Date.now() >= this.nextConnectAt ? this.connect(wanted) : undefined;
    if (this.open) this._applySubscription(wanted);
    return undefined;
  }

  async connect(wanted) {
    const token = await this.getAccessToken();
    if (!token) {
      this.lastError = 'No Kite access token';
      return;
    }
    const ws = new WebSocket(this.wsUrl(token));
    this.ws = ws;
    this.open = false;
    this._gotTick = false;
    this.subscribed.clear();
    ws.on('open', () => {
      if (ws !== this.ws) return;
      this.open = true;
      this.lastError = null;
      console.log(`📈 [cashEq feed] connected (${wanted.length} scripts)`);
      this._applySubscription(wanted);
    });
    ws.on('message', (data, isBinary) => {
      if (ws !== this.ws || isBinary === false) return; // text frames: Kite notices
      this._onTicks(parseMessage(Buffer.isBuffer(data) ? data : Buffer.from(data)));
    });
    ws.on('close', (code) => {
      if (ws !== this.ws) return;
      if (!this._gotTick) this.fails += 1;
      // Back off when Kite keeps closing us before any price: 30 s, 1, 2, 4 … max 10 min.
      this.nextConnectAt = this.fails ? Date.now() + Math.min(30000 * 2 ** (this.fails - 1), 600000) : 0;
      console.log(`⚠️ [cashEq feed] closed (${code}) — reconnects ${this.fails ? 'in ' + Math.round((this.nextConnectAt - Date.now()) / 1000) + ' s' : 'on the next refresh'}`);
      this.ws = null;
      this.open = false;
      this.subscribed.clear();
    });
    ws.on('error', (err) => {
      if (ws !== this.ws) return;
      this.lastError = err.message;
      console.log(`⚠️ [cashEq feed] error: ${err.message}`);
    });
  }

  _send(obj) {
    if (this.ws && this.open && this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(obj));
  }

  _applySubscription(wanted) {
    const want = new Set(wanted);
    const add = wanted.filter((t) => !this.subscribed.has(t));
    const remove = [...this.subscribed].filter((t) => !want.has(t));
    if (remove.length) {
      this._send({ a: 'unsubscribe', v: remove });
      remove.forEach((t) => this.subscribed.delete(t));
    }
    if (add.length) {
      this._send({ a: 'subscribe', v: add });
      this._send({ a: 'mode', v: ['full', add] }); // full: best bid/ask for fills
      add.forEach((t) => this.subscribed.add(t));
    }
  }

  _onTicks(ticks) {
    if (!ticks.length) return;
    const at = new Date();
    for (const t of ticks) {
      this.quotes.set(t.instrument_token, { ...(this.quotes.get(t.instrument_token) || {}), ...t, at });
      this.changed.add(t.instrument_token);
      this.unsaved.add(t.instrument_token);
    }
    this.lastTickAt = Date.now();
    this._gotTick = true;
    this.fails = 0;
    for (const fn of this.listeners) {
      try { fn(ticks); } catch (err) { console.log(`⚠️ [cashEq feed] listener: ${err.message}`); }
    }
  }

  /** Called with every batch of ticks (after the quotes are updated). */
  addListener(fn) {
    if (!this.listeners.includes(fn)) this.listeners.push(fn);
  }

  stop(reason) {
    if (this.ws) {
      console.log(`📈 [cashEq feed] disconnecting: ${reason}`);
      const ws = this.ws;
      this.ws = null;
      this.open = false;
      ws.removeAllListeners();
      ws.on('error', () => {});
      try { ws.terminate(); } catch (_) { /* already closed */ }
    }
    this.subscribed.clear();
  }

  /** Latest quote per token (live, else last saved). */
  getQuotes(tokens) {
    const out = [];
    for (const t of tokens) {
      const q = this.quotes.get(Number(t));
      if (q) out.push(q);
    }
    return out;
  }

  /** Send changed quotes to each viewer who asked for them. */
  push() {
    if (!this.changed.size || !this.lps) { this.changed.clear(); return 0; }
    let sent = 0;
    const now = Date.now();
    for (const [viewer, v] of this.interest) {
      if (v.until < now) continue;
      const data = [];
      for (const t of v.tokens) if (this.changed.has(t)) data.push(this.quotes.get(t));
      if (data.length) {
        this.lps.broadcastToUser(viewer, { type: 'cash_ticks', data });
        sent++;
      }
    }
    this.changed.clear();
    return sent;
  }

  async persist() {
    if (!this.unsaved.size) return 0;
    const tokens = [...this.unsaved];
    this.unsaved.clear();
    const ops = tokens.map((t) => {
      const { instrument_token, exchange_ts, ...q } = this.quotes.get(t);
      return { updateOne: { filter: { instrument_token }, update: { $set: q }, upsert: true } };
    });
    await EqQuote.bulkWrite(ops, { ordered: false });
    return ops.length;
  }

  async loadSaved() {
    const rows = await EqQuote.find({}).lean();
    for (const r of rows) {
      const { _id, ...q } = r;
      if (!this.quotes.has(r.instrument_token)) this.quotes.set(r.instrument_token, q);
    }
    return rows.length;
  }

  status() {
    return {
      connected: this.open,
      subscribed: this.subscribed.size,
      cap: MAX_TOKENS,
      left_out_by_cap: this.dropped,
      viewers: this.interest.size,
      quotes_known: this.quotes.size,
      last_tick_at: this.lastTickAt ? new Date(this.lastTickAt) : null,
      last_error: this.lastError,
    };
  }

  /** Background timers (jobs.js). */
  start(lps) {
    this.lps = lps;
    this.loadSaved().catch((e) => console.log(`⚠️ [cashEq feed] load saved quotes: ${e.message}`));
    const every = (ms, fn) => { const h = setInterval(() => { Promise.resolve().then(fn).catch((e) => console.log(`⚠️ [cashEq feed] ${e.message}`)); }, ms); h.unref?.(); this._timers.push(h); };
    every(PUSH_MS, () => this.push());
    every(PERSIST_MS, () => this.persist());
  }

  shutdown() {
    this._timers.forEach(clearInterval);
    this._timers = [];
    this.stop('shutdown');
  }
}

const feed = new CashFeed();
module.exports = feed;
module.exports.CashFeed = CashFeed;
module.exports.parseTick = parseTick;
module.exports.parseMessage = parseMessage;
module.exports.MAX_TOKENS = MAX_TOKENS;
