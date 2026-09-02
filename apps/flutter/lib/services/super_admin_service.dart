import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'sercure_storage_service.dart';

/// Super Admin-only admin-management calls — /api/super-admin/admins/*.
class SuperAdminService {
  final ApiService _apiService;
  final SecureStorageService _storage = SecureStorageService();

  SuperAdminService(this._apiService);

  Future<http.Response> createAdmin({
    required String username,
    required String password,
    List<String>? permissions,
  }) async {
    final data = {
      'username': username,
      'password': password,
      if (permissions != null) 'permissions': permissions,
    };
    final token = await _storage.getToken();
    return await _apiService.post('/super-admin/admins', data, token: token);
  }

  Future<http.Response> getAllAdmins() async {
    final token = await _storage.getToken();
    return await _apiService.get('/super-admin/admins', token: token);
  }

  Future<http.Response> getAdmin(String id) async {
    final token = await _storage.getToken();
    return await _apiService.get('/super-admin/admins/$id', token: token);
  }

  Future<http.Response> updatePermissions({
    required String id,
    List<String>? permissions,
    bool? watchOnly,
  }) async {
    final data = {
      if (permissions != null) 'permissions': permissions,
      if (watchOnly != null) 'watch_only': watchOnly,
    };
    final token = await _storage.getToken();
    return await _apiService.put('/super-admin/admins/$id/permissions', data, token: token);
  }

  /// Wholesale replace — the client sends the full current hidden-id set
  /// each time, not one toggle-a-single-master-off call.
  Future<http.Response> updateMasterVisibility({
    required String id,
    required List<String> hiddenMasterIds,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put(
      '/super-admin/admins/$id/master-visibility',
      {'hidden_master_ids': hiddenMasterIds},
      token: token,
    );
  }

  Future<http.Response> updateStatus({
    required String id,
    required bool activeStatus,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put(
      '/super-admin/admins/$id/status',
      {'active_status': activeStatus},
      token: token,
    );
  }

  Future<http.Response> deleteAdmin(String id) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/super-admin/admins/$id', token: token);
  }
}
