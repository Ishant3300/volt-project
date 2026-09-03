# White-label flavours

One codebase, one branch, multiple branded apps. Every feature and bug fix lands
once and every brand gets it — only the **name, logo and colours** differ.

| Brand | Dart define | Gradle flavour | Android applicationId | iOS bundle id | Primary colour |
|---|---|---|---|---|---|
| Apex (default) | `BRAND=apex` | `apex` | `com.apexlive.apex` | `com.apexlive.apex` | `#3F45C7` |
| Volt | `BRAND=volt` | `volt` | `com.voltlive.volt` | `com.voltlive.volt` | `#4E75FF` |

The backend is shared — `backendUrl` in `lib/utils/contants.dart` is **not**
per-brand.

---

## Building

Use the wrapper so the Gradle flavour and the Dart define can't drift apart
(passing only one gives you e.g. Volt's icon with Apex's colours):

```bash
scripts/flavor.sh apex run
scripts/flavor.sh volt run

scripts/flavor.sh apex build apk --release
scripts/flavor.sh volt build appbundle --release
```

Equivalent raw commands — **always pass both flags**:

```bash
flutter run                        --flavor apex --dart-define=BRAND=apex
flutter build apk --release        --flavor volt --dart-define=BRAND=volt
```

> **Heads-up:** now that Android product flavours exist, plain `flutter run` /
> `flutter build` fail with *"You must specify a --flavor"*. Always go through
> `scripts/flavor.sh`, or pass `--flavor` yourself.

Running the brand unit test for each flavour:

```bash
flutter test test/brand_flavor_test.dart
flutter test test/brand_flavor_test.dart --dart-define=BRAND=volt
```

---

## How it works

Branding resolves at **compile time** in `lib/config/app_brand.dart`:

```dart
const String kBrandId = String.fromEnvironment('BRAND', defaultValue: 'apex');
const bool   kIsVolt  = kBrandId == 'volt';

const Color kBrandPrimary = kIsVolt ? Color(0xFF4E75FF) : Color(0xFF3F45C7);
const String kAppName     = kIsVolt ? 'VOLT' : 'APEX';
```

Compile-time consts were chosen over a runtime config object on purpose: the app
had **408 brand-colour literals across 62 files, 201 of them inside `const`
contexts**. A runtime singleton would have forced `const` to be stripped from
200+ widget constructors — a huge diff, and worse for performance. Because
`String.fromEnvironment` is a `const` constructor, every existing
`const Color(...)` / `const TextStyle(...)` call site kept working untouched.

`lib/utils/contants.dart` re-exports `app_brand.dart`, so any file that already
imports the constants file gets the brand tokens with no extra import.

### Tokens

| Token | Use |
|---|---|
| `kAppName` | Display name (splash, login, `MaterialApp.title`) |
| `kLogoAsset` | In-app logo SVG path |
| `kBrandPrimary` | Primary colour — buttons, active states, spinners, focus borders |
| `kBrandGradientStart` / `kBrandGradientEnd` | Primary CTA gradient |
| `kBrandGradient` | Ready-made left→right `LinearGradient` |
| `kBrandId`, `kIsApex`, `kIsVolt` | Brand checks for anything conditional |

**Never hardcode a brand colour again** — use these tokens.

---

## Per-brand menu row style

The Profile, Settings, Admin Settings and Reports menus are styled per brand:

| | Apex | Volt |
|---|---|---|
| tile shape | circle | rounded square (radius 10) |
| tile fill | one neutral grey `#F1F5F9` | a **per-row accent colour** |
| icon colour | brand navy `#1E3A8A` | white |
| tile / icon size | 32 / 16 | 40 / 21 |
| row height | 50px (9px padding) | 68px (14px padding) |

All four screens render their rows through a single widget —
`BrandMenuRow` in `lib/widgets/brand_menu_row.dart` — so the styling lives in one
place instead of being duplicated per screen:

```dart
BrandMenuRow(
  label: 'Settings',        // also selects the Volt accent colour
  svgPath: kIconSettings,   // or: icon: Icons.settings
  onTap: () { ... },
  isDestructive: false,     // red label + chevron (Logout / Delete Account)
  horizontalPadding: 16,    // 0 when the row sits in a card that already pads
  showBottomBorder: false,
)
```

