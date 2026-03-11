import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'add_instrument_to_lot_view.dart';

class GroupQuantityLotDetailView extends StatefulWidget {
  final String exchange;
  final String lotName;
  const GroupQuantityLotDetailView({super.key, required this.exchange, required this.lotName});
  @override
  State<GroupQuantityLotDetailView> createState() => _GroupQuantityLotDetailViewState();
}

class _GroupQuantityLotDetailViewState extends State<GroupQuantityLotDetailView> {
  List<Map<String, dynamic>> _instruments = [];
  bool _isLoading = false;
  bool _isAdmin = false;
  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() { super.initState(); _checkUserRole(); _fetchLotData(); }

  Future<void> _checkUserRole() async {
    final role = await _storage.getRole();
    setState(() => _isAdmin = role == 'ADMIN');
  }

  Future<void> _fetchLotData() async {
    setState(() => _isLoading = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.getAllGroupedQuantities(limit: 1000);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> allDocs = data['data']['grouped_quantities'] ?? [];
          List<Map<String, dynamic>> filtered = [];
          for (var doc in allDocs) {
            if (doc['exchange_name']?.toString().toUpperCase() == widget.exchange && doc['lot_name'] == widget.lotName) {
              filtered.add({'id': doc['id'], 'instrument_id': doc['instrument_id'], 'instrument_symbol': doc['instrument_symbol'], 'max_qty': doc['max_qty'], 'break_qty': doc['break_qty'], 'lot_size': doc['lot_size']});
            }
          }
          setState(() => _instruments = filtered);
        }
      }
    } catch (e) { log('❌ Error: $e'); }
    finally { if (mounted) setState(() => _isLoading = false); }
  }

  Future<void> _deleteInstrument(String docId, String symbol) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.deleteGroupedQuantity(docId);
      if (response.statusCode == 200) {
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Instrument deleted'), backgroundColor: Color(0xFF10B981))); _fetchLotData(); }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? 'Failed'), backgroundColor: const Color(0xFFEF4444)));
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444))); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: const Icon(Icons.arrow_back, color: Colors.black, size: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.lotName, style: const TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            Text('${widget.exchange} · ${_instruments.length} instruments', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: 'Inter')),
          ])),
        ])),

        // Add button (admin)
        if (_isAdmin)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AddInstrumentToLotView(exchange: widget.exchange, lotName: widget.lotName))).then((_) => _fetchLotData()),
            child: Container(height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF22547C), borderRadius: BorderRadius.circular(12)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add, color: Colors.white, size: 18), SizedBox(width: 6),
                Text('Add Instrument', style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
              ]),
            ),
          )),
        if (_isAdmin) const SizedBox(height: 12),

        // List
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF22547C), strokeWidth: 2.5))
          : _instruments.isEmpty
            ? const Center(child: Text('No instruments added yet', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Inter')))
            : RefreshIndicator(onRefresh: _fetchLotData, child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _instruments.length,
                itemBuilder: (_, i) {
                  final inst = _instruments[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(inst['instrument_symbol'] ?? 'N/A', style: const TextStyle(color: Color(0xFF22547C), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: -0.3)),
                        const SizedBox(height: 8),
                        Row(children: [
                          _chip('Max', '${inst['max_qty']}'),
                          const SizedBox(width: 6),
                          _chip('Brk', '${inst['break_qty']}'),
                          const SizedBox(width: 6),
                          _chip('Lot', '${inst['lot_size']}'),
                        ]),
                      ])),
                      if (_isAdmin)
                        GestureDetector(
                          onTap: () => showDialog(context: context, builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            title: const Text('Delete Instrument', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16)),
                            content: const Text('Are you sure?', style: TextStyle(fontFamily: 'Inter', fontSize: 13)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Inter'))),
                              GestureDetector(
                                onTap: () { Navigator.pop(ctx); _deleteInstrument(inst['id'], inst['instrument_symbol']); },
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Delete', style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 13))),
                              ),
                            ],
                          )),
                          child: Container(width: 36, height: 36,
                            decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444))),
                        ),
                    ]),
                  );
                },
              )),
        ),
      ])),
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: 0.3)),
        Text(value, style: const TextStyle(color: Color(0xFF334155), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
