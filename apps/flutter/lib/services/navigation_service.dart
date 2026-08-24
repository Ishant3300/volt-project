import 'package:flutter/material.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> navigateToLogin() async {
    final context = navigatorKey.currentContext;
    if (context != null) {
      // Clear all routes and navigate to login
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  static BuildContext? get currentContext => navigatorKey.currentContext;
}
