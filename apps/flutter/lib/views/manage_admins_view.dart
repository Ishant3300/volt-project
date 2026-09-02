import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/super_admin_admin.dart';
import '../services/api_service.dart';
import '../services/super_admin_service.dart';
import '../utils/contants.dart';
import 'create_admin_view.dart';
import 'manage_admin_detail_view.dart';

/// Super Admin only. Create/list/restrict other Admins.
class ManageAdminsView extends StatefulWidget {
  const ManageAdminsView({super.key});

  @override
  State<ManageAdminsView> createState() => _ManageAdminsViewState();
}

class _ManageAdminsViewState extends State<ManageAdminsView> {
  List<SuperAdminAdmin> _admins = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchAdmins();
  }

  Future<void> _fetchAdmins() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await SuperAdminService(api).getAllAdmins();
      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['success'] == true) {
        final List<dynamic> raw = body['data'] ?? [];
        final parsed = <SuperAdminAdmin>[];
        for (final a in raw) {
          try {
            parsed.add(SuperAdminAdmin.fromJson(a));
          } catch (e) {
            log('❌ Error parsing admin: $e');
          }
        }
        setState(() {
          _admins = parsed;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = body['message'] ?? 'Failed to load admins';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
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
                    onTap: () => Navigator.pop(context),
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
                  const Expanded(
                    child: Text('Manage Admins', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const CreateAdminView()),
                      );
                      if (result == true) _fetchAdmins();
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: kBrandPrimary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: kIconSizeMedium),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMessage != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontFamily: kFontFamily)),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _fetchAdmins, child: const Text('Retry')),
                            ],
                          ),
                        )
                      : _admins.isEmpty
                          ? const Center(
                              child: Text('No admin accounts yet.', style: TextStyle(color: Color(0xFF8E8E93), fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily)),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _admins.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 4),
                              itemBuilder: (context, index) {
                                final admin = _admins[index];
                                return GestureDetector(
                                  onTap: admin.isSuperAdmin
                                      ? null
                                      : () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => ManageAdminDetailView(admin: admin)),
                                          );
                                          if (result == true) _fetchAdmins();
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: ShapeDecoration(
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(admin.username, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                                              const SizedBox(height: 4),
                                              Row(
                                                children: [
                                                  _badge(
                                                    admin.isSuperAdmin ? 'Super Admin' : 'Admin',
                                                    admin.isSuperAdmin ? const Color(0xFFF59E0B) : const Color(0xFF94A3B8),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  _badge(
                                                    admin.activeStatus ? 'Active' : 'Disabled',
                                                    admin.activeStatus ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                                  ),
                                                  if (admin.watchOnly) ...[
                                                    const SizedBox(width: 6),
                                                    _badge('Watch-only', const Color(0xFFF59E0B)),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                admin.isSuperAdmin
                                                    ? 'All permissions (unrestricted)'
                                                    : '${admin.permissions.length}/9 permissions · ${admin.hiddenMasterIds.isEmpty ? 'all masters visible' : '${admin.hiddenMasterIds.length} master(s) hidden'}',
                                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: kFontFamily),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!admin.isSuperAdmin) const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
    );
  }
}
