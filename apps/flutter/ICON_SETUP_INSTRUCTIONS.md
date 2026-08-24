# App Icon Setup Instructions

## Overview
Your app now uses the APEX logo (Subtract.svg) with a white background for the app icon.

## Steps to Generate and Set App Icons

### Option 1: Using Online Tool (Easiest)
1. Go to https://www.appicon.co/ or https://icon.kitchen/
2. Upload your `assets/Subtract.svg` file
3. Set background color to white (#FFFFFF)
4. Add some padding (10-15%) so the logo doesn't touch edges
5. Download the generated icon pack
6. Replace the icons in:
   - `android/app/src/main/res/mipmap-*/ic_launcher.png`
   - `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

### Option 2: Using flutter_launcher_icons Package
1. Add to `pubspec.yaml` under `dev_dependencies`:
```yaml
flutter_launcher_icons: ^0.13.1
```

2. Add configuration in `pubspec.yaml`:
```yaml
flutter_launcher_icons:
  android: true
  ios: true
  image_path: "assets/icon_with_bg.png"
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/Subtract.svg"
```

3. Create a PNG version with white background (1024x1024):
   - Use any image editor (Figma, Photoshop, GIMP, Inkscape)
   - Place the SVG on white background with padding
   - Export as `assets/icon_with_bg.png`

4. Run:
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

### Option 3: Manual Setup (Android)
1. Create PNG versions at these sizes with white background:
   - mipmap-mdpi: 48x48
   - mipmap-hdpi: 72x72
   - mipmap-xhdpi: 96x96
   - mipmap-xxhdpi: 144x144
   - mipmap-xxxhdpi: 192x192

2. Replace files in `android/app/src/main/res/mipmap-*/ic_launcher.png`

### Option 4: Manual Setup (iOS)
1. Create PNG versions at these sizes:
   - 20x20, 29x29, 40x40, 58x58, 60x60, 76x76, 80x80, 87x87, 120x120, 152x152, 167x167, 180x180, 1024x1024

2. Add to `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

## Quick Fix for Development
For immediate testing, you can:
1. Create a simple 1024x1024 PNG with white background and centered logo
2. Use an online converter to generate all sizes
3. Replace the default Flutter icons

## Notes
- The SVG has a transparent background, so always add white background
- Add 10-15% padding around the logo for better appearance
- Test on both light and dark mode devices
- The splash screen already uses the SVG with animations
