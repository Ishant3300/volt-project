import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class ProfitAndLossView extends StatefulWidget {
  const ProfitAndLossView({super.key});
  @override
  State<ProfitAndLossView> createState() => _ProfitAndLossViewState();
}

class _ProfitAndLossViewState extends State<ProfitAndLossView> {
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {'realised': 0.0, 'position': 0.0, 'm2m': 0.0};
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  int _sortCol = 3; // default sort by Total
  bool _sortAsc = false;

  @override
  void initState() { super.initState(); _fetch(); }
  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).get('/master/pnl-summary', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _rows = List<Map<String, dynamic>>.from(body['data'] ?? []);
            final t = body['totals'];
            _totals = {
              'realised': (t?['realised'] as num?)?.toDouble() ?? 0.0,
              'position': (t?['position'] as num?)?.toDouble() ?? 0.0,
              'm2m': (t?['m2m'] as num?)?.toDouble() ?? 0.0,
            };
            _applySort();
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

  void _applySort() {
    final keys = ['username', 'realised_pnl', 'position_pnl', 'm2m_pnl'];
    final k = keys[_sortCol];
    _rows.sort((a, b) {
      final av = a[k], bv = b[k];
      if (av is num && bv is num) return _sortAsc ? av.compareTo(bv) : bv.compareTo(av);
      return _sortAsc ? av.toString().compareTo(bv.toString()) : bv.toString().compareTo(av.toString());
    });
  }

  void _sort(int col) {
    setState(() {
      if (_sortCol == col) { _sortAsc = !_sortAsc; } else { _sortCol = col; _sortAsc = true; }
      _applySort();
    });
  }

  Color _pnlColor(double v) => v >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
  String _pnlStr(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';

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
              const Text('Profit & Loss', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
            ]),
          ),

          // Totals card
          if (!_isLoading)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: Row(children: [
                _totalItem('Realised', -_totals['realised']!),
                Container(width: 1, height: 36, color: const Color(0xFFF1F5F9)),
                _totalItem('M2M', -_totals['position']!),
                Container(width: 1, height: 36, color: const Color(0xFFF1F5F9)),
                _totalItem('Total', -_totals['m2m']!),
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
              style: const TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
              decoration: InputDecoration(
                hintText: 'Search $label...',
                hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: kFontFamily),
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
              child: Text('${filtered.length} $label', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
          ),
          const SizedBox(height: 8),

          // Table header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(children: List.generate(4, (i) {
              final labels = [label.toUpperCase(), 'REALISED', 'M2M', 'TOTAL'];
              final isSorted = _sortCol == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _sort(i),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                    Text(labels[i], style: TextStyle(
                      color: isSorted ? kBrandPrimary : const Color(0xFF94A3B8),
                      fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
                    const SizedBox(width: 2),
                    Icon(isSorted ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                      size: 11, color: isSorted ? kBrandPrimary : const Color(0xFF94A3B8)),
                  ]),
                ),
              );
            })),
          ),

          // Table body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
                : filtered.isEmpty
                    ? const Center(child: Text('No data', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)))
                    : RefreshIndicator(
                        onRefresh: _fetch,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(bottom: Radius.circular(16))),
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) => _buildRow(filtered[i], i),
                          ),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _totalItem(String label, double value) {
    return Expanded(
      child: Column(children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(_pnlStr(value), style: TextStyle(color: _pnlColor(value), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
      ]),
    );
  }

  Widget _buildRow(Map<String, dynamic> row, int index) {
    final username = row['username'] ?? '';
    final type = row['type'] ?? '';
    final realised = -((row['realised_pnl'] as num?)?.toDouble() ?? 0);
    final position = -((row['position_pnl'] as num?)?.toDouble() ?? 0);
    final m2m = -((row['m2m_pnl'] as num?)?.toDouble() ?? 0);
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFAFBFC),
        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.5)),
      ),
      child: Row(children: [
        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (type == 'master')
            const Padding(padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.supervisor_account, size: 12, color: kBrandPrimary)),
          Flexible(child: Text(username, textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
        Expanded(child: Text(_pnlStr(realised), textAlign: TextAlign.center,
          style: TextStyle(color: _pnlColor(realised), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
        Expanded(child: Text(_pnlStr(position), textAlign: TextAlign.center,
          style: TextStyle(color: _pnlColor(position), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
        Expanded(child: Text(_pnlStr(m2m), textAlign: TextAlign.center,
          style: TextStyle(color: _pnlColor(m2m), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightBold))),
      ]),
    );
  }
}
