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
 * COMEX metals (26 Oct 2026): only each metal's MAIN months are loaded —
 * Gold Feb/Apr/Jun/Aug/Oct/Dec, Silver and Copper Mar/May/Jul/Sep/Dec. The
 * in-between months barely trade (GCX6 38 trades on a day GCZ6 had 26,273),
 * so their prices looked frozen. A main-month contract's platform expiry is
 * its FIRST NOTICE DAY (last weekday of the month before delivery) — when
 * the market moves on to the next main month — so this platform's expiry
 * open/cut (config/expiryRules.js) rolls clients while the price is live.
 * The token comes from the contract's DELIVERY month, not that expiry, so it
 * matches every contract seeded before.
 *
 * Usage: node scripts/seedGlobalFutures.js [--dry-run] [--retire-comex-off-months]
 *   --dry-run                  print what would change, write nothing
 *   --retire-comex-off-months  also hide active COMEX contracts that aren't
 *                              among the loaded main months (only if nobody
 *                              holds them) and move watchlists to the
 *                              nearest loaded contract of that metal
 * Runs weekly (server crontab) so new contracts are always there; the live
 * feed subscribes to them on its own (massiveFuturesFeedService.js).
 * Requires MASSIVE_API_KEY in the environment.
 */

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });
const mongoose = require('mongoose');
const axios = require('axios');
const connectDatabase = require('../src/database/database');
const KiteInstrument = require('../src/models/KiteInstrument');

const API_KEY = process.env.MASSIVE_API_KEY;
const BASE_URL = 'https://api.massive.com';
const DRY_RUN = process.argv.includes('--dry-run');
const RETIRE_COMEX = process.argv.includes('--retire-comex-off-months');
const MONTH_CODES = 'FGHJKMNQUVXZ'; // Jan..Dec
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
// friendlyName is what gets written to KiteInstrument.name/raw_name — shown
// to users combined with the expiry date (mobile's userFriendlyName getter),
// so it needs to read cleanly on its own ("S&P 500 18 September", not
// "ES 18 September"). Matches the exact naming convention this platform
// already uses for the old Zerodha global cash indices (Nasdaq 100/S&P 500/
// Dow Jones 30), for consistency. `code` stays the internal short product
// code used for Massive's own API calls — unrelated to display.
const PRODUCTS = [
  { code: 'ES', name: 'E-mini S&P 500', friendlyName: 'S&P 500', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 0 },
  { code: 'NQ', name: 'E-mini Nasdaq-100', friendlyName: 'Nasdaq 100', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 1 },
  { code: 'YM', name: 'E-mini Dow Jones', friendlyName: 'Dow Jones 30', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 2 },
  { code: 'RTY', name: 'E-mini Russell 2000', friendlyName: 'Russell 2000', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 3 },
  { code: 'NKD', name: 'Nikkei 225 (USD)', friendlyName: 'Nikkei 225', exchange: 'GLOBAL', segment: 'GLOBAL', tokenIndex: 4 },
  // DVE (FTSE Developed Europe) dropped — zero session bars across every
  // listed contract month in Massive's data, confirmed live. No European
  // index in this set for now.
  // mainMonths: the only months loaded; expiry = first notice day (see top).
  { code: 'GC', name: 'Gold', friendlyName: 'Gold', exchange: 'COMEX', segment: 'COMEX-FUT', tokenIndex: 6, mainMonths: 'GJMQVZ' },
  { code: 'SI', name: 'Silver', friendlyName: 'Silver', exchange: 'COMEX', segment: 'COMEX-FUT', tokenIndex: 7, mainMonths: 'HKNUZ' },
  { code: 'HG', name: 'Copper', friendlyName: 'Copper', exchange: 'COMEX', segment: 'COMEX-FUT', tokenIndex: 8, mainMonths: 'HKNUZ' },
];

const TOKEN_BASE = 9_000_000_000_000;

/** Contract's delivery month as YYYYMM — month from the ticker's month code, year from its last trade date. */
function contractMonth(contract, code) {
  const month = MONTH_CODES.indexOf(contract.ticker.charAt(code.length)) + 1;
  return Number(contract.last_trade_date.slice(0, 4)) * 100 + month;
}

