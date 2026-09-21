/**
 * NSE F&O Ban List Sync
 *
 * NSE publishes a daily list of securities under F&O ban (MWPL breached the
 * prior session) at nsearchives.nseindia.com/content/fo/fo_secban.csv. The
 * ban is entirely NSE's own call and lifts on its own the day a symbol drops
 * back under the limit — this sync just mirrors that state onto
 * KiteInstrument.nse_banned/nse_ban_date each morning, independent of the
 * admin-driven `enabled`/`ban_reason` fields. Also posts the day's ban list
 * as the active Announcement (same single-slot mechanism as an admin manually
 * setting one — this replaces whatever was active, admin-set or not).
 *
 * Main entry: syncNseBanList()
 */

const axios = require('axios');
const KiteInstrument = require('../models/KiteInstrument');
const Announcement = require('../models/Announcement');
const { toIndiaDateOnly } = require('../utils/settlementDates');

const BAN_LIST_URL = 'https://nsearchives.nseindia.com/content/fo/fo_secban.csv';
const BROWSER_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/** Parses the "SR_NO,SYMBOL" body (first line is a "Securities in Ban For Trade Date ..." header, skip it). */
function parseBanListCsv(text) {
  const symbols = new Set();
  const lines = text.split(/\r?\n/).map(l => l.trim()).filter(Boolean);
  for (const line of lines) {
    const cols = line.split(',').map(c => c.trim());
    if (cols.length < 2) continue; // header/footer line, not a data row
    const symbol = cols[1].toUpperCase();
    if (!symbol || !/^[0-9]+$/.test(cols[0])) continue; // require a numeric SR_NO to confirm it's a data row
    symbols.add(symbol);
  }
  return symbols;
}

async function fetchBanListSymbols() {
  const res = await axios.get(BAN_LIST_URL, {
    responseType: 'text',
    timeout: 30000,
    validateStatus: () => true,
    headers: { 'User-Agent': BROWSER_UA },
  });
  if (res.status !== 200 || typeof res.data !== 'string') {
    throw new Error(`NSE ban list fetch failed: HTTP ${res.status}`);
  }
  return parseBanListCsv(res.data);
}

/**
 * Syncs today's NSE F&O ban list onto KiteInstrument.nse_banned. Every
 * underlying symbol in today's list is banned; every symbol previously
 * banned but absent from today's list is automatically un-banned — no
 * admin action needed either way.
 */
async function syncNseBanList() {
  const symbols = await fetchBanListSymbols();
  const today = toIndiaDateOnly();

  const lifted = await KiteInstrument.updateMany(
    { nse_banned: true, name: { $nin: [...symbols] } },
    { $set: { nse_banned: false, nse_ban_date: null } }
  );

  let banned = { matchedCount: 0, modifiedCount: 0 };
  if (symbols.size > 0) {
    banned = await KiteInstrument.updateMany(
      { name: { $in: [...symbols] }, exchange: { $in: ['NFO', 'NSE'] } },
      { $set: { nse_banned: true, nse_ban_date: today } }
    );
  }

  if (lifted.modifiedCount > 0 || banned.modifiedCount > 0) {
    try {
      require('./instrumentSearchService').invalidateCache();
    } catch (_) {}
  }

  // Auto-post today's ban list as the active announcement, same behavior as
  // an admin manually setting one (Announcement only ever holds one active
  // row — this replaces whatever was there, admin-set or not). Only touches
  // it when there's an actual ban list to show; an empty day leaves whatever
  // announcement is already active alone rather than posting "no bans".
  if (symbols.size > 0) {
    try {
      const dateLabel = today.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });
      const message = `NSE F&O Ban (${dateLabel}): ${[...symbols].sort().join(', ')} — new positions blocked, existing positions may still be closed.`;
      await Announcement.updateMany({ is_active: true }, { $set: { is_active: false } });
      await Announcement.create({ message, is_active: true });
    } catch (_) {}
  }

  return {
    symbolsInBanList: symbols.size,
    liftedCount: lifted.modifiedCount,
    bannedCount: banned.modifiedCount,
  };
}

module.exports = { syncNseBanList, fetchBanListSymbols, parseBanListCsv };
