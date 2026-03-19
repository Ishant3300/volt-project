import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import '../models/script_quantity.dart';
import '../utils/date_formatter.dart';
import 'add_script_qty_to_exchange_view.dart';

class ScriptQuantitySettingsView extends StatefulWidget {
  const ScriptQuantitySettingsView({super.key});

  @override
  State<ScriptQuantitySettingsView> createState() => _ScriptQuantitySettingsViewState();
}

class _ScriptQuantitySettingsViewState extends State<ScriptQuantitySettingsView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _maxQtyController = TextEditingController();
  final TextEditingController _brkQtyController = TextEditingController();
  final SecureStorageService _storage = SecureStorageService();
  
  String? _selectedExchange;
  final _exchanges = ['NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'GLOBAL', 'SGX'];
  List<ScriptQuantity> _scriptItems = [];
  List<ScriptQuantity> _filteredItems = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadScriptQuantities();
  }

  Future<void> _checkUserRole() async {
    try {
      final role = await _storage.getRole();
      setState(() {
        _isAdmin = role == 'ADMIN';
      });
    } catch (e) {
      log('❌ Error checking user role: $e');
    }
  }

  Future<void> _loadScriptQuantities() async {
    setState(() {
      _isLoading = true;
    });

    try {
      log('🔄 Loading script quantities');
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      final response = await adminService.getAllScriptQuantities(limit: 100);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> items = data['data']['script_quantities'] ?? [];
          setState(() {
            _scriptItems = items.map((json) => ScriptQuantity.fromJson(json)).toList();
            _filteredItems = _scriptItems;
            _isLoading = false;
          });
          log('✅ Loaded ${_scriptItems.length} script quantities');
        }
      }
    } catch (e) {
      log('❌ Error loading script quantities: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterScripts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = _scriptItems;
      } else {
        _filteredItems = _scriptItems
            .where((item) => item.scriptName.toLowerCase().contains(query.toLowerCase()))
            .toList();
      }
    });
  }

  Future<void> _applyUpdates() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one script')),
      );
      return;
    }

    final maxQty = double.tryParse(_maxQtyController.text.trim());
    final brkQty = double.tryParse(_brkQtyController.text.trim());

    if (maxQty == null && brkQty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one value to update')),
      );
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      log('💾 Updating ${_selectedIds.length} script quantities');
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      int successCount = 0;
      for (final id in _selectedIds) {
        final response = await adminService.updateScriptQuantity(
          id: id,
          maxQty: maxQty?.toInt(),
          brkQty: brkQty?.toInt(),
        );
        
        if (response.statusCode == 200) {
          successCount++;
        }
      }
      
      log('✅ Updated $successCount script quantities');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated $successCount script quantities successfully')),
        );
        _selectedIds.clear();
        _maxQtyController.clear();
        _brkQtyController.clear();
        _loadScriptQuantities();
      }
    } catch (e) {
      log('❌ Error updating script quantities: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _maxQtyController.dispose();
    _brkQtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Script Quantity Setting',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (_isAdmin)
                    GestureDetector(
                      onTap: () {
                        if (_selectedExchange == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an exchange first')));
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AddScriptQtyToExchangeView(
                            exchange: _selectedExchange!,
                            isExistingGroup: _filteredItems.isNotEmpty,
                          ),
                        )).then((_) => _loadScriptQuantities());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF3F45C7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'CREATE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Exchange Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedExchange,
                    hint: const Text('Select Exchange', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Inter')),
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8)),
                    style: const TextStyle(color: Colors.black, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w500),
                    items: _exchanges.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) {
                      setState(() => _selectedExchange = v);
                      _loadScriptQuantities();
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Search Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 24, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterScripts,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search script',
                        hintStyle: TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Action Buttons Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedIds.length == _filteredItems.length) {
                          _selectedIds.clear();
                        } else {
                          _selectedIds = _filteredItems.map((item) => item.id).toSet();
                        }
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: ShapeDecoration(
                        color: _selectedIds.length == _filteredItems.length && _filteredItems.isNotEmpty
                            ? const Color(0xFF3F45C7)
                            : const Color(0xFFE5E5EA),
                        shape: const OvalBorder(),
                      ),
                      child: _selectedIds.length == _filteredItems.length && _filteredItems.isNotEmpty
                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _maxQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Max Qty',
                          hintStyle: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _brkQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Breakup',
                          hintStyle: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isUpdating ? null : _applyUpdates,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          color: _isUpdating ? const Color(0xFF8E8E93) : const Color(0xFF3F45C7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isUpdating
                            ? const Center(
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Text(
                                'APPLY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Script Items List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF3F45C7)),
                    )
                  : _filteredItems.isEmpty
                      ? const Center(
                          child: Text(
                            'No script quantities found',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 16,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            final isSelected = _selectedIds.contains(item.id);
                            
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedIds.remove(item.id);
                                  } else {
                                    _selectedIds.add(item.id);
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  border: Border(
                                    bottom: BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: ShapeDecoration(
                                        color: isSelected ? const Color(0xFF3F45C7) : const Color(0xFFE5E5EA),
                                        shape: const OvalBorder(),
                                      ),
                                      child: isSelected
                                          ? const Icon(Icons.check, color: Colors.white, size: 20)
                                          : null,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.scriptName,
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 16,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Last Update: ${DateFormatter.formatDateTime(item.updatedAt)}',
                                                style: const TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 10,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Opacity(
                                                  opacity: 0.80,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: ShapeDecoration(
                                                      color: const Color(0xFFE5E5EA),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Text(
                                                          'Lot ',
                                                          style: TextStyle(
                                                            color: Colors.black,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight: FontWeight.w400,
                                                          ),
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            item.lotSize.toStringAsFixed(0),
                                                            style: const TextStyle(
                                                              color: Colors.black,
                                                              fontSize: 12,
                                                              fontFamily: 'Inter',
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Opacity(
                                                  opacity: 0.80,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: ShapeDecoration(
                                                      color: const Color(0xFFE5E5EA),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Text(
                                                          'Brk ',
                                                          style: TextStyle(
                                                            color: Colors.black,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight: FontWeight.w400,
                                                          ),
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            item.brkQty.toStringAsFixed(0),
                                                            style: const TextStyle(
                                                              color: Colors.black,
                                                              fontSize: 12,
                                                              fontFamily: 'Inter',
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Opacity(
                                                  opacity: 0.80,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: ShapeDecoration(
                                                      color: const Color(0xFFE5E5EA),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        const Text(
                                                          'Max ',
                                                          style: TextStyle(
                                                            color: Colors.black,
                                                            fontSize: 10,
                                                            fontFamily: 'Inter',
                                                            fontWeight: FontWeight.w400,
                                                          ),
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            item.maxQty.toStringAsFixed(0),
                                                            style: const TextStyle(
                                                              color: Colors.black,
                                                              fontSize: 12,
                                                              fontFamily: 'Inter',
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
