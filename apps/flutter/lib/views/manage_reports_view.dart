import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../providers/user_profile_provider.dart';
import '../services/admin_service.dart';
import '../services/master_service.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class ManageReportsView extends StatefulWidget {
  /// If provided, opens directly for this master (used from Master's sub-master view)
  final Master? targetMaster;

  const ManageReportsView({super.key, this.targetMaster});

  @override
  State<ManageReportsView> createState() => _ManageReportsViewState();
}

class _ManageReportsViewState extends State<ManageReportsView> {
  // 0 = Masters, 1 = Users
  int _selectedTab = 0;

  // Masters state
  List<Master> _masters = [];
  Master? _selectedMaster;
  bool _isLoadingMasters = true;

  // Users state
  List<User> _users = [];
  User? _selectedUser;
  bool _isLoadingUsers = true;

  // Shared state
  bool _isUpdating = false;
  bool _hasChanges = false;
  Map<String, bool> _permissions = {};
  Map<String, bool> _original = {};

  /// The ceiling permissions — the logged-in user's own report permissions.
  Map<String, bool> _parentPermissions = {};

  static const _masterPermLabels = {
    'account_summary': 'Account Summary',
    'pnl_summary': 'P&L Summary',
    'client_summary': 'Client Summary',
    'settlement_report': 'Settlement Report',
    'generate_pdf': 'Generate PDF',
    'weekly_admin': 'Weekly Admin',
    'intraday_history': 'Intraday History',
    'userwise_open_position': 'Userwise Position',
    'script_quantity': 'Script Quantity',
    'deleted_trade': 'Deleted Trade',
    'trade_account': 'Trade Account',
  };

  // Users only see these 7 reports
  static const _userPermLabels = {
    'account_summary': 'Account Summary',
    'generate_pdf': 'Generate PDF',
    'intraday_history': 'Intraday History',
    'userwise_open_position': 'Userwise Position',
    'script_quantity': 'Script Quantity',
    'deleted_trade': 'Deleted Trade',
    'trade_account': 'Rejection Log',
  };

  @override
  void initState() {
    super.initState();
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    _parentPermissions = profile.reportPermissions;

    if (widget.targetMaster != null) {
      // Opened for a specific master (from Admin flow)
      _isLoadingMasters = false;
      _isLoadingUsers = false;
      _masters = [widget.targetMaster!];
      _selectMaster(widget.targetMaster!);
    } else if (profile.isAdmin) {
      // Admin: manages Masters/SubMasters only
      _selectedTab = 0;
      _isLoadingUsers = false;
      _fetchMasters();
    } else {
      // Master/SubMaster: manages only their direct Users
      _selectedTab = 1;
      _isLoadingMasters = false;
      _fetchUsers();
    }
  }

  Future<void> _fetchMasters() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // Admin fetches ALL masters (including sub-masters) as a flat list
      final res = await AdminService(api).getAllMasters(page: 1, limit: 500, includeSubmasters: true);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final List list = data['data']['masters'] ?? [];
          setState(() {
            _masters = list.map((j) { try { return Master.fromJson(j); } catch (_) { return null; } }).whereType<Master>().toList();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMasters = false);
  }

  Future<void> _fetchUsers() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      // Master/SubMaster fetches only their direct users
      final res = await MasterService(api).getAllUsers(page: 1, limit: 500);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final nested = data['data'];
          final List list = nested is Map ? (nested['users'] ?? []) : (nested ?? []);
          setState(() {
            _users = list.map((j) { try { return User.fromJson(j as Map<String, dynamic>); } catch (_) { return null; } }).whereType<User>().toList();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingUsers = false);
  }

  void _selectMaster(Master master) {
    final p = master.permissions;
    final perms = <String, bool>{
      'account_summary': p?.accountSummary ?? true,
      'pnl_summary': p?.pnlSummary ?? true,
      'client_summary': p?.clientSummary ?? true,
      'settlement_report': p?.settlementReport ?? true,
      'generate_pdf': p?.generatePdf ?? true,
      'weekly_admin': p?.weeklyAdmin ?? true,
      'intraday_history': p?.intradayHistory ?? true,
      'userwise_open_position': p?.userwiseOpenPosition ?? true,
      'script_quantity': p?.scriptQuantity ?? true,
      'deleted_trade': p?.deletedTrade ?? true,
      'trade_account': p?.tradeAccount ?? true,
    };
    setState(() {
      _selectedMaster = master;
      _selectedUser = null;
      _permissions = perms;
      _original = Map.from(perms);
      _hasChanges = false;
    });
  }

