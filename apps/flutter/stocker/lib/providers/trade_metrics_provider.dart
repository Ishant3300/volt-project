import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:stocker/models/brokerage_rule.dart';
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
  List<TradeMargin> _margins = [];
  List<BrokerageRule> _brokerageRules = [];
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

  double get realisedPnl => _realisedPnl;
  double get positionPnl => _positionPnl;
  double get m2mPnl => _m2mPnl;
  double get marginUsed => _marginUsed;
  double get equity => _equity;
  double get freeMargin => _freeMargin;
  double get credit => _credit;
  double get balance => _balance;

  TradeMetricsProvider({required this.userProfileProvider});

  /// Reset all cached data (call on logout / account switch).
  void clear() {
    _trades = [];
    _margins = [];
    _brokerageRules = [];
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

      // 1. Fetch base account values (credit, equity, free_margin from DB)
      final metricsRes =
          await _apiService.get('/trade/metrics', token: token);
      if (metricsRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(metricsRes.body);
        final data = body['data'];
        if (data != null) {
          _credit = (data['credit'] as num?)?.toDouble() ?? 0;
          _balance = (data['balance'] as num?)?.toDouble() ?? 0;
          // Seed equity/free_margin from DB snapshot (will be overwritten by local calc)
          _equity = (data['equity'] as num?)?.toDouble() ?? _credit;
          _freeMargin = (data['free_margin'] as num?)?.toDouble() ?? _credit;
        }
      }

      // 2. Fetch margin rules
      final marginRes = await _apiService.get('/trade/margins', token: token);
      if (marginRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(marginRes.body);
        final List data = body['data'] ?? [];
        _margins = data.map((e) => TradeMargin.fromJson(e)).toList();
      }

      // 3. Fetch positions/trades
      final tradeRes = await _apiService.get('/trade/positions', token: token);
      if (tradeRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(tradeRes.body);
        final List data = body['data'] ?? [];
        _trades = data.map((e) => Trade.fromJson(e)).toList();
      }

      // 4. Fetch brokerage rules for client-side brokerage calculation
      final brkRes = await _apiService.get('/trade/brokerage-rules', token: token);
      if (brkRes.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(brkRes.body);
        final List data = body['data'] ?? [];
        _brokerageRules = data.map((e) => BrokerageRule.fromJson(e)).toList();
      }

      // 5. Compute all 6 metrics locally
      _calculateMetrics();
    } catch (e) {
      debugPrint('Error fetching base trade data: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called on every price tick from WebSocket.
  void updateLtp(String instrumentToken, double ltp, {double? bid, double? ask}) {
    bool changed = false;
    if (_ltpMap[instrumentToken] != ltp) {
      _ltpMap[instrumentToken] = ltp;
      changed = true;
    }
    // Store bid/ask for position P&L calculation (matches CMP display)
    if (bid != null && bid > 0) {
      final key = '${instrumentToken}_bid';
      if (_ltpMap[key] != bid) { _ltpMap[key] = bid; changed = true; }
    }
    if (ask != null && ask > 0) {
      final key = '${instrumentToken}_ask';
      if (_ltpMap[key] != ask) { _ltpMap[key] = ask; changed = true; }
    }
    if (changed) _calculateMetrics();
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

  /// Full client-side computation of all 6 metrics + position display data.
  void _calculateMetrics() {
    // 1. Get user credit
    _credit = userProfileProvider.user?.credits ??
        userProfileProvider.master?.credits ??
        _credit;
    _balance = userProfileProvider.user?.equity ??
        userProfileProvider.master?.equity ??
        _balance;

    // 2. Aggregate trades using running-average ATP.
    Map<String, PositionAgg> aggMap = {};
    final sortedTrades = List<Trade>.from(
      _trades.where((t) => t.status == 'completed'),
    )..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final Map<String, _RunningPos> running = {};

    for (var t in sortedTrades) {
      if (!aggMap.containsKey(t.instrumentToken)) {
        final newAgg = PositionAgg(
          instrumentToken: t.instrumentToken,
          exchange: t.exchange,
          tradingsymbol: t.tradingSymbol,
        );
        newAgg.lotSize = t.lotSize > 1 ? t.lotSize : 1;
        newAgg.segment = t.segment;
        newAgg.rawName = t.rawName;
        aggMap[t.instrumentToken] = newAgg;
        running[t.instrumentToken] = _RunningPos();
      }

      final agg = aggMap[t.instrumentToken]!;
      final run = running[t.instrumentToken]!;

      if (t.lotSize > 1) agg.lotSize = t.lotSize;
      if (t.segment.isNotEmpty) agg.segment = t.segment;
      if (t.rawName.isNotEmpty) agg.rawName = t.rawName;

      if (t.transactionType == 'BUY') {
        final newQty = run.netQty + t.quantity;
        if (run.netQty >= 0) {
          run.avgBuy = run.netQty > 0
              ? (run.avgBuy * run.netQty + t.price * t.quantity) / newQty
              : t.price;
        } else {
          if (newQty >= 0) {
            run.avgBuy = newQty > 0 ? t.price : 0;
          }
        }
        run.netQty = newQty;
        agg.totalBuyQty += t.quantity;
        agg.totalBuyValue += t.quantity * t.price;
      } else if (t.transactionType == 'SELL') {
        final newQty = run.netQty - t.quantity;
        if (run.netQty <= 0) {
          final absOld = run.netQty.abs();
          final absNew = absOld + t.quantity;
          run.avgSell = absOld > 0
              ? (run.avgSell * absOld + t.price * t.quantity) / absNew
              : t.price;
        } else {
          if (newQty <= 0) {
            run.avgSell = newQty < 0 ? t.price : 0;
          }
        }
        run.netQty = newQty;
        agg.totalSellQty += t.quantity;
        agg.totalSellValue += t.quantity * t.price;
      }

      if (run.netQty == 0) {
        run.avgBuy = 0;
        run.avgSell = 0;
      }
    }

    double totalFloating = 0;
    double totalMargin = 0;

    log('📊 [Metrics] _margins count: ${_margins.length}, trades count: ${sortedTrades.length}, positions: ${aggMap.length}');
    for (var m in _margins) {
      log('📊 [Metrics] Margin rule: exchange=${m.exchangeName}, script=${m.scriptName}, type=${m.amountType}, value=${m.tradeMargin}');
    }

    for (var agg in aggMap.values) {
      final run = running[agg.instrumentToken]!;
      int netQty = run.netQty;

      double avgBuyPrice = run.avgBuy;
      double avgSellPrice = run.avgSell;

      double ltp = _ltpMap[agg.instrumentToken] ??
          (avgBuyPrice > 0 ? avgBuyPrice : avgSellPrice);

      // Use bid for long positions, ask for short (matches CMP display)
      double valuationPrice = ltp;
      if (netQty > 0) {
        valuationPrice = _ltpMap['${agg.instrumentToken}_bid'] ?? ltp;
      } else if (netQty < 0) {
        valuationPrice = _ltpMap['${agg.instrumentToken}_ask'] ?? ltp;
      }

      double floating = 0;
      if (netQty > 0) {
        floating = (valuationPrice - avgBuyPrice) * netQty;
      } else if (netQty < 0) {
        floating = (avgSellPrice - valuationPrice) * netQty.abs();
      }
      totalFloating += floating;

      // Calculate margin
      double positionMargin = 0;
      if (netQty != 0) {
        log('📊 [Margin] Position: ${agg.tradingsymbol}, netQty=$netQty, rawName=${agg.rawName}, segment=${agg.segment}, exchange=${agg.exchange}, lotSize=${agg.lotSize}');

        // 1. Try per-instrument rule: match raw_name to script_name + segment
        TradeMargin? rule;
        if (agg.rawName.isNotEmpty) {
          try {
            rule = _margins.firstWhere(
                (m) =>
                    m.scriptName.toUpperCase() == agg.rawName.toUpperCase() &&
                    m.exchangeName == agg.segment.toUpperCase());
          } catch (_) {
            rule = null;
          }
        }

        // 2. Fallback: match raw_name to script_name (any exchange)
        if (rule == null && agg.rawName.isNotEmpty) {
          try {
            rule = _margins.firstWhere(
                (m) =>
                    m.scriptName.toUpperCase() == agg.rawName.toUpperCase());
          } catch (_) {
            rule = null;
          }
        }

        // 3. Fallback: match by segment only
        if (rule == null) {
          try {
            rule = _margins.firstWhere(
                (m) => m.exchangeName == agg.segment.toUpperCase());
          } catch (_) {
            rule = null;
          }
        }

        // 4. Fallback: match by base exchange
        if (rule == null) {
          try {
            rule = _margins.firstWhere(
                (m) => m.exchangeName == agg.exchange.toUpperCase());
          } catch (_) {
            rule = null;
          }
        }

        if (rule != null) {
          final seg = agg.segment.toUpperCase();
          final bool isLotBased =
              seg == 'MCX-FUT' || seg == 'MCX-OPT' || seg == 'NFO-OPT';

          if (isLotBased && rule.amountType == 'amount') {
            // Lot-based: margin = trade_margin per lot × number of lots
            final lots = agg.lotSize > 0
                ? (netQty.abs() / agg.lotSize).ceil()
                : netQty.abs();
            positionMargin = rule.tradeMargin * lots;
          } else if (rule.amountType == 'percentage') {
            // Percentage-based: margin = qty * ATP * (trade_margin / 100)
            // Use avgBuyPrice for longs, avgSellPrice for shorts — NOT ltp
            // so margin only changes on trade execution, not on every tick.
            final atp = netQty > 0 ? avgBuyPrice : avgSellPrice;
            positionMargin =
                netQty.abs() * atp * (rule.tradeMargin / 100);
          } else {
            // Flat amount fallback for non-lot-based
            positionMargin = netQty.abs() * rule.tradeMargin;
          }
          log('📊 [Margin] Rule found: exchange=${rule.exchangeName}, script=${rule.scriptName}, type=${rule.amountType}, tradeMargin=${rule.tradeMargin}, isLotBased=$isLotBased → positionMargin=$positionMargin');
        } else {
          log('📊 [Margin] ⚠️ NO RULE FOUND for ${agg.tradingsymbol} (rawName=${agg.rawName}, segment=${agg.segment}, exchange=${agg.exchange})');
        }
        totalMargin += positionMargin;
      }

      agg.netQty = netQty;
      agg.avgBuyPrice = avgBuyPrice;
      agg.avgSellPrice = avgSellPrice;
      agg.ltp = ltp;
      agg.realised = 0;
      agg.floating = floating;
      agg.positionMargin = positionMargin;
    }

    _positions = aggMap.values.toList();

    // Compute brokerage client-side: TURNOVER WISE uses /10000, LOT WISE is flat per lot
    double totalBrokerage = 0;
    for (var t in sortedTrades) {
      final seg = (aggMap[t.instrumentToken]?.segment ?? '').toUpperCase();
      final rawName = aggMap[t.instrumentToken]?.rawName ?? '';
      final exchange = seg.isNotEmpty ? seg : t.exchange.toUpperCase();

      // Look up brokerage rule: try raw_name + segment, then raw_name only, then segment, then base exchange
      BrokerageRule? brkRule;
      if (rawName.isNotEmpty) {
        brkRule = _brokerageRules.cast<BrokerageRule?>().firstWhere(
            (r) =>
                r!.scriptName.toUpperCase() == rawName.toUpperCase() &&
                r.exchangeName == exchange,
            orElse: () => null);
      }
      if (brkRule == null && rawName.isNotEmpty) {
        brkRule = _brokerageRules.cast<BrokerageRule?>().firstWhere(
            (r) => r!.scriptName.toUpperCase() == rawName.toUpperCase(),
            orElse: () => null);
      }
      if (brkRule == null) {
        brkRule = _brokerageRules.cast<BrokerageRule?>().firstWhere(
            (r) => r!.exchangeName == exchange,
            orElse: () => null);
      }
      if (brkRule == null) {
        brkRule = _brokerageRules.cast<BrokerageRule?>().firstWhere(
            (r) => r!.exchangeName == t.exchange.toUpperCase(),
            orElse: () => null);
      }

      double tradeBrokerage = 0;
      if (brkRule != null) {
        if (brkRule.type == 'TURNOVER WISE') {
          // brk_value / 10000: e.g. 2 means 0.0002
          tradeBrokerage = t.price * t.quantity * (brkRule.brkValue / 10000);
        } else if (brkRule.type == 'LOT WISE') {
          // Flat value per lot
          final lotSize = aggMap[t.instrumentToken]?.lotSize ?? 1;
          final lots = lotSize > 1 ? t.quantity / lotSize : t.quantity.toDouble();
          tradeBrokerage = lots * brkRule.brkValue;
        }
      }
      totalBrokerage += tradeBrokerage;
    }

    // All 6 metrics computed client-side
    _realisedPnl = sortedTrades.fold(0.0, (sum, t) => sum + t.pnl) - totalBrokerage;
    _positionPnl = totalFloating;
    _m2mPnl = _realisedPnl + _positionPnl;
    _marginUsed = totalMargin;
    // Equity = credit + M2M - marginUsed (margin is locked/reserved from equity)
    _equity = _credit + _m2mPnl - _marginUsed;
    // Free Margin = equity (equity already has margin deducted)
    _freeMargin = _equity;

    log('📊 [Metrics] FINAL: credit=$_credit, realised=$_realisedPnl, floating=$_positionPnl, m2m=$_m2mPnl, marginUsed=$_marginUsed, equity=$_equity, freeMargin=$_freeMargin');

    notifyListeners();
  }
}

class _RunningPos {
  int netQty = 0;
  double avgBuy = 0;
  double avgSell = 0;
}
