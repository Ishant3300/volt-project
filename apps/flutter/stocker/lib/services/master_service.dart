import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'sercure_storage_service.dart';

class MasterService {
  final ApiService _apiService;
  final SecureStorageService _storage = SecureStorageService();

  MasterService(this._apiService);

  // ============================================
  // Child Master Management
  // ============================================

  /// Create a child master
  Future<http.Response> createChildMaster({
    required String name,
    required String username,
    required String password,
    required double credits,
    required String note,
    required double pnlSharing,
    required double brokerageSharing,
    required List<String> exchangesAllowed,
    required List<String> tradeLimit,
    required bool addMaster,
    required bool changePassOnFirstLogin,
    required String serverId,
    double? maxCredit,
    String? status,
    bool? activeStatus,
    String? lastDueBill,
    List<String>? exchanges,
    Map<String, bool>? permissions,
    Map<String, double>? wallet,
  }) async {
    final data = {
      'name': name,
      'username': username,
      'password': password,
      'credits': credits,
      'note': note,
      'pnl_sharing': pnlSharing,
      'brokerage_sharing': brokerageSharing,
      'exchanges_allowed': exchangesAllowed,
      'trade_limit': tradeLimit,
      'add_master': addMaster,
      'change_pass_on_first_login': changePassOnFirstLogin,
      'server_id': serverId,
      if (maxCredit != null) 'max_credit': maxCredit,
      if (status != null) 'status': status,
      if (activeStatus != null) 'active_status': activeStatus,
      if (lastDueBill != null) 'last_due_bill': lastDueBill,
      if (exchanges != null) 'exchanges': exchanges,
      if (permissions != null) 'permissions': permissions,
      if (wallet != null && wallet.isNotEmpty) 'wallet': wallet,
    };

    final token = await _storage.getToken();
    return await _apiService.post('/master/masters', data, token: token);
  }

