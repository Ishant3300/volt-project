import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stocker/utils/contants.dart';

class LivePriceService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  Function(Map<String, dynamic>)? onTickReceived;
  Function(bool)? onConnectionChanged;
  Function(Map<String, dynamic>)? onTradeExecuted;
  Function(Map<String, dynamic>)? onTradePlaced;
  Function(Map<String, dynamic>)? onMetricsUpdate;
  Function(Map<String, dynamic>)? onMasterMetricsUpdate;
  Function(List<dynamic>)? onAdminMetricsUpdate;
  Function(Map<String, dynamic>)? onSettlementProgress;

  bool get isConnected => _isConnected;

  /// Connect to the backend WebSocket server
  void connect() {
    if (_isConnected) {
      log('📡 Already connected to live price server');
      return;
    }

    try {
      // Convert http URL to ws URL
      final wsUrl = backendUrl.replaceFirst('http', 'ws');
      final uri = Uri.parse('$wsUrl/ws/live-prices');

      log('📡 Connecting to live price server...');
      log('   URL: $uri');

      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        (message) {
          if (kLogWebSockets) log('RAW SOCKET EVENT RECEIVED: $message');
          _handleMessage(message);
        },
        onDone: () {
          log('⚠️  WebSocket connection closed');
          _isConnected = false;
          onConnectionChanged?.call(false);
          _scheduleReconnect();
        },
        onError: (error) {
          log('❌ WebSocket error: $error');
          _isConnected = false;
          onConnectionChanged?.call(false);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      log('❌ Failed to connect to live price server: $e');
      _scheduleReconnect();
    }
  }

  /// Handle incoming WebSocket messages
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'connected':
          log('✅ Connected to live price server');
          log('   Kite connected: ${data['kiteConnected']}');
          _isConnected = true;
          onConnectionChanged?.call(true);
          break;

        case 'kite_status':
          log('📊 Kite status: connected=${data['connected']}');
          break;

        case 'ticks':
          final ticks = data['data'] as List<dynamic>;
          // log('📈 Received ${ticks.length} tick(s)');
          for (final tick in ticks) {
            final tickMap = tick as Map<String, dynamic>;
            if (kLogLivePrices) {
              log('   Token: ${tickMap['instrument_token']} | LTP: ${tickMap['last_price']} | Change: ${tickMap['change']?.toStringAsFixed(2) ?? 'N/A'}');
            }
            onTickReceived?.call(tickMap);
          }
          break;

        case 'trade_executed':
          log('⚡ Trade executed event: ${data['tradingsymbol']} ${data['transaction_type']} ${data['quantity']} @ ${data['executed_price']}');
          onTradeExecuted?.call(data);
          break;

        case 'trade_rejected':
          log('⚠️ Trade rejected: ${data['tradingsymbol']} — ${data['message']}');
          onTradeExecuted?.call(data);
          break;

        case 'margin_square_off':
          log('🛡️ Margin square-off: ${data['message']}');
          onTradeExecuted?.call(data);
          break;

        case 'trade_placed':
          log('📝 Trade placed event: ${data['tradingsymbol']} ${data['transaction_type']} ${data['quantity']} @ ${data['price']}');
          onTradePlaced?.call(data);
          break;

        case 'metrics_update':
          onMetricsUpdate?.call(data['data'] as Map<String, dynamic>);
          break;

        case 'master_metrics_update':
          onMasterMetricsUpdate?.call(data['data'] as Map<String, dynamic>);
          break;

        case 'admin_metrics_update':
          onAdminMetricsUpdate?.call(data['data'] as List<dynamic>);
          break;

        case 'settlement_progress':
          onSettlementProgress?.call(data['data'] as Map<String, dynamic>);
          break;

        default:
          log('❓ Unknown message type: $type');
      }
    } catch (e) {
      log('❌ Error handling WebSocket message: $e');
    }
  }

  /// Authenticate this WebSocket connection with the user's ID
  /// so the backend can send targeted trade_executed events
  void authenticate(String userId, {String? role}) {
    if (!_isConnected || _channel == null) {
      log('⚠️  Cannot authenticate, not connected');
      return;
    }

    log('🔐 Authenticating WebSocket as user: $userId${role != null ? ' ($role)' : ''}');
    final message = jsonEncode({
      'type': 'auth',
      'userId': userId,
      if (role != null) 'role': role,
    });
    _channel!.sink.add(message);
  }

  /// Subscribe to instrument tokens for live prices
  void subscribe(List<String> tokens) {
    if (!_isConnected || _channel == null) {
      log('⚠️  Cannot subscribe, not connected');
      return;
    }

    log('📊 Subscribing to ${tokens.length} token(s): ${tokens.join(', ')}');

    final message = jsonEncode({
      'type': 'subscribe',
      'tokens': tokens,
    });

    _channel!.sink.add(message);
  }

  /// Unsubscribe from instrument tokens
  void unsubscribe(List<String> tokens) {
    if (!_isConnected || _channel == null) return;

    log('📊 Unsubscribing from ${tokens.length} token(s)');

    final message = jsonEncode({
      'type': 'unsubscribe',
      'tokens': tokens,
    });

    _channel!.sink.add(message);
  }

  /// Schedule a reconnection attempt
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      log('🔄 Attempting to reconnect...');
      connect();
    });
  }

  /// Disconnect and clean up
  void disconnect() {
    log('🛑 Disconnecting from live price server');
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected = false;
  }
}
