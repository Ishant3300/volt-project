import 'package:flutter/material.dart';
import 'send_message_view.dart';
import 'manage_reports_view.dart';
import 'trade_margin_settings_view.dart';
import 'brokerage_settings_view.dart';
import 'group_quantity_view.dart';
import 'script_quantity_settings_view.dart';
import 'fresh_stoploss_limit_view.dart';
import '../utils/contants.dart';

class AdminSettingsView extends StatelessWidget {
  const AdminSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
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
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.arrow_back,
                            color: Colors.black, size: kIconSizeMedium),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Admin Settings',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeViewTitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ],
                ),
              ),

              // Management section
              _sectionLabel('MANAGEMENT'),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    _settingRow(context, Icons.mail_outline, 'Send Message',
                        () => _push(context, const SendMessageView())),
                    _divider(),
                    _settingRow(context, Icons.description_outlined, 'Manage Reports',
                        () => _push(context, const ManageReportsView()), isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Settings section
              _sectionLabel('SETTINGS'),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    _settingRow(context, Icons.grid_view_rounded, 'Group Quantity',
                        () => _push(context, const GroupQuantityView())),
                    _divider(),
                    _settingRow(context, Icons.list_alt_outlined, 'Script Quantity',
                        () => _push(context, const ScriptQuantitySettingsView())),
                    _divider(),
                    _settingRow(context, Icons.tune_outlined, 'Brokerage Settings',
                        () => _push(context, const BrokerageSettingsView())),
                    _divider(),
                    _settingRow(context, Icons.trending_up_outlined, 'Trade Margin',
                        () => _push(context, const TradeMarginSettingsView())),
                    _divider(),
                    _settingRow(context, Icons.shield_outlined, 'Fresh Stop-Loss Limits',
                        () => _push(context, const FreshStoplossLimitView()), isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  static Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: kFontSizeNavLabel,
          fontFamily: 'Inter',
          fontWeight: kFontWeightSemiBold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  static Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  static Widget _divider() {
    return const Divider(height: 1, color: Color(0xFFF1F5F9));
  }

  static Widget _settingRow(
      BuildContext context, IconData icon, String label, VoidCallback onTap,
      {bool isLast = false}) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Container(
                  width: kMenuIconCircleSize,
                  height: kMenuIconCircleSize,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(icon, size: kMenuIconSize, color: const Color(0xFF1E3A8A)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: kFontSizeMenuItem,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: kMenuChevronSize, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}
