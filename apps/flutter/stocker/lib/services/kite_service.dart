import 'dart:convert';
import 'dart:developer';
import 'package:stocker/models/option_chain.dart';
import 'package:stocker/models/market_depth.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class KiteService {
  final ApiService api;
  final SecureStorageService storage = SecureStorageService();

  KiteService(this.api);

  Future<String?> _getToken() async {
    return await storage.getToken();
  }

  /// Get option chain for a trading symbol
  Future<List<OptionChainItem>> getOptionChain(
    String tradingSymbol, {
    String? expiry,
  }) async {
    try {
      final token = await _getToken();

      if (token == null) {
        log('❌ No authentication token found');
        throw Exception('Please login again');
      }

      log('📊 Fetching option chain for $tradingSymbol');

      String endpoint = '/kite/option-chain/$tradingSymbol';
      if (expiry != null) {
        endpoint += '?expiry=$expiry';
      }

      final response = await api.get(endpoint, token: token);
      final decoded = jsonDecode(response.body);

      log('   Response: ${response.statusCode}');

      if (response.statusCode == 401) {
        log('❌ Authentication failed - redirecting to login');
        // ApiService already handles 401 and redirects to login
        throw Exception('Authentication required');
      }

      if (decoded['success'] == true && decoded['data'] != null) {
        final chain = decoded['data']['chain'] as List;
        log('   ✅ Found ${chain.length} strike prices');

        return chain.map((item) => OptionChainItem.fromJson(item)).toList();
      }

      log('   No option chain data: ${decoded['message']}');
      return [];
    } catch (e) {
      log('   ❌ Error fetching option chain: $e');
      rethrow;
    }
  }

  /// Get market depth for an instrument token
  Future<MarketDepth?> getMarketDepth(String instrumentToken) async {
    try {
      final token = await _getToken();

      if (token == null) {
        log('❌ No authentication token found');
        throw Exception('Please login again');
      }

      log('📊 Fetching market depth for token $instrumentToken');

      final response = await api.get(
        '/kite/market-depth/$instrumentToken',
        token: token,
      );
      final decoded = jsonDecode(response.body);

      log('   Response: ${response.statusCode}');
      log('   Response body: ${response.body}');

      if (response.statusCode == 401) {
        log('❌ Authentication failed - redirecting to login');
        // ApiService already handles 401 and redirects to login
        throw Exception('Authentication required');
      }

      if (decoded['success'] == true && decoded['data'] != null) {
        log('   ✅ Market depth fetched');
        log('   Data keys: ${decoded['data'].keys}');
        return MarketDepth.fromJson(decoded['data']);
      }

      log('   No market depth data: ${decoded['message']}');
      return null;
    } catch (e) {
      log('   ❌ Error fetching market depth: $e');
      rethrow;
    }
  }

  /// Search instruments
  Future<List<Map<String, dynamic>>> searchInstruments(
    String query, {
    String? exchange,
    int limit = 20,
  }) async {
    try {
      final token = await _getToken();
      log('🔍 Searching instruments: $query');

      String endpoint = '/kite/instruments/search?q=$query&limit=$limit';
      if (exchange != null) {
        endpoint += '&exchange=$exchange';
      }

      final response = await api.get(endpoint, token: token);
      final decoded = jsonDecode(response.body);

      if (decoded['success'] == true && decoded['data'] != null) {
        final results = List<Map<String, dynamic>>.from(decoded['data']);
        log('   ✅ Found ${results.length} instruments');
        return results;
      }

      return [];
    } catch (e) {
      log('   ❌ Error searching instruments: $e');
      return [];
    }
  }

  /// Smart search instruments with fuzzy matching and grouping
  Future<Map<String, dynamic>> smartSearchInstruments(
    String query, {
    String category = 'ALL',
    int limit = 50,
  }) async {
    try {
      final token = await _getToken();

      final endpoint =
          '/kite/instruments/smart-search?q=$query&category=$category&limit=$limit';
      final response = await api.get(endpoint, token: token);
      final decoded = jsonDecode(response.body);

      if (decoded['success'] == true && decoded['data'] != null) {
        return Map<String, dynamic>.from(decoded['data']);
      }

      return {'groups': [], 'total': 0, 'query': query};
    } catch (e) {
      log('   ❌ Error smart searching instruments: $e');
      return {'groups': [], 'total': 0, 'query': query};
    }
  }

  /// Get search categories
  Future<List<Map<String, dynamic>>> getSearchCategories() async {
    try {
      final token = await _getToken();
      final response =
          await api.get('/kite/instruments/categories', token: token);
      final decoded = jsonDecode(response.body);

      if (decoded['success'] == true && decoded['data'] != null) {
        return List<Map<String, dynamic>>.from(decoded['data']);
      }

      return [];
    } catch (e) {
      log('   ❌ Error getting categories: $e');
      return [];
    }
  }
}
