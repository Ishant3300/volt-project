import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/services/multi_account_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/pages/login_page.dart';
import 'package:stocker/home_page.dart';

class AccountSwitcherSheet extends StatefulWidget {
  const AccountSwitcherSheet({super.key});

  @override
  State<AccountSwitcherSheet> createState() => _AccountSwitcherSheetState();
}

class _AccountSwitcherSheetState extends State<AccountSwitcherSheet> {
  final MultiAccountService _multiAccount = MultiAccountService();
  final SecureStorageService _storage = SecureStorageService();
  List<SavedAccount> _accounts = [];
  String? _activeKey;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final accounts = await _multiAccount.getSavedAccounts();
    final activeKey = await _multiAccount.getActiveKey();
    if (mounted) {
      setState(() {
        _accounts = accounts;
        _activeKey = activeKey;
      });
    }
  }

  Future<void> _switchTo(SavedAccount account) async {
    if (account.key == _activeKey || _switching) return;

    setState(() => _switching = true);

    try {
      // Set the new token and role in secure storage
      await _storage.saveToken(token: account.token);
      await _storage.saveRole(role: account.role);
      await _multiAccount.setActiveKey(account.key);

      if (!mounted) return;

      // Refresh all providers with new account data
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      profileProvider.clearProfile();
      await profileProvider.fetchProfile();

      if (!mounted) return;

      final tradeMetrics =
          Provider.of<TradeMetricsProvider>(context, listen: false);
      tradeMetrics.clear();
      await tradeMetrics.fetchBaseData();

      if (!mounted) return;

      final watchlist =
          Provider.of<WatchlistProvider>(context, listen: false);
      await watchlist.loadWatchlist();

      if (!mounted) return;

      Navigator.of(context).pop(); // close sheet

      // Navigate to home, clearing the stack
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MyHomePage(title: 'Stocker'),
        ),
        (route) => false,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Switched to ${account.username}'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _switching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switch failed: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  Future<void> _removeAccount(SavedAccount account) async {
    if (account.key == _activeKey) return; // can't remove active account

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Remove Account',
            style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        content: Text(
          'Remove ${account.username} (${account.role}) from saved accounts?',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _multiAccount.removeAccount(account.key);
      _loadAccounts();
    }
  }

  void _addNewAccount() {
    Navigator.of(context).pop(); // close sheet
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'ADMIN':
        return const Color(0xFF8B5CF6);
      case 'MASTER':
        return const Color(0xFF3F45C7);
      default:
        return const Color(0xFF10B981);
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'ADMIN':
        return Icons.admin_panel_settings;
      case 'MASTER':
        return Icons.shield_outlined;
      default:
        return Icons.person_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Text(
              'Switch Account',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),

          // Loading overlay
          if (_switching)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                children: [
                  CircularProgressIndicator(
                      color: Color(0xFF3F45C7), strokeWidth: 2.5),
                  SizedBox(height: 16),
                  Text('Switching account...',
                      style: TextStyle(
                          color: Color(0xFF64748B),
                          fontFamily: 'Inter',
                          fontSize: 14)),
                ],
              ),
            )
          else ...[
            // Account list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _accounts.length,
                itemBuilder: (context, index) {
                  final account = _accounts[index];
                  final isActive = account.key == _activeKey;
                  return _buildAccountTile(account, isActive);
                },
              ),
            ),

            // Add account button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: GestureDetector(
                onTap: _addNewAccount,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFE2E8F0),
                      width: 1.5,
                      strokeAlign: BorderSide.strokeAlignInside,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: Color(0xFF3F45C7), size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Add Another Account',
                        style: TextStyle(
                          color: Color(0xFF3F45C7),
                          fontSize: 15,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccountTile(SavedAccount account, bool isActive) {
    final roleColor = _roleColor(account.role);

    return GestureDetector(
      onTap: () => _switchTo(account),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF3F45C7).withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive ? const Color(0xFF3F45C7).withValues(alpha: 0.2) : const Color(0xFFF1F5F9),
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: roleColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (account.name ?? account.username)
                      .substring(0, 1)
                      .toUpperCase(),
                  style: TextStyle(
                    color: roleColor,
                    fontSize: 18,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          account.name ?? account.username,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 15,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 9,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(_roleIcon(account.role),
                          size: 12, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        '${account.username} · ${account.role}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Remove button (only for non-active accounts)
            if (!isActive)
              GestureDetector(
                onTap: () => _removeAccount(account),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      size: 14, color: Color(0xFF94A3B8)),
                ),
              )
            else
              const Icon(Icons.check_circle,
                  size: 22, color: Color(0xFF10B981)),
          ],
        ),
      ),
    );
  }
}

void showAccountSwitcher(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const AccountSwitcherSheet(),
  );
}
