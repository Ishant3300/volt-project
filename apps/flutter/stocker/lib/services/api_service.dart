import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:stocker/services/firebase_service.dart';

class ApiService {
  final String baseUrl;
  final SecureStorageService _storage = SecureStorageService();
  static bool _isInitializing = false;
  static bool _isHandling401 = false;

  ApiService(this.baseUrl);

  /// Call this to prevent 401 handling during login/initialization
  void setInitializing(bool value) {
    _isInitializing = value;
    log('🔄 ApiService: Initializing mode = $_isInitializing');
  }

  Future<void> _handleUnauthorized() async {
    // Don't handle 401 during login/initialization flow
    if (_isInitializing) {
      log('⚠️  401 during initialization - ignoring');
      return;
    }

    // If there's no token stored, redirect to login (session was invalidated)
    final existingToken = await _storage.getToken();
    if (existingToken == null) {
      log('⚠️  401 with no token — redirecting to login');
      if (_isHandling401) return;
      _isHandling401 = true;
      try {
        await NavigationService.navigateToLogin();
      } finally {
        _isHandling401 = false;
      }
      return;
    }

    // Prevent multiple concurrent 401 handlers from racing
    if (_isHandling401) return;
    _isHandling401 = true;

    log('🚨 401 Unauthorized - session expired or logged in elsewhere');

    try {
      // Unregister FCM token before clearing credentials
      try {
        await FirebaseService().unregisterToken();
      } catch (_) {}

      // Clear all stored data
      await _storage.deleteToken();
      await _storage.deleteRole();
      await _storage.deleteAddMasterPermission();

      // Show message and redirect to login
      final ctx = NavigationService.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(
            content: Text('Session expired. You may have logged in on another device.'),
            backgroundColor: Color(0xFFEF4444),
            duration: Duration(seconds: 3),
          ),
        );
      }
      await NavigationService.navigateToLogin();
    } finally {
      _isHandling401 = false;
    }
  }

  Map<String, String> _defaultHeaders({String? token}) {
    final headers = {
      "Content-Type": "application/json",
    };

    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }

    return headers;
  }

  Future<http.Response> get(String endpoint, {String? token}) async {
    final url = "$baseUrl/api$endpoint";
    log('📡 GET Request');
    log('   URL: $url');
    log('   Has Token: ${token != null}');
    if (token != null) {
      log('   Token: ${token.substring(0, 20)}...');
    }

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: _defaultHeaders(token: token),
          )
          .timeout(const Duration(seconds: 30));

      log('   ✅ Response: ${response.statusCode}');
      log('   Body length: ${response.body.length}');
      log('   Body preview: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _handleUnauthorized();
      }

      return response;
    } catch (e, stackTrace) {
      log('   ❌ Request failed: $e');
      log('   Stack trace: $stackTrace');
      throw _sanitizeError(e);
    }
  }

  Future<http.Response> post(String endpoint, dynamic body,
      {String? token}) async {
    final url = "$baseUrl/api$endpoint";
    log('📡 POST Request');
    log('   URL: $url');
    log('   Has Token: ${token != null}');
    log('   Body: ${jsonEncode(body)}');

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: _defaultHeaders(token: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      log('   ✅ Response: ${response.statusCode}');
      log('   Body: ${response.body}');

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _handleUnauthorized();
      }

      return response;
    } catch (e, stackTrace) {
      log('   ❌ Request failed: $e');
      log('   Stack trace: $stackTrace');
      throw _sanitizeError(e);
    }
  }

  Future<http.Response> put(String endpoint, dynamic body,
      {String? token}) async {
    final url = "$baseUrl/api$endpoint";
    log('📡 PUT Request');
    log('   URL: $url');
    log('   Has Token: ${token != null}');
    log('   Body: ${jsonEncode(body)}');

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: _defaultHeaders(token: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      log('   ✅ Response: ${response.statusCode}');
      log('   Body: ${response.body}');

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _handleUnauthorized();
      }

      return response;
    } catch (e, stackTrace) {
      log('   ❌ Request failed: $e');
      log('   Stack trace: $stackTrace');
      throw _sanitizeError(e);
    }
  }

  Future<http.Response> delete(String endpoint, {String? token, dynamic body}) async {
    final url = "$baseUrl/api$endpoint";
    log('📡 DELETE Request');
    log('   URL: $url');
    log('   Has Token: ${token != null}');

    try {
      final request = http.Request('DELETE', Uri.parse(url));
      request.headers.addAll(_defaultHeaders(token: token));
      if (body != null) {
        request.body = jsonEncode(body);
      }

      final streamedResponse = await request.send().timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);

      log('   ✅ Response: ${response.statusCode}');
      log('   Body: ${response.body}');

      // Handle 401 Unauthorized
      if (response.statusCode == 401) {
        await _handleUnauthorized();
      }

      return response;
    } catch (e, stackTrace) {
      log('   ❌ Request failed: $e');
      log('   Stack trace: $stackTrace');
      throw _sanitizeError(e);
    }
  }

  /// Sanitize network errors so raw exception details (IP, port, endpoint)
  /// are never exposed to the end user in error messages.
  static Exception _sanitizeError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('socketexception') ||
        msg.contains('network is unreachable') ||
        msg.contains('connection refused') ||
        msg.contains('connection failed') ||
        msg.contains('no route to host') ||
        msg.contains('no internet') ||
        msg.contains('failed host lookup')) {
      return Exception('No internet connection. Please check your network and try again.');
    }
    if (msg.contains('timeout') || msg.contains('timed out')) {
      return Exception('Server is not responding. Please try again later.');
    }
    if (msg.contains('handshake') || msg.contains('certificate') || msg.contains('ssl')) {
      return Exception('Secure connection failed. Please try again.');
    }
    // Generic fallback — don't expose raw error
    return Exception('Something went wrong. Please try again.');
  }
}
