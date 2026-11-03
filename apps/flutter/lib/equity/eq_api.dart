// Equity (NSE cash) API — /api/cash-eq on the live backend. Its own accounts,
// orders, trades and ledger; nothing here calls an F&O endpoint.

import 'dart:convert';

import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class EqError implements Exception {
  final String message;
  final int status;
  EqError(this.message, this.status);
  @override
  String toString() => message;
}

bool isCashRole(String? role) {
  final r = (role ?? '').toUpperCase();
  return r == 'CASH_MASTER' || r == 'CASH_CLIENT';
}

class EqApi {
  final ApiService api;
  EqApi(this.api);

  final SecureStorageService _storage = SecureStorageService();

  Future<String?> _token() => _storage.getToken();

  dynamic _unwrap(int status, String body) {
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw EqError('Unexpected reply from the server', status);
    }
    if (status >= 200 && status < 300 && decoded['success'] != false) return decoded['data'];
    throw EqError((decoded['message'] ?? 'Request failed').toString(), status);
  }

  Future<dynamic> get(String path) async {
    final r = await api.get('/cash-eq$path', token: await _token());
    return _unwrap(r.statusCode, r.body);
  }

  Future<dynamic> post(String path, [Map<String, dynamic>? body]) async {
    final r = await api.post('/cash-eq$path', body ?? {}, token: await _token());
    return _unwrap(r.statusCode, r.body);
  }

  Future<dynamic> delete(String path) async {
    final r = await api.delete('/cash-eq$path', token: await _token());
    return _unwrap(r.statusCode, r.body);
  }

  String _q(Map<String, String?> params) {
    final p = params.entries.where((e) => e.value != null && e.value!.isNotEmpty).map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value!)}');
    return p.isEmpty ? '' : '?${p.join('&')}';
  }

  // Account
  Future<Map<String, dynamic>> me() async => Map<String, dynamic>.from(await get('/me'));
  Future<void> changePassword(String current, String next) => post('/me/password', {'current_password': current, 'new_password': next});

  // Stocks, watchlist, prices
  Future<List<dynamic>> search(String q) async => List<dynamic>.from(await get('/instruments/search${_q({'q': q})}'));
  Future<List<dynamic>> watchlist() async => List<dynamic>.from(await get('/watchlist'));
  Future<void> addToWatchlist(int token) => post('/watchlist', {'instrument_token': token});
  Future<void> removeFromWatchlist(int token) => delete('/watchlist/$token');
  Future<Map<String, dynamic>> stream(List<int> tokens) async => Map<String, dynamic>.from(await post('/stream', {'tokens': tokens.join(',')}));

  // Orders
  Future<Map<String, dynamic>> preview(int token, {String? clientId}) async =>
      Map<String, dynamic>.from(await get('/orders/preview${_q({'instrument_token': '$token', 'client_id': clientId})}'));
  Future<Map<String, dynamic>> placeOrder(Map<String, dynamic> body) async => Map<String, dynamic>.from(await post('/orders', body));
  Future<List<dynamic>> orders({String? clientId, String? status, String? date}) async =>
      List<dynamic>.from(await get('/orders${_q({'client_id': clientId, 'status': status, 'date': date})}'));
  Future<void> cancelOrder(String id) => post('/orders/$id/cancel');
  Future<List<dynamic>> trades({String? clientId, String? date}) async =>
      List<dynamic>.from(await get('/trades${_q({'client_id': clientId, 'date': date})}'));

  // Live account, portfolio, statement
  Future<Map<String, dynamic>> account({String? clientId}) async => Map<String, dynamic>.from(await get('/account${_q({'client_id': clientId})}'));
  Future<Map<String, dynamic>> accounts() async => Map<String, dynamic>.from(await get('/accounts'));
  Future<Map<String, dynamic>> holdings() async => Map<String, dynamic>.from(await get('/holdings'));
  Future<List<dynamic>> clients() async => List<dynamic>.from(await get('/clients'));
  Future<Map<String, dynamic>> statement({String? clientId, String? from, String? to}) async =>
      Map<String, dynamic>.from(await get('/statement${_q({'client_id': clientId, 'from': from, 'to': to})}'));
}
