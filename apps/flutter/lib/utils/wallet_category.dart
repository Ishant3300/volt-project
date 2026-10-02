/// Wallet category for a segment (display only; backend is authoritative —
/// mirrors apps/backend/src/utils/walletCategory.js exactly).
/// NFO-FUT -> NSE; NFO-OPT -> NSEOPT ("NSE OPT": NSE options have their own
/// pool, option margin is blocked/released only there); MCX-FUT/MCX-OPT ->
/// MCX; COMEX-FUT -> COMEX; everything else -> GLOBAL.
String categoryForSegment(String? segment) {
  final s = (segment ?? '').trim().toUpperCase();
  if (s == 'NFO-FUT') return 'NSE';
  if (s == 'NFO-OPT') return 'NSEOPT';
  if (s == 'MCX-FUT' || s == 'MCX-OPT') return 'MCX';
  if (s == 'COMEX-FUT') return 'COMEX';
  return 'GLOBAL';
}

/// Every wallet pool, in display order.
const List<String> kWalletCategories = ['NSE', 'NSEOPT', 'MCX', 'COMEX', 'GLOBAL'];

const Map<String, String> _kWalletLabels = {'NSEOPT': 'NSE OPT'};

/// Display label for a wallet pool key ("NSE OPT" for NSEOPT).
String walletLabel(String category) => _kWalletLabels[category] ?? category;

/// Sort order of a wallet pool key (unknown keys last).
int walletOrder(String category) {
  final i = kWalletCategories.indexOf(category);
  return i == -1 ? kWalletCategories.length : i;
}

/// Distinct allowed categories from a list of segment/exchange names.
List<String> allowedCategories(Iterable<String> segments) {
  final found = <String>{for (final seg in segments) categoryForSegment(seg)};
  return kWalletCategories.where(found.contains).toList();
}
