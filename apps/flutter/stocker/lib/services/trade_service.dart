import 'dart:convert';
import 'dart:developer';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class TradeService {
  final ApiService _apiService = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();

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
  }) async {
    try {
      final token = await _storage.getToken();

      final body = {
        'instrument_token': instrumentToken,
        'tradingsymbol': tradingSymbol,
        'exchange': exchange,
        'transaction_type': transactionType.toUpperCase(),
        'quantity': quantity,
        'price': price,
        'order_type': orderType.toUpperCase(),
      };

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
