import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/kite_service.dart';
import '../services/sercure_storage_service.dart';
import '../services/pdf_report_service.dart';
import '../utils/contants.dart';
import 'account_summary_view.dart';
import 'profit_and_loss_view.dart';
import 'weekly_admin_view.dart';
import 'intraday_history_view.dart';
import 'userwise_position_view.dart';
import 'script_quantity_detail_view.dart';
import 'deleted_trade_view.dart';
import 'rejection_log_history_view.dart';

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isUser =
        Provider.of<UserProfileProvider>(context, listen: false).isUser;

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
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Reports',
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
                        context, 'Account Summary', kIconAccountSummary,
                        showBorder: true),
                    if (!isUser)
                      _buildReportItem(
                          context, 'Profit & Loss', kIconProfitAndLoss,
                          showBorder: true),
                    _buildReportItem(
                        context, 'Generate PDF', kIconGeneratePdf,
                        showBorder: true),
                    if (!isUser)
                      _buildReportItem(
                          context, 'Weekly Admin Report', kIconWeeklyAdminReport,
                          showBorder: true),
                    _buildReportItem(context, 'Intraday History', kIconIntradayHistory,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Userwise Open Position', kIconUserwisePosition,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Script Qty Details', kIconScriptQtyDetails,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Deleted Trades', kIconDeletedTrades,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Rejection Log History', kIconRejectionLogHistory,
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

  Widget _buildReportItem(BuildContext context, String title, String svgPath,
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
        } else if (title == 'Userwise Open Position') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const UserwisePositionView()),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
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
                  width: kMenuIconCircleSize,
                  height: kMenuIconCircleSize,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: SvgPicture.asset(
                      svgPath,
                      width: kMenuIconSize,
                      height: kMenuIconSize,
                      colorFilter: const ColorFilter.mode(Color(0xFF1E3A8A), BlendMode.srcIn),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: kFontSizeMenuItem,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightMedium,
                  ),
                ),
              ],
            ),
            const Icon(Icons.chevron_right, size: kMenuChevronSize, color: Color(0xFF94A3B8)),
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

class GeneratePdfBottomSheet extends StatefulWidget {
  final String? preselectedUserId;
  final String? preselectedUserName;

  const GeneratePdfBottomSheet(
      {super.key, this.preselectedUserId, this.preselectedUserName});

  @override
  State<GeneratePdfBottomSheet> createState() => _GeneratePdfBottomSheetState();
}

class _GeneratePdfBottomSheetState extends State<GeneratePdfBottomSheet> {
  DateTime? _fromDate;
  DateTime? _toDate;
  int _selectedMode = 0; // 0 = Default, 1 = Advanced
  bool _isLoading = false;
  bool _isUser = true;

