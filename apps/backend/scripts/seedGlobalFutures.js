/**
 * Seed CME/CBOT index futures and COMEX metal futures from Massive's REST API
 * (Products + Contracts) as KiteInstrument records.
 *
 * These are NOT Kite instruments — Kite has no data for them at all. They're
 * fed live by massiveFuturesFeedService.js's WebSocket connection, not Kite's
 * tick feed. Reusing the KiteInstrument model (rather than a new one) keeps
 * every existing trade/margin/brokerage/watchlist code path working
 * unchanged, since none of it assumes the source is actually Kite.
 *
 * instrument_token scheme: since these have no native Kite token, tokens are
 * deterministically derived from (product, contract YYYYMM) so re-running
 * this script is idempotent — the same contract always upserts the same
 * document rather than creating a duplicate. Namespaced well above any real
 * Kite token range to guarantee no collision.
 *
 * Usage: node scripts/seedGlobalFutures.js
 * Requires MASSIVE_API_KEY in the environment.
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const axios = require('axios');
const connectDatabase = require('../src/database/database');
const KiteInstrument = require('../src/models/KiteInstrument');

const API_KEY = process.env.MASSIVE_API_KEY;
const BASE_URL = 'https://api.massive.com';
const CONTRACTS_PER_PRODUCT = 3; // front month + next 2, enough for rollover's own next-expiry lookup

// name/exchange/segment are ours to choose (Massive doesn't return a
// tradable display name for the product); index/name come from Massive's
// Products response, contract specs from its Contracts response.
// Index futures (ES/NQ/YM/RTY/NKD) deliberately use the platform's existing
// 'GLOBAL' segment/exchange — not a new 'CME-FUT' string — so they inherit
// every piece of GLOBAL-aware code that already exists (instrumentSearchService's
// search-category bucket, exchanges_allowed, wallet category) with zero
// further changes needed anywhere else. A brand-new segment string that
// nothing else recognized was the actual root cause of "shows in some
// places, not others." COMEX (GC/SI/HG) stays its own distinct segment —
// it already has its own dedicated wallet pool, unlike the index futures
// which share GLOBAL with everything else non-NSE/MCX/COMEX.
const PRODUCTS = [
  { code: 'ES', name: 'E-mini S&P 500', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 0 },
  { code: 'NQ', name: 'E-mini Nasdaq-100', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 1 },
  { code: 'YM', name: 'E-mini Dow Jones', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 2 },
  { code: 'RTY', name: 'E-mini Russell 2000', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 3 },
  { code: 'NKD', name: 'Nikkei 225 (USD)', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 4 },
  // DVE (FTSE Developed Europe) dropped — zero session bars across every
  // listed contract month in Massive's data, confirmed live. No European
  // index in this set for now.
  { code: 'GC', name: 'Gold', exchange: 'COMEX', segment: 'COMEX-FUT', tokenIndex: 6 },
  { code: 'SI', name: 'Silver', exchange: 'COMEX', segment: 'COMEX-FUT', tokenIndex: 7 },
  { code: 'HG', name: 'Copper', exchange: 'COMEX', segment: 'COMEX-FUT', tokenIndex: 8 },
];

const TOKEN_BASE = 9_000_000_000_000;

function tokenFor(tokenIndex, expiry) {
  const yyyymm = expiry.getUTCFullYear() * 100 + (expiry.getUTCMonth() + 1);
  return String(TOKEN_BASE + tokenIndex * 100_000_000 + yyyymm);
}

async function fetchProductSpec(code) {
  const { data } = await axios.get(`${BASE_URL}/futures/v1/products`, {
    params: { apiKey: API_KEY, product_code: code, type: 'single', sort: 'date.desc', limit: 1 },
  });
  return data.results && data.results[0];
}

async function fetchUpcomingContracts(code) {
  const today = new Date().toISOString().slice(0, 10);
  const { data } = await axios.get(`${BASE_URL}/futures/v1/contracts`, {
    params: { apiKey: API_KEY, product_code: code, active: true, date: today, limit: 1000 },
  });
  const results = data.results || [];
  const outrightRe = new RegExp(`^${code}[FGHJKMNQUVXZ][0-9]$`);
  const seen = new Map();
  for (const r of results) {
    if (outrightRe.test(r.ticker) && r.last_trade_date >= today && !seen.has(r.ticker)) {
      seen.set(r.ticker, r);
    }
  }
  return [...seen.values()]
    .sort((a, b) => a.last_trade_date.localeCompare(b.last_trade_date))
    .slice(0, CONTRACTS_PER_PRODUCT);
}

async function run() {
  if (!API_KEY) {
    console.error('❌ MASSIVE_API_KEY not set in environment.');
    process.exit(1);
  }

  await connectDatabase();

  let upserted = 0;
  for (const product of PRODUCTS) {
    console.log(`\n📡 [SeedGlobalFutures] ${product.code} — ${product.name}`);
    const spec = await fetchProductSpec(product.code);
    if (!spec) {
      console.warn(`⚠️  No product spec found for ${product.code}, skipping.`);
      continue;
    }
    const lotSize = Number(spec.unit_of_measure_qty) || 1;

    const contracts = await fetchUpcomingContracts(product.code);
    if (contracts.length === 0) {
      console.warn(`⚠️  No active contracts found for ${product.code}, skipping.`);
      continue;
    }

    for (const contract of contracts) {
      const expiry = new Date(contract.last_trade_date + 'T00:00:00.000Z');
      const token = tokenFor(product.tokenIndex, expiry);

      await KiteInstrument.updateOne(
        { instrument_token: token },
        {
          $set: {
            exchange_token: token,
            tradingsymbol: contract.ticker,
            name: product.code,
            raw_name: product.code,
            display_name: `${product.name} ${contract.ticker}`,
            expiry,
            strike: 0,
            tick_size: Number(contract.trade_tick_size) || 0,
            lot_size: lotSize,
            instrument_type: 'FUT',
            segment: product.segment,
            exchange: product.exchange,
            is_active: true,
          },
          $setOnInsert: {
            enabled: true,
            deleted_at: null,
          },
        },
        { upsert: true }
      );
      console.log(`   ✅ ${contract.ticker} (token ${token}, expiry ${contract.last_trade_date}, lot ${lotSize}, tick ${contract.trade_tick_size})`);
      upserted += 1;
    }
  }

  console.log(`\n📊 [SeedGlobalFutures] Done — ${upserted} contract(s) upserted.`);
  await mongoose.connection.close();
  process.exit(0);
}

run().catch((err) => {
  console.error('❌ [SeedGlobalFutures] Failed:', err.message);
  process.exit(1);
});
