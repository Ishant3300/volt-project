import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/live_price_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/watchlist_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';

class WatchlistProvider with ChangeNotifier {
  final List<WatchlistItem> _items = [];
  bool _isLoading = false;
  final LivePriceService _livePriceService = LivePriceService();
  WatchlistService? _watchlistService;
  final Map<String, String> _backendIdMap = {};
  TradeMetricsProvider? tradeMetricsProvider;
  String? _authenticatedUserId;

  WatchlistProvider({this.tradeMetricsProvider});

  void _setupLivePriceCallbacks() {
    log('📞 Setting up live price callbacks');

    _livePriceService.onTickReceived = (tick) {
      final token = tick['instrument_token']?.toString();
      if (token == null) {
        log('⚠️  Received tick with no token');
        return;
      }

      final price = (tick['last_price'] as num?)?.toDouble();
      final change = (tick['change'] as num?)?.toDouble();
      final changePercent = (tick['change_percent'] as num?)?.toDouble();
      final bidPrice = (tick['bid_price'] as num?)?.toDouble();
      final askPrice = (tick['ask_price'] as num?)?.toDouble();
      final open = (tick['open'] as num?)?.toDouble();
      final close = (tick['close'] as num?)?.toDouble();
      final upperCircuit = (tick['upper_circuit_limit'] as num?)?.toDouble();
      final lowerCircuit = (tick['lower_circuit_limit'] as num?)?.toDouble();

      // Debug log to check if bid/ask are received
      if (bidPrice != null || askPrice != null) {
        if (kLogLivePrices)
          log('💰 Token $token: LTP=$price, Bid=$bidPrice, Ask=$askPrice');
      } else {
        // Log when bid/ask are missing (only for first few ticks to avoid spam)
        if (kLogLivePrices)
          log('⚠️  Token $token: LTP=$price, Bid/Ask=NULL (using fallback spread)');
      }

      // Send to Metrics Provider for realtime calculation
      if (price != null) {
        tradeMetricsProvider?.updateLtp(token, price,
            bid: bidPrice, ask: askPrice);
      }

      // log('💰 Price update for token $token: LTP=$price, Change=$change, Change%=$changePercent');

      updatePrice(
        token,
        price: price,
        change: change,
        changePercent: changePercent,
        high: (tick['high'] as num?)?.toDouble(),
        low: (tick['low'] as num?)?.toDouble(),
        open: open,
        close: close,
        bidPrice: bidPrice,
        askPrice: askPrice,
        upperCircuitLimit: upperCircuit,
        lowerCircuitLimit: lowerCircuit,
      );
    };

    _livePriceService.onTradeExecuted = (data) {
      log('⚡ onTradeExecuted callback fired: ${data['tradingsymbol']} ${data['transaction_type']} ${data['quantity']}');
      if (tradeMetricsProvider == null) {
        log('⚠️  tradeMetricsProvider is NULL – UI will not update automatically!');
      } else {
        log('🔄 Calling fetchBaseData() to refresh trades...');
        tradeMetricsProvider!.fetchBaseData();
      }

      // Only show snackbar for async limit order executions (status field present)
      // Market orders already show their own snackbar from the trade card page
      if (data['status'] == 'completed') {
        _showTradeNotification(data);
      }
    };

    _livePriceService.onTradePlaced = (data) {
      log('📝 Trade placed via WebSocket: ${data['tradingsymbol']} ${data['transaction_type']} ${data['quantity']}');
      // Re-fetch trades so orders tab updates instantly
      tradeMetricsProvider?.fetchBaseData();
    };

    // Server-pushed metrics (single source of truth from metricsEngine)
    _livePriceService.onMetricsUpdate = (data) {
      // Only apply metrics for the currently logged-in user (not other users'
      // metrics that admins/masters receive via the broadcast)
      final metricsUserId = data['user_id']?.toString() ?? '';
      if (metricsUserId.isNotEmpty &&
          _authenticatedUserId != null &&
          metricsUserId != _authenticatedUserId) {
        return; // Ignore metrics for other users
      }
      tradeMetricsProvider?.applyServerMetrics(data);
    };

    _livePriceService.onConnectionChanged = (connected) {
      log('🔌 WebSocket connection changed: $connected');
      if (connected) {
        // Authenticate so backend can send targeted trade_executed events
        _authenticateWebSocket();
        if (_items.isNotEmpty) {
          log('   Re-subscribing to ${_items.length} tokens');
          _subscribeCurrentTokens();
        }
      }
      notifyListeners();
    };

    log('✅ Live price callbacks setup complete');

    // If already connected, immediately re-authenticate and re-subscribe.
    // (onConnectionChanged won't fire again for an existing connection.)
    if (_livePriceService.isConnected) {
      log('🔐 Already connected – re-authenticating now');
      _authenticateWebSocket();
      if (_items.isNotEmpty) {
        _subscribeCurrentTokens();
      }
    }

    // Connect to WebSocket (no-op if already connected)
    log('🔌 Initiating WebSocket connection...');
    _livePriceService.connect();
  }

