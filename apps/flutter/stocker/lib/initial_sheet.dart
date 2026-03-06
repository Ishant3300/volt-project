import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'pages/login_page.dart';
import 'home_page.dart';

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
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    log('🔐 Checking authentication status...');

    await Future.delayed(const Duration(seconds: 2));

    try {
      final token = await _storage.getToken();

      if (!mounted) return;

      if (token != null && token.isNotEmpty) {
        log('✅ Token found, fetching user profile...');

        final apiService = Provider.of<ApiService>(context, listen: false);
        apiService.setInitializing(true);

        final profileProvider =
            Provider.of<UserProfileProvider>(context, listen: false);
        await profileProvider.fetchProfile();

        if (!mounted) return;
        final tradeMetricsProvider =
            Provider.of<TradeMetricsProvider>(context, listen: false);
        await tradeMetricsProvider.fetchBaseData();

        apiService.setInitializing(false);

        if (!mounted) return;

        log('✅ Profile loaded, navigating to home');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => const MyHomePage(title: 'Stocker'),
          ),
        );
      } else {
        log('❌ No token found, navigating to login');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    } catch (e) {
      log('❌ Error checking auth status: $e');

      if (mounted) {
        final apiService = Provider.of<ApiService>(context, listen: false);
        apiService.setInitializing(false);
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
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _subtitleFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
    ));

    _subtitleFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
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
                  // STOCKER text — slides up + fades in
                  SlideTransition(
                    position: _slideAnimation,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: const Text(
                        'STOCKER',
                        style: TextStyle(
                          color: Color(0xFF22547C),
                          fontSize: 32,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Subtitle fades in after the main text
                  FadeTransition(
                    opacity: _subtitleFade,
                    child: const Text(
                      'Trade smarter',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0.5,
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
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF22547C),
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
