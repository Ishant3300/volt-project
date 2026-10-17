import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:stocker/services/app_identity.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

/// Sends uncaught app errors to POST /api/auth/client-events
/// (source 'app', kind 'crash') — before, they were only printed on the
/// phone and never seen. Fire-and-forget, never throws. Each distinct error
/// is sent once per app run, at most 20 per run; layout-overflow warnings
/// are not crashes and are skipped.
class CrashReporter {
  static final Set<String> _seen = {};
  static int _sent = 0;
  static const int _maxPerRun = 20;

  static void install() {
    FlutterError.onError = (details) {
      debugPrint('🔴 FLUTTER ERROR: ${details.exception}');
      debugPrint('🔴 STACK: ${details.stack}');
      if (details.silent || details.exception.toString().contains('overflowed')) return;
      report(details.exception, details.stack, where: details.library ?? 'flutter');
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('🔴 UNCAUGHT: $error');
      report(error, stack, where: 'async');
      return true; // handled — same as before: logged, app keeps running
    };
  }

  static Future<void> report(Object error, StackTrace? stack, {String where = ''}) async {
    try {
      final message = error.toString();
      final frames = (stack?.toString() ?? '')
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .take(6)
          .toList();
      final key = '$message|${frames.take(2).join('|')}';
      if (_seen.contains(key) || _sent >= _maxPerRun) return;
      _seen.add(key);
      _sent++;

      final context = <String, Object>{
        'where': where,
        'error_type': error.runtimeType.toString(),
        'platform': defaultTargetPlatform.name,
        if (AppIdentity.device.isNotEmpty) 'device': AppIdentity.device,
      };
      for (var i = 0; i < frames.length; i++) {
        context['stack_$i'] = frames[i];
      }
      String? token;
      try {
        token = await SecureStorageService().getToken();
      } catch (_) {}
      await http
          .post(
            Uri.parse('$backendUrl/api/auth/client-events'),
            headers: {
              'Content-Type': 'application/json',
              if (AppIdentity.userAgent.isNotEmpty) 'User-Agent': AppIdentity.userAgent,
              if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'events': [
                {
                  'source': 'app',
                  'kind': 'crash',
                  'code': error.runtimeType.toString(),
                  'message': message,
                  'page': where,
                  'context': context,
                  'version': AppIdentity.version,
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }
}
