/// Mirrors the record shape returned by every /api/super-admin/admins
/// endpoint (apex-project/apps/backend/src/controllers/superAdminController.js).
class SuperAdminAdmin {
  final String id;
  final String username;
  final bool isSuperAdmin;
  final bool watchOnly;
  final List<String> permissions;
  final List<String> hiddenMasterIds;
  final bool activeStatus;

  SuperAdminAdmin({
    required this.id,
    required this.username,
    required this.isSuperAdmin,
    required this.watchOnly,
    required this.permissions,
    required this.hiddenMasterIds,
    required this.activeStatus,
  });

  factory SuperAdminAdmin.fromJson(Map<String, dynamic> json) {
    return SuperAdminAdmin(
      id: (json['id'] ?? json['_id']).toString(),
      username: json['username'] as String? ?? '',
      isSuperAdmin: json['is_super_admin'] as bool? ?? false,
      watchOnly: json['watch_only'] as bool? ?? false,
      permissions: (json['permissions'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      hiddenMasterIds: (json['hidden_master_ids'] as List? ?? [])
          .map((e) => e is Map ? (e['_id'] ?? e['id']).toString() : e.toString())
          .toList(),
      activeStatus: json['active_status'] as bool? ?? true,
    );
  }
}

/// Fixed 9 permission keys a Super Admin can grant a regular Admin —
/// mirrors apps/backend/src/constants/adminPermissions.js exactly.
const Map<String, String> kAdminPermissionLabels = {
  'TRADE_CUSTOM': 'Custom-price orders',
  'TRADE_DELETE': 'Delete trades',
  'WALLET_MANAGE': 'Wallet assign/withdraw',
  'BROKERAGE_MANAGE': 'Brokerage settings',
  'INSTRUMENT_MANAGE': 'Instrument management',
  'SETTLEMENT_TRIGGER': 'Trigger settlement',
  'FRESH_STOPLOSS_MANAGE': 'Fresh stop-loss limits',
  'REPORTS_ACCESS': 'Reports access',
  'MASTER_EDIT_ANY': 'Edit any master',
};
