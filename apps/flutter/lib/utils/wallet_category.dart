/// Wallet category for a segment (display only; backend is authoritative —
/// mirrors apps/backend/src/utils/walletCategory.js exactly).
/// NFO-FUT -> NSE, except NIFTY / BANKNIFTY / SENSEX futures -> INDEX (pass the
/// underlying or tradingsymbol); NFO-OPT -> NSEOPT ("NSE OPT": NSE options
/// have their own pool, option margin is blocked/released only there);
/// MCX-FUT/MCX-OPT -> MCX; COMEX-FUT -> COMEX; everything else -> GLOBAL.
String categoryForSegment(String? segment, [String? nameOrSymbol]) {
  final s = (segment ?? '').trim().toUpperCase();
  if (s == 'NFO-FUT') return isIndexFuture(nameOrSymbol) ? 'INDEX' : 'NSE';
  if (s == 'NFO-OPT') return 'NSEOPT';
  if (s == 'MCX-FUT' || s == 'MCX-OPT') return 'MCX';
  if (s == 'COMEX-FUT') return 'COMEX';
  return 'GLOBAL';
}

/// NFO futures on these underlyings trade from the INDEX pool.
const List<String> kIndexFutureNames = ['NIFTY', 'BANKNIFTY', 'SENSEX'];
final RegExp _kIndexFutureSymbol = RegExp(r'^(NIFTY|BANKNIFTY|SENSEX)\d{2}[A-Z]{3}FUT$');

/// NIFTY / BANKNIFTY / SENSEX future, by underlying name or tradingsymbol
/// (never NIFTYNXT50 / FINNIFTY / MIDCPNIFTY).
bool isIndexFuture(String? nameOrSymbol) {
  final s = (nameOrSymbol ?? '').trim().toUpperCase();
  return kIndexFutureNames.contains(s) || _kIndexFutureSymbol.hasMatch(s);
}

/// Every wallet pool, in display order.
const List<String> kWalletCategories = ['NSE', 'INDEX', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL'];

const Map<String, String> _kWalletLabels = {'NSEOPT': 'NSE OPT'};

/// Display label for a wallet pool key ("NSE OPT" for NSEOPT).
String walletLabel(String category) => _kWalletLabels[category] ?? category;

/// Sort order of a wallet pool key (unknown keys last).
int walletOrder(String category) {
  final i = kWalletCategories.indexOf(category);
  return i == -1 ? kWalletCategories.length : i;
}

/// Distinct allowed categories from a list of segment/exchange names.
/// NFO-FUT spans NSE (stock futures) and INDEX (index futures).
List<String> allowedCategories(Iterable<String> segments) {
  final found = <String>{};
  for (final seg in segments) {
    found.add(categoryForSegment(seg));
    if (seg.trim().toUpperCase() == 'NFO-FUT') found.add('INDEX');
  }
  return kWalletCategories.where(found.contains).toList();
}
