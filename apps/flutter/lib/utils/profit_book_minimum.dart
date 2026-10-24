import 'dart:convert';
import 'dart:developer';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import 'contants.dart';

/// Admin minimum profit book time (backend utils/profitBookTime.js, 24 Oct
/// 2026): default 5 minutes. A new client starts at it; no client's time can
/// be SET below it (an unchanged time below a since-raised minimum is kept).
const int kDefaultProfitBookMinimum = 5;

/// GET /admin/settings/profit-book-minimum (admin or master); the default on any failure.
Future<int> fetchProfitBookMinimum() async {
  try {
    final token = await SecureStorageService().getToken();
    final res = await ApiService(backendUrl).get('/admin/settings/profit-book-minimum', token: token);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final n = body['data']?['minutes'];
      if (n is num) return n.toInt();
    }
  } catch (e) {
    log('profit book minimum: $e');
  }
  return kDefaultProfitBookMinimum;
}

/// PUT /admin/settings/profit-book-minimum (admin). Returns null on success, else the error message.
Future<String?> saveProfitBookMinimum(int minutes) async {
  try {
    final token = await SecureStorageService().getToken();
    final res = await ApiService(backendUrl).put('/admin/settings/profit-book-minimum', {'minutes': minutes}, token: token);
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['success'] == true) return null;
    return (body['message'] ?? 'Could not save').toString();
  } catch (e) {
    return 'Could not save: $e';
  }
}
