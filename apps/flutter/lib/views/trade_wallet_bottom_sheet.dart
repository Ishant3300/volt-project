import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../utils/number_to_words.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/master_service.dart';
import '../providers/user_profile_provider.dart';
import '../utils/contants.dart';
import '../utils/wallet_category.dart';

/// Dedicated Trade Wallet funding sheet — assign/withdraw category funds for the
/// current account. Mirrors the credit/debit sheet's visual structure. The
/// service used depends on the logged-in role: a MASTER viewer funds via
/// MasterService (transfer from the master's own pool); an ADMIN viewer funds via
/// AdminService (grant/remove).
class TradeWalletBottomSheet extends StatefulWidget {
  final Master? master;
  final User? user;

  const TradeWalletBottomSheet({super.key, this.master, this.user})
      : assert(master != null || user != null,
            'Either master or user must be provided');

  @override
  State<TradeWalletBottomSheet> createState() => _TradeWalletBottomSheetState();
}

class _TradeWalletBottomSheetState extends State<TradeWalletBottomSheet> {
  int _mode = 0; // 0 = Assign, 1 = Withdraw
  String? _category;
  final TextEditingController _amountController = TextEditingController();
  bool _isSubmitting = false;
  Map<String, double> _balances = {};

  /// Allowed categories for the current account, derived from its exchanges.
  List<String> get _allowedCats {
    if (widget.master != null) {
      return allowedCategories(widget.master!.exchangesAllowed);
    }
    return allowedCategories(
        widget.user!.exchangesAllowed.map((e) => e.exchangeName));
  }

  String get _targetId => widget.master?.id ?? widget.user!.id;
  String get _targetType => widget.user != null ? 'User' : 'Master';
  String get _targetName => widget.master?.username ?? widget.user!.username;

