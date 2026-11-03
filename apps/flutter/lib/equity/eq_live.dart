// Equity live prices and order updates — its OWN socket to /ws/live-prices (the F&O
// LivePriceService is not touched). The server sends 'cash_ticks' only for stocks a
// screen registered (POST /cash-eq/stream, repeated every minute) and 'cash_order'
// when one of the account's equity orders changes.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';

class EqLive extends ChangeNotifier {
  final EqApi api;
  EqLive(this.api);

  final Map<int, Map<String, dynamic>> quotes = {};
  final StreamController<Map<String, dynamic>> _orders = StreamController.broadcast();
  Stream<Map<String, dynamic>> get orderEvents => _orders.stream;

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _reconnect;
  Timer? _register;
  Set<int> _tokens = {};
  bool _closed = false;

  void start() {
    _closed = false;
    _connect();
    _register = Timer.periodic(const Duration(seconds: 60), (_) => _registerTokens());
  }

  void _connect() {
    if (_closed) return;
    try {
      final uri = Uri.parse('${backendUrl.replaceFirst('http', 'ws')}/ws/live-prices');
      final ch = IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 15));
      _ch = ch;
      ch.ready.catchError((Object _) {});
      _sub = ch.stream.listen(_onMessage, onDone: _scheduleReconnect, onError: (_) => _scheduleReconnect());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    if (_closed) return;
    _reconnect = Timer(const Duration(seconds: 5), _connect);
  }

  Future<void> _onMessage(dynamic raw) async {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'connected':
        final token = await SecureStorageService().getToken();
        if (token != null) _ch?.sink.add(jsonEncode({'type': 'auth', 'token': token}));
        break;
      case 'cash_ticks':
        for (final q in (m['data'] as List? ?? [])) {
          final t = (q['instrument_token'] as num?)?.toInt();
          if (t == null) continue;
          quotes[t] = {...?quotes[t], ...Map<String, dynamic>.from(q)};
        }
        notifyListeners();
        break;
      case 'cash_order':
        if (m['data'] is Map) _orders.add(Map<String, dynamic>.from(m['data']));
        break;
    }
  }

  /// The stocks on screen right now (replaces the previous set).
  Future<void> watch(Iterable<int> tokens) async {
    _tokens = tokens.toSet();
    await _registerTokens();
  }

  /// Add stocks without dropping the ones already on screen (the ticket over a list).
  Future<void> add(Iterable<int> tokens) async {
    _tokens = {..._tokens, ...tokens};
    await _registerTokens();
  }

  Future<void> _registerTokens() async {
    if (_tokens.isEmpty) return;
    try {
      final r = await api.stream(_tokens.toList());
      for (final q in (r['quotes'] as List? ?? [])) {
        final t = (q['instrument_token'] as num?)?.toInt();
        if (t != null) quotes[t] = {...?quotes[t], ...Map<String, dynamic>.from(q)};
      }
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _closed = true;
    _reconnect?.cancel();
    _register?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _orders.close();
    super.dispose();
  }
}
