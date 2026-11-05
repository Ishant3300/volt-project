import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/contants.dart';

/// Result of a version check — null from [UpdateCheckService.check] means
/// either the installed build is already current, or the check itself
/// failed (e.g. no network) — deliberately fail-open so a flaky connection
/// on launch never blocks the app.
class UpdateInfo {
  final int latestBuild;
  final String apkUrl;
  /// iPhone: the App Store page to update from (no APK download on iOS).
  final String? storeUrl;
  const UpdateInfo({required this.latestBuild, required this.apkUrl, this.storeUrl});
}

/// Compares the installed build number against `<brand>-version.json`,
/// hosted as a static file on the backend and overwritten by the deploy
/// script every time a new APK is built — see deploy/flutter-build-*.sh.
/// No dedicated backend endpoint needed for this: it's a plain static file
/// fetch, checked once per app cold-start (see InitialScreen).
class UpdateCheckService {
  Future<UpdateInfo?> check() async {
    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    if (defaultTargetPlatform != TargetPlatform.android && !isIos) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(info.buildNumber) ?? 0;

      final response = await http
          .get(Uri.parse('$kLiveBackendUrl/downloads/$kBrandId-version.json'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        log('⚠️ [UpdateCheck] version.json fetch failed: ${response.statusCode}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      // iPhone (5 Nov 2026): every iOS release is a force update too — the file's
      // ios_build is raised once the new version is live on the App Store, and
      // older builds are sent to the App Store page (ios_url).
      if (isIos) {
        final iosBuild = (body['ios_build'] as num?)?.toInt();
        final iosUrl = body['ios_url'] as String?;
        if (iosBuild == null || iosUrl == null || iosBuild <= installedBuild) return null;
        return UpdateInfo(latestBuild: iosBuild, apkUrl: '', storeUrl: iosUrl);
      }
      final latestBuild = body['build'] as int;
      final apkUrl = body['apk_url'] as String;

      if (latestBuild <= installedBuild) return null;
      return UpdateInfo(latestBuild: latestBuild, apkUrl: apkUrl);
    } catch (e) {
      log('⚠️ [UpdateCheck] check failed, skipping: $e');
      return null;
    }
  }
}
