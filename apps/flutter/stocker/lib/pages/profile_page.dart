import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:developer';
import '../views/account_detail_view.dart';
import '../views/user_management_view.dart';
import '../views/login_history_view.dart';
import '../views/reports_view.dart';
import '../views/settings_view.dart';
import '../views/admin_settings_view.dart';
import '../services/sercure_storage_service.dart';
import '../services/auth_service.dart';
import '../services/multi_account_service.dart';
import '../providers/user_profile_provider.dart';
import '../providers/trade_metrics_provider.dart';
import '../pages/login_page.dart';
import '../services/firebase_service.dart';
import '../pages/account_switcher_sheet.dart';
import '../widgets/announcement_banner.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final SecureStorageService _storage = SecureStorageService();
  final MultiAccountService _multiAccount = MultiAccountService();
  bool _isAdmin = false;
  bool _isMaster = false;
  bool _isLoggingOut = false;
  int _savedAccountCount = 0;

  @override
  void initState() {
    super.initState();
    _checkAdminStatus();
    _loadAccountCount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAdminStatus();
    _loadAccountCount();
  }

  Future<void> _loadAccountCount() async {
    final accounts = await _multiAccount.getSavedAccounts();
    if (mounted) {
      setState(() => _savedAccountCount = accounts.length);
    }
  }

  Future<void> _checkAdminStatus() async {
    final role = await _storage.getRole();
    log('🔍 Profile page - Retrieved role: "$role"');

    final isAdmin = role == 'ADMIN';
    final isMaster = role == 'MASTER';

    log('📊 Profile page - Comparison: role=="ADMIN" = $isAdmin, role=="MASTER" = $isMaster');

    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _isMaster = isMaster;
      });
      log('✅ Profile page - State updated: _isAdmin: $_isAdmin, _isMaster: $_isMaster');
    }
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

      // Unregister FCM token before logout
      await FirebaseService().unregisterToken();

      // Call logout API
      await authService.logout(role: role ?? 'USER');

      // Remove this account from saved accounts
      final activeKey = await _multiAccount.getActiveKey();
      if (activeKey != null) {
        await _multiAccount.removeAccount(activeKey);
      }

      // Clear profile data
      profileProvider.clearProfile();

      // Clear trade metrics (stale data from previous session)
      final metricsProvider =
          Provider.of<TradeMetricsProvider>(context, listen: false);
      metricsProvider.clear();

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
    log('🏗️ Building ProfilePage - _isAdmin: $_isAdmin, _isMaster: $_isMaster');

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 20,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.settings,
                          size: 20, color: Color(0xFF334155)),
                    ),
                  ],
                ),
              ),

              // Announcement marquee
              const AnnouncementBanner(),

              const SizedBox(height: 4),

              // Account switcher card
              Consumer<UserProfileProvider>(
                builder: (context, profileProvider, _) {
                  final name = profileProvider.user?.name ??
                      profileProvider.master?.name ??
                      'Account';
                  final username = profileProvider.user?.username ??
                      profileProvider.master?.username ??
                      '';
                  final role = profileProvider.role ?? '';

                  Color roleColor;
                  switch (role) {
                    case 'ADMIN':
                      roleColor = const Color(0xFF8B5CF6);
                      break;
                    case 'MASTER':
                      roleColor = const Color(0xFF3F45C7);
                      break;
                    default:
                      roleColor = const Color(0xFF10B981);
                  }

                  return GestureDetector(
                    onTap: () => showAccountSwitcher(context),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 2),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0), width: 1),
                      ),
                      child: Row(
                        children: [
                          // Avatar
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: roleColor.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty
                                    ? name.substring(0, 1).toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  color: roleColor,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 14,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Text(
                                      username,
                                      style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 11,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: roleColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        role,
                                        style: TextStyle(
                                          color: roleColor,
                                          fontSize: 9,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (_savedAccountCount > 1) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$_savedAccountCount',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 10,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          const Icon(Icons.unfold_more,
                              size: 18, color: Color(0xFF94A3B8)),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 4),

              // Menu items
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    if (_isAdmin) ...[
                      _buildMenuItem(
                          context, Icons.admin_panel_settings, 'Admin Setting'),
                      _buildDivider(),
                    ] else
                      Builder(builder: (context) {
                        return const SizedBox.shrink();
                      }),
                    _buildMenuItem(context, Icons.person, 'Account Detail'),
                    _buildDivider(),
                    if (_isAdmin || _isMaster) ...[
                      _buildMenuItem(
                          context, Icons.people, 'Master And User Management'),
                      _buildDivider(),
                    ] else
                      Builder(builder: (context) {
                        return const SizedBox.shrink();
                      }),
                    _buildMenuItem(context, Icons.insert_chart, 'Reports'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.settings, 'Settings'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.person_add, 'Invite Friends'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.history, 'Login History'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.swap_horiz, 'Switch Account'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.logout, 'Logout',
                        isRed: true),
                  ],
                ),
              ),

              const SizedBox(height: 6),

              // Delete account
              const Center(
                child: Text(
                  'Delete Account',
                  style: TextStyle(
                    color: Color(0xFF334155),
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 12),
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
              } else if (title == 'Switch Account') {
                showAccountSwitcher(context);
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        color: Colors.transparent, // allow full width tap
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isRed
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 14,
                      color: isRed
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF1E3A8A),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: isRed
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF1E293B),
                    fontSize: 13,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_isLoggingOut && title == 'Logout') ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFEF4444),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Icon(
              Icons.chevron_right,
              size: 20,
              color: Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
        height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16);
  }
}
