import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/live_price_service.dart';
import 'package:stocker/services/watchlist_service.dart';
import 'package:stocker/utils/contants.dart';

class WatchlistProvider with ChangeNotifier {
  final List<WatchlistItem> _items = [];
  bool _isLoading = false;
  final LivePriceService _livePriceService = LivePriceService();
  WatchlistService? _watchlistService;
  final Map<String, String> _backendIdMap = {};
  bool _hasLoaded = false;

  WatchlistProvider() {
    _initializeServices();
  }

  void _initializeServices() {
    log('🚀 Initializing WatchlistProvider services');
    if (!_hasLoaded) {
      _hasLoaded = true;
      loadWatchlist();
    }
  }

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
      
      // log('💰 Price update for token $token: LTP=$price, Change=$change, Change%=$changePercent');

      updatePrice(
        token,
        price: price,
        change: change,
        changePercent: changePercent,
        high: (tick['high'] as num?)?.toDouble(),
        low: (tick['low'] as num?)?.toDouble(),
      );
    };

    _livePriceService.onConnectionChanged = (connected) {
      log('🔌 WebSocket connection changed: $connected');
      if (connected && _items.isNotEmpty) {
        log('   Re-subscribing to ${_items.length} tokens');
        _subscribeCurrentTokens();
      }
      notifyListeners();
    };

    log('✅ Live price callbacks setup complete');
    
    // Connect to WebSocket
    log('🔌 Initiating WebSocket connection...');
    _livePriceService.connect();
  }

  void _subscribeCurrentTokens() {
    final tokens = _items.map((item) => item.instrument.instrumentToken).toList();
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

        _items.add(WatchlistItem(
          id: localId,
          instrument: instrument,
          currentPrice: instrument.lastPrice,
          lastUpdated: DateTime.now(),
        ));
        
        log('   ✅ Added: ${instrument.tradingsymbol} (Token: $localId)');
      }

      log('📋 Loaded ${_items.length} watchlist items from backend');
      
      _setupLivePriceCallbacks();
      
      final tokens = _items.map((item) => item.instrument.instrumentToken).toList();
      log('   Tokens to subscribe: ${tokens.join(', ')}');

      if (_livePriceService.isConnected) {
        log('   WebSocket already connected, subscribing now');
        _subscribeCurrentTokens();
      } else {
        log('   WebSocket not connected yet, will subscribe when connected');
      }
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

    _items.add(WatchlistItem(
      id: localId,
      instrument: instrument,
      currentPrice: instrument.lastPrice,
      lastUpdated: DateTime.now(),
    ));
    notifyListeners();
    _livePriceService.subscribe([instrument.instrumentToken]);

    if (_watchlistService != null) {
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

    if (_watchlistService != null && backendId != null) {
      await _watchlistService!.removeFromWatchlist(backendId);
      log('✅ Removed from backend');
    }
  }

  void updatePrice(String instrumentToken, {
    double? price,
    double? change,
    double? changePercent,
    double? high,
    double? low,
  }) {
    final index = _items.indexWhere(
      (item) => item.instrument.instrumentToken == instrumentToken,
    );

    if (index != -1) {
      // log('🔄 Updating price for token $instrumentToken at index $index');
      
      _items[index] = _items[index].copyWith(
        currentPrice: price,
        change: change,
        changePercent: changePercent,
        high: high,
        low: low,
        lastUpdated: DateTime.now(),
      );
      
      // log('   ✅ Updated: ${_items[index].instrument.tradingsymbol} -> Price: $price');
      notifyListeners();
    } else {
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
    final tokens = _items.map((item) => item.instrument.instrumentToken).toList();
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
      return _items.firstWhere(
        (item) => item.instrument.instrumentToken == instrumentToken,
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
