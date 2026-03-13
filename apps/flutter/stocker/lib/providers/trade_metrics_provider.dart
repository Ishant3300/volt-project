import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:stocker/models/trade.dart';
import 'package:stocker/models/trade_margin.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class PositionAgg {
  final String instrumentToken;
  final String exchange;
  final String tradingsymbol;
  int totalBuyQty = 0;
  int totalSellQty = 0;
  double totalBuyValue = 0;
  double totalSellValue = 0;

  int netQty = 0;
  double avgBuyPrice = 0;
  double avgSellPrice = 0;
  double ltp = 0;
  double realised = 0;
  double floating = 0;
  double positionMargin = 0;

  PositionAgg({
    required this.instrumentToken,
    required this.exchange,
    required this.tradingsymbol,
  });
}

class TradeMetricsProvider with ChangeNotifier {
  final ApiService _apiService = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();
  final UserProfileProvider userProfileProvider;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<Trade> _trades = [];
  List<Trade> get trades => _trades;
  List<TradeMargin> _margins = [];
  final Map<String, double> _ltpMap = {};
  List<PositionAgg> _positions = [];
  List<PositionAgg> get positions => _positions;

  // Metrics
  double _realisedPnl = 0;
  double _positionPnl = 0;
  double _m2mPnl = 0;
  double _marginUsed = 0;
  double _equity = 0;
  double _freeMargin = 0;
  double _credit = 0;
  double _balance = 0;

  double get realisedPnl => _realisedPnl;
  double get positionPnl => _positionPnl;
  double get m2mPnl => _m2mPnl;
  double get marginUsed => _marginUsed;
  double get equity => _equity;
  double get freeMargin => _freeMargin;
  double get credit => _credit;
  double get balance => _balance;

  TradeMetricsProvider({required this.userProfileProvider});

  Future<void> fetchBaseData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await _storage.getToken();

      // Fetch margins
      final marginRes = await _apiService.get('/trade/margins', token: token);
      if (marginRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(marginRes.body);
        final List data = body['data'] ?? [];
        _margins = data.map((e) => TradeMargin.fromJson(e)).toList();
      }

      // Fetch positions/trades
      final tradeRes = await _apiService.get('/trade/positions', token: token);
      if (tradeRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(tradeRes.body);
        final List data = body['data'] ?? [];
        _trades = data.map((e) => Trade.fromJson(e)).toList();
      }