Knobs live in `lib/config/app_brand.dart`: `kMenuTileColourful`,
`kMenuTileIsCircle`, `kMenuTileCornerRadius`, `kMenuTileSize`,
`kMenuTileIconSize`, `kMenuRowVerticalPadding`, `kMenuRowIconLabelGap`.

`BrandMenuIconTile` exposes just the icon tile, for rows that share the look but
not the layout (e.g. the Two-Factor Auth row, which has a subtitle and a toggle
instead of a chevron).

### Accent colours

On colourful brands each row's tile colour comes from `menuAccentFor(label)` — a
label-keyed map in `brand_menu_row.dart`, so no screen has to thread colours
through its call sites. Labels not in the map fall back to a deterministic hash
into a small palette, so **a newly added menu item gets a sensible stable colour
with no code change**. To pin a specific colour, add the label to `_menuAccents`
or pass `accentColor:` explicitly.

---

## Adding a new brand

1. **`lib/config/app_brand.dart`** — add `kIsX` and extend each ternary chain.
2. **`assets/<brand>/`** — add `logo.svg`, `icon.png`, `adaptive_icon_foreground.png`
   (see `assets/volt/README.md` for how the PNGs are generated).
3. **`pubspec.yaml`** — add `- assets/<brand>/` under `assets:`.
4. **`flutter_launcher_icons-<brand>.yaml`** — copy the Volt file and repoint it,
   then run `dart run flutter_launcher_icons`.
5. **`android/app/build.gradle`** — add a `productFlavors` entry with its
   `applicationId` and `resValue "string", "app_name", "<NAME>"`.
6. **iOS** — add `ios/Flutter/brand-<brand>.xcconfig` plus the three
   `{Debug,Profile,Release}-<brand>.xcconfig` files, then the Xcode steps below.
7. Register the new app in Firebase (below).

`scripts/flavor.sh` discovers brands from the `flutter_launcher_icons-*.yaml`
files, so it needs no change.

---

## Firebase

> **Volt builds and installs fine, but its push notifications do not work yet.**

`android/app/google-services.json` contains a **placeholder** client for
`com.voltlive.volt`:

```json
{
  "mobilesdk_app_id": "1:975924213018:android:0000000000000000000000",
  "android_client_info": { "package_name": "com.voltlive.volt" }
}
```

That entry exists purely to satisfy the `com.google.gms.google-services` Gradle
plugin, which otherwise fails the build with *"No matching client found for
package name 'com.voltlive.volt'"*.

The app id is deliberately fake rather than a copy of Apex's real one. A fake id
makes Volt's FCM registration fail **cleanly**; copying Apex's id would have made
Volt silently register push tokens against the *Apex* Firebase app, which is much
harder to notice and debug.

Also note `lib/firebase_options.dart` hardcodes Apex's `appId`
(`1:975924213018:android:5ff2d2c2ed976c364168a3`) and `main.dart` passes it to
`Firebase.initializeApp`, so the Dart-side Firebase app is Apex's for both
flavours regardless of `google-services.json`.

### Making Volt's Firebase real (needed before shipping Volt)

This needs Firebase console access, so it can't be done from the repo.

1. Firebase console → project **`stockerdev-33a2c`** → **Add app**:
   - Android, package name `com.voltlive.volt`
   - iOS, bundle id `com.voltlive.volt`
2. Download the refreshed **`google-services.json`** and replace
   `android/app/google-services.json` — this also removes the placeholder above.
   One file covers *all* registered apps, so both flavours work from it; no
   per-flavour copies needed.
3. Download Volt's **`GoogleService-Info.plist`**. Because iOS reads a single
   fixed filename, keep one per flavour and select it in a build phase (or swap
   it in CI):
   ```
   ios/config/apex/GoogleService-Info.plist
   ios/config/volt/GoogleService-Info.plist
   ```
