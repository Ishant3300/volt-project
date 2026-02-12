import 'dart:convert';
import 'dart:developer';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class WatchlistService {
  final ApiService api;
  final SecureStorageService storage = SecureStorageService();

  WatchlistService(this.api);

  Future<String?> _getToken() async {
    return await storage.getToken();
  }

  /// Fetch user's watchlist from backend
  Future<List<Map<String, dynamic>>> getWatchlist() async {
    try {
      final token = await _getToken();
      log('📋 Fetching watchlist from backend...');

      final response = await api.get('/api/watchlist', token: token);
      final decoded = jsonDecode(response.body);

      log('   Response: ${response.statusCode}');

      if (decoded['success'] == true && decoded['data'] != null) {
        final items = List<Map<String, dynamic>>.from(decoded['data']);
        log('   ✅ Found ${items.length} watchlist items');
        return items;
      }

      log('   No watchlist data');
      return [];
    } catch (e) {
      log('   ❌ Error fetching watchlist: $e');
      return [];
    }
  }

  /// Add instrument to watchlist on backend
  Future<Map<String, dynamic>?> addToWatchlist({
    required String kiteInstrumentId,
    required String instrumentToken,
  }) async {
    try {
      final token = await _getToken();
      log('➕ Adding to watchlist: $instrumentToken');

      final response = await api.post(
        '/api/watchlist',
        {
          'kite_instrument_id': kiteInstrumentId,
          'instrument_token': instrumentToken,
        },
        token: token,
      );

      final decoded = jsonDecode(response.body);
      log('   Response: ${response.statusCode} - ${decoded['message']}');

      if (decoded['success'] == true) {
        return decoded['data'] as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      log('   ❌ Error adding to watchlist: $e');
      return null;
    }
  }

  /// Remove instrument from watchlist on backend
  Future<bool> removeFromWatchlist(String watchlistId) async {
    try {
      final token = await _getToken();
      log('🗑️ Removing from watchlist: $watchlistId');

      final response = await api.delete('/api/watchlist/$watchlistId', token: token);
      final decoded = jsonDecode(response.body);

      log('   Response: ${response.statusCode} - ${decoded['message']}');
      return decoded['success'] == true;
    } catch (e) {
      log('   ❌ Error removing from watchlist: $e');
      return false;
    }
  }
}
