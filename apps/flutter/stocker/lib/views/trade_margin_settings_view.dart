import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'create_trade_margin_view.dart';

class TradeMarginSettingsView extends StatefulWidget {
  const TradeMarginSettingsView({super.key});

  @override
  State<TradeMarginSettingsView> createState() => _TradeMarginSettingsViewState();
}

class _TradeMarginSettingsViewState extends State<TradeMarginSettingsView> {
  final TextEditingController _amountController = TextEditingController();
  
  String? _selectedExchange;
  String _selectedAmountType = 'amount';
  final List<String> _exchanges = ['NSE', 'MCX', 'SGX', 'CALLPUT', 'OTHERS', 'MCX-OPT'];
  final List<String> _amountTypes = ['amount', 'percentage'];
  
  List<Map<String, dynamic>> _tradeMarginItems = [];
  Map<String, bool> _selectedItems = {};
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchTradeMargins() async {
    if (_selectedExchange == null) return;

    log('📊 Fetching trade margins for exchange: $_selectedExchange, amount type: $_selectedAmountType');
    setState(() {
      _isLoading = true;
      _tradeMarginItems = [];
      _selectedItems = {};
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      final response = await adminService.getAllTradeMargins(limit: 1000);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> allMargins = data['data']['trade_margins'] ?? [];
          
          // Filter by selected exchange AND amount type
          List<Map<String, dynamic>> filteredMargins = [];
          for (var margin in allMargins) {
            final exchangeName = margin['exchange_name']?.toString().toUpperCase();
            final amountType = margin['amount_type']?.toString().toLowerCase();
            
            if (exchangeName == _selectedExchange && amountType == _selectedAmountType) {
              filteredMargins.add({
                'id': margin['id'],
                'script_name': margin['script_name'],
                'trade_margin': margin['trade_margin'],
                'amount_type': margin['amount_type'],
                'exchange_name': margin['exchange_name'],
              });
            }
          }
          
          setState(() {
            _tradeMarginItems = filteredMargins;
            _isLoading = false;
          });
          log('   ✅ Total entries found: ${filteredMargins.length}');
        }
      }
    } catch (e) {
      log('   ❌ Error fetching: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching trade margins: $e')),
        );
      }
    }
  }

  Future<void> _applyMargin() async {
    if (_selectedExchange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an exchange')),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    final selectedScripts = _selectedItems.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();

    if (selectedScripts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select at least one script')),
      );
      return;
    }

    log('📝 Applying margin: $amount $_selectedAmountType to ${selectedScripts.length} scripts');

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      int successCount = 0;
      int failCount = 0;

      // Update each selected item individually
      for (var item in _tradeMarginItems) {
        final scriptName = item['script_name'];
        
        if (selectedScripts.contains(scriptName)) {
          final docId = item['id'];
          
          log('   Updating document: $docId for script: $scriptName');
          final response = await adminService.updateTradeMargin(
            id: docId,
            exchangeName: _selectedExchange,
            scriptName: scriptName,
            amountType: _selectedAmountType,
            tradeMargin: amount,
          );

          if (response.statusCode == 200) {
            successCount++;
            log('   ✅ Updated $scriptName successfully');
          } else {
            failCount++;
            final data = jsonDecode(response.body);
            log('   ❌ Failed to update $scriptName: ${data['message']}');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Updated $successCount items${failCount > 0 ? ", $failCount failed" : ""}')),
        );
        _amountController.clear();
        _selectedItems.clear();
        _fetchTradeMargins();
      }
    } catch (e) {
      log('   ❌ Error: $e');
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
                    'Trade Margin Setting',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Spacer(),
                  FutureBuilder<String?>(
                    future: SecureStorageService().getRole(),
                    builder: (context, snapshot) {
                      final isAdmin = snapshot.data == 'ADMIN';
                      if (!isAdmin) return const SizedBox.shrink();
                      
                      return GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const CreateTradeMarginView()),
                          );
                          // Refresh list after returning from create view
                          if (_selectedExchange != null) {
                            _fetchTradeMargins();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: ShapeDecoration(
                            color: const Color(0xFF22547C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.add, color: Colors.white, size: 18),
                              SizedBox(width: 4),
                              Text(
                                'CREATE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // Two Dropdowns Side by Side
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedExchange,
                          hint: Text(
                            'Select Exchange',
                            style: TextStyle(
                              color: const Color(0xFF8E8E93),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: const Color(0xFF8E8E93)),
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
                            _fetchTradeMargins();
                          },
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 13),
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedAmountType,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: const Color(0xFF8E8E93)),
                          items: _amountTypes.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedAmountType = value;
                              });
                              _fetchTradeMargins();
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 8),

            // Amount Input and Apply Button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                      ),
                      child: TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Amount',
                          hintStyle: TextStyle(
                            color: const Color(0xFF8E8E93),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _applyMargin,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF22547C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                      ),
                      child: Text(
                        'APPLY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Header Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 2, color: const Color(0xFF8E8E93)),
                            borderRadius: BorderRadius.circular(44),
                          ),
                        ),
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Script Name',
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Trade Margin',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: const Color(0xFF8E8E93),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // Trade Margin Items List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: const Color(0xFF22547C)),
                    )
                  : _tradeMarginItems.isEmpty
                      ? Center(
                          child: Text(
                            _selectedExchange == null
                                ? 'Select an exchange to view trade margins'
                                : 'No trade margins found for $_selectedExchange ($_selectedAmountType)',
                            style: TextStyle(
                              color: const Color(0xFF8E8E93),
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _tradeMarginItems.length,
                          itemBuilder: (context, index) {
                            final item = _tradeMarginItems[index];
                            final scriptName = item['script_name'];
                            final isSelected = _selectedItems[scriptName] ?? false;
                            
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedItems[scriptName] = !isSelected;
                                });
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: ShapeDecoration(
                                            color: isSelected ? const Color(0xFF22547C) : Colors.white,
                                            shape: RoundedRectangleBorder(
                                              side: BorderSide(
                                                width: 2,
                                                color: isSelected ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                                              ),
                                              borderRadius: BorderRadius.circular(44),
                                            ),
                                          ),
                                          child: isSelected
                                              ? Icon(Icons.check, size: 12, color: Colors.white)
                                              : null,
                                        ),
                                        SizedBox(width: 7),
                                        Text(
                                          scriptName,
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 16,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      item['trade_margin'].toString(),
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w400,
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
