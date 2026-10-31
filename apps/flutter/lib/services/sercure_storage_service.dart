import 'dart:developer';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const tokenKey = "auth_token";

  // Token and role kept in memory once read or written (1 Nov 2026): every
  // API call reads the token, and Android's encrypted storage is slow on some
  // phones (seconds on a realme / Android 16) — that made login and search
  // feel stuck. Storage is still written; this only skips the slow re-reads.
  static String? _tokenCache;
  static bool _tokenCached = false;
  static String? _roleCache;
  static bool _roleCached = false;
  static void _forgetCache() {
    _tokenCache = null;
    _tokenCached = false;
    _roleCache = null;
    _roleCached = false;
  }
  static const roleKey = "user_role";
  static const addMasterKey = "add_master_permission";
  static const passwordResetPendingKey = "password_reset_pending";
  static const passwordResetPasswordKey = "password_reset_current_pass";

  /// Safe read that handles corrupted keystore (BadPaddingException).
  /// Returns null and clears storage if decryption fails.
  Future<String?> _safeRead(String key) async {
    try {
      return await storage.read(key: key);
    } catch (e) {
      log('⚠️ SecureStorage: Error reading "$key": $e');
      // Corrupted keystore — clear everything so user can re-login
      try {
        await storage.deleteAll();
        _forgetCache();
        log('🗑️ SecureStorage: Cleared all data due to corruption');
      } catch (_) {}
      return null;
    }
  }

  Future<void> saveToken({required String token}) async {
    _tokenCache = token;
    _tokenCached = true;
    try {
      await storage.write(key: tokenKey, value: token);
    } catch (e) {
      // iOS keychain duplicate item error — delete first then write
      log('⚠️ SecureStorage: Write failed for token, retrying: $e');
      await storage.delete(key: tokenKey);
      await storage.write(key: tokenKey, value: token);
    }
  }

  Future<String?> getToken() async {
    if (_tokenCached) return _tokenCache;
    final token = await _safeRead(tokenKey);
    _tokenCache = token;
    _tokenCached = true;
    return token;
  }

  Future<void> deleteToken() async {
    _tokenCache = null;
    _tokenCached = true;
    await storage.delete(key: tokenKey);
  }

  Future<void> saveRole({required String role}) async {
    log('💾 SecureStorage: Saving role: "$role"');
    _roleCache = role;
    _roleCached = true;
    try {
      await storage.write(key: roleKey, value: role);
    } catch (e) {
      log('⚠️ SecureStorage: Write failed for role, retrying: $e');
      await storage.delete(key: roleKey);
      await storage.write(key: roleKey, value: role);
    }
  }

  Future<String?> getRole() async {
    if (_roleCached) return _roleCache;
    final role = await _safeRead(roleKey);
    _roleCache = role;
    _roleCached = true;
    log('📖 SecureStorage: Retrieved role: "$role"');
    return role;
  }

  Future<void> deleteRole() async {
    log('🗑️ SecureStorage: Deleting role');
    _roleCache = null;
    _roleCached = true;
    await storage.delete(key: roleKey);
  }

  Future<bool> isAdmin() async {
    final role = await getRole();
    return role == 'ADMIN' || role == 'MASTER';
  }

  Future<void> saveAddMasterPermission({required bool addMaster}) async {
    await storage.write(key: addMasterKey, value: addMaster.toString());
  }

  Future<bool> getAddMasterPermission() async {
    final value = await _safeRead(addMasterKey);
    return value == 'true';
  }

  Future<void> deleteAddMasterPermission() async {
    await storage.delete(key: addMasterKey);
  }

  // Quick quantity values for trade card
  static const quickQtyKey = "quick_qty_values";

  Future<void> saveQuickQuantities(List<int> values) async {
    await storage.write(key: quickQtyKey, value: values.join(','));
  }

  Future<List<int>> getQuickQuantities() async {
    final raw = await _safeRead(quickQtyKey);
    if (raw == null || raw.isEmpty) return [100, 200, 500, 1000, 2000, 5000];
    return raw
        .split(',')
        .map((s) => int.tryParse(s) ?? 0)
        .where((v) => v > 0)
        .toList();
  }

  // Password reset pending flag (survives app restart)
  Future<void> setPasswordResetPending(
      {required String currentPassword}) async {
    await storage.write(key: passwordResetPendingKey, value: 'true');
    await storage.write(key: passwordResetPasswordKey, value: currentPassword);
  }

  Future<bool> isPasswordResetPending() async {
    final value = await _safeRead(passwordResetPendingKey);
    return value == 'true';
  }

  Future<String?> getPasswordResetCurrentPassword() async {
    return await _safeRead(passwordResetPasswordKey);
  }

  Future<void> clearPasswordResetPending() async {
    await storage.delete(key: passwordResetPendingKey);
    await storage.delete(key: passwordResetPasswordKey);
  }
}
