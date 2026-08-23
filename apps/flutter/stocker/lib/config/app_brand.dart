import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// White-label brand configuration.
///
/// All branding (name, logo, colours) is resolved at COMPILE TIME so that every
/// existing `const Color(...)` / `const TextStyle(...)` call site keeps working
/// unchanged. A runtime singleton would have forced us to strip `const` from
/// 200+ widget constructors across 62 files.
///
/// Selecting a flavour:
///   Apex (default) →  flutter run
///   Volt           →  flutter run --dart-define=BRAND=volt
///
/// Adding a new white-label brand:
///   1. add a `kIsX` const below,
///   2. extend each ternary chain with the new brand's value,
///   3. drop the logo into `assets/<brand>/`,
///   4. add an Android productFlavor + iOS xcconfig.
/// No other file needs to change.
/// ─────────────────────────────────────────────────────────────────────────────

/// Raw brand id supplied via `--dart-define=BRAND=...`. Defaults to `apex`.
const String kBrandId = String.fromEnvironment('BRAND', defaultValue: 'apex');

/// Per-brand compile-time switches. `String.fromEnvironment` is a const
/// constructor and `==` on const strings is const-evaluable, so these remain
/// usable inside `const` expressions.
const bool kIsVolt = kBrandId == 'volt';
const bool kIsApex = !kIsVolt;

// ─── Identity ───────────────────────────────────────────────────────────────

/// Display name shown on the splash screen, login screen and MaterialApp title.
const String kAppName = kIsVolt ? 'VOLT' : 'APEX';

/// Brand logo (SVG) shown on the splash and login screens.
const String kLogoAsset =
    kIsVolt ? 'assets/volt/logo.svg' : 'assets/Subtract.svg';

// ─── Brand colours ──────────────────────────────────────────────────────────

/// Primary brand colour — buttons, active states, spinners, focus borders.
const Color kBrandPrimary =
    kIsVolt ? Color(0xFF4E75FF) : Color(0xFF3F45C7);

/// Gradient start for primary CTAs (login button, badges, avatars).
const Color kBrandGradientStart =
    kIsVolt ? Color(0xFF4E75FF) : Color(0xFFC6529E);

/// Gradient end for primary CTAs.
const Color kBrandGradientEnd =
    kIsVolt ? Color(0xFF2E55DF) : Color(0xFF3B43C9);

/// Standard left→right brand gradient used on primary CTAs.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kBrandGradientStart, kBrandGradientEnd],
);
