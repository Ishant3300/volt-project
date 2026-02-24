import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'create_brokerage_view.dart';

class BrokerageSettingsView extends StatefulWidget {
  const BrokerageSettingsView({super.key});

  @override
  State<BrokerageSettingsView> createState() => _BrokerageSettingsViewState();
}

class _BrokerageSettingsViewState extends State<BrokerageSettingsView> {
  final TextEditingController _amountController = TextEditingController();
  
  String? _selectedExchange;
  String _selectedType = 'TURNOVER WISE';
  final List<String> _exchanges = ['NSE', 'MCX', 'SGX', 'CALLPUT', 'OTHERS', 'MCX-OPT'];
  final List<String> _types = ['TURNOVER WISE', 'LOT WISE'];
  
  List<Map<String, dynamic>> _brokerageItems = [];
  Map<String, bool> _selectedItems = {};
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchBrokerageSettings() async {
    if (_selectedExchange == null) return;

    log('📊 Fetching brokerage settings for exchange: $_selectedExchange, type: $_selectedType');
    setState(() {
      _isLoading = true;
      _brokerageItems = [];
      _selectedItems = {};
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      final response = await adminService.getAllBrokerageSettings(limit: 1000);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> allSettings = data['data']['brokerage_settings'] ?? [];
          
          // Filter by selected exchange AND type
          List<Map<String, dynamic>> filteredSettings = [];
          for (var setting in allSettings) {
            final exchangeName = setting['exchange_name']?.toString().toUpperCase();
            final type = setting['type']?.toString().toUpperCase();
            
            if (exchangeName == _selectedExchange && type == _selectedType) {
              filteredSettings.add({
                'id': setting['id'],
                'script_name': setting['script_name'],
                'brk_value': setting['brk_value'],
                'type': setting['type'],
                'exchange_name': setting['exchange_name'],
              });
            }
          }
          
          setState(() {
            _brokerageItems = filteredSettings;
            _isLoading = false;
          });
          log('   ✅ Total entries found: ${filteredSettings.length}');
        }
      }
    } catch (e) {
      log('   ❌ Error fetching: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching brokerage settings: $e')),
        );
      }
    }
  }

  Future<void> _applyBrokerage() async {
    if (_selectedExchange == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select an exchange')),
      );
      return;
    }

    final value = double.tryParse(_amountController.text);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid value')),
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

    log('📝 Applying brokerage: $value $_selectedType to ${selectedScripts.length} scripts');

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      int successCount = 0;
      int failCount = 0;

      // Update each selected item individually
      for (var item in _brokerageItems) {
        final scriptName = item['script_name'];
        
        if (selectedScripts.contains(scriptName)) {
          final docId = item['id'];
          
          log('   Updating document: $docId for script: $scriptName');
          final response = await adminService.updateBrokerageSettings(
            id: docId,
            type: _selectedType,
            exchangeName: _selectedExchange,
            scriptName: scriptName,
            brkValue: value,
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
        _fetchBrokerageSettings();
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
                    'Brokerage Setting',
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
                            MaterialPageRoute(builder: (context) => const CreateBrokerageView()),
                          );
                          // Refresh list after returning from create view
                          if (_selectedExchange != null) {
                            _fetchBrokerageSettings();
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
                            _fetchBrokerageSettings();
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
                          value: _selectedType,
                          isExpanded: true,
                          icon: Icon(Icons.keyboard_arrow_down, color: const Color(0xFF8E8E93)),
                          items: _types.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                _selectedType = value;
                              });
                              _fetchBrokerageSettings();
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
                          hintText: 'Value',
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
                    onTap: _applyBrokerage,
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
                    'Brk Value',
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

            // Brokerage Items List
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: const Color(0xFF22547C)),
                    )
                  : _brokerageItems.isEmpty
                      ? Center(
                          child: Text(
                            _selectedExchange == null
                                ? 'Select an exchange to view brokerage settings'
                                : 'No brokerage settings found for $_selectedExchange ($_selectedType)',
                            style: TextStyle(
                              color: const Color(0xFF8E8E93),
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.builder(
                          itemCount: _brokerageItems.length,
                          itemBuilder: (context, index) {
                            final item = _brokerageItems[index];
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
                                      item['brk_value'].toString(),
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
