import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../providers/user_profile_provider.dart';

class CreateMasterView extends StatefulWidget {
  final Master? master; // If provided, we're in edit mode
  
  const CreateMasterView({super.key, this.master});

  @override
  State<CreateMasterView> createState() => _CreateMasterViewState();
}

class _CreateMasterViewState extends State<CreateMasterView> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _creditController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _profitLossController = TextEditingController();
  final TextEditingController _brkSharingController = TextEditingController();

  bool _addMaster = false;
  bool _changePasswordOnFirstLogin = true;
  bool _isSubmitting = false;
  String? _selectedServerId;
  List<Map<String, dynamic>> _servers = [];
  bool _isLoadingServers = false;
  
  Map<String, bool> _exchangeAllow = {
    'NSE': false,
    'MCX': false,
    'SGX': false,
    'CALLPUT': false,
    'OTHERS': false,
    'MCX-OPT': false,
  };

  Map<String, bool> _highLowBetweenTradeLimit = {
    'NSE': false,
    'MCX': false,
    'SGX': false,
    'CALLPUT': false,
    'OTHERS': false,
    'MCX-OPT': false,
  };

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _creditController.dispose();
    _noteController.dispose();
    _profitLossController.dispose();
    _brkSharingController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    
    // Fetch servers for admin users
    _fetchServers();
    
    // Add listeners to P&L and Brokerage controllers for real-time updates
    _profitLossController.addListener(() {
      setState(() {
        // Trigger rebuild to update "Remaining" display
      });
    });
    
    _brkSharingController.addListener(() {
      setState(() {
        // Trigger rebuild to update "Remaining" display
      });
    });
    
    // If we're editing an existing master, pre-fill the form
    if (widget.master != null) {
      final master = widget.master!;
      _nameController.text = master.name;
      _usernameController.text = master.username;
      _creditController.text = master.credits.toString();
      _noteController.text = master.note;
      _profitLossController.text = master.pnlSharing.toString();
      _brkSharingController.text = master.brokerageSharing.toString();
      
      _addMaster = master.addMaster; // Load the current value
      _changePasswordOnFirstLogin = master.changePassOnFirstLogin;
      _selectedServerId = master.serverId;
      
      // Set exchange allow
      for (var exchange in master.exchangesAllowed) {
        if (_exchangeAllow.containsKey(exchange)) {
          _exchangeAllow[exchange] = true;
        }
      }
      
      // Set high low between trade limit (tradeLimit in the model)
      for (var exchange in master.tradeLimit) {
        if (_highLowBetweenTradeLimit.containsKey(exchange)) {
          _highLowBetweenTradeLimit[exchange] = true;
        }
      }
    }
  }

  Future<void> _fetchServers() async {
    setState(() {
      _isLoadingServers = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      // Fetch all servers
      final response = await adminService.getAllServers();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          setState(() {
            _servers = List<Map<String, dynamic>>.from(data['data']['servers'] ?? []);
            _isLoadingServers = false;
          });
          log('✅ Loaded ${_servers.length} servers');
        }
      } else {
        log('❌ Failed to fetch servers: ${response.statusCode}');
        setState(() {
          _isLoadingServers = false;
        });
      }
    } catch (e) {
      log('❌ Error fetching servers: $e');
      setState(() {
        _isLoadingServers = false;
      });
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
                  Text(
                    widget.master != null ? 'Edit Master' : 'Create Master',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Personal Details Section
                    const Text(
                      'PERSONAL DETAILS',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildTextField(label: 'Name', controller: _nameController),
                          const SizedBox(height: 16),
                          _buildTextField(label: 'Username', controller: _usernameController),
                          const SizedBox(height: 16),
                          // Server selection dropdown (for Admin users)
                          Consumer<UserProfileProvider>(
                            builder: (context, profileProvider, child) {
                              if (profileProvider.isAdmin) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDropdownField(
                                      label: 'Server',
                                      hint: _isLoadingServers ? 'Loading servers...' : 'Select Server',
                                      value: _selectedServerId,
                                      onChanged: (value) {
                                        setState(() {
                                          _selectedServerId = value;
                                        });
                                      },
                                      items: _servers.map((server) => server['id'] as String).toList(),
                                      itemLabels: _servers.map((server) => server['name'] as String).toList(),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          _buildTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: true,
                            hint: widget.master != null ? 'Leave empty to keep current password' : 'Enter password',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Confirm Password',
                            controller: _confirmPasswordController,
                            obscureText: true,
                            hint: widget.master != null ? 'Leave empty to keep current password' : 'Confirm password',
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(
                            label: 'Credit',
                            controller: _creditController,
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          _buildTextField(label: 'Note/Remark', controller: _noteController),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Partnership Share Detail Section
                    const Text(
                      'PARTNERSHIP SHARE DETAIL',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Profit & Loss Sharing
                    Builder(
                      builder: (context) {
                        final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
                        final isMaster = profileProvider.isMaster;
                        final parentPnl = profileProvider.master?.pnlSharing ?? 100;
                        final enteredPnl = double.tryParse(_profitLossController.text) ?? 0;
                        final remainingPnl = isMaster ? (parentPnl - enteredPnl) : (100 - enteredPnl);
                        
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Profit & Loss sharing',
                                style: TextStyle(
                                  color: Color(0xFF2B2B2B),
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildInputField(
                                hint: 'Enter Profit & Loss Sharing',
                                controller: _profitLossController,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoBox(
                                      isMaster ? 'Our: ${parentPnl.toStringAsFixed(1)}' : 'Our: 100',
                                      const Color(0xFF22547C),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildInfoBox(
                                      'Remaining: ${remainingPnl.toStringAsFixed(1)}',
                                      remainingPnl < 0 ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 16),

                    // BRK Sharing
                    Builder(
                      builder: (context) {
                        final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
                        final isMaster = profileProvider.isMaster;
                        final parentBrk = profileProvider.master?.brokerageSharing ?? 100;
                        final enteredBrk = double.tryParse(_brkSharingController.text) ?? 0;
                        final remainingBrk = isMaster ? (parentBrk - enteredBrk) : (100 - enteredBrk);
                        
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'BRK SHARING',
                                style: TextStyle(
                                  color: Color(0xFF2B2B2B),
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _buildInputField(
                                hint: 'Enter Brk Sharing',
                                controller: _brkSharingController,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildInfoBox(
                                      isMaster ? 'Our: ${parentBrk.toStringAsFixed(1)}' : 'Our: 100',
                                      const Color(0xFF22547C),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildInfoBox(
                                      'Remaining: ${remainingBrk.toStringAsFixed(1)}',
                                      remainingBrk < 0 ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 24),

                    // Exchange Allow Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'EXCHANGE ALLOW',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              bool allSelected = _exchangeAllow.values.every((v) => v);
                              _exchangeAllow.updateAll((key, value) => !allSelected);
                            });
                          },
                          child: const Icon(Icons.check_circle_outline, size: 24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxItem('NSE', _exchangeAllow['NSE']!, (value) {
                                  setState(() => _exchangeAllow['NSE'] = value);
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCheckboxItem('MCX', _exchangeAllow['MCX']!, (value) {
                                  setState(() => _exchangeAllow['MCX'] = value);
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxItem('SGX', _exchangeAllow['SGX']!, (value) {
                                  setState(() => _exchangeAllow['SGX'] = value);
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCheckboxItem('CALLPUT', _exchangeAllow['CALLPUT']!, (value) {
                                  setState(() => _exchangeAllow['CALLPUT'] = value);
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxItem('OTHERS', _exchangeAllow['OTHERS']!, (value) {
                                  setState(() => _exchangeAllow['OTHERS'] = value);
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCheckboxItem('MCX-OPT', _exchangeAllow['MCX-OPT']!, (value) {
                                  setState(() => _exchangeAllow['MCX-OPT'] = value);
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // High Low Between Trade Limit Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'HIGH LOW BETWEEN TRADE LIMIT',
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              bool allSelected = _highLowBetweenTradeLimit.values.every((v) => v);
                              _highLowBetweenTradeLimit.updateAll((key, value) => !allSelected);
                            });
                          },
                          child: const Icon(Icons.check_circle_outline, size: 24),
                        ),
                      ],
                    ),
                    const SizedBox(height: 11),

                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxItem('NSE', _highLowBetweenTradeLimit['NSE']!, (value) {
                                  setState(() => _highLowBetweenTradeLimit['NSE'] = value);
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCheckboxItem('MCX', _highLowBetweenTradeLimit['MCX']!, (value) {
                                  setState(() => _highLowBetweenTradeLimit['MCX'] = value);
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxItem('SGX', _highLowBetweenTradeLimit['SGX']!, (value) {
                                  setState(() => _highLowBetweenTradeLimit['SGX'] = value);
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCheckboxItem('CALLPUT', _highLowBetweenTradeLimit['CALLPUT']!, (value) {
                                  setState(() => _highLowBetweenTradeLimit['CALLPUT'] = value);
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _buildCheckboxItem('OTHERS', _highLowBetweenTradeLimit['OTHERS']!, (value) {
                                  setState(() => _highLowBetweenTradeLimit['OTHERS'] = value);
                                }),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildCheckboxItem('MCX-OPT', _highLowBetweenTradeLimit['MCX-OPT']!, (value) {
                                  setState(() => _highLowBetweenTradeLimit['MCX-OPT'] = value);
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Toggle Switches
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildToggleRow(
                            'Add Master',
                            _addMaster,
                            (value) => setState(() => _addMaster = value),
                          ),
                          const SizedBox(height: 16),
                          _buildToggleRow(
                            'Change password on first login',
                            _changePasswordOnFirstLogin,
                            (value) => setState(() => _changePasswordOnFirstLogin = value),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Create/Update Button
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: _isSubmitting ? null : () async {
                          // Validate required fields
                          if (_nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter name'),
                                backgroundColor: Color(0xFFFF3B30),
                              ),
                            );
                            return;
                          }
                          
                          if (_usernameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter username'),
                                backgroundColor: Color(0xFFFF3B30),
                              ),
                            );
                            return;
                          }
                          
                          // Validate password fields if provided
                          if (_passwordController.text.isNotEmpty || _confirmPasswordController.text.isNotEmpty) {
                            if (_passwordController.text != _confirmPasswordController.text) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Passwords do not match'),
                                  backgroundColor: Color(0xFFFF3B30),
                                ),
                              );
                              return;
                            }
                          }
                          
                          setState(() {
                            _isSubmitting = true;
                          });
                          
                          try {
                            final apiService = Provider.of<ApiService>(context, listen: false);
                            final adminService = AdminService(apiService);
                            
                            // Get selected exchanges
                            final selectedExchanges = _exchangeAllow.entries
                                .where((entry) => entry.value)
                                .map((entry) => entry.key)
                                .toList();
                            
                            // Get selected trade limits
                            final selectedTradeLimit = _highLowBetweenTradeLimit.entries
                                .where((entry) => entry.value)
                                .map((entry) => entry.key)
                                .toList();
                            
                            if (widget.master != null) {
                              // Update existing master
                              log('💾 Updating master: ${widget.master!.id}');
                              
                              final response = await adminService.updateMaster(
                                masterId: widget.master!.id,
                                name: _nameController.text.trim(),
                                username: _usernameController.text.trim(),
                                password: _passwordController.text.isNotEmpty ? _passwordController.text : null,
                                credits: double.tryParse(_creditController.text.trim()),
                                note: _noteController.text.trim(),
                                pnlSharing: double.tryParse(_profitLossController.text.trim()),
                                brokerageSharing: double.tryParse(_brkSharingController.text.trim()),
                                exchangesAllowed: selectedExchanges,
                                tradeLimit: selectedTradeLimit,
                                addMaster: _addMaster,
                                changePassOnFirstLogin: _changePasswordOnFirstLogin,
                              );
                              
                              if (response.statusCode == 200) {
                                log('✅ Master updated successfully');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Master updated successfully'),
                                      backgroundColor: Color(0xFF34C759),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  Navigator.pop(context, true);
                                }
                              } else {
                                log('❌ Failed to update master: ${response.statusCode}');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Failed to update master'),
                                      backgroundColor: Color(0xFFFF3B30),
                                    ),
                                  );
                                }
                              }
                            } else {
                              // Create new master
                              log('💾 Creating new master');
                              
                              // Validate password is provided for new master
                              if (_passwordController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password is required for new master'),
                                    backgroundColor: Color(0xFFFF3B30),
                                  ),
                                );
                                setState(() => _isSubmitting = false);
                                return;
                              }
                              
                              // Get current user's serverId
                              final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
                              
                              String? serverId;
                              
                              if (profileProvider.isAdmin) {
                                // Admin: Use selected server from dropdown
                                serverId = _selectedServerId;
                                
                                if (serverId == null || serverId.isEmpty) {
                                  log('❌ No server selected');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please select a server'),
                                      backgroundColor: Color(0xFFFF3B30),
                                    ),
                                  );
                                  setState(() => _isSubmitting = false);
                                  return;
                                }
                                
                                log('✅ Admin using selected serverId: $serverId');
                              } else {
                                // Master: Use their own serverId
                                serverId = profileProvider.master?.serverId;
                                
                                log('🔍 Checking serverId from master profile');
                                log('   Role: ${profileProvider.role}');
                                log('   Master serverId: ${profileProvider.master?.serverId}');
                                log('   Master username: ${profileProvider.master?.username}');
                                
                                if (serverId == null || serverId.isEmpty) {
                                  log('❌ ServerId not found in master profile');
                                  
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Server ID not found. Please logout and login again.'),
                                      backgroundColor: Color(0xFFFF3B30),
                                    ),
                                  );
                                  setState(() => _isSubmitting = false);
                                  return;
                                }
                                
                                log('✅ Master using serverId: $serverId');
                              }
                              
                              final response = await adminService.createMaster(
                                name: _nameController.text.trim(),
                                username: _usernameController.text.trim(),
                                password: _passwordController.text,
                                credits: double.tryParse(_creditController.text.trim()) ?? 0,
                                note: _noteController.text.trim(),
                                pnlSharing: double.tryParse(_profitLossController.text.trim()) ?? 0,
                                brokerageSharing: double.tryParse(_brkSharingController.text.trim()) ?? 0,
                                exchangesAllowed: selectedExchanges,
                                tradeLimit: selectedTradeLimit,
                                addMaster: _addMaster,
                                changePassOnFirstLogin: _changePasswordOnFirstLogin,
                                serverId: serverId,
                              );
                              
                              if (response.statusCode == 201) {
                                log('✅ Master created successfully');
                                if (mounted) {
                                  // Refresh profile to update credits
                                  await profileProvider.fetchProfile();
                                  
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Master created successfully'),
                                      backgroundColor: Color(0xFF34C759),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  Navigator.pop(context, true);
                                }
                              } else {
                                log('❌ Failed to create master: ${response.statusCode}');
                                log('   Response body: ${response.body}');
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to create master: ${response.body}'),
                                      backgroundColor: const Color(0xFFFF3B30),
                                    ),
                                  );
                                }
                              }
                            }
                          } catch (e) {
                            log('❌ Error: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error: $e'),
                                  backgroundColor: const Color(0xFFFF3B30),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                _isSubmitting = false;
                              });
                            }
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
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
                              : Text(
                                  widget.master != null ? 'UPDATE MASTER' : 'CREATE MASTER',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String hint,
    required String? value,
    required Function(String?) onChanged,
    required List<String> items,
    List<String>? itemLabels,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              hint: Text(
                hint,
                style: const TextStyle(
                  color: Color(0xFF8E8E93),
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                ),
              ),
              isExpanded: true,
              icon: const Icon(Icons.arrow_forward_ios, size: 16),
              onChanged: onChanged,
              items: items.asMap().entries.map((entry) {
                final index = entry.key;
                final item = entry.value;
                final label = itemLabels != null && index < itemLabels.length 
                    ? itemLabels[index] 
                    : item;
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(label),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint ?? 'Placeholder',
              hintStyle: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required String hint,
    required TextEditingController controller,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(
            color: Color(0xFF8E8E93),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
          ),
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _buildInfoBox(String text, Color color) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontFamily: 'Inter',
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildCheckboxItem(String label, bool value, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: value ? const Color(0xFF22547C) : Colors.transparent,
                border: Border.all(
                  color: value ? const Color(0xFF22547C) : const Color(0xFFC7C7CC),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: value
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
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
  }

  Widget _buildToggleRow(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        GestureDetector(
          onTap: () => onChanged(!value),
          child: Container(
            width: 40,
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: ShapeDecoration(
              color: value ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.50),
              ),
            ),
            child: Align(
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 23,
                height: 23,
                decoration: const ShapeDecoration(
                  color: Colors.white,
                  shape: OvalBorder(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
