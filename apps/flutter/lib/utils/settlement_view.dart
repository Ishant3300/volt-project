/// Settlement Report rows, in the reference terminal's layout — one account's
/// view of the period: what reaches it from each direct child, what it keeps
/// (My Brokerage / My Profit/Loss), and what it passes up ("Admin").
///
/// NO new calculation: every figure is a field GET /master/weekly-admin-report
/// already computes (the same engine as the ledger's Self / Downline / Upline
/// MTM), only regrouped — a line-for-line copy of the web portal's
/// lib/settlementView.ts:
///
///   downline row   = -(caller share + owed upward) for that child
///   My Brokerage   = totals.caller_brk
///   My Profit/Loss = totals.caller_profit
///   Admin          = totals.owed_upward_*
///   header         = My Brokerage + My Profit/Loss
///
/// Every row is signed from that party's own side (positive = it gains), so
/// one view's rows add up to zero. A client's own view is its row in its
/// master's report, seen from the client's side.
library;

class SettlementLine {
  final String key;

  /// 'downline' | 'my_brokerage' | 'my_pnl' | 'admin'
  final String kind;
  final String label;
  final String? sub;
  final String? username;
  final double pnl;
  final double brokerage;
  final double total;

  /// A downline row opens that account's own view: {type: 'master'|'user', id, name, username}.
  final Map<String, String>? drill;

  const SettlementLine({
    required this.key,
    required this.kind,
    required this.label,
    this.sub,
    this.username,
    required this.pnl,
    required this.brokerage,
    required this.total,
    this.drill,
  });
}

class SettlementView {
  final double header;
  final List<SettlementLine> profit;
  final List<SettlementLine> loss;
  const SettlementView(this.header, this.profit, this.loss);

  static const empty = SettlementView(0, [], []);
}

double _r2(num? n) => ((n ?? 0) * 100).round() / 100;
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

/// What one child row hands to the viewer and its upline: (pnl, brokerage).
(double, double) _handedUp(Map<String, dynamic> row) => (
      _d(row['caller_profit']) + _d(row['owed_upward_pnl']),
      _d(row['caller_brk']) + _d(row['owed_upward_brk']),
    );

SettlementLine _line(String key, String kind, String label, double pnl, double brokerage, double total,
        {String? sub, String? username, Map<String, String>? drill}) =>
    SettlementLine(
      key: key,
      kind: kind,
      label: label,
      sub: sub,
      username: username,
      pnl: _r2(pnl),
      brokerage: _r2(brokerage),
      total: _r2(total),
      drill: drill,
    );

SettlementView _split(List<SettlementLine> lines, double header) {
  // A row that is zero across the board is left out, like the reference.
  final shown = lines.where((l) => l.pnl != 0 || l.brokerage != 0 || l.total != 0).toList();
  final profit = shown.where((l) => l.total >= 0).toList()..sort((a, b) => b.total.compareTo(a.total));
  final loss = shown.where((l) => l.total < 0).toList()..sort((a, b) => a.total.compareTo(b.total));
  return SettlementView(_r2(header), profit, loss);
}

/// A master's (or admin's own) view — from its weekly admin report body.
SettlementView buildMasterSettlementView(Map<String, dynamic> body, Map<String, double> sharingById) {
  final t = Map<String, dynamic>.from(body['totals'] ?? {});
  final lines = <SettlementLine>[];
  for (final raw in List.from(body['data'] ?? [])) {
    final row = Map<String, dynamic>.from(raw);
    final (pnl, brk) = _handedUp(row);
    final id = '${row['id']}';
    final username = '${row['username'] ?? ''}';
    final name = '${row['name'] ?? ''}';
    final isMaster = row['type'] == 'master';
    final share = sharingById[id] ?? 0;
    lines.add(_line('d-$id', 'downline', name.isNotEmpty ? name : username, -pnl, -brk, -(pnl + brk),
        sub: '($username - ${isMaster ? 'M' : 'C'} - ${share.toStringAsFixed(2)})',
        username: username,
        drill: {'type': isMaster ? 'master' : 'user', 'id': id, 'name': name, 'username': username}));
  }
  lines.add(_line('my-brk', 'my_brokerage', 'My Brokerage', 0, 0, _d(t['caller_brk'])));
  lines.add(_line('my-pnl', 'my_pnl', 'My Profit/Loss', 0, 0, _d(t['caller_profit'])));
  lines.add(_line('admin', 'admin', 'Admin', _d(t['owed_upward_pnl']), _d(t['owed_upward_brk']), _d(t['total_owed_upward'])));
  return _split(lines, _d(t['caller_brk']) + _d(t['caller_profit']));
}

/// A client's own view — its row in its master's weekly admin report, from the client's side.
SettlementView buildClientSettlementView(Map<String, dynamic>? row) {
  if (row == null) return SettlementView.empty;
  final (pnl, brk) = _handedUp(row);
  return _split([
    _line('my-brk', 'my_brokerage', 'My Brokerage', 0, 0, -brk),
    _line('my-pnl', 'my_pnl', 'My Profit/Loss', 0, 0, -pnl),
    _line('admin', 'admin', 'Admin', pnl, brk, pnl + brk),
  ], -(pnl + brk));
}

/// A section's TOTAL row: (pnl, brokerage, total).
(double, double, double) sectionTotals(List<SettlementLine> lines) => (
      _r2(lines.fold<double>(0, (s, l) => s + l.pnl)),
      _r2(lines.fold<double>(0, (s, l) => s + l.brokerage)),
      _r2(lines.fold<double>(0, (s, l) => s + l.total)),
    );
