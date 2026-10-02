import 'dart:convert';
import 'dart:developer';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

/// Holds lot/quantity limit info for an instrument.
/// - [isTurnoverMode]: true = instrument traded in raw quantity (NFO-FUT, SGX, GLOBAL etc.)
///   false = instrument traded in lots (MCX-FUT etc.)
/// - [maxLots] / [lotSize]: only meaningful when [isTurnoverMode] == false
/// - [maxQty]: max allowed raw quantity per order
/// - [breakQty]: max single-order qty before it must be split (turnover mode only)
class LotLimitInfo {
  final int maxLots;
  final int lotSize;
  final int maxQty;
  final int breakQty;
  final bool isTurnoverMode;
  final String? groupName;

  LotLimitInfo({
    required this.maxLots,
    required this.lotSize,
    required this.maxQty,
    this.breakQty = 0,
    this.isTurnoverMode = false,
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
    String? rawName, // raw_name for direct GroupedQuantity lookup
    String? userId, // For admin/master viewing a user
  }) async {
    try {
      final token = await _storage.getToken();

      // New targeted endpoint
      String endpoint =
          '/trade/instrument-limit?segment=$exchange&instrument_id=$instrumentToken&symbol=$tradingSymbol';
      if (rawName != null && rawName.isNotEmpty) {
        endpoint += '&raw_name=${Uri.encodeComponent(rawName)}';
      }
      if (userId != null) {
        endpoint += '&user_id=$userId';
      }

      final res = await _apiService.get(endpoint, token: token);
      log('Body preview: ${res.body.length > 300 ? res.body.substring(0, 300) : res.body}');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'];
        if (data != null && data['limit'] != null) {
          final limit = data['limit'];
          final maxQty = _toInt(limit['max_qty']) ?? 0;
          final lotSize = _toInt(limit['lot_size']) ?? 1;
          final breakQty = _toInt(limit['break_qty']) ?? 0;

          // Determine trading mode from the exchange-level flags
          final isTurnover = data['turnover'] == true;
          final isLot = data['lot'] == true;

          if (isTurnover) {
            // Turnover mode: user trades in raw quantity (NFO-FUT, SGX, GLOBAL, etc.)
            return LotLimitInfo(
              maxLots: 0, // not used in turnover mode
              lotSize: lotSize,
              maxQty: maxQty,
              breakQty: breakQty,
              isTurnoverMode: true,
            );
          } else if (isLot) {
            // Lot mode: user selects number of lots (MCX-FUT etc.)
            return LotLimitInfo(
              maxLots: maxQty, // max_qty from API = max lots allowed
              lotSize: lotSize,
              maxQty: maxQty * lotSize,
              breakQty: breakQty,
              isTurnoverMode: false,
            );
          }
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

  /// Tells the server the app blocked an order before sending it, so it
  /// appears in the Rejection Log (POST /trade/app-rejection). Clients only;
  /// fire-and-forget — any failure is ignored and never affects the UI.
  Future<void> reportBlockedOrder({
    required String instrumentToken,
    required String transactionType,
    required int quantity,
    required String orderType,
    required double price,
    required String code,
    required String message,
  }) async {
    try {
      final token = await _storage.getToken();
      await _apiService.post(
        '/trade/app-rejection',
        {
          'instrument_token': instrumentToken,
          'transaction_type': transactionType.toUpperCase(),
          'quantity': quantity,
          'order_type': orderType.toUpperCase(),
          'price': price,
          'code': code,
          'message': message,
        },
        token: token,
      );
    } catch (e) {
      log('Could not report blocked order: $e');
    }
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
    String? segment, // e.g. NFO-FUT, MCX-FUT — used for limit validation
    String? userId, // Admin/Master can trade on behalf of a user
    bool noBrokerage = false, // Admin Custom-ticket toggle — server re-checks admin role
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
      if (segment != null && segment.isNotEmpty) body['segment'] = segment;
      if (userId != null) body['user_id'] = userId;
      if (noBrokerage) body['no_brokerage'] = true;

      final response = await _apiService.post('/trade', body, token: token);
      final jsonResponse = jsonDecode(response.body);

      if (response.statusCode == 201 && jsonResponse['success'] == true) {
        final message =
            jsonResponse['message'] as String? ?? 'Trade placed successfully';
        // The backend's own message never carries the price (confirmed real:
        // "Trade executed successfully", nothing else) — the pop-up told the
        // user it worked but not at what price. `data.executed_price` is set
        // once a MARKET order (or a LIMIT/SL that fired immediately) fills;
        // a still-pending LIMIT/SL has no execution yet, so fall back to the
        // price the user actually submitted, same as the web app's own
        // OrderResultToast (`trade.executed_price ?? priceValue`).
        final data = jsonResponse['data'];
        final executedPrice = data is Map
            ? (data['executed_price'] as num?)?.toDouble()
            : null;
        final displayPrice =
            (executedPrice != null && executedPrice > 0) ? executedPrice : price;
        return (true, '$message @ ₹${displayPrice.toStringAsFixed(2)}');
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
