import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/kite_service.dart';
import '../models/kite_instrument.dart';

class AddInstrumentToLotView extends StatefulWidget {
  final String exchange;
  final String lotName;

  const AddInstrumentToLotView({
    super.key,
    required this.exchange,
    required this.lotName,
  });

  @override
  State<AddInstrumentToLotView> createState() => _AddInstrumentToLotViewState();
}

class _AddInstrumentToLotViewState extends State<AddInstrumentToLotView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _maxQtyController = TextEditingController();
  final TextEditingController _breakQtyController = TextEditingController();
  final TextEditingController _lotSizeController = TextEditingController();

  List<KiteInstrument> _searchResults = [];
  KiteInstrument? _selectedInstrument;
  bool _isSearching = false;
  bool _isAdding = false;

  @override
  void dispose() {
    _searchController.dispose();
    _maxQtyController.dispose();
    _breakQtyController.dispose();
    _lotSizeController.dispose();
    super.dispose();
  }

  Future<void> _searchInstruments(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    log('🔍 Searching instruments: $query');
    setState(() {
      _isSearching = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final kiteService = KiteService(apiService);
      
      final results = await kiteService.searchInstruments(
        query,
        exchange: widget.exchange,
      );

      setState(() {
        _searchResults = results.map((json) => KiteInstrument.fromJson(json)).toList();
        _isSearching = false;
      });
      log('   Found ${_searchResults.length} instruments');
    } catch (e) {
      log('   ❌ Error: $e');
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _addInstrument() async {
    if (_selectedInstrument == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an instrument')),
      );
      return;
    }

    final maxQty = double.tryParse(_maxQtyController.text);
    final breakQty = double.tryParse(_breakQtyController.text);
    final lotSize = double.tryParse(_lotSizeController.text);

    if (maxQty == null || breakQty == null || lotSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter valid numbers')),
      );
      return;
    }

    log('➕ Adding instrument to lot');
    log('   Exchange: ${widget.exchange}');
    log('   Lot Name: ${widget.lotName}');
    log('   Instrument: ${_selectedInstrument!.tradingsymbol}');
    log('   Max Qty: $maxQty, Break Qty: $breakQty, Lot Size: $lotSize');
    
    setState(() {
      _isAdding = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      // Create a new grouped quantity document
      final response = await adminService.createGroupedQuantity(
        exchangeName: widget.exchange,
        lotName: widget.lotName,
        instrumentId: _selectedInstrument!.instrumentToken.toString(),
        instrumentSymbol: _selectedInstrument!.tradingsymbol,
        maxQty: maxQty,
        breakQty: breakQty,
        lotSize: lotSize,
      );

      log('   Response status: ${response.statusCode}');
      log('   Response body: ${response.body}');

      setState(() {
        _isAdding = false;
      });

      if (response.statusCode == 201) {
        log('   ✅ Instrument added successfully');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Instrument added successfully')),
          );
          Navigator.pop(context, true);
        }
      } else {
        final data = jsonDecode(response.body);
        log('   ❌ Failed: ${data['message']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Failed to add instrument')),
          );
        }
      }
    } catch (e, stackTrace) {
      log('   ❌ Error: $e');
      log('   Stack trace: $stackTrace');
      setState(() {
        _isAdding = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Icon(Icons.arrow_back, color: Colors.black),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Add Instrument',
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

              // Search Instruments
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, size: 24, color: const Color(0xFF8E8E93)),
                    SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search instruments...',
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: const Color(0xFF8E8E93)),
                        ),
                        onChanged: _searchInstruments,
                      ),
                    ),
                    if (_isSearching)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: const Color(0xFF22547C),
                        ),
                      ),
                  ],
                ),
              ),

              SizedBox(height: 8),

              // Search Results
              if (_searchResults.isNotEmpty)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  constraints: BoxConstraints(maxHeight: 200),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _searchResults.length,
                    itemBuilder: (context, index) {
                      final instrument = _searchResults[index];
                      return ListTile(
                        title: Text(instrument.tradingsymbol),
                        subtitle: Text(instrument.name),
                        onTap: () {
                          setState(() {
                            _selectedInstrument = instrument;
                            _searchResults = [];
                            _searchController.clear();
                          });
                        },
                      );
                    },
                  ),
                ),

              SizedBox(height: 16),

              // Selected Instrument
              if (_selectedInstrument != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selected Instrument',
                                  style: TextStyle(
                                    color: const Color(0xFF8E8E93),
                                    fontSize: 12,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _selectedInstrument!.tradingsymbol,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _selectedInstrument = null;
                              });
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _maxQtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Max Quantity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: _breakQtyController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Break Quantity',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: _lotSizeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Lot Size',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),

              SizedBox(height: 16),

              // Add Button
              if (_selectedInstrument != null)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isAdding ? null : _addInstrument,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22547C),
                      padding: EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isAdding
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'ADD INSTRUMENT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),

              SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