4. Make the Dart-side Firebase options brand-aware. `main.dart` currently calls
   `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`, and
   `lib/firebase_options.dart` **hardcodes Apex's `appId`**
   (`1:975924213018:android:5ff2d2c2ed976c364168a3`). Until this is updated, a
   Volt build registers FCM tokens against the *Apex* Firebase app. Easiest fix:
   re-run `flutterfire configure` per flavour, or branch on `kIsVolt` when
   choosing the `FirebaseOptions`.

### If the build starts failing on google-services again

Re-downloading `google-services.json` from the Firebase console **without** Volt
registered wipes the placeholder and the Volt build breaks again.
`scripts/flavor.sh` detects this and tells you which `applicationId` is missing
instead of letting Gradle fail cryptically. Either finish the registration above,
or re-add the placeholder client entry.

---

## iOS: flavour setup (done)

The iOS project is now wired for both flavours — `scripts/flavor.sh <brand> build ipa --release`
works the same as Android. The xcconfig files:

```
ios/Flutter/brand-apex.xcconfig      ios/Flutter/brand-volt.xcconfig
ios/Flutter/Debug-apex.xcconfig      ios/Flutter/Debug-volt.xcconfig
ios/Flutter/Profile-apex.xcconfig    ios/Flutter/Profile-volt.xcconfig
ios/Flutter/Release-apex.xcconfig    ios/Flutter/Release-volt.xcconfig
```

drive `PRODUCT_BUNDLE_IDENTIFIER`, `APP_DISPLAY_NAME` and
`ASSETCATALOG_COMPILER_APPICON_NAME` per brand. Each brand also has its own
`Info.plist` (`ios/Runner/Info.plist` for apex, `ios/Runner/Info-volt.plist` for
volt); both still read name/id/version from build variables.

What is set up inside `Runner.xcodeproj`:

- Build configurations `Debug-apex`, `Release-apex`, `Profile-apex`,
  `Debug-volt`, `Release-volt`, `Profile-volt` on the project, the **Runner**
  target and the **RunnerTests** target, each pointed at the matching xcconfig.
- Shared schemes named exactly `apex` and `volt` (Flutter matches `--flavor` to
  the scheme name); each scheme archives its brand's `Release-<brand>` config.

Resolved values (verified via `xcodebuild -showBuildSettings`):

| | apex | volt |
|---|---|---|
| bundle id | `com.apexlive.apex` | `com.voltlive.volt` |
| display name | APEX | VOLT |
| app icon | `AppIcon-apex` | `AppIcon-volt` |
| Info.plist | `Runner/Info.plist` | `Runner/Info-volt.plist` |

> **Heads-up:** because a `volt` scheme now exists, Flutter requires `--flavor`
> for iOS too — a bare `flutter build ipa` fails with *"You must specify a
> --flavor"*. Always go through `scripts/flavor.sh` or pass `--flavor`.

Verify:
```bash
scripts/flavor.sh apex run
scripts/flavor.sh volt run
```

---

## Verified

- `flutter analyze` → **218 issues, 0 errors**, byte-identical to the
  pre-change baseline.
- `flutter test test/brand_flavor_test.dart` passes for **both** flavours.
- `flutter test test/brand_menu_row_test.dart` passes for **both** flavours, and
  asserts the concrete rendering: Apex → circle tile, 32px, `#F1F5F9`, 50px rows;
  Volt → rounded tile, 40px, accent colour, 68px rows.
- **Release** APKs build for both brands via `scripts/flavor.sh <brand> build apk --release`.
- `aapt2 dump badging` on the release APKs:

  | APK | package | label |
  |---|---|---|
  | `app-apex-release.apk` | `com.apexlive.apex` | `APEX` |
  | `app-volt-release.apk` | `com.voltlive.volt` | `VOLT` |

- Launcher PNGs differ between flavours (`mipmap-xxxhdpi/ic_launcher.png`,
  `drawable-xxxhdpi/ic_launcher_foreground.png`); adaptive background
  `#000000` (Apex) vs `#FFFFFF` (Volt).
- **Not verified:** anything iOS — Xcode is not installed on this machine
  (Command Line Tools only), so no iOS build was possible.
- **Known gap:** Volt push notifications (see *Firebase* above).
