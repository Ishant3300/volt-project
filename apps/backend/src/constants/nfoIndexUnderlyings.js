/**
 * NFO underlyings traded as an index (vs a single stock). Used only to
 * classify a script for brokerage-rate purposes — Index futures/options
 * commonly carry a different brokerage rate than Stock futures/options.
 * Not applicable outside NFO-FUT/NFO-OPT (MCX scripts get their own rate
 * directly, no category concept).
 */
const NFO_INDEX_UNDERLYINGS = Object.freeze([
  'NIFTY',
  'BANKNIFTY',
  'FINNIFTY',
  'MIDCPNIFTY',
  'SENSEX',
  'BANKEX',
]);

/**
 * 'INDEX' | 'STOCK' | null — null for non-NFO segments, where the
 * category concept doesn't apply.
 */
function categoryForNfoScript(segment, rawName) {
  const seg = (segment || '').toUpperCase();
  if (seg !== 'NFO-FUT' && seg !== 'NFO-OPT') return null;
  const name = (rawName || '').toUpperCase();
  return NFO_INDEX_UNDERLYINGS.includes(name) ? 'INDEX' : 'STOCK';
}

module.exports = { NFO_INDEX_UNDERLYINGS, categoryForNfoScript };
