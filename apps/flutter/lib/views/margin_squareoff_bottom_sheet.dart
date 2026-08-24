import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../utils/contants.dart';

class MarginSquareoffBottomSheet extends StatefulWidget {
  final Master? master;
  final User? user;
  
  const MarginSquareoffBottomSheet({
    super.key,
    this.master,
    this.user,
  }) : assert(master != null || user != null, 'Either master or user must be provided');

  @override
  State<MarginSquareoffBottomSheet> createState() => _MarginSquareoffBottomSheetState();
}

class _MarginSquareoffBottomSheetState extends State<MarginSquareoffBottomSheet> {
  final TextEditingController _percentageController = TextEditingController();
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      log('🔄 Loading margin squareoff settings');
      
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
      
      // Load the current percentage value
      double? currentPercentage;
      if (freshMaster != null) {
        currentPercentage = freshMaster.marginSquareOffPercentage;
      } else if (freshUser != null) {
        currentPercentage = freshUser.marginSquareOffPercentage;
      }
      
      if (currentPercentage != null && currentPercentage > 0) {
        _percentageController.text = currentPercentage.toString();
      }
      
      log('   Current percentage: $currentPercentage');
      
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

  Future<void> _submitPercentage() async {
    String percentage = _percentageController.text.trim();
    
    if (percentage.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a percentage value')),
      );
      return;
    }

    final percentageValue = double.tryParse(percentage);
    if (percentageValue == null || percentageValue < 0 || percentageValue > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid percentage between 0 and 100')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      log('💾 Updating margin squareoff percentage: $percentageValue');
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      http.Response response;
      
      if (widget.master != null) {
        response = await adminService.updateMasterMarginSquareoffPercentage(
          masterId: widget.master!.id,
          percentage: percentageValue,
        );
      } else {
        response = await adminService.updateUserMarginSquareoffPercentage(
          userId: widget.user!.id,
          percentage: percentageValue,
        );
      }
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          log('   ✅ Percentage updated successfully');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Margin squareoff percentage updated successfully')),
            );
            Navigator.pop(context, true);
          }
        } else {
          throw Exception(data['message'] ?? 'Failed to update percentage');
        }
      } else {
        final data = jsonDecode(response.body);
        throw Exception(data['message'] ?? 'Failed to update percentage');
      }
    } catch (e) {
      log('   ❌ Error updating percentage: $e');
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
  void dispose() {
    _percentageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
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
                child: CircularProgressIndicator(color: kBrandPrimary),
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
                          'Margin SquareOff Settings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeSheetTitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16),

                  // Input Section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add Percentage (%)',
                        style: TextStyle(
                          color: const Color(0xFF2B2B2B),
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              width: 1,
                              color: const Color(0xFFD1D1D6),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: TextField(
                          controller: _percentageController,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter percentage',
                            hintStyle: TextStyle(
                              color: const Color(0xFF8E8E93),
                              fontSize: kFontSizeSheetHint,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightRegular,
                            ),
                          ),
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeSheetBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightRegular,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 16),

                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSubmitting ? null : () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            decoration: ShapeDecoration(
                              color: _isSubmitting ? const Color(0xFFE5E5EA) : const Color(0xFFD1D1D6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(
                              'CLOSE',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: kFontSizeButtonText,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightSemiBold,
                                height: 1.25,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSubmitting ? null : _submitPercentage,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            decoration: ShapeDecoration(
                              color: _isSubmitting ? const Color(0xFF8E8E93) : kBrandPrimary,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: _isSubmitting
                                ? Center(
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
                                    'SUBMIT',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: kFontSizeButtonText,
                                      fontFamily: kFontFamily,
                                      fontWeight: kFontWeightSemiBold,
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
      ),
    );
  }
}