import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:stocker/config/app_brand.dart';

/// App version and phone model, read once at start-up. Sent as the User-Agent
/// on every API call, so login history, the watchdog's login alerts and crash
/// reports show which phone and app version — e.g.
/// `Volt/1.0.51+54 (Android 14; samsung SM-A546E) Dart/3`. "Dart/" stays in
/// it: the backend/watchdog already read that as "the app".
class AppIdentity {
  static String version = '';
  static String device = '';
  static String userAgent = '';

  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    var os = '';
    try {
      final plugin = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final a = await plugin.androidInfo;
        device = '${a.manufacturer} ${a.model}'.trim();
        os = 'Android ${a.version.release}';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final i = await plugin.iosInfo;
        device = i.utsname.machine; // e.g. iPhone15,2
        os = 'iOS ${i.systemVersion}';
      }
    } catch (_) {}
    final brand = kIsBolt ? 'Bolt' : kIsVolt ? 'Volt' : 'Apex';
    userAgent = _ascii('$brand/$version (${[os, device].where((s) => s.isNotEmpty).join('; ')}) Dart/3');
  }

  // Header values must be printable ASCII.
  static String _ascii(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
}
