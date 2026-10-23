import 'package:flutter/foundation.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/config/practice_only.dart';

/// Tracks whether the current session is an investor (read-only) login.
/// Persisted to secure storage so it survives app restarts.
class InvestorModeProvider with ChangeNotifier {
  static const _storageKey = 'is_investor_mode';
  final SecureStorageService _storage = SecureStorageService();

  bool _isInvestor = false;
  // Investor logins are live accounts — never in the practice-only build.
  bool get isInvestor => !kPracticeOnly && _isInvestor;

  /// Call after login to set the investor mode state.
  Future<void> setInvestor(bool value) async {
    _isInvestor = value;
    await _storage.storage.write(key: _storageKey, value: value.toString());
    notifyListeners();
  }

  /// Call on app startup to restore persisted state.
  Future<void> loadFromStorage() async {
    try {
      final value = await _storage.storage.read(key: _storageKey);
      _isInvestor = value == 'true';
    } catch (_) {
      _isInvestor = false;
    }
    notifyListeners();
  }

  /// Call on logout to reset the state.
  Future<void> clear() async {
    _isInvestor = false;
    await _storage.storage.delete(key: _storageKey);
    notifyListeners();
  }
}
