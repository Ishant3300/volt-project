/// Profit-book hold time (owner, 10 Nov 2026).
///
/// A client may not close a position IN PROFIT within his profit-book minutes
/// of opening that quantity; closing at a loss is always allowed. The server
/// decides every order (tradeController _validateFreshStoplossHoldTime). The
/// live position data carries `profit_hold` while part of a position is still
/// inside the hold (metricsEngine profitHoldOf), and the app uses it to show the
/// closing button as a timer — only when the server WOULD refuse:
///   profit_hold: { minutes, avg, free_qty, lots: [{ qty, free_at }] }
/// No `profit_hold` (no hold time, or every lot free) = no timer.
/// Same rule as backend tests/profitBookTime.integration.test.js predictRefused.
library;

class HoldLot {
  final int qty;
  final DateTime freeAt;
  const HoldLot(this.qty, this.freeAt);
}

class ProfitHold {
  final int minutes;
  final double avg;
  final int freeQty;
  final List<HoldLot> lots;
  const ProfitHold({required this.minutes, required this.avg, required this.freeQty, required this.lots});

  static ProfitHold? fromJson(dynamic j) {
    if (j is! Map) return null;
    final lots = <HoldLot>[];
    for (final l in (j['lots'] as List? ?? const [])) {
      if (l is! Map) continue;
      final at = DateTime.tryParse(l['free_at']?.toString() ?? '');
      final qty = (l['qty'] as num?)?.toInt() ?? 0;
      if (at != null && qty > 0) lots.add(HoldLot(qty, at));
    }
    if (lots.isEmpty) return null;
    lots.sort((a, b) => a.freeAt.compareTo(b.freeAt));
    return ProfitHold(
      minutes: (j['minutes'] as num?)?.toInt() ?? 0,
      avg: (j['avg'] as num?)?.toDouble() ?? 0,
      freeQty: (j['free_qty'] as num?)?.toInt() ?? 0,
      lots: lots,
    );
  }
}

class HoldLock {
  /// Time until the quantity asked can be closed in profit.
  final Duration left;

  /// Quantity that can already be closed in profit now (older lots).
  final int freeNow;
  const HoldLock(this.left, this.freeNow);
}

/// Null = the server would accept this close (or it is not a close); otherwise
/// how long until it would. `orderType` MARKET is judged at the bid (closing a
/// BUY position) or the ask (closing a SELL position); LIMIT / SL at `price`.
HoldLock? profitHoldLock({
  required ProfitHold? hold,
  required int netQty,
  required String side,
  required String orderType,
  required double price,
  required double bid,
  required double ask,
  required int qty,
  DateTime? now,
}) {
  if (hold == null || netQty == 0 || qty <= 0) return null;
  final closingLong = netQty > 0 && side == 'SELL';
  final closingShort = netQty < 0 && side == 'BUY';
  if (!closingLong && !closingShort) return null;
  final closePrice = orderType == 'MARKET' ? (closingLong ? bid : ask) : price;
  if (!(closePrice > 0)) return null;
  final inProfit = closingLong ? closePrice > hold.avg : closePrice < hold.avg;
  if (!inProfit) return null;

  final t = now ?? DateTime.now();
  var free = hold.freeQty;
  for (final l in hold.lots) {
    if (!l.freeAt.isAfter(t)) free += l.qty;
  }
  final held = netQty.abs();
  final need = qty < held ? qty : held;
  if (need <= free) return null;

  var covered = free;
  DateTime release = hold.lots.last.freeAt;
  for (final l in hold.lots) {
    if (!l.freeAt.isAfter(t)) continue;
    covered += l.qty;
    if (covered >= need) {
      release = l.freeAt;
      break;
    }
  }
  final left = release.difference(t);
  return HoldLock(left.isNegative ? Duration.zero : left, free);
}

/// 6:41 · 1:02:05
String formatHoldLeft(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds + (d.inMilliseconds % 1000 > 0 ? 1 : 0);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}
