import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class WeeklyAdminView extends StatefulWidget {
  const WeeklyAdminView({super.key});
  @override
  State<WeeklyAdminView> createState() => _WeeklyAdminViewState();
}

class _WeeklyAdminViewState extends State<WeeklyAdminView> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() { super.initState(); _fetch(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).get('/master/weekly-admin-report', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _rows = List<Map<String, dynamic>>.from(body['data'] ?? []);
            _totals = Map<String, dynamic>.from(body['totals'] ?? {});
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _rows;
    final q = _searchQuery.toLowerCase();
    return _rows.where((r) {
      final name = (r['name'] ?? '').toString().toLowerCase();
      final username = (r['username'] ?? '').toString().toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  Color _pnlColor(double v) => v >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
  String _fmt(double v) => v.toStringAsFixed(2);
  String _fmtSigned(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final label = profile.isAdmin ? 'Masters' : 'Children';
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Weekly Admin Report', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
            ]),
          ),

          // Summary pills
          if (!_isLoading && _totals.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _pill('Total P&L', _d(_totals['total_pnl'])),
                const SizedBox(width: 6),
                _pill('Realised', _d(_totals['realised_pnl'])),
                const SizedBox(width: 6),
                _pill('M2M', _d(_totals['m2m_pnl'])),
                const SizedBox(width: 6),
                _pill('Brokerage', _d(_totals['brokerage'])),
                const SizedBox(width: 6),
                _pill('Total Admin', _d(_totals['total_admin'])),
              ]),
            ),
          const SizedBox(height: 12),

          // Search
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
              style: const TextStyle(fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
              decoration: InputDecoration(
                hintText: 'Search $label...',
                hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: 'Inter'),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF94A3B8), size: kIconSizeMedium),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? GestureDetector(onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
                        child: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18))
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('${filtered.length} $label', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightMedium))),
          ),
          const SizedBox(height: 8),

          // Cards
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
                : filtered.isEmpty
                    ? const Center(child: Text('No data', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: 'Inter')))
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _buildCard(filtered[i]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _pill(String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
        Text(_fmtSigned(value), style: TextStyle(color: _pnlColor(value), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
      ]),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final username = row['username'] ?? '';
    final parentUsername = row['parent_username'] ?? '';
    final realised = _d(row['realised_pnl']);
    final m2m = _d(row['m2m_pnl']);
    final brokerage = _d(row['brokerage']);
    final adminBrk = _d(row['admin_brk']);
    final totalPnl = _d(row['total_pnl']);
    final adminProfit = _d(row['admin_profit']);
    final totalAdmin = _d(row['total_admin']);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header: username + parent badge
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(username.toUpperCase(), style: const TextStyle(color: Color(0xFF3F45C7), fontSize: kFontSizeName, fontFamily: 'Inter', fontWeight: kFontWeightName, letterSpacing: -0.3)),
          if (parentUsername.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF94A3B8), borderRadius: BorderRadius.circular(6)),
              child: Text('PARENT: $parentUsername', style: const TextStyle(color: Colors.white, fontSize: kFontSizeCaption, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
            ),
        ]),
        const SizedBox(height: 8),

        // Stats grid
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(children: [
            Row(children: [
              _statCell('REALISED P&L', realised, showRight: true),
              _statCell('M2M P&L', m2m, showRight: false),
            ]),
            Container(height: 1, color: const Color(0xFFF1F5F9)),
            Row(children: [
              _statCell('BROKERAGE', brokerage, showRight: true),
              _statCell('ADMIN BRK', adminBrk, showRight: false),
            ]),
          ]),
        ),
        const SizedBox(height: 8),

        // Summary row (values already inverted on server side)
        Row(children: [
          _summaryBox('TOTAL P&L', totalPnl),
          const SizedBox(width: 8),
          _summaryBox('ADMIN PROFIT', adminProfit),
          const SizedBox(width: 8),
          _summaryBox('TOTAL ADMIN', totalAdmin),
        ]),
      ]),
    );
  }

  Widget _statCell(String label, double value, {required bool showRight}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: showRight ? const Border(right: BorderSide(color: Color(0xFFF1F5F9))) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: 'Inter', fontWeight: kFontWeightMedium, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(_fmt(value), style: TextStyle(color: _pnlColor(value), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
        ]),
      ),
    );
  }

  Widget _summaryBox(String label, double value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFBFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: Column(children: [
          Text(label, textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBadge, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
          const SizedBox(height: 4),
          Container(width: 20, height: 1, color: const Color(0xFFE2E8F0)),
          const SizedBox(height: 4),
          Text(_fmtSigned(value), textAlign: TextAlign.center,
            style: TextStyle(color: _pnlColor(value), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
        ]),
      ),
    );
  }
}
