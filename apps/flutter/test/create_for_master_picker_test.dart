import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/widgets/create_for_master_picker.dart';

// "Create account for": defaults to Myself, searchable list of downline
// masters (name + ID only), masters without sub-master rights greyed out
// when creating a sub-master, admin creating a client must pick a master.
void main() {
  final masters = [
    {'id': 'a', 'name': '(463) DBH', 'username': '640988', 'add_master': true},
    {'id': 'b', 'name': 'GM11', 'username': '652874', 'add_master': false},
  ];

  Future<List<String?>> pump(WidgetTester t,
      {String? selfLabel = 'Myself — harry (839276)',
      bool requireAddMaster = false,
      String? selectedId}) async {
    final picked = <String?>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CreateForMasterPicker(
          masters: masters,
          selectedId: selectedId,
          selfLabel: selfLabel,
          loading: false,
          requireAddMaster: requireAddMaster,
          onSelect: picked.add,
        ),
      ),
    ));
    return picked;
  }

  testWidgets('defaults to Myself; list shows name (ID) only; pick a master',
      (t) async {
    final picked = await pump(t);
    expect(find.text('Myself — harry (839276)'), findsOneWidget);
    await t.tap(find.text('Myself — harry (839276)'));
    await t.pumpAndSettle();
    expect(find.text('(463) DBH (640988)'), findsOneWidget);
    expect(find.text('GM11 (652874)'), findsOneWidget);
    expect(find.text('no sub-master rights'), findsNothing); // client: all pickable
    await t.tap(find.text('GM11 (652874)'));
    await t.pumpAndSettle();
    expect(picked, ['b']);
  });

  testWidgets('sub-master: masters without rights are greyed and not pickable',
      (t) async {
    final picked = await pump(t, requireAddMaster: true);
    await t.tap(find.text('Myself — harry (839276)'));
    await t.pumpAndSettle();
    expect(find.text('no sub-master rights'), findsOneWidget);
    await t.tap(find.text('GM11 (652874)'));
    await t.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.text('GM11 (652874)'), findsOneWidget); // sheet still open
  });

  testWidgets('search filters by name or ID', (t) async {
    await pump(t);
    await t.tap(find.text('Myself — harry (839276)'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), '6409');
    await t.pumpAndSettle();
    expect(find.text('(463) DBH (640988)'), findsOneWidget);
    expect(find.text('GM11 (652874)'), findsNothing);
  });

  testWidgets('back to Myself from a master', (t) async {
    final picked = await pump(t, selectedId: 'a');
    expect(find.text('(463) DBH (640988)'), findsOneWidget);
    await t.tap(find.text('(463) DBH (640988)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Myself — harry (839276)'));
    await t.pumpAndSettle();
    expect(picked, [null]);
  });

  testWidgets('admin creating a client: no Myself, must select a master',
      (t) async {
    await pump(t, selfLabel: null);
    expect(find.text('Select master'), findsOneWidget);
    await t.tap(find.text('Select master'));
    await t.pumpAndSettle();
    expect(find.textContaining('Myself'), findsNothing);
  });
}
