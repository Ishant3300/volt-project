import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/utils/settlement_view.dart';

/// Real weekly-admin-report figures (week of 28 Sep 2026, vijay 652874 with
/// one client, viral 592725) — the same numbers the web portal's
/// lib/settlementView.ts produced from live data. The app must show the same.
void main() {
  final vijayReport = <String, dynamic>{
    'data': [
      {
        'id': 'viral',
        'name': 'viral',
        'username': '592725',
        'type': 'user',
        'caller_profit': -3149.56,
        'owed_upward_pnl': -28346.04,
        'caller_brk': 5205.46,
        'owed_upward_brk': 3607.03,
      },
    ],
    'totals': {
      'caller_brk': 5205.46,
      'caller_profit': -3149.56,
      'owed_upward_pnl': -28346.04,
      'owed_upward_brk': 3607.03,
      'total_owed_upward': -24739.01,
    },
  };

  test('master view: vijay', () {
    final v = buildMasterSettlementView(vijayReport, {'viral': 0});
    expect(v.header, 2055.9);
    expect(v.profit.map((l) => [l.label, l.pnl, l.brokerage, l.total]).toList(), [
      ['viral', 31495.6, -8812.49, 22683.11],
      ['My Brokerage', 0, 5205.46, 5205.46],
    ]);
    expect(v.profit.first.sub, '(592725 - C - 0.00)');
    expect(v.loss.map((l) => [l.label, l.pnl, l.brokerage, l.total]).toList(), [
      ['Admin', -28346.04, 3607.03, -24739.01],
      ['My Profit/Loss', -3149.56, 0, -3149.56],
    ]);
    final all = [...v.profit, ...v.loss].fold<double>(0, (s, l) => s + l.total);
    expect(all.abs() < 0.005, true);
    expect(sectionTotals(v.profit), (31495.6, -3607.03, 27888.57));
    expect(sectionTotals(v.loss), (-31495.6, 3607.03, -27888.57));
  });

  test('client view: viral', () {
    final v = buildClientSettlementView(Map<String, dynamic>.from((vijayReport['data'] as List).first));
    expect(v.header, 22683.11);
    expect(v.profit.map((l) => [l.label, l.total]).toList(), [
      ['My Profit/Loss', 31495.6],
    ]);
    expect(v.loss.map((l) => [l.label, l.pnl, l.brokerage, l.total]).toList(), [
      ['Admin', -31495.6, 8812.49, -22683.11],
      ['My Brokerage', 0, -8812.49, -8812.49],
    ]);
  });

  test('a traded downline account stays visible when nothing reaches the viewer (harry seen by admin)', () {
    final v = buildMasterSettlementView({
      'data': [
        {'id': 'harry', 'name': 'harry', 'username': '839276', 'type': 'master', 'realised_pnl': -2428329.8, 'brokerage': 143492.03,
         'caller_profit': 0.0, 'owed_upward_pnl': 0.0, 'caller_brk': 0.0, 'owed_upward_brk': 0.0},
        {'id': 'idle', 'name': 'idle', 'username': '000001', 'type': 'master', 'realised_pnl': 0.0, 'brokerage': 0.0,
         'caller_profit': 0.0, 'owed_upward_pnl': 0.0, 'caller_brk': 0.0, 'owed_upward_brk': 0.0},
      ],
      'totals': {'caller_brk': 0.0, 'caller_profit': 0.0, 'owed_upward_pnl': 0.0, 'owed_upward_brk': 0.0, 'total_owed_upward': 0.0},
    }, {'harry': 100});
    expect(v.profit.map((l) => [l.label, l.sub, l.total]).toList(), [
      ['harry', '(839276 - M - 100.00)', 0],
    ]);
    expect(v.loss, isEmpty);
  });

  test('zero rows are left out (top account: Admin)', () {
    final v = buildMasterSettlementView({
      'data': [],
      'totals': {'caller_brk': 10.0, 'caller_profit': 0.0, 'owed_upward_pnl': 0.0, 'owed_upward_brk': 0.0, 'total_owed_upward': 0.0},
    }, {});
    expect(v.profit.map((l) => l.label).toList(), ['My Brokerage']);
    expect(v.loss, isEmpty);
  });
}
