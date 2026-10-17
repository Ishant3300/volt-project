'use strict';

/**
 * Practice mode — feeds simulated prices (simPrice.js) into the normal price
 * pipeline (livePriceService._applyTicks → latestPrices, metricsEngine,
 * pending-order matching, phones). See docs/practice-trading.md.
 *
 * - One anchor {price, slot} per contract in the practice database
 *   (`simanchors`), created from the contract's last known close the first
 *   time it is needed, rolled forward nightly.
 * - Every 30-minute slot change, publishes a simulated tick for every contract
 *   a practice user watches, holds, or has a pending order on.
 * - At each market's close writes the simulated close as the contract's
 *   settlement price (source PRACTICE_SIM) so settlement / expiry use it.
 *
 * Only ever started when PRACTICE_MODE=1.
 */
const mongoose = require('mongoose');
const sim = require('./simPrice');
const { STEP_MIN } = require('../../config/practice');

const META_FIELDS = 'instrument_token segment exchange name instrument_type tick_size last_price settlement_price ohlc_close';

class SimFeed {
  constructor() {
    this.meta = new Map();
    this.anchors = new Map();
    this.lastSlot = null;
    this.timer = null;
    this.lps = null;
    this.metricsEngine = null;
  }

  _anchorCol() { return mongoose.connection.db.collection('simanchors'); }
  _instCol() { return mongoose.connection.db.collection('kiteinstruments'); }

  async init(livePriceService, metricsEngine) {
    this.lps = livePriceService;
    this.metricsEngine = metricsEngine;
    await this._anchorCol().createIndex({ instrument_token: 1 }, { unique: true });
    await this.publish(true);
    // Cheap check every 20 s; real work only when the 30-minute slot changes.
    this.timer = setInterval(() => this.publish(false).catch((e) => console.error('[simFeed] publish failed:', e.message)), 20000);
    console.log(`🎲 [simFeed] simulated prices running (step ${STEP_MIN} min)`);
  }

  stop() { if (this.timer) clearInterval(this.timer); }

  async _metaFor(token) {
    const key = String(token);
    if (this.meta.has(key)) return this.meta.get(key);
    const m = await this._instCol().findOne({ instrument_token: key }, { projection: Object.fromEntries(META_FIELDS.split(' ').map((f) => [f, 1])) });
    if (m) this.meta.set(key, m);
    return m;
  }

  /** Anchor for a contract — created from its last known close on first use. */
  async anchorFor(token) {
    const key = String(token);
    if (this.anchors.has(key)) return this.anchors.get(key);
    let a = await this._anchorCol().findOne({ instrument_token: key });
    if (!a) {
      const m = await this._metaFor(key);
      const base = Number(m?.settlement_price) || Number(m?.last_price) || Number(m?.ohlc_close) || 0;
      if (!(base > 0)) return null; // no price to start from — contract stays without a quote
      const doc = { instrument_token: key, price: base, slot: sim.slotOf(Date.now(), STEP_MIN), created_at: new Date() };
      await this._anchorCol().updateOne({ instrument_token: key }, { $setOnInsert: doc }, { upsert: true });
      a = await this._anchorCol().findOne({ instrument_token: key });
    }
    this.anchors.set(key, { price: a.price, slot: a.slot });
    return this.anchors.get(key);
  }

  /** Simulated ticks (live-feed shape) for these contracts at `now`. */
  async ticksFor(tokens, now = Date.now()) {
    const out = [];
    for (const t of tokens) {
      const meta = await this._metaFor(t);
      if (!meta) continue;
      const anchor = await this.anchorFor(t);
      if (!anchor) continue;
      out.push(sim.tickAt(anchor, meta, now, STEP_MIN));
    }
    return out;
  }

  /** Simulated price only (fills, depth, quotes). */
  async priceFor(token, now = Date.now()) {
    const [tick] = await this.ticksFor([token], now);
    return tick || null;
  }

  _tokensToPublish() {
    const set = new Set();
    for (const t of this.lps?.subscribedTokens || []) set.add(String(t));
    for (const t of this.lps?.pendingTokensCache || []) set.add(String(t));
    try { for (const t of this.metricsEngine?.getPositionTokens?.() || []) set.add(String(t)); } catch (_) { /* metrics not ready */ }
    return [...set];
  }

  /** Push the current slot's prices when the slot changes (or `force`). */
  async publish(force) {
    const slot = sim.slotOf(Date.now(), STEP_MIN);
    if (!force && slot === this.lastSlot) return;
    this.lastSlot = slot;
    const ticks = await this.ticksFor(this._tokensToPublish());
    if (ticks.length) this.lps._applyTicks(ticks);
  }

  /**
   * Market close: write the simulated close as each anchored contract's
   * settlement price for `dateIst` (YYYY-MM-DD) — kinds: 'nse' | 'mcx' | 'global'.
   */
  async writeClosePrices(kinds, dateIst) {
    const anchors = await this._anchorCol().find({}).toArray();
    let n = 0;
    for (const a of anchors) {
      const meta = await this._metaFor(a.instrument_token);
      if (!meta) continue;
      const kind = sim.kindOf(meta);
      const group = kind === 'mcx' ? 'mcx' : kind === 'global' ? 'global' : 'nse';
      if (!kinds.includes(group)) continue;
      const price = sim.priceAt({ price: a.price, slot: a.slot }, meta, Date.now(), STEP_MIN);
      await this._instCol().updateOne({ instrument_token: a.instrument_token }, {
        $set: { settlement_price: price, settlement_price_date: new Date(`${dateIst}T00:00:00+05:30`), settlement_price_source: 'PRACTICE_SIM', last_price: price, ohlc_close: price },
      });
      n++;
    }
    return n;
  }

  /** Nightly: move every anchor to "now" so the walk sums stay short. */
  async rollAnchors() {
    const now = Date.now();
    const slot = sim.slotOf(now, STEP_MIN);
    const anchors = await this._anchorCol().find({}).toArray();
    for (const a of anchors) {
      const meta = await this._metaFor(a.instrument_token);
      if (!meta || a.slot >= slot) continue;
      const price = sim.priceAt({ price: a.price, slot: a.slot }, meta, now, STEP_MIN);
      await this._anchorCol().updateOne({ _id: a._id }, { $set: { price, slot, rolled_at: new Date() } });
      this.anchors.set(String(a.instrument_token), { price, slot });
    }
    return anchors.length;
  }
}

module.exports = new SimFeed();
