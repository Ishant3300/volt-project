/**
 * Official settlement price for GLOBAL index futures + COMEX instruments
 * (Massive.com).
 *
 * NSE/BSE/MCX get their official close from a daily bhavcopy file
 * (bhavcopyService.js). Nothing equivalent exists for the GLOBAL/COMEX-FUT
 * instruments added via scripts/seedGlobalFutures.js — without this, weekly
 * settlement's expectedPriceDateForInstrument/hasOfficialSettlementAuthority
 * (settlementService.js) reject every open position on these instruments,
 * which fails the ENTIRE settlement run, not just that position.
 *
 * Massive's session-resolution Aggregate Bars endpoint returns a real
 * `settlement_price` per completed session — the equivalent of a bhavcopy
 * official close. This fetches the latest completed session per tracked
 * contract and writes it the same way bhavcopyService does: settlement_price
 * / settlement_price_date / settlement_price_source on the KiteInstrument
 * record, plus applying it to the live-price caches so after-hours reads see
 * a fresh number instead of a stale live tick.
 *
 * Scheduling: run daily, safely after the latest Massive session close
 * (see cronService.js) — by the time weekly settlement runs (Sunday), the
 * most recently completed session for these instruments is Friday's, the
 * same calendar date NSE/MCX settle on, so this reuses the existing
 * price_dates.global exact-date-match model rather than needing a separate
 * date-resolution scheme.
 */

const axios = require('axios');
const KiteInstrument = require('../models/KiteInstrument');
const { toIndiaDateOnly } = require('../utils/settlementDates');
const { GLOBAL_INDEX_NAMES, COMEX_METAL_SEGMENT } = require('../constants/massiveInstruments');

const API_KEY = process.env.MASSIVE_API_KEY;
const BASE_URL = 'https://api.massive.com';

async function fetchLatestSessionSettlement(ticker) {
  // limit=1 would always return TODAY's still-in-progress session, whose
  // settlement_price is 0 until it closes — fetch a small window of recent
  // bars and take the first one that's actually settled.
  const { data } = await axios.get(`${BASE_URL}/futures/v1/aggs/${ticker}`, {
    params: { apiKey: API_KEY, resolution: '1session', limit: 5, sort: 'window_start.desc' },
  });
  const bar = (data.results || []).find(r => Number(r.settlement_price) > 0);
  if (!bar) return null;
  return { settlementPrice: Number(bar.settlement_price), sessionEndDate: bar.session_end_date };
}

async function fetchAndApplyMassiveSettlement(options = {}) {
  if (!API_KEY) {
    console.warn('⚠️  [MassiveSettlement] MASSIVE_API_KEY not set — skipping.');
    return { updated: 0 };
  }

  const instruments = await KiteInstrument.find({
    $or: [
      { segment: 'GLOBAL', name: { $in: GLOBAL_INDEX_NAMES } },
      { segment: COMEX_METAL_SEGMENT },
    ],
    deleted_at: null,
    is_active: true,
  }).select('instrument_token tradingsymbol exchange').lean();

  let updated = 0;
  const applyToLivePrices = options.applyToLivePrices !== false;
  const ticks = [];

  for (const inst of instruments) {
    try {
      const result = await fetchLatestSessionSettlement(inst.tradingsymbol);
      if (!result) continue;

      const settlementDate = toIndiaDateOnly(result.sessionEndDate);
      const source = `MASSIVE_OFFICIAL_SESSION_${inst.exchange}`;

      await KiteInstrument.updateOne(
        { instrument_token: inst.instrument_token },
        {
          $set: {
            settlement_price: result.settlementPrice,
            settlement_price_date: settlementDate,
            settlement_price_source: source,
            settlement_price_updated_at: new Date(),
          },
        }
      );
      updated += 1;
      ticks.push({ token: inst.instrument_token, price: result.settlementPrice });
      console.log(`   ✅ [MassiveSettlement] ${inst.tradingsymbol} → ${result.settlementPrice} (session ${result.sessionEndDate})`);
    } catch (err) {
      console.warn(`⚠️  [MassiveSettlement] Failed for ${inst.tradingsymbol}: ${err.message}`);
    }
  }

  if (ticks.length > 0 && applyToLivePrices) {
    try {
      const livePriceService = require('./livePriceService');
      const metricsEngine = require('./metricsEngine');
      if (livePriceService && livePriceService._broadcastToClients) {
        const broadcastTicks = [];
        for (const { token, price } of ticks) {
          // Deliberately NOT writing to livePriceService._settlementPrices —
          // that map exists so a client subscribing while NSE/MCX is closed
          // sees the last official close instead of a stale pre-close tick.
          // GLOBAL/COMEX (Massive) trade near-continuously; the WS feed's
          // own latestPrices is refreshed every few seconds whenever the
          // market is open, so it's always more current than yesterday's
          // settlement. Populating _settlementPrices here made every fresh
          // subscribe permanently show yesterday's close (no change field,
          // stale price) until a live tick happened to arrive and overwrite
          // it — exactly the "stale then jumps after a minute" symptom.
          livePriceService.latestPrices.set(token, price);
          livePriceService.latestPrices.set(Number(token), price);
          metricsEngine.onTick(token, price, price, price);
          broadcastTicks.push({ instrument_token: token, last_price: price, bid_price: price, ask_price: price, is_settlement: true });
        }
        livePriceService._broadcastToClients({ type: 'ticks', data: broadcastTicks });
      }
    } catch (_) {
      console.log('   [MassiveSettlement] Broadcast skipped (standalone mode or no clients connected).');
    }
  }

  console.log(`📊 [MassiveSettlement] Done — ${updated}/${instruments.length} instrument(s) updated.`);
  return { updated, total: instruments.length };
}

module.exports = { fetchAndApplyMassiveSettlement };
