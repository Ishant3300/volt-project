import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/navigation_service.dart';

class ApiService {
  final String baseUrl;
  final SecureStorageService _storage = SecureStorageService();
  bool _isInitializing = false;

  ApiService(this.baseUrl);

  /// Call this to prevent 401 handling during login/initialization
  void setInitializing(bool value) {
    _isInitializing = value;
    log('🔄 ApiService: Initializing mode = $_isInitializing');
  }

  Future<void> _handleUnauthorized() async {
    // Don't handle 401 during initialization (login flow)
    if (_isInitializing) {
      log('⚠️  401 during initialization - ignoring (login in progress)');
      return;
    }
    
    // Get the current role before clearing (to check if we just logged in)
    final currentRole = await _storage.getRole();
    final currentToken = await _storage.getToken();
    
    log('🚨 401 Unauthorized - Current role: $currentRole, Has token: ${currentToken != null}');
    
    // If we have both a token and role, this might be a transient 401 during login
    // Don't clear immediately - give it a moment
    if (currentToken != null && currentRole != null) {
      log('⚠️  Have token and role - might be transient 401, waiting 500ms...');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Check again
      final tokenAfterWait = await _storage.getToken();
      if (tokenAfterWait != null && tokenAfterWait == currentToken) {
        log('⚠️  Token still valid after wait - ignoring 401');
        return;
      }
    }
    
    log('🚨 Clearing session and redirecting to login');
    
    // Clear all stored data
    await _storage.deleteToken();
    await _storage.deleteRole();
    await _storage.deleteAddMasterPermission();
    
    // Navigate to login silently (no error message shown to user)
    await NavigationService.navigateToLogin();
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
      final response = await http.get(
        Uri.parse(url),
        headers: _defaultHeaders(token: token),
      );
      
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
      rethrow;
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
      final response = await http.post(
        Uri.parse(url),
        headers: _defaultHeaders(token: token),
        body: jsonEncode(body),
      );
      
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
      rethrow;
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
      final response = await http.put(
        Uri.parse(url),
        headers: _defaultHeaders(token: token),
        body: jsonEncode(body),
      );
      
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
      rethrow;
    }
  }

  Future<http.Response> delete(String endpoint, {String? token}) async {
    final url = "$baseUrl/api$endpoint";
    log('📡 DELETE Request');
    log('   URL: $url');
    log('   Has Token: ${token != null}');
    
    try {
      final response = await http.delete(
        Uri.parse(url),
        headers: _defaultHeaders(token: token),
      );
      
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
      rethrow;
    }
  }
}
