import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'add_trade_margin_to_exchange_view.dart';

class TradeMarginSettingsView extends StatefulWidget {
  const TradeMarginSettingsView({super.key});
  @override
  State<TradeMarginSettingsView> createState() =>
      _TradeMarginSettingsViewState();
}

class _TradeMarginSettingsViewState extends State<TradeMarginSettingsView> {
  final _amountCtrl = TextEditingController();
  String? _selectedExchange;
  String _selectedAmountType = 'amount';
  final _exchanges = [
    'NFO-FUT',
    'NFO-OPT',
    'MCX-FUT',
    'MCX-OPT',
    'GLOBAL',
    'SGX'
  ];
  final _amountTypes = ['amount', 'percentage'];
  static const _amountSegments = {'MCX-FUT', 'MCX-OPT'};
  List<Map<String, dynamic>> _items = [];
  Map<String, bool> _selected = {};
  bool _isLoading = false;
  bool _hasInitialized = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkRole();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized && _selectedExchange == null) {
        setState(() {
          _selectedExchange = _exchanges.first;
          _selectedAmountType = _amountSegments.contains(_exchanges.first)
              ? 'amount'
              : 'percentage';
          _hasInitialized = true;
        });
        _fetch();
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkRole() async {
    final role = await SecureStorageService().getRole();
    setState(() => _isAdmin = role == 'ADMIN');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitialized && _selectedExchange != null) _fetch();
  }

  Future<void> _fetch() async {
    if (_selectedExchange == null) return;
    setState(() {
      _isLoading = true;
      _items = [];
      _selected = {};
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final effectiveExchange =
          _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange!;
      final res = await AdminService(apiService).getTradeMarginByExchange(
        exchangeName: effectiveExchange,
        amountType: _selectedAmountType,
        limit: 2000,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final List<dynamic> items = data['data']['items'] ?? [];
          List<Map<String, dynamic>> filtered = [];
          for (var m in items) {
            filtered.add({
              'id': m['id'],
              'script_name': m['script_name'],
              'trade_margin': m['trade_margin'],
              'amount_type': m['amount_type'],
              'exchange_name': m['exchange_name']
            });
          }
          setState(() => _items = filtered);
        }
      }
    } catch (e) {
      log('❌ Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _apply() async {
    if (_selectedExchange == null) return;
    final value = double.tryParse(_amountCtrl.text);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid value')));
      return;
    }
    final scripts =
        _selected.entries.where((e) => e.value).map((e) => e.key).toList();
    if (scripts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one script')));
      return;
    }
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final admin = AdminService(apiService);
      int ok = 0, fail = 0;
      for (var item in _items) {
        if (scripts.contains(item['script_name'])) {
          final effectiveExchange =
              _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange;
          final r = await admin.updateTradeMargin(
              id: item['id'],
              amountType: _selectedAmountType,
              exchangeName: effectiveExchange,
              scriptName: item['script_name'],
              tradeMargin: value);
          r.statusCode == 200 ? ok++ : fail++;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Updated $ok${fail > 0 ? ", $fail failed" : ""}'),
            backgroundColor: const Color(0xFF10B981)));
        _amountCtrl.clear();
        _selected.clear();
        _fetch();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _toggleAll() {
    final allSelected =
        _items.every((i) => _selected[i['script_name']] == true);
    setState(() {
      for (var i in _items) {
        _selected[i['script_name']] = !allSelected;
      }
    });
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2))
                          ]),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black, size: 20))),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('Trade Margin Settings',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600))),
              if (_isAdmin) ...[
                GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AddTradeMarginToExchangeView(
                        exchange: _selectedExchange!,
                        amountType: _selectedAmountType,
                        isExistingGroup: _items.isNotEmpty,
                      ),
                    )).then((_) => _fetch());
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(10)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Create', style: TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w600))
                      ])),
                ),
              ],
            ])),

        // Exchange chips
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _exchanges.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final ex = _exchanges[i];
                  final sel = ex == _selectedExchange;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedExchange = ex;
                        _selectedAmountType =
                            _amountSegments.contains(ex)
                                ? 'amount'
                                : 'percentage';
                      });
                      _fetch();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF3F45C7) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: sel
                            ? null
                            : Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(ex,
                          style: TextStyle(
                              color:
                                  sel ? Colors.white : const Color(0xFF64748B),
                              fontSize: 13,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600)),
                    ),
                  );
                },
              ),
            )),
        const SizedBox(height: 8),

        // Amount type dropdown (locked based on exchange)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Opacity(
              opacity: 0.6,
              child: _dropdown(_selectedAmountType, _amountTypes, null),
            )),
        const SizedBox(height: 8),

        // Value + Apply
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                  child: Container(
                height: 42,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12)),
                    border: Border.all(color: const Color(0xFFE2E8F0))),
                child: TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                        fontSize: 13,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                        hintText: 'Value',
                        hintStyle: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 13,
                            fontFamily: 'Inter'),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: InputBorder.none)),
              )),
              GestureDetector(
                  onTap: _apply,
                  child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                          color: Color(0xFF3F45C7),
                          borderRadius: BorderRadius.only(
                              topRight: Radius.circular(12),
                              bottomRight: Radius.circular(12))),
                      child: const Text('Apply',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600)))),
            ])),
        const SizedBox(height: 10),

        // Table header
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                GestureDetector(
                    onTap: _items.isNotEmpty ? _toggleAll : null,
                    child: _headerCheck()),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('SCRIPT',
                        style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5))),
                const Text('MARGIN',
                    style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5)),
              ]),
            )),
        const SizedBox(height: 4),

        // List
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF3F45C7), strokeWidth: 2.5))
              : _items.isEmpty
                  ? Center(
                      child: Text(
                          _isAdmin
                              ? 'No settings found. Create one!'
                              : 'No settings found',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontFamily: 'Inter')))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final name = item['script_name'] as String;
                        final sel = _selected[name] ?? false;
                        return GestureDetector(
                          onTap: () => setState(() => _selected[name] = !sel),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: const Color(0xFFF1F5F9),
                                        width: i < _items.length - 1 ? 1 : 0))),
                            child: Row(children: [
                              _checkCircle(sel),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          color: Color(0xFF334155),
                                          fontSize: 13,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w500))),
                              Text('${item['trade_margin']}',
                                  style: const TextStyle(
                                      color: Color(0xFF3F45C7),
                                      fontSize: 13,
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        );
                      }),
        ),
      ])),
    );
  }

  Widget _dropdown(
      String? value, List<String> items, ValueChanged<String?>? onChanged,
      {Map<String, String>? displayMap}) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ]),
      child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down,
            size: 18, color: Color(0xFF94A3B8)),
        style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500),
        items: items
            .map((k) => DropdownMenuItem(
                value: k,
                child:
                    Text(displayMap?[k] ?? k, overflow: TextOverflow.ellipsis)))
            .toList(),
        onChanged: onChanged,
      )),
    );
  }

  Widget _headerCheck() {
    final all = _items.isNotEmpty &&
        _items.every((i) => _selected[i['script_name']] == true);
    return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            color: all ? const Color(0xFF3F45C7) : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: all ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                width: 1.5)),
        child: all
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null);
  }

  Widget _checkCircle(bool sel) {
    return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            color: sel ? const Color(0xFF3F45C7) : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: sel ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                width: 1.5)),
        child: sel
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null);
  }
}
