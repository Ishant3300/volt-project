import 'package:flutter/material.dart';
import 'edit_user_view.dart';
import 'credit_debit_bottom_sheet.dart';
import 'group_quantity_view.dart';
import 'margin_squareoff_bottom_sheet.dart';
import 'brokerage_settings_view.dart';
import 'intraday_squareoff_bottom_sheet.dart';
import 'trade_margin_settings_view.dart';
import 'script_quantity_settings_view.dart';
import 'sharing_details_view.dart';
import 'rejection_log_history_view.dart';
import 'settlement_report_view.dart';

class UsernameView extends StatefulWidget {
  const UsernameView({super.key});

  @override
  State<UsernameView> createState() => _UsernameViewState();
}

class _UsernameViewState extends State<UsernameView> {
  int _selectedTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
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
                        'Username',
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
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const EditUserView()),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF8E8E93),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Credit/Balance Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: const Color(0xFFE5E5EA),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Credit: 50,000',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    'Balance: 25,251.50',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Tab buttons
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 0 ? const Color(0xFF22547C) : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFF22547C)),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                        ),
                        child: Text(
                          'Overview',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 0 ? Colors.white : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 1 ? const Color(0xFF22547C) : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFF22547C)),
                          ),
                        ),
                        child: Text(
                          'Tradelist',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 1 ? Colors.white : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 2 ? const Color(0xFF22547C) : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFF22547C)),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                        ),
                        child: Text(
                          'Position',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 2 ? Colors.white : Colors.black,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Tab Content
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildOverviewTab()
                  : _selectedTabIndex == 1
                      ? _buildTradelistTab()
                      : _buildPositionTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // User Info Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildInfoRow('Created Date', '01 JAN 2026 11:34:00', showBorder: true),
                _buildInfoRow('Last Login', '01 JAN 2026 11:34:00', showBorder: true),
                _buildInfoRow('IP Address', '165.856.521.120', showBorder: true),
                _buildInfoRow('Exchanges', 'NSE, MCX', showBorder: false),
              ],
            ),
          ),

          SizedBox(height: 24),

          // CONTROL Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CONTROL',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Control Toggles
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildToggleRow('User Status', false),
                SizedBox(height: 16),
                _buildToggleRow('Close Only', true),
                SizedBox(height: 16),
                _buildToggleRow('BET', false),
                SizedBox(height: 16),
                _buildToggleRow('Margin Square Off', true),
                SizedBox(height: 16),
                _buildToggleRow('Fresh Stop-Loss', false),
              ],
            ),
          ),

          SizedBox(height: 24),

          // CONTROL Section 2
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CONTROL',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Settings List
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildSettingRow('Credit/Debit', Icons.account_balance_wallet, showBorder: true),
                _buildSettingRow('Group Quantity Settings', Icons.settings, showBorder: true),
                _buildSettingRow('Margin SquareOff Settings', Icons.settings, showBorder: true),
                _buildSettingRow('Brk Settings', Icons.settings, showBorder: true),
                _buildSettingRow('Intraday SquareOff', Icons.settings, showBorder: true),
                _buildSettingRow('Trade Margin', Icons.settings, showBorder: true),
                _buildSettingRow('Sharing Details', Icons.share, showBorder: true),
                _buildSettingRow('Script Quantity Setting', Icons.settings, showBorder: false),
              ],
            ),
          ),

          SizedBox(height: 24),

          // ACTION Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ACTION',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Action List
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildSettingRow('Change Password', Icons.lock, showBorder: true),
                _buildSettingRow('Rejection Log', Icons.error_outline, showBorder: true),
                _buildSettingRow('Generate PDF', Icons.picture_as_pdf, showBorder: true),
                _buildSettingRow('Settlement Report', Icons.description, showBorder: false),
              ],
            ),
          ),

          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTradelistTab() {
    return Column(
      children: [
        // Search bar
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.search, size: 24, color: const Color(0xFF8E8E93)),
                  SizedBox(width: 10),
                  Text(
                    'Search users',
                    style: TextStyle(
                      color: const Color(0xFF8E8E93),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              Icon(Icons.filter_list, size: 24, color: const Color(0xFF8E8E93)),
            ],
          ),
        ),

        SizedBox(height: 8),

        // Trade list
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            separatorBuilder: (context, index) => SizedBox(height: 2),
            itemBuilder: (context, index) => _buildTradeCard(),
          ),
        ),
      ],
    );
  }

  Widget _buildPositionTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Summary Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'REALISED P&L',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              '0.0',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'M2M P&L',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              '0.0',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'CREDIT',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              '0.0',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'EQUITY',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              '0.0',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'MARGIN USED',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              '0.0',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'FREE MARGIN',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Text(
                              '0.0',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Position Cards
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildPositionCard(isFirst: true),
                _buildPositionCard(isFirst: false),
                _buildPositionCard(isFirst: false, isLast: true),
              ],
            ),
          ),

          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildPositionCard({bool isFirst = false, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
          borderRadius: isFirst
              ? BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                )
              : isLast
                  ? BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    )
                  : BorderRadius.zero,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'BANK NIFTY',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  SizedBox(width: 8),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: ShapeDecoration(
                      color: const Color(0xFFD9D9D9),
                      shape: OvalBorder(),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'JAN 27',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                'BUY: 2500 QTY',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '59854.52',
                style: TextStyle(
                  color: const Color(0xFFFF3B30),
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '2099.5 - 2077.5',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradeCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(Icons.person, size: 24, color: Colors.black),
              SizedBox(height: 4),
              Text(
                'YASH',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'NSE ADANIENT 27 JAN 2026',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF34C759),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text(
                        'Success',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(width: 1, color: const Color(0xFFD1D1D6))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'BUY: 100',
                        style: TextStyle(
                          color: const Color(0xFF22547C),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: const Color(0xFF999999)),
                          SizedBox(width: 4),
                          Text(
                            'JAN 20 | 12:34:12',
                            style: TextStyle(
                              color: const Color(0xFF999999),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {required bool showBorder}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: showBorder
          ? ShapeDecoration(
              shape: RoundedRectangleBorder(
                side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              ),
            )
          : null,
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
          Text(
            value,
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String label, bool isOn) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          width: 40,
          height: 25,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: ShapeDecoration(
            color: isOn ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.50)),
          ),
          child: Align(
            alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 23,
              height: 23,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: OvalBorder(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingRow(String label, IconData icon, {required bool showBorder}) {
    return GestureDetector(
      onTap: () {
        if (label == 'Credit/Debit') {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const CreditDebitBottomSheet(),
          );
        } else if (label == 'Group Quantity Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const GroupQuantityView()),
          );
        } else if (label == 'Margin SquareOff Settings') {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const MarginSquareoffBottomSheet(),
          );
        } else if (label == 'Brk Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const BrokerageSettingsView()),
          );
        } else if (label == 'Intraday SquareOff') {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => const IntradaySquareoffBottomSheet(),
          );
        } else if (label == 'Trade Margin') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const TradeMarginSettingsView()),
          );
        } else if (label == 'Script Quantity Setting') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ScriptQuantitySettingsView()),
          );
        } else if (label == 'Sharing Details') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SharingDetailsView()),
          );
        } else if (label == 'Rejection Log') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RejectionLogHistoryView()),
          );
        } else if (label == 'Settlement Report') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SettlementReportView()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: showBorder
            ? ShapeDecoration(
                shape: RoundedRectangleBorder(
                  side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                ),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: Colors.black),
                SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            Icon(Icons.chevron_right, size: 24, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
