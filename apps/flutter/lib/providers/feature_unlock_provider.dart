import 'package:flutter/foundation.dart';

/// Gates the full app behind a tap gesture. Deliberately in-memory only —
/// never persisted (no SecureStorageService) — so every cold start and every
/// return from background defaults back to locked, regardless of role.
class FeatureUnlockProvider extends ChangeNotifier {
  bool _isUnlocked = false;

  bool get isUnlocked => _isUnlocked;

  void unlock() {
    if (_isUnlocked) return;
    _isUnlocked = true;
    notifyListeners();
  }

  void lock() {
    if (!_isUnlocked) return;
    _isUnlocked = false;
    notifyListeners();
  }
}
