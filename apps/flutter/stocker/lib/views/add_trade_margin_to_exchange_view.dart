import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';

class AddTradeMarginToExchangeView extends StatefulWidget {
  final String exchange;
  final String amountType;
  final bool isExistingGroup;

  const AddTradeMarginToExchangeView({
    super.key,
    required this.exchange,
    required this.amountType,
    this.isExistingGroup = false,
  });

  @override
  State<AddTradeMarginToExchangeView> createState() => _AddTradeMarginToExchangeViewState();
}

class _AddTradeMarginToExchangeViewState extends State<AddTradeMarginToExchangeView> {
  List<_MarginEntry> _instruments = [];
  List<_MarginEntry> _filteredInstruments = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  String get _effectiveExchange =>
      widget.exchange.toUpperCase() == 'GLOBAL' ? 'INDICES' : widget.exchange;

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final inst in _instruments) {
      inst.marginCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInstruments() async {
    setState(() => _isLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      if (!widget.isExistingGroup) {
        final bulkResponse = await adminService.bulkCreateTradeMargin(
          exchangeName: _effectiveExchange,
          amountType: widget.amountType,
          defaultTradeMargin: 0,
        );
        if (bulkResponse.statusCode != 201) {
          final data = jsonDecode(bulkResponse.body);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(data['message'] ?? 'Failed to create'),
              backgroundColor: const Color(0xFFEF4444),
            ));
          }
        }
      }

      final response = await adminService.getTradeMarginByExchange(
        exchangeName: _effectiveExchange,
        amountType: widget.amountType,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data']['items'] as List<dynamic>;
        _instruments = items.map((i) => _MarginEntry(
          id: i['id'] ?? '',
          scriptName: i['script_name'] ?? '',
          tradeMargin: (i['trade_margin'] ?? 0).toDouble(),
        )).toList();
      }

      _filteredInstruments = List.from(_instruments);
    } catch (e) {
      log('Error loading trade margins: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _filterInstruments(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredInstruments = List.from(_instruments);
      } else {
        final upper = query.toUpperCase();
        _filteredInstruments = _instruments
            .where((i) => i.scriptName.toUpperCase().contains(upper))
            .toList();
      }
    });
  }

  Future<void> _saveInstrument(_MarginEntry entry) async {
    final value = double.tryParse(entry.marginCtrl.text);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid number'), backgroundColor: Color(0xFFEF4444),
      ));
      return;
    }
    setState(() => entry.isSaving = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.updateTradeMargin(
        id: entry.id,
        tradeMargin: value,
      );
      if (mounted) {
        if (response.statusCode == 200) {
          entry.tradeMargin = value;
          entry.isModified = false;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${entry.scriptName} updated'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 1),
          ));
        } else {
          final data = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(data['message'] ?? 'Failed'),
            backgroundColor: const Color(0xFFEF4444),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444),
        ));
      }
    }
    if (mounted) setState(() => entry.isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.amountType == 'percentage' ? 'Percentage' : 'Amount';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(label),
          const SizedBox(height: 8),
          _buildInfoBanner(label),
          const SizedBox(height: 8),
          _buildSearchBar(),
          const SizedBox(height: 8),
          _buildColumnHeaders(label),
          Expanded(child: _isLoading ? _buildLoading() : _buildList()),
        ]),
      ),
    );
  }

  Widget _buildHeader(String label) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context, true),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Trade Margin · $label',
              style: const TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          Text('${widget.exchange} · ${_instruments.length} instruments',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: 'Inter')),
        ])),
      ]),
    );
  }

  Widget _buildInfoBanner(String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3F45C7).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3F45C7).withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 16, color: Color(0xFF3F45C7)),
        const SizedBox(width: 8),
        Expanded(child: Text('Values are in ${label.toLowerCase()}. Tap save icon to update.',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontFamily: 'Inter'))),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          const Padding(padding: EdgeInsets.only(left: 14, right: 8), child: Icon(Icons.search, color: Color(0xFF94A3B8), size: 20)),
          Expanded(child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), fontFamily: 'Inter'),
            decoration: const InputDecoration(
              hintText: 'Filter instruments...', hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontFamily: 'Inter'),
              border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 12),
            ),
            onChanged: _filterInstruments,
          )),
          if (_searchQuery.isNotEmpty)
            GestureDetector(
              onTap: () { _searchCtrl.clear(); _filterInstruments(''); },
              child: const Padding(padding: EdgeInsets.only(right: 14), child: Icon(Icons.close, color: Color(0xFF94A3B8), size: 18)),
            ),
        ]),
      ),
    );
  }

  Widget _buildColumnHeaders(String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Expanded(flex: 3, child: Text('SCRIPT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), fontFamily: 'Inter', letterSpacing: 0.5))),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF94A3B8), fontFamily: 'Inter', letterSpacing: 0.5))),
        const SizedBox(width: 4),
        const SizedBox(width: 36),
      ]),
    );
  }

  Widget _buildLoading() {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5),
      SizedBox(height: 16),
      Text('Loading instruments...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Inter')),
    ]));
  }

  Widget _buildList() {
    if (_filteredInstruments.isEmpty) {
      return const Center(child: Text('No instruments found', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontFamily: 'Inter')));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      itemCount: _filteredInstruments.length,
      itemBuilder: (context, index) {
        final entry = _filteredInstruments[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10),
            border: entry.isModified ? Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.5)) : null,
          ),
          child: Row(children: [
            Expanded(flex: 3, child: Text(entry.scriptName,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A), fontFamily: 'Inter'),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            Expanded(flex: 2, child: _buildCompactInput(entry.marginCtrl, () => setState(() => entry.isModified = true))),
            const SizedBox(width: 4),
            SizedBox(width: 36, child: entry.isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3F45C7)))
                : GestureDetector(
                    onTap: entry.isModified ? () => _saveInstrument(entry) : null,
                    child: Icon(Icons.check_circle, size: 22,
                      color: entry.isModified ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1)),
                  )),
          ]),
        );
      },
    );
  }

  Widget _buildCompactInput(TextEditingController ctrl, VoidCallback onChanged) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F172A), fontFamily: 'Inter'),
        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _MarginEntry {
  String id;
  final String scriptName;
  double tradeMargin;
  bool isSaving;
  bool isModified;
  final TextEditingController marginCtrl;

  _MarginEntry({
    required this.id,
    required this.scriptName,
    required this.tradeMargin,
    this.isSaving = false,
    this.isModified = false,
  }) : marginCtrl = TextEditingController(text: tradeMargin.toStringAsFixed(2));
}
