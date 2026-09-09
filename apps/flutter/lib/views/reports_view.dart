import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import '../widgets/brand_menu_row.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
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
import 'settlement_report_view.dart';
import 'client_pnl_summary_view.dart';

class ReportsView extends StatelessWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final isUser = profile.isUser;
    final perms = profile.reportPermissions;

    // Build the list of report items based on permissions
    final reportItems = <_ReportItemData>[];

    if (perms['account_summary'] == true) {
      reportItems.add(_ReportItemData('Account Summary', kIconAccountSummary));
    }
    if (perms['pnl_summary'] == true && !isUser) {
      reportItems.add(_ReportItemData('Profit & Loss', kIconProfitAndLoss));
    }
    if (perms['client_summary'] == true && !isUser) {
      reportItems.add(_ReportItemData('Client Summary', kIconProfitAndLoss));
    }
    if (perms['generate_pdf'] == true) {
      reportItems.add(_ReportItemData('Generate PDF', kIconGeneratePdf));
    }
    if (perms['weekly_admin'] == true && !isUser) {
      reportItems
          .add(_ReportItemData('Weekly Admin Report', kIconWeeklyAdminReport));
    }
    if (perms['settlement_report'] == true && !isUser) {
      reportItems
          .add(_ReportItemData('Settlement Report', kIconWeeklyAdminReport));
    }
    if (perms['intraday_history'] == true) {
      reportItems
          .add(_ReportItemData('Intraday History', kIconIntradayHistory));
    }
    if (perms['userwise_open_position'] == true) {
      reportItems.add(
          _ReportItemData('Userwise Open Position', kIconUserwisePosition));
    }
    if (perms['script_quantity'] == true) {
      reportItems
          .add(_ReportItemData('Script Qty Details', kIconScriptQtyDetails));
    }
    if (perms['deleted_trade'] == true) {
      reportItems.add(_ReportItemData('Deleted Trades', kIconDeletedTrades));
    }
    if (perms['trade_account'] == true) {
      reportItems.add(
          _ReportItemData('Rejection Log History', kIconRejectionLogHistory));
    }

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
                    'Reports',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: kFontSizePageTitle,
                      fontFamily: kFontFamily,
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
              child: reportItems.isEmpty
                  ? const Center(
                      child: Text(
                        'No reports available',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeBody,
                          fontFamily: kFontFamily,
                        ),
                      ),
                    )
                  : Container(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(
                              width: 1, color: Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          for (int i = 0; i < reportItems.length; i++)
                            _buildReportItem(
                              context,
                              reportItems[i].title,
                              reportItems[i].iconPath,
                              showBorder: i < reportItems.length - 1,
                            ),
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
    return BrandMenuRow(
      label: title,
      svgPath: svgPath,
      showBottomBorder: showBorder,
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
        } else if (title == 'Settlement Report') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const SettlementReportView()),
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
        } else if (title == 'Client Summary') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ClientPnlSummaryView()),
          );
        }
      },
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

class _ReportItemData {
  final String title;
  final String iconPath;
  const _ReportItemData(this.title, this.iconPath);
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
          colorScheme: const ColorScheme.light(primary: kBrandPrimary),
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

