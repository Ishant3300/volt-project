import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/super_admin_admin.dart';
import '../services/admin_service.dart';
import '../services/api_service.dart';
import '../services/super_admin_service.dart';
import '../utils/contants.dart';

/// Super Admin only. Permissions + watch-only + master visibility + enable/
/// disable + delete for one regular Admin. Each section saves independently
/// (three separate PUT calls, matching the backend's three endpoints) —
/// not one combined save, same reasoning as the web portal's version.
class ManageAdminDetailView extends StatefulWidget {
  final SuperAdminAdmin admin;

  const ManageAdminDetailView({super.key, required this.admin});

  @override
  State<ManageAdminDetailView> createState() => _ManageAdminDetailViewState();
}

class _ManageAdminDetailViewState extends State<ManageAdminDetailView> {
  late SuperAdminAdmin _admin;
  late Set<String> _permissions;
  late bool _watchOnly;
  bool _isSavingPermissions = false;

  List<Master> _masters = [];
  bool _isLoadingMasters = true;
  late Set<String> _hiddenMasterIds;
  bool _isSavingVisibility = false;

  bool _isTogglingStatus = false;
  bool _isDeleting = false;
  bool _confirmDelete = false;

  bool _changedThisSession = false;

  @override
  void initState() {
    super.initState();
    _admin = widget.admin;
    _permissions = _admin.permissions.toSet();
    _watchOnly = _admin.watchOnly;
    _hiddenMasterIds = _admin.hiddenMasterIds.toSet();
    _fetchMasters();
  }

  Future<void> _fetchMasters() async {
    setState(() => _isLoadingMasters = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await AdminService(api).getAllMasters(
        limit: 1000,
        includeSubmasters: true,
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        final List<dynamic> mastersJson = body['data']['masters'] ?? [];
        final parsed = <Master>[];
        for (final m in mastersJson) {
          try {
            parsed.add(Master.fromJson(m));
          } catch (_) {}
        }
        setState(() => _masters = parsed);
      }
    } catch (_) {
      // Non-fatal — the section just shows empty; retry via pull-to-refresh isn't wired here, keep it simple.
    } finally {
      if (mounted) setState(() => _isLoadingMasters = false);
    }
  }

