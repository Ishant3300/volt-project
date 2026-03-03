import 'dart:developer';
import 'dart:convert';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class ChartService {
  final ApiService _apiService;
  final SecureStorageService _storage = SecureStorageService();

  ChartService(this._apiService);

  /// Fetch historical candle data for an instrument
  /// interval: minute, day, 3minute, 5minute, 10minute, 15minute, 30minute, 60minute
  /// fromDate: YYYY-MM-DD format
  /// toDate: YYYY-MM-DD format
  Future<List<Map<String, dynamic>>> getHistoricalData({
    required String instrumentToken,
    required String interval,
    required String fromDate,
    required String toDate,
  }) async {
    try {
      log('📊 Fetching historical data for token: $instrumentToken');
      log('   Interval: $interval, From: $fromDate, To: $toDate');

      final token = await _storage.getToken();
      final response = await _apiService.get(
        '/kite/historical/$instrumentToken/$interval?from=$fromDate&to=$toDate',
        token: token,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          final candles = (data['data'] as List)
              .map((item) => item as Map<String, dynamic>)
              .toList();
          
          log('✅ Fetched ${candles.length} candles');
          return candles;
        } else {
          log('❌ Failed to fetch historical data: ${data['message']}');
          return [];
        }
      } else {
        log('❌ HTTP error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      log('❌ Error fetching historical data: $e');
      return [];
    }
  }
}
