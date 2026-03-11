import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/kite_service.dart';
import '../models/kite_instrument.dart';

class CreateBrokerageView extends StatefulWidget {
  const CreateBrokerageView({super.key});
  @override
  State<CreateBrokerageView> createState() => _CreateBrokerageViewState();
}

class _CreateBrokerageViewState extends State<CreateBrokerageView> {
  String _selectedExchange = 'NSE';
  String _selectedType = 'TURNOVER WISE';
  final _exchanges = ['NSE', 'MCX', 'SGX', 'CALLPUT', 'OTHERS', 'MCX-OPT'];
  final _types = ['TURNOVER WISE', 'LOT WISE'];
  final _searchCtrl = TextEditingController();
  List<KiteInstrument> _results = [];
  bool _isSearching = false;

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q.isEmpty) { setState(() => _results = []); return; }
    setState(() => _isSearching = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final results = await KiteService(apiService).searchInstruments(q, exchange: _selectedExchange);
      setState(() { _results = results.map((j) => KiteInstrument.fromJson(j)).toList(); _isSearching = false; });
    } catch (e) { setState(() => _isSearching = false); }
  }

  void _showAddDialog(KiteInstrument inst) {
    final valueCtrl = TextEditingController();
    String localType = _selectedType;
    bool adding = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Add Brokerage', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(inst.tradingsymbol, style: const TextStyle(color: Color(0xFF22547C), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: -0.3)),
        const SizedBox(height: 14),
        _dialogDropdown(localType, _types, (v) => setD(() => localType = v!)),
        const SizedBox(height: 12),
        _dialogField(valueCtrl, 'Brokerage value'),
      ]),
      actions: [
        TextButton(onPressed: adding ? null : () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Inter'))),
        GestureDetector(
          onTap: adding ? null : () async {
            final v = double.tryParse(valueCtrl.text);
            if (v == null || v <= 0) return;
            setD(() => adding = true);
            try {
              final apiService = Provider.of<ApiService>(ctx, listen: false);
              final r = await AdminService(apiService).createBrokerageSettings(type: localType, exchangeName: _selectedExchange, scriptName: inst.tradingsymbol, brkValue: v);
              setD(() => adding = false);
              if (r.statusCode == 201) { if (ctx.mounted) Navigator.pop(ctx); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Created'), backgroundColor: Color(0xFF10B981))); }
              else { final d = jsonDecode(r.body); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(d['message'] ?? 'Failed'), backgroundColor: const Color(0xFFEF4444))); }
            } catch (e) { setD(() => adding = false); }
          },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF22547C), borderRadius: BorderRadius.circular(10)),
            child: adding
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Add', style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
        ),
      ],
    )));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      resizeToAvoidBottomInset: true,
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: const Icon(Icons.arrow_back, color: Colors.black, size: 20))),
          const SizedBox(width: 12),
          const Text('Create Brokerage', style: TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        ])),

        // Exchange chips
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(height: 36,
          child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _exchanges.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final ex = _exchanges[i]; final sel = ex == _selectedExchange;
              return GestureDetector(
                onTap: () { setState(() { _selectedExchange = ex; _results = []; _searchCtrl.clear(); }); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
                  decoration: BoxDecoration(color: sel ? const Color(0xFF22547C) : Colors.white, borderRadius: BorderRadius.circular(10), border: sel ? null : Border.all(color: const Color(0xFFE2E8F0))),
                  child: Text(ex, style: TextStyle(color: sel ? Colors.white : const Color(0xFF64748B), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600))),
              );
            }),
        )),
        const SizedBox(height: 12),

        // Search
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(height: 42,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
          child: TextField(controller: _searchCtrl, onChanged: _search,
            style: const TextStyle(fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w500),
            decoration: InputDecoration(
              hintText: 'Search instruments...', hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter'),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
              suffixIcon: _isSearching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF22547C)))) : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 12), border: InputBorder.none)),
        )),
        const SizedBox(height: 8),

        // Results
        Expanded(child: _results.isEmpty
          ? const Center(child: Text('Search for an instrument to add', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Inter')))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _results.length, itemBuilder: (_, i) {
              final inst = _results[i];
              return GestureDetector(
                onTap: () => _showAddDialog(inst),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(inst.tradingsymbol, style: const TextStyle(color: Color(0xFF22547C), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                      if (inst.name.isNotEmpty) Text(inst.name, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Inter')),
                    ])),
                    const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF22547C)),
                  ]),
                ),
              );
            }),
        ),
      ])),
    );
  }

  Widget _dialogDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(height: 42, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: DropdownButtonHideUnderline(child: DropdownButton<String>(
        value: value, isExpanded: true, icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8)),
        style: const TextStyle(color: Colors.black, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w500),
        items: items.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(), onChanged: onChanged,
      )),
    );
  }

  Widget _dialogField(TextEditingController ctrl, String hint) {
    return TextField(controller: ctrl, keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w500),
      decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), filled: true, fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF22547C), width: 1.5))));
  }
}
