/// COMEX on the bill (backend utils/comexFx.js, 25 Oct 2026): COMEX trades,
/// prices, brokerage and P&L are in US dollars; only the bill converts. The
/// weekly settlement converts each client's COMEX net at admin's base + spread
/// when the client owes (debit) and base - spread when owed (credit). On a
/// bill: settled weeks use the rupee amount their settlement booked (the
/// server's `comex.settled`); anything not settled yet - including open
/// positions' live P&L - is an ESTIMATE at today's rate (`comex.fx`). With no
/// rate set no rupee figure is invented. Mirrors the web's lib/comexBill.ts.
library;

bool isComexExchange(Object? exchange) {
  final s = (exchange ?? '').toString().toUpperCase();
  return s == 'COMEX' || s == 'COMEX-FUT';
}

/// Debit (net < 0) -> base + spread; credit -> base - spread; 0 -> base.
double? comexRateForNet(double net, Map? fx) {
  final base = (fx?['base'] as num?)?.toDouble();
  if (base == null || base <= 0) return null;
  final spread = (fx?['spread'] as num?)?.toDouble() ?? 0;
  if (net < 0) return base + spread;
  if (net > 0) return base - spread;
  return base;
}

class ComexBillLine {
  final String label;
  final double usdNet;
  final double? rate;
  final double? inrNet;
  final bool estimate;
  const ComexBillLine(this.label, this.usdNet, this.rate, this.inrNet, this.estimate);
}

class ComexBill {
  final double usdPnl;
  final double usdBr;
  final double usdBuyTurnover;
  final double usdSellTurnover;
  final List<ComexBillLine> lines;

  /// Rupee totals - null when some part couldn't be converted (no rate set).
  final double? inrPnl;
  final double? inrBr;
  ComexBill(this.usdPnl, this.usdBr, this.usdBuyTurnover, this.usdSellTurnover, this.lines, this.inrPnl, this.inrBr);
  double get usdNet => usdPnl - usdBr;
  double? get inrNet => inrPnl == null || inrBr == null ? null : inrPnl! - inrBr!;
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
double _r2(double n) => (n * 100).roundToDouble() / 100;

/// The bill's COMEX conversion from its COMEX dollar totals (incl. live P&L)
/// and the server's `comex` block. Null when the bill has no COMEX.
ComexBill? comexBill({
  required double usdPnl,
  required double usdBr,
  required double usdBuyTurnover,
  required double usdSellTurnover,
  required Map? serverComex,
  required bool hasComex,
}) {
  if (!hasComex) return null;
  final lines = <ComexBillLine>[];
  double setUsdPnl = 0, setUsdBr = 0, inrPnl = 0, inrBr = 0;
  for (final p in (serverComex?['settled'] as List?) ?? const []) {
    final uP = (p['usd_pnl'] as num?)?.toDouble() ?? 0;
    final uB = (p['usd_brokerage'] as num?)?.toDouble() ?? 0;
    final iP = (p['inr_pnl'] as num?)?.toDouble() ?? 0;
    final iB = (p['inr_brokerage'] as num?)?.toDouble() ?? 0;
    setUsdPnl += uP;
    setUsdBr += uB;
    inrPnl += iP;
    inrBr += iB;
    // The settled trading day (as the web labels it); the commit time in IST as a fallback.
    final tradingDay = DateTime.tryParse((p['settlement_trading_date'] ?? '').toString())?.toUtc();
    final d = tradingDay ?? DateTime.tryParse((p['settlement_date'] ?? '').toString())?.toUtc().add(const Duration(hours: 5, minutes: 30));
    lines.add(ComexBillLine(
      d == null ? 'Settled' : 'Settled ${d.day} ${_months[d.month - 1]} ${d.year}',
      _r2(uP - uB),
      (p['fx_rate'] as num?)?.toDouble(),
      _r2(iP - iB),
      false,
    ));
  }
  final remPnl = usdPnl - setUsdPnl;
  final remBr = usdBr - setUsdBr;
  bool complete = true;
  if (remPnl.abs() >= 0.005 || remBr.abs() >= 0.005) {
    final remNet = remPnl - remBr;
    final rate = comexRateForNet(remNet, serverComex?['fx'] as Map?);
    lines.add(ComexBillLine('Not yet settled (estimate at today\'s rate)', _r2(remNet), rate,
        rate == null ? null : _r2(remNet * rate), true));
    if (rate == null) {
      complete = false;
    } else {
      inrPnl += remPnl * rate;
      inrBr += remBr * rate;
    }
  }
  return ComexBill(_r2(usdPnl), _r2(usdBr), usdBuyTurnover, usdSellTurnover, lines,
      complete ? _r2(inrPnl) : null, complete ? _r2(inrBr) : null);
}
