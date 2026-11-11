import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/services/broker_service.dart';
import 'package:stocker/views/broker_create_section.dart';
import 'package:stocker/views/broker_share_view.dart';

/// Broker inside the Create forms + Index / Stock and per-script broker rates
/// (owner, 12 Nov 2026).   flutter test test/broker_create_test.dart
void main() {
  // The paying master's own rows (what the form loads for the owner).
  final nfoRows = <Map<String, dynamic>>[
    {'script_name': 'NIFTY', 'brk_value': 2, 'category': 'INDEX'},
    {'script_name': 'BANKNIFTY', 'brk_value': 3, 'category': 'INDEX'},
    {'script_name': 'RELIANCE', 'brk_value': 2, 'category': 'STOCK'},
    {'script_name': 'TCS', 'brk_value': 4, 'category': 'STOCK'},
  ];

  group('brokerRoom', () {
    test('flat client 6: room = 6 − the master\'s highest own rate on any script = 2', () {
      expect(brokerRoom(nfoRows, (s, c) => 6), 2);
    });
    test('Customize: Index 8 / Stock 6 -> Index room 5, Stock room 2, whole segment 2', () {
      double rate(String s, String? c) => c == 'INDEX' ? 8 : 6;
      expect(brokerRoom(nfoRows, rate, include: (s, c) => c == 'INDEX'), 5);
      expect(brokerRoom(nfoRows, rate, include: (s, c) => c == 'STOCK'), 2);
      expect(brokerRoom(nfoRows, rate), 2);
    });
    test('one script; never below 0; unknown when nothing is loaded', () {
      expect(brokerRoom(nfoRows, (s, c) => 6, include: (s, c) => s == 'NIFTY'), 4);
      expect(brokerRoom(nfoRows, (s, c) => 1), 0);
      expect(brokerRoom(null, (s, c) => 6), isNull);
      expect(brokerRoom(nfoRows, (s, c) => null), isNull); // no client rate typed yet
    });
  });

  group('NewAccountBrokerDraft', () {
    test('rates: flat + Index/Stock (open panel) + MCX scripts; closed panels ignored', () {
      final d = NewAccountBrokerDraft()..allowed = true..enabled = true;
      d.flat('NFO-FUT').text = '1';
      d.category('NFO-FUT', 'INDEX').text = '3';
      d.category('NFO-FUT', 'STOCK').text = '';
      d.flat('MCX-FUT').text = '50';
      d.script('MCX-FUT', 'GOLD').text = '150';
      d.category('NFO-OPT', 'INDEX').text = '20'; // NFO-OPT panel closed -> ignored
      final rates = d.rates(
        exchanges: ['NFO-FUT', 'NFO-OPT', 'MCX-FUT'],
        typeOf: (ex) => ex == 'NFO-FUT' ? 'TURNOVER WISE' : 'LOT WISE',
        customizedCategory: (ex) => ex == 'NFO-FUT',
        customizedScript: (ex) => ex == 'MCX-FUT',
      );
      expect(rates, [
        {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 1.0},
        {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 3.0, 'category': 'INDEX'},
        {'segment': 'MCX-FUT', 'type': 'LOT WISE', 'value': 50.0},
        {'segment': 'MCX-FUT', 'type': 'LOT WISE', 'value': 150.0, 'script': 'GOLD'},
      ]);
    });

    test('checks before Create: broker chosen, % within max, rates within room', () {
      final d = NewAccountBrokerDraft()..allowed = true..enabled = true;
      expect(checkNewAccountBroker(d, pnlMax: 90, brkMax: 60, overLimits: []), contains('Choose a broker'));
      d.brokerId = 'new';
      expect(checkNewAccountBroker(d, pnlMax: 90, brkMax: 60, overLimits: []), contains('new broker name'));
      d.newName.text = 'Ramesh';
      d.pnl.text = '95';
      expect(checkNewAccountBroker(d, pnlMax: 90, brkMax: 60, overLimits: []), 'Broker P&L sharing can be at most 90%.');
      d.pnl.text = '20';
      expect(checkNewAccountBroker(d, pnlMax: 90, brkMax: 60, overLimits: ['NFO-FUT (max 2)']), contains('NFO-FUT (max 2)'));
      expect(checkNewAccountBroker(d, pnlMax: 90, brkMax: 60, overLimits: []), isNull);
      d.enabled = false; // switched off -> nothing to check
      d.pnl.text = '999';
      expect(checkNewAccountBroker(d, pnlMax: 90, brkMax: 60, overLimits: []), isNull);
    });
  });

  group('Broker screen settings (existing account)', () {
    final limits = <String, dynamic>{
      'kind': 'client',
      'target': {'name': 'AB'},
      'paying_master': {'name': 'Harish'},
      'pnl_max': 90,
      'brk_max': 60,
      'segments': [
        {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'x_max': 2, 'categories': {'INDEX': {'x_max': 4}, 'STOCK': {'x_max': 2}}},
        {'segment': 'MCX-FUT', 'type': 'LOT WISE', 'x_max': 0, 'scripts': [{'script': 'GOLD', 'below': 500, 'paying': 300, 'x_max': 200}, {'script': 'SILVER', 'below': 300, 'paying': 300, 'x_max': 0}]},
      ],
    };

    test('Index / Stock and per-script rates are sent only while Customize is open, each within its own max', () {
      final d = BrokerSettingsDraft();
      d.rate('NFO-FUT').text = '2';
      d.category('NFO-FUT', 'INDEX').text = '4';
      d.script('MCX-FUT', 'GOLD').text = '200';
      expect(d.toSettings(limits)['rates'], [{'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 2.0}]); // panels closed
      d.customized.addAll(['NFO-FUT', 'MCX-FUT']);
      expect(d.toSettings(limits)['rates'], [
        {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 2.0},
        {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 4.0, 'category': 'INDEX'},
        {'segment': 'MCX-FUT', 'type': 'LOT WISE', 'value': 200.0, 'script': 'GOLD'},
      ]);
      d.category('NFO-FUT', 'STOCK').text = '3';
      expect(() => d.toSettings(limits), throwsA(isA<BrokerApiException>().having((e) => e.message, 'm', 'NFO-FUT Stock: the broker can get at most 2 paisa.')));
      d.category('NFO-FUT', 'STOCK').text = '';
      d.script('MCX-FUT', 'SILVER').text = '1';
      expect(() => d.toSettings(limits), throwsA(isA<BrokerApiException>().having((e) => e.message, 'm', 'MCX-FUT SILVER: the broker can get at most 0 ₹/lot.')));
    });

    test('fillFrom routes saved rates back to their boxes and opens Customize', () {
      final d = BrokerSettingsDraft()
        ..fillFrom({
          'pnl_share_pct': 0,
          'brk_share_pct': 10,
          'rates': [
            {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 1},
            {'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 3, 'category': 'INDEX'},
            {'segment': 'MCX-FUT', 'type': 'LOT WISE', 'value': 150, 'script': 'GOLD'},
          ],
        });
      expect([d.rate('NFO-FUT').text, d.category('NFO-FUT', 'INDEX').text, d.script('MCX-FUT', 'GOLD').text, d.brk.text], ['1', '3', '150', '10']);
      expect(d.customized, {'NFO-FUT', 'MCX-FUT'});
    });

    test('rate labels', () {
      expect(brokerRateText({'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 3, 'category': 'INDEX'}), 'NFO-FUT Index 3 paisa');
      expect(brokerRateText({'segment': 'MCX-FUT', 'type': 'LOT WISE', 'value': 150, 'script': 'GOLD'}), 'MCX-FUT GOLD 150 ₹/lot');
      expect(brokerRateText({'segment': 'NFO-FUT', 'type': 'TURNOVER WISE', 'value': 2}), 'NFO-FUT 2 paisa');
    });
  });

  testWidgets('card: off shows a hint only; on shows broker, P&L % and Brk % with their max', (tester) async {
    final d = NewAccountBrokerDraft()..allowed = true;
    Widget app() => MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (ctx, set) => BrokerCreateCard(
                  draft: d,
                  accountKind: 'client',
                  payingName: 'Harish',
                  pnlMax: 90,
                  brkMax: 60,
                  onToggle: (v) => set(() => d.enabled = v),
                  onChanged: () => set(() {}),
                ),
              ),
            ),
          ),
        );
    await tester.pumpWidget(app());
    expect(find.text('Add broker'), findsOneWidget);
    expect(find.textContaining('P&L sharing %'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(find.text('P&L sharing % · max 90'), findsOneWidget);
    expect(find.text('Brk sharing % · max 60'), findsOneWidget);
    expect(find.text('Select broker…'), findsOneWidget);
  });

  testWidgets('broker box: hint shows the room, turns red above it', (tester) async {
    final c = TextEditingController();
    Widget box() => MaterialApp(home: Scaffold(body: brokerRateBox(c, 2)));
    await tester.pumpWidget(box());
    expect(find.text('≤2'), findsOneWidget);
    c.text = '3';
    await tester.pumpWidget(box());
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style?.color, isNot(equals(Colors.black)));
    final decorated = tester.widget<Container>(find.byType(Container).first);
    final border = (decorated.decoration as BoxDecoration).border as Border;
    expect(border.top.color.toARGB32(), const Color(0xFFC94A4A).toARGB32()); // kColorSell
  });
}
