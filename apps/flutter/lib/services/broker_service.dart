import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/practice_session.dart';
import '../utils/contants.dart';
import 'api_service.dart';
import 'sercure_storage_service.dart';

/// A readable error from the broker endpoints (the server's own message).
class BrokerApiException implements Exception {
  final String message;
  BrokerApiException(this.message);
  @override
  String toString() => message;
}

/// Broker sharing (owner, 11 Nov 2026) — same endpoints as the web portal.
/// TRACKING ONLY: nothing here changes the ledger, settlement or any report;
/// the statement reads the Ledger's own weekly figures on the server.
///
/// An admin uses /admin/brokers (every broker); a master uses /master/brokers
/// (his own brokers, his DIRECT clients and sub-masters, and only when an
/// admin switched "Brokers allowed" on for him).
class BrokerService {
  final bool isAdmin;
  final ApiService _api = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();

  BrokerService({required this.isAdmin});

  String get _base => isAdmin ? '/admin/brokers' : '/master/brokers';

  Future<dynamic> _data(Future<http.Response> Function(String? token) call) async {
    final token = await _storage.getToken();
    final res = await call(token);
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300 && body?['success'] != false) {
      return body?['data'];
    }
    throw BrokerApiException(body?['message']?.toString() ?? 'Request failed (${res.statusCode})');
  }

  static List<Map<String, dynamic>> _list(dynamic d) =>
      d is List ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
  static Map<String, dynamic> _map(dynamic d) => d is Map ? Map<String, dynamic>.from(d) : {};

  /// Can this login use brokers at all? Admin: yes. Master: only when allowed.
  /// Never in the practice app (its server has no brokers).
  Future<bool> allowed() async {
    if (PracticeSession.isActive) return false;
    if (isAdmin) return true;
    try {
      final d = await _data((t) => _api.get('/master/brokers/access', token: t));
      return d is Map && d['allowed'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> list() async => _list(await _data((t) => _api.get(_base, token: t)));

  Future<Map<String, dynamic>> create({required String name, String? phone}) async => _map(await _data((t) => _api.post(
        _base,
        {'name': name, if (phone != null && phone.isNotEmpty) 'phone': phone},
        token: t,
      )));

  /// What a broker may get on one account (a client: userId; a sub-master: masterId).
  Future<Map<String, dynamic>> limits({String? userId, String? masterId}) async {
    final q = userId != null ? 'user_id=$userId' : 'master_id=$masterId';
    return _map(await _data((t) => _api.get('$_base/limits?$q', token: t)));
  }

  /// Settings: {rates: [{segment, type, value}], pnl_share_pct, brk_share_pct}.
  Future<void> addClientLink(String brokerId, String userId, Map<String, dynamic> settings) async =>
      _data((t) => _api.post('$_base/$brokerId/links', {...settings, 'user_id': userId}, token: t));

  Future<void> addMasterLink(String brokerId, String masterId, Map<String, dynamic> settings) async =>
      _data((t) => _api.post('$_base/$brokerId/master-links', {...settings, 'master_id': masterId}, token: t));

  Future<void> endClientLink(String linkId) async => _data((t) => _api.put('$_base/links/$linkId/end', {}, token: t));

  Future<void> endMasterLink(String linkId) async => _data((t) => _api.put('$_base/master-links/$linkId/end', {}, token: t));

  Future<Map<String, dynamic>> statement(String brokerId, {int weeks = 8}) async =>
      _map(await _data((t) => _api.get('$_base/$brokerId/statement?weeks=$weeks', token: t)));

  Future<void> setLogin(String brokerId, {String? username, String? password, bool? enabled}) async => _data((t) => _api.put(
        '$_base/$brokerId/login',
        {
          if (username != null) 'username': username,
          if (password != null) 'password': password,
          if (enabled != null) 'enabled': enabled,
        },
        token: t,
      ));

  // ---- admin only: "Brokers allowed" per master ----

  Future<bool> masterAllowed(String masterId) async {
    final rows = _list(await _data((t) => _api.get('/admin/broker-access', token: t)));
    return rows.any((r) => r['master_id']?.toString() == masterId);
  }

  Future<void> setMasterAllowed(String masterId, bool allowed) async =>
      _data((t) => _api.put('/admin/broker-access/$masterId', {'allowed': allowed}, token: t));
}