// Same tokens as before for every existing contract: their expiry always fell
// in the delivery month, which is what the token encoded.
function tokenFor(tokenIndex, yyyymm) {
  return String(TOKEN_BASE + tokenIndex * 100_000_000 + yyyymm);
}

/** Last weekday of the month before the delivery month (COMEX metals first notice day), as UTC midnight. */
function firstNoticeDay(yyyymm) {
  const d = new Date(Date.UTC(Math.floor(yyyymm / 100), (yyyymm % 100) - 1, 0)); // day 0 = last day of the previous month
  while (d.getUTCDay() === 0 || d.getUTCDay() === 6) d.setUTCDate(d.getUTCDate() - 1);
  return d;
}

/** Platform expiry: first notice day for main-month metals, the last trade date otherwise. */
function platformExpiry(product, contract) {
  if (product.mainMonths) return firstNoticeDay(contractMonth(contract, product.code));
  return new Date(contract.last_trade_date + 'T00:00:00.000Z');
}

async function fetchProductSpec(code) {
  const { data } = await axios.get(`${BASE_URL}/futures/v1/products`, {
    params: { apiKey: API_KEY, product_code: code, type: 'single', sort: 'date.desc', limit: 1 },
  });
  return data.results && data.results[0];
}

async function fetchUpcomingContracts(product) {
  const { code } = product;
  const today = new Date().toISOString().slice(0, 10);
  // Every page — the list is paged (next_url), and Copper's December was on
  // a later page than its first months, so it was never loaded.
  const results = [];
  let url = `${BASE_URL}/futures/v1/contracts`;
  let params = { apiKey: API_KEY, product_code: code, active: true, date: today, limit: 1000 };
  for (let page = 0; url && page < 20; page++) {
    const { data } = await axios.get(url, { params, timeout: 15000 });
    results.push(...(data.results || []));
    url = data.next_url || null;
    params = { apiKey: API_KEY };
  }
  const outrightRe = new RegExp(`^${code}[FGHJKMNQUVXZ][0-9]$`);
  const seen = new Map();
  for (const r of results) {
    if (!outrightRe.test(r.ticker) || seen.has(r.ticker)) continue;
    if (product.mainMonths && !product.mainMonths.includes(r.ticker.charAt(code.length))) continue;
    const expiry = platformExpiry(product, r);
    if (expiry.toISOString().slice(0, 10) >= today) seen.set(r.ticker, { ...r, expiry });
  }
  return [...seen.values()]
    .sort((a, b) => a.expiry - b.expiry)
    .slice(0, CONTRACTS_PER_PRODUCT);
}

/**
 * Hide active COMEX contracts that aren't among the loaded main months —
 * only when nobody holds a position or pending order in them — and move their
 * watchlist rows to the nearest loaded contract of the same metal (dropped if
 * the owner already watches it).
 */
