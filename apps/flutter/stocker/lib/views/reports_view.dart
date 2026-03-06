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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back,
                        size: 24, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Reports',
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

            // Balance card
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

            // Reports List
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _buildReportItem(
                        context, 'Account Summary', Icons.account_balance,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Profit & Loss', Icons.trending_up,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Generate PDF', Icons.picture_as_pdf,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Weekly Admin Report', Icons.calendar_today,
                        showBorder: true),
                    _buildReportItem(context, 'Intraday History', Icons.history,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Upperwise Open Position', Icons.open_in_new,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Script Qty Details', Icons.list_alt,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Deleted Trades', Icons.delete_outline,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Rejection Log History', Icons.error_outline,
                        showBorder: false),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportItem(BuildContext context, String title, IconData icon,
      {required bool showBorder}) {
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
            MaterialPageRoute(
                builder: (context) => const IntradayHistoryView()),
          );
        } else if (title == 'Upperwise Open Position') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const UpperwisePositionView()),
          );
        } else if (title == 'Script Qty Details') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const ScriptQuantityDetailView()),
          );
        } else if (title == 'Deleted Trades') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const DeletedTradeView()),
          );
        } else if (title == 'Rejection Log History') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const RejectionLogHistoryView()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: showBorder
            ? const BoxDecoration(
                border: Border(
                  bottom: BorderSide(width: 1, color: Color(0xFFF1F5F9)),
                ),
              )
            : null,
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
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Color(0xFF8E8E93)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFD1D1D6),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFF22547C),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
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
