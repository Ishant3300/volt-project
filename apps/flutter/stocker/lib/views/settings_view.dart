import 'package:flutter/material.dart';
import '../utils/contants.dart';
import '../widgets/brand_menu_row.dart';
import 'market_hours_view.dart';
import 'set_quantity_values.dart';
import 'change_password_view.dart';
import 'notification_settings_view.dart';
import 'terms_view.dart';
import 'webview_page.dart';

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
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.black, size: kIconSizeMedium),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Settings',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: kFontSizePageTitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightBold,
                        letterSpacing: -0.5,
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
                    _buildMenuItem(context, kIconMarketHours, 'Market Hours'),
                    _buildDivider(),
                    _buildMenuItem(
                        context, kIconSetQuantityValues, 'Set Quantity Values'),
                    _buildDivider(),
                    _buildMenuItem(
                        context, kIconChangePassword, 'Change Password'),
                    _buildDivider(),
                    _buildMenuItem(context, kIconNotifications, 'Notification'),
                    _buildDivider(),
                    _buildMenuItem(
                        context, kIconPrivacyPolicy, 'Privacy Policy'),
                    _buildDivider(),
                    _buildMenuItem(
                        context, kIconTermsOfUse, 'Rules And Regulations'),
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

  Widget _buildMenuItem(BuildContext context, String svgPath, String title) {
    return BrandMenuRow(
      label: title,
      svgPath: svgPath,
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
            MaterialPageRoute(
                builder: (context) => const WebViewPage(
                    url: 'https://apexlive.framer.website/privacy',
                    title: 'Privacy Policy')),
          );
        } else if (title == 'Rules And Regulations') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TermsView()),
          );
        }
      },
    );
  }

  Widget _buildDivider() {
    return const Divider(
        height: 1, color: Color(0xFFF1F5F9), indent: 16, endIndent: 16);
  }
}
