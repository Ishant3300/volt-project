import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../views/account_detail_view.dart';
import '../views/user_management_view.dart';
import '../views/login_history_view.dart';
import '../views/reports_view.dart';
import '../views/settings_view.dart';
import '../views/admin_settings_view.dart';
import '../services/sercure_storage_service.dart';
import '../services/auth_service.dart';
import '../providers/user_profile_provider.dart';
import '../providers/trade_metrics_provider.dart';
import '../pages/login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final SecureStorageService _storage = SecureStorageService();
  bool _isAdmin = false;
  bool _isMaster = false;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final role = await _storage.getRole();
    setState(() {
      _isAdmin = role == 'ADMIN';
      _isMaster = role == 'MASTER';
    });
  }

  Future<void> _handleLogout() async {
    if (_isLoggingOut) return;

    setState(() {
      _isLoggingOut = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      final role = await _storage.getRole();

      // Call logout API
      await authService.logout(role: role ?? 'USER');

      // Clear profile data
      profileProvider.clearProfile();

      if (!mounted) return;

      // Navigate to login page
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
        (route) => false,
      );

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Profile',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Icon(Icons.settings, size: 24, color: Colors.black),
                  ],
                ),
              ),

              // Security notice
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(4),
                decoration: ShapeDecoration(
                  color: const Color(0x19FF3B30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.security,
                        color: const Color(0xFFFF3B30), size: 18),
                    SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        'All profile running in this app is secure. The new',
                        style: TextStyle(
                          color: const Color(0xFFFF3B30),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Balance and Credit summary
              Consumer<TradeMetricsProvider>(
                builder: (context, metricsProvider, child) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BALANCE',
                                style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 12,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                metricsProvider.balance.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: const Color(0xFFE5E5EA),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CREDIT',
                                style: TextStyle(
                                  color: Color(0xFF8E8E93),
                                  fontSize: 12,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                metricsProvider.credit.toStringAsFixed(2),
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 20,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),

              SizedBox(height: 16),

              // Menu items
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    if (_isAdmin) ...[
                      _buildMenuItem(
                          context, Icons.admin_panel_settings, 'Admin Setting'),
                      _buildDivider(),
                    ],
                    _buildMenuItem(
                        context, Icons.account_circle, 'Account Detail'),
                    _buildDivider(),
                    if (_isAdmin || _isMaster) ...[
                      _buildMenuItem(
                          context, Icons.people, 'Master And User Management'),
                      _buildDivider(),
                    ],
                    _buildMenuItem(context, Icons.assessment, 'Reports'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.settings, 'Settings'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.person_add, 'Invite Friends'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.history, 'Login History'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.logout, 'Logout',
                        isRed: true),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Delete account
              Text(
                'Delete Account',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title,
      {bool isRed = false}) {
    return GestureDetector(
      onTap: _isLoggingOut
          ? null
          : () {
              if (title == 'Logout') {
                _handleLogout();
              } else if (title == 'Admin Setting') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminSettingsView()),
                );
              } else if (title == 'Account Detail') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AccountDetailView()),
                );
              } else if (title == 'Master And User Management') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const UserManagementView()),
                );
              } else if (title == 'Login History') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const LoginHistoryView()),
                );
              } else if (title == 'Reports') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReportsView()),
                );
              } else if (title == 'Settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsView()),
                );
              }
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 24,
                  color: isRed ? const Color(0xFFFF3B30) : Colors.black,
                ),
                SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: isRed ? const Color(0xFFFF3B30) : Colors.black,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                if (_isLoggingOut && title == 'Logout') ...[
                  SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        const Color(0xFFFF3B30),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Icon(
              Icons.chevron_right,
              size: 24,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
        height: 1, color: const Color(0xFFC7C7CC), indent: 16, endIndent: 16);
  }
}
