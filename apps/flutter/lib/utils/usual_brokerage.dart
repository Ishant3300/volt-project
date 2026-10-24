/// An account's usual brokerage among its rows for one segment — the most
/// common `brk_value` (the higher one wins a tie, the safer floor), or null
/// when there are no rows.
///
/// Not "the first row": NBS (593462) had NFO-FUT 1 on 218 scripts and 2 on
/// 11 F&O stocks that no longer trade, and when the first row was one of
/// those the create forms showed and enforced 2 (24 Oct 2026). Same rule as
/// the web forms (useBaseRates.ts usualRate) and the backend's new-F&O-stock
/// setup (newNfoStockService.js).
double? usualBrokerage(List items) {
  final counts = <double, int>{};
  for (final item in items) {
    final v = (item is Map ? item['brk_value'] as num? : null)?.toDouble();
    if (v == null) continue;
    counts[v] = (counts[v] ?? 0) + 1;
  }
  double? best;
  var bestCount = 0;
  counts.forEach((v, n) {
    if (n > bestCount || (n == bestCount && best != null && v > best!)) {
      best = v;
      bestCount = n;
    }
  });
  return best;
}
