import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import 'scriptwise_pnl_detail_view.dart';

enum _DateRangeMode { thisWeek, previousWeek, custom }

/// Scriptwise P&L Summary — GET /api/master/positions/scriptwise-pnl
/// (Level 1: one row per script across the caller's whole hierarchy).
/// Tapping a row opens ScriptwisePnlDetailView, the SAME endpoint with
/// exchange+tradingsymbol added — the two screens can never disagree since
/// they're reading the same aggregation, just at a different grouping.
///
/// Column mapping from the backend response ("Profit & Loss" == the
/// backend's realized `net_pnl`; "Total" here means realized-net
/// (net_pnl - brokerage); "M2MPL" == `floating_pnl`; "NetPL" == the
/// backend's own `total` field, i.e. the fully blended figure) — matches
/// this feature's web-portal twin (ScriptwisePnlPanel.tsx) exactly.
class ScriptwisePnlView extends StatefulWidget {
  const ScriptwisePnlView({super.key});
  @override
  State<ScriptwisePnlView> createState() => _ScriptwisePnlViewState();
}

class _ScriptwisePnlViewState extends State<ScriptwisePnlView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _summary = const {};

  _DateRangeMode _dateMode = _DateRangeMode.thisWeek;
  DateTime? _customFrom;
  DateTime? _customTo;
  String? _selectedExchange;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  static const _exchanges = ['NFO', 'BFO', 'MCX', 'NSE', 'BSE', 'COMEX'];

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

  DateTime _mondayOf(DateTime d) {
    final diff = d.weekday - DateTime.monday;
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: diff));
  }

  (DateTime from, DateTime to) _resolveRange() {
    final now = DateTime.now();
    switch (_dateMode) {
      case _DateRangeMode.thisWeek:
        return (_mondayOf(now), now);
      case _DateRangeMode.previousWeek:
        final thisMonday = _mondayOf(now);
        final prevMonday = thisMonday.subtract(const Duration(days: 7));
        final prevSunday = thisMonday.subtract(const Duration(days: 1));
        return (prevMonday, prevSunday);
      case _DateRangeMode.custom:
        return (_customFrom ?? _mondayOf(now), _customTo ?? now);
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await SecureStorageService().getToken();
      final range = _resolveRange();
      final params = <String>[
        'from=${Uri.encodeQueryComponent(_isoDate(range.$1))}',
        'to=${Uri.encodeQueryComponent(_isoDate(range.$2))}',
      ];
      if (_selectedExchange != null) {
        params.add('exchange=${Uri.encodeQueryComponent(_selectedExchange!)}');
      }
      if (_searchQuery.isNotEmpty) {
        params.add('search=${Uri.encodeQueryComponent(_searchQuery)}');
      }

      final res = await ApiService(backendUrl)
          .get('/master/positions/scriptwise-pnl?${params.join('&')}', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          final data = body['data'] as Map<String, dynamic>? ?? {};
          setState(() {
            _rows = List<Map<String, dynamic>>.from(data['rows'] ?? []);
            _summary = Map<String, dynamic>.from(data['summary'] ?? {});
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
      _searchCtrl.clear();
      _searchQuery = '';
    });
    _fetch();
  }

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  Color _pnlColor(double v) => v >= 0 ? kColorBuy : kColorSell;

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

  void _openScript(Map<String, dynamic> row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScriptwisePnlDetailView(
          exchange: (row['exchange'] ?? '').toString(),
          tradingsymbol: (row['tradingsymbol'] ?? '').toString(),
          displayName: (row['display_name'] ?? row['tradingsymbol'] ?? '').toString(),
          from: _resolveRange().$1,
          to: _resolveRange().$2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
                : _error != null
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!,
                              style: const TextStyle(
                                  color: kColorTextMuted, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
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
                            _buildFilters(),
                            const SizedBox(height: 12),
                            _buildSearch(),
                            const SizedBox(height: 12),
                            _buildSummaryTiles(),
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
            child: const Icon(Icons.arrow_back, color: kColorTextPrimary, size: kIconSizeMedium),
          ),
        ),
        const SizedBox(width: 12),
        const Text('Scriptwise P & L Summary',
            style: TextStyle(
                color: kColorTextPrimary, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
      ]),
    );
  }

  Widget _buildFilters() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dropdownField<_DateRangeMode>(
        value: _dateMode,
        hint: 'This Week',
        items: const {
          _DateRangeMode.thisWeek: 'This Week',
          _DateRangeMode.previousWeek: 'Previous Week',
          _DateRangeMode.custom: 'Custom period',
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
      _dropdownField<String>(
        value: _selectedExchange,
        hint: 'Exchange',
        items: {for (final e in _exchanges) e: e},
        onChanged: (v) => setState(() => _selectedExchange = v),
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
                      color: Colors.white, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
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
                      color: kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
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
          hint: Text(hint, style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
          icon: const Icon(Icons.arrow_drop_down, color: kColorTextMuted),
          items: [
            DropdownMenuItem<T>(
                value: null,
                child: Text(hint, style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))),
            ...items.entries.map((e) => DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value, style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)))),
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
          hintText: 'Search',
          hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: kFontFamily),
          prefixIcon: const Icon(Icons.search, color: kColorTextMuted, size: kIconSizeMedium),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildSummaryTiles() {
    final pnl = _d(_summary['net_pnl']);
    final brk = _d(_summary['brokerage']);
    final m2m = _d(_summary['floating_pnl']);
    final netpl = pnl - brk + m2m;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        _summaryTile('P&L', pnl),
        _summaryTile('Brk', brk, colored: false),
        _summaryTile('M2MPL', m2m),
        _summaryTile('NetPL', netpl),
      ]),
    );
  }

  Widget _summaryTile(String label, double value, {bool colored = true}) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
        Text(value.toStringAsFixed(2),
            style: TextStyle(
                color: colored ? _pnlColor(value) : const Color(0xFF334155),
                fontSize: kFontSizeBodySmall,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold)),
      ]),
    );
  }

  static const _colWidths = <double>[180, 70, 90, 80, 90, 90, 90];

  Widget _buildTable() {
    if (_rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: const Center(
          child: Text('No data', style: TextStyle(color: kColorTextMuted, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
      // Header and body scroll TOGETHER horizontally — no existing shared
      // horizontal-scroll-table widget in this app, so built fresh here
      // (see the reference mobile screenshots this feature replicates).
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(children: [
              _headerCell('Description', _colWidths[0]),
              _headerCell('Users', _colWidths[1]),
              _headerCell('P & L', _colWidths[2]),
              _headerCell('Brk', _colWidths[3]),
              _headerCell('Total', _colWidths[4]),
              _headerCell('M2MPL', _colWidths[5]),
              _headerCell('NetPL', _colWidths[6]),
            ]),
          ),
          ...List.generate(
            _rows.length,
            (i) => Column(children: [
              if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
              _buildRow(_rows[i]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _headerCell(String label, double width) => SizedBox(
        width: width,
        child: Text(label,
            style: const TextStyle(
                color: kColorTextMuted, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
      );

  Widget _buildRow(Map<String, dynamic> row) {
    final pnl = _d(row['net_pnl']);
    final brk = _d(row['brokerage']);
    final total = pnl - brk;
    final m2m = _d(row['floating_pnl']);
    final netpl = total + m2m;
    final exchange = (row['exchange'] ?? '').toString();
    final displayName = (row['display_name'] ?? '').toString();
    final userCount = (row['user_count'] as num?)?.toInt() ?? 0;

    return InkWell(
      onTap: () => _openScript(row),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(children: [
          SizedBox(
            width: _colWidths[0],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(displayName,
                  style: const TextStyle(
                      color: kBrandPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
              Text(exchange, style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
            ]),
          ),
          SizedBox(
              width: _colWidths[1],
              child: Text('$userCount',
                  style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))),
          SizedBox(
              width: _colWidths[2],
              child: Text(pnl.toStringAsFixed(2),
                  style: TextStyle(color: _pnlColor(pnl), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          SizedBox(
              width: _colWidths[3],
              child: Text(brk.toStringAsFixed(2),
                  style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          SizedBox(
              width: _colWidths[4],
              child: Text(total.toStringAsFixed(2),
                  style: TextStyle(color: _pnlColor(total), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          SizedBox(
              width: _colWidths[5],
              child: Text(m2m.toStringAsFixed(2),
                  style: TextStyle(color: _pnlColor(m2m), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          SizedBox(
              width: _colWidths[6],
              child: Text(netpl.toStringAsFixed(2),
                  style: TextStyle(color: _pnlColor(netpl), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        ]),
      ),
    );
  }
}
