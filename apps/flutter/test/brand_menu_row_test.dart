import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/config/app_brand.dart';
import 'package:stocker/widgets/brand_menu_row.dart';

/// Verifies the menu row renders in the active brand's style.
///
///   Apex:  flutter test test/brand_menu_row_test.dart
///   Volt:  flutter test test/brand_menu_row_test.dart --dart-define=BRAND=volt
void main() {
  /// The icon tile is the first Container that actually paints a BoxDecoration.
  BoxDecoration tileDecorationOf(WidgetTester tester) {
    final container =
        tester.widgetList<Container>(find.byType(Container)).firstWhere(
              (c) => c.decoration is BoxDecoration,
            );
    return container.decoration! as BoxDecoration;
  }

  Future<void> pumpRow(WidgetTester tester, {String label = 'Settings'}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandMenuRow(
            label: label,
            icon: Icons.settings,
            onTap: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('renders the label and a chevron', (tester) async {
    await pumpRow(tester);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('tile shape and size match the active brand', (tester) async {
    await pumpRow(tester);
    final decoration = tileDecorationOf(tester);
    final tile = tester.getSize(
      find
          .descendant(
            of: find.byType(BrandMenuIconTile),
            matching: find.byType(Container),
          )
          .first,
    );

    if (kIsVolt) {
      // Rounded square, larger, filled with the row's accent colour.
      expect(decoration.shape, BoxShape.rectangle);
      expect(decoration.borderRadius, isNotNull);
      expect(tile.width, 36.0);
      expect(decoration.color, menuAccentFor('Settings'));
    } else {
      // Circle, compact, single neutral grey — unchanged Apex look.
      expect(decoration.shape, BoxShape.circle);
      expect(decoration.borderRadius, isNull);
      expect(tile.width, 32.0);
      expect(decoration.color, kMenuTileNeutralBg);
    }
  });

  testWidgets('Volt rows are taller than Apex rows', (tester) async {
    await pumpRow(tester);
    final rowHeight = tester.getSize(find.byType(BrandMenuRow)).height;
    // tile height + 2 * vertical padding
    final expected = kMenuTileSize + (kMenuRowVerticalPadding * 2);
    expect(rowHeight, expected);
    expect(rowHeight, kIsVolt ? 54.0 : 50.0);
  });

  testWidgets('destructive rows use the destructive foreground',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrandMenuRow(
            label: 'Logout',
            icon: Icons.logout,
            isDestructive: true,
            onTap: () {},
          ),
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Logout'));
    expect(label.style!.color, kMenuRowDestructiveColor);
  });

  testWidgets('chevrons align regardless of label length', (tester) async {
    // Regression: Flexible(flex:1) + Spacer(flex:1) split the free space, so the
    // chevron drifted left/right depending on how long the label was.
    const labels = [
      'Reports',
      'Settings',
      'Admin Setting',
      'Master And User Management',
    ];

    final xPositions = <double>[];
    for (final label in labels) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body:
                BrandMenuRow(label: label, icon: Icons.settings, onTap: () {}),
          ),
        ),
      );
      xPositions.add(tester.getTopRight(find.byIcon(Icons.chevron_right)).dx);
    }

    expect(
      xPositions.every((x) => x == xPositions.first),
      isTrue,
      reason: 'chevron x positions differ across label lengths: $xPositions',
    );
  });

  testWidgets('long labels wrap onto a second line instead of truncating',
      (tester) async {
    // Narrow surface so a real menu label genuinely runs out of room, the way
    // it does on a phone inside a padded card.
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpRow(tester, label: 'Reports');
    final shortRow = tester.getSize(find.byType(BrandMenuRow)).height;

    await pumpRow(tester, label: 'Master And User Management');
    final longRow = tester.getSize(find.byType(BrandMenuRow)).height;

    final text = tester.widget<Text>(find.text('Master And User Management'));
    // No single-line clamp and no ellipsis — the label may wrap.
    expect(text.maxLines, isNull);
    expect(text.overflow, anyOf(isNull, TextOverflow.clip));

    // Wrapping makes the row taller than a single-line row.
    expect(longRow, greaterThan(shortRow),
        reason: 'long label did not wrap (short=$shortRow long=$longRow)');

    // Nothing overflowed.
    expect(tester.takeException(), isNull);
  });

  test('accent colours are deterministic and defined for known labels', () {
    expect(menuAccentFor('Logout'), menuAccentFor('Logout'));
    // Unmapped labels still resolve to a stable colour rather than throwing.
    expect(menuAccentFor('Some Brand New Row'),
        menuAccentFor('Some Brand New Row'));
  });
}