  void _selectUser(User user) {
    final rp = user.reportPermissions;
    final perms = <String, bool>{
      'account_summary': rp?['account_summary'] ?? true,
      'generate_pdf': rp?['generate_pdf'] ?? true,
      'intraday_history': rp?['intraday_history'] ?? true,
      'userwise_open_position': rp?['userwise_open_position'] ?? true,
      'script_quantity': rp?['script_quantity'] ?? true,
      'deleted_trade': rp?['deleted_trade'] ?? true,
      'trade_account': rp?['trade_account'] ?? true,
    };
    setState(() {
      _selectedUser = user;
      _selectedMaster = null;
      _permissions = perms;
      _original = Map.from(perms);
      _hasChanges = false;
    });
  }

  Future<void> _update() async {
    if (!_hasChanges) return;
    if (_selectedTab == 0 && _selectedMaster == null) return;
    if (_selectedTab == 1 && _selectedUser == null) return;

    setState(() => _isUpdating = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final profile = Provider.of<UserProfileProvider>(context, listen: false);

      if (_selectedTab == 0 && _selectedMaster != null) {
        // Updating a Master's permissions
        final cp = _selectedMaster!.permissions;
        final updated = MasterPermissions(
          accountSummary: _permissions['account_summary']!,
          pnlSummary: _permissions['pnl_summary']!,
          clientSummary: _permissions['client_summary']!,
          settlementReport: _permissions['settlement_report']!,
          generatePdf: _permissions['generate_pdf']!,
          weeklyAdmin: _permissions['weekly_admin']!,
          intradayHistory: _permissions['intraday_history']!,
          userwiseOpenPosition: _permissions['userwise_open_position']!,
          scriptQuantity: _permissions['script_quantity']!,
          deletedTrade: _permissions['deleted_trade']!,
          tradeAccount: _permissions['trade_account']!,
          closeOnly: cp?.closeOnly ?? false,
          bet: cp?.bet ?? false,
          marginSquare: cp?.marginSquare ?? false,
          freshStoploss: cp?.freshStoploss ?? false,
        );

        late final dynamic res;
        if (profile.isAdmin) {
          res = await AdminService(api).updateMasterPermissions(
            masterId: _selectedMaster!.id,
            permissions: updated,
          );
        } else {
          res = await MasterService(api).updateChildMasterPermissions(
            masterId: _selectedMaster!.id,
            permissions: updated.toJson().cast<String, bool>(),
          );
        }

        if (res.statusCode == 200) {
          setState(() { _hasChanges = false; _original = Map.from(_permissions); });
          _snack('Permissions updated');
        } else {
          final body = jsonDecode(res.body);
          _snack(body['message'] ?? 'Failed to update', isError: true);
        }
      } else if (_selectedTab == 1 && _selectedUser != null) {
        // Updating a User's report permissions
        final token = await SecureStorageService().getToken();
        final res = await api.put(
          '/master/users/${_selectedUser!.id}/report-permissions',
          {'report_permissions': _permissions},
          token: token,
        );

        if (res.statusCode == 200) {
          setState(() { _hasChanges = false; _original = Map.from(_permissions); });
          _snack('User permissions updated');
        } else {
          final body = jsonDecode(res.body);
          _snack(body['message'] ?? 'Failed to update', isError: true);
        }
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = _isLoadingMasters || _isLoadingUsers;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Manage Reports', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                ],
              ),
            ),

            // Tab selector — no longer needed. Admin sees Masters, Master sees Users.

            const SizedBox(height: 12),

            // Selector (Master or User depending on role)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _card(
                child: GestureDetector(
                  onTap: () => _selectedTab == 0 ? _showMasterSheet() : _showUserSheet(),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: kBrandPrimary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _selectedTab == 0 ? Icons.person_outline : Icons.person,
                          size: 18, color: kBrandPrimary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedTab == 0
                                  ? (_selectedMaster?.name ?? 'Select Master')
                                  : (_selectedUser?.name ?? 'Select User'),
                              style: TextStyle(
                                color: (_selectedTab == 0 ? _selectedMaster : _selectedUser) != null
                                    ? Colors.black : const Color(0xFF94A3B8),
                                fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold,
                              ),
                            ),
                            if (_selectedTab == 0 && _selectedMaster != null)
                              Text(_selectedMaster!.username, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                            if (_selectedTab == 1 && _selectedUser != null)
                              Text(_selectedUser!.username, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: kIconSizeMedium, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Permissions list
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
                  : (_selectedTab == 0 && _masters.isEmpty) || (_selectedTab == 1 && _users.isEmpty)
                      ? Center(
                          child: Text(
                            _selectedTab == 0 ? 'No masters to manage' : 'No users to manage',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: kFontFamily),
                          ),
                        )
                      : ((_selectedTab == 0 && _selectedMaster == null) || (_selectedTab == 1 && _selectedUser == null))
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 64, height: 64,
                                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
                                    child: const Icon(Icons.admin_panel_settings_outlined, size: 28, color: Color(0xFFCBD5E1)),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _selectedTab == 0 ? 'Select a master to manage permissions' : 'Select a user to manage permissions',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: kFontFamily),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        const Text('PERMISSIONS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
                        const SizedBox(height: 12),
                        _card(
                          child: Column(
                            children: (_selectedTab == 0 ? _masterPermLabels : _userPermLabels).entries.map((e) {
                              final labels = _selectedTab == 0 ? _masterPermLabels : _userPermLabels;
                              final isLast = e.key == labels.keys.last;
                              final parentHas = _parentPermissions[e.key] ?? true;
                              return Column(
                                children: [
                                  _toggleRow(
                                    e.value,
                                    _permissions[e.key] ?? false,
                                    enabled: parentHas,
                                    (v) {
                                      setState(() { _permissions[e.key] = v; _hasChanges = true; });
                                    },
                                  ),
                                  if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _isUpdating || !_hasChanges ? null : _update,
                          child: Container(
                            width: double.infinity, height: 52,
                            decoration: BoxDecoration(
                              color: _isUpdating || !_hasChanges ? const Color(0xFF94A3B8) : kBrandPrimary,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: _isUpdating
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('UPDATE PERMISSIONS', style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMasterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Select Master', style: TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
            const SizedBox(height: 16),
            if (_isLoadingMasters)
              const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _masters.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (_, i) {
                    final m = _masters[i];
                    final sel = _selectedMaster?.id == m.id;
                    return GestureDetector(
                      onTap: () { _selectMaster(m); Navigator.pop(context); },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                        color: sel ? kBrandPrimary.withValues(alpha: 0.05) : Colors.transparent,
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: kBrandPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                              child: Center(child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?', style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightBold))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                                  Text(m.username, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                                ],
                              ),
                            ),
                            if (sel) const Icon(Icons.check_circle, size: kIconSizeMedium, color: kBrandPrimary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showUserSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Select User', style: TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
            const SizedBox(height: 16),
            if (_isLoadingUsers)
              const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (_, i) {
                    final u = _users[i];
                    final sel = _selectedUser?.id == u.id;
                    return GestureDetector(
                      onTap: () { _selectUser(u); Navigator.pop(context); },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                        color: sel ? kBrandPrimary.withValues(alpha: 0.05) : Colors.transparent,
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: kBrandPrimary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                              child: Center(child: Text(u.name.isNotEmpty ? u.name[0].toUpperCase() : '?', style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightBold))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.name, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                                  Text(u.username, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                                ],
                              ),
                            ),
                            if (sel) const Icon(Icons.check_circle, size: kIconSizeMedium, color: kBrandPrimary),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: child,
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged, {bool enabled = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  color: enabled ? Colors.black : const Color(0xFF94A3B8),
                  fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium,
                )),
                if (!enabled)
                  const Text('Disabled by parent', style: TextStyle(
                    color: Color(0xFFEF4444), fontSize: 11, fontFamily: kFontFamily,
                  )),
              ],
            ),
          ),
          GestureDetector(
            onTap: enabled ? () => onChanged(!value) : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 26, padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: !enabled
                    ? const Color(0xFFE2E8F0)
                    : value
                        ? kBrandPrimary
                        : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value && enabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(width: 22, height: 22, decoration: BoxDecoration(
                  color: enabled ? Colors.white : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