async function retireComexOffMonths(keepTokens) {
  const Trade = require('../src/models/Trade');
  const Watchlist = require('../src/models/Watchlist');
  const stale = await KiteInstrument.find({ segment: 'COMEX-FUT', is_active: true, deleted_at: null, instrument_token: { $nin: [...keepTokens] } })
    .select('instrument_token tradingsymbol name expiry').lean();
  if (stale.length === 0) console.log('   none');
  for (const inst of stale) {
    const token = String(inst.instrument_token);
    const [held] = await Trade.aggregate([
      { $match: { instrument_token: { $in: [token, Number(token)] }, status: 'completed', deleted_at: null } },
      { $group: { _id: '$user_id', net: { $sum: { $cond: [{ $eq: ['$transaction_type', 'BUY'] }, '$quantity', { $multiply: ['$quantity', -1] }] } } } },
      { $match: { net: { $ne: 0 } } },
      { $count: 'holders' },
    ]);
    const pending = await Trade.countDocuments({ instrument_token: { $in: [token, Number(token)] }, status: 'pending', deleted_at: null });
    if ((held && held.holders) || pending) {
      console.log(`   ⏭️  ${inst.tradingsymbol}: kept — ${held ? held.holders : 0} open position(s), ${pending} pending order(s)`);
      continue;
    }
    const next = await KiteInstrument.findOne({ segment: 'COMEX-FUT', name: inst.name, instrument_token: { $in: [...keepTokens] }, deleted_at: null })
      .sort({ expiry: 1 }).select('_id instrument_token tradingsymbol').lean();
    const entries = await Watchlist.find({ instrument_token: token, deleted_at: null }).select('owner_id owner_type').lean();
    let moved = 0;
    let dropped = 0;
    for (const e of entries) {
      const already = next && await Watchlist.exists({ owner_id: e.owner_id, owner_type: e.owner_type, instrument_token: String(next.instrument_token), deleted_at: null });
      if (next && !already) {
        if (!DRY_RUN) await Watchlist.updateOne({ _id: e._id }, { $set: { instrument_token: String(next.instrument_token), kite_instrument_id: next._id } });
        moved++;
      } else {
        if (!DRY_RUN) await Watchlist.updateOne({ _id: e._id }, { $set: { deleted_at: new Date() } });
        dropped++;
      }
    }
    if (!DRY_RUN) {
      await KiteInstrument.updateOne({ _id: inst._id }, { $set: { is_active: false, enabled: false, ban_reason: 'Not a main COMEX month', banned_at: new Date() } });
    }
    console.log(`   🗄️  ${inst.tradingsymbol}: ${DRY_RUN ? 'would be hidden' : 'hidden'}; watchlists → ${next ? next.tradingsymbol : '—'}: moved ${moved}, dropped ${dropped}`);
  }
}

async function run() {
  if (!API_KEY) {
    console.error('❌ MASSIVE_API_KEY not set in environment.');
    process.exit(1);
  }

  await connectDatabase();

  let upserted = 0;
  const keepTokens = new Set(); // every token loaded this run
  if (DRY_RUN) console.log('DRY RUN — nothing is written');
  for (const product of PRODUCTS) {
    console.log(`\n📡 [SeedGlobalFutures] ${product.code} — ${product.name}`);
    const spec = await fetchProductSpec(product.code);
    if (!spec) {
      console.warn(`⚠️  No product spec found for ${product.code}, skipping.`);
      continue;
    }
    const lotSize = Number(spec.unit_of_measure_qty) || 1;

    const contracts = await fetchUpcomingContracts(product);
    if (contracts.length === 0) {
      console.warn(`⚠️  No active contracts found for ${product.code}, skipping.`);
      continue;
    }

    for (const contract of contracts) {
      const expiry = contract.expiry;
      const token = tokenFor(product.tokenIndex, contractMonth(contract, product.code));
      keepTokens.add(token);
      const line = `${contract.ticker} (token ${token}, expiry ${expiry.toISOString().slice(0, 10)}${product.mainMonths ? ' = first notice day' : ''}, last trade ${contract.last_trade_date}, lot ${lotSize}, tick ${contract.trade_tick_size})`;
      if (DRY_RUN) {
        const had = await KiteInstrument.findOne({ instrument_token: token }).select('tradingsymbol expiry is_active').lean();
        const now = had ? ` — now ${had.tradingsymbol} ${had.expiry ? had.expiry.toISOString().slice(0, 10) : ''} active=${had.is_active}` : ' — new';
        console.log(`   ${had ? '↻' : '➕'} ${line}${now}`);
        upserted += 1;
        continue;
      }

      await KiteInstrument.updateOne(
        { instrument_token: token },
        {
          $set: {
            exchange_token: token,
            tradingsymbol: contract.ticker,
            name: product.friendlyName,
            raw_name: product.friendlyName,
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
      console.log(`   ✅ ${line}`);
      upserted += 1;
    }
  }

  if (RETIRE_COMEX) {
    console.log('\n🗄️  [SeedGlobalFutures] COMEX contracts outside the loaded main months:');
    await retireComexOffMonths(keepTokens);
  }

  console.log(`\n📊 [SeedGlobalFutures] Done — ${upserted} contract(s) ${DRY_RUN ? 'would be upserted' : 'upserted'}.`);
  await mongoose.connection.close();
  process.exit(0);
}

run().catch((err) => {
  console.error('❌ [SeedGlobalFutures] Failed:', err.message);
  process.exit(1);
});
