import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocker/config/app_brand.dart';

/// Verifies the compile-time brand switch resolves correctly for each flavour.
///
///   Apex:  flutter test test/brand_flavor_test.dart
///   Volt:  flutter test test/brand_flavor_test.dart --dart-define=BRAND=volt
void main() {
  test('brand constants resolve for the compiled flavour', () {
    if (kIsVolt) {
      expect(kBrandId, 'volt');
      expect(kAppName, 'VOLT');
      expect(kLogoAsset, 'assets/volt/logo.svg');
      expect(kBrandPrimary, const Color(0xFF4E75FF));
      expect(kBrandGradientStart, const Color(0xFF4E75FF));
      expect(kIsApex, isFalse);
    } else {
      expect(kBrandId, 'apex');
      expect(kAppName, 'APEX');
      expect(kLogoAsset, 'assets/Subtract.svg');
      expect(kBrandPrimary, const Color(0xFF3F45C7));
      expect(kBrandGradientStart, const Color(0xFFC6529E));
      expect(kIsApex, isTrue);
    }
  });

  test('gradient is wired to the brand gradient colours', () {
    expect(kBrandGradient.colors, [kBrandGradientStart, kBrandGradientEnd]);
  });
}
