import 'dart:convert';
import 'dart:developer';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';

class CreateUserData {
  final String username;
  final String password;
  final String serverId;
  final String masterId;
  final int? credit;
  final int? currentCredit;
  final int? balance;
  final List<String>? exchangesSupport;
  final String? status;

  CreateUserData({
    required this.username,
    required this.password,
    required this.serverId,
    required this.masterId,
    this.credit,
    this.currentCredit,
    this.balance,
    this.exchangesSupport,
    this.status,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      "username": username,
      "password": password,
      "server_id": serverId,
      "master_id": masterId,
    };

    if (credit != null) map["credit"] = credit;
    if (currentCredit != null) map["current_credit"] = currentCredit;
    if (balance != null) map["balance"] = balance;
    if (exchangesSupport != null) map["exchanges_support"] = exchangesSupport;
    if (status != null) map["status"] = status;

    return map;
  }
}

class UpdateUserData {
  final String? username;
  final String? password;
  final String? serverId;
  final String? masterId;
  final int? credit;
  final int? currentCredit;
  final int? balance;
  final List<String>? exchangesSupport;
  final String? status;

  UpdateUserData({
    this.username,
    this.password,
    this.serverId,
    this.masterId,
    this.credit,
    this.currentCredit,
    this.balance,
    this.exchangesSupport,
    this.status,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};

    if (username != null) map["username"] = username;
    if (password != null) map["password"] = password;
    if (serverId != null) map["server_id"] = serverId;
    if (masterId != null) map["master_id"] = masterId;
    if (credit != null) map["credit"] = credit;
    if (currentCredit != null) map["current_credit"] = currentCredit;
    if (balance != null) map["balance"] = balance;
    if (exchangesSupport != null) map["exchanges_support"] = exchangesSupport;
    if (status != null) map["status"] = status;

    return map;
  }
}

class AdminResponse {
  final bool success;
  final String message;
  final dynamic data;

  AdminResponse({
    required this.success,
    required this.message,
    required this.data,
  });

  factory AdminResponse.fromJson(Map<String, dynamic> json) {
    return AdminResponse(
      success: json["success"],
      message: json["message"],
      data: json["data"],
    );
  }
}

class AdminService {
  final ApiService api;
  final SecureStorageService storage = SecureStorageService();

  AdminService(this.api);

  Future<String?> _getToken() async {
    return await storage.getToken();
  }

  // Create User
  Future<AdminResponse> createUser(CreateUserData data) async {
    try {
      final token = await _getToken();
      final response = await api.post(
        '/api/admin/users',
        data.toJson(),
        token: token,
      );

      final decoded = jsonDecode(response.body);
      return AdminResponse.fromJson(decoded);
    } catch (err) {
      log(err.toString());
      rethrow;
    }
  }

  // Get All Users
  Future<AdminResponse> getAllUsers({
    int page = 1,
    int limit = 20,
    String? status,
    String? serverId,
    String? masterId,
  }) async {
    try {
      final token = await _getToken();
      String endpoint = '/api/admin/users?page=$page&limit=$limit';

      if (status != null) endpoint += '&status=$status';
      if (serverId != null) endpoint += '&server_id=$serverId';
      if (masterId != null) endpoint += '&master_id=$masterId';

      final response = await api.get(endpoint, token: token);
      final decoded = jsonDecode(response.body);
      return AdminResponse.fromJson(decoded);
    } catch (err) {
      log(err.toString());
      rethrow;
    }
  }

  // Get User by ID
  Future<AdminResponse> getUserById(String userId) async {
    try {
      final token = await _getToken();
      final response = await api.get(
        '/api/admin/users/$userId',
        token: token,
      );

      final decoded = jsonDecode(response.body);
      return AdminResponse.fromJson(decoded);
    } catch (err) {
      log(err.toString());
      rethrow;
    }
  }

  // Update User
  Future<AdminResponse> updateUser(String userId, UpdateUserData data) async {
    try {
      final token = await _getToken();
      final response = await api.put(
        '/api/admin/users/$userId',
        data.toJson(),
        token: token,
      );

      final decoded = jsonDecode(response.body);
      return AdminResponse.fromJson(decoded);
    } catch (err) {
      log(err.toString());
      rethrow;
    }
  }

  // Delete User
  Future<AdminResponse> deleteUser(String userId) async {
    try {
      final token = await _getToken();
      final response = await api.delete(
        '/api/admin/users/$userId',
        token: token,
      );

      final decoded = jsonDecode(response.body);
      return AdminResponse.fromJson(decoded);
    } catch (err) {
      log(err.toString());
      rethrow;
    }
  }
}
