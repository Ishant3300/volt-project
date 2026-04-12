import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'sercure_storage_service.dart';
import '../models/master.dart';

class AdminService {
  final ApiService _apiService;
  final SecureStorageService _storage = SecureStorageService();

  AdminService(this._apiService);

  // ============================================
  // Server Management
  // ============================================

  /// Get all servers
  Future<http.Response> getAllServers({
    int page = 1,
    int limit = 100,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/servers$queryString', token: token);
  }

  // ============================================
  // Master Management
  // ============================================

  /// Create a new master
  Future<http.Response> createMaster({
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
    MasterPermissions? permissions,
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
      if (permissions != null) 'permissions': permissions.toJson(),
    };

    final token = await _storage.getToken();
    // Use master flow route for creating child masters
    return await _apiService.post('/master/masters', data, token: token);
  }

  /// Get all masters with pagination
  Future<http.Response> getAllMasters({
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
    return await _apiService.get('/masters$queryString', token: token);
  }

  /// Get master by ID
  Future<http.Response> getMasterById(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/masters/$masterId', token: token);
  }

  /// Update master details
  Future<http.Response> updateMasterDetails({
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
    return await _apiService.put('/masters/$masterId/details', data, token: token);
  }

  /// Update master (full update)
  Future<http.Response> updateMaster({
    required String masterId,
    String? name,
    String? username,
    String? password,
    double? credits,
    String? note,
    double? pnlSharing,
    double? brokerageSharing,
    List<String>? exchangesAllowed,
    List<String>? tradeLimit,
    bool? addMaster,
    bool? changePassOnFirstLogin,
  }) async {
    final data = {
      if (name != null) 'name': name,
      if (username != null) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (credits != null) 'credits': credits,
      if (note != null) 'note': note,
      if (pnlSharing != null) 'pnl_sharing': pnlSharing,
      if (brokerageSharing != null) 'brokerage_sharing': brokerageSharing,
      if (exchangesAllowed != null) 'exchanges_allowed': exchangesAllowed,
      if (tradeLimit != null) 'trade_limit': tradeLimit,
      if (addMaster != null) 'add_master': addMaster,
      if (changePassOnFirstLogin != null) 'change_pass_on_first_login': changePassOnFirstLogin,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/masters/$masterId', data, token: token);
  }

  /// Update master permissions
  Future<http.Response> updateMasterPermissions({
    required String masterId,
    required MasterPermissions permissions,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/masters/$masterId/permissions', {
      'permissions': permissions.toJson(),
    }, token: token);
  }

  /// Update master status
  Future<http.Response> updateMasterStatus({
    required String masterId,
    bool? activeStatus,
    String? lastDueBill,
  }) async {
    final data = {
      if (activeStatus != null) 'active_status': activeStatus,
      if (lastDueBill != null) 'last_due_bill': lastDueBill,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/masters/$masterId/status', data, token: token);
  }

  /// Credit master account
  Future<http.Response> creditMaster({
    required String masterId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/masters/$masterId/credit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Debit master account
  Future<http.Response> debitMaster({
    required String masterId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/masters/$masterId/debit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Credit user account (admin flow)
  Future<http.Response> creditUser({
    required String userId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/admin/users/$userId/credit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Debit user account (admin flow)
  Future<http.Response> debitUser({
    required String userId,
    required double amount,
    String? note,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/admin/users/$userId/debit', {
      'amount': amount,
      if (note != null) 'note': note,
    }, token: token);
  }

  /// Get master position
  Future<http.Response> getMasterPosition(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/masters/$masterId/position', token: token);
  }

  /// Delete master (soft delete)
  Future<http.Response> deleteMaster(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/masters/$masterId', token: token);
  }

  // ============================================
  // Trade Management
  // ============================================

  /// Get all trades
  Future<http.Response> getAllTrades({
    String? masterId,
    String? userId,
    int page = 1,
    int limit = 50,
    String? dateFrom,
    String? dateTo,
    String? status,
    String? exchange,
    String? tradingsymbol,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    if (masterId != null) queryParams.add('master_id=$masterId');
    if (userId != null) queryParams.add('user_id=$userId');
    if (dateFrom != null) queryParams.add('date_from=$dateFrom');
    if (dateTo != null) queryParams.add('date_to=$dateTo');
    if (status != null) queryParams.add('status=$status');
    if (exchange != null) queryParams.add('exchange=$exchange');
    if (tradingsymbol != null) queryParams.add('tradingsymbol=${Uri.encodeComponent(tradingsymbol)}');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/masters/trades/all$queryString', token: token);
  }

  // ============================================
  // Messaging
  // ============================================

  /// Send message to master
  Future<http.Response> sendMessageToMaster({
    required String masterId,
    String? subject,
    required String message,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.post('/masters/$masterId/messages', {
      if (subject != null) 'subject': subject,
      'message': message,
    }, token: token);
  }

  // ============================================
  // User Management (if admin manages users directly)
  // ============================================

  /// Create a new user (Master endpoint)
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
    };

    final token = await _storage.getToken();
    return await _apiService.post('/master/users', data, token: token);
  }

  /// Get all users (Admin endpoint)
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
    return await _apiService.get('/admin/users$queryString', token: token);
  }

  /// Get user by ID
  Future<http.Response> getUserById(String userId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/users/$userId', token: token);
  }

  /// Update user details (partial update)
  Future<http.Response> updateUserDetails({
    required String userId,
    String? name,
    String? username,
    double? credits,
    String? note,
    List<String>? exchangesAllowed,
    List<String>? tradeLimit,
    bool? activeStatus,
    bool? marginSquareOff,
    bool? closeOnly,
    bool? bet,
    bool? freshStoploss,
  }) async {
    final data = {
      if (name != null) 'name': name,
      if (username != null) 'username': username,
      if (credits != null) 'credits': credits,
      if (note != null) 'note': note,
      if (exchangesAllowed != null) 'exchanges_allowed': exchangesAllowed,
      if (tradeLimit != null) 'trade_limit': tradeLimit,
      if (activeStatus != null) 'active_status': activeStatus,
      if (marginSquareOff != null) 'margin_square_off': marginSquareOff,
      if (closeOnly != null) 'close_only': closeOnly,
      if (bet != null) 'bet': bet,
      if (freshStoploss != null) 'fresh_stoploss': freshStoploss,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/master/users/$userId/details', data, token: token);
  }

  /// Update user (full update)
  Future<http.Response> updateUser({
    required String userId,
    String? name,
    String? username,
    String? password,
    double? credits,
    String? note,
    double? pnlSharing,
    double? brokerageSharing,
    List<Map<String, dynamic>>? exchangesAllowed,
    List<String>? tradeLimit,
    bool? marginSquareOff,
    bool? changePassOnFirstLogin,
  }) async {
    final data = {
      if (name != null) 'name': name,
      if (username != null) 'username': username,
      if (password != null && password.isNotEmpty) 'password': password,
      if (credits != null) 'credits': credits,
      if (note != null) 'note': note,
      if (pnlSharing != null) 'pnl_sharing': pnlSharing,
      if (brokerageSharing != null) 'brokerage_sharing': brokerageSharing,
      if (exchangesAllowed != null) 'exchanges_allowed': exchangesAllowed,
      if (tradeLimit != null) 'trade_limit': tradeLimit,
      if (marginSquareOff != null) 'margin_square_off': marginSquareOff,
      if (changePassOnFirstLogin != null) 'change_pass_on_first_login': changePassOnFirstLogin,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/master/users/$userId', data, token: token);
  }

  // ============================================
  // Master Flow - Child Masters and Users
  // ============================================

  /// Get all child masters (Master endpoint - returns only children of logged-in master)
  Future<http.Response> getChildMasters({
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/master/masters$queryString', token: token);
  }

  /// Get all child users (Master endpoint - returns only children of logged-in master)
  Future<http.Response> getChildUsers({
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/master/users$queryString', token: token);
  }

  // ============================================
  // Grouped Quantity Management
  // ============================================

  /// Create grouped quantity
  Future<http.Response> createGroupedQuantity({
    required String exchangeName,
    required String lotName,
    required String instrumentId,
    required String instrumentSymbol,
    required double maxQty,
    required double breakQty,
    required double lotSize,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'lot_name': lotName,
      'instrument_id': instrumentId,
      'instrument_symbol': instrumentSymbol,
      'max_qty': maxQty,
      'break_qty': breakQty,
      'lot_size': lotSize,
    };

    final token = await _storage.getToken();
    return await _apiService.post('/admin/grouped-quantities', data, token: token);
  }

  /// Get all grouped quantities
  Future<http.Response> getAllGroupedQuantities({
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/grouped-quantities$queryString', token: token);
  }

  /// Get grouped quantity by ID
  Future<http.Response> getGroupedQuantityById(String id) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/grouped-quantities/$id', token: token);
  }

  /// Update grouped quantity
  Future<http.Response> updateGroupedQuantity({
    required String id,
    String? exchangeName,
    String? lotName,
    String? instrumentId,
    String? instrumentSymbol,
    double? maxQty,
    double? breakQty,
    double? lotSize,
  }) async {
    final data = {
      if (exchangeName != null) 'exchange_name': exchangeName,
      if (lotName != null) 'lot_name': lotName,
      if (instrumentId != null) 'instrument_id': instrumentId,
      if (instrumentSymbol != null) 'instrument_symbol': instrumentSymbol,
      if (maxQty != null) 'max_qty': maxQty,
      if (breakQty != null) 'break_qty': breakQty,
      if (lotSize != null) 'lot_size': lotSize,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/admin/grouped-quantities/$id', data, token: token);
  }

  /// Delete grouped quantity
  Future<http.Response> deleteGroupedQuantity(String id) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/admin/grouped-quantities/$id', token: token);
  }

  /// Get unique raw_names by segment
  Future<http.Response> getUniqueRawNamesBySegment(String segment) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/grouped-quantities/unique-raw-names/$segment', token: token);
  }

  /// Bulk create a group with all instruments for a segment
  Future<http.Response> bulkCreateGroup({
    required String exchangeName,
    required String lotName,
    required double defaultMaxQty,
    required double defaultBreakQty,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'lot_name': lotName,
      'default_max_qty': defaultMaxQty,
      'default_break_qty': defaultBreakQty,
    };
    final token = await _storage.getToken();
    return await _apiService.post('/admin/grouped-quantities/bulk-create', data, token: token);
  }

  /// Get all instruments in a specific group
  Future<http.Response> getGroupInstruments({
    required String exchangeName,
    required String lotName,
    int page = 1,
    int limit = 500,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.get(
      '/admin/grouped-quantities/group/$exchangeName/$lotName?page=$page&limit=$limit',
      token: token,
    );
  }

  // ============================================
  // Script Quantity Management
  // ============================================

  /// Create script quantity
  Future<http.Response> createScriptQuantity({
    required String exchangeName,
    required String scriptName,
    required int lotSize,
    required int maxQty,
    required int brkQty,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'script_name': scriptName,
      'lot_size': lotSize,
      'max_qty': maxQty,
      'brk_qty': brkQty,
    };

    final token = await _storage.getToken();
    return await _apiService.post('/admin/script-quantities', data, token: token);
  }

  /// Get all script quantities
  Future<http.Response> getAllScriptQuantities({
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/script-quantities$queryString', token: token);
  }

  /// Get script quantity by ID
  Future<http.Response> getScriptQuantityById(String id) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/script-quantities/$id', token: token);
  }

  /// Get lot names by exchange
  Future<http.Response> getLotNamesByExchange(String exchangeName) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/grouped-quantities/exchange/$exchangeName/lot-names', token: token);
  }

  /// Update script quantity
  Future<http.Response> updateScriptQuantity({
    required String id,
    String? exchangeName,
    String? scriptName,
    int? lotSize,
    int? maxQty,
    int? brkQty,
  }) async {
    final data = {
      if (exchangeName != null) 'exchange_name': exchangeName,
      if (scriptName != null) 'script_name': scriptName,
      if (lotSize != null) 'lot_size': lotSize,
      if (maxQty != null) 'max_qty': maxQty,
      if (brkQty != null) 'brk_qty': brkQty,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/admin/script-quantities/$id', data, token: token);
  }

  /// Delete script quantity
  Future<http.Response> deleteScriptQuantity(String id) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/admin/script-quantities/$id', token: token);
  }

  // ============================================
  // Trade Margin Management
  // ============================================

  /// Create trade margin
  Future<http.Response> createTradeMargin({
    required String exchangeName,
    required String scriptName,
    required String amountType,
    required double tradeMargin,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'script_name': scriptName,
      'amount_type': amountType,
      'trade_margin': tradeMargin,
    };

    print('📤 AdminService.createTradeMargin called');
    print('   Trade margin data: $data');
    final token = await _storage.getToken();
    print('   Token: ${token != null ? "Present" : "Missing"}');
    final response = await _apiService.post('/admin/trade-margins', data, token: token);
    print('   Response: ${response.statusCode} - ${response.body}');
    return response;
  }

  /// Get all trade margins
  Future<http.Response> getAllTradeMargins({
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/trade-margins$queryString', token: token);
  }

  /// Get trade margin by ID
  Future<http.Response> getTradeMarginById(String id) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/trade-margins/$id', token: token);
  }

  /// Update trade margin
  Future<http.Response> updateTradeMargin({
    required String id,
    String? exchangeName,
    String? scriptName,
    String? amountType,
    double? tradeMargin,
  }) async {
    final data = {
      if (exchangeName != null) 'exchange_name': exchangeName,
      if (scriptName != null) 'script_name': scriptName,
      if (amountType != null) 'amount_type': amountType,
      if (tradeMargin != null) 'trade_margin': tradeMargin,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/admin/trade-margins/$id', data, token: token);
  }

  /// Delete trade margin
  Future<http.Response> deleteTradeMargin(String id) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/admin/trade-margins/$id', token: token);
  }

  // ============================================
  // Brokerage Settings Management
  // ============================================

  /// Create brokerage settings
  Future<http.Response> createBrokerageSettings({
    required String type,
    required String exchangeName,
    required String scriptName,
    required double brkValue,
  }) async {
    final data = {
      'type': type,
      'exchange_name': exchangeName,
      'script_name': scriptName,
      'brk_value': brkValue,
    };

    final token = await _storage.getToken();
    return await _apiService.post('/admin/brokerage-settings', data, token: token);
  }

  /// Get all brokerage settings
  Future<http.Response> getAllBrokerageSettings({
    int page = 1,
    int limit = 20,
  }) async {
    final queryParams = <String>[];
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    
    final queryString = queryParams.isNotEmpty ? '?${queryParams.join('&')}' : '';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/brokerage-settings$queryString', token: token);
  }

  /// Get brokerage settings by ID
  Future<http.Response> getBrokerageSettingsById(String id) async {
    final token = await _storage.getToken();
    return await _apiService.get('/admin/brokerage-settings/$id', token: token);
  }

  /// Update brokerage settings
  Future<http.Response> updateBrokerageSettings({
    required String id,
    String? type,
    String? exchangeName,
    String? scriptName,
    double? brkValue,
  }) async {
    final data = {
      if (type != null) 'type': type,
      if (exchangeName != null) 'exchange_name': exchangeName,
      if (scriptName != null) 'script_name': scriptName,
      if (brkValue != null) 'brk_value': brkValue,
    };

    final token = await _storage.getToken();
    return await _apiService.put('/admin/brokerage-settings/$id', data, token: token);
  }

  /// Delete brokerage settings
  Future<http.Response> deleteBrokerageSettings(String id) async {
    final token = await _storage.getToken();
    return await _apiService.delete('/admin/brokerage-settings/$id', token: token);
  }

  /// Bulk create brokerage settings for all raw_names in a segment
  Future<http.Response> bulkCreateBrokerage({
    required String exchangeName,
    required String type,
    required double defaultBrkValue,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'type': type,
      'default_brk_value': defaultBrkValue,
    };
    final token = await _storage.getToken();
    return await _apiService.post('/admin/brokerage-settings/bulk-create', data, token: token);
  }

  /// Get brokerage settings by exchange with optional type filter
  Future<http.Response> getBrokerageByExchange({
    required String exchangeName,
    String? type,
    int page = 1,
    int limit = 500,
  }) async {
    final queryParams = <String>['page=$page', 'limit=$limit'];
    if (type != null) queryParams.add('type=$type');
    final queryString = '?${queryParams.join('&')}';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/brokerage-settings/exchange/$exchangeName$queryString', token: token);
  }

  /// Bulk create trade margins for all raw_names in a segment
  Future<http.Response> bulkCreateTradeMargin({
    required String exchangeName,
    required String amountType,
    required double defaultTradeMargin,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'amount_type': amountType,
      'default_trade_margin': defaultTradeMargin,
    };
    final token = await _storage.getToken();
    return await _apiService.post('/admin/trade-margins/bulk-create', data, token: token);
  }

  /// Get trade margins by exchange with optional amount_type filter
  Future<http.Response> getTradeMarginByExchange({
    required String exchangeName,
    String? amountType,
    int page = 1,
    int limit = 500,
  }) async {
    final queryParams = <String>['page=$page', 'limit=$limit'];
    if (amountType != null) queryParams.add('amount_type=$amountType');
    final queryString = '?${queryParams.join('&')}';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/trade-margins/exchange/$exchangeName$queryString', token: token);
  }

  /// Bulk create script quantities for all raw_names in a segment
  Future<http.Response> bulkCreateScriptQuantity({
    required String exchangeName,
    required double defaultMaxQty,
    required double defaultBrkQty,
  }) async {
    final data = {
      'exchange_name': exchangeName,
      'default_max_qty': defaultMaxQty,
      'default_brk_qty': defaultBrkQty,
    };
    final token = await _storage.getToken();
    return await _apiService.post('/admin/script-quantities/bulk-create', data, token: token);
  }

  /// Get script quantities by exchange
  Future<http.Response> getScriptQuantityByExchange({
    required String exchangeName,
    int page = 1,
    int limit = 500,
  }) async {
    final queryParams = <String>['page=$page', 'limit=$limit'];
    final queryString = '?${queryParams.join('&')}';
    final token = await _storage.getToken();
    return await _apiService.get('/admin/script-quantities/exchange/$exchangeName$queryString', token: token);
  }

  // ============================================
  // Intraday Squareoff Management
  // ============================================

  /// Update master intraday squareoff settings
  Future<http.Response> updateMasterIntradaySquareoff({
    required String masterId,
    required List<Map<String, dynamic>> intradaySquareoff,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/masters/$masterId/intraday-squareoff', {
      'intraday_squareoff': intradaySquareoff,
    }, token: token);
  }

  /// Update user intraday squareoff settings
  Future<http.Response> updateUserIntradaySquareoff({
    required String userId,
    required List<Map<String, dynamic>> intradaySquareoff,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/master-flow/users/$userId/intraday-squareoff', {
      'intraday_squareoff': intradaySquareoff,
    }, token: token);
  }

  /// Update master margin squareoff percentage
  Future<http.Response> updateMasterMarginSquareoffPercentage({
    required String masterId,
    required double percentage,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/masters/$masterId/margin-squareoff-percentage', {
      'margin_square_off_percentage': percentage,
    }, token: token);
  }

  /// Update user margin squareoff percentage
  Future<http.Response> updateUserMarginSquareoffPercentage({
    required String userId,
    required double percentage,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/master/users/$userId/margin-squareoff-percentage', {
      'margin_square_off_percentage': percentage,
    }, token: token);
  }

  // ============================================
  // Account Limit
  // ============================================

  Future<http.Response> getAccountLimit(String masterId) async {
    final token = await _storage.getToken();
    return await _apiService.get('/masters/$masterId/account-limit', token: token);
  }

  Future<http.Response> updateAccountLimit({
    required String masterId,
    required bool enabled,
    required int maxMasters,
    required int maxUsers,
  }) async {
    final token = await _storage.getToken();
    return await _apiService.put('/masters/$masterId/account-limit', {
      'enabled': enabled,
      'max_masters': maxMasters,
      'max_users': maxUsers,
    }, token: token);
  }
}
