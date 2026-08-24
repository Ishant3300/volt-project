@echo off
echo ========================================
echo APEX App Icon Generator
echo ========================================
echo.

REM Check if Node.js is installed
node --version >nul 2>&1
if errorlevel 1 (
    echo [WARNING] Node.js is not installed or not in PATH
    echo.
    echo Please use the manual method instead:
    echo 1. Go to: https://icon.kitchen/
    echo 2. Upload: assets\Subtract.svg
    echo 3. Set Background: White
    echo 4. Set Padding: 12%%
    echo 5. Download and save as: assets\icon_with_bg.png
    echo 6. Run: flutter pub run flutter_launcher_icons
    echo.
    pause
    exit /b 1
)

echo [1/3] Installing Sharp library for image processing...
call npm install sharp

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to install Sharp
    echo Please use the manual method (see ICON_SETUP_INSTRUCTIONS.md)
    pause
    exit /b 1
)

echo.
echo [2/3] Generating app icon with white background...
node generate_icon.js

if errorlevel 1 (
    echo.
    echo [ERROR] Failed to generate icon
    echo Please use the manual method (see ICON_SETUP_INSTRUCTIONS.md)
    pause
    exit /b 1
)

echo.
echo [3/3] Installing flutter_launcher_icons and generating platform icons...
call flutter pub get
call flutter pub run flutter_launcher_icons

echo.
echo ========================================
echo SUCCESS! App icons have been generated
echo ========================================
echo.
echo The APEX logo is now set as your app icon with white background.
echo.
echo Next steps:
echo 1. Run your app to see the new icon
echo 2. For release builds, the icon will appear on device home screen
echo.
pause
