import 'dart:developer';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/services/multi_account_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/update_check_service.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'pages/login_page.dart';
import 'pages/force_password_reset_page.dart';
import 'home_page.dart';
import 'utils/contants.dart';

/// Update: downloads the APK into the app's own temp storage and hands it
/// straight to Android's package installer (open_filex) — a plain
/// browser-launched download only ever produces a "downloaded" notification
/// the user has to go find in their Downloads folder and open manually,
/// which is exactly the friction this is meant to remove. Cancel: closes
/// the app outright, by design — an outdated build simply isn't allowed to
/// continue past this point.
///
/// Shared by InitialScreen (cold start) and main.dart's app-lifecycle
/// resume observer — a user who backgrounds the app instead of fully
/// closing it must still be blocked once a force update is published, not
/// only on the next cold start.
bool _forceUpdateDialogShowing = false;

Future<void> checkAndShowForceUpdate(BuildContext context) async {
  // Guards against the cold-start check and a rapid resume/pause cycle
  // both trying to show the blocking dialog at once.
  if (_forceUpdateDialogShowing) return;
  final update = await UpdateCheckService().check();
  if (update == null || !context.mounted) return;

  _forceUpdateDialogShowing = true;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: _UpdateDialog(apkUrl: update.apkUrl),
      ),
    );
  } finally {
    _forceUpdateDialogShowing = false;
  }
}

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

    if (!mounted) return;
    await _checkForUpdate();
    if (!mounted) return;

    try {
      final token = await _storage.getToken();
      print('🔐 Token retrieved: ${token != null ? "exists" : "null"}');

      if (!mounted) return;

      if (token != null && token.isNotEmpty) {
        log('✅ Token found, fetching user profile...');

        // Check if there's a pending password reset that was interrupted
        if (await _storage.isPasswordResetPending()) {
          log('🔐 Password reset pending — redirecting to reset screen');
          final currentPass = await _storage.getPasswordResetCurrentPassword();
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ForcePasswordResetPage(
                currentPassword: currentPass ?? '',
              ),
            ),
          );
          return;
        }

        final apiService = Provider.of<ApiService>(context, listen: false);
        apiService.setInitializing(true);

        // Restore investor mode state from storage
        final investorProvider =
            Provider.of<InvestorModeProvider>(context, listen: false);
        await investorProvider.loadFromStorage();

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
              builder: (context) => const MyHomePage(title: kAppName),
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

  /// Checked once per cold start, before the auth flow even runs, so it
  /// applies to every role (client/master/admin) and to a logged-out
  /// device alike. See [checkAndShowForceUpdate] below for the shared
  /// dialog logic — also invoked on app resume (main.dart) so a user who
  /// backgrounds the app instead of fully closing it is still caught.
  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    await checkAndShowForceUpdate(context);
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

enum _UpdateStage { prompt, downloading, error }

/// Update/Cancel prompt that, on Update, downloads the APK into the app's
/// own cache dir and hands it straight to Android's package installer
/// (open_filex) instead of just launching a browser download the user has
/// to go find manually. Cancel stays reachable throughout, including mid
/// download, so a stalled/slow download can never leave the user stuck.
class _UpdateDialog extends StatefulWidget {
  final String apkUrl;
  const _UpdateDialog({required this.apkUrl});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _UpdateStage _stage = _UpdateStage.prompt;
  double? _progress; // null = indeterminate (no Content-Length reported)
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _stage = _UpdateStage.downloading;
      _progress = null;
      _errorMessage = null;
    });
    try {
      final request = http.Request('GET', Uri.parse(widget.apkUrl));
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        throw Exception('Download failed (${response.statusCode})');
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/apex_update.apk');
      final sink = file.openWrite();

      final total = response.contentLength;
      var received = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0 && mounted) {
          setState(() => _progress = received / total);
        }
      }
      await sink.close();

      if (!mounted) return;
      final result = await OpenFilex.open(file.path);
      // A non-'done' result (e.g. the user has never allowed installs from
      // this app, or declines Android's own "install unknown app" prompt)
      // leaves the OLD build still running — return to the prompt so
      // Update can be retried rather than silently stranding the dialog.
      if (result.type != ResultType.done && mounted) {
        setState(() {
          _stage = _UpdateStage.error;
          _errorMessage = result.message.isNotEmpty
              ? result.message
              : 'Could not open the installer — please allow installs from this app if prompted, then try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _UpdateStage.error;
        _errorMessage = 'Download failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Update available'),
      content: switch (_stage) {
        _UpdateStage.prompt => const Text(
            'A new version of the app is available. Please update to continue using the app.',
          ),
        _UpdateStage.downloading => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Downloading update…'),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _progress),
              if (_progress != null) ...[
                const SizedBox(height: 6),
                Text('${(_progress! * 100).toStringAsFixed(0)}%'),
              ],
            ],
          ),
        _UpdateStage.error => Text(_errorMessage ?? 'Something went wrong.'),
      },
      actions: [
        TextButton(
          onPressed: () => SystemNavigator.pop(),
          child: const Text('Cancel'),
        ),
        if (_stage != _UpdateStage.downloading)
          TextButton(
            onPressed: _startDownload,
            child: Text(_stage == _UpdateStage.error ? 'Retry' : 'Update'),
          ),
      ],
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
                        kLogoAsset,
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
                  // Brand name text — slides up + fades in
                  SlideTransition(
                    position: _textSlide,
                    child: FadeTransition(
                      opacity: _textFade,
                      child: const Text(
                        kAppName,
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: kFontSizeDisplay,
                          fontFamily: kFontFamily,
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
                        fontFamily: kFontFamily,
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
                      color: kBrandPrimary,
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
