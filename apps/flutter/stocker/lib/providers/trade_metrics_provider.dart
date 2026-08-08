import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:stocker/models/trade.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class PositionAgg {
  final String instrumentToken;
  final String exchange;
  final String tradingsymbol;
  String rawName = '';
  int lotSize = 1;
  String segment = '';
  int totalBuyQty = 0;
  int totalSellQty = 0;
  double totalBuyValue = 0;
  double totalSellValue = 0;

  int netQty = 0;
  double avgBuyPrice = 0;
  double avgSellPrice = 0;
  double ltp = 0;
  double cmp = 0;
  double realised = 0;
  double floating = 0;
  double positionMargin = 0;

  PositionAgg({
    required this.instrumentToken,
    required this.exchange,
    required this.tradingsymbol,
  });

  bool get isLotBased {
    final seg = segment.toUpperCase();
    return seg == 'MCX-FUT' || seg == 'MCX-OPT' || seg == 'NFO-OPT';
  }

  int get lots =>
      (lotSize > 0) ? (netQty.abs() / lotSize).round() : netQty.abs();
  int get displayVolume => isLotBased ? lots : netQty.abs();
  String get volumeUnit => isLotBased ? 'LOT' : 'QTY';
}

class TradeMetricsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();
  final UserProfileProvider userProfileProvider;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Trade> _trades = [];
  List<Trade> get trades => _trades;
  final Map<String, double> _ltpMap = {};
  List<PositionAgg> _positions = [];
  List<PositionAgg> get positions => _positions;

  // The 6 metrics — all computed client-side on every tick
  double _realisedPnl = 0;
  double _positionPnl = 0;
  double _m2mPnl = 0;
  double _marginUsed = 0;
  double _equity = 0;
  double _freeMargin = 0;
  double _credit = 0;
  double _balance = 0;
  String? _currentUserId;

  // Per-category available wallet balances (filtered to the account's allowed
  // categories by the backend), e.g. { "NSE": 75000.0, "MCX": 30000.0 }.
  // Equity == sum of these values. Used for the orders-page "i" breakdown.
  Map<String, double> _wallet = {};

  double get realisedPnl => _realisedPnl;
  double get positionPnl => _positionPnl;
  double get m2mPnl => _m2mPnl;
  double get marginUsed => _marginUsed;
  double get equity => _equity;
  double get freeMargin => _freeMargin;
  double get credit => _credit;
  double get balance => _balance;
  Map<String, double> get wallet => _wallet;

  TradeMetricsProvider({required this.userProfileProvider});

  /// Reset all cached data (call on logout / account switch).
  void clear() {
    _trades = [];
    _ltpMap.clear();
    _positions = [];
    _realisedPnl = 0;
    _positionPnl = 0;
    _m2mPnl = 0;
    _marginUsed = 0;
    _equity = 0;
    _freeMargin = 0;
    _credit = 0;
    _balance = 0;
    _wallet = {};
    _currentUserId = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Fetch base data on login / app open.
  /// 1. GET /trade/metrics → credit, equity, free_margin (DB snapshot)
  /// 2. GET /trade/margins → margin rules for local calc
  /// 3. GET /trade/positions → trades for local position aggregation
  /// Then compute all 6 metrics locally.
  Future<void> fetchBaseData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.getToken();

      // 1. Fetch account metrics from metricsEngine (single source of truth)
      final metricsRes =
          await _apiService.get('/trade/metrics', token: token);
      if (metricsRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(metricsRes.body);
        final data = body['data'];
        if (data != null) {
          _currentUserId = data['user_id']?.toString();
          _credit = (data['credit'] as num?)?.toDouble() ?? 0;
          _balance = (data['balance'] as num?)?.toDouble() ?? 0;
          _equity = (data['equity'] as num?)?.toDouble() ?? _credit;
          _freeMargin = (data['free_margin'] as num?)?.toDouble() ?? _credit;
          _realisedPnl = (data['realised_pnl'] as num?)?.toDouble() ?? 0;
          _positionPnl = (data['position_pnl'] as num?)?.toDouble() ?? 0;
          _m2mPnl = (data['m2m_pnl'] as num?)?.toDouble() ?? 0;
          _marginUsed = (data['margin_used'] as num?)?.toDouble() ?? 0;

          // Per-category available balances for the equity "i" breakdown.
          // Default to {} on the base fetch when the key is absent.
          _wallet = data['wallet'] is Map
              ? (data['wallet'] as Map).map(
                  (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0))
              : {};

          // Populate positions from metrics response
          final List serverPositions = data['positions'] ?? [];
          _positions = serverPositions.map((p) {
            final agg = PositionAgg(
              instrumentToken: p['instrument_token']?.toString() ?? '',
              exchange: p['exchange'] ?? '',
              tradingsymbol: p['tradingsymbol'] ?? '',
            );
            agg.netQty = (p['net_qty'] as num?)?.toInt() ?? 0;
            agg.avgBuyPrice = (p['avg_buy_price'] as num?)?.toDouble() ?? 0;
            agg.avgSellPrice = (p['avg_sell_price'] as num?)?.toDouble() ?? 0;
            agg.ltp = (p['ltp'] as num?)?.toDouble() ?? 0;
            agg.cmp = (p['cmp'] as num?)?.toDouble() ?? 0;
            agg.floating = (p['floating_pnl'] as num?)?.toDouble() ?? 0;
            agg.positionMargin = (p['margin'] as num?)?.toDouble() ?? 0;
            agg.segment = p['segment'] ?? '';
            agg.lotSize = (p['lot_size'] as num?)?.toInt() ?? 1;
            return agg;
          }).toList();
        }
      }

      // 2. Fetch positions/trades (still needed for history page)
      final tradeRes = await _apiService.get('/trade/positions', token: token);
      if (tradeRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(tradeRes.body);
        final List data = body['data'] ?? [];
        _trades = data.map((e) => Trade.fromJson(e)).toList();
      }

      // 3. Server will push live values via WebSocket for ongoing updates
    } catch (e) {
      debugPrint('Error fetching base trade data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called on every price tick from WebSocket — only updates LTP map for CMP display.
  /// Metrics are computed server-side by metricsEngine and pushed via WebSocket.
  void updateLtp(String instrumentToken, double ltp, {double? bid, double? ask}) {
    _ltpMap[instrumentToken] = ltp;
    if (bid != null && bid > 0) _ltpMap['${instrumentToken}_bid'] = bid;
    if (ask != null && ask > 0) _ltpMap['${instrumentToken}_ask'] = ask;
  }

  /// Apply server-pushed metrics from metricsEngine (single source of truth).
  void applyServerMetrics(Map<String, dynamic> data) {
    // Ignore metrics for a different user (stale WebSocket push after account switch)
    final incomingUserId = data['user_id']?.toString();
    if (_currentUserId != null && incomingUserId != null && incomingUserId != _currentUserId) {
      return;
    }

    _credit = (data['credit'] as num?)?.toDouble() ?? _credit;
    _realisedPnl = (data['realised_pnl'] as num?)?.toDouble() ?? _realisedPnl;
    _positionPnl = (data['position_pnl'] as num?)?.toDouble() ?? _positionPnl;
    _m2mPnl = (data['m2m_pnl'] as num?)?.toDouble() ?? _m2mPnl;
    _marginUsed = (data['margin_used'] as num?)?.toDouble() ?? _marginUsed;
    _equity = (data['equity'] as num?)?.toDouble() ?? _equity;
    _freeMargin = (data['free_margin'] as num?)?.toDouble() ?? _freeMargin;

    // Per-category available balances for the equity "i" breakdown. Keep the
    // previous value when the push omits the key (so the breakdown never blanks).
    _wallet = data['wallet'] is Map
        ? (data['wallet'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0))
        : _wallet;

    // Update positions from server data (always replace, even if empty — positions may have been closed)
    final List serverPositions = data['positions'] ?? [];
    _positions = serverPositions.map((p) {
      final agg = PositionAgg(
        instrumentToken: p['instrument_token']?.toString() ?? '',
        exchange: p['exchange'] ?? '',
        tradingsymbol: p['tradingsymbol'] ?? '',
      );
      agg.netQty = (p['net_qty'] as num?)?.toInt() ?? 0;
      agg.avgBuyPrice = (p['avg_buy_price'] as num?)?.toDouble() ?? 0;
      agg.avgSellPrice = (p['avg_sell_price'] as num?)?.toDouble() ?? 0;
      agg.ltp = (p['ltp'] as num?)?.toDouble() ?? 0;
      agg.cmp = (p['cmp'] as num?)?.toDouble() ?? 0;
      agg.floating = (p['floating_pnl'] as num?)?.toDouble() ?? 0;
      agg.positionMargin = (p['margin'] as num?)?.toDouble() ?? 0;
      agg.segment = p['segment'] ?? '';
      agg.lotSize = (p['lot_size'] as num?)?.toInt() ?? 1;
      return agg;
    }).toList();

    notifyListeners();
  }

  /// Push current cached metrics to server for DB persistence.
  /// Call this periodically or on app background/close.
  Future<void> pushMetricsToServer() async {
    try {
      final token = await _storage.getToken();
      await _apiService.post('/trade/metrics', {
        'realised_pnl': _realisedPnl,
        'position_pnl': _positionPnl,
        'm2m_pnl': _m2mPnl,
        'margin_used': _marginUsed,
        'equity': _equity,
        'free_margin': _freeMargin,
      }, token: token);
    } catch (e) {
      debugPrint('Error pushing metrics to server: $e');
    }
  }

}
