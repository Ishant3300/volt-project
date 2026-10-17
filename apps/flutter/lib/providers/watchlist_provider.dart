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
  // Set when loadWatchlist's fetch throws — previously swallowed silently,
  // so a genuinely empty watchlist and "the request failed and _items was
  // simply never populated" rendered identically as "No instruments in
  // watchlist" with no way for the user to tell the difference or retry.
  String? _error;
  String? get error => _error;
  final LivePriceService _livePriceService = LivePriceService();
  WatchlistService? _watchlistService;
  final Map<String, String> _backendIdMap = {};
  // Scripts open on an order screen but NOT in the watchlist (opened from
  // Positions / History / Reports / option chain). Their ticks are applied
  // here too — before, updatePrice dropped them, the order screen's copy
  // never updated and the stale-quote guard blocked every order after 25 s.
  // Ref-counted by track/untrack; never shown in the watchlist itself.
  final Map<String, WatchlistItem> _tracked = {};
  final Map<String, int> _trackCount = {};
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
        genuine: !tick.containsKey('is_settlement'),
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
        if (_items.isNotEmpty || _tracked.isNotEmpty) {
          log('   Re-subscribing to ${_items.length + _tracked.length} tokens');
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
    final tokens = {
      ..._items.map((item) => item.instrument.instrumentToken),
      ..._tracked.keys,
    }.toList();
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

      _error = null;
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
      // Only surface this as a load failure if we ended up with nothing to
      // show — if items from a prior successful load are still present,
      // treat this as a transient refresh error rather than blanking the
      // screen the user was already looking at.
      if (_items.isEmpty) {
        _error = 'Failed to load watchlist';
      }
    }
    setLoading(false);
  }

  /// Returns true once the instrument is actually persisted on the backend.
  /// If the backend call fails, the optimistic local add is rolled back —
  /// previously it stayed in the in-memory list indefinitely (looking
  /// "added" to the user) until the next full loadWatchlist() silently
  /// dropped it, with no error ever shown.
  Future<bool> addInstrument(KiteInstrument instrument) async {
    final localId = instrument.instrumentToken;

    if (_items.any((item) => item.instrument.instrumentToken == localId)) {
      log('⚠️  Instrument already in watchlist: ${instrument.tradingsymbol}');
      return true;
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
      return true;
    }

    log('❌ Failed to save to backend — rolling back optimistic add');
    _items.removeWhere((item) => item.instrument.instrumentToken == localId);
    _livePriceService.unsubscribe([localId]);
    notifyListeners();
    return false;
  }

  /// Returns true once the instrument is actually removed on the backend.
  /// If the backend call fails, the optimistic local removal is rolled
  /// back — previously the item stayed gone from the in-memory list
  /// indefinitely (looking "removed" to the user) even though it was
  /// still present server-side, until the next full loadWatchlist()
  /// silently brought it back with no explanation.
  Future<bool> removeInstrument(String localId) async {
    final itemIndex = _items.indexWhere((item) => item.id == localId);
    if (itemIndex == -1) return true;
    final item = _items[itemIndex];
    final token = item.instrument.instrumentToken;
    final backendId = _backendIdMap[localId];

    log('➖ Removing instrument: ${item.instrument.tradingsymbol} (Token: $token)');

    _items.removeAt(itemIndex);
    _backendIdMap.remove(localId);
    notifyListeners();
    if ((_trackCount[token] ?? 0) > 0) {
      _tracked[token] = item; // its order screen is still open — keep ticking
    } else {
      _livePriceService.unsubscribe([token]);
    }

    if (_watchlistService == null) {
      final apiService = ApiService(backendUrl);
      _watchlistService = WatchlistService(apiService);
    }

    if (backendId == null) {
      // If we don't have the backendId locally for some reason, we might need to fetch it first,
      // but typically we'll have it if it was loaded or just added.
      log('⚠️ Cannot remove from backend: backendId is null — rolling back');
      _items.insert(itemIndex, item);
      notifyListeners();
      _livePriceService.subscribe([token]);
      return false;
    }

    final removed = await _watchlistService!.removeFromWatchlist(backendId);
    if (removed) {
      log('✅ Removed from backend');
      return true;
    }

    log('❌ Failed to remove from backend — rolling back');
    _items.insert(itemIndex, item);
    _backendIdMap[localId] = backendId;
    notifyListeners();
    _livePriceService.subscribe([token]);
    return false;
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
    // false for a cached / settlement price (the server's reply to a
    // subscribe, bhavcopy, settlement): shown, but not counted as a fresh
    // tick — the stale-quote guard trusts only genuine live ticks.
    bool genuine = true,
  }) {
    final index = _items.indexWhere(
      (item) => item.instrument.instrumentToken == instrumentToken,
    );

    WatchlistItem applyTick(WatchlistItem oldItem) => oldItem.copyWith(
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
        lastUpdated: genuine ? DateTime.now() : null,
      );

    if (index != -1) {
      _items[index] = applyTick(_items[index]);
      // log('   ✅ Updated: ${_items[index].instrument.tradingsymbol} -> Price: $price');
      notifyListeners();
    } else if (_tracked.containsKey(instrumentToken)) {
      _tracked[instrumentToken] = applyTick(_tracked[instrumentToken]!);
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
    _tracked.clear();
    _trackCount.clear();
    notifyListeners();
  }

  /// An order screen opened for [seed]'s script: keep its live price ticking
  /// even when it isn't in the watchlist. Pair every call with [untrack].
  /// Starts with no tick time, so the stale-quote guard waits for a genuine
  /// tick instead of trusting the caller's (possibly old) copy.
  void track(WatchlistItem seed) {
    final token = seed.instrument.instrumentToken.toString();
    final n = (_trackCount[token] ?? 0) + 1;
    _trackCount[token] = n;
    if (n > 1 || contains(token)) return;
    _tracked[token] = WatchlistItem(
      id: 'track_$token',
      instrument: seed.instrument,
      currentPrice: seed.currentPrice,
      change: seed.change,
      changePercent: seed.changePercent,
      high: seed.high,
      low: seed.low,
      open: seed.open,
      close: seed.close,
      bidPrice: seed.bidPrice,
      askPrice: seed.askPrice,
      upperCircuitLimit: seed.upperCircuitLimit,
      lowerCircuitLimit: seed.lowerCircuitLimit,
    );
    _livePriceService.subscribe([token]);
  }

  /// The order screen for [instrumentToken] closed. No unsubscribe: the
  /// server's subscribed-token set is shared by every client (an unsubscribe
  /// removes the script for all of them) and ticks are broadcast to all
  /// connections anyway, so dropping it locally is enough.
  void untrack(String instrumentToken) {
    final token = instrumentToken.toString();
    final n = (_trackCount[token] ?? 0) - 1;
    if (n > 0) {
      _trackCount[token] = n;
      return;
    }
    _trackCount.remove(token);
    _tracked.remove(token);
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
      return _tracked[instrumentToken.toString()];
    }
  }

  bool contains(String instrumentToken) {
    return _items.any(
      (item) => item.instrument.instrumentToken == instrumentToken,
    );
  }
}
