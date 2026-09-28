/**
 * Official settlement price for GIFT NIFTY (KiteInstrument.exchange === 'NSEIX').
 *
 * NSE/BSE/MCX get their official close from a daily bhavcopy file
 * (bhavcopyService.js); GLOBAL/COMEX index futures get theirs from Massive
 * (massiveSettlementService.js). Nothing equivalent existed for GIFT NIFTY —
 * settlementService.js's expectedPriceDateForInstrument/
 * hasOfficialSettlementAuthority had no NSEIX branch at all, so any user
 * holding an open GIFT NIFTY position failed the ENTIRE weekly settlement run
 * (confirmed real: a SettlementRun record was found permanently `blocked`
 * with error "Settlement validation failed for 1 position(s): GIFT NIFTY
 * (official settlement source unsupported for NSEIX)").
 *
 * NSEIX (nseix.com) publishes its own official Daily Settlement Price file —
 * discoverable via a small JSON index at /api/daily-settlement-prices (used
 * by the "Daily Settlement Price INDEX" widget on nseix.com's own homepage),
 * which points at a dated CSV (G_T_DSP_INDEX_DDMMYYYY.csv) containing every
 * NSEIX index future's official settlement price for that trading day,
 * including SYMBOL=NIFTY (GIFT Nifty's underlying symbol on NSEIX) rows for
 * every listed expiry. GIFT Nifty is stored in our DB as a single continuous
 * instrument (expiry: null, no per-contract-month tracking) — the nearest
 * (soonest) expiry's settlement price is used, same near-month convention
 * giftNiftyFeedService.js already uses for its live bid/ask.
 *
 * NSEIX runs on the same India trading-calendar day as NSE (confirmed: the
 * published file's own DATE column matches NSE's trading date), so this
 * reuses SettlementRun.price_dates.nse rather than needing a dedicated
 * schema field.
 */

const axios = require('axios');
const KiteInstrument = require('../models/KiteInstrument');
const { dateKey, toIndiaDateOnly } = require('../utils/settlementDates');

const BROWSER_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const INDEX_URL = 'https://www.nseix.com/api/daily-settlement-prices';

/** "29-Sep-2026" → Date */
function parseNseixDate(raw) {
  const months = { JAN: '01', FEB: '02', MAR: '03', APR: '04', MAY: '05', JUN: '06', JUL: '07', AUG: '08', SEP: '09', OCT: '10', NOV: '11', DEC: '12' };
  const match = /^(\d{1,2})-([A-Za-z]{3})-(\d{4})$/.exec(String(raw || '').trim());
  if (!match || !months[match[2].toUpperCase()]) return null;
  return new Date(`${match[3]}-${months[match[2].toUpperCase()]}-${match[1].padStart(2, '0')}T00:00:00.000Z`);
}

function parseCsvLine(line) {
  return line.split(',').map(s => s.trim());
}

/**
 * Parse NSEIX's Daily Settlement Price CSV.
 * Header: DATE,INSTRUMENT TYPE,SYMBOL,EXPIRY DATE,STRIKE,OPTION TYPE,SETTLEMENT PRICE
 * Returns { rows: [{date, instrumentType, symbol, expiry, settlementPrice}], sourceDates: Set<string> }
 */
function parseDailySettlementCsv(text) {
  const lines = text.trim().split(/\r?\n/);
  const rows = [];
  const sourceDates = new Set();
  if (lines.length < 2) return { rows, sourceDates };

  const header = parseCsvLine(lines[0]).map(h => h.toUpperCase());
  const iDate = header.indexOf('DATE');
  const iInstType = header.indexOf('INSTRUMENT TYPE');
  const iSymbol = header.indexOf('SYMBOL');
  const iExpiry = header.indexOf('EXPIRY DATE');
  const iSettle = header.indexOf('SETTLEMENT PRICE');
  if ([iDate, iInstType, iSymbol, iExpiry, iSettle].some(i => i === -1)) {
    return { rows, sourceDates, invalidSchema: true };
  }

  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    const c = parseCsvLine(line);
    if (c.length <= Math.max(iDate, iInstType, iSymbol, iExpiry, iSettle)) continue;

    const dateValue = parseNseixDate(c[iDate]);
    const settlementPrice = parseFloat(c[iSettle]) || 0;
    const expiry = parseNseixDate(c[iExpiry]);
    if (!dateValue || settlementPrice <= 0) continue;

    sourceDates.add(dateKey(dateValue));
    rows.push({
      date: dateValue,
      instrumentType: c[iInstType].toUpperCase(),
      symbol: c[iSymbol].toUpperCase(),
      expiry,
      settlementPrice,
    });
  }

  return { rows, sourceDates };
}

function pickNearMonthRow(rows) {
  const futures = rows.filter(r => r.instrumentType === 'FUTIDX' && r.symbol === 'NIFTY' && r.expiry);
  if (futures.length === 0) return null;
  return futures.reduce((nearest, row) => (!nearest || row.expiry < nearest.expiry ? row : nearest), null);
}

