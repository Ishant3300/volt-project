import 'dart:convert';
import 'dart:developer';
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
  final List<String> _exchanges = ['NSE', 'MCX', 'SGX', 'CALLPUT', 'OTHERS', 'MCX-OPT'];
  final List<String> _types = ['TURNOVER WISE', 'LOT WISE'];
  
  final TextEditingController _searchController = TextEditingController();
  List<KiteInstrument> _searchResults = [];
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchInstruments(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    log('🔍 Searching instruments: $query for exchange: $_selectedExchange');
    setState(() {
      _isSearching = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final kiteService = KiteService(apiService);
      
      final results = await kiteService.searchInstruments(
        query,
        exchange: _selectedExchange,
      );

      log('   Found ${results.length} instruments');
      setState(() {
        _searchResults = results
            .map((json) => KiteInstrument.fromJson(json))
            .toList();
        _isSearching = false;
      });
    } catch (e) {
      log('   ❌ Error searching: $e');
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching instruments: $e')),
        );
      }
    }
  }

  void _showAddBrokerageDialog(KiteInstrument instrument) {
    final TextEditingController valueController = TextEditingController();
    String localType = _selectedType;
    bool isAdding = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Add Brokerage Setting'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                instrument.tradingsymbol,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 16),
              Text('Type'),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: localType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _types.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() {
                      localType = value;
                    });
                  }
                },
              ),
              SizedBox(height: 16),
              TextField(
                controller: valueController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Brokerage Value',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isAdding ? null : () => Navigator.pop(context),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: isAdding ? null : () async {
                final value = double.tryParse(valueController.text);
                if (value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a valid value')),
                  );
                  return;
                }

                setDialogState(() {
                  isAdding = true;
                });

                log('➕ Creating brokerage setting: ${instrument.tradingsymbol} - $value $localType');

                try {
                  final apiService = Provider.of<ApiService>(context, listen: false);
                  final adminService = AdminService(apiService);

                  final response = await adminService.createBrokerageSettings(
                    type: localType,
                    exchangeName: _selectedExchange,
                    scriptName: instrument.tradingsymbol,
                    brkValue: value,
                  );

                  log('   Response status: ${response.statusCode}');
                  log('   Response body: ${response.body}');

                  setDialogState(() {
                    isAdding = false;
                  });

                  if (response.statusCode == 201) {
                    log('   ✅ Brokerage setting created successfully');
                    if (!mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Brokerage setting created successfully')),
                    );
                  } else {
                    final data = jsonDecode(response.body);
                    log('   ❌ Failed to create: ${data['message']}');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(data['message'] ?? 'Failed to create brokerage setting')),
                      );
                    }
                  }
                } catch (e, stackTrace) {
                  log('   ❌ Error: $e');
                  log('   Stack trace: $stackTrace');
                  setDialogState(() {
                    isAdding = false;
                  });
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF22547C),
              ),
              child: isAdding
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('ADD', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      resizeToAvoidBottomInset: true,
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
                      'Create Brokerage Setting',
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

              // Exchange Selector
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
                    Text(
                      'Select Exchange',
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedExchange,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _exchanges.map((exchange) {
                        return DropdownMenuItem(
                          value: exchange,
                          child: Text(exchange),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _selectedExchange = value;
                            _searchResults = [];
                            _searchController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

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
                          hintStyle: TextStyle(
                            color: const Color(0xFF8E8E93),
                            fontSize: 16,
                          ),
                        ),
                        onChanged: (value) {
                          _searchInstruments(value);
                        },
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
                          _showAddBrokerageDialog(instrument);
                        },
                      );
                    },
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