  // User selection (admin/master only)
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  Map<String, dynamic>? _selectedUser;
  bool _showUserDropdown = false;
  final _userSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    _isUser = profile.isUser;
    if (widget.preselectedUserId != null) {
      _selectedUser = {
        'id': widget.preselectedUserId,
        'name': widget.preselectedUserName ?? '',
        'username': widget.preselectedUserName ?? ''
      };
    } else if (!_isUser) {
      _fetchUsers();
    }
    _userSearchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final q = _userSearchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filteredUsers = List.from(_users);
      } else {
        _filteredUsers = _users.where((u) {
          final name = (u['name'] ?? '').toString().toLowerCase();
          final username = (u['username'] ?? '').toString().toLowerCase();
          return name.contains(q) || username.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _fetchUsers() async {
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final api = ApiService(backendUrl);
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      final endpoint = profile.isAdmin
          ? '/admin/users?limit=500'
          : '/master/users?limit=500';
      final res = await api.get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final nested = body['data'];
        final List list =
            nested is Map ? (nested['users'] ?? []) : (nested ?? []);
        setState(() {
          _users = list.cast<Map<String, dynamic>>();
          _filteredUsers = List.from(_users);
        });
      }
    } catch (_) {}
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? now) : (_toDate ?? now),
      firstDate: DateTime(2024),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFF3F45C7)),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom)
          _fromDate = picked;
        else
          _toDate = picked;
      });
    }
  }

  Future<void> _showPdfOptionsSheet(BuildContext context, Uint8List bytes, {required String userName}) async {
    final dateFmt = DateFormat('ddMMyyyy');
    final fileName = '${userName.replaceAll(' ', '_')}_${dateFmt.format(_fromDate!)}_${dateFmt.format(_toDate!)}.pdf';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 24, left: 24, right: 24,
          bottom: 24 + MediaQuery.of(ctx).viewPadding.bottom,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PDF Generated',
                style: TextStyle(fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightBold, color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            Text(fileName,
                style: const TextStyle(fontSize: kFontSizeSubtitle, fontFamily: 'Inter', color: Color(0xFF94A3B8))),
            const SizedBox(height: 24),
            Row(
              children: [
                // Download/Print button
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      await Printing.layoutPdf(onLayout: (_) => bytes);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.download_rounded, size: 28, color: Color(0xFF3F45C7)),
                          SizedBox(height: 6),
                          Text('Download', style: TextStyle(fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, color: Color(0xFF3F45C7))),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Share button
                Expanded(
                  child: GestureDetector(
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        final dir = await getTemporaryDirectory();
                        final file = File('${dir.path}/$fileName');
                        await file.writeAsBytes(bytes);
                        await Share.shareXFiles(
                          [XFile(file.path)],
                          text: 'Trade Report - $userName',
                        );
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Share failed: $e'), backgroundColor: Colors.red),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.share_rounded, size: 28, color: Color(0xFF10B981)),
                          SizedBox(height: 6),
                          Text('Share', style: TextStyle(fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, color: Color(0xFF10B981))),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePdf() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both From and To dates')),
      );
      return;
    }
    final from = _fromDate!.toIso8601String().split('T')[0];
    final to = _toDate!.toIso8601String().split('T')[0];

    setState(() => _isLoading = true);
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final api = ApiService(backendUrl);
      String url = '/trade/report?from=$from&to=$to';
      if (_selectedUser != null) {
        final uid = _selectedUser!['id'] ?? _selectedUser!['_id'] ?? '';
        url += '&user_id=$uid';
      }
      final res = await api.get(url, token: token);

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          Map<String, dynamic> reportData = body['data'];

          // For Live M2M mode, enrich with live positions client-side
          if (_selectedMode == 1) {
            reportData = await _enrichWithLivePositions(reportData, api, token);
          }

          final pdf = _selectedMode == 0
              ? PdfReportService.generateDefaultReport(reportData)
              : PdfReportService.generateAdvancedReport(reportData);
          final bytes = await pdf.save();

          if (!mounted) return;
          Navigator.pop(context); // dismiss loading

          // Show options: Download or Share
          await _showPdfOptionsSheet(context, bytes, userName: reportData['user_name'] ?? 'Report');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(body['message'] ?? 'Failed to fetch report')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Walk through each instrument's all_trades to find open positions,
  /// fetch live prices, and inject LIVE rows + carry_forward entries.
  Future<Map<String, dynamic>> _enrichWithLivePositions(
    Map<String, dynamic> reportData,
    ApiService api,
    String? token,
  ) async {
    final kite = KiteService(api);
    final instruments = List<Map<String, dynamic>>.from(
      (reportData['instruments'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? [],
    );
    final List<Map<String, dynamic>> carryForward = [];
    double totalLivePnlAdjustment = 0;

    for (int i = 0; i < instruments.length; i++) {
      final instr = Map<String, dynamic>.from(instruments[i]);
      final allTrades = List<Map<String, dynamic>>.from(
        (instr['all_trades'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? [],
      );
      final exchange = (instr['exchange'] ?? '').toString();
      final symbol = (instr['tradingsymbol'] ?? '').toString();

      // Compute net open position by walking trades chronologically
      double netQty = 0;
      double totalBuyQty = 0;
      double totalBuyValue = 0;
      double totalSellQty = 0;
      double totalSellValue = 0;

      for (final t in allTrades) {
        final type = (t['type'] ?? '').toString().toUpperCase();
        final bQty = (t['buy_qty'] as num?)?.toDouble() ?? 0;
        final sQty = (t['sell_qty'] as num?)?.toDouble() ?? 0;
        final rate = (t['rate'] as num?)?.toDouble() ?? 0;

        if (type == 'BUY') {
          netQty += bQty;
          totalBuyQty += bQty;
          totalBuyValue += bQty * rate;
        } else if (type == 'SELL') {
          netQty -= sQty;
          totalSellQty += sQty;
          totalSellValue += sQty * rate;
        }
      }

      // If there's an open position, fetch live price and inject LIVE row
      if (netQty.abs() > 0.001) {
        double? livePrice;

        try {
          // Search for instrument to get token
          final searchResults = await kite.searchInstruments(
            symbol,
            exchange: exchange,
            limit: 5,
          );

          String? instrumentToken;
          for (final result in searchResults) {
            final rSymbol = (result['tradingsymbol'] ?? '').toString();
            final rExchange = (result['exchange'] ?? '').toString();
            if (rSymbol == symbol && rExchange == exchange) {
              instrumentToken = (result['instrument_token'] ?? '').toString();
              break;
            }
          }

          if (instrumentToken != null && instrumentToken.isNotEmpty) {
            final depth = await kite.getMarketDepth(instrumentToken);
            if (depth != null) {
              livePrice = depth.lastPrice;
            }
          }
        } catch (e) {
          log('⚠️ Could not fetch live price for $symbol: $e');
        }

        if (livePrice != null) {
          final now = DateTime.now();
          final bool isLong = netQty > 0;
          final double openQty = netQty.abs();
          final double avgEntryPrice = isLong
              ? (totalBuyQty > 0 ? totalBuyValue / totalBuyQty : 0)
              : (totalSellQty > 0 ? totalSellValue / totalSellQty : 0);

          // Unrealized P&L: for long = (livePrice - avgBuy) * qty
          //                  for short = (avgSell - livePrice) * qty
          final double unrealizedPnl = isLong
              ? (livePrice - avgEntryPrice) * openQty
              : (avgEntryPrice - livePrice) * openQty;

          // Inject LIVE row into all_trades
          final liveRow = {
            'date': now.toIso8601String(),
            'type': 'LIVE',
            'buy_qty': isLong ? 0 : openQty,
            'sell_qty': isLong ? openQty : 0,
            'rate': livePrice,
            'brokerage': 0,
            'net': unrealizedPnl,
          };
          allTrades.add(liveRow);

          // Update instrument totals to include the LIVE virtual close
          if (isLong) {
            instr['total_sell_qty'] = ((instr['total_sell_qty'] as num?)?.toDouble() ?? 0) + openQty;
          } else {
            instr['total_buy_qty'] = ((instr['total_buy_qty'] as num?)?.toDouble() ?? 0) + openQty;
          }

          // Adjust P&L to include unrealized
          final existingPnl = (instr['pnl'] as num?)?.toDouble() ?? 0;
          final existingBrokerage = (instr['brokerage'] as num?)?.toDouble() ?? 0;
          instr['pnl'] = existingPnl + unrealizedPnl;
          instr['net_pnl'] = (existingPnl + unrealizedPnl) - existingBrokerage;
          totalLivePnlAdjustment += unrealizedPnl;

          // Add carry forward entry
          carryForward.add({
            'exchange': exchange,
            'tradingsymbol': symbol,
            'type': isLong ? 'Buy' : 'Sell',
            'quantity': openQty,
            'price': avgEntryPrice,
          });
        }
      }

      instr['all_trades'] = allTrades;
      instruments[i] = instr;
    }

    // Update summary totals
    final summary = Map<String, dynamic>.from(reportData['summary'] ?? {});
    if (totalLivePnlAdjustment != 0) {
      final oldTotalPnl = (summary['total_pnl'] as num?)?.toDouble() ?? 0;
      final totalBrokerage = (summary['total_brokerage'] as num?)?.toDouble() ?? 0;
      summary['total_pnl'] = oldTotalPnl + totalLivePnlAdjustment;
      summary['net_pnl'] = (oldTotalPnl + totalLivePnlAdjustment) - totalBrokerage;
    }

    return {
      ...reportData,
      'instruments': instruments,
      'summary': summary,
      'carry_forward': carryForward,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding:
            EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 32 + MediaQuery.of(context).viewPadding.bottom),
        decoration: const ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Generate PDF',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeSheetTitle,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold)),
              const SizedBox(height: 16),

              // Mode selector — layout type only
              const Text('Report Type',
                  style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: kFontSizeSheetLabel,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _modeChip('General', 0),
                  const SizedBox(width: 10),
                  _modeChip('Live M2M', 1),
                ],
              ),
              const SizedBox(height: 12),

              // Date pickers — shown for both modes
              GestureDetector(
                onTap: () => _pickDate(true),
                child: _dateField('From Date',
                    _fromDate != null ? dateFmt.format(_fromDate!) : null),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => _pickDate(false),
                child: _dateField('To Date',
                    _toDate != null ? dateFmt.format(_toDate!) : null),
              ),
              const SizedBox(height: 16),

              // User selector (admin/master only)
              if (!_isUser && widget.preselectedUserId == null) ...[
                const Text('Select User',
                    style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: kFontSizeSheetLabel,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                        letterSpacing: 0.5)),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () =>
                      setState(() => _showUserDropdown = !_showUserDropdown),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFD1D1D6)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _selectedUser != null
                                ? '${_selectedUser!['name'] ?? _selectedUser!['username']} (@${_selectedUser!['username']})'
                                : 'All Users',
                            style: TextStyle(
                              color: _selectedUser != null
                                  ? const Color(0xFF0F172A)
                                  : const Color(0xFF8E8E93),
                              fontSize: kFontSizeSheetBody,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightRegular,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Icon(
                            _showUserDropdown
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            size: 20,
                            color: const Color(0xFF8E8E93)),
                      ],
                    ),
                  ),
                ),
                if (_showUserDropdown) ...[
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFD1D1D6)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: TextField(
                            controller: _userSearchController,
                            style: const TextStyle(
                                fontSize: kFontSizeSheetHint, fontFamily: 'Inter'),
                            decoration: const InputDecoration(
                              hintText: 'Search by name...',
                              hintStyle: TextStyle(
                                  color: Color(0xFFCBD5E1), fontSize: kFontSizeSheetHint),
                              prefixIcon: Icon(Icons.search,
                                  size: 18, color: Color(0xFF94A3B8)),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Color(0xFFF1F5F9))),
                              isDense: true,
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 160),
                          child: ListView(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            children: [
                              // "All Users" option
                              _userOption(null),
                              ..._filteredUsers.map((u) => _userOption(u)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        decoration: ShapeDecoration(
                          color: const Color(0xFFD1D1D6),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('CLEAR',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: kFontSizeButtonText,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading ? null : _generatePdf,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF3F45C7),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isLoading
                            ? const Center(
                                child: SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2)))
                            : const Text('VIEW',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: kFontSizeButtonText,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _userOption(Map<String, dynamic>? user) {
    final selectedId = _selectedUser?['id'] ?? _selectedUser?['_id'];
    final userId = user?['id'] ?? user?['_id'];
    final isSelected =
        user == null ? _selectedUser == null : selectedId == userId;
    final label = user == null
        ? 'All Users'
        : '${user['name'] ?? user['username']} (@${user['username']})';
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedUser = user;
          _showUserDropdown = false;
          _userSearchController.clear();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFF1F5F9) : Colors.white,
          border: const Border(
              bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.5)),
        ),
        child: Text(label,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFF3F45C7)
                  : const Color(0xFF1E293B),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: isSelected ? kFontWeightSemiBold : kFontWeightRegular,
            )),
      ),
    );
  }

  Widget _dateField(String hint, String? value) {
    return Container(
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
          Text(
            value ?? hint,
            style: TextStyle(
              color: value != null
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF8E8E93),
              fontSize: 15,
              fontFamily: 'Inter',
              fontWeight: kFontWeightRegular,
            ),
          ),
          const Icon(Icons.calendar_today, size: 18, color: Colors.black),
        ],
      ),
    );
  }

  Widget _modeChip(String label, int index) {
    final selected = _selectedMode == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedMode = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3F45C7) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  selected ? const Color(0xFF3F45C7) : const Color(0xFFD1D1D6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF64748B),
            fontSize: 13,
            fontFamily: 'Inter',
            fontWeight: kFontWeightSemiBold,
          ),
        ),
      ),
    );
  }
}