async function fetchAndApplyGiftNiftySettlement(targetDate, options = {}) {
  const requestedDate = toIndiaDateOnly(targetDate || options.now || new Date());
  const requestedKey = dateKey(requestedDate);

  let indexRes;
  try {
    indexRes = await axios.get(INDEX_URL, { timeout: 15000, headers: { 'User-Agent': BROWSER_UA } });
  } catch (e) {
    console.warn(`⚠️  [GiftNiftySettlement] Index fetch failed: ${e.message}`);
    return { updated: 0 };
  }

  const entries = Array.isArray(indexRes.data) ? indexRes.data : [];
  const entry = entries.find(e => e.FILE_DATE && dateKey(new Date(e.FILE_DATE)) === requestedKey) || entries[0];
  if (!entry || !entry.FILE_NAME) {
    console.warn('⚠️  [GiftNiftySettlement] No daily settlement file listed by NSEIX.');
    return { updated: 0 };
  }

  let csvText;
  try {
    const csvRes = await axios.get(entry.FILE_NAME, { timeout: 30000, headers: { 'User-Agent': BROWSER_UA } });
    csvText = typeof csvRes.data === 'string' ? csvRes.data : JSON.stringify(csvRes.data);
  } catch (e) {
    console.warn(`⚠️  [GiftNiftySettlement] CSV download failed: ${e.message}`);
    return { updated: 0 };
  }

  const { rows, sourceDates, invalidSchema } = parseDailySettlementCsv(csvText);
  if (invalidSchema) {
    console.warn('⚠️  [GiftNiftySettlement] CSV header shape changed from the confirmed real format — refusing to parse.');
    return { updated: 0 };
  }
  if (sourceDates.size !== 1 || !sourceDates.has(requestedKey)) {
    console.warn(`⚠️  [GiftNiftySettlement] Rejected file: requested ${requestedKey}, source dates: ${[...sourceDates].join(', ') || 'missing'}.`);
    return { updated: 0, rejectedSourceDate: true, sourceDates: [...sourceDates] };
  }

  const nearMonth = pickNearMonthRow(rows);
  if (!nearMonth) {
    console.warn('⚠️  [GiftNiftySettlement] No NIFTY FUTIDX row in the settlement file.');
    return { updated: 0 };
  }

  const instrument = await KiteInstrument.findOne({
    exchange: 'NSEIX',
    $or: [{ tradingsymbol: 'GIFT NIFTY' }, { name: 'GIFT NIFTY' }, { display_name: 'GIFT NIFTY' }],
    is_active: true,
  }).select('instrument_token').lean();
  if (!instrument) {
    console.warn('⚠️  [GiftNiftySettlement] "GIFT NIFTY" instrument not found.');
    return { updated: 0 };
  }

  const token = instrument.instrument_token.toString();
  const settlementPrice = nearMonth.settlementPrice;
  const updatedAt = new Date();

  await KiteInstrument.updateOne(
    { instrument_token: token },
    {
      $set: {
        settlement_price: settlementPrice,
        settlement_price_date: requestedDate,
        settlement_price_source: 'NSEIX_OFFICIAL_DAILY_SETTLEMENT',
        settlement_price_updated_at: updatedAt,
      },
    }
  );
  console.log(`   ✅ [GiftNiftySettlement] GIFT NIFTY → ${settlementPrice} (${requestedKey}, near-month expiry).`);

  // Monthly GIFTNIFTY…FUT contracts (giftNiftyContracts.js): each gets its
  // OWN month's official settlement price from the same file.
  const monthly = await KiteInstrument.find({ exchange: 'NSEIX', instrument_type: 'FUT', name: 'GIFT NIFTY', deleted_at: null })
    .select('instrument_token tradingsymbol expiry').lean();
  const futRows = rows.filter(r => r.instrumentType === 'FUTIDX' && r.symbol === 'NIFTY' && r.expiry);
  const monthlyApplied = [];
  for (const c of monthly) {
    const row = futRows.find(r => dateKey(r.expiry) === dateKey(c.expiry));
    if (!row) continue;
    await KiteInstrument.updateOne({ instrument_token: c.instrument_token }, { $set: {
      settlement_price: row.settlementPrice,
      settlement_price_date: requestedDate,
      settlement_price_source: 'NSEIX_OFFICIAL_DAILY_SETTLEMENT',
      settlement_price_updated_at: updatedAt,
    } });
    monthlyApplied.push({ token: c.instrument_token.toString(), price: row.settlementPrice });
    console.log(`   ✅ [GiftNiftySettlement] ${c.tradingsymbol} → ${row.settlementPrice} (${requestedKey}).`);
  }

  if (options.applyToLivePrices !== false) {
    try {
      const livePriceService = require('./livePriceService');
      const metricsEngine = require('./metricsEngine');
      if (livePriceService && livePriceService._broadcastToClients) {
        livePriceService.latestPrices.set(token, settlementPrice);
        livePriceService.latestPrices.set(Number(token), settlementPrice);
        metricsEngine.onTick(token, settlementPrice, settlementPrice, settlementPrice);
        for (const m of monthlyApplied) {
          livePriceService.latestPrices.set(m.token, m.price);
          livePriceService.latestPrices.set(Number(m.token), m.price);
          metricsEngine.onTick(m.token, m.price, m.price, m.price);
        }
        livePriceService._broadcastToClients({
          type: 'ticks',
          data: [{
            instrument_token: token,
            last_price: settlementPrice,
            bid_price: settlementPrice,
            ask_price: settlementPrice,
            close: settlementPrice,
            is_settlement: true,
          }, ...monthlyApplied.map(m => ({
            instrument_token: m.token,
            last_price: m.price,
            bid_price: m.price,
            ask_price: m.price,
            close: m.price,
            is_settlement: true,
          }))],
        });
      }
    } catch (_) {
      console.log('   Broadcast skipped (standalone mode or no clients connected).');
    }
  }

  return { updated: 1 + monthlyApplied.length, settlementPrice, monthly: monthlyApplied, tradingDate: requestedKey };
}

module.exports = {
  fetchAndApplyGiftNiftySettlement,
  _private: { parseDailySettlementCsv, parseNseixDate, pickNearMonthRow },
};