  /// Get all child masters
  Future<http.Response> getAllChildMasters({
    int page = 1,
    int limit = 20,
    String? status,
    String? serverId,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    if (status != null) queryParams.add('status=$status');
    if (serverId != null) queryParams.add('server_id=$serverId');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/master/masters$queryString', token: token);
  }

  /// Get child master by ID
  Future<http.Response> getChildMasterById(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/master/masters/$masterId', token: token);
  }

  /// Update child master details
  Future<http.Response> updateChildMasterDetails({
    required String masterId,
    String? name,
    String? username,
    double? credits,
    String? note,
    List<String>? exchangesAllowed,
    List<String>? tradeLimit,
  }) async {
    final data = {
      if (name != null) 'name': name,
      if (username != null) 'username': username,
      if (credits != null) 'credits': credits,
      if (note != null) 'note': note,
      if (exchangesAllowed != null) 'exchanges_allowed': exchangesAllowed,
      if (tradeLimit != null) 'trade_limit': tradeLimit,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/master/masters/$masterId/details', data, token: token);
  }

  /// Update child master permissions
  Future<http.Response> updateChildMasterPermissions({
    required String masterId,
    required Map<String, bool> permissions,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/master/masters/$masterId/permissions', {
      'permissions': permissions,
    }, token: token);
  }

  /// Credit child master account
  Future<http.Response> creditChildMaster({
    required String masterId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/masters/$masterId/credit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Debit child master account
  Future<http.Response> debitChildMaster({
    required String masterId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/masters/$masterId/debit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Get child master position
  Future<http.Response> getChildMasterPosition(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/master/masters/$masterId/position', token: token);
  }

  /// Send message to child master
  Future<http.Response> sendMessageToChildMaster({
    required String masterId,
    String? subject,
    required String message,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/masters/$masterId/messages', {
      if (subject != null) 'subject': subject,
      'message': message,
    }, token: token);
  }

  /// Delete child master (soft delete)
  Future<http.Response> deleteChildMaster(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/master/masters/$masterId', token: token);
  }

  // ============================================
  // User Management
  // ============================================

  /// Create a user
  Future<http.Response> createUser({
    required String name,
    required String username,
    required String password,
    required double credits,
    required String note,
    required double pnlSharing,
    required double brokerageSharing,
    required List<Map<String, dynamic>> exchangesAllowed,
    required List<String> tradeLimit,
    required bool marginSquareOff,
    required bool changePassOnFirstLogin,
    required String serverId,
    String? status,
    Map<String, double>? wallet,
  }) async {
    final data = {
      'name': name,
      'username': username,
      'password': password,
      'credits': credits,
      'note': note,
      'pnl_sharing': pnlSharing,
      'brokerage_sharing': brokerageSharing,
      'exchanges_allowed': exchangesAllowed,
      'trade_limit': tradeLimit,
      'margin_square_off': marginSquareOff,
      'change_pass_on_first_login': changePassOnFirstLogin,
      'server_id': serverId,
      if (status != null) 'status': status,
      if (wallet != null && wallet.isNotEmpty) 'wallet': wallet,
    };

    final token = await _storage.getToken();
    return await _apiService.post('/master/users', data, token: token);
  }

  /// Get all users
  Future<http.Response> getAllUsers({
    int page = 1,
    int limit = 20,
    String? status,
    String? serverId,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    if (status != null) queryParams.add('status=$status');
    if (serverId != null) queryParams.add('server_id=$serverId');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/master/users$queryString', token: token);
  }

  /// Get user by ID
  Future<http.Response> getUserById(String userId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/master/users/$userId', token: token);
  }

  /// Update user details
  Future<http.Response> updateUserDetails({
    required String userId,
    String? name,
    String? username,
    double? credits,
    String? note,
    List<Map<String, dynamic>>? exchangesAllowed,
    List<String>? tradeLimit,
  }) async {
    final data = {
      if (name != null) 'name': name,
      if (username != null) 'username': username,
      if (credits != null) 'credits': credits,
      if (note != null) 'note': note,
      if (exchangesAllowed != null) 'exchanges_allowed': exchangesAllowed,
      if (tradeLimit != null) 'trade_limit': tradeLimit,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/master/users/$userId/details', data, token: token);
  }

  /// Credit user account
  Future<http.Response> creditUser({
    required String userId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/users/$userId/credit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Debit user account
  Future<http.Response> debitUser({
    required String userId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/users/$userId/debit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Get user position
  Future<http.Response> getUserPosition(String userId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/master/users/$userId/position', token: token);
  }

  /// Send message to user
  Future<http.Response> sendMessageToUser({
    required String userId,
    String? subject,
    required String message,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/users/$userId/messages', {
      if (subject != null) 'subject': subject,
      'message': message,
    }, token: token);
  }

  /// Delete user (soft delete)
  Future<http.Response> deleteUser(String userId) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/master/users/$userId', token: token);
  }

  // ============================================
  // Trade Management
  // ============================================

  /// Get all trades in hierarchy
  Future<http.Response> getAllTrades({
    String? masterId,
    String? userId,
    int page = 1,
    int limit = 50,
    String? dateFrom,
    String? dateTo,
    String? status,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    if (masterId != null) queryParams.add('master_id=$masterId');
    if (userId != null) queryParams.add('user_id=$userId');
    if (dateFrom != null) queryParams.add('date_from=$dateFrom');
    if (dateTo != null) queryParams.add('date_to=$dateTo');
    if (status != null) queryParams.add('status=$status');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/master/trades$queryString', token: token);
  }

  // ============================================
  // Trade Wallet Funding (category pools)
  // ============================================

  /// Assign category funds to a direct child (debits master's same-category pool)
  Future<http.Response> walletAssign({
    required String targetId,
    required String targetType,
    required String category,
    required double amount,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/wallet/assign', {
      'target_id': targetId,
      'target_type': targetType,
      'category': category,
      'amount': amount,
    }, token: token);
  }

  /// Withdraw category funds from a direct child (credits master's same-category pool)
  Future<http.Response> walletWithdraw({
    required String targetId,
    required String targetType,
    required String category,
    required double amount,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/master/wallet/withdraw', {
      'target_id': targetId,
      'target_type': targetType,
      'category': category,
      'amount': amount,
    }, token: token);
  }

  /// Get an owner's per-category wallet balances
  Future<http.Response> getWallet({
    required String ownerId,
    required String ownerType,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.get(
      '/master/wallet?owner_id=$ownerId&owner_type=$ownerType',
      token: token,
    );
  }
}
