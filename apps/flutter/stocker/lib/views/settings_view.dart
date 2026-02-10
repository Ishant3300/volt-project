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
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, size: 24, color: Colors.black),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
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

              // Balance card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(10),
                decoration: ShapeDecoration(
                  color: const Color(0xFF22547C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Credit: 50,000',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Text(
                      'Balance: 25,251.50',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Menu items
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    _buildMenuItem(context, Icons.access_time, 'Market Hours'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.format_list_numbered, 'Set Quantity Values'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.lock, 'Change Password'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.notifications, 'Notification'),
                    _buildDivider(),
                    _buildMenuItem(context, Icons.privacy_tip, 'Privacy Policy'),
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
            MaterialPageRoute(builder: (context) => const SetQuantityValuesView()),
          );
        } else if (title == 'Change Password') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ChangePasswordView()),
          );
        } else if (title == 'Notification') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NotificationSettingsView()),
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
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: Colors.black),
                SizedBox(width: 16),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            Icon(Icons.chevron_right, size: 24, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(height: 1, color: const Color(0xFFC7C7CC), indent: 16, endIndent: 16);
  }
}
