import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'sercure_storage_service.dart';

class UserService {
  final ApiService _apiService;
  final SecureStorageService _storage = SecureStorageService();

  UserService(this._apiService);

  /// Fetch all user's trades by ID
  Future<http.Response> getUserTrades({
    required String userId,
    int page = 1,
    int limit = 50,
    String? dateFrom,
    String? dateTo,
    String? status,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    if (dateFrom != null) queryParams.add('date_from=$dateFrom');
    if (dateTo != null) queryParams.add('date_to=$dateTo');
    if (status != null) queryParams.add('status=$status');

    final queryString =
        queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();

    return await _apiService.get('/users/$userId/trades$queryString',
        token: token);
  }
}