  @override
  void initState() {
    super.initState();
    // Seed balances from the already-loaded model, then refresh from backend.
    _balances = Map<String, double>.from(
        widget.user?.wallet ?? widget.master?.wallet ?? const {});
    final cats = _allowedCats;
    if (cats.isNotEmpty) _category = cats.first;
    _amountController.addListener(() => setState(() {}));
    _loadBalances();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  /// Pre-load current per-category balances (nice-to-have display).
  Future<void> _loadBalances() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      http.Response res;
      if (profileProvider.isMaster) {
        res = await MasterService(apiService)
            .getWallet(ownerId: _targetId, ownerType: _targetType);
      } else {
        res = await AdminService(apiService)
            .getWallet(ownerId: _targetId, ownerType: _targetType);
      }
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'];
        final walletMap = data is Map ? (data['wallet'] ?? data) : null;
        if (walletMap is Map) {
          setState(() {
            _balances = walletMap.map((k, v) =>
                MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0));
          });
        }
      }
    } catch (_) {
      // Non-fatal: balances are only a display aid.
    }
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountController.text.trim());
    if (_category == null) {
      _showSnack('Select a category', isError: true);
      return;
    }
    if (amount == null || amount <= 0) {
      _showSnack('Enter a valid amount', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      final isAssign = _mode == 0;
      final isMaster = profileProvider.isMaster;

      http.Response response;
      if (isMaster) {
        final svc = MasterService(apiService);
        response = isAssign
            ? await svc.walletAssign(
                targetId: _targetId,
                targetType: _targetType,
                category: _category!,
                amount: amount)
            : await svc.walletWithdraw(
                targetId: _targetId,
                targetType: _targetType,
                category: _category!,
                amount: amount);
      } else {
        final svc = AdminService(apiService);
        response = isAssign
            ? await svc.walletAssign(
                targetId: _targetId,
                targetType: _targetType,
                category: _category!,
                amount: amount)
            : await svc.walletWithdraw(
                targetId: _targetId,
                targetType: _targetType,
                category: _category!,
                amount: amount);
      }

      if (!mounted) return;
      final body = jsonDecode(response.body);
      if (response.statusCode == 200 && body['success'] == true) {
        _showSnack(
          '${isAssign ? 'Assigned' : 'Withdrew'} ${amount.toStringAsFixed(2)} '
          '${isAssign ? 'to' : 'from'} $_category',
          isError: false,
        );
        Navigator.pop(context, true);
      } else {
        // Surfaces backend 400 INSUFFICIENT_WALLET / 403 messages.
        _showSnack(body['message']?.toString() ?? 'Failed', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? kColorSell : kColorBuy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cats = _allowedCats;
    final Color actionColor =
        _mode == 0 ? kColorBuy : kColorSell;

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 32),
        decoration: const ShapeDecoration(
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
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Trade Wallet',
                  style: TextStyle(
                    color: kColorTextPrimary,
                    fontSize: kFontSizeSheetTitle,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
                Flexible(
                  child: Text(
                    _targetName,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: kColorTextMuted,
                      fontSize: kFontSizeSubtitle,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (cats.isEmpty) ...[
              const Text(
                'No fundable categories for this account.',
                style: TextStyle(
                  color: kColorTextMuted,
                  fontSize: kFontSizeSheetBody,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightMedium,
                ),
              ),
              const SizedBox(height: 20),
              _closeButton(),
            ] else ...[
              // Assign / Withdraw toggle
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    _buildModeToggle('Assign', 0, kColorBuy),
                    _buildModeToggle('Withdraw', 1, kColorSell),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Category selector
              const Text(
                'Category',
                style: TextStyle(
                  color: kColorTextMuted,
                  fontSize: kFontSizeSheetLabel,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cats.map(_buildCategoryChip).toList(),
              ),
              const SizedBox(height: 16),

              // Current balance for selected category
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF1F5F9)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Available ${_category ?? ''}',
                      style: const TextStyle(
                        color: kColorTextMuted,
                        fontSize: kFontSizeSheetLabel,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                    Text(
                      (_balances[_category] ?? 0).toStringAsFixed(2),
                      style: const TextStyle(
                        color: kColorTextPrimary,
                        fontSize: kFontSizeSheetBody,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightBold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Amount field
              const Text(
                'Amount',
                style: TextStyle(
                  color: kColorTextMuted,
                  fontSize: kFontSizeSheetLabel,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                    color: kColorTextPrimary,
                    fontSize: kFontSizeSheetBody,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    hintText: 'Enter amount',
                    hintStyle: TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: kFontSizeSheetHint,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightRegular,
                    ),
                  ),
                ),
              ),
              // Amount in words
              Builder(builder: (_) {
                final parsed = double.tryParse(_amountController.text.trim());
                final words = numberToIndianWords(parsed);
                if (words.isEmpty) return const SizedBox(height: 24);
                return Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 18),
                  child: Text(
                    '₹ $words',
                    style: const TextStyle(
                      color: kBrandPrimary,
                      fontSize: 12,
                      fontFamily: kFontFamily,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }),

              // Actions
              Row(
                children: [
                  Expanded(child: _closeButton()),
                  const SizedBox(width: 16),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isSubmitting ? null : _submit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: ShapeDecoration(
                          color: _isSubmitting
                              ? const Color(0xFF8E8E93)
                              : actionColor,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isSubmitting
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                ),
                              )
                            : Text(
                                _mode == 0 ? 'ASSIGN' : 'WITHDRAW',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
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
          ],
        ),
      ),
    );
  }

  Widget _closeButton() {
    return GestureDetector(
      onTap: _isSubmitting ? null : () => Navigator.pop(context),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: ShapeDecoration(
          color:
              _isSubmitting ? const Color(0xFFE5E5EA) : const Color(0xFFD1D1D6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text(
          'CLOSE',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: kColorTextPrimary,
            fontSize: kFontSizeButtonText,
            fontFamily: kFontFamily,
            fontWeight: kFontWeightSemiBold,
            height: 1.25,
          ),
        ),
      ),
    );
  }

  Widget _buildModeToggle(String label, int index, Color activeColor) {
    final selected = _mode == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : kColorTextMuted,
              fontSize: kFontSizeBodySmall,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String category) {
    final selected = _category == category;
    return GestureDetector(
      onTap: () => setState(() => _category = category),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kBrandPrimary : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? kBrandPrimary : const Color(0xFFF1F5F9),
          ),
        ),
        child: Text(
          category,
          style: TextStyle(
            color: selected ? Colors.white : kColorTextMuted,
            fontSize: kFontSizeBodySmall,
            fontFamily: kFontFamily,
            fontWeight: kFontWeightSemiBold,
          ),
        ),
      ),
    );
  }
}
