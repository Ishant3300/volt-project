import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../providers/user_profile_provider.dart';
import '../services/admin_service.dart';
import '../services/api_service.dart';
import '../services/master_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import 'username_view.dart';

enum _DateRangeMode { today, thisWeek, thisMonth, custom }

/// Client P&L Summary — GET /api/master/weekly-admin-report, reusing its
/// existing per-user realised_pnl/brokerage figures rather than a new
/// endpoint (see weeklyAdminController.js). Netpl/P&L/Brk here are the
/// CLIENT's own perspective (client-positive), unlike the separate Weekly
/// Admin Report screen's caller_profit/total_caller fields, which are the
/// house/commission perspective — deliberately not reused here.
///
/// Master sees two tabs: their direct clients (report rows with
/// type=='user') and an aggregated summary per sub-broker (type=='master').
/// Admin sees only the master-aggregated rows (the report only returns
/// top-level masters for an admin caller) — no client-level tab, matching
/// there being no "direct client" concept for admin in this report.
class ClientPnlSummaryView extends StatefulWidget {
  const ClientPnlSummaryView({super.key});
  @override
  State<ClientPnlSummaryView> createState() => _ClientPnlSummaryViewState();
}

class _ClientPnlSummaryViewState extends State<ClientPnlSummaryView> {
  bool _isLoading = true;
  bool _isOpeningRow = false;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  List<String> _availableExchanges = [];
  List<String> _availableScripts = [];

  _DateRangeMode _dateMode = _DateRangeMode.thisWeek;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _selectedExchange;
  String? _selectedScript;
  String? _selectedUsername;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  int _tab = 0; // 0 = Clients, 1 = Sub-Brokers (master only; admin has no tabs)

  String _sortColumn = 'username';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  ({DateTime from, DateTime? to}) _resolveDateRange() {
    final now = DateTime.now();
    switch (_dateMode) {
      case _DateRangeMode.today:
        return (from: DateTime(now.year, now.month, now.day), to: null);
      case _DateRangeMode.thisWeek:
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return (from: DateTime(monday.year, monday.month, monday.day), to: null);
      case _DateRangeMode.thisMonth:
        return (from: DateTime(now.year, now.month, 1), to: null);
      case _DateRangeMode.custom:
        return (
          from: _customFrom ?? DateTime(now.year, now.month, now.day),
          to: _customTo,
        );
    }
  }

