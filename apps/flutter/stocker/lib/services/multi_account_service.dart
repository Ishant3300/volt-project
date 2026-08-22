import 'dart:convert';
import 'dart:developer';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Represents a saved account session.
class SavedAccount {
  final String username;
  final String role;
  final String token;
  final String? name;
  final bool investor;

  SavedAccount({
    required this.username,
    required this.role,
    required this.token,
    this.name,
    this.investor = false,
  });

  Map<String, dynamic> toJson() => {
        'username': username,
        'role': role,
        'token': token,
        'investor': investor,
        if (name != null) 'name': name,
      };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
        username: json['username'] ?? '',
        role: json['role'] ?? '',
        token: json['token'] ?? '',
        name: json['name'],
        investor: json['investor'] == true,
      );

  /// Unique key: username + role + mode (same user can have investor and normal sessions)
  String get key =>
      investor ? '${username}_${role}_investor' : '${username}_$role';
}

/// Manages multiple saved account sessions in secure storage.
class MultiAccountService {
  static const _accountsKey = 'saved_accounts';
  static const _activeKey = 'active_account_key';
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Get all saved accounts.
  Future<List<SavedAccount>> getSavedAccounts() async {
    try {
      final raw = await _storage.read(key: _accountsKey);
      if (raw == null || raw.isEmpty) return [];
      final List decoded = jsonDecode(raw);
      return decoded.map((e) => SavedAccount.fromJson(e)).toList();
    } catch (e) {
      log('⚠️ MultiAccountService: Error reading accounts: $e');
      // If storage is corrupted, clear it
      try {
        await _storage.delete(key: _accountsKey);
      } catch (_) {}
      return [];
    }
  }

  /// Save or update an account in the list.
  Future<void> saveAccount(SavedAccount account) async {
    final accounts = await getSavedAccounts();
    // Remove existing entry with same key
    accounts.removeWhere((a) => a.key == account.key);
    // Add at the front (most recent)
    accounts.insert(0, account);
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    log('💾 MultiAccountService: Saved account ${account.username} (${account.role})');
  }

  /// Remove an account from saved list.
  Future<void> removeAccount(String key) async {
    final accounts = await getSavedAccounts();
    accounts.removeWhere((a) => a.key == key);
    await _storage.write(
      key: _accountsKey,
      value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
    log('🗑️ MultiAccountService: Removed account $key');
  }

  /// Set the active account key.
  Future<void> setActiveKey(String key) async {
    await _storage.write(key: _activeKey, value: key);
  }

  /// Get the active account key.
  Future<String?> getActiveKey() async {
    return await _storage.read(key: _activeKey);
  }

  /// Update the token for an existing saved account.
  Future<void> updateToken(String key, String newToken) async {
    final accounts = await getSavedAccounts();
    final idx = accounts.indexWhere((a) => a.key == key);
    if (idx != -1) {
      final old = accounts[idx];
      accounts[idx] = SavedAccount(
        username: old.username,
        role: old.role,
        token: newToken,
        name: old.name,
        investor: old.investor,
      );
      await _storage.write(
        key: _accountsKey,
        value: jsonEncode(accounts.map((a) => a.toJson()).toList()),
      );
    }
  }

  /// Clear all saved accounts (full reset).
  Future<void> clearAll() async {
    await _storage.delete(key: _accountsKey);
    await _storage.delete(key: _activeKey);
  }
}
