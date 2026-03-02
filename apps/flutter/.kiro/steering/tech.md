# Technology Stack

## Framework & Language

- Flutter SDK 3.6.0+
- Dart language
- Material Design 3 (useMaterial3: true)

## Key Dependencies

- `provider` (6.1.2): State management using Provider pattern
- `http` (1.2.0): REST API communication
- `web_socket_channel` (3.0.1): Real-time WebSocket connections for live prices
- `flutter_secure_storage` (9.0.0): Secure credential storage
- `jwt_decode` (0.3.1): JWT token parsing
- `intl` (0.19.0): Date/time formatting and internationalization
- `cupertino_icons` (1.0.8): iOS-style icons

## Development Tools

- `flutter_lints` (5.0.0): Recommended linting rules
- `flutter_test`: Testing framework

## Common Commands

```bash
# Install dependencies
flutter pub get

# Run the app (development)
flutter run

# Build for Android
flutter build apk

# Build for iOS
flutter build ios

# Run tests
flutter test

# Analyze code
flutter analyze

# Clean build artifacts
flutter clean
```

## Build System

- Android: Gradle-based build system (see android/build.gradle)
- iOS: Xcode project configuration (see ios/)
- Uses standard Flutter build toolchain

## Backend Configuration

Backend URL is configured in `lib/utils/contants.dart` (default: http://127.0.0.1:3000)
