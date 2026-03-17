import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class IntradayHistoryView extends StatefulWidget {
  const IntradayHistoryView({super.key});
  @override
  State<IntradayHistoryView> createState() => _IntradayHistoryViewState();
}

class _IntradayHistoryViewState extends State<IntradayHistoryView> {
  String _selectedExchange = 'NSE';
  String _selectedInterval = 'minute';
  final _exchanges = ['NSE', 'BSE', 'NFO', 'BFO', 'MCX', 'CDS'];
  final _intervals = ['minute', '3minute', '5minute', '10minute', '15minute', '30minute', '60minute', 'day'];

  final _instCtrl = TextEditingController();
  List<Map<String, dynamic>> _instResults = [];
  Map<String, dynamic>? _selectedInst;
  bool _showDropdown = false;
  bool _isSearching = false;

  List<Map<String, dynamic>> _candles = [];
  bool _isLoading = false;
  int _sortCol = 0;
  bool _sortAsc = true;

  @override
  void dispose() { _instCtrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.length < 2) { setState(() { _instResults = []; _showDropdown = false; }); return; }
    setState(() => _isSearching = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).get(
        '/kite/instruments/search?q=$q&exchange=$_selectedExchange&limit=20', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          setState(() { _instResults = List<Map<String, dynamic>>.from(body['data']); _showDropdown = _instResults.isNotEmpty; });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearching = false);
  }

  void _selectInst(Map<String, dynamic> inst) {
    setState(() { _selectedInst = inst; _instCtrl.text = inst['tradingsymbol'] ?? ''; _showDropdown = false; _instResults = []; });
  }

  Future<void> _fetch() async {
    if (_selectedInst == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an instrument'))); return; }
    setState(() { _isLoading = true; _candles = []; });
    try {
      final token = await SecureStorageService().getToken();
      final t = _selectedInst!['instrument_token'];
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final res = await ApiService(backendUrl).get('/kite/historical/$t/$_selectedInterval?from=$today&to=$today', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          setState(() => _candles = List<Map<String, dynamic>>.from(body['data']));
        }
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  void _clear() { setState(() { _selectedInst = null; _instCtrl.clear(); _candles = []; _instResults = []; _showDropdown = false; }); }

  void _sort(int col) {
    setState(() {
      if (_sortCol == col) { _sortAsc = !_sortAsc; } else { _sortCol = col; _sortAsc = true; }
      final keys = ['date', 'open', 'high', 'low', 'close', 'volume'];
      final k = keys[col];
      _candles.sort((a, b) {
        final av = a[k], bv = b[k];
        if (av is num && bv is num) return _sortAsc ? av.compareTo(bv) : bv.compareTo(av);
        return _sortAsc ? av.toString().compareTo(bv.toString()) : bv.toString().compareTo(av.toString());
      });
    });
  }

  String _fmtTime(String dateStr) {
    try { return DateFormat('HH:mm:ss').format(DateTime.parse(dateStr).toLocal()); } catch (_) { return dateStr; }
  }

  @override
  Widget build(BuildContext context) {
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
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Intraday History', style: TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            ]),
          ),
          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              // Exchange + Instrument
              Row(children: [
                _buildDropdown<String>(_selectedExchange, _exchanges, (v) {
                  setState(() { _selectedExchange = v!; _selectedInst = null; _instCtrl.clear(); _candles = []; });
                }),
                const SizedBox(width: 10),
                Expanded(child: _buildInstField()),
              ]),
              // Instrument dropdown results
              if (_showDropdown) _buildInstDropdown(),
              const SizedBox(height: 10),
              // Interval + View + Clear
              Row(children: [
                _buildDropdown<String>(_selectedInterval, _intervals, (v) => setState(() => _selectedInterval = v!)),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _isLoading ? null : _fetch,
                    child: Container(
                      height: 44, alignment: Alignment.center,
                      decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(12)),
                      child: _isLoading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('View', style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _clear,
                  child: Container(
                    height: 44, padding: const EdgeInsets.symmetric(horizontal: 20), alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: const Text('Clear', style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 12),
          // Table header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(children: List.generate(6, (i) {
              final labels = ['Timing', 'Open', 'High', 'Low', 'Close', 'Volume'];
              final isSorted = _sortCol == i;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _sort(i),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(labels[i], style: TextStyle(
                        color: isSorted ? const Color(0xFF3F45C7) : const Color(0xFF94A3B8),
                        fontSize: 11, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                      const SizedBox(width: 2),
                      Icon(isSorted ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                        size: 12, color: isSorted ? const Color(0xFF3F45C7) : const Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              );
            })),
          ),
          // Table body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
                : _candles.isEmpty
                    ? Center(child: Text(
                        _selectedInst == null ? 'Select an instrument and tap View' : 'No data available',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Inter')))
                    : Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: _candles.length,
                          itemBuilder: (_, i) => _buildRow(_candles[i], i),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildDropdown<T>(T value, List<T> items, ValueChanged<T?> onChanged) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8)),
          style: const TextStyle(color: Colors.black, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600),
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString()))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildInstField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: TextField(
        controller: _instCtrl,
        onChanged: _search,
        style: const TextStyle(fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: 'Search instrument...',
          hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter'),
          suffixIcon: _isSearching
              ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3F45C7))))
              : (_instCtrl.text.isNotEmpty
                  ? GestureDetector(
                      onTap: () { _instCtrl.clear(); setState(() { _selectedInst = null; _instResults = []; _showDropdown = false; }); },
                      child: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)))
                  : const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildInstDropdown() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        itemCount: _instResults.length,
        itemBuilder: (_, i) {
          final inst = _instResults[i];
          final sym = inst['tradingsymbol'] ?? '';
          final name = inst['name'] ?? '';
          final type = inst['instrument_type'] ?? '';
          return GestureDetector(
            onTap: () => _selectInst(inst),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: const Color(0xFFF1F5F9), width: i < _instResults.length - 1 ? 1 : 0))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sym, style: const TextStyle(color: Colors.black, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                  if (name.isNotEmpty) Text(name, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Inter'), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                  child: Text(type, style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> c, int index) {
    final time = _fmtTime(c['date']?.toString() ?? '');
    final open = (c['open'] as num?)?.toDouble() ?? 0;
    final high = (c['high'] as num?)?.toDouble() ?? 0;
    final low = (c['low'] as num?)?.toDouble() ?? 0;
    final close = (c['close'] as num?)?.toDouble() ?? 0;
    final volume = (c['volume'] as num?)?.toInt() ?? 0;
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFAFBFC),
        border: Border(bottom: BorderSide(color: const Color(0xFFF1F5F9), width: 0.5)),
      ),
      child: Row(children: [
        _cell(time, isBold: true),
        _cell(open.toStringAsFixed(1)),
        _cell(high.toStringAsFixed(1)),
        _cell(low.toStringAsFixed(1)),
        _cell(close.toStringAsFixed(1)),
        _cell(volume.toString()),
      ]),
    );
  }

  Widget _cell(String text, {bool isBold = false}) {
    return Expanded(
      child: Text(text, textAlign: TextAlign.center,
        style: TextStyle(
          color: isBold ? Colors.black : const Color(0xFF334155),
          fontSize: 12, fontFamily: 'Inter',
          fontWeight: isBold ? FontWeight.w600 : FontWeight.w400)),
    );
  }
}
