

import 'dart:developer';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const tokenKey = "auth_token";
  static const roleKey = "user_role";
  static const addMasterKey = "add_master_permission";

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
        log('🗑️ SecureStorage: Cleared all data due to corruption');
      } catch (_) {}
      return null;
    }
  }

  Future<void> saveToken({required String token}) async {
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
    return await _safeRead(tokenKey);
  }

  Future<void> deleteToken() async {
    await storage.delete(key: tokenKey);
  }

  Future<void> saveRole({required String role}) async {
    log('💾 SecureStorage: Saving role: "$role"');
    try {
      await storage.write(key: roleKey, value: role);
    } catch (e) {
      log('⚠️ SecureStorage: Write failed for role, retrying: $e');
      await storage.delete(key: roleKey);
      await storage.write(key: roleKey, value: role);
    }
  }

  Future<String?> getRole() async {
    final role = await _safeRead(roleKey);
    log('📖 SecureStorage: Retrieved role: "$role"');
    return role;
  }

  Future<void> deleteRole() async {
    log('🗑️ SecureStorage: Deleting role');
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
    return raw.split(',').map((s) => int.tryParse(s) ?? 0).where((v) => v > 0).toList();
  }
}
