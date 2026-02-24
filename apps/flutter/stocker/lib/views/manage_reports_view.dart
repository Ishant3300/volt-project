import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../services/admin_service.dart';
import '../services/api_service.dart';

class ManageReportsView extends StatefulWidget {
  const ManageReportsView({super.key});

  @override
  State<ManageReportsView> createState() => _ManageReportsViewState();
}

class _ManageReportsViewState extends State<ManageReportsView> {
  List<Master> _masters = [];
  Master? _selectedMaster;
  bool _isLoadingMasters = true;
  bool _isUpdatingPermissions = false;
  bool _hasChanges = false;
  
  // Permission states
  Map<String, bool> _permissions = {
    'account_summary': false,
    'pnl_summary': false,
    'client_summary': false,
    'settlement_report': false,
    'generate_pdf': false,
    'weekly_admin': false,
    'intraday_history': false,
    'userwise_open_position': false,
    'script_quantity': false,
    'deleted_trade': false,
    'trade_account': false,
    'close_only': false,
    'bet': false,
    'margin_square': false,
    'fresh_stoploss': false,
  };
  
  // Original permissions to track changes
  Map<String, bool> _originalPermissions = {};

  @override
  void initState() {
    super.initState();
    _fetchMasters();
  }

  Future<void> _fetchMasters() async {
    setState(() {
      _isLoadingMasters = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.getAllMasters(page: 1, limit: 100);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> mastersJson = data['data']['masters'] ?? [];
          setState(() {
            _masters = mastersJson
                .map((json) {
                  try {
                    return Master.fromJson(json);
                  } catch (e) {
                    print('Error parsing master: $e');
                    return null;
                  }
                })
                .whereType<Master>()
                .toList();
            _isLoadingMasters = false;
          });
        }
      }
    } catch (e) {
      print('Error fetching masters: $e');
      setState(() {
        _isLoadingMasters = false;
      });
    }
  }

  void _selectMaster(Master master) {
    print('🔍 Selected master: ${master.username}');
    print('🔍 Master has permissions: ${master.permissions != null}');
    
    setState(() {
      _selectedMaster = master;
      _hasChanges = false;
      
      // Load the master's current permissions
      if (master.permissions != null) {
        _permissions = {
          'account_summary': master.permissions!.accountSummary,
          'pnl_summary': master.permissions!.pnlSummary,
          'client_summary': master.permissions!.clientSummary,
          'settlement_report': master.permissions!.settlementReport,
          'generate_pdf': master.permissions!.generatePdf,
          'weekly_admin': master.permissions!.weeklyAdmin,
          'intraday_history': master.permissions!.intradayHistory,
          'userwise_open_position': master.permissions!.userwiseOpenPosition,
          'script_quantity': master.permissions!.scriptQuantity,
          'deleted_trade': master.permissions!.deletedTrade,
          'trade_account': master.permissions!.tradeAccount,
          'close_only': master.permissions!.closeOnly,
          'bet': master.permissions!.bet,
          'margin_square': master.permissions!.marginSquare,
          'fresh_stoploss': master.permissions!.freshStoploss,
        };
      } else {
        // Reset to defaults if no permissions
        _permissions = {
          'account_summary': false,
          'pnl_summary': false,
          'client_summary': false,
          'settlement_report': false,
          'generate_pdf': false,
          'weekly_admin': false,
          'intraday_history': false,
          'userwise_open_position': false,
          'script_quantity': false,
          'deleted_trade': false,
          'trade_account': false,
          'close_only': false,
          'bet': false,
          'margin_square': false,
          'fresh_stoploss': false,
        };
      }
      
      // Store original permissions for comparison
      _originalPermissions = Map.from(_permissions);
    });
  }

  void _togglePermission(String permissionKey) {
    if (_selectedMaster == null) return;
    
    setState(() {
      _permissions[permissionKey] = !_permissions[permissionKey]!;
      _hasChanges = true;
    });
  }

  Future<void> _updatePermissions() async {
    if (_selectedMaster == null || !_hasChanges) return;

    setState(() {
      _isUpdatingPermissions = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      // Create MasterPermissions object with updated values
      final updatedPermissions = MasterPermissions(
        accountSummary: _permissions['account_summary']!,
        pnlSummary: _permissions['pnl_summary']!,
        clientSummary: _permissions['client_summary']!,
        settlementReport: _permissions['settlement_report']!,
        generatePdf: _permissions['generate_pdf']!,
        weeklyAdmin: _permissions['weekly_admin']!,
        intradayHistory: _permissions['intraday_history']!,
        userwiseOpenPosition: _permissions['userwise_open_position']!,
        scriptQuantity: _permissions['script_quantity']!,
        deletedTrade: _permissions['deleted_trade']!,
        tradeAccount: _permissions['trade_account']!,
        closeOnly: _permissions['close_only']!,
        bet: _permissions['bet']!,
        marginSquare: _permissions['margin_square']!,
        freshStoploss: _permissions['fresh_stoploss']!,
      );

      final response = await adminService.updateMasterPermissions(
        masterId: _selectedMaster!.id,
        permissions: updatedPermissions,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _hasChanges = false;
            _originalPermissions = Map.from(_permissions);
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Permissions updated successfully'),
                backgroundColor: Color(0xFF34C759),
              ),
            );
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update permissions');
        }
      } else {
        throw Exception('Failed to update permissions');
      }
    } catch (e) {
      print('❌ Error updating permissions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update permissions: $e'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    } finally {
      setState(() {
        _isUpdatingPermissions = false;
      });
    }
  }

  void _showMasterSelector() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select Master',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              ),
            ),
            SizedBox(height: 16),
            if (_isLoadingMasters)
              CircularProgressIndicator()
            else if (_masters.isEmpty)
              Text('No masters available')
            else
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _masters.length,
                  itemBuilder: (context, index) {
                    final master = _masters[index];
                    return ListTile(
                      title: Text(master.username),
                      subtitle: Text(master.name),
                      onTap: () {
                        _selectMaster(master);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
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
                      child: Icon(Icons.arrow_back, size: 24, color: Colors.black),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Manage Reports',
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

              SizedBox(height: 16),

              // Select Master
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Master',
                      style: TextStyle(
                        color: const Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    GestureDetector(
                      onTap: _showMasterSelector,
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(width: 1, color: const Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _selectedMaster?.username ?? 'Select Master',
                              style: TextStyle(
                                color: _selectedMaster != null ? Colors.black : const Color(0xFF8E8E93),
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: Colors.grey),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Permissions info
              if (_selectedMaster != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Managing permissions for: ${_selectedMaster!.name}',
                    style: TextStyle(
                      color: const Color(0xFF666666),
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

              SizedBox(height: 16),

              // Report toggles
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildToggleItem('Account Summary', 'account_summary'),
                    SizedBox(height: 16),
                    _buildToggleItem('P&L Summary', 'pnl_summary'),
                    SizedBox(height: 16),
                    _buildToggleItem('Client Summary', 'client_summary'),
                    SizedBox(height: 16),
                    _buildToggleItem('Settlement Report', 'settlement_report'),
                    SizedBox(height: 16),
                    _buildToggleItem('Generate PDF', 'generate_pdf'),
                    SizedBox(height: 16),
                    _buildToggleItem('Weekly Admin', 'weekly_admin'),
                    SizedBox(height: 16),
                    _buildToggleItem('Intraday History', 'intraday_history'),
                    SizedBox(height: 16),
                    _buildToggleItem('Userwise Open Position', 'userwise_open_position'),
                    SizedBox(height: 16),
                    _buildToggleItem('Script Quantity', 'script_quantity'),
                    SizedBox(height: 16),
                    _buildToggleItem('Deleted Trade', 'deleted_trade'),
                    SizedBox(height: 16),
                    _buildToggleItem('Trade Account', 'trade_account'),
                    SizedBox(height: 16),
                    _buildToggleItem('Close Only', 'close_only'),
                    SizedBox(height: 16),
                    _buildToggleItem('Bet', 'bet'),
                    SizedBox(height: 16),
                    _buildToggleItem('Margin Square', 'margin_square'),
                    SizedBox(height: 16),
                    _buildToggleItem('Fresh Stoploss', 'fresh_stoploss'),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Update Button
              if (_selectedMaster != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: GestureDetector(
                      onTap: _isUpdatingPermissions || !_hasChanges ? null : _updatePermissions,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                        decoration: BoxDecoration(
                          color: _isUpdatingPermissions || !_hasChanges
                              ? const Color(0xFF8E8E93)
                              : const Color(0xFF22547C),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _isUpdatingPermissions
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
                            : Text(
                                'UPDATE PERMISSIONS',
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
                ),

              SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToggleItem(String title, String permissionKey) {
    final isEnabled = _permissions[permissionKey] ?? false;
    final isDisabled = _selectedMaster == null || _isUpdatingPermissions;

    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: const Color(0xFF2B2B2B),
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
          GestureDetector(
            onTap: isDisabled ? null : () => _togglePermission(permissionKey),
            child: Container(
              width: 40,
              height: 25,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                borderRadius: BorderRadius.circular(12.5),
              ),
              child: Align(
                alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 23,
                  height: 23,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
