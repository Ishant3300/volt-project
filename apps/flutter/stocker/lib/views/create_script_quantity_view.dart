import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import '../models/kite_instrument.dart';

class CreateScriptQuantityView extends StatefulWidget {
  const CreateScriptQuantityView({super.key});

  @override
  State<CreateScriptQuantityView> createState() => _CreateScriptQuantityViewState();
}

class _CreateScriptQuantityViewState extends State<CreateScriptQuantityView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _maxQtyController = TextEditingController();
  final TextEditingController _brkQtyController = TextEditingController();
  final SecureStorageService _storage = SecureStorageService();
  
  List<KiteInstrument> _searchResults = [];
  KiteInstrument? _selectedInstrument;
  bool _isSearching = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _searchController.dispose();
    _maxQtyController.dispose();
    _brkQtyController.dispose();
    super.dispose();
  }

  Future<void> _searchInstruments(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      log('🔍 Searching instruments: $query');
      final apiService = Provider.of<ApiService>(context, listen: false);
      
      // Get token from secure storage
      final token = await _storage.getToken();
      
      // Make authenticated request
      final response = await apiService.get('/kite/instruments/search?q=$query', token: token);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> instruments = data['data'] ?? [];
          setState(() {
            _searchResults = instruments.map((json) => KiteInstrument.fromJson(json)).toList();
          });
        }
      }
    } catch (e) {
      log('❌ Error searching instruments: $e');
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _createScriptQuantity() async {
    if (_selectedInstrument == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an instrument')),
      );
      return;
    }

    final maxQty = double.tryParse(_maxQtyController.text.trim());
    final brkQty = double.tryParse(_brkQtyController.text.trim());

    if (maxQty == null || maxQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid max quantity')),
      );
      return;
    }

    if (brkQty == null || brkQty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid breakup quantity')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      log('💾 Creating script quantity');
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      final response = await adminService.createScriptQuantity(
        exchangeName: _selectedInstrument!.exchange,
        scriptName: _selectedInstrument!.tradingsymbol,
        lotSize: _selectedInstrument!.lotSize?.toInt() ?? 1,
        maxQty: maxQty.toInt(),
        brkQty: brkQty.toInt(),
      );
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          log('✅ Script quantity created successfully');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Script quantity created successfully')),
            );
            Navigator.pop(context, true);
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to create');
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to create');
      }
    } catch (e) {
      log('❌ Error creating script quantity: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
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
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Create Script Quantity',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Instrument
                    const Text(
                      'Search Instrument',
                      style: TextStyle(
                        color: Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          _searchInstruments(value);
                        },
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Type to search instruments...',
                          hintStyle: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    // Search Results
                    if (_isSearching)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_searchResults.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: _searchResults.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final instrument = _searchResults[index];
                            return ListTile(
                              title: Text(
                                instrument.tradingsymbol,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '${instrument.exchange} • Lot: ${instrument.lotSize ?? 1}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () {
                                setState(() {
                                  _selectedInstrument = instrument;
                                  _searchController.text = instrument.tradingsymbol;
                                  _searchResults = [];
                                });
                              },
                            );
                          },
                        ),
                      ),

                    // Selected Instrument
                    if (_selectedInstrument != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: ShapeDecoration(
                          color: const Color(0xFFE5F4FF),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF22547C)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedInstrument!.tradingsymbol,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${_selectedInstrument!.exchange} • Lot Size: ${_selectedInstrument!.lotSize ?? 1}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Max Quantity
                    const Text(
                      'Max Quantity',
                      style: TextStyle(
                        color: Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _maxQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Enter max quantity',
                          hintStyle: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Breakup Quantity
                    const Text(
                      'Breakup Quantity',
                      style: TextStyle(
                        color: Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _brkQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Enter breakup quantity',
                          hintStyle: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Create Button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _isSubmitting ? null : _createScriptQuantity,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: ShapeDecoration(
                            color: _isSubmitting ? const Color(0xFF8E8E93) : const Color(0xFF22547C),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: _isSubmitting
                              ? const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : const Text(
                                  'CREATE',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
