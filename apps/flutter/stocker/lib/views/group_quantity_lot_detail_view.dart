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

  const GroupQuantityLotDetailView({
    super.key,
    required this.exchange,
    required this.lotName,
  });

  @override
  State<GroupQuantityLotDetailView> createState() => _GroupQuantityLotDetailViewState();
}

class _GroupQuantityLotDetailViewState extends State<GroupQuantityLotDetailView> {
  List<Map<String, dynamic>> _instruments = [];
  bool _isLoading = false;
  bool _isAdmin = false;
  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _fetchLotData();
  }

  Future<void> _checkUserRole() async {
    final isAdmin = await _storage.isAdmin();
    setState(() {
      _isAdmin = isAdmin;
    });
  }

  Future<void> _fetchLotData() async {
    log('📊 Fetching lot data for: ${widget.lotName} in ${widget.exchange}');
    setState(() {
      _isLoading = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.getAllGroupedQuantities(limit: 1000);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> allDocs = data['data']['grouped_quantities'] ?? [];
          
          // Filter by exchange and lot_name
          List<Map<String, dynamic>> filteredInstruments = [];
          for (var doc in allDocs) {
            final exchangeName = doc['exchange_name']?.toString().toUpperCase();
            final lotName = doc['lot_name'];
            
            if (exchangeName == widget.exchange && lotName == widget.lotName) {
              filteredInstruments.add({
                'id': doc['id'],
                'instrument_id': doc['instrument_id'],
                'instrument_symbol': doc['instrument_symbol'],
                'max_qty': doc['max_qty'],
                'break_qty': doc['break_qty'],
                'lot_size': doc['lot_size'],
              });
            }
          }
          
          setState(() {
            _instruments = filteredInstruments;
            _isLoading = false;
          });
          log('   ✅ Loaded ${_instruments.length} instruments');
        }
      }
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      log('   ❌ Error: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteInstrument(String docId, String instrumentSymbol) async {
    log('🗑️ Deleting instrument: $instrumentSymbol (doc: $docId)');
    
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.deleteGroupedQuantity(docId);

      if (response.statusCode == 200) {
        log('   ✅ Instrument deleted');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Instrument deleted')),
          );
          _fetchLotData(); // Refresh the list
        }
      } else {
        final data = jsonDecode(response.body);
        log('   ❌ Failed: ${data['message']}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(data['message'] ?? 'Failed to delete')),
          );
        }
      }
    } catch (e) {
      log('   ❌ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting instrument: $e')),
        );
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
                    child: Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.lotName,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${widget.exchange} • ${_instruments.length} instruments',
                          style: TextStyle(
                            color: const Color(0xFF8E8E93),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Add Instrument Button (Admin only)
            if (_isAdmin)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AddInstrumentToLotView(
                          exchange: widget.exchange,
                          lotName: widget.lotName,
                        ),
                      ),
                    ).then((_) {
                      // Reload instruments after adding
                      _fetchLotData();
                    });
                  },
                  icon: Icon(Icons.add, color: Colors.white),
                  label: Text('Add Instrument', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22547C),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),

            SizedBox(height: 16),

            // Instruments List
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: const Color(0xFF22547C)))
                  : _instruments.isEmpty
                      ? Center(
                          child: Text(
                            'No instruments added yet',
                            style: TextStyle(color: const Color(0xFF8E8E93), fontSize: 16),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchLotData,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _instruments.length,
                            itemBuilder: (context, index) {
                              final instrument = _instruments[index];
                              
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(16),
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            instrument['instrument_symbol'] ?? 'N/A',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Row(
                                            children: [
                                              _buildInfoChip('Max: ${instrument['max_qty']}'),
                                              SizedBox(width: 8),
                                              _buildInfoChip('Break: ${instrument['break_qty']}'),
                                              SizedBox(width: 8),
                                              _buildInfoChip('Lot: ${instrument['lot_size']}'),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isAdmin)
                                      IconButton(
                                        icon: Icon(Icons.delete, color: Colors.red),
                                        onPressed: () {
                                          showDialog(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: Text('Delete Instrument'),
                                              content: Text('Are you sure you want to delete this instrument?'),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.pop(context),
                                                  child: Text('CANCEL'),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    Navigator.pop(context);
                                                    _deleteInstrument(
                                                      instrument['id'],
                                                      instrument['instrument_symbol'],
                                                    );
                                                  },
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.red,
                                                  ),
                                                  child: Text('DELETE', style: TextStyle(color: Colors.white)),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: const Color(0xFFE5E5EA),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: const Color(0xFF8E8E93),
          fontSize: 12,
        ),
      ),
    );
  }
}
