

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  final FlutterSecureStorage storage = FlutterSecureStorage();

  static const tokenKey = "auth_token";
  Future<void> saveToken({required String token}) async {
    await storage.write(key: tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await storage.read(key: tokenKey);
  }

  Future<void> deleteToken() async {
    await storage.delete(key: tokenKey);
  }
}