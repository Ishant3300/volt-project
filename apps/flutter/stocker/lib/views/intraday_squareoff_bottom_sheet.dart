import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../models/master.dart';
import '../models/user.dart';

class IntradaySquareoffBottomSheet extends StatefulWidget {
  final Master? master;
  final User? user;
  
  const IntradaySquareoffBottomSheet({
    super.key,
    this.master,
    this.user,
  }) : assert(master != null || user != null, 'Either master or user must be provided');

  @override
  State<IntradaySquareoffBottomSheet> createState() => _IntradaySquareoffBottomSheetState();
}

class _IntradaySquareoffBottomSheetState extends State<IntradaySquareoffBottomSheet> {
  Map<String, bool> _exchangeSettings = {};
  List<String> _allowedExchanges = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      log('🔄 Loading intraday squareoff settings');
      
      // Fetch fresh master/user data from backend
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      Master? freshMaster;
      User? freshUser;
      
      if (widget.master != null) {
        log('   Fetching fresh master data for: ${widget.master!.id}');
        final response = await adminService.getMasterById(widget.master!.id);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            freshMaster = Master.fromJson(data['data']);
          }
        }
      } else if (widget.user != null) {
        log('   Fetching fresh user data for: ${widget.user!.id}');
        final response = await adminService.getUserById(widget.user!.id);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            freshUser = User.fromJson(data['data']);
          }
        }
      }
      
      // Get allowed exchanges from the fresh data
      if (freshMaster != null) {
        _allowedExchanges = freshMaster.exchangesAllowed.isNotEmpty
            ? freshMaster.exchangesAllowed
            : (freshMaster.exchanges ?? []);
      } else if (freshUser != null) {
        _allowedExchanges = freshUser.exchangesAllowed
            .map((ex) => ex.exchangeName)
            .toList();
      } else {
        // Fallback to passed data if fetch failed
        if (widget.master != null) {
          _allowedExchanges = widget.master!.exchangesAllowed.isNotEmpty
              ? widget.master!.exchangesAllowed
              : (widget.master!.exchanges ?? []);
        } else if (widget.user != null) {
          _allowedExchanges = widget.user!.exchangesAllowed
              .map((ex) => ex.exchangeName)
              .toList();
        }
      }
      
      log('   Allowed exchanges: $_allowedExchanges');
      
      // Get current intraday squareoff settings from fresh data
      final List<IntradaySquareoffSetting> intradaySquareoff = 
          freshMaster?.intradaySquareoff ?? 
          freshUser?.intradaySquareoff ?? 
          widget.master?.intradaySquareoff ?? 
          widget.user?.intradaySquareoff ?? 
          [];
      
      // Initialize settings map
      for (var exchange in _allowedExchanges) {
        _exchangeSettings[exchange] = false;
      }
      
      // Update with saved settings
      for (var setting in intradaySquareoff) {
        final exchangeName = setting.exchangeName;
        final enabled = setting.enabled;
        if (_allowedExchanges.contains(exchangeName)) {
          _exchangeSettings[exchangeName] = enabled;
        }
      }
      
      log('   Current settings: $_exchangeSettings');
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      log('   ❌ Error loading settings: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading settings: $e')),
        );
      }
    }
  }

  Future<void> _updateSettings() async {
    try {
      log('💾 Updating intraday squareoff settings');
      
      // Convert settings map to list format for API
      final intradaySquareoff = _exchangeSettings.entries
          .map((entry) => {
                'exchange_name': entry.key,
                'enabled': entry.value,
              })
          .toList();
      
      log('   Settings to save: $intradaySquareoff');
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      http.Response response;
      
      if (widget.master != null) {
        response = await adminService.updateMasterIntradaySquareoff(
          masterId: widget.master!.id,
          intradaySquareoff: intradaySquareoff,
        );
      } else {
        response = await adminService.updateUserIntradaySquareoff(
          userId: widget.user!.id,
          intradaySquareoff: intradaySquareoff,
        );
      }
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          log('   ✅ Settings updated successfully');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Settings updated successfully')),
            );
            Navigator.pop(context, true); // Return true to indicate success
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update settings');
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to update settings');
      }
    } catch (e) {
      log('   ❌ Error updating settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 24,
        left: 16,
        right: 16,
        bottom: 56,
      ),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),
      child: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: const Color(0xFF22547C)),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Container(
                  width: double.infinity,
                  child: Row(
                    children: [
                      Text(
                        'Intraday SquareOff Settings',
                        textAlign: TextAlign.center,
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

                // Toggle Section
                if (_allowedExchanges.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No exchanges allowed',
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      children: _allowedExchanges.asMap().entries.map((entry) {
                        final index = entry.key;
                        final exchange = entry.value;
                        final isEnabled = _exchangeSettings[exchange] ?? false;
                        
                        return Column(
                          children: [
                            if (index > 0) SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  exchange.toUpperCase(),
                                  style: TextStyle(
                                    color: const Color(0xFF2B2B2B),
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _exchangeSettings[exchange] = !isEnabled;
                                    });
                                  },
                                  child: Container(
                                    width: 40,
                                    height: 25,
                                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                    decoration: ShapeDecoration(
                                      color: isEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12.50),
                                      ),
                                    ),
                                    child: Align(
                                      alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        width: 23,
                                        height: 23,
                                        decoration: ShapeDecoration(
                                          color: Colors.white,
                                          shape: OvalBorder(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                SizedBox(height: 16),

                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                          decoration: ShapeDecoration(
                            color: const Color(0xFFD1D1D6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            'CLOSE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: GestureDetector(
                        onTap: _updateSettings,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                          decoration: ShapeDecoration(
                            color: const Color(0xFF22547C),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            'UPDATE',
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
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
