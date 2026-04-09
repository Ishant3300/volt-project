import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/multi_account_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'pages/login_page.dart';
import 'home_page.dart';
import 'utils/contants.dart';

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  final SecureStorageService _storage = SecureStorageService();
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    print('🏁 InitialScreen initState called');
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    print('🔐 Checking authentication status...');

    await Future.delayed(const Duration(seconds: 2));

    try {
      final token = await _storage.getToken();
      print('🔐 Token retrieved: ${token != null ? "exists" : "null"}');

      if (!mounted) return;

      if (token != null && token.isNotEmpty) {
        log('✅ Token found, fetching user profile...');

        final apiService = Provider.of<ApiService>(context, listen: false);
        apiService.setInitializing(true);

        try {
          final profileProvider =
              Provider.of<UserProfileProvider>(context, listen: false);
          await profileProvider.fetchProfile().timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              log('⏰ Profile fetch timed out');
              throw Exception('Profile fetch timed out');
            },
          );

          if (!mounted) return;
          final tradeMetricsProvider =
              Provider.of<TradeMetricsProvider>(context, listen: false);
          await tradeMetricsProvider.fetchBaseData().timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              log('⏰ Base data fetch timed out');
              throw Exception('Base data fetch timed out');
            },
          );

          apiService.setInitializing(false);

          if (!mounted) return;

          log('✅ Profile loaded, navigating to home');

          // Ensure current session is in multi-account list (migration for existing users)
          final multiAccount = MultiAccountService();
          final accounts = await multiAccount.getSavedAccounts();
          final role = await _storage.getRole();
          final username = profileProvider.user?.username ??
              profileProvider.master?.username ??
              '';
          if (username.isNotEmpty && role != null) {
            final key = '${username}_$role';
            final exists = accounts.any((a) => a.key == key);
            if (!exists) {
              await multiAccount.saveAccount(SavedAccount(
                username: username,
                role: role,
                token: token,
                name: profileProvider.user?.name ??
                    profileProvider.master?.name ??
                    username,
              ));
              await multiAccount.setActiveKey(key);
              log('📦 Migrated existing session to multi-account list');
            } else {
              // Update token in case it changed
              await multiAccount.updateToken(key, token);
              await multiAccount.setActiveKey(key);
            }
          }

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const MyHomePage(title: 'APEX'),
            ),
          );
        } catch (e) {
          log('❌ Error during profile fetch: $e');
          apiService.setInitializing(false);
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginPage()),
          );
        }
      } else {
        log('❌ No token found, navigating to login');
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    } catch (e) {
      log('❌ Error checking auth status: $e');

      if (mounted) {
        try {
          final apiService = Provider.of<ApiService>(context, listen: false);
          apiService.setInitializing(false);
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () {
          if (!_isChecking) {
            log('Initial screen tapped - checking auth');
            _checkAuthStatus();
          }
        },
        child: const SplashScreen(),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<double> _textFade;
  late Animation<Offset> _textSlide;
  late Animation<double> _subtitleFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // Logo scales up and fades in
    _logoScale = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic),
    ));

    _logoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );

    // Text fades in and slides up after logo
    _textFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 0.7, curve: Curves.easeOut),
    );

    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.4, 0.7, curve: Curves.easeOutCubic),
    ));

    // Subtitle fades in last
    _subtitleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
      child: SafeArea(
        child: Stack(
          children: [
            // Centered logo area
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo — scales up and fades in
                  ScaleTransition(
                    scale: _logoScale,
                    child: FadeTransition(
                      opacity: _logoFade,
                      child: SvgPicture.asset(
                        'assets/Subtract.svg',
                        width: 100,
                        height: 100,
                        placeholderBuilder: (context) => Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.image,
                            size: 50,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // APEX text — slides up + fades in
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: const Text(
                        'APEX',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: kFontSizeDisplay,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightBold,
                          letterSpacing: 4,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle fades in after the main text
                  FadeTransition(
                    opacity: _subtitleFade,
                    child: const Text(
                      'YOUR EDGE IN THE MARKET',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: kFontSizeSubtitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom loading indicator
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: FadeTransition(
                opacity: _subtitleFade,
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF3F45C7),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
