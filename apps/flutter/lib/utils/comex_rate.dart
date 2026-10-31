import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import 'contants.dart';

/// COMEX dollar rate + spread for one master or client (backend
/// utils/comexFx.js, 1 Nov 2026), shown wherever COMEX is ticked. Pre-filled
/// with the account's rate (its own, else the master above's, else admin's
/// default); saved only when changed, so an untouched account keeps
/// following the master above. A master can't go below the master directly
/// above the account (dollar rate and spread each); admin can.
class ComexRateState {
  final TextEditingController base = TextEditingController();
  final TextEditingController spread = TextEditingController();
  double? _loadedBase;
  double? _loadedSpread;
  double? floorBase;
  double? floorSpread;
  bool loaded = false;

  void dispose() {
    base.dispose();
    spread.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _fill(Map? rate, Map? floor) {
    final b = (rate?['base'] as num?)?.toDouble();
    final s = (rate?['spread'] as num?)?.toDouble();
    _loadedBase = b;
    _loadedSpread = s;
    base.text = b == null ? '' : _fmt(b);
    spread.text = s == null ? '' : _fmt(s);
    floorBase = (floor?['base'] as num?)?.toDouble();
    floorSpread = (floor?['spread'] as num?)?.toDouble();
    loaded = true;
  }

  static Future<Map?> _get(String path) async {
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).get(path, token: token);
      if (res.statusCode == 200) return jsonDecode(res.body)['data'] as Map?;
    } catch (e) {
      log('comex rate: $e');
    }
    return null;
  }

  /// New account under [parentMasterId] (null = a top-level master → admin's default).
  Future<void> loadForCreate(String? parentMasterId) async {
    if (parentMasterId != null && parentMasterId.isNotEmpty) {
      final view = await _get('/admin/comex-rate/masters/$parentMasterId');
      final eff = view?['effective'] as Map?;
      _fill(eff, eff);
    } else {
      final def = await _get('/admin/comex-rate');
      _fill(def?['base'] == null ? null : def, null);
    }
  }

  /// Existing account: its own rate, else the one it follows; floor = the master above.
  Future<void> loadForEdit(String kind, String id) async {
    final view = await _get('/admin/comex-rate/${kind == 'client' ? 'clients' : 'masters'}/$id');
    _fill((view?['own'] ?? view?['effective']) as Map?, view?['floor'] as Map?);
  }

  /// Error text or null. Both empty = follow the master above. [limited]: the caller is a master.
  String? validate({required bool limited}) {
    final bt = base.text.trim();
    final st = spread.text.trim();
    if (bt.isEmpty && st.isEmpty) return null;
    final b = double.tryParse(bt);
    final s = double.tryParse(st);
    if (b == null || b <= 0 || b > 1000) return 'Enter a COMEX dollar rate above 0.';
    if (s == null || s < 0 || s >= b) return 'COMEX spread rate must be 0 or more and less than the dollar rate.';
    if (limited && floorBase != null && floorSpread != null && (b < floorBase! || s < floorSpread!)) {
      return "COMEX rate can't be below dollar rate ${_fmt(floorBase!)} and spread rate ${_fmt(floorSpread!)}.";
    }
    return null;
  }

  /// After create / update: stores the account's own rate only when changed. Null = ok, else the error.
  Future<String?> save(String kind, String id) async {
    final b = double.tryParse(base.text.trim());
    final s = double.tryParse(spread.text.trim());
    if (b == null || s == null) return null;
    if (b == _loadedBase && s == _loadedSpread) return null;
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).put(
          '/admin/comex-rate/${kind == 'client' ? 'clients' : 'masters'}/$id', {'base': b, 'spread': s},
          token: token);
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        _loadedBase = b;
        _loadedSpread = s;
        return null;
      }
      return (body['message'] ?? 'Could not save the COMEX rate').toString();
    } catch (e) {
      return 'Could not save the COMEX rate: $e';
    }
  }
}

/// Just the two fields: Dollar rate and Spread rate.
class ComexRateFields extends StatelessWidget {
  final ComexRateState state;
  const ComexRateFields({super.key, required this.state});

  Widget _field(String label, TextEditingController c) => Expanded(
        child: TextField(
          controller: c,
          enabled: state.loaded,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: label,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          _field('Dollar rate', state.base),
          const SizedBox(width: 12),
          _field('Spread rate', state.spread),
        ],
      ),
    );
  }
}