      _calculateMetrics();
    } catch (e) {
      debugPrint('Error fetching base trade data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updateLtp(String instrumentToken, double ltp) {
    if (_ltpMap[instrumentToken] != ltp) {
      _ltpMap[instrumentToken] = ltp;
      _calculateMetrics();
    }
  }

  void _calculateMetrics() {
    // 1. Get user credit and balance
    _credit = userProfileProvider.user?.credits ??
        userProfileProvider.master?.credits ??
        0.0;
    _balance = userProfileProvider.user?.balance ??
        userProfileProvider.master?.balance ??
        0.0;

    // 2. Aggregate trades using running-average ATP.
    //    When the position goes flat (netQty == 0), the cost basis resets so
    //    a fresh entry starts with a clean ATP instead of blending old trades.
    Map<String, PositionAgg> aggMap = {};

    // Sort trades by creation time so we process them chronologically.
    final sortedTrades = List<Trade>.from(
      _trades.where((t) => t.status == 'completed'),
    )..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // Per-instrument running state (resets on flat).
    final Map<String, _RunningPos> running = {};

    for (var t in sortedTrades) {
      if (!aggMap.containsKey(t.instrumentToken)) {
        aggMap[t.instrumentToken] = PositionAgg(
          instrumentToken: t.instrumentToken,
          exchange: t.exchange,
          tradingsymbol: t.tradingSymbol,
        );
        running[t.instrumentToken] = _RunningPos();
      }

      final agg = aggMap[t.instrumentToken]!;
      final run = running[t.instrumentToken]!;

      if (t.transactionType == 'BUY') {
        // Update running avg buy price
        final newQty = run.netQty + t.quantity;
        if (run.netQty >= 0) {
          // Adding to long (or opening fresh long from flat)
          run.avgBuy = run.netQty > 0
              ? (run.avgBuy * run.netQty + t.price * t.quantity) / newQty
              : t.price;
        } else {
          // Covering a short — reduce short qty, avg sell stays
          if (newQty >= 0) {
            // Fully covered + possibly flipped long
            run.avgBuy = newQty > 0 ? t.price : 0;
          }
          // avgSell unchanged while still short
        }
        run.netQty = newQty;
        agg.totalBuyQty += t.quantity;
        agg.totalBuyValue += t.quantity * t.price;
      } else if (t.transactionType == 'SELL') {
        final newQty = run.netQty - t.quantity;
        if (run.netQty <= 0) {
          // Adding to short (or opening fresh short from flat)
          final absOld = run.netQty.abs();
          final absNew = absOld + t.quantity;
          run.avgSell = absOld > 0
              ? (run.avgSell * absOld + t.price * t.quantity) / absNew
              : t.price;
        } else {
          // Reducing a long — avg buy stays
          if (newQty <= 0) {
            // Fully closed + possibly flipped short
            run.avgSell = newQty < 0 ? t.price : 0;
          }
        }
        run.netQty = newQty;
        agg.totalSellQty += t.quantity;
        agg.totalSellValue += t.quantity * t.price;
      }

      // When position goes flat, reset running state for next fresh entry
      if (run.netQty == 0) {
        run.avgBuy = 0;
        run.avgSell = 0;
      }
    }

    double totalRealised = 0;
    double totalFloating = 0;
    double totalMargin = 0;

    for (var agg in aggMap.values) {
      final run = running[agg.instrumentToken]!;
      int netQty = run.netQty;

      // Use running ATP instead of simple total/qty average
      double avgBuyPrice = run.avgBuy;
      double avgSellPrice = run.avgSell;

      double ltp = _ltpMap[agg.instrumentToken] ??
          (avgBuyPrice > 0 ? avgBuyPrice : avgSellPrice);

      double realised = 0;
      double floating = 0;

      if (netQty > 0) {
        // Net Long
        realised = agg.totalSellValue - (agg.totalSellQty * avgBuyPrice);
        floating = (ltp - avgBuyPrice) * netQty;
      } else if (netQty < 0) {
        // Net Short
        realised = (agg.totalBuyQty * avgSellPrice) - agg.totalBuyValue;
        floating = (avgSellPrice - ltp) * netQty.abs();
      } else {
        // Flat
        realised = agg.totalSellValue - agg.totalBuyValue;
        floating = 0;
      }

      totalRealised += realised;
      totalFloating += floating;

      // Calculate margin
      double positionMargin = 0;
      if (netQty != 0) {
        // Find margin rule safely
        TradeMargin? rule;
        try {
          rule = _margins.firstWhere((m) => m.exchangeName == agg.exchange);
        } catch (_) {
          // firstWhere throws StateError if no element is found
          rule = null;
        }

        if (rule != null) {
          if (rule.amountType == 'percentage') {
            double contractValue = netQty.abs() * ltp;
            positionMargin = (contractValue * rule.tradeMargin) / 100;
          } else {
            positionMargin = netQty.abs() * rule.tradeMargin;
          }
        }
        totalMargin += positionMargin;
      }

      agg.netQty = netQty;
      agg.avgBuyPrice = avgBuyPrice;
      agg.avgSellPrice = avgSellPrice;
      agg.ltp = ltp;
      agg.realised = realised;
      agg.floating = floating;
      agg.positionMargin = positionMargin;
    }

    _positions = aggMap.values.toList();

    _realisedPnl = totalRealised;
    _positionPnl = totalFloating;
    _m2mPnl = totalRealised + totalFloating;
    _equity = _balance + _m2mPnl;
    _marginUsed = totalMargin;
    _freeMargin = _equity - _marginUsed;

    notifyListeners();
  }
}

/// Tracks the running net position and ATP for a single instrument.
/// Resets cost basis when the position goes flat, so a fresh entry
/// gets a clean ATP instead of blending historical trades.
class _RunningPos {
  int netQty = 0;
  double avgBuy = 0;
  double avgSell = 0;
}
