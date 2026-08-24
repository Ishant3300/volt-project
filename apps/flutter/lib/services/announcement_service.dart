import 'dart:convert';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class AnnouncementService {
  static final AnnouncementService _instance = AnnouncementService._();
  factory AnnouncementService() => _instance;
  AnnouncementService._();

  final _api = ApiService(backendUrl);
  final _storage = SecureStorageService();

  String? _cachedMessage;
  String? get currentMessage => _cachedMessage;

  Future<String?> fetchActive() async {
    try {
      final token = await _storage.getToken();
      final res = await _api.get('/admin/announcements/active', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        _cachedMessage = body['data']?['message'];
        return _cachedMessage;
      }
    } catch (_) {}
    return _cachedMessage;
  }

  Future<bool> send(String message) async {
    try {
      final token = await _storage.getToken();
      final res = await _api.post('/admin/announcements', {'message': message}, token: token);
      return res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clear() async {
    try {
      final token = await _storage.getToken();
      final res = await _api.delete('/admin/announcements', token: token);
      if (res.statusCode == 200) {
        _cachedMessage = null;
        return true;
      }
    } catch (_) {}
    return false;
  }
}
