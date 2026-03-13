import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'group_quantity_lot_detail_view.dart';

class GroupQuantityView extends StatefulWidget {
  const GroupQuantityView({super.key});
  @override
  State<GroupQuantityView> createState() => _GroupQuantityViewState();
}

class _GroupQuantityViewState extends State<GroupQuantityView> {
  String? _selectedExchange;
  final List<String> _exchanges = [
    'NFO-FUT',
    'NFO-OPT',
    'MCX-FUT',
    'MCX-OPT',
    'GLOBAL',
    'SGX'
  ];
  Map<String, int> _lotCounts = {};
  bool _isLoading = false;
  bool _hasInitialized = false;
  bool _isAdmin = false;
  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized && _selectedExchange == null) {
        setState(() {
          _selectedExchange = _exchanges.first;
          _hasInitialized = true;
        });
        _fetchGroupQuantities();
      }
    });
  }

  Future<void> _checkUserRole() async {
    final role = await _storage.getRole();
    setState(() => _isAdmin = role == 'ADMIN');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitialized && _selectedExchange != null) _fetchGroupQuantities();
  }

  Future<void> _fetchGroupQuantities() async {
    if (_selectedExchange == null) return;
    log('📊 Fetching group quantities for: $_selectedExchange');
    setState(() {
      _isLoading = true;
      _lotCounts = {};
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final response = await adminService.getAllGroupedQuantities(limit: 1000);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> allDocs =
              data['data']['grouped_quantities'] ?? [];
          Map<String, int> counts = {};
          final effectiveExchange =
              _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange;
          for (var doc in allDocs) {
            if (doc['exchange_name']?.toString().toUpperCase() ==
                effectiveExchange) {
              final lotName = doc['lot_name'];
              counts[lotName] = (counts[lotName] ?? 0) + 1;
            }
          }
          setState(() {
            _lotCounts = counts;
          });
        }
      }
    } catch (e) {
      log('❌ Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateLotDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create New Lot',
            style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
                fontSize: 16)),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a name for the new lot.',
                  style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                      fontFamily: 'Inter')),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Lot name',
                  hintStyle: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                      fontFamily: 'Inter'),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: Color(0xFF22547C), width: 1.5)),
                ),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600))),
          GestureDetector(
            onTap: () {
              if (controller.text.isNotEmpty) {
                Navigator.pop(ctx);
                Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => GroupQuantityLotDetailView(
                                exchange: _selectedExchange!,
                                lotName: controller.text)))
                    .then((_) => _fetchGroupQuantities());
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFF22547C),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('Next',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
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
                        color: Colors.black, size: 20)),
              ),
              const SizedBox(width: 12),
              const Text('Group Quantity',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600)),
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
                      setState(() => _selectedExchange = ex);
                      _fetchGroupQuantities();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFF22547C) : Colors.white,
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
        const SizedBox(height: 12),

        // Create button (admin only)
        if (_isAdmin && _selectedExchange != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _showCreateLotDialog,
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xFF22547C),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('Create New Lot',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600)),
                      ]),
                ),
              )),
        if (_isAdmin && _selectedExchange != null) const SizedBox(height: 12),

        // Count label
        if (!_isLoading && _lotCounts.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${_lotCounts.length} lots',
                      style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 11,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500)))),
        const SizedBox(height: 6),

        // Lots list
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: Color(0xFF22547C), strokeWidth: 2.5))
              : _lotCounts.isEmpty
                  ? Center(
                      child: Text(
                          _isAdmin
                              ? 'No lots found. Create one!'
                              : 'No lots available',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 13,
                              fontFamily: 'Inter')))
                  : RefreshIndicator(
                      onRefresh: _fetchGroupQuantities,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _lotCounts.length,
                        itemBuilder: (_, i) {
                          final lotName = _lotCounts.keys.elementAt(i);
                          final count = _lotCounts[lotName] ?? 0;
                          return GestureDetector(
                            onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            GroupQuantityLotDetailView(
                                                exchange: _selectedExchange!,
                                                lotName: lotName)))
                                .then((_) => _fetchGroupQuantities()),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.02),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(lotName,
                                          style: const TextStyle(
                                              color: Color(0xFF22547C),
                                              fontSize: 15,
                                              fontFamily: 'Inter',
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: -0.3)),
                                      const SizedBox(height: 4),
                                      Text('$count instruments',
                                          style: const TextStyle(
                                              color: Color(0xFF94A3B8),
                                              fontSize: 12,
                                              fontFamily: 'Inter')),
                                    ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('VIEW',
                                            style: TextStyle(
                                                color: Color(0xFF22547C),
                                                fontSize: 11,
                                                fontFamily: 'Inter',
                                                fontWeight: FontWeight.w700,
                                                letterSpacing: 0.3)),
                                        SizedBox(width: 2),
                                        Icon(Icons.chevron_right,
                                            size: 16, color: Color(0xFF22547C)),
                                      ]),
                                ),
                              ]),
                            ),
                          );
                        },
                      )),
        ),
      ])),
    );
  }
}
