import 'package:flutter/material.dart';
import 'market_hours_view.dart';
import 'set_quantity_values.dart';
import 'change_password_view.dart';
import 'notification_settings_view.dart';
import 'privacy_view.dart';
import 'terms_view.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.arrow_back,
                          size: 24, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Settings',
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
              ),

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
                    const Icon(Icons.shield,
                        color: Color(0xFFEF4444), size: 20),
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

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(14),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BALANCE',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '25,251.50',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 48,
                      color: const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'CREDIT',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '50,000.00',
                            style: TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 20,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildMenuItem(context, Icons.access_time, 'Market Hours'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.format_list_numbered,
                        'Set Quantity Values'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.lock, 'Change Password'),
                    _buildDivider(),
                    _buildMenuItem(
                        context, Icons.notifications, 'Notification'),
                    _buildDivider(),
                    _buildMenuItem(
                        context, Icons.privacy_tip, 'Privacy Policy'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.description, 'Terms of Use'),
                  ],
                ),
              ),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, IconData icon, String title) {
    return GestureDetector(
      onTap: () {
        if (title == 'Market Hours') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const MarketHoursView()),
          );
        } else if (title == 'Set Quantity Values') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const SetQuantityValuesView()),
          );
        } else if (title == 'Change Password') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ChangePasswordView()),
          );
        } else if (title == 'Notification') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const NotificationSettingsView()),
          );
        } else if (title == 'Privacy Policy') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const PrivacyView()),
          );
        } else if (title == 'Terms of Use') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TermsView()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(icon, size: 16, color: const Color(0xFF1E3A8A)),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Icon(Icons.chevron_right, size: 24, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return const Divider(
        height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16);
  }
}
