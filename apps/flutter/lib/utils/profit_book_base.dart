import 'dart:convert';
import 'dart:developer';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import 'contants.dart';

/// A master's base profit book time (backend utils/profitBookTime.js, 25 Oct
/// 2026): no client or sub-master under it can be given less; raising it
/// lifts the whole tree below. Admin sets any master's; a master only its
/// own sub-masters'. A top-level master starts at 10 with no minimum.
const int kDefaultProfitBookBase = 10;

class ProfitBookBase {
  final int minutes;

  /// The parent's base (minimum for this master); null = top-level.
  final int? floor;
  final String? username;
  final String? parentUsername;
  const ProfitBookBase(this.minutes, this.floor, this.username, this.parentUsername);
}

/// GET /admin/profit-book-base/:masterId — null on failure.
Future<ProfitBookBase?> fetchProfitBookBase(String masterId) async {
  try {
    final token = await SecureStorageService().getToken();
    final res = await ApiService(backendUrl).get('/admin/profit-book-base/$masterId', token: token);
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body)['data'];
      final m = d?['minutes'];
      if (m is num) {
        final f = d['floor'];
        return ProfitBookBase(m.toInt(), f is num ? f.toInt() : null, d['username']?.toString(), d['parent_username']?.toString());
      }
    }
  } catch (e) {
    log('profit book base: $e');
  }
  return null;
}

/// How many clients / sub-masters a raise to [minutes] would lift — (clients, masters), or null.
Future<(int, int)?> previewProfitBookBase(String masterId, int minutes) async {
  try {
    final token = await SecureStorageService().getToken();
    final res = await ApiService(backendUrl).get('/admin/profit-book-base/$masterId/preview?minutes=$minutes', token: token);
    if (res.statusCode == 200) {
      final d = jsonDecode(res.body)['data'];
      return ((d['clients'] as num).toInt(), (d['masters'] as num).toInt());
    }
  } catch (e) {
    log('profit book base preview: $e');
  }
  return null;
}

/// PUT /admin/profit-book-base/:masterId — null on success, else the error message.
Future<String?> saveProfitBookBase(String masterId, int minutes) async {
  try {
    final token = await SecureStorageService().getToken();
    final res = await ApiService(backendUrl).put('/admin/profit-book-base/$masterId', {'minutes': minutes}, token: token);
    final body = jsonDecode(res.body);
    if (res.statusCode == 200 && body['success'] == true) return null;
    return (body['message'] ?? 'Could not save the base profit book time').toString();
  } catch (e) {
    return 'Could not save the base profit book time: $e';
  }
}
