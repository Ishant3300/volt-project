import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/services/firebase_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/multi_account_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../home_page.dart';
import '../utils/contants.dart';
import '../views/webview_page.dart';
import 'force_password_reset_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _serverSearchController = TextEditingController();

  String _selectedServer = 'Select Server';
  bool _isLoading = false;
  List<Map<String, dynamic>> _servers = [];
  bool _isLoadingServers = false;
  bool _showServerResults = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _searchServers(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _servers = [];
        _showServerResults = false;
      });
      return;
    }
    setState(() => _isLoadingServers = true);
    try {
      final res = await ApiService(backendUrl)
          .get('/servers/search?q=${Uri.encodeComponent(query.trim())}');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _servers = List<Map<String, dynamic>>.from(body['data'] ?? []);
            _showServerResults = _servers.isNotEmpty;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingServers = false);
  }

  void _login() async {
    if (_selectedServer == 'Select Server') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a server'),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (_usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter username'),
            backgroundColor: Colors.red),
      );
      return;
    }
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter password'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Get FCM token so OTP is sent to THIS device
      String? fcmToken;
      try {
        fcmToken = await FirebaseMessaging.instance.getToken();
      } catch (_) {}

      final authData = AuthenticateData(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
        fcmToken: fcmToken,
      );

      apiService.setInitializing(true);
      final response = await authService.login(data: authData);

      if (mounted) {
        if (response.success) {
          // Check if OTP is required (admin login)
          if (response.data != null &&
              response.data!['requires_totp'] == true) {
            apiService.setInitializing(false);
            setState(() => _isLoading = false);
            _showTotpDialog();
            return;
          }

          // Check if password change is required (first login)
          if (response.requiresPasswordChange) {
            apiService.setInitializing(false);
            setState(() => _isLoading = false);
            if (!mounted) return;
            // Persist the pending state so app restart can't bypass
            await SecureStorageService().setPasswordResetPending(
              currentPassword: _passwordController.text,
            );
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ForcePasswordResetPage(
                  currentPassword: _passwordController.text,
                ),
              ),
            );
            return;
          }

          // Set investor mode based on login response
          final investorProvider =
              Provider.of<InvestorModeProvider>(context, listen: false);
          await investorProvider
              .setInvestor(response.data?['investor'] == true);

          final profileProvider =
              Provider.of<UserProfileProvider>(context, listen: false);
          await profileProvider.fetchProfile();

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(response.message), backgroundColor: Colors.green),
          );

          final watchlistProvider =
              Provider.of<WatchlistProvider>(context, listen: false);
          await watchlistProvider.loadWatchlist();

          final tradeMetricsProvider =
              Provider.of<TradeMetricsProvider>(context, listen: false);
          await tradeMetricsProvider.fetchBaseData();

          // Register FCM token with backend
          await FirebaseService().registerToken();

          apiService.setInitializing(false);

          // Check if disclaimer has been accepted
          const storage = FlutterSecureStorage();
          final accepted = await storage.read(key: 'disclaimer_accepted');
          if (!mounted) return;

          if (accepted == 'true') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => const MyHomePage(title: kAppName)),
            );
          } else {
            _showDisclaimerDialog();
          }
        } else {
          apiService.setInitializing(false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(response.message), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Provider.of<ApiService>(context, listen: false).setInitializing(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Login failed: ${e.toString()}'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showTotpDialog() {
    final totpController = TextEditingController();
    bool isVerifying = false;
    bool isLoadingApp = false;
    String loadingMessage = '';
    final parentContext = context;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Loading state — full dialog becomes a loader
          if (isLoadingApp) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [kBrandGradientStart, kBrandGradientEnd]),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: kBrandPrimary
                                  .withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ],
                      ),
                      child: const Center(
                        child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Verified ✓',
                        style: TextStyle(
                            fontSize: kFontSizeSectionHeader,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightBold,
                            color: kColorBuy)),
                    const SizedBox(height: 8),
                    Text(loadingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: kFontSizeBodySmall,
                            fontFamily: kFontFamily,
                            color: kColorTextMuted)),
                  ],
                ),
              ),
            );
          }

          // Normal TOTP input state
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.security,
                      size: 48, color: kBrandPrimary),
                  const SizedBox(height: 12),
                  const Text('Two-Factor Authentication',
                      style: TextStyle(
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightBold,
                          color: Color(0xFF0F172A))),
                  const SizedBox(height: 8),
                  const Text(
                      'Enter the 6-digit code from your authenticator app',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: kFontSizeBodySmall,
                          fontFamily: kFontFamily,
                          color: kColorTextMuted)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: totpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 24,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightBold,
                        letterSpacing: 8),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '------',
                      hintStyle: const TextStyle(
                          color: Color(0xFFCBD5E1), letterSpacing: 8),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide:
                              const BorderSide(color: Color(0xFFE2E8F0))),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                              color: kBrandPrimary, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GestureDetector(
                    onTap: isVerifying
                        ? null
                        : () async {
                            final code = totpController.text.trim();
                            if (code.length != 6) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                    content: Text('Enter 6-digit code'),
                                    backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setDialogState(() => isVerifying = true);

                            try {
                              final apiService = Provider.of<ApiService>(
                                  parentContext,
                                  listen: false);
                              apiService.setInitializing(true);

                              final res = await apiService.post('/auth/login', {
                                'username': _usernameController.text.trim(),
                                'password': _passwordController.text,
                                'totp_code': code,
                              });

                              final body = jsonDecode(res.body);

                              if (res.statusCode == 200 &&
                                  body['success'] == true &&
                                  body['data']?['requires_totp'] != true) {
                                // TOTP verified — switch to loading state
                                setDialogState(() {
                                  isLoadingApp = true;
                                  loadingMessage = 'Setting up your account...';
                                });

                                final token = body['data']?['token'];
                                if (token != null) {
                                  // This dialog used to be admin-only, so it
                                  // hardcoded 'ADMIN' here — now that a
                                  // master can have TOTP enabled too (see
                                  // totpService.js), that hardcoding mislabels
                                  // every TOTP-enabled master as an admin in
                                  // local storage and the account switcher,
                                  // even though the token itself is a real
                                  // master token. universalLogin's response
                                  // already carries the true role — use it.
                                  final role =
                                      (body['data']?['role'] as String?) ??
                                          'ADMIN';
                                  final accountData =
                                      body['data']?[role.toLowerCase()];

                                  final secStorage = SecureStorageService();
                                  await secStorage.saveToken(token: token);
                                  await secStorage.saveRole(role: role);

                                  final multiAccount = MultiAccountService();
                                  final savedAccount = SavedAccount(
                                    username: _usernameController.text.trim(),
                                    role: role,
                                    token: token,
                                    name: accountData?['username'] ??
                                        _usernameController.text.trim(),
                                  );
                                  await multiAccount.saveAccount(savedAccount);
                                  await multiAccount.setActiveKey(
                                      '${savedAccount.username}_${savedAccount.role}');
                                }

                                setDialogState(() =>
                                    loadingMessage = 'Loading profile...');
                                final profileProvider =
                                    Provider.of<UserProfileProvider>(
                                        parentContext,
                                        listen: false);
                                await profileProvider.fetchProfile();
                                if (!mounted) return;

                                setDialogState(() =>
                                    loadingMessage = 'Loading watchlist...');
                                final watchlistProvider =
                                    Provider.of<WatchlistProvider>(
                                        parentContext,
                                        listen: false);
                                await watchlistProvider.loadWatchlist();

                                setDialogState(() =>
                                    loadingMessage = 'Loading trade data...');
                                final tradeMetricsProvider =
                                    Provider.of<TradeMetricsProvider>(
                                        parentContext,
                                        listen: false);
                                await tradeMetricsProvider.fetchBaseData();

                                setDialogState(
                                    () => loadingMessage = 'Almost ready...');
                                await FirebaseService().registerToken();
                                apiService.setInitializing(false);

                                if (!mounted) return;
                                Navigator.of(ctx).pop();

                                const flutterStorage = FlutterSecureStorage();
                                final accepted = await flutterStorage.read(
                                    key: 'disclaimer_accepted');
                                if (!mounted) return;

                                if (accepted == 'true') {
                                  Navigator.pushReplacement(
                                      parentContext,
                                      MaterialPageRoute(
                                          builder: (_) => const MyHomePage(
                                              title: kAppName)));
                                } else {
                                  _showDisclaimerDialog();
                                }
                              } else {
                                apiService.setInitializing(false);
                                setDialogState(() => isVerifying = false);
                                ScaffoldMessenger.of(parentContext)
                                    .showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          body['message'] ?? 'Invalid code'),
                                      backgroundColor: Colors.red),
                                );
                              }
                            } catch (e) {
                              Provider.of<ApiService>(parentContext,
                                      listen: false)
                                  .setInitializing(false);
                              setDialogState(() {
                                isVerifying = false;
                                isLoadingApp = false;
                              });
                              ScaffoldMessenger.of(parentContext).showSnackBar(
                                SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: Colors.red),
                              );
                            }
                          },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: isVerifying
                            ? null
                            : const LinearGradient(
                                colors: [kBrandGradientStart, kBrandGradientEnd]),
                        color: isVerifying ? kColorTextMuted : null,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: isVerifying
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('VERIFY',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: kFontSizeButtonText,
                                    fontFamily: kFontFamily,
                                    fontWeight: kFontWeightBold)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(
                            color: kColorTextMuted,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDisclaimerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                'Important Notice',
                style: TextStyle(
                  fontSize: kFontSizeSectionHeader,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightBold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$kAppName is a simulation-based trading platform designed for educational purposes only.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: kFontSizeBody,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 16),
              _buildBulletPoint('No real money trading is supported'),
              _buildBulletPoint('No deposits or withdrawals are possible'),
              _buildBulletPoint(
                  'All trades, prices, and profits/losses are simulated or based on delayed data'),
              _buildBulletPoint(
                  '$kAppName does not provide financial or investment advice'),
              const SizedBox(height: 16),
              Text(
                'By continuing, you acknowledge that you are using a virtual trading environment and not a real brokerage service.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: kFontSizeSubtitle,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightRegular,
                  color: kColorTextMuted,
                ),
              ),
              const SizedBox(height: 24),
              // I Understand & Continue
              GestureDetector(
                onTap: () async {
                  const storage = FlutterSecureStorage();
                  await storage.write(
                      key: 'disclaimer_accepted', value: 'true');
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (context) =>
                            const MyHomePage(title: kAppName)),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [kBrandGradientStart, kBrandGradientEnd],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      'I Understand & Continue',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: kFontSizeButtonText,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightBold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Exit App
              GestureDetector(
                onTap: () => exit(0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Center(
                    child: Text(
                      'Exit App',
                      style: TextStyle(
                          color: kColorTextMuted,
                          fontSize: kFontSizeButtonText,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ',
              style: TextStyle(fontSize: 14, color: kColorTextMuted)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kFontSizeBodySmall,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightRegular,
                color: kColorTextMuted,
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                // Main login form
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      SvgPicture.asset(
                        kLogoAsset,
                        width: 80,
                        height: 80,
                      ),
                      const SizedBox(height: 12),
                      Text(kAppName,
                          style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: kFontSizeLoginTitle,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightBold,
                              letterSpacing: 3)),
                      const SizedBox(height: 8),
                      Text(
                        'To sign in to an account in the application,\nenter your username and password',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: kColorTextMuted,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightRegular),
                      ),
                      const SizedBox(height: 16),

                      // Server field
                      _buildFieldLabel('Server'),
                      const SizedBox(height: 6),
                      _buildServerSearchField(),
                      const SizedBox(height: 14),

                      // Username field
                      _buildFieldLabel('Username'),
                      const SizedBox(height: 6),
                      _buildTextField(
                          _usernameController, 'Enter Username', false),
                      const SizedBox(height: 14),

                      // Password field
                      _buildFieldLabel('Password'),
                      const SizedBox(height: 6),
                      _buildTextField(
                          _passwordController, 'Enter Password', true),
                      const SizedBox(height: 16),

                      // Continue button
                      GestureDetector(
                        onTap: _isLoading ? null : _login,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: _isLoading
                                ? null
                                : const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      kBrandGradientStart,
                                      kBrandGradientEnd,
                                    ],
                                  ),
                            color: _isLoading ? kColorTextMuted : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : Text('CONTINUE',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: kFontSizeButtonText,
                                        fontFamily: kFontFamily,
                                        fontWeight: kFontWeightBold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // Terms
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(
                          text:
                              'By clicking "Continue", I have read and agree\nwith the ',
                          style: TextStyle(
                              color: kColorTextMuted,
                              fontSize: kFontSizeSubtitle,
                              fontFamily: kFontFamily)),
                      WidgetSpan(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const WebViewPage(
                                  url:
                                      'https://apexlive.framer.website/privacy',
                                  title: 'Privacy Policy',
                                ),
                              ),
                            );
                          },
                          child: Text(
                            'Term & Privacy Policy',
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.7),
                              fontSize: kFontSizeSubtitle,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightMedium,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ]),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerSearchField() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _selectedServer != 'Select Server'
                  ? kColorBuy
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _serverSearchController,
                  onChanged: (v) => _searchServers(v),
                  style: const TextStyle(
                      fontSize: kFontSizeButtonText,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium),
                  decoration: const InputDecoration(
                    hintText: 'Search server by name...',
                    hintStyle: TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: kFontSizeButtonText,
                        fontFamily: kFontFamily),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (_isLoadingServers)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kBrandPrimary)),
                )
              else if (_selectedServer != 'Select Server')
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedServer = 'Select Server';
                      _serverSearchController.clear();
                      _servers = [];
                      _showServerResults = false;
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child:
                        Icon(Icons.close, size: 18, color: kColorTextMuted),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.search, size: 18, color: kColorTextMuted),
                ),
            ],
          ),
        ),
        if (_showServerResults && _servers.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ],
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _servers.length,
              itemBuilder: (_, i) {
                final name = _servers[i]['name']?.toString() ?? '';
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedServer = name;
                      _serverSearchController.text = name;
                      _showServerResults = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: const Color(0xFFF1F5F9),
                              width: i < _servers.length - 1 ? 1 : 0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.dns_outlined,
                            size: 16, color: kColorTextMuted),
                        const SizedBox(width: 10),
                        Text(name,
                            style: const TextStyle(
                                color: kColorTextPrimary,
                                fontSize: kFontSizeBody,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightMedium)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label,
          style: const TextStyle(
              color: kColorTextPrimary,
              fontSize: kFontSizeBodySmall,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
              letterSpacing: 0.3)),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String hint, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
          fontSize: kFontSizeButtonText,
          fontFamily: kFontFamily,
          fontWeight: kFontWeightMedium),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: kFontSizeButtonText,
            fontFamily: kFontFamily),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBrandPrimary, width: 1.5)),
      ),
    );
  }
}
