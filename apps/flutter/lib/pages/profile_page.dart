import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'dart:developer';
import '../views/account_detail_view.dart';
import '../views/user_management_view.dart';
import '../views/login_history_view.dart';
import '../views/reports_view.dart';
import '../views/manage_reports_view.dart';
import '../views/settings_view.dart';
import '../views/admin_settings_view.dart';
import '../views/manage_admins_view.dart';
import '../services/sercure_storage_service.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../services/multi_account_service.dart';
import '../providers/user_profile_provider.dart';
import '../providers/trade_metrics_provider.dart';
import '../providers/investor_mode_provider.dart';
import '../widgets/brand_menu_row.dart';
import '../pages/login_page.dart';
import '../services/firebase_service.dart';
import '../pages/account_switcher_sheet.dart';
import '../widgets/announcement_banner.dart';
import 'package:stocker/config/practice_session.dart';
import '../utils/contants.dart';

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

      // Clear investor-mode flag — otherwise it persists in storage and
      // leaks into whichever account logs in next on this device, until
      // that account's own login response happens to set it explicitly.
      final investorModeProvider =
          Provider.of<InvestorModeProvider>(context, listen: false);
      await investorModeProvider.clear();
      // Back to the live backend for the next login.
      await PracticeSession.set(false);

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

  Future<void> _handleDeleteAccount() async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Delete Account',
                  style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: kFontSizeViewTitle,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightBold)),
              const SizedBox(height: 12),
              const Text(
                'Are you sure you want to delete your account? This action cannot be undone.\n\nAll your data will be permanently removed.',
                style: TextStyle(
                    color: kColorTextMuted,
                    fontSize: kFontSizeBody,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                    height: 1.5),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: kColorTextMuted,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFFEF2F2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(
                            color: kColorSell,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    // Tracks whether the loading dialog is still on screen — if jsonDecode
    // below throws (a non-JSON response, e.g. a gateway HTML error page),
    // the catch block used to pop AGAIN unconditionally, closing the
    // ProfilePage route itself (already-dismissed dialog gone, so the pop
    // landed on the next thing on the stack) instead of just dismissing
    // the loading indicator.
    var dialogDismissed = false;
    try {
      final token = await _storage.getToken();
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.delete('/auth/account', token: token);

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      dialogDismissed = true;

      final body = jsonDecode(response.body);

      if (response.statusCode == 200 && body['success'] == true) {
        // Unregister FCM
        try {
          await FirebaseService().unregisterToken();
        } catch (_) {}

        // Clear local data
        final profileProvider =
            Provider.of<UserProfileProvider>(context, listen: false);
        profileProvider.clearProfile();
        Provider.of<TradeMetricsProvider>(context, listen: false).clear();
        await Provider.of<InvestorModeProvider>(context, listen: false)
            .clear();

        final activeKey = await _multiAccount.getActiveKey();
        if (activeKey != null) {
          await _multiAccount.removeAccount(activeKey);
        }

        await _storage.deleteToken();
        await _storage.deleteRole();

        if (!mounted) return;

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account deleted successfully'),
            backgroundColor: kColorBuy,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(body['message'] ?? 'Failed to delete account'),
            backgroundColor: kColorSell,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (!dialogDismissed) Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: kColorSell,
          ),
        );
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
                        fontSize: kFontSizePageTitle,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightBold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

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
                      roleColor = kBrandPrimary;
                      break;
                    default:
                      roleColor = kColorBuy;
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
                                  fontSize: kFontSizeSectionHeader,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightBold,
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
                                    fontSize: kFontSizeBody,
                                    fontFamily: kFontFamily,
                                    fontWeight: kFontWeightBold,
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
                                        color: kColorTextMuted,
                                        fontSize: kFontSizeNavLabel,
                                        fontFamily: kFontFamily,
                                        fontWeight: kFontWeightMedium,
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
                                          fontSize: kFontSizeBadge,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightBold,
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
                                  color: kColorTextMuted,
                                  fontSize: kFontSizeCaption,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightSemiBold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          const Icon(Icons.unfold_more,
                              size: kIconSizeMedium, color: kColorTextMuted),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // Announcement marquee
              const AnnouncementBanner(),

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
                          _buildMenuItem(context, 'Admin Setting',
                              svgPath: kIconAdminSettings),
                          _buildDivider(),
                        ] else
                          Builder(builder: (context) {
                            return const SizedBox.shrink();
                          }),
                        if (Provider.of<UserProfileProvider>(context,
                                listen: false)
                            .isSuperAdmin) ...[
                          _buildMenuItem(context, 'Manage Admins',
                              icon: Icons.admin_panel_settings_outlined),
                          _buildDivider(),
                        ],
                        _buildMenuItem(context, 'Account Detail',
                            svgPath: kIconAccountDetails),
                        _buildDivider(),
                        if ((_isAdmin || _isMaster) &&
                            !Provider.of<InvestorModeProvider>(context,
                                    listen: false)
                                .isInvestor) ...[
                          _buildMenuItem(
                              context, 'Master And User Management',
                              svgPath: kIconMasterUserMgmt),
                          _buildDivider(),
                        ] else
                          Builder(builder: (context) {
                            return const SizedBox.shrink();
                          }),
                        if (Provider.of<UserProfileProvider>(context,
                                listen: false)
                            .hasAnyReportPermission) ...[
                          _buildMenuItem(context, 'Reports',
                              svgPath: kIconReports),
                          _buildDivider(),
                        ],
                        if (_isMaster) ...[
                          _buildMenuItem(context, 'Manage Reports',
                              icon: Icons.description_outlined),
                          _buildDivider(),
                        ],
                        _buildMenuItem(context, 'Settings',
                            svgPath: kIconSettings),
                        _buildDivider(),
                        _buildMenuItem(context, 'Login History',
                            svgPath: kIconLoginHistory),
                        _buildDivider(),
                        _buildMenuItem(context, 'Switch Account',
                            icon: Icons.swap_horiz),
                        _buildDivider(),
                        if (!Provider.of<InvestorModeProvider>(context,
                                listen: false)
                            .isInvestor) ...[
                          _buildMenuItem(context, 'Delete Account',
                              svgPath: kIconDeleteAccount, isRed: true),
                          _buildDivider(),
                        ],
                        _buildMenuItem(context, 'Logout',
                            svgPath: kIconLogout, isRed: true),
                  ],
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title,
      {String? svgPath, IconData? icon, bool isRed = false}) {
    return BrandMenuRow(
      label: title,
      svgPath: svgPath,
      icon: icon,
      isDestructive: isRed,
      trailing: (_isLoggingOut && title == 'Logout')
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(kMenuRowDestructiveColor),
              ),
            )
          : null,
      onTap: _isLoggingOut
          ? null
          : () {
              if (title == 'Logout') {
                _handleLogout();
              } else if (title == 'Delete Account') {
                _handleDeleteAccount();
              } else if (title == 'Admin Setting') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const AdminSettingsView()),
                );
              } else if (title == 'Manage Admins') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ManageAdminsView()),
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
              } else if (title == 'Manage Reports') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const ManageReportsView()),
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
    );
  }

  Widget _buildDivider() {
    return const Divider(
        height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16);
  }
}
