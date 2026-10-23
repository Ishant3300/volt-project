import 'dart:convert';
import '../config/practice_only.dart';
import 'dart:developer';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/multi_account_service.dart';

class AuthenticateData {
  final String username;
  final String password;
  final String? fcmToken;

  AuthenticateData({
    required this.username,
    required this.password,
    this.fcmToken,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      "username": username,
      "password": password,
    };
    if (fcmToken != null) map["fcm_token"] = fcmToken;
    return map;
  }
}

class AuthenticationResponse {
  final bool success;
  final String message;
  final dynamic data;
  final bool requiresPasswordChange;

  AuthenticationResponse({
    required this.success,
    required this.message,
    required this.data,
    this.requiresPasswordChange = false,
  });

  factory AuthenticationResponse.fromJson(Map<String, dynamic> json) {
    return AuthenticationResponse(
      success: json["success"],
      message: json["message"],
      data: json["data"],
      requiresPasswordChange: json["data"]?["requires_password_change"] == true,
    );
  }
}

class AuthService {
  final ApiService api;
  final SecureStorageService storage = SecureStorageService();
  final MultiAccountService multiAccount = MultiAccountService();

  AuthService(this.api);

  Future<AuthenticationResponse> login({
    required AuthenticateData data,
  }) async {
    try {
      // IMPORTANT: Clear old token before login to prevent using stale credentials
      // This ensures single-session login works correctly
      await storage.deleteToken();
      await storage.deleteRole();
      log('🗑️  Cleared old credentials before login');

      String endpoint = '/auth/login';

      var response = await api.post(endpoint, data.toJson());
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final authResponse = AuthenticationResponse.fromJson(decoded);

        // Save token and role to secure storage
        if (authResponse.success && authResponse.data != null) {
          // If TOTP or OTP is required, don't save token yet (no token in response)
          if (authResponse.data['requires_otp'] == true ||
              (!kPracticeOnly &&
                  authResponse.data['requires_totp'] == true)) {
            return authResponse;
          }

          final token = authResponse.data['token'];
          await storage.saveToken(token: token);
          log('💾 Saved new token to secure storage');

          // Decode JWT to extract role
          try {
            Map<String, dynamic> payload = Jwt.parseJwt(token);
            String tokenRole = payload['role'] ?? '';
            // Convert to uppercase to match the role parameter
            await storage.saveRole(role: tokenRole.toUpperCase());
            log('Saved role from token: ${tokenRole.toUpperCase()}');

            // If master login, save add_master permission
            if (!kPracticeOnly &&
                tokenRole.toUpperCase() == 'MASTER' &&
                authResponse.data['master'] != null) {
              final masterData = authResponse.data['master'];
              final addMaster = masterData['add_master'] ?? false;
              await storage.saveAddMasterPermission(addMaster: addMaster);
              log('Saved add_master permission: $addMaster');
            }

            // Save to multi-account list
            final savedAccount = SavedAccount(
              username: data.username,
              role: tokenRole.toUpperCase(),
              token: token,
              investor: authResponse.data['investor'] == true,
              name: authResponse.data['user']?['name'] ??
                  authResponse.data['master']?['name'] ??
                  authResponse.data['admin']?['username'] ??
                  data.username,
            );
            await multiAccount.saveAccount(savedAccount);
            await multiAccount.setActiveKey(savedAccount.key);
          } catch (e) {
            log('Error decoding JWT: $e');
            // Fallback to the role returned from the backend if JWT decode fails
            if (authResponse.data['role'] != null) {
              await storage.saveRole(role: authResponse.data['role']);
            }
          }
        }

        return authResponse;
      } else {
        final decoded = jsonDecode(response.body);
        return AuthenticationResponse.fromJson(decoded);
      }
    } catch (err) {
      log(err.toString());
      rethrow;
    }
  }

  Future<AuthenticationResponse> logout({required String role}) async {
    try {
      late String endpoint;
      // Client accounts only in the practice-only build.
      if (kPracticeOnly || role == 'USER') {
        endpoint = '/auth/user/logout';
      } else if (role == 'MASTER') {
        endpoint = '/auth/master/logout';
      } else {
        endpoint = '/auth/admin/logout';
      }

      final token = await storage.getToken();
      var response = await api.post(endpoint, {}, token: token);

      // Clear the LOCAL token/role regardless of the server's response
      // status — logging out is fundamentally a device-side action (this
      // device should forget its credentials the moment the user asks),
      // and the caller (profile_page.dart's _handleLogout) proceeds to
      // navigate to the login screen and remove the saved account
      // unconditionally either way. Previously this only cleared storage
      // on a 200: a session that had already expired server-side (a
      // realistic logout scenario, not an edge case) returned a non-200,
      // and the UI told the user "Logged out successfully" while their
      // real JWT stayed in secure storage — walking them straight back
      // into the funded account on next launch.
      await storage.deleteToken();
      await storage.deleteRole();
      final decoded = jsonDecode(response.body);
      return AuthenticationResponse.fromJson(decoded);
    } catch (err) {
      // Same reasoning applies to a network failure: the device should
      // still forget its credentials even though the server never
      // acknowledged the logout. Only the SERVER-side session may remain
      // valid until it naturally expires; the caller still sees this as a
      // thrown error so it can tell the user the server round-trip failed.
      await storage.deleteToken();
      await storage.deleteRole();
      log(err.toString());
      rethrow;
    }
  }

  Future<String?> getToken() async {
    return await storage.getToken();
  }

  Future<bool> isLoggedIn() async {
    final token = await storage.getToken();
    return token != null;
  }
}
