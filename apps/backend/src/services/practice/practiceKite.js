'use strict';

/**
 * Practice mode (docs/practice-trading.md): the single choke point between the
 * practice backend and Kite. kiteService exports `wrap(new KiteService())`
 * when PRACTICE_MODE=1, so every caller — order fills, the High-Low check,
 * quotes, option chain, depth, charts, after-close refreshes — gets
 * SIMULATED data in Kite's own response shapes, and nothing can reach Kite:
 * no request, no login, no token (Kite allows one session per API key, a
 * practice login would log the live backend out).
 */
const mongoose = require('mongoose');
const sim = require('./simPrice');
const { STEP_MIN } = require('../../config/practice');

const BLOCKED = 'Kite is not available in practice mode';
const blocked = async () => { throw new Error(BLOCKED); };

const INTERVAL_MIN = { minute: 1, '3minute': 3, '5minute': 5, '10minute': 10, '15minute': 15, '30minute': 30, '60minute': 60, day: 1440 };

function instCol() { return mongoose.connection.db.collection('kiteinstruments'); }

/** "EXCH:SYMBOL" keys → instrument docs. */
async function resolveKeys(keys) {
  const pairs = keys.map((k) => { const i = String(k).indexOf(':'); return { key: k, exchange: String(k).slice(0, i), tradingsymbol: String(k).slice(i + 1) }; });
  const docs = await instCol().find({ $or: pairs.map((p) => ({ exchange: p.exchange, tradingsymbol: p.tradingsymbol })) }).toArray();
  const byPair = new Map(docs.map((d) => [`${d.exchange}:${d.tradingsymbol}`, d]));
  return pairs.map((p) => ({ key: p.key, doc: byPair.get(`${p.exchange}:${p.tradingsymbol}`) })).filter((x) => x.doc);
}

function simFeed() { return require('./simFeed'); }

/** Kite-shaped quote for one instrument doc. */
async function quoteFor(doc, type) {
  const anchor = await simFeed().anchorFor(doc.instrument_token);
  if (!anchor) return null;
  const t = sim.tickAt(anchor, doc, Date.now(), STEP_MIN);
  const base = { instrument_token: Number(doc.instrument_token), last_price: t.last_price };
  if (type === 'ltp') return base;
  const ohlc = { open: t.open, high: t.high, low: t.low, close: t.close };
  if (type === 'ohlc') return { ...base, ohlc };
  return {
    ...base, ohlc, net_change: t.change, volume: 0, average_price: t.last_price, oi: 0,
    timestamp: new Date().toISOString(), last_trade_time: new Date().toISOString(),
    depth: {
      buy: [{ price: t.bid_price, quantity: 1, orders: 1 }],
      sell: [{ price: t.ask_price, quantity: 1, orders: 1 }],
    },
  };
}

function wrap(svc) {
  const orig = { storeMarketQuotes: svc.storeMarketQuotes.bind(svc) };
  Object.assign(svc, {
    practice: true,
    // Never a real token; nothing that uses it can reach Kite (all overridden below).
    getStoredAccessToken: async () => 'practice-simulated',
    isAuthenticated: async () => true,
    exchangeToken: blocked,
    storeAccessToken: blocked,
    validateAccessToken: async () => false,
    clearSession: async () => ({ cleared: false, reason: BLOCKED }),
    fetchInstrumentsFromKite: blocked,
    fetchAndStoreAllInstruments: blocked,
    getProfile: blocked,
    getLoginUrl: () => { throw new Error(BLOCKED); },

    async getMarketQuotes(instruments, quoteType = 'ltp') {
      const out = {};
      for (const { key, doc } of await resolveKeys(instruments || [])) {
        const q = await quoteFor(doc, quoteType);
        if (q) out[key] = q;
      }
      return out;
    },

    // Stored quotes are irrelevant in practice — answer with the simulation.
    storeMarketQuotes: orig.storeMarketQuotes,
    async getLatestQuotes(instruments = null, limit = 100) {
      const filter = instruments && instruments.length ? { instrument_token: { $in: instruments.map(String) } } : {};
      const docs = await instCol().find(filter).limit(limit).toArray();
      const out = [];
      for (const d of docs) {
        const q = await quoteFor(d, 'ohlc');
        if (q) out.push({ instrument_token: q.instrument_token, tradingsymbol: d.tradingsymbol, exchange: d.exchange, last_price: q.last_price, ohlc: q.ohlc, timestamp: new Date() });
      }
      return out;
    },

    async getMarketDepth(exchange, tradingsymbol) {
      const key = `${exchange}:${tradingsymbol}`;
      return svc.getMarketQuotes([key], 'ohlc');
    },

    async getHistoricalData(instrumentToken, interval, fromDate, toDate) {
      const doc = await instCol().findOne({ instrument_token: String(instrumentToken) });
      if (!doc) return [];
      const anchor = await simFeed().anchorFor(instrumentToken);
      if (!anchor) return [];
      const parse = (v, end) => {
        const s = String(v).trim();
        const iso = /^\d{4}-\d{2}-\d{2}$/.test(s) ? `${s}T${end ? '23:59:59' : '00:00:00'}+05:30` : s.replace(' ', 'T') + (/[zZ+]/.test(s.slice(10)) ? '' : '+05:30');
        return Date.parse(iso);
      };
      const from = parse(fromDate, false);
      const to = Math.min(parse(toDate, true), Date.now());
      if (!(from <= to)) return [];
      return sim.candles(anchor, doc, from, to, INTERVAL_MIN[interval] || 5, STEP_MIN).map((c) => ({ ...c, oi: 0 }));
    },
  });
  return svc;
}

module.exports = { wrap, BLOCKED };
