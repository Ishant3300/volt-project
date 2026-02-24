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
              padding: const EdgeInsets.all(17),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Account Detail',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: Colors.black),
                  ),
                ],
              ),
            ),

            // Security notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: ShapeDecoration(
                color: const Color(0x19FF3B30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, color: const Color(0xFFFF3B30), size: 18),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'All profile running in this app is secure. The new',
                      style: TextStyle(
                        color: const Color(0xFFFF3B30),
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

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
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow('Role', role ?? 'N/A', true),
                      _buildDetailRow('Username', username, true),
                      _buildDetailRow('Server ID', serverId, true),
                      if (createdAt != null)
                        _buildDetailRow('Created Date', DateFormatter.formatDateTime(createdAt), true),
                      _buildDetailRow('Device Name', _deviceName, true),
                      _buildDetailRow('Device Version', _deviceVersion, true),
                      _buildDetailRow('Last Logged', 
                        lastLogin != null ? DateFormatter.formatDateTime(lastLogin) : 'Never', 
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
