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
  final List<String> _exchanges = ['NSE', 'MCX', 'SGX', 'CALLPUT'];

  Map<String, int> _lotCounts = {}; // lot_name -> count of instruments
  bool _isLoading = false;
  bool _hasInitialized = false;
  bool _isAdmin = false;
  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    // Auto-select first exchange on initial load
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
    setState(() {
      _isAdmin = role == 'ADMIN';
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when coming back to this screen
    if (_hasInitialized && _selectedExchange != null) {
      log('🔄 Screen became active, refreshing data for $_selectedExchange');
      _fetchGroupQuantities();
    }
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
      log('   Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success'] == true) {
          final List<dynamic> allDocs = data['data']['grouped_quantities'] ?? [];
          log('   Total documents: ${allDocs.length}');

          // Group by lot_name for the selected exchange
          Map<String, int> counts = {};
          
          for (var doc in allDocs) {
            final exchangeName = doc['exchange_name']?.toString().toUpperCase();
            
            if (exchangeName == _selectedExchange) {
              final lotName = doc['lot_name'];
              counts[lotName] = (counts[lotName] ?? 0) + 1;
            }
          }

          setState(() {
            _lotCounts = counts;
            _isLoading = false;
          });
          log('   ✅ Found ${counts.length} unique lots');
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      log('   ❌ Error: $e');
      log('   Stack trace: $stackTrace');
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showCreateLotDialog() {
    final TextEditingController controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Create New Lot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a name for the new lot. You\'ll be able to add instruments to it next.',
              style: TextStyle(fontSize: 14, color: const Color(0xFF8E8E93)),
            ),
            SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Lot Name',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                final lotName = controller.text;
                Navigator.pop(context);
                
                // Navigate directly to add instrument view
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => GroupQuantityLotDetailView(
                      exchange: _selectedExchange!,
                      lotName: lotName,
                    ),
                  ),
                ).then((_) => _fetchGroupQuantities());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22547C),
            ),
            child: Text('NEXT', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
                  Text(
                    'Group Quantity Settings',
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
                    value: _selectedExchange,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    hint: Text('Select Exchange'),
                    items: _exchanges.map((exchange) {
                      return DropdownMenuItem(
                        value: exchange,
                        child: Text(exchange),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedExchange = value;
                      });
                      _fetchGroupQuantities();
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Create Lot Button (Admin only)
            if (_isAdmin && _selectedExchange != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showCreateLotDialog,
                  icon: Icon(Icons.add, color: Colors.white),
                  label: Text('Create New Lot', style: TextStyle(color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22547C),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),

            SizedBox(height: 16),

            // Lots List
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: const Color(0xFF22547C)))
                  : _selectedExchange == null
                      ? Center(
                          child: Text(
                            'Select an exchange to view lots',
                            style: TextStyle(color: const Color(0xFF8E8E93), fontSize: 16),
                          ),
                        )
                      : _lotCounts.isEmpty
                          ? Center(
                              child: Text(
                                _isAdmin ? 'No lots found. Create one!' : 'No lots available',
                                style: TextStyle(color: const Color(0xFF8E8E93), fontSize: 16),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchGroupQuantities,
                              child: ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _lotCounts.length,
                                itemBuilder: (context, index) {
                                  final lotName = _lotCounts.keys.elementAt(index);
                                  final entryCount = _lotCounts[lotName] ?? 0;

                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => GroupQuantityLotDetailView(
                                            exchange: _selectedExchange!,
                                            lotName: lotName,
                                          ),
                                        ),
                                      ).then((_) => _fetchGroupQuantities());
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(16),
                                      decoration: ShapeDecoration(
                                        color: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                lotName,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(height: 4),
                                              Text(
                                                '$entryCount instruments',
                                                style: TextStyle(
                                                  color: const Color(0xFF8E8E93),
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              Text(
                                                'VIEW',
                                                style: TextStyle(
                                                  color: const Color(0xFF22547C),
                                                  fontSize: 16,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              SizedBox(width: 5),
                                              Icon(Icons.chevron_right, size: 24, color: const Color(0xFF22547C)),
                                            ],
                                          ),
                                        ],
                                      ),
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
}
