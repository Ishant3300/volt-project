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
const Color kBrandPrimary = kIsVolt ? Color(0xFF4E75FF) : Color(0xFF3F45C7);

/// Gradient start for primary CTAs (login button, badges, avatars).
const Color kBrandGradientStart =
    kIsVolt ? Color(0xFF4E75FF) : Color(0xFFC6529E);

/// Gradient end for primary CTAs.
const Color kBrandGradientEnd = kIsVolt ? Color(0xFF2E55DF) : Color(0xFF3B43C9);

/// Standard left→right brand gradient used on primary CTAs.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kBrandGradientStart, kBrandGradientEnd],
);

// ─── Typography ─────────────────────────────────────────────────────────────

/// Font family applied app-wide via ThemeData and every explicit TextStyle.
/// Apex uses Inter (loaded via google_fonts) — already one of the typography
/// spec's own approved web/Android alternatives to SF Pro. Volt previously
/// used the bundled 'Manrope', which isn't on that list; switched to
/// 'Roboto' instead — deliberately NOT registered as a custom font asset,
/// so Flutter falls back to each platform's real system default when it
/// can't resolve the family: true Roboto on Android, San Francisco on iOS.
/// That fallback IS the spec's own "SF Pro on iOS / Roboto on Android" ask,
/// with no asset changes needed.
const String kFontFamily = kIsVolt ? 'Roboto' : 'Inter';

// ─── Menu row style (Profile / Settings / Admin Settings / Reports) ─────────
//
// Apex: small light-grey CIRCLE behind a brand-tinted icon, compact rows.
// Volt: larger ROUNDED-SQUARE tile filled with a per-item accent colour behind
//       a white icon, and taller rows with bigger icons.
//
// Consumed exclusively by `BrandMenuRow` (lib/widgets/brand_menu_row.dart) —
// the four menu screens delegate their row rendering to it, so this is the only
// place menu styling is defined.

/// `true`  → each row's tile is filled with its own accent colour, icon white.
/// `false` → every tile uses the same neutral background, icon brand-tinted.
const bool kMenuTileColourful = kIsVolt;

/// Tile shape: circle (Apex) vs rounded square (Volt).
const bool kMenuTileIsCircle = !kIsVolt;

/// Corner radius used when [kMenuTileIsCircle] is false.
const double kMenuTileCornerRadius = 10.0;

/// Width/height of the icon tile.
const double kMenuTileSize = kIsVolt ? 36.0 : 32.0;

/// Icon size inside the tile.
const double kMenuTileIconSize = kIsVolt ? 19.0 : 16.0;

/// Vertical padding on each row (same for both brands; Volt rows are still
/// slightly taller via their larger tile).
// Volt was 14 (68px rows, ~7 items per screen); tightened to 9 (54px rows)
// in the cross-device density pass — same icons/colours, just less padding.
const double kMenuRowVerticalPadding = 9.0;

/// Gap between the icon tile and the label.
const double kMenuRowIconLabelGap = kIsVolt ? 14.0 : 16.0;

// Neutral (Apex) tile colours.
const Color kMenuTileNeutralBg = Color(0xFFF1F5F9);
const Color kMenuTileNeutralIcon = Color(0xFF1E3A8A);
const Color kMenuTileDestructiveBg = Color(0xFFFEF2F2);

// Shared row colours (identical across brands).
const Color kMenuRowLabelColor = Color(0xFF1E293B);
const Color kMenuRowDestructiveColor = Color(0xFFEF4444);
const Color kMenuRowChevronColor = Color(0xFF94A3B8);
const Color kMenuRowDividerColor = Color(0xFFF1F5F9);
