import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../providers/user_profile_provider.dart';
import '../utils/contants.dart';

class CreditDebitBottomSheet extends StatefulWidget {
  final Master? master;
  final User? user;
  
  const CreditDebitBottomSheet({super.key, this.master, this.user})
      : assert(master != null || user != null, 'Either master or user must be provided');

  @override
  State<CreditDebitBottomSheet> createState() => _CreditDebitBottomSheetState();
}

class _CreditDebitBottomSheetState extends State<CreditDebitBottomSheet> {
  int _selectedTab = 0; // 0 for Credit, 1 for Debit
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _commentController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final amount = double.tryParse(_amountController.text);
    
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter a valid amount')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      final isCredit = _selectedTab == 0;
      final note = _commentController.text.trim().isEmpty ? null : _commentController.text.trim();
      
      if (widget.master != null) {
        // Admin crediting/debiting master
        final response = isCredit
            ? await adminService.creditMaster(
                masterId: widget.master!.id,
                amount: amount,
                note: note,
              )
            : await adminService.debitMaster(
                masterId: widget.master!.id,
                amount: amount,
                note: note,
              );
        
        if (response.statusCode == 200) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${isCredit ? "Credit" : "Debit"} successful')),
            );
            Navigator.pop(context, true); // Return true to indicate success
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to ${isCredit ? "credit" : "debit"} amount')),
            );
          }
        }
      } else {
        // Master crediting/debiting user
        final response = isCredit
            ? await adminService.creditUser(
                userId: widget.user!.id,
                amount: amount,
                note: note,
              )
            : await adminService.debitUser(
                userId: widget.user!.id,
                amount: amount,
                note: note,
              );
        
        if (response.statusCode == 200) {
          if (mounted) {
            // Refresh the master profile to update credits
            final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
            await profileProvider.fetchProfile();
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${isCredit ? "Credit" : "Debit"} successful')),
            );
            Navigator.pop(context, true); // Return true to indicate success
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to ${isCredit ? "credit" : "debit"} amount')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 56),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Transaction',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeSheetTitle,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
            ),
          ),

          SizedBox(height: 16),

          // Credit/Debit Tabs
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    decoration: ShapeDecoration(
                      color: _selectedTab == 0 ? const Color(0xFF3F45C7) : Colors.white,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(width: 1, color: const Color(0xFF3F45C7)),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                    ),
                    child: Text(
                      'Credit',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedTab == 0 ? Colors.white : const Color(0xFF333333),
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    decoration: ShapeDecoration(
                      color: _selectedTab == 1 ? const Color(0xFF3F45C7) : Colors.white,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(width: 1, color: const Color(0xFF3F45C7)),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                    ),
                    child: Text(
                      'Debit',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedTab == 1 ? Colors.white : const Color(0xFF333333),
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Available Credit
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: ShapeDecoration(
              color: const Color(0xFFE5E5EA),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              'Available Credit: ${(widget.master?.credits ?? widget.user?.credits ?? 0).toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.black,
                fontSize: kFontSizeSectionHeader,
                fontFamily: 'Inter',
                fontWeight: kFontWeightRegular,
              ),
            ),
          ),

          SizedBox(height: 16),

          // Add Amount
          Text(
            'Add Amount',
            style: TextStyle(
              color: const Color(0xFF2B2B2B),
              fontSize: kFontSizeSectionHeader,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Enter amount',
              hintStyle: TextStyle(
                color: const Color(0xFF8E8E93),
                fontSize: kFontSizeSectionHeader,
                fontFamily: 'Inter',
                fontWeight: kFontWeightRegular,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: const Color(0xFF3F45C7)),
              ),
            ),
          ),

          SizedBox(height: 16),

          // Comment
          Text(
            'Comment',
            style: TextStyle(
              color: const Color(0xFF2B2B2B),
              fontSize: kFontSizeSectionHeader,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Add a comment (optional)',
              hintStyle: TextStyle(
                color: const Color(0xFF8E8E93),
                fontSize: kFontSizeSectionHeader,
                fontFamily: 'Inter',
                fontWeight: kFontWeightRegular,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(width: 1, color: const Color(0xFF3F45C7)),
              ),
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
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFD1D1D6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'CLOSE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeButtonText,
                        fontFamily: 'Inter',
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
                  onTap: _isLoading ? null : () {
                    _handleSubmit();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: ShapeDecoration(
                      color: _isLoading ? const Color(0xFF8E8E93) : const Color(0xFF3F45C7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _isLoading
                        ? Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                          )
                        : Text(
                            'SUBMIT',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: kFontSizeButtonText,
                              fontFamily: 'Inter',
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
    );
  }
}
