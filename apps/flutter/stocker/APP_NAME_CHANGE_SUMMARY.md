# App Name Change: Stocker → APEX

## Summary
The application has been successfully renamed from "Stocker" to "APEX" across all user-facing elements.

## Changes Made

### 1. Android Configuration ✅
**File**: `android/app/src/main/AndroidManifest.xml`
- Changed `android:label` from "stocker" to "APEX"
- App name now displays as "APEX" on Android devices

### 2. iOS Configuration ✅
**File**: `ios/Runner/Info.plist`
- Changed `CFBundleDisplayName` to "APEX"
- Changed `CFBundleName` to "APEX"
- App name now displays as "APEX" on iOS devices

### 3. Flutter App Configuration ✅
**File**: `lib/main.dart`
- Changed MaterialApp `title` to "APEX"
- Updated startup log message from "Starting Stocker App" to "Starting APEX App"

### 4. Package Metadata ✅
**File**: `pubspec.yaml`
- Description already set to: "APEX - Your Edge in the Market"
- Package name remains `stocker` (this is correct - package names should not change)

## What Was NOT Changed (Intentionally)

### Package Name
- `pubspec.yaml` package name remains `stocker`
- All import statements remain as `package:stocker/...`
- **Reason**: Changing package names requires extensive refactoring and can break existing installations

### Firebase Notification Channel
- Channel ID remains `stocker_trades`
- **Reason**: Changing this would break notifications for existing app installations

### Folder Structure
- Root folder remains `stocker/`
- **Reason**: Folder names don't affect the user experience

## User-Facing Impact

Users will now see:
- ✅ App name "APEX" on their home screen (Android & iOS)
- ✅ App title "APEX" in the app bar
- ✅ "APEX" in system settings and app switcher

## Technical Notes

The app is fully functional with the new name. No code changes were required beyond the configuration files listed above. All imports and internal references correctly use the package name `stocker`, which is the standard Flutter convention.

## Build Instructions

To build the app with the new name:

```bash
# Clean previous builds
flutter clean

# Get dependencies
flutter pub get

# Build for Android
flutter build apk --release

# Build for iOS
flutter build ios --release
```

The generated APK/IPA will show "APEX" as the app name when installed.