  Future<void> _authenticateWebSocket() async {
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      if (token != null) {
        final payload = Jwt.parseJwt(token);
        final userId = payload['id'] as String?;
        if (userId != null) {
          // Keep the local id only to filter incoming metrics; identity on the
          // server comes from the verified token, not this value.
          _authenticatedUserId = userId;
          log('🔐 Authenticating WebSocket via token');
          _livePriceService.authenticate(token);
        } else {
          log('⚠️  JWT payload has no "id" field – auth skipped. Payload keys: ${payload.keys.join(', ')}');
        }
      }
    } catch (e) {
      log('⚠️  Failed to authenticate WebSocket: $e');
    }
  }

  void _showTradeNotification(Map<String, dynamic> data) {
    final ctx = NavigationService.navigatorKey.currentContext;
    if (ctx == null) return;

    final symbol = data['tradingsymbol'] ?? '';
    final side = data['transaction_type'] ?? '';
    final qty = data['quantity'] ?? '';
    final price = data['executed_price'] ?? data['price'] ?? '';
    final pnl = data['pnl'];

    String message = '✅ $symbol $side $qty @ $price';
    if (pnl != null && pnl != 0) {
      final pnlNum = (pnl as num);
      message +=
          ' | P&L: ${pnlNum >= 0 ? '+' : ''}${pnlNum.toStringAsFixed(2)}';
    }

    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _subscribeCurrentTokens() {
    final tokens =
        _items.map((item) => item.instrument.instrumentToken).toList();
    if (tokens.isNotEmpty) {
      log('📡 Subscribing to ${tokens.length} tokens: ${tokens.join(', ')}');
      _livePriceService.subscribe(tokens);
    }
  }

  List<WatchlistItem> get items => _items;
  bool get isLoading => _isLoading;
  bool get isEmpty => _items.isEmpty;
  int get count => _items.length;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  Future<void> loadWatchlist() async {
    log('📥 Loading watchlist from backend...');
    if (_watchlistService == null) {
      final apiService = ApiService(backendUrl);
      _watchlistService = WatchlistService(apiService);
    }

    setLoading(true);
    try {
      final watchlistData = await _watchlistService!.getWatchlist();
      log('   Received ${watchlistData.length} items from backend');

      _items.clear();
      _backendIdMap.clear();

      for (final item in watchlistData) {
        log('   Processing item: ${item['id']}');

        // Backend returns 'instrument' not 'kiteInstrument'
        final instrumentData = item['instrument'] as Map<String, dynamic>?;
        if (instrumentData == null) {
          log('   ⚠️  No instrument data found for item ${item['id']}');
          continue;
        }

        log('   Instrument data: ${instrumentData['tradingsymbol']}');

        final instrument = KiteInstrument.fromJson(instrumentData);
        final backendId = item['id'].toString();
        final localId = instrument.instrumentToken;

        _backendIdMap[localId] = backendId;

        // Use last_price (= settlement price from bhavcopy) for bid/ask seeding.
        // No fake spread — show the exact settlement price on both sides
        // until live ticks from Kite arrive and override.
        final seedPrice = instrument.lastPrice > 0
            ? instrument.lastPrice
            : (instrument.ohlcClose > 0 ? instrument.ohlcClose : null);

        _items.add(WatchlistItem(
          id: localId,
          instrument: instrument,
          // GLOBAL/COMEX (Massive-fed) instruments never get last_price
          // written to the DB — only ohlc_close, via the periodic OHLC poll
          // (massiveFuturesFeedService.js) — so falling back to instrument.
          // lastPrice alone left CMP at 0 until a live tick arrived. Use the
          // same seedPrice fallback already used for bid/ask below.
          currentPrice: seedPrice ?? instrument.lastPrice,
          // Seed OHLC from DB so trade card shows correct values before live ticks arrive
          open: instrument.ohlcOpen > 0 ? instrument.ohlcOpen : null,
          high: instrument.ohlcHigh > 0 ? instrument.ohlcHigh : null,
          low: instrument.ohlcLow > 0 ? instrument.ohlcLow : null,
          close: instrument.ohlcClose > 0 ? instrument.ohlcClose : null,
          // Seed bid/ask from settlement price (last_price from DB)
          bidPrice: seedPrice,
          askPrice: seedPrice,
          lastUpdated: DateTime.now(),
        ));

        log('   ✅ Added: ${instrument.tradingsymbol} (Token: $localId)');
      }

      log('📋 Loaded ${_items.length} watchlist items from backend');

      // Disconnect old WebSocket so we get a fresh connection with current settlement prices.
      // This ensures account switches and reloads always get the latest data from the server.
      _livePriceService.disconnect();

      _setupLivePriceCallbacks();

      final tokens =
          _items.map((item) => item.instrument.instrumentToken).toList();
      log('   Tokens to subscribe: ${tokens.join(', ')}');

      if (_livePriceService.isConnected) {
        log('   WebSocket already connected, subscribing now');
        _subscribeCurrentTokens();
      } else {
        log('   WebSocket not connected yet, will subscribe when connected');
      }

      notifyListeners();
    } catch (e) {
      log('❌ Error loading watchlist: $e');
    }
    setLoading(false);
  }

  Future<void> addInstrument(KiteInstrument instrument) async {
    final localId = instrument.instrumentToken;

    if (_items.any((item) => item.instrument.instrumentToken == localId)) {
      log('⚠️  Instrument already in watchlist: ${instrument.tradingsymbol}');
      return;
    }

    log('➕ Adding instrument: ${instrument.tradingsymbol} (Token: $localId)');

    final seedPrice = instrument.lastPrice > 0
        ? instrument.lastPrice
        : (instrument.ohlcClose > 0 ? instrument.ohlcClose : null);

    _items.add(WatchlistItem(
      id: localId,
      instrument: instrument,
      currentPrice: instrument.lastPrice,
      open: instrument.ohlcOpen > 0 ? instrument.ohlcOpen : null,
      high: instrument.ohlcHigh > 0 ? instrument.ohlcHigh : null,
      low: instrument.ohlcLow > 0 ? instrument.ohlcLow : null,
      close: instrument.ohlcClose > 0 ? instrument.ohlcClose : null,
      bidPrice: seedPrice,
      askPrice: seedPrice,
      lastUpdated: DateTime.now(),
    ));
    notifyListeners();
    _livePriceService.subscribe([instrument.instrumentToken]);

    if (_watchlistService == null) {
      final apiService = ApiService(backendUrl);
      _watchlistService = WatchlistService(apiService);
    }

    final result = await _watchlistService!.addToWatchlist(
      kiteInstrumentId: instrument.id,
      instrumentToken: instrument.instrumentToken,
    );
    if (result != null) {
      _backendIdMap[localId] = result['id'].toString();
      log('✅ Saved to backend with ID: ${result['id']}');
    } else {
      log('❌ Failed to save to backend');
    }
  }

  Future<void> removeInstrument(String localId) async {
    final item = _items.firstWhere((item) => item.id == localId);
    final token = item.instrument.instrumentToken;
    final backendId = _backendIdMap[localId];

    log('➖ Removing instrument: ${item.instrument.tradingsymbol} (Token: $token)');

    _items.removeWhere((item) => item.id == localId);
    _backendIdMap.remove(localId);
    notifyListeners();
    _livePriceService.unsubscribe([token]);

    if (_watchlistService == null) {
      final apiService = ApiService(backendUrl);
      _watchlistService = WatchlistService(apiService);
    }

    if (backendId != null) {
      await _watchlistService!.removeFromWatchlist(backendId);
      log('✅ Removed from backend');
    } else {
      // If we don't have the backendId locally for some reason, we might need to fetch it first,
      // but typically we'll have it if it was loaded or just added.
      log('⚠️ Cannot remove from backend: backendId is null');
    }
  }

  void updatePrice(
    String instrumentToken, {
    double? price,
    double? change,
    double? changePercent,
    double? high,
    double? low,
    double? open,
    double? close,
    double? bidPrice,
    double? askPrice,
    double? upperCircuitLimit,
    double? lowerCircuitLimit,
  }) {
    final index = _items.indexWhere(
      (item) => item.instrument.instrumentToken == instrumentToken,
    );

    if (index != -1) {
      final oldItem = _items[index];
      _items[index] = oldItem.copyWith(
        currentPrice: price,
        change: change,
        changePercent: changePercent,
        high: high,
        low: low,
        open: open,
        close: close,
        previousBidPrice: bidPrice != null ? oldItem.bidPrice : null,
        previousAskPrice: askPrice != null ? oldItem.askPrice : null,
        bidPrice: bidPrice,
        askPrice: askPrice,
        upperCircuitLimit: upperCircuitLimit,
        lowerCircuitLimit: lowerCircuitLimit,
        lastUpdated: DateTime.now(),
      );

      // log('   ✅ Updated: ${_items[index].instrument.tradingsymbol} -> Price: $price');
      notifyListeners();
    } else {
      if (kLogTokenWarnings)
        log('⚠️  Token $instrumentToken not found in watchlist');
    }
  }

  void updatePrices(Map<String, Map<String, dynamic>> quotes) {
    for (var item in _items) {
      final quote = quotes[item.instrument.instrumentToken];
      if (quote != null) {
        updatePrice(
          item.instrument.instrumentToken,
          price: quote['last_price']?.toDouble() ?? item.currentPrice ?? 0,
          change: quote['change']?.toDouble(),
          changePercent: quote['change_percent']?.toDouble(),
          high: quote['high']?.toDouble(),
          low: quote['low']?.toDouble(),
        );
      }
    }
  }

  Future<void> clearAll() async {
    final tokens =
        _items.map((item) => item.instrument.instrumentToken).toList();
    if (tokens.isNotEmpty) {
      _livePriceService.unsubscribe(tokens);
    }
    _items.clear();
    _backendIdMap.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    // LivePriceService doesn't have dispose method
    super.dispose();
  }

  WatchlistItem? getByToken(String instrumentToken) {
    try {
      final targetToken = instrumentToken.toString();
      return _items.firstWhere(
        (item) => item.instrument.instrumentToken.toString() == targetToken,
      );
    } catch (e) {
      return null;
    }
  }

  bool contains(String instrumentToken) {
    return _items.any(
      (item) => item.instrument.instrumentToken == instrumentToken,
    );
  }
}
