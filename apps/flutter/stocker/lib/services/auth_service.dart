
import 'dart:convert';
import 'dart:developer';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class AuthenticateData {
  final String username;
  final String password;

  AuthenticateData({
    required this.username,
    required this.password,
  });

  Map<String, dynamic> toJson() {
    return {
      "username": username,
      "password": password,
    };
  }
}

class AuthenticationResponse {
  final bool success;
  final String message;
  final dynamic data;

  AuthenticationResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  factory AuthenticationResponse.fromJson(Map<String, dynamic> json) {
    return AuthenticationResponse(
      success: json["success"],
      message: json["message"],
      data: json["data"],
    );
  }
}

class AuthService {
  final ApiService api;
  final SecureStorageService storage = SecureStorageService();

  AuthService(this.api);

  Future<AuthenticationResponse> login({
    required AuthenticateData data,
    required String role,
  }) async {
    try {
      late String endpoint;
      if (role == 'USER') {
        endpoint = '/api/auth/user/login';
      } else {
        endpoint = '/api/auth/admin/login';
      }

      var response = await api.post(endpoint, data.toJson());
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final authResponse = AuthenticationResponse.fromJson(decoded);

        // Save token to secure storage
        if (authResponse.success && authResponse.data != null) {
          final token = authResponse.data['token'];
          await storage.saveToken(token: token);
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
      if (role == 'USER') {
        endpoint = '/api/auth/user/logout';
      } else {
        endpoint = '/api/auth/admin/logout';
      }

      final token = await storage.getToken();
      var response = await api.post(endpoint, {}, token: token);

      if (response.statusCode == 200) {
        // Clear token from secure storage
        await storage.deleteToken();
        final decoded = jsonDecode(response.body);
        return AuthenticationResponse.fromJson(decoded);
      } else {
        final decoded = jsonDecode(response.body);
        return AuthenticationResponse.fromJson(decoded);
      }
    } catch (err) {
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