import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/services/admin_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/utils/contants.dart';
import 'initial_sheet.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiService>(
          create: (_) => ApiService(backendUrl),
        ),
        ProxyProvider<ApiService, AuthService>(
          update: (_, apiService, __) => AuthService(apiService),
        ),
        ProxyProvider<ApiService, AdminService>(
          update: (_, apiService, __) => AdminService(apiService),
        ),
      ],
      child: MaterialApp(
        title: 'Stocker',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const InitialScreen(),
      ),
    );
  }
}
