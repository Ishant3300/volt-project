import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:jwt_decode/jwt_decode.dart';
import '../models/user.dart';
import '../models/master.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';

class UserProfileProvider with ChangeNotifier {
  final ApiService _apiService;
  final SecureStorageService _storage = SecureStorageService();

  User? _user;
  Master? _master;
  dynamic _admin;
  String? _role;
  bool _isLoading = false;
  String? _error;

  UserProfileProvider(this._apiService);

  User? get user => _user;
  Master? get master => _master;
  dynamic get admin => _admin;
  String? get role => _role;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get isAdmin => _role == 'ADMIN';
  bool get isMaster => _role == 'MASTER';
  bool get isUser => _role == 'USER';

  /// Super Admin is an Admin with one extra capability (manage other
  /// Admins) — never a separate role string, just this flag on top of
  /// isAdmin. Populated from GET /api/admin/profile's is_super_admin field.
  bool get isSuperAdmin => isAdmin && _admin is Map && _admin['is_super_admin'] == true;

  /// A regular (non-super) Admin's granted permission keys — empty for
  /// Super Admin (never gated by this list) and for every other role.
  List<String> get adminPermissions {
    if (!isAdmin || _admin is! Map) return [];
    final raw = _admin['permissions'];
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).toList();
  }

  bool get isWatchOnlyAdmin => isAdmin && _admin is Map && _admin['watch_only'] == true;

  // Check if master can add child masters
  bool get canAddMaster {
    if (_master != null) {
      return _master!.addMaster;
    }
    return false;
  }

  /// Get report permissions for the current user/master.
  /// Admin always gets all permissions (true).
  /// Master gets their own permissions object.
  /// User gets the report_permissions from their parent Master (returned by the API).
  Map<String, bool> get reportPermissions {
    if (isAdmin) {
      return {
        'account_summary': true,
        'pnl_summary': true,
        'client_summary': true,
        'settlement_report': true,
        'generate_pdf': true,
        'weekly_admin': true,
        'intraday_history': true,
        'userwise_open_position': true,
        'script_quantity': true,
        'deleted_trade': true,
        'trade_account': true,
      };
    }
    if (isMaster && _master?.permissions != null) {
      final p = _master!.permissions!;
      return {
        'account_summary': p.accountSummary,
        'pnl_summary': p.pnlSummary,
        'client_summary': p.clientSummary,
        'settlement_report': p.settlementReport,
        'generate_pdf': p.generatePdf,
        'weekly_admin': p.weeklyAdmin,
        'intraday_history': p.intradayHistory,
        'userwise_open_position': p.userwiseOpenPosition,
        'script_quantity': p.scriptQuantity,
        'deleted_trade': p.deletedTrade,
        'trade_account': p.tradeAccount,
      };
    }
    if (isUser && _user?.reportPermissions != null) {
      return _user!.reportPermissions!;
    }
    // Default: all reports visible
    return {
      'account_summary': true,
      'pnl_summary': true,
      'client_summary': true,
      'settlement_report': true,
      'generate_pdf': true,
      'weekly_admin': true,
      'intraday_history': true,
      'userwise_open_position': true,
      'script_quantity': true,
      'deleted_trade': true,
      'trade_account': true,
    };
  }

  /// Whether any report is accessible (used to show/hide the Reports menu item)
  bool get hasAnyReportPermission {
    return reportPermissions.values.any((v) => v);
  }

  /// Fetch current user/master/admin profile based on role
  Future<void> fetchProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final token = await _storage.getToken();
      final role = await _storage.getRole();

      if (token == null || role == null) {
        _error = 'Not authenticated';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _role = role;

      // Clear stale profile data before fetching fresh
      _user = null;
      _master = null;
      _admin = null;

      // Decode JWT to get user/master/admin ID
      Map<String, dynamic> payload = Jwt.parseJwt(token);
      String? id = payload['id'];

      if (id == null) {
        _error = 'Invalid token';
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Fetch profile based on role
      if (role == 'USER') {
        await _fetchUserProfile(id, token);
      } else if (role == 'MASTER') {
        await _fetchMasterProfile(id, token);
      } else if (role == 'ADMIN') {
        await _fetchAdminProfile(id, token);
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      log('❌ Error fetching profile: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchUserProfile(String userId, String token) async {
    try {
      final response = await _apiService.get('/users/$userId', token: token);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _user = User.fromJson(data['data']);
          log('✅ User profile loaded: ${_user?.username}');
        }
      } else {
        log('❌ Failed to fetch user profile: ${response.statusCode}');
      }
    } catch (e) {
      log('❌ Error fetching user profile: $e');
      rethrow;
    }
  }

  Future<void> _fetchMasterProfile(String masterId, String token) async {
    try {
      log('🔍 Fetching master profile for ID: $masterId');
      final response =
          await _apiService.get('/masters/$masterId', token: token);

      log('🔍 Master profile response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _master = Master.fromJson(data['data']);
          log('✅ Master profile loaded: ${_master?.username}, add_master: ${_master?.addMaster}');
        }
      } else {
        log('❌ Failed to fetch master profile: ${response.statusCode}');
        log('   Response: ${response.body}');
      }
    } catch (e) {
      log('❌ Error fetching master profile: $e');
      rethrow;
    }
  }

  Future<void> _fetchAdminProfile(String adminId, String token) async {
    try {
      // Admin model has username and createdAt from DB
      // Use the account-summary endpoint or decode from stored login response
      // For now, fetch directly via admin GET endpoint
      final response = await _apiService.get('/admin/profile', token: token);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          _admin = data['data'];
          log('✅ Admin profile loaded: ${_admin['username']}');
        } else {
          _admin = {'id': adminId};
        }
      } else {
        // Fallback — at minimum store the id
        _admin = {'id': adminId};
        log('⚠️ Admin profile endpoint returned ${response.statusCode}, using minimal data');
      }
    } catch (e) {
      log('❌ Error in admin profile: $e');
      _admin = {'id': adminId};
    }
  }

  /// Clear profile data on logout
  void clearProfile() {
    _user = null;
    _master = null;
    _admin = null;
    _role = null;
    _error = null;
    // Also clear the stored add_master permission
    _storage.deleteAddMasterPermission();
    notifyListeners();
  }

  /// Refresh profile data
  Future<void> refreshProfile() async {
    await fetchProfile();
  }
}
