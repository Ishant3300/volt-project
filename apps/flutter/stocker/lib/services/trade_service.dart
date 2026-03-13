import 'dart:convert';
import 'dart:developer';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

/// Holds lot limit info for an instrument
class LotLimitInfo {
  final int maxLots;
  final int lotSize;
  final int maxQty;
  final String? groupName;

  LotLimitInfo({
    required this.maxLots,
    required this.lotSize,
    required this.maxQty,
    this.groupName,
  });
}

class TradeService {
  final ApiService _apiService = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();

  /// Fetches lot limit info for a specific instrument.
  /// Returns null if no limit is configured.
  Future<LotLimitInfo?> getLotLimit({
    required String exchange,
    required String instrumentToken,
    required String tradingSymbol,
    String? userId, // For admin/master viewing a user
  }) async {
    try {
      final token = await _storage.getToken();

      // New targeted endpoint
      String endpoint =
          '/trade/instrument-limit?segment=$exchange&instrument_id=$instrumentToken';
      if (userId != null) {
        endpoint += '&user_id=$userId';
      }

      final res = await _apiService.get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'];
        if (data != null && data['limit'] != null) {
          final limit = data['limit'];
          final maxQty = _toInt(limit['max_qty']) ?? 0;
          final lotSize = _toInt(limit['lot_size']) ?? 1;

          return LotLimitInfo(
            maxLots: maxQty,
            lotSize: lotSize,
            maxQty: maxQty * lotSize,
          );
        }
      }
      return null;
    } catch (e) {
      log('Error fetching lot limit: $e');
      return null;
    }
  }

  /// Clears the cached lot limit data
  void clearCache() {}

  /// Helper to convert dynamic number to int
  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Places a new trade.
  /// Returns a tuple of (success, message).
  Future<(bool, String)> placeTrade({
    required String instrumentToken,
    required String tradingSymbol,
    required String exchange,
    required String transactionType, // 'BUY' or 'SELL'
    required int quantity,
    required double price,
    required String orderType, // 'MARKET' or 'LIMIT'
    String? userId, // Admin/Master can trade on behalf of a user
  }) async {
    try {
      final token = await _storage.getToken();

      final body = <String, dynamic>{
        'instrument_token': instrumentToken,
        'tradingsymbol': tradingSymbol,
        'exchange': exchange,
        'transaction_type': transactionType.toUpperCase(),
        'quantity': quantity,
        'price': price,
        'order_type': orderType.toUpperCase(),
      };
      if (userId != null) body['user_id'] = userId;

      final response = await _apiService.post('/trade', body, token: token);
      final jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 201 && jsonResponse['success'] == true) {
        return (
          true,
          jsonResponse['message'] as String? ?? 'Trade placed successfully'
        );
      } else {
        return (
          false,
          jsonResponse['message'] as String? ?? 'Failed to place trade'
        );
      }
    } catch (e) {
      log('Error placing trade: $e');
      return (
        false,
        'An unexpected error occurred while placing the trade: $e'
      );
    }
  }
}
