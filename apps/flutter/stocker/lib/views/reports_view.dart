import 'package:flutter/material.dart';
import 'account_summary_view.dart';
import 'profit_and_loss_view.dart';
import 'weekly_admin_view.dart';
import 'intraday_history_view.dart';
import 'upperwise_position_view.dart';
import 'script_quantity_detail_view.dart';
import 'deleted_trade_view.dart';
import 'rejection_log_history_view.dart';

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

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
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Reports',
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

            // Reports List
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Column(
                  children: [
                    _buildReportItem(context, 'Account Summary', Icons.account_balance, showBorder: true),
                    _buildReportItem(context, 'Profit & Loss', Icons.trending_up, showBorder: true),
                    _buildReportItem(context, 'Generate PDF', Icons.picture_as_pdf, showBorder: true),
                    _buildReportItem(context, 'Weekly Admin Report', Icons.calendar_today, showBorder: true),
                    _buildReportItem(context, 'Intraday History', Icons.history, showBorder: true),
                    _buildReportItem(context, 'Upperwise Open Position', Icons.open_in_new, showBorder: true),
                    _buildReportItem(context, 'Script Qty Details', Icons.list_alt, showBorder: true),
                    _buildReportItem(context, 'Deleted Trades', Icons.delete_outline, showBorder: true),
                    _buildReportItem(context, 'Rejection Log History', Icons.error_outline, showBorder: false),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportItem(BuildContext context, String title, IconData icon, {required bool showBorder}) {
    return GestureDetector(
      onTap: () {
        if (title == 'Account Summary') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AccountSummaryView()),
          );
        } else if (title == 'Profit & Loss') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ProfitAndLossView()),
          );
        } else if (title == 'Generate PDF') {
          _showGeneratePdfBottomSheet(context);
        } else if (title == 'Weekly Admin Report') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const WeeklyAdminView()),
          );
        } else if (title == 'Intraday History') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const IntradayHistoryView()),
          );
        } else if (title == 'Upperwise Open Position') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UpperwisePositionView()),
          );
        } else if (title == 'Script Qty Details') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ScriptQuantityDetailView()),
          );
        } else if (title == 'Deleted Trades') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DeletedTradeView()),
          );
        } else if (title == 'Rejection Log History') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RejectionLogHistoryView()),
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
            Icon(Icons.chevron_right, size: 24, color: Colors.black),
          ],
        ),
      ),
    );
  }

  void _showGeneratePdfBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const GeneratePdfBottomSheet(),
    );
  }
}

class GeneratePdfBottomSheet extends StatelessWidget {
  const GeneratePdfBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        top: 24,
        left: 16,
        right: 16,
        bottom: 56,
      ),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text(
            'Generate PDF',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          // From - To Date field
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'From - To Date',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Icon(Icons.calendar_today, size: 20, color: Colors.black),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Select User dropdown
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select User',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Clear logic
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFD1D1D6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'CLEAR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Generate PDF logic
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFF22547C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
                      'VIEW',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