  /// The picked date represents an IST calendar-day boundary, not a real
  /// device-timezone instant — re-anchored to IST before converting to a
  /// real UTC instant, same fix already applied to history_filter_sheet.dart
  /// for the identical class of bug (a marker-less local wall-clock string
  /// gets misread by the backend's `new Date(...)` as local-to-the-server,
  /// not IST).
  String _istWallClockToUtcIso(DateTime wallClock) {
    return DateTime.utc(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
    ).subtract(const Duration(hours: 5, minutes: 30)).toIso8601String();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await SecureStorageService().getToken();
      final range = _resolveDateRange();
      final params = <String>[
        'date_from=${Uri.encodeQueryComponent(_istWallClockToUtcIso(range.from))}',
      ];
      if (range.to != null) {
        final endOfDay = DateTime(range.to!.year, range.to!.month, range.to!.day, 23, 59, 59);
        params.add('date_to=${Uri.encodeQueryComponent(_istWallClockToUtcIso(endOfDay))}');
      }
      if (_selectedExchange != null) {
        params.add('exchange=${Uri.encodeQueryComponent(_selectedExchange!)}');
      }
      if (_selectedScript != null) {
        params.add('script=${Uri.encodeQueryComponent(_selectedScript!)}');
      }

      final res = await ApiService(backendUrl)
          .get('/master/weekly-admin-report?${params.join('&')}', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _rows = List<Map<String, dynamic>>.from(body['data'] ?? []);
            _availableExchanges = List<String>.from(body['available_exchanges'] ?? []);
            _availableScripts = List<String>.from(body['available_scripts'] ?? []);
          });
        } else {
          _error = body['message']?.toString() ?? 'Failed to load';
        }
      } else {
        _error = 'Failed to load (${res.statusCode})';
      }
    } catch (e) {
      _error = 'Error: $e';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _resetFilters() {
    setState(() {
      _dateMode = _DateRangeMode.thisWeek;
      _customFrom = null;
      _customTo = null;
      _selectedExchange = null;
      _selectedScript = null;
      _selectedUsername = null;
      _searchCtrl.clear();
      _searchQuery = '';
      _sortColumn = 'username';
      _sortAscending = true;
    });
    _fetch();
  }

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  double _netpl(Map<String, dynamic> row) => _d(row['realised_pnl']) - _d(row['brokerage']);

  List<Map<String, dynamic>> get _clientRows =>
      _rows.where((r) => r['type'] == 'user').toList();
  List<Map<String, dynamic>> get _subBrokerRows =>
      _rows.where((r) => r['type'] == 'master').toList();

  List<Map<String, dynamic>> get _displayedRows {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    var rows = profile.isAdmin ? _subBrokerRows : (_tab == 0 ? _clientRows : _subBrokerRows);

    if (_selectedUsername != null) {
      rows = rows.where((r) => r['username'] == _selectedUsername).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      rows = rows
          .where((r) =>
              (r['username'] ?? '').toString().toLowerCase().contains(q) ||
              (r['name'] ?? '').toString().toLowerCase().contains(q))
          .toList();
    }

    final sorted = [...rows];
    sorted.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'netpl':
          cmp = _netpl(a).compareTo(_netpl(b));
          break;
        case 'pnl':
          cmp = _d(a['realised_pnl']).compareTo(_d(b['realised_pnl']));
          break;
        case 'brk':
          cmp = _d(a['brokerage']).compareTo(_d(b['brokerage']));
          break;
        default:
          cmp = (a['username'] ?? '').toString().compareTo((b['username'] ?? '').toString());
      }
      return _sortAscending ? cmp : -cmp;
    });
    return sorted;
  }

  void _toggleSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Future<void> _openRow(Map<String, dynamic> row) async {
    if (_isOpeningRow) return;
    final id = row['id']?.toString();
    if (id == null) return;
    setState(() => _isOpeningRow = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      final isMaster = profile.isMaster;
      if (row['type'] == 'master') {
        final res = isMaster
            ? await MasterService(apiService).getChildMasterById(id)
            : await AdminService(apiService).getMasterById(id);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final master = Master.fromJson(body['data']);
          if (mounted) {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => UsernameView(master: master, user: null)));
          }
        }
      } else {
        final res = isMaster
            ? await MasterService(apiService).getUserById(id)
            : await AdminService(apiService).getUserById(id);
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          final user = User.fromJson(body['data']);
          if (mounted) {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => UsernameView(master: null, user: user)));
          }
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open account')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningRow = false);
    }
  }

  Future<void> _pickCustomDate(bool isFrom) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _customFrom : _customTo) ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: const ColorScheme.light(primary: kBrandPrimary)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _customFrom = picked;
        } else {
          _customTo = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final isAdmin = profile.isAdmin;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          if (!isAdmin) _buildTabs(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: kFontSizeBodySmall,
                                  fontFamily: kFontFamily)),
                          const SizedBox(height: 12),
                          TextButton(onPressed: _fetch, child: const Text('Retry')),
                        ]),
                      )
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _buildFilters(isAdmin),
                            const SizedBox(height: 12),
                            _buildSearch(),
                            const SizedBox(height: 12),
                            _buildTable(),
                          ]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
          ),
        ),
        const SizedBox(width: 12),
        const Text('Client P & L Summary',
            style: TextStyle(
                color: Colors.black,
                fontSize: kFontSizeViewTitle,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold)),
      ]),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          _tabButton('Clients', 0),
          _tabButton('Sub-Brokers', 1),
        ]),
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final selected = _tab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _tab = index;
          _selectedUsername = null;
        }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? kBrandPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF94A3B8),
                  fontSize: kFontSizeBodySmall,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold)),
        ),
      ),
    );
  }

  String get _userDropdownLabel {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    if (profile.isAdmin) return 'All Master';
    return _tab == 0 ? 'All User' : 'All Sub-Broker';
  }

  Widget _buildFilters(bool isAdmin) {
    final userOptions = (isAdmin ? _subBrokerRows : (_tab == 0 ? _clientRows : _subBrokerRows))
        .map((r) => (r['username'] ?? '').toString())
        .where((u) => u.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dropdownField<_DateRangeMode>(
        value: _dateMode,
        hint: 'This Week',
        items: const {
          _DateRangeMode.today: 'Today',
          _DateRangeMode.thisWeek: 'This Week',
          _DateRangeMode.thisMonth: 'This Month',
          _DateRangeMode.custom: 'Custom Range',
        },
        onChanged: (v) => setState(() => _dateMode = v ?? _DateRangeMode.thisWeek),
      ),
      if (_dateMode == _DateRangeMode.custom) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _dateButton('From', _customFrom, () => _pickCustomDate(true))),
          const SizedBox(width: 8),
          Expanded(child: _dateButton('To', _customTo, () => _pickCustomDate(false))),
        ]),
      ],
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _dropdownField<String>(
            value: _selectedExchange,
            hint: 'Exchange',
            items: {for (final e in _availableExchanges) e: e},
            onChanged: (v) => setState(() => _selectedExchange = v),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dropdownField<String>(
            value: _selectedScript,
            hint: 'All Script',
            items: {for (final s in _availableScripts) s: s},
            onChanged: (v) => setState(() => _selectedScript = v),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      _dropdownField<String>(
        value: _selectedUsername,
        hint: _userDropdownLabel,
        items: {for (final u in userOptions) u: u},
        onChanged: (v) => setState(() => _selectedUsername = v),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _fetch,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(12)),
              child: const Text('View',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: kFontSizeBody,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _resetFilters,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBrandPrimary),
              ),
              child: const Text('Reset',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: kBrandPrimary,
                      fontSize: kFontSizeBody,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold)),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _dateButton(String label, DateTime? value, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          value == null ? label : '${value.day}/${value.month}/${value.year}',
          style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
        ),
      ),
    );
  }

  Widget _dropdownField<T>({
    required T? value,
    required String hint,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF94A3B8)),
          items: [
            DropdownMenuItem<T>(
                value: null,
                child: Text(hint,
                    style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))),
            ...items.entries.map((e) => DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value,
                    style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)))),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        style: const TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
        decoration: InputDecoration(
          hintText: 'Search by username',
          hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: kFontFamily),
          prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: kIconSizeMedium),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _sortHeader(String label, String column) {
    final active = _sortColumn == column;
    return GestureDetector(
      onTap: () => _toggleSort(column),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label,
            style: TextStyle(
                color: active ? kBrandPrimary : const Color(0xFF64748B),
                fontSize: kFontSizeCaption,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold)),
        Icon(
          active
              ? (_sortAscending ? Icons.arrow_upward : Icons.arrow_downward)
              : Icons.unfold_more,
          size: 14,
          color: active ? kBrandPrimary : const Color(0xFF94A3B8),
        ),
      ]),
    );
  }

  Widget _buildTable() {
    final rows = _displayedRows;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(children: [
            Expanded(flex: 2, child: _sortHeader('Username', 'username')),
            Expanded(child: _sortHeader('Netpl', 'netpl')),
            Expanded(child: _sortHeader('P & L', 'pnl')),
            Expanded(child: _sortHeader('Brk', 'brk')),
          ]),
        ),
        if (rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No data',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (_, i) => _buildRow(rows[i]),
          ),
      ]),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final netpl = _netpl(row);
    final pnl = _d(row['realised_pnl']);
    final brk = _d(row['brokerage']);
    final username = (row['username'] ?? '').toString();
    final name = (row['name'] ?? '').toString();

    Color pnlColor(double v) => v >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return InkWell(
      onTap: () => _openRow(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          Expanded(
            flex: 2,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(username,
                  style: const TextStyle(
                      color: kBrandPrimary,
                      fontSize: kFontSizeBodySmall,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold,
                      decoration: TextDecoration.underline)),
              if (name.isNotEmpty)
                Text(name,
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
            ]),
          ),
          Expanded(
            child: Text(netpl.toStringAsFixed(2),
                style: TextStyle(color: pnlColor(netpl), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          ),
          Expanded(
            child: Text(pnl.toStringAsFixed(2),
                style: TextStyle(color: pnlColor(pnl), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          ),
          Expanded(
            child: Text(brk.toStringAsFixed(2),
                style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          ),
        ]),
      ),
    );
  }
}
