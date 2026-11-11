import 'dart:convert';

import '../utils/contants.dart';
import 'api_service.dart';
import 'broker_service.dart' show BrokerApiException;
import 'sercure_storage_service.dart';

/// Broker login in the app (owner, 12 Nov 2026) — the same read-only
/// /api/broker endpoints as the web Broker View. A broker token is refused by
/// every client / master / admin route on the server; these GET routes are
/// all it can use.
class BrokerViewService {
  final ApiService _api = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();

  Future<dynamic> _get(String path) async {
    final token = await _storage.getToken();
    final res = await _api.get(path, token: token);
    Map<String, dynamic>? body;
    try {
      final d = jsonDecode(res.body);
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (res.statusCode == 200 && body?['success'] != false) return body?['data'];
    throw BrokerApiException(body?['message']?.toString() ?? 'Request failed (${res.statusCode})');
  }

  Future<Map<String, dynamic>> me() async => Map<String, dynamic>.from((await _get('/broker/me')) as Map? ?? {});

  Future<Map<String, dynamic>> statement({int weeks = 12}) async =>
      Map<String, dynamic>.from((await _get('/broker/statement?weeks=$weeks')) as Map? ?? {});

  Future<List<Map<String, dynamic>>> clients() async =>
      ((await _get('/broker/clients')) as List? ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<Map<String, dynamic>> client(String userId) async =>
      Map<String, dynamic>.from((await _get('/broker/clients/$userId')) as Map? ?? {});

  /// Newest first; `data.trades`.
  Future<List<Map<String, dynamic>>> trades(String userId, {int page = 1, int limit = 100}) async {
    final d = await _get('/broker/clients/$userId/trades?page=$page&limit=$limit');
    final list = d is Map ? (d['trades'] as List? ?? const []) : (d is List ? d : const []);
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }
}
