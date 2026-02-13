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

      String endpoint = '/api/kite/option-chain/$tradingSymbol';
      if (expiry != null) {
        endpoint += '?expiry=$expiry';
      }

      final response = await api.get(endpoint, token: token);
      final decoded = jsonDecode(response.body);

      log('   Response: ${response.statusCode}');

      if (response.statusCode == 401) {
        log('❌ Authentication failed - token expired');
        throw Exception('Session expired. Please login again');
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
        '/api/kite/market-depth/$instrumentToken',
        token: token,
      );
      final decoded = jsonDecode(response.body);

      log('   Response: ${response.statusCode}');
      log('   Response body: ${response.body}');

      if (response.statusCode == 401) {
        log('❌ Authentication failed - token expired');
        throw Exception('Session expired. Please login again');
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

      String endpoint = '/api/kite/instruments/search?q=$query&limit=$limit';
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
}
