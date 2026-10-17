import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:stocker/services/firebase_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/services/app_identity.dart';

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
            backgroundColor: kColorSell,
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
      // app version + phone model (login history, alerts, crash reports)
      if (AppIdentity.userAgent.isNotEmpty) "User-Agent": AppIdentity.userAgent,
    };

    if (token != null) {
      headers["Authorization"] = "Bearer $token";
    }

    return headers;
  }

  /// Keys whose values must never reach the device log — request bodies
  /// carry plaintext passwords (login, change-password, create-user,
  /// investor_password) and response bodies carry freshly issued JWTs.
  static const _sensitiveLogKeys = {
    'password',
    'investor_password',
    'current_password',
    'new_password',
    'confirm_password',
    'token',
    'active_token',
    'access_token',
    'jwt',
  };

  static dynamic _redactSensitive(dynamic value) {
    if (value is Map) {
      return value.map((k, v) {
        final key = k.toString().toLowerCase();
        final isSensitive = _sensitiveLogKeys.any((s) => key.contains(s));
        return MapEntry(k, isSensitive ? '<redacted>' : _redactSensitive(v));
      });
    }
    if (value is List) {
      return value.map(_redactSensitive).toList();
    }
    return value;
  }

  /// Redacted rendering of a request body for logging.
  static String _loggableBody(dynamic body) {
    try {
      return jsonEncode(_redactSensitive(body));
    } catch (_) {
      return '<unloggable>';
    }
  }

  /// Redacted rendering of a raw JSON response body for logging. Falls back
  /// to the raw string when the response isn't JSON (nothing structured to redact).
  static String _loggableResponseBody(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      return jsonEncode(_redactSensitive(decoded));
    } catch (_) {
      return responseBody;
    }
  }

  Future<http.Response> get(String endpoint, {String? token}) async {
    final url = "$baseUrl/api$endpoint";
    log('📡 GET Request');
    log('   URL: $url');
    log('   Has Token: ${token != null}');

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: _defaultHeaders(token: token),
          )
          .timeout(const Duration(seconds: 30));

      log('   ✅ Response: ${response.statusCode}');
      log('   Body length: ${response.body.length}');
      final preview = _loggableResponseBody(response.body);
      log('   Body preview: ${preview.substring(0, preview.length > 200 ? 200 : preview.length)}');

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
    log('   Body: ${_loggableBody(body)}');

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: _defaultHeaders(token: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      log('   ✅ Response: ${response.statusCode}');
      log('   Body: ${_loggableResponseBody(response.body)}');

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
    log('   Body: ${_loggableBody(body)}');

    try {
      final response = await http
          .put(
            Uri.parse(url),
            headers: _defaultHeaders(token: token),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      log('   ✅ Response: ${response.statusCode}');
      log('   Body: ${_loggableResponseBody(response.body)}');

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
      log('   Body: ${_loggableResponseBody(response.body)}');

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
