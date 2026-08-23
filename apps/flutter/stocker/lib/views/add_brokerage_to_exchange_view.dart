import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../utils/contants.dart';

class AddBrokerageToExchangeView extends StatefulWidget {
  final String exchange;
  final String type;
  final bool isExistingGroup;

  const AddBrokerageToExchangeView({
    super.key,
    required this.exchange,
    required this.type,
    this.isExistingGroup = false,
  });

  @override
  State<AddBrokerageToExchangeView> createState() => _AddBrokerageToExchangeViewState();
}

class _AddBrokerageToExchangeViewState extends State<AddBrokerageToExchangeView> {
  List<_BrkEntry> _instruments = [];
  List<_BrkEntry> _filteredInstruments = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  String get _effectiveExchange =>
      widget.exchange.toUpperCase() == 'GLOBAL' ? 'INDICES' : widget.exchange;

  bool get _isLotWise => widget.type.toUpperCase() == 'LOT WISE';

  @override
  void initState() {
    super.initState();
    _loadInstruments();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final inst in _instruments) {
      inst.brkCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInstruments() async {
    setState(() => _isLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      if (!widget.isExistingGroup) {
        // Bulk create first
        final bulkResponse = await adminService.bulkCreateBrokerage(
          exchangeName: _effectiveExchange,
          type: widget.type,
          defaultBrkValue: 0,
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

      // Load items
      final response = await adminService.getBrokerageByExchange(
        exchangeName: _effectiveExchange,
        type: widget.type,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['data']['items'] as List<dynamic>;
        _instruments = items.map((i) => _BrkEntry(
          id: i['id'] ?? '',
          scriptName: i['script_name'] ?? '',
          brkValue: (i['brk_value'] ?? 0).toDouble(),
          isLotWise: _isLotWise,
        )).toList();
      }

      _filteredInstruments = List.from(_instruments);
    } catch (e) {
      log('Error loading brokerage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
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

  Future<void> _saveInstrument(_BrkEntry entry) async {
    final value = double.tryParse(entry.brkCtrl.text);
    if (value == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a valid number'),
        backgroundColor: Color(0xFFEF4444),
      ));
      return;
    }
    setState(() => entry.isSaving = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.updateBrokerageSettings(
        id: entry.id,
        brkValue: value,
      );
      if (mounted) {
        if (response.statusCode == 200) {
          entry.brkValue = value;
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
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
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
          Text('Brokerage · ${widget.type}',
              style: const TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
          Text('${widget.exchange} · ${_instruments.length} instruments',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter')),
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
      child: const Row(children: [
        Icon(Icons.info_outline, size: kIconSizeDefault, color: kBrandPrimary),
        SizedBox(width: 8),
        Expanded(child: Text('Tap save icon to update each instrument\'s brokerage value.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeSubtitle, fontFamily: 'Inter'))),
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
            style: const TextStyle(fontSize: kFontSizeBody, color: Color(0xFF0F172A), fontFamily: 'Inter'),
            decoration: const InputDecoration(
              hintText: 'Filter instruments...', hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: 'Inter'),
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
      child: const Row(children: [
        Expanded(flex: 3, child: Text('SCRIPT', style: TextStyle(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold, color: Color(0xFF94A3B8), fontFamily: 'Inter', letterSpacing: 0.5))),
        SizedBox(width: 4),
        Expanded(flex: 2, child: Text('BRK VALUE', style: TextStyle(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold, color: Color(0xFF94A3B8), fontFamily: 'Inter', letterSpacing: 0.5))),
        SizedBox(width: 4),
        SizedBox(width: 36),
      ]),
    );
  }

  Widget _buildLoading() {
    return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5),
      SizedBox(height: 16),
      Text('Loading instruments...', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: 'Inter')),
    ]));
  }

  Widget _buildList() {
    if (_filteredInstruments.isEmpty) {
      return const Center(child: Text('No instruments found', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: 'Inter')));
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
                style: const TextStyle(fontSize: kFontSizeBodySmall, fontWeight: kFontWeightSemiBold, color: Color(0xFF0F172A), fontFamily: 'Inter'),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            Expanded(flex: 2, child: _buildCompactInput(entry.brkCtrl, () => setState(() => entry.isModified = true), integerOnly: _isLotWise)),
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

  Widget _buildCompactInput(TextEditingController ctrl, VoidCallback onChanged, {bool integerOnly = false}) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: ctrl,
        keyboardType: integerOnly
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: integerOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: const TextStyle(fontSize: kFontSizeBodySmall, fontWeight: kFontWeightSemiBold, color: Color(0xFF0F172A), fontFamily: 'Inter'),
        decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 10)),
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

class _BrkEntry {
  String id;
  final String scriptName;
  double brkValue;
  bool isSaving;
  bool isModified;
  final TextEditingController brkCtrl;

  _BrkEntry({
    required this.id,
    required this.scriptName,
    required this.brkValue,
    bool isLotWise = false,
    this.isSaving = false,
    this.isModified = false,
  }) : brkCtrl = TextEditingController(
            text: isLotWise ? brkValue.toStringAsFixed(0) : brkValue.toStringAsFixed(2));
}
