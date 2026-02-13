import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:flutter/material.dart';

class ApiService {
  final String baseUrl;
  final SecureStorageService _storage = SecureStorageService();

  ApiService(this.baseUrl);

  Future<void> _handleUnauthorized() async {
    log('🚨 401 Unauthorized - Session expired');
    
    // Clear stored token
    await _storage.deleteToken();
    
    // Show snackbar
    final context = NavigationService.currentContext;
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please login again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
    
    // Navigate to login after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
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
    final url = "$baseUrl$endpoint";
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
    final url = "$baseUrl$endpoint";
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
    final url = "$baseUrl$endpoint";
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
      
      return response;
    } catch (e, stackTrace) {
      log('   ❌ Request failed: $e');
      log('   Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<http.Response> delete(String endpoint, {String? token}) async {
    final url = "$baseUrl$endpoint";
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
      
      return response;
    } catch (e, stackTrace) {
      log('   ❌ Request failed: $e');
      log('   Stack trace: $stackTrace');
      rethrow;
    }
  }
}
