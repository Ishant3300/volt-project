@echo off
echo ========================================
echo APEX App Icon Generator (Simple Method)
echo ========================================
echo.
echo This will use flutter_launcher_icons to generate your app icon.
echo.
echo IMPORTANT: You need to create the base icon first!
echo.
echo Please follow these steps:
echo.
echo 1. Go to: https://icon.kitchen/
echo 2. Click "Upload Image"
echo 3. Select: assets\Subtract.svg
echo 4. Set Background: White (#FFFFFF)
echo 5. Set Padding: 12%%
echo 6. Click "Download"
echo 7. Extract the downloaded zip
echo 8. Copy the 1024x1024 PNG to: assets\icon_with_bg.png
echo.
echo Once you have created assets\icon_with_bg.png, press any key to continue...
pause >nul

echo.
echo Checking if icon file exists...
if not exist "assets\icon_with_bg.png" (
    echo [ERROR] File not found: assets\icon_with_bg.png
    echo Please create the icon file first using the steps above.
    echo.
    pause
    exit /b 1
)

echo [OK] Icon file found!
echo.
echo Installing flutter_launcher_icons...
call flutter pub get

echo.
echo Generating platform-specific icons...
call flutter pub run flutter_launcher_icons

echo.
echo ========================================
echo SUCCESS! App icons have been generated
echo ========================================
echo.
echo Next steps:
echo 1. Rebuild your app: flutter run
echo 2. Or build release: flutter build apk
echo 3. Install on device to see the new icon
echo.
pause