  Future<void> _showPdfOptionsSheet(BuildContext context, Uint8List bytes,
      {required String userName}) async {
    final dateFmt = DateFormat('ddMMyyyy');
    final fileName =
        '${userName.replaceAll(' ', '_')}_${dateFmt.format(_fromDate!)}_${dateFmt.format(_toDate!)}.pdf';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          top: 24,
          left: 24,
          right: 24,
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
                style: TextStyle(
                    fontSize: kFontSizeViewTitle,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightBold,
                    color: Color(0xFF0F172A))),
            const SizedBox(height: 8),
            Text(fileName,
                style: const TextStyle(
                    fontSize: kFontSizeSubtitle,
                    fontFamily: kFontFamily,
                    color: Color(0xFF94A3B8))),
            const SizedBox(height: 24),
            Row(
              children: [
                // View/Print button — uses in-app PdfPreview (avoids Android print spooler crash)
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      // Capture navigator from ctx BEFORE popping (ctx becomes invalid after pop)
                      final nav = Navigator.of(ctx);
                      Navigator.pop(ctx);
                      nav.push(
                        MaterialPageRoute(
                          builder: (_) => Scaffold(
                            appBar: AppBar(
                              title: Text(
                                fileName,
                                style: const TextStyle(
                                    fontSize: 13, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                              backgroundColor: kBrandPrimary,
                              foregroundColor: Colors.white,
                            ),
                            body: PdfPreview(
                              build: (_) => bytes,
                              allowSharing: true,
                              allowPrinting: true,
                              pdfFileName: fileName,
                              canChangeOrientation: false,
                              canChangePageFormat: false,
                            ),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.picture_as_pdf_rounded,
                              size: 28, color: kBrandPrimary),
                          SizedBox(height: 6),
                          Text('View PDF',
                              style: TextStyle(
                                  fontSize: kFontSizeBody,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightSemiBold,
                                  color: kBrandPrimary)),
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
                        // Financial report PDFs shouldn't linger in app cache
                        // after the share sheet is done with them — a lost/
                        // resold device could otherwise leak old bills from
                        // temp storage indefinitely.
                        try {
                          if (await file.exists()) await file.delete();
                        } catch (_) {}
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text('Share failed: $e'),
                                backgroundColor: Colors.red),
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
                          Icon(Icons.share_rounded,
                              size: 28, color: Color(0xFF10B981)),
                          SizedBox(height: 6),
                          Text('Share',
                              style: TextStyle(
                                  fontSize: kFontSizeBody,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightSemiBold,
                                  color: Color(0xFF10B981))),
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
          // ONLY when the date range includes today (live prices are relevant).
          // For past date ranges, the backend already provides carry_forward data
          // with settlement prices — no live enrichment needed.
          if (_selectedMode == 1) {
            final today = DateTime.now();
            final todayStart = DateTime(today.year, today.month, today.day);
            final isCurrentPeriod = !_toDate!.isBefore(todayStart);
            if (isCurrentPeriod) {
              reportData =
                  await _enrichWithLivePositions(reportData, api, token);
            }
          }

          final pdf = _selectedMode == 0
              ? PdfReportService.generateDefaultReport(reportData)
              : PdfReportService.generateAdvancedReport(reportData);
          final bytes = await pdf.save();

          if (!mounted) return;
          Navigator.pop(context); // dismiss loading

          // Show options: Download or Share
          await _showPdfOptionsSheet(context, bytes,
              userName: reportData['user_name'] ?? 'Report');
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

  /// Walk through the report instruments, fetch actual current open positions
  /// from the backend (no date filter = correct direction always), then inject
  /// LIVE rows and carry_forward entries for any open positions.
  Future<Map<String, dynamic>> _enrichWithLivePositions(
    Map<String, dynamic> reportData,
    ApiService api,
    String? token,
  ) async {
    // Only enrich when we have a single specific user in scope.
    // For "All Users" mode (_selectedUser == null and admin/master), skip.
    final bool hasSpecificUser = _isUser || _selectedUser != null;
    if (!hasSpecificUser) return reportData;

    final instruments = List<Map<String, dynamic>>.from(
      (reportData['instruments'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e)) ??
          [],
    );
    final List<Map<String, dynamic>> carryForward = [];
    double totalLivePnlAdjustment = 0;

    // ── Step 1: Fetch actual open positions from backend (all historical trades) ──
    final Map<String, Map<String, dynamic>> openPosMap = {};
    try {
      String posUrl = '/trade/open-positions';
      if (_selectedUser != null) {
        final uid = _selectedUser!['id'] ?? _selectedUser!['_id'] ?? '';
        posUrl += '?user_id=$uid';
      }
      // For regular users (_isUser == true), no user_id needed — backend uses auth token
      final posRes = await api.get(posUrl, token: token);
      if (posRes.statusCode == 200) {
        final posBody = jsonDecode(posRes.body);
        if (posBody['success'] == true) {
          final posList = (posBody['data'] as List?) ?? [];
          for (final p in posList) {
            final key = '${p['exchange']}::${p['tradingsymbol']}';
            openPosMap[key] = Map<String, dynamic>.from(p);
          }
        }
      }
    } catch (e) {
      log('⚠️ Could not fetch open positions: $e');
    }

    // ── Step 1b: Fetch live price per instrument from metricsEngine (the
    // settlement-aware source), not a raw Kite quote. Kite's own market-depth
    // endpoint returns whatever it has for the instrument — including a
    // stale last-session price from before the market closed — with zero
    // awareness of this platform's own settlement price lock. Right after
    // settlement, a carried position's live price should read exactly its
    // own average entry price (ATP = CMP is settlement's own invariant,
    // confirmed in settlementService.js's verifySettlementInvariants), the
    // same way the Open Position tab already correctly shows it — that tab
    // reads from this same metricsEngine-backed source, not Kite directly.
    // Confirmed against a real export: Kite's raw quote for VBL read 417.65
    // (Friday's last tick) against a settlement price of 417.50, inventing a
    // ₹225 "live" swing that hadn't actually happened since settlement.
    //
    // One upfront batch fetch instead of a per-instrument Kite lookup, same
    // shape as Step 1's own single call.
    final Map<String, double> livePriceMap = {};
    try {
      if (_isUser) {
        final res = await api.get('/trade/metrics', token: token);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true) {
            final positions = (body['data']?['positions'] as List?) ?? [];
            for (final p in positions) {
              final ltp = (p['ltp'] as num?)?.toDouble() ?? 0;
              if (ltp > 0) {
                livePriceMap['${p['exchange']}::${p['tradingsymbol']}'] = ltp;
              }
            }
          }
        }
      } else if (_selectedUser != null) {
        final uid = _selectedUser!['id'] ?? _selectedUser!['_id'] ?? '';
        final res = await api.get(
          '/master/positions/live-metrics?user_id=$uid',
          token: token,
        );
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true) {
            final data = (body['data'] as List?) ?? [];
            if (data.isNotEmpty) {
              final positions = (data.first['positions'] as List?) ?? [];
              for (final p in positions) {
                final ltp = (p['ltp'] as num?)?.toDouble() ?? 0;
                if (ltp > 0) {
                  livePriceMap['${p['exchange']}::${p['tradingsymbol']}'] = ltp;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      log('⚠️ Could not fetch live metrics: $e');
    }

    // ── Step 2: Add LIVE rows for instruments in the report that have open positions ──
    for (int i = 0; i < instruments.length; i++) {
      final instr = Map<String, dynamic>.from(instruments[i]);
      final exchange = (instr['exchange'] ?? '').toString();
      final symbol = (instr['tradingsymbol'] ?? '').toString();
      final key = '$exchange::$symbol';

      final openPos = openPosMap[key];
      if (openPos == null) {
        instruments[i] = instr;
        continue; // No open position for this instrument
      }

      final bool isLong = (openPos['direction'] ?? '') == 'BUY';
      final double openQty = (openPos['open_qty'] as num?)?.toDouble() ?? 0;
      final double avgEntryPrice =
          (openPos['avg_price'] as num?)?.toDouble() ?? 0;

      if (openQty <= 0.001) {
        instruments[i] = instr;
        continue;
      }

      double? livePrice = livePriceMap[key];

      // No real live price available — right after settlement a carried
      // position's true price equals its own average entry price (ATP =
      // CMP is settlement's own invariant), so fall back to that instead of
      // silently dropping the LIVE row; it nets to a correct 0 unrealized
      // P&L rather than inventing one from a ₹0 reference.
      livePrice ??= avgEntryPrice > 0 ? avgEntryPrice : null;

      if (livePrice != null) {
        final allTrades = List<Map<String, dynamic>>.from(
          (instr['all_trades'] as List?)
                  ?.map((e) => Map<String, dynamic>.from(e)) ??
              [],
        );
        final now = DateTime.now();

        // Unrealized P&L
        final double unrealizedPnl = isLong
            ? (livePrice - avgEntryPrice) * openQty
            : (avgEntryPrice - livePrice) * openQty;

        // LIVE row: shows the open position direction (not the closing trade)
        // Long position → B Qty (you hold longs); Short → S Qty (you hold shorts)
        final liveRow = {
          'date': now.toIso8601String(),
          'type': 'LIVE',
          'buy_qty': isLong ? openQty : 0, // Long  → show in Buy column
          'sell_qty': isLong ? 0 : openQty, // Short → show in Sell column
          'rate': livePrice,
          'brokerage': 0,
          'net': unrealizedPnl,
        };
        allTrades.add(liveRow);

        // Adjust instrument totals to match open position direction
        if (isLong) {
          instr['total_buy_qty'] =
              ((instr['total_buy_qty'] as num?)?.toDouble() ?? 0) + openQty;
        } else {
          instr['total_sell_qty'] =
              ((instr['total_sell_qty'] as num?)?.toDouble() ?? 0) + openQty;
        }

        // Adjust P&L to include unrealized
        final existingPnl = (instr['pnl'] as num?)?.toDouble() ?? 0;
        final existingBrokerage = (instr['brokerage'] as num?)?.toDouble() ?? 0;
        instr['pnl'] = existingPnl + unrealizedPnl;
        instr['net_pnl'] = (existingPnl + unrealizedPnl) - existingBrokerage;
        totalLivePnlAdjustment += unrealizedPnl;

        instr['all_trades'] = allTrades;

        // Add carry forward entry (open position summary at top of page)
        carryForward.add({
          'exchange': exchange,
          'tradingsymbol': symbol,
          'display_name': instr['display_name'] ?? symbol,
          'type': isLong ? 'Buy' : 'Sell',
          'quantity': openQty,
          'price': avgEntryPrice,
        });
      }

      instruments[i] = instr;
    }

    // Update summary totals to include unrealized P&L
    final summary = Map<String, dynamic>.from(reportData['summary'] ?? {});
    if (totalLivePnlAdjustment != 0) {
      final oldTotalPnl = (summary['total_pnl'] as num?)?.toDouble() ?? 0;
      final totalBrokerage =
          (summary['total_brokerage'] as num?)?.toDouble() ?? 0;
      summary['total_pnl'] = oldTotalPnl + totalLivePnlAdjustment;
      summary['net_pnl'] =
          (oldTotalPnl + totalLivePnlAdjustment) - totalBrokerage;
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
        padding: EdgeInsets.only(
            top: 24,
            left: 16,
            right: 16,
            bottom: 32 + MediaQuery.of(context).viewPadding.bottom),
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
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold)),
              const SizedBox(height: 16),

              // Mode selector — layout type only
              const Text('Report Type',
                  style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: kFontSizeSheetLabel,
                      fontFamily: kFontFamily,
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
                        fontFamily: kFontFamily,
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
                              fontFamily: kFontFamily,
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
                                fontSize: kFontSizeSheetHint,
                                fontFamily: kFontFamily),
                            decoration: const InputDecoration(
                              hintText: 'Search by name...',
                              hintStyle: TextStyle(
                                  color: Color(0xFFCBD5E1),
                                  fontSize: kFontSizeSheetHint),
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
                                fontFamily: kFontFamily,
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
                          color: kBrandPrimary,
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
                                    fontFamily: kFontFamily,
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
              color: isSelected ? kBrandPrimary : const Color(0xFF1E293B),
              fontSize: 13,
              fontFamily: kFontFamily,
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
              fontFamily: kFontFamily,
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
          color: selected ? kBrandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? kBrandPrimary : const Color(0xFFD1D1D6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF64748B),
            fontSize: 13,
            fontFamily: kFontFamily,
            fontWeight: kFontWeightSemiBold,
          ),
        ),
      ),
    );
  }
}
