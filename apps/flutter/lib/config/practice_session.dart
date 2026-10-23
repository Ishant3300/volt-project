import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'practice_only.dart';

/// Practice (paper trading) accounts talk to a separate backend with
/// simulated prices (apex-project docs/practice-trading.md). A practice
/// account's login ID is its email, so any username with '@' is practice —
/// live user IDs never contain one.
///
/// [active] drives the backend address (see `backendUrl` in contants.dart and
/// ApiService), the permanent banner, token labels and the hidden screens.
class PracticeSession {
  PracticeSession._();

  static const String liveUrl = 'https://apexlive-api.mynpe.in';
  static const String practiceUrl = 'https://apexlive-api.mynpe.in/practice';

  /// Always on in the practice-only build (config/practice_only.dart).
  static final ValueNotifier<bool> active = ValueNotifier<bool>(kPracticeOnly);
  static bool get isActive => kPracticeOnly || active.value;

  static const _key = 'practice_mode';
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static bool isPracticeUsername(String? username) =>
      (username ?? '').contains('@');

  /// Current backend: practice or live.
  static String get baseUrl =>
      (kPracticeOnly || active.value) ? practiceUrl : liveUrl;

  /// An ApiService created with either backend address always uses the
  /// current one, so long-lived instances follow a login / account switch.
  static String resolve(String url) =>
      (url == liveUrl || url == practiceUrl) ? baseUrl : url;

  /// Restore at cold start (before the token is used).
  static Future<void> load() async {
    if (kPracticeOnly) return;
    try {
      active.value = (await _storage.read(key: _key)) == 'true';
    } catch (_) {
      active.value = false;
    }
  }

  static Future<void> set(bool value) async {
    if (kPracticeOnly) return;
    active.value = value;
    try {
      await _storage.write(key: _key, value: value ? 'true' : 'false');
    } catch (_) {}
  }

  /// Set from a login ID (practice if it is an email).
  static Future<void> setForUsername(String? username) =>
      set(isPracticeUsername(username));

  /// "1,00,000.00 tokens" style label for practice money; plain value for live.
  static String money(String formatted) =>
      active.value ? '$formatted tokens' : formatted;
}
