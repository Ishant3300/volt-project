import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/services/admin_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/services/user_service.dart';
import 'package:stocker/services/kite_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:stocker/services/firebase_service.dart';
import 'package:stocker/firebase_options.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/pages/login_page.dart';
import 'initial_sheet.dart';
import 'dart:developer';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await FirebaseService().init();
  log('🚀 Starting Stocker App');
  log('   Backend URL: $backendUrl');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    log('🏗️ Building MyApp');
    return MultiProvider(
      providers: [
        Provider<ApiService>(
          create: (_) {
            log('   Creating ApiService with URL: $backendUrl');
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
      ],
      child: MaterialApp(
        title: 'APEX',
        navigatorKey: NavigationService.navigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        debugShowCheckedModeBanner: false,
        home: const InitialScreen(),
        routes: {
          '/login': (context) => const LoginPage(),
        },
      ),
    );
  }
}
