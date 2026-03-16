import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:printing/printing.dart';
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
                    if (!isUser)
                      _buildReportItem(
                          context, 'Profit & Loss', Icons.trending_up,
                          showBorder: true),
                    _buildReportItem(
                        context, 'Generate PDF', Icons.picture_as_pdf,
                        showBorder: true),
                    if (!isUser)
                      _buildReportItem(
                          context, 'Weekly Admin Report', Icons.calendar_today,
                          showBorder: true),
                    _buildReportItem(context, 'Intraday History', Icons.history,
                        showBorder: true),
                    _buildReportItem(
                        context, 'Userwise Open Position', Icons.open_in_new,
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
          colorScheme: const ColorScheme.light(primary: Color(0xFF22547C)),
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

  Future<void> _generatePdf() async {
    String from, to;

    if (_selectedMode == 0) {
      // Default: last 7 days (excluding today)
      final now = DateTime.now();
      final yesterday = now.subtract(const Duration(days: 1));
      from =
          now.subtract(const Duration(days: 7)).toIso8601String().split('T')[0];
      to = yesterday.toIso8601String().split('T')[0];
    } else {
      // Advanced: user-picked dates
      if (_fromDate == null || _toDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select both dates')),
        );
        return;
      }
      from = _fromDate!.toIso8601String().split('T')[0];
      to = _toDate!.toIso8601String().split('T')[0];
    }

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
          final reportData = body['data'];
          final pdf = _selectedMode == 0
              ? PdfReportService.generateDefaultReport(reportData)
              : PdfReportService.generateAdvancedReport(reportData);
          final bytes = await pdf.save();

          if (!mounted) return;
          Navigator.pop(context);

          await Printing.layoutPdf(onLayout: (_) => bytes);
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

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd MMM yyyy');
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding:
            const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 32),
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
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Mode selector (moved above dates so Default can hide them)
              const Text('Report Type',
                  style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _modeChip('Default', 0),
                  const SizedBox(width: 10),
                  _modeChip('Advanced', 1),
                ],
              ),
              const SizedBox(height: 12),

              // Default mode: show fixed "Last 7 days" label
              if (_selectedMode == 0)
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Icon(Icons.info_outline,
                              size: 14, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Last 7 days · ${DateFormat('dd/MM').format(DateTime.now().subtract(const Duration(days: 7)))} – ${DateFormat('dd/MM/yy').format(DateTime.now().subtract(const Duration(days: 1)))}',
                            style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                ),

              // Advanced mode: date pickers
              if (_selectedMode == 1) ...[
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
              ],
              const SizedBox(height: 16),

              // User selector (admin/master only)
              if (!_isUser && widget.preselectedUserId == null) ...[
                const Text('Select User',
                    style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
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
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
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
                                fontSize: 13, fontFamily: 'Inter'),
                            decoration: const InputDecoration(
                              hintText: 'Search by name...',
                              hintStyle: TextStyle(
                                  color: Color(0xFFCBD5E1), fontSize: 13),
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
                                fontSize: 15,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600)),
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
                          color: const Color(0xFF22547C),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('VIEW',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600)),
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
                  ? const Color(0xFF22547C)
                  : const Color(0xFF1E293B),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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
              fontWeight: FontWeight.w400,
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
          color: selected ? const Color(0xFF22547C) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color:
                  selected ? const Color(0xFF22547C) : const Color(0xFFD1D1D6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF64748B),
            fontSize: 13,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
