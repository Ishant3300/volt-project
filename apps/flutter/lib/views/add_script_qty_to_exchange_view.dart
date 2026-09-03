import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../utils/contants.dart';

class AddScriptQtyToExchangeView extends StatefulWidget {
  final String exchange;
  final bool isExistingGroup;
  final String? ownerId;
  final String? ownerType;

  const AddScriptQtyToExchangeView({
    super.key,
    required this.exchange,
    this.isExistingGroup = false,
    this.ownerId,
    this.ownerType,
  });

  @override
  State<AddScriptQtyToExchangeView> createState() => _AddScriptQtyToExchangeViewState();
}

class _AddScriptQtyToExchangeViewState extends State<AddScriptQtyToExchangeView> {
  List<_ScriptQtyEntry> _instruments = [];
  List<_ScriptQtyEntry> _filteredInstruments = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  static const _lotBasedSegments = {'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT'};

  String get _effectiveExchange =>
      widget.exchange.toUpperCase() == 'GLOBAL' ? 'INDICES' : widget.exchange;

  bool get _isLotBased => _lotBasedSegments.contains(widget.exchange.toUpperCase());
  String get _qtyLabel => _isLotBased ? 'Max Lots' : 'Max Qty';
  String get _brkLabel => _isLotBased ? 'Break Lots' : 'Break Qty';

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final inst in _instruments) {
      inst.maxQtyCtrl.dispose();
      inst.brkQtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInstruments() async {
    setState(() => _isLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      if (!widget.isExistingGroup) {
        final bulkResponse = await adminService.bulkCreateScriptQuantity(
          exchangeName: _effectiveExchange,
          defaultMaxQty: _isLotBased ? 5 : 100,
          defaultBrkQty: _isLotBased ? 2 : 50,
          ownerId: widget.ownerId,
          ownerType: widget.ownerType,
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

      final response = await adminService.getScriptQuantityByExchange(
        exchangeName: _effectiveExchange,
        ownerId: widget.ownerId,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data']['items'] as List<dynamic>;
        _instruments = items.map((i) => _ScriptQtyEntry(
          id: i['id'] ?? '',
          scriptName: i['script_name'] ?? '',
          lotSize: (i['lot_size'] ?? 1).toInt(),
          maxQty: (i['max_qty'] ?? 0).toDouble(),
          brkQty: (i['brk_qty'] ?? 0).toDouble(),
        )).toList();
      }

      _filteredInstruments = List.from(_instruments);
    } catch (e) {
      log('Error loading script quantities: $e');
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

  Future<void> _saveInstrument(_ScriptQtyEntry entry) async {
    final maxQty = double.tryParse(entry.maxQtyCtrl.text);
    final brkQty = double.tryParse(entry.brkQtyCtrl.text);
    if (maxQty == null || brkQty == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter valid numbers'), backgroundColor: Color(0xFFEF4444),
      ));
      return;
    }
    setState(() => entry.isSaving = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.updateScriptQuantity(
        id: entry.id,
        maxQty: maxQty.toInt(),
        brkQty: brkQty.toInt(),
      );
      if (mounted) {
        if (response.statusCode == 200) {
          entry.maxQty = maxQty;
          entry.brkQty = brkQty;
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          const SizedBox(height: 8),
          _buildInfoBanner(),
          const SizedBox(height: 8),
          _buildSearchBar(),
          const SizedBox(height: 8),
          _buildColumnHeaders(),
          Expanded(child: _isLoading ? _buildLoading() : _buildList()),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
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
            child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Script Quantity',
              style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          Text('${widget.exchange} · ${_instruments.length} instruments',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily)),
        ])),
      ]),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kBrandPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBrandPrimary.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: kIconSizeDefault, color: kBrandPrimary),
        const SizedBox(width: 8),
        Expanded(child: Text(
          _isLotBased
              ? 'Values are in lots. Tap save icon to update each instrument.'
              : 'Values are in quantity. Tap save icon to update each instrument.',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily),
        )),
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
          const Padding(padding: EdgeInsets.only(left: 14, right: 8), child: Icon(Icons.search, color: Color(0xFF94A3B8), size: kIconSizeMedium)),
          Expanded(child: TextField(
            controller: _searchCtrl,
            style: const TextStyle(fontSize: kFontSizeBody, color: Color(0xFF0F172A), fontFamily: kFontFamily),
            decoration: const InputDecoration(
              hintText: 'Filter instruments...', hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: kFontFamily),
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

  Widget _buildColumnHeaders() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Expanded(flex: 3, child: Text('SCRIPT', style: TextStyle(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold, color: Color(0xFF94A3B8), fontFamily: kFontFamily, letterSpacing: 0.5))),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: Text(_qtyLabel.toUpperCase(), style: const TextStyle(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold, color: Color(0xFF94A3B8), fontFamily: kFontFamily, letterSpacing: 0.5))),
        const SizedBox(width: 4),
        Expanded(flex: 2, child: Text(_brkLabel.toUpperCase(), style: const TextStyle(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold, color: Color(0xFF94A3B8), fontFamily: kFontFamily, letterSpacing: 0.5))),
        const SizedBox(width: 4),
        const SizedBox(width: 36),
      ]),
    );
  }

  Widget _buildLoading() {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5),
      SizedBox(height: 16),
      Text('Loading instruments...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
    ]));
  }

  Widget _buildList() {
    if (_filteredInstruments.isEmpty) {
      return const Center(child: Text('No instruments found', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: kFontFamily)));
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
            Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(entry.scriptName,
                  style: const TextStyle(fontSize: kFontSizeBodySmall, fontWeight: kFontWeightSemiBold, color: Color(0xFF0F172A), fontFamily: kFontFamily),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              if (!_isLotBased)
                Text('Lot: ${entry.lotSize}',
                    style: const TextStyle(fontSize: kFontSizeCaption, color: Color(0xFF94A3B8), fontFamily: kFontFamily)),
            ])),
            const SizedBox(width: 4),
            Expanded(flex: 2, child: _buildCompactInput(entry.maxQtyCtrl, () => setState(() => entry.isModified = true))),
            const SizedBox(width: 4),
            Expanded(flex: 2, child: _buildCompactInput(entry.brkQtyCtrl, () => setState(() => entry.isModified = true))),
            const SizedBox(width: 4),
            SizedBox(width: 36, child: entry.isSaving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: kBrandPrimary))
                : GestureDetector(
                    onTap: entry.isModified ? () => _saveInstrument(entry) : null,
                    child: Icon(Icons.check_circle, size: 22,
                      color: entry.isModified ? kBrandPrimary : const Color(0xFFCBD5E1)),
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
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: kFontSizeBodySmall, fontWeight: kFontWeightSemiBold, color: Color(0xFF0F172A), fontFamily: kFontFamily),
        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _ScriptQtyEntry {
  String id;
  final String scriptName;
  final int lotSize;
  double maxQty;
  double brkQty;
  bool isSaving;
  bool isModified;
  final TextEditingController maxQtyCtrl;
  final TextEditingController brkQtyCtrl;

  _ScriptQtyEntry({
    required this.id,
    required this.scriptName,
    required this.lotSize,
    required this.maxQty,
    required this.brkQty,
    this.isSaving = false,
    this.isModified = false,
  })  : maxQtyCtrl = TextEditingController(text: maxQty.toStringAsFixed(0)),
        brkQtyCtrl = TextEditingController(text: brkQty.toStringAsFixed(0));
}
