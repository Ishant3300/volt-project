import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/services/firebase_service.dart';
import '../home_page.dart';
import '../utils/contants.dart';
import 'login_page.dart';

/// Screen shown when a user/master logs in for the first time and must
/// change their password before proceeding. Cannot be bypassed — there is
/// no back button, no skip option. The only way out is to set a new password
/// or log out (which clears the token).
class ForcePasswordResetPage extends StatefulWidget {
  /// The current (temporary) password the user just logged in with.
  /// Needed for the change-password API which requires current_password.
  final String currentPassword;

  const ForcePasswordResetPage({super.key, required this.currentPassword});

  @override
  State<ForcePasswordResetPage> createState() => _ForcePasswordResetPageState();
}

class _ForcePasswordResetPageState extends State<ForcePasswordResetPage> {
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.isEmpty || confirmPass.isEmpty) {
      _showError('Please fill in both fields');
      return;
    }

    if (newPass.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    if (newPass != confirmPass) {
      _showError('Passwords do not match');
      return;
    }

    if (newPass == widget.currentPassword) {
      _showError('New password must be different from current password');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final token = await SecureStorageService().getToken();

      final response = await apiService.post(
        '/auth/change-password',
        {
          'current_password': widget.currentPassword,
          'new_password': newPass,
        },
        token: token,
      );

      final body = jsonDecode(response.body);

      if (mounted) {
        if (response.statusCode == 200 && body['success'] == true) {
          // Password changed successfully on the backend — from this point
          // on we must never show this form again or let a later local
          // failure look like the change itself failed: widget.currentPassword
          // is now stale, so a retry from this screen would be rejected by
          // the backend as "current password incorrect", confusingly
          // implying the just-confirmed success never happened.
          try {
            await SecureStorageService().clearPasswordResetPending();
          } catch (e) {
            log('⚠️ Failed to clear password-reset-pending flag locally: $e');
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Password changed successfully'),
              backgroundColor: Colors.green,
            ),
          );

          // Load profile and navigate to home
          await _loadAppData();
        } else {
          _showError(body['message'] ?? 'Failed to change password');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAppData() async {
    try {
      // The backend only ever requires a forced password change for
      // non-investor logins (see authController.js's requiresPasswordChange:
      // `!isInvestorLogin && ...`), so this path is unreachable for a real
      // investor session. Set it explicitly rather than leaving whatever
      // stale value secure storage carried over from a previous account on
      // this device.
      await Provider.of<InvestorModeProvider>(context, listen: false)
          .setInvestor(false);

      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      await profileProvider.fetchProfile();

      if (!mounted) return;

      final watchlistProvider =
          Provider.of<WatchlistProvider>(context, listen: false);
      await watchlistProvider.loadWatchlist();

      final tradeMetricsProvider =
          Provider.of<TradeMetricsProvider>(context, listen: false);
      await tradeMetricsProvider.fetchBaseData();

      await FirebaseService().registerToken();

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
            builder: (_) => const MyHomePage(title: kAppName)),
        (route) => false, // Remove all previous routes
      );
    } catch (e) {
      // The password change itself already succeeded by the time this runs
      // (this is only called from that success branch) — a failure here is
      // just a secondary data load hiccup. Every screen it would have
      // populated (profile, watchlist, metrics) already tracks and surfaces
      // its own load-failure/retry state independently, so trap the user on
      // this password screen instead — where retrying is broken — is worse
      // than just letting them in and refreshing from inside.
      log('⚠️ Post-password-change data load failed, proceeding to home anyway: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Password changed. Some data failed to load — pull to refresh once inside.'),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MyHomePage(title: kAppName)),
          (route) => false,
        );
      }
    }
  }

  Future<void> _logout() async {
    final storage = SecureStorageService();
    await storage.clearPasswordResetPending();
    await storage.deleteToken();
    await storage.deleteRole();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back button
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // Lock icon
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kBrandGradientStart, kBrandGradientEnd],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kBrandPrimary.withValues(alpha: 0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.lock_reset,
                        size: 40, color: Colors.white),
                  ),

                  const SizedBox(height: 24),

                  const Text(
                    'Set New Password',
                    style: TextStyle(
                      fontSize: kFontSizePageTitle,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightBold,
                      color: Color(0xFF0F172A),
                    ),
                  ),

                  const SizedBox(height: 8),

                  const Text(
                    'Your account requires a password change before you can continue. Please set a new password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: kFontSizeBody,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightRegular,
                      color: Color(0xFF64748B),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // New password field
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'New Password',
                          style: TextStyle(
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _newPasswordController,
                          obscureText: _obscureNew,
                          style: const TextStyle(
                              fontSize: kFontSizeButtonText,
                              fontFamily: kFontFamily),
                          decoration: InputDecoration(
                            hintText: 'Enter new password',
                            hintStyle: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: kFontSizeButtonText),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: kBrandPrimary, width: 1.5),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureNew
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Confirm Password',
                          style: TextStyle(
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                            color: Color(0xFF334155),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirm,
                          style: const TextStyle(
                              fontSize: kFontSizeButtonText,
                              fontFamily: kFontFamily),
                          decoration: InputDecoration(
                            hintText: 'Confirm new password',
                            hintStyle: const TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: kFontSizeButtonText),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(
                                  color: kBrandPrimary, width: 1.5),
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirm
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                                color: const Color(0xFF94A3B8),
                                size: 20,
                              ),
                              onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Change password button
                  GestureDetector(
                    onTap: _isLoading ? null : _changePassword,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: _isLoading
                            ? null
                            : const LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: [kBrandGradientStart, kBrandGradientEnd],
                              ),
                        color: _isLoading ? const Color(0xFF94A3B8) : null,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : const Text(
                                'SET NEW PASSWORD',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: kFontSizeButtonText,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightBold,
                                ),
                              ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Logout option
                  GestureDetector(
                    onTap: _isLoading ? null : _logout,
                    child: const Text(
                      'Logout instead',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: kFontSizeBody,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