  /// Top-level masters first, each followed by their own sub-masters.
  List<MapEntry<Master, bool>> get _orderedMasters {
    final topLevel = _masters.where((m) => m.masterId == null).toList();
    final byParent = <String, List<Master>>{};
    for (final m in _masters) {
      if (m.masterId == null) continue;
      byParent.putIfAbsent(m.masterId!, () => []).add(m);
    }
    final rows = <MapEntry<Master, bool>>[];
    for (final top in topLevel) {
      rows.add(MapEntry(top, false));
      for (final child in byParent[top.id] ?? []) {
        rows.add(MapEntry(child, true));
      }
    }
    return rows;
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
    ));
  }

  Future<void> _savePermissions() async {
    setState(() => _isSavingPermissions = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await SuperAdminService(api).updatePermissions(
        id: _admin.id,
        permissions: _permissions.toList(),
        watchOnly: _watchOnly,
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        _changedThisSession = true;
        _snack('Permissions updated');
      } else {
        _snack(body['message'] ?? 'Failed to update permissions', isError: true);
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingPermissions = false);
    }
  }

  Future<void> _saveVisibility() async {
    setState(() => _isSavingVisibility = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await SuperAdminService(api).updateMasterVisibility(
        id: _admin.id,
        hiddenMasterIds: _hiddenMasterIds.toList(),
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        _changedThisSession = true;
        _snack('Master visibility updated');
      } else {
        _snack(body['message'] ?? 'Failed to update master visibility', isError: true);
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingVisibility = false);
    }
  }

  Future<void> _toggleStatus() async {
    setState(() => _isTogglingStatus = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await SuperAdminService(api).updateStatus(
        id: _admin.id,
        activeStatus: !_admin.activeStatus,
      );
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        setState(() {
          _admin = SuperAdminAdmin.fromJson(body['data']);
        });
        _changedThisSession = true;
        _snack(_admin.activeStatus ? 'Admin enabled' : 'Admin disabled');
      } else {
        _snack(body['message'] ?? 'Failed to update status', isError: true);
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isTogglingStatus = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await SuperAdminService(api).deleteAdmin(_admin.id);
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _isDeleting = false);
        _snack(body['message'] ?? 'Failed to delete admin', isError: true);
      }
    } catch (e) {
      setState(() => _isDeleting = false);
      _snack('Error: $e', isError: true);
    }
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold));
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                if (hint != null)
                  Text(hint, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: kFontFamily)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? kBrandPrimary : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context, _changedThisSession),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                        ),
                        child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(_admin.username, style: const TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Status
                    _card(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _admin.activeStatus ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _admin.activeStatus ? 'Active' : 'Disabled',
                                  style: TextStyle(color: _admin.activeStatus ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontSize: 12, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: _isTogglingStatus ? null : _toggleStatus,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: _admin.activeStatus ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isTogglingStatus
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(
                                      _admin.activeStatus ? 'Disable account' : 'Enable account',
                                      style: TextStyle(color: _admin.activeStatus ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontSize: 13, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Permissions
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Permissions'),
                          const SizedBox(height: 4),
                          _toggleRow(
                            'Watch-only mode',
                            _watchOnly,
                            (v) => setState(() => _watchOnly = v),
                            hint: 'Blocks every mutating action, regardless of permissions below',
                          ),
                          const Divider(height: 20, color: Color(0xFFF1F5F9)),
                          ...kAdminPermissionLabels.entries.map((entry) => _toggleRow(
                                entry.value,
                                _permissions.contains(entry.key),
                                (v) => setState(() {
                                  if (v) {
                                    _permissions.add(entry.key);
                                  } else {
                                    _permissions.remove(entry.key);
                                  }
                                }),
                              )),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              GestureDetector(
                                onTap: () => setState(() => _permissions = kAdminPermissionLabels.keys.toSet()),
                                child: const Text('Grant all', style: TextStyle(color: Color(0xFF64748B), fontSize: 13, fontFamily: kFontFamily, decoration: TextDecoration.underline)),
                              ),
                              ElevatedButton(
                                onPressed: _isSavingPermissions ? null : _savePermissions,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kBrandPrimary,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                child: _isSavingPermissions
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Save permissions', style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Master visibility
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle('Master visibility'),
                          const SizedBox(height: 4),
                          const Text(
                            'Every master is visible by default. Turning one off hides that master, its entire sub-master tree, their users, and all trade/report/ledger data belonging to any of them — everywhere, for this admin only.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontFamily: kFontFamily),
                          ),
                          const SizedBox(height: 12),
                          if (_isLoadingMasters)
                            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                          else if (_masters.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('No masters on the platform yet.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: kFontFamily)),
                            )
                          else
                            ..._orderedMasters.map((entry) {
                              final master = entry.key;
                              final indent = entry.value;
                              final visible = !_hiddenMasterIds.contains(master.id);
                              return Padding(
                                padding: EdgeInsets.only(left: indent ? 20 : 0, top: 6, bottom: 6),
                                child: _toggleRow(
                                  '${indent ? '↳ ' : ''}${master.name} (@${master.username})',
                                  visible,
                                  (v) => setState(() {
                                    if (v) {
                                      _hiddenMasterIds.remove(master.id);
                                    } else {
                                      _hiddenMasterIds.add(master.id);
                                    }
                                  }),
                                ),
                              );
                            }),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: (_isSavingVisibility || _isLoadingMasters) ? null : _saveVisibility,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kBrandPrimary,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: _isSavingVisibility
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Text('Save master visibility', style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Delete
                    _card(
                      child: _confirmDelete
                          ? Row(
                              children: [
                                const Expanded(
                                  child: Text('Delete this admin permanently?', style: TextStyle(color: Color(0xFFEF4444), fontSize: kFontSizeBody, fontFamily: kFontFamily)),
                                ),
                                TextButton(
                                  onPressed: () => setState(() => _confirmDelete = false),
                                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontFamily: kFontFamily)),
                                ),
                                ElevatedButton(
                                  onPressed: _isDeleting ? null : _delete,
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                                  child: _isDeleting
                                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Text('Confirm delete', style: TextStyle(color: Colors.white, fontFamily: kFontFamily)),
                                ),
                              ],
                            )
                          : GestureDetector(
                              onTap: () => setState(() => _confirmDelete = true),
                              child: const Text('Delete this admin', style: TextStyle(color: Color(0xFFEF4444), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                            ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
    ); // end Scaffold
  }
}

