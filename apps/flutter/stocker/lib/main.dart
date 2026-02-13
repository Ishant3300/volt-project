import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/services/admin_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/services/kite_service.dart';
import 'package:stocker/services/navigation_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/pages/login_page.dart';
import 'initial_sheet.dart';
import 'dart:developer';

void main() {
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
        ProxyProvider<ApiService, KiteService>(
          update: (_, apiService, __) {
            log('   Creating KiteService');
            return KiteService(apiService);
          },
        ),
        ChangeNotifierProvider<WatchlistProvider>(
          create: (_) {
            log('   Creating WatchlistProvider');
            return WatchlistProvider();
          },
        ),
      ],
      child: MaterialApp(
        title: 'Stocker',
        navigatorKey: NavigationService.navigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const InitialScreen(),
        routes: {
          '/login': (context) => const LoginPage(),
        },
      ),
    );
  }
}
