/**
 * NSE F&O Ban List Sync
 *
 * NSE publishes a daily list of securities under F&O ban (MWPL breached the
 * prior session) at nsearchives.nseindia.com/content/fo/fo_secban.csv. The
 * ban is entirely NSE's own call and lifts on its own the day a symbol drops
 * back under the limit — this sync just mirrors that state onto
 * KiteInstrument.nse_banned/nse_ban_date each morning, independent of the
 * admin-driven `enabled`/`ban_reason` fields. Also posts the day's ban list
 * as the banner's 'ban' section (services/announcementBoard.js) — it scrolls
 * alongside an admin's message and new-contract notices, never replaces them.
 *
 * Main entry: syncNseBanList()
 */

const axios = require('axios');
const KiteInstrument = require('../models/KiteInstrument');
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

  // Today's ban list is the banner's 'ban' section — it replaces only
  // yesterday's list, never an admin's message or a new-contract notice
  // (services/announcementBoard.js). A day with no bans removes the section
  // so a stale list doesn't stay up.
  try {
    const board = require('./announcementBoard');
    if (symbols.size > 0) {
      const dateLabel = today.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric', timeZone: 'UTC' });
      await board.postSection('ban', `NSE F&O Ban (${dateLabel}): ${[...symbols].sort().join(', ')} — new positions blocked, existing positions may still be closed.`);
    } else {
      await board.clearSection('ban');
    }
  } catch (_) {}

  return {
    symbolsInBanList: symbols.size,
    liftedCount: lifted.modifiedCount,
    bannedCount: banned.modifiedCount,
  };
}

module.exports = { syncNseBanList, fetchBanListSymbols, parseBanListCsv };
