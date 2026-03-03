

import 'dart:developer';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage storage = FlutterSecureStorage();

  static const tokenKey = "auth_token";
  static const roleKey = "user_role";
  static const addMasterKey = "add_master_permission";

  Future<void> saveToken({required String token}) async {
    await storage.write(key: tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await storage.read(key: tokenKey);
  }

  Future<void> deleteToken() async {
    await storage.delete(key: tokenKey);
  }

  Future<void> saveRole({required String role}) async {
    log('💾 SecureStorage: Saving role: "$role"');
    await storage.write(key: roleKey, value: role);
  }

  Future<String?> getRole() async {
    final role = await storage.read(key: roleKey);
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
    final value = await storage.read(key: addMasterKey);
    return value == 'true';
  }

  Future<void> deleteAddMasterPermission() async {
    await storage.delete(key: addMasterKey);
  }
}