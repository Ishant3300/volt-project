import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

/// Scriptwise P&L — per-user drill-down for one script. Same endpoint as
/// ScriptwisePnlView, with exchange+tradingsymbol added — its own summary
/// tiles always sum to exactly the row that opened this screen, since
/// they're reading the same backend aggregation.
class ScriptwisePnlDetailView extends StatefulWidget {
  final String exchange;
  final String tradingsymbol;
  final String displayName;
  final DateTime from;
  final DateTime to;

  const ScriptwisePnlDetailView({
    super.key,
    required this.exchange,
    required this.tradingsymbol,
    required this.displayName,
    required this.from,
    required this.to,
  });

  @override
  State<ScriptwisePnlDetailView> createState() => _ScriptwisePnlDetailViewState();
}

class _ScriptwisePnlDetailViewState extends State<ScriptwisePnlDetailView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _summary = const {};
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

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

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await SecureStorageService().getToken();
      final params = <String>[
        'from=${Uri.encodeQueryComponent(_isoDate(widget.from))}',
        'to=${Uri.encodeQueryComponent(_isoDate(widget.to))}',
        'exchange=${Uri.encodeQueryComponent(widget.exchange)}',
        'tradingsymbol=${Uri.encodeQueryComponent(widget.tradingsymbol)}',
      ];

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

  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
  Color _pnlColor(double v) => v >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

  List<Map<String, dynamic>> get _displayedRows {
    if (_searchQuery.isEmpty) return _rows;
    final q = _searchQuery.toLowerCase();
    return _rows
        .where((r) =>
            (r['username'] ?? '').toString().toLowerCase().contains(q) ||
            (r['name'] ?? '').toString().toLowerCase().contains(q))
        .toList();
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
                                  color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
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
            child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text('${widget.exchange} ${widget.displayName}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
        ),
      ]),
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
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
        Text(value.toStringAsFixed(2),
            style: TextStyle(
                color: colored ? _pnlColor(value) : const Color(0xFF334155),
                fontSize: kFontSizeBodySmall,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold)),
      ]),
    );
  }

  static const _colWidths = <double>[160, 70, 90, 80, 90, 90, 90, 60, 60, 90, 90];

  Widget _buildTable() {
    final rows = _displayedRows;
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF1F5F9)),
        ),
        child: const Center(
          child: Text('No data', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF1F5F9)),
      ),
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
              _headerCell('Username', _colWidths[0]),
              _headerCell('P & L', _colWidths[1]),
              _headerCell('Brk', _colWidths[2]),
              _headerCell('Total', _colWidths[3]),
              _headerCell('M2MPL', _colWidths[4]),
              _headerCell('NetPL', _colWidths[5]),
              _headerCell('Qty', _colWidths[6]),
              _headerCell('Side', _colWidths[7]),
              _headerCell('Avg Rate', _colWidths[8]),
              _headerCell('LTP', _colWidths[9]),
            ]),
          ),
          ...List.generate(
            rows.length,
            (i) => Column(children: [
              if (i > 0) const Divider(height: 1, color: Color(0xFFF1F5F9)),
              _buildRow(rows[i]),
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
                color: Color(0xFF64748B), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
      );

  Widget _buildRow(Map<String, dynamic> row) {
    final pnl = _d(row['net_pnl']);
    final brk = _d(row['brokerage']);
    final total = pnl - brk;
    final m2m = _d(row['floating_pnl']);
    final netpl = total + m2m;
    final username = (row['username'] ?? '').toString();
    final name = (row['name'] ?? '').toString();
    final side = row['side']?.toString();
    final netQty = (row['net_qty'] as num?)?.abs();
    final avgRate = row['avg_rate'] as num?;
    final ltp = row['ltp'] as num?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        SizedBox(
          width: _colWidths[0],
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(username,
                style: const TextStyle(
                    color: kBrandPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
            if (name.isNotEmpty)
              Text(name, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
          ]),
        ),
        SizedBox(
            width: _colWidths[1],
            child: Text(pnl.toStringAsFixed(2),
                style: TextStyle(color: _pnlColor(pnl), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        SizedBox(
            width: _colWidths[2],
            child: Text(brk.toStringAsFixed(2),
                style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        SizedBox(
            width: _colWidths[3],
            child: Text(total.toStringAsFixed(2),
                style: TextStyle(color: _pnlColor(total), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        SizedBox(
            width: _colWidths[4],
            child: Text(m2m.toStringAsFixed(2),
                style: TextStyle(color: _pnlColor(m2m), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        SizedBox(
            width: _colWidths[5],
            child: Text(netpl.toStringAsFixed(2),
                style: TextStyle(color: _pnlColor(netpl), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        SizedBox(
            width: _colWidths[6],
            child: Text(netQty == null || netQty == 0 ? '—' : netQty.toStringAsFixed(0),
                style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))),
        SizedBox(
          width: _colWidths[7],
          child: side == null
              ? const Text('—', style: TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))
              : Text(side,
                  style: TextStyle(
                      color: side == 'BUY' ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                      fontSize: kFontSizeBodySmall,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold)),
        ),
        SizedBox(
            width: _colWidths[8],
            child: Text(avgRate == null ? '—' : avgRate.toStringAsFixed(2),
                style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))),
        SizedBox(
            width: _colWidths[9],
            child: Text(ltp == null ? '—' : ltp.toStringAsFixed(2),
                style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily))),
      ]),
    );
  }
}
