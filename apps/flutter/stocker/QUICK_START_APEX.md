# 🚀 Quick Start - APEX Branding

## See the New Splash Screen (Immediate)

```bash
flutter run
```

You'll see:
- ✨ Animated gradient logo (scales up)
- ✨ "APEX" text (slides up)
- ✨ "YOUR EDGE IN THE MARKET" subtitle
- ✨ Loading indicator

## Generate App Icon (One-time setup)

### Option 1: Automated (If you have Node.js)
```bash
generate_icon.bat
```

### Option 2: Manual (Easiest - Recommended)
1. Go to https://icon.kitchen/
2. Click "Upload Image" and select `assets\Subtract.svg`
3. Set Background Color: **White** (#FFFFFF)
4. Set Padding: **12%**
5. Click "Download"
6. From the downloaded zip, copy the 1024x1024 PNG to `assets\icon_with_bg.png`
7. Run:
```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

### Option 3: Use Simple Script
```bash
generate_icon_simple.bat
```
(This will guide you through the manual process)

## That's It! 🎉

Your app now has:
- ✅ APEX branding on splash screen
- ✅ Animated logo entrance
- ⏳ App icon (after running icon generation)

## Troubleshooting

**Splash screen not showing?**
- Make sure you ran `flutter pub get`
- Try `flutter clean` then `flutter run`

**Icon generation failed?**
- Use the manual method (Option 2) - it's the most reliable
- Just create the PNG online and run flutter_launcher_icons

**Icon not changing on device?**
- Uninstall and reinstall the app
- For release: `flutter build apk` then install

**Need help?**
- See `APEX_BRANDING_CHANGES.md` for details
- See `ICON_SETUP_INSTRUCTIONS.md` for more options
