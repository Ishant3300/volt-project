import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/services/admin_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/services/user_service.dart';
import 'package:stocker/services/kite_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:stocker/services/firebase_service.dart';
import 'package:stocker/services/app_identity.dart';
import 'package:stocker/services/crash_reporter.dart';
import 'package:stocker/firebase_options.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/pages/login_page.dart';
import 'initial_sheet.dart';
import 'dart:async';
import 'dart:developer';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Uncaught errors go to the backend (client-events, kind 'crash') too.
  CrashReporter.install();
  // App version + phone model for the User-Agent / crash reports; read in
  // the background so it never delays the first frame.
  unawaited(AppIdentity.load());

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print('✅ Firebase initialized');

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  print('🚀 Starting $kAppName App');
  runApp(const MyApp());
  print('✅ runApp called');

  // FirebaseService().init() requests notification permissions — a real OS
  // dialog that can sit waiting on the user — and sets up channels, neither
  // of which the first frame needs. It used to block runApp() itself, so
  // every cold start paid for it before the user saw anything at all. Fired
  // here instead, after the splash is already on screen; the permission
  // prompt now appears a moment after launch rather than delaying launch.
  unawaited(FirebaseService().init().then((_) {
    print('✅ FirebaseService initialized');
  }));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // The very first transition to `resumed` happens as part of cold start,
  // before InitialScreen's own _checkForUpdate has necessarily run — skip
  // it so cold start isn't double-checked, and only react to a REAL
  // return from background/minimized from here on.
  bool _skipNextResume = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (_skipNextResume) {
      _skipNextResume = false;
      return;
    }
    // A user who minimizes the app instead of fully closing it previously
    // never re-ran the force-update check at all — InitialScreen only runs
    // once per cold start, so a published force update never caught them
    // until they happened to kill and reopen the app. The global
    // navigatorKey lets this show on top of whatever screen the user is
    // actually on, not just the splash screen.
    final navContext = NavigationService.navigatorKey.currentContext;
    if (navContext != null) {
      checkAndShowForceUpdate(navContext);
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🔨 Building MyApp widget tree');
    return MultiProvider(
      providers: [
        Provider<ApiService>(
          create: (_) {
            log('   Creating ApiService with URL: ');
            return ApiService(backendUrl);
          },
        ),
        ProxyProvider<ApiService, AuthService>(
          update: (_, apiService, __) {
            log('   Creating AuthService');
            return AuthService(apiService);
          },
        ),
        ProxyProvider<ApiService, AdminService>(
          update: (_, apiService, __) {
            log('   Creating AdminService');
            return AdminService(apiService);
          },
        ),
        ProxyProvider<ApiService, UserService>(
          update: (_, apiService, __) {
            log('   Creating UserService');
            return UserService(apiService);
          },
        ),
        ProxyProvider<ApiService, KiteService>(
          update: (_, apiService, __) {
            log('   Creating KiteService');
            return KiteService(apiService);
          },
        ),
        ChangeNotifierProxyProvider<ApiService, UserProfileProvider>(
          create: (context) {
            log('   Creating UserProfileProvider');
            final apiService = Provider.of<ApiService>(context, listen: false);
            return UserProfileProvider(apiService);
          },
          update: (_, apiService, previous) {
            log('   Updating UserProfileProvider');
            return previous ?? UserProfileProvider(apiService);
          },
        ),
        ChangeNotifierProxyProvider<UserProfileProvider, TradeMetricsProvider>(
          create: (context) {
            log('   Creating TradeMetricsProvider');
            return TradeMetricsProvider(
              userProfileProvider:
                  Provider.of<UserProfileProvider>(context, listen: false),
            );
          },
          update: (_, userProfileProvider, previous) {
            log('   Updating TradeMetricsProvider');
            return previous ??
                TradeMetricsProvider(userProfileProvider: userProfileProvider);
          },
        ),
        ChangeNotifierProxyProvider<TradeMetricsProvider, WatchlistProvider>(
          create: (context) {
            log('   Creating WatchlistProvider');
            return WatchlistProvider(
              tradeMetricsProvider:
                  Provider.of<TradeMetricsProvider>(context, listen: false),
            );
          },
          update: (_, tradeMetricsProvider, previous) {
            previous ??=
                WatchlistProvider(tradeMetricsProvider: tradeMetricsProvider);
            previous.tradeMetricsProvider = tradeMetricsProvider;
            return previous;
          },
        ),
        ChangeNotifierProvider<InvestorModeProvider>(
          create: (_) => InvestorModeProvider(),
        ),
      ],
      child: MaterialApp(
        title: kAppName,
        navigatorKey: NavigationService.navigatorKey,
        theme: ThemeData(
          // Seeded from the active brand so Material-generated colours
          // (selection handles, ripples, date pickers) follow the flavour.
          colorScheme: ColorScheme.fromSeed(seedColor: kBrandPrimary),
          fontFamily: kFontFamily,
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        // Every phone's own font-size / display-size setting used to scale
        // all text unbounded, so the same screen looked fine on one device
        // and cramped on another (4-5 watchlist rows, names cut to "…").
        // Clamped to 0.9-1.1x: users on "large text" still get slightly
        // larger text, but dense trading layouts can't blow apart.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.1,
              ),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const InitialScreen(),
        routes: {
          '/login': (context) => const LoginPage(),
        },
      ),
    );
  }
}
