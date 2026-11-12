import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/services/broker_service.dart';
import 'package:stocker/views/broker_share_view.dart';

/// Broker sharing (11 Nov 2026) — the app's settings checks and the
/// Ledger-style statement table, on the figures checked by hand on the web
/// demo (Harish 90/60 rate 2; S 30/40 rate 5; clients pay 8 paisa).
///   flutter test test/broker_share_test.dart
void main() {
  final subLimits = <String, dynamic>{
    'kind': 'master',
    'target': {'id': 's', 'username': 'demosub', 'name': 'S'},
    'paying_master': {'id': 'h', 'username': 'demoharish', 'name': 'Harish'},
    'pnl_max': 60,
    'brk_max': 20,
    'below_pnl_pct': 30,
    'below_brk_pct': 40,
    'segments': [
      {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'x_max': 3},
    ],
  };

  group('settings draft', () {
    test('valid settings become the server payload', () {
      final d = BrokerSettingsDraft();
      d.pnl.text = '20';
      d.brk.text = '10';
      d.rate('NFO-FUT').text = '1';
      expect(d.toSettings(subLimits), {
        'rates': [
          {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 1.0},
        ],
        'pnl_share_pct': 20.0,
        'brk_share_pct': 10.0,
      });
    });

    test('0 / 0 / 0 is allowed (view only)', () {
      expect(BrokerSettingsDraft().toSettings(subLimits), {'rates': [], 'pnl_share_pct': 0.0, 'brk_share_pct': 0.0});
    });

    test('above the limits is refused with a readable message', () {
      final d = BrokerSettingsDraft()..brk.text = '21';
      expect(() => d.toSettings(subLimits), throwsA(isA<BrokerApiException>().having((e) => e.message, 'message', 'Brokerage sharing can be at most 20%.')));
      final p = BrokerSettingsDraft()..pnl.text = '61';
      expect(() => p.toSettings(subLimits), throwsA(isA<BrokerApiException>()));
      final r = BrokerSettingsDraft()..rate('NFO-FUT').text = '3.5';
      expect(() => r.toSettings(subLimits), throwsA(isA<BrokerApiException>().having((e) => e.message, 'message', contains('at most 3 paisa'))));
      final bad = BrokerSettingsDraft()..pnl.text = 'abc';
      expect(() => bad.toSettings(subLimits), throwsA(isA<BrokerApiException>()));
    });

    test('fillFrom puts an existing link back into the boxes', () {
      final d = BrokerSettingsDraft()
        ..fillFrom({
          'pnl_share_pct': 20,
          'brk_share_pct': 10,
          'rates': [
            {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 3},
          ],
        });
      expect([d.pnl.text, d.brk.text, d.rate('NFO-FUT').text], ['20', '10', '3']);
    });
  });

  // The demo week: GH direct client (in profit), S sub-master with CD and EF under him.
  Map<String, dynamic> split(num t, num b, num s, num u) => {'total': t, 'below': b, 'self': s, 'upline': u};
  final week = <String, dynamic>{
    'key': '2026-11-08',
    'label': 'This week (from 2026-11-08)',
    'current': true,
    'rows': [
      {
        'target': {'type': 'client', 'id': 'gh', 'name': 'GH', 'username': '100003'},
        'paying_master': {'id': 'h', 'name': 'Harish', 'username': 'demoharish'},
        'pnl': split(-4000, 0, -800, -3200),
        'brokerage': split(163.2, 0, 71.4, 91.8),
        'net': -728.6,
      },
      {
        'target': {'type': 'master', 'id': 's', 'name': 'S', 'username': 'demosub'},
        'paying_master': {'id': 'h', 'name': 'Harish', 'username': 'demoharish'},
        'pnl': split(2000, 600, 400, 1000),
        'brokerage': split(318.4, 199, 39.8, 79.6),
        'net': 439.8,
        'accounts': [
          {
            'target': {'type': 'client', 'id': 'cd', 'name': 'CD', 'username': '100002'},
            'pnl': split(5000, 1500, 1000, 2500),
            'brokerage': split(156, 97.5, 19.5, 39),
            'net': 1019.5,
          },
          {
            'target': {'type': 'client', 'id': 'ef', 'name': 'EF', 'username': '100004'},
            'pnl': split(-3000, -900, -600, -1500),
            'brokerage': split(162.4, 101.5, 20.3, 40.6),
            'net': -579.7,
          },
        ],
      },
    ],
    'totals': {
      'pnl': split(-2000, 600, -400, -2200),
      'brokerage': split(481.6, 199, 111.2, 171.4),
      'net': -288.8,
    },
  };

  testWidgets('statement table: one row per account (sub-master broken down), then Total', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BrokerStatementTable(week: week)))));

    // GH direct, CD and EF from S's breakdown — S itself is not a row.
    for (final t in ['GH', 'CD', 'EF', '100003', '100002', '100004', 'Total (3)', 'UNDER']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('S'), findsNWidgets(2)); // the "Under" column of CD and EF
    expect(find.text('demosub'), findsNothing);
    // CD: Client P&L (client's sign: the house's +5,000 is the client's -5,000), Brokerage, Net MTM (= Self + Downline + Upline), Self MTM
    for (final t in ['-5,000.00', '156.00', '5,156.00', '1,019.50', '1,597.50', '2,539.00']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    // Total row: client P&L +2,000 (house -2,000), 481.60 brokerage, net -288.80 to the broker
    for (final t in ['2,000.00', '481.60', '-1,518.40', '-288.80', '799.00', '-2,028.60']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('statement table fits a phone: name pinned, figures scroll', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: BrokerStatementTable(week: week)))));
    expect(tester.takeException(), isNull); // no overflow
    expect(find.byType(SingleChildScrollView), findsNWidgets(2));
    final nameBefore = tester.getTopLeft(find.text('CD'));
    await tester.drag(find.text('-5,000.00'), const Offset(-500, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('CD')), nameBefore); // the name did not move
  });
}
