import 'package:flutter/foundation.dart';

/// Previously gated the full app behind a hidden long-press gesture on the
/// Watchlist nav icon (locked by default on every cold start / return from
/// background, never persisted). Turned off for now, per explicit request —
/// every feature stays visible without needing to unlock anything. lock()/
/// unlock() are kept intact (unused currently) rather than ripped out, in
/// case this gate needs to come back.
class FeatureUnlockProvider extends ChangeNotifier {
  bool _isUnlocked = true;

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
