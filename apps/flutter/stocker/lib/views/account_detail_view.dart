import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/date_formatter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class AccountDetailView extends StatefulWidget {
  const AccountDetailView({super.key});

  @override
  State<AccountDetailView> createState() => _AccountDetailViewState();
}

class _AccountDetailViewState extends State<AccountDetailView> {
  String _deviceName = 'Loading...';
  String _deviceVersion = 'Loading...';
  String _appVersion = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadDeviceInfo();
    _loadAppVersion();
  }

  Future<void> _loadDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _deviceName = androidInfo.model;
          _deviceVersion = 'Android ${androidInfo.version.release}';
        });
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        setState(() {
          _deviceName = iosInfo.model;
          _deviceVersion = 'iOS ${iosInfo.systemVersion}';
        });
      }
    } catch (e) {
      setState(() {
        _deviceName = 'Unknown';
        _deviceVersion = 'Unknown';
      });
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    } catch (e) {
      setState(() {
        _appVersion = 'Unknown';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back,
                            size: 24, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Account Detail',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 24,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Security notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: const Color(0xFFFEF2F2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'All profile running in this app is secure. The new security features are active.',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Account details card
            Consumer<UserProfileProvider>(
              builder: (context, profileProvider, child) {
                final role = profileProvider.role;
                final username = profileProvider.master?.username ??
                    profileProvider.user?.username ??
                    'N/A';
                final serverId = profileProvider.master?.serverId ??
                    profileProvider.user?.serverId ??
                    'N/A';
                final lastLogin = profileProvider.master?.lastLogin ??
                    profileProvider.user?.lastLogin;
                final createdAt = profileProvider.master?.createdAt ??
                    profileProvider.user?.createdAt;

                return Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      side:
                          const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildDetailRow('Role', role ?? 'N/A', true),
                      _buildDetailRow('Username', username, true),
                      _buildDetailRow('Server ID', serverId, true),
                      if (createdAt != null)
                        _buildDetailRow('Created Date',
                            DateFormatter.formatDateTime(createdAt), true),
                      _buildDetailRow('Device Name', _deviceName, true),
                      _buildDetailRow('Device Version', _deviceVersion, true),
                      _buildDetailRow(
                          'Last Logged',
                          lastLogin != null
                              ? DateFormatter.formatDateTime(lastLogin)
                              : 'Never',
                          true),
                      _buildDetailRow('App Version', _appVersion, false),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool showBorder) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: showBorder
            ? const Border(
                bottom: BorderSide(width: 1, color: Color(0xFFF1F5F9)),
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
