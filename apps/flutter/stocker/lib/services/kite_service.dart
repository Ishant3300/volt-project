import 'dart:convert';
import 'dart:developer';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class KiteResponse {
  final bool success;
  final String message;
  final dynamic data;

  KiteResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  factory KiteResponse.fromJson(Map<String, dynamic> json) {
    return KiteResponse(
      success: json['success'],
      message: json['message'],
      data: json['data'],
    );
  }
}

class KiteService {
  final ApiService api;
  final SecureStorageService storage = SecureStorageService();

  KiteService(this.api);

  Future<String?> _getToken() async {
    return await storage.getToken();
  }

  // Search instruments
  Future<List<KiteInstrument>> searchInstruments({
    required String query,
    String? exchange,
    String? instrumentType,
    int limit = 50,
  }) async {
    try {
      log('🔍 Searching instruments...');
      log('   Query: $query');
      log('   Exchange: $exchange');
      log('   Type: $instrumentType');
      
      final token = await _getToken();
      log('   Token: ${token?.substring(0, 20)}...');
      
      String endpoint = '/api/kite/instruments/search?q=$query';
      if (exchange != null) endpoint += '&exchange=$exchange';
      if (instrumentType != null) endpoint += '&instrument_type=$instrumentType';
      endpoint += '&limit=$limit';

      log('   Endpoint: $endpoint');

      final response = await api.get(endpoint, token: token);
      log('   Response status: ${response.statusCode}');
      log('   Response body: ${response.body}');
      
      final decoded = jsonDecode(response.body);
      final kiteResponse = KiteResponse.fromJson(decoded);

      log('   Success: ${kiteResponse.success}');
      log('   Message: ${kiteResponse.message}');
      log('   Data type: ${kiteResponse.data.runtimeType}');

      if (kiteResponse.success && kiteResponse.data != null) {
        final List<dynamic> instrumentsJson = kiteResponse.data;
        log('   Found ${instrumentsJson.length} instruments');
        
        final instruments = instrumentsJson
            .map((json) => KiteInstrument.fromJson(json))
            .toList();
        
        log('   Parsed ${instruments.length} instruments');
        return instruments;
      }

      log('   No data returned');
      return [];
    } catch (err) {
      log('❌ Error searching instruments: $err');
      log('   Stack trace: ${StackTrace.current}');
      rethrow;
    }
  }

  // Get instruments info
  Future<Map<String, dynamic>> getInstrumentsInfo() async {
    try {
      final token = await _getToken();
      final response = await api.get('/api/kite/instruments/info', token: token);
      final decoded = jsonDecode(response.body);
      final kiteResponse = KiteResponse.fromJson(decoded);

      if (kiteResponse.success) {
        return kiteResponse.data;
      }

      return {};
    } catch (err) {
      log('Error getting instruments info: $err');
      rethrow;
    }
  }

  // Get latest quotes
  Future<List<Map<String, dynamic>>> getLatestQuotes({
    List<String>? instruments,
    int limit = 100,
  }) async {
    try {
      final token = await _getToken();
      
      String endpoint = '/api/kite/quotes/latest?limit=$limit';
      if (instruments != null && instruments.isNotEmpty) {
        endpoint += '&instruments=${instruments.join(',')}';
      }

      final response = await api.get(endpoint, token: token);
      final decoded = jsonDecode(response.body);
      final kiteResponse = KiteResponse.fromJson(decoded);

      if (kiteResponse.success && kiteResponse.data != null) {
        return List<Map<String, dynamic>>.from(kiteResponse.data);
      }

      return [];
    } catch (err) {
      log('Error getting latest quotes: $err');
      rethrow;
    }
  }

  // Fetch quotes from Kite API
  Future<Map<String, dynamic>> fetchQuotes({
    required List<String> instruments,
    String type = 'ltp',
  }) async {
    try {
      final token = await _getToken();
      
      final response = await api.post(
        '/api/kite/quotes/fetch',
        {
          'instruments': instruments,
          'type': type,
        },
        token: token,
      );

      final decoded = jsonDecode(response.body);
      final kiteResponse = KiteResponse.fromJson(decoded);

      if (kiteResponse.success) {
        return kiteResponse.data;
      }

      return {};
    } catch (err) {
      log('Error fetching quotes: $err');
      rethrow;
    }
  }
}
