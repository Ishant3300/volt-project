import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/master_service.dart';
import '../services/sercure_storage_service.dart';
import '../providers/user_profile_provider.dart';
import '../utils/contants.dart';

class TransactionPage extends StatefulWidget {
  final Master? master;
  final User? user;

  const TransactionPage({super.key, this.master, this.user})
      : assert(master != null || user != null);

  @override
  State<TransactionPage> createState() => _TransactionPageState();
}

class _TransactionPageState extends State<TransactionPage> {
  int _selectedTab = 0; // 0 = History, 1 = Credit/Debit

  // History state
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoadingHistory = false;
  bool _hasMore = true;
  int _page = 1;

  // Credit/Debit state
  int _txnType = 0; // 0 = Credit, 1 = Debit
  final _amountController = TextEditingController();
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  String get _targetId => widget.master?.id ?? widget.user!.id;
  String get _targetModel => widget.master != null ? 'Master' : 'User';
  String get _targetName => widget.master?.username ?? widget.user!.username;
  double _currentCredits = 0;

  @override
  void initState() {
    super.initState();
    _currentCredits = widget.master?.credits ?? widget.user!.credits;
    _amountController.addListener(() => setState(() {}));
    _fetchHistory();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _transactions = [];
    }
    if (!_hasMore || _isLoadingHistory) return;
    setState(() => _isLoadingHistory = true);
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final apiService = ApiService(backendUrl);
      final res = await apiService.get(
        '/master/transactions?target_id=$_targetId&target_model=$_targetModel&page=$_page&limit=30&type=CREDIT,DEBIT',
        token: token,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List txns = body['data']['transactions'] ?? [];
        final int total = body['data']['total'] ?? 0;
        // Filter to only show CREDIT/DEBIT transactions
        final filteredTxns = txns.where((txn) {
          final type = (txn['type'] ?? '').toString().toUpperCase();
          return type == 'CREDIT' || type == 'DEBIT';
        }).toList();
        setState(() {
          _transactions.addAll(filteredTxns.cast<Map<String, dynamic>>());
          _hasMore = _transactions.length < total;
          _page++;
        });
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
    } finally {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  Future<void> _handleSubmit() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final masterService = MasterService(apiService);
      final isCredit = _txnType == 0;
      final note = _commentController.text.trim().isEmpty ? null : _commentController.text.trim();
      final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
      final isMaster = profileProvider.isMaster;

      late final dynamic response;
      if (widget.master != null) {
        response = isCredit
            ? await adminService.creditMaster(masterId: widget.master!.id, amount: amount, note: note)
            : await adminService.debitMaster(masterId: widget.master!.id, amount: amount, note: note);
      } else {
        // Use master endpoint if caller is a master, admin endpoint if caller is admin
        response = isCredit
            ? (isMaster
                ? await masterService.creditUser(userId: widget.user!.id, amount: amount, note: note)
                : await adminService.creditUser(userId: widget.user!.id, amount: amount, note: note))
            : (isMaster
                ? await masterService.debitUser(userId: widget.user!.id, amount: amount, note: note)
                : await adminService.debitUser(userId: widget.user!.id, amount: amount, note: note));
      }

      if (response.statusCode == 200) {
        if (mounted) {
          // Update local credits from response
          try {
            final body = jsonDecode(response.body);
            final newCredits = (body['data']?['credits'] as num?)?.toDouble();
            if (newCredits != null) {
              setState(() => _currentCredits = newCredits);
            } else {
              // Fallback: manually adjust
              final amt = double.tryParse(_amountController.text) ?? 0;
              setState(() {
                _currentCredits += _txnType == 0 ? amt : -amt;
              });
            }
          } catch (_) {
            final amt = double.tryParse(_amountController.text) ?? 0;
            setState(() {
              _currentCredits += _txnType == 0 ? amt : -amt;
            });
          }

          final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
          await profileProvider.fetchProfile();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${isCredit ? "Credit" : "Debit"} successful')),
          );
          _amountController.clear();
          _commentController.clear();
          // Refresh history
          await _fetchHistory(refresh: true);
        }
      } else {
        if (mounted) {
          final body = jsonDecode(response.body);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(body['message'] ?? 'Failed'), backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Transactions', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                        Text(_targetName, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(
                children: [
                  _buildTab('History', 0),
                  _buildTab('Credit / Debit', 1),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: _selectedTab == 0 ? _buildHistoryTab() : _buildCreditDebitTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final selected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3F45C7) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  // ── History Tab ──
  Widget _buildHistoryTab() {
    if (_isLoadingHistory && _transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5));
    }
    if (_transactions.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _fetchHistory(refresh: true),
        child: ListView(
          children: [
            const SizedBox(height: 200),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
                    ),
                    child: const Icon(Icons.receipt_long, size: 32, color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 20),
                  const Text('No transactions yet', style: TextStyle(color: Color(0xFF475569), fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchHistory(refresh: true),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: NotificationListener<ScrollNotification>(
          onNotification: (scroll) {
            if (scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 100 && _hasMore && !_isLoadingHistory) {
              _fetchHistory();
            }
            return false;
          },
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: _transactions.length + (_hasMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              if (index >= _transactions.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2)),
                );
              }
              return _buildTransactionItem(_transactions[index]);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> txn) {
    final String type = txn['type'] ?? '';
    final bool isCredit = type == 'CREDIT';
    final double amount = (txn['amount'] as num?)?.toDouble() ?? 0;
    final double balBefore = (txn['balanceBefore'] as num?)?.toDouble() ?? 0;
    final double balAfter = (txn['balanceAfter'] as num?)?.toDouble() ?? 0;
    final String note = (txn['metadata'] is Map ? txn['metadata']['note'] : null) ?? '';
    final String dateStr = txn['createdAt'] ?? '';

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      formattedDate = DateFormat('dd MMM yyyy · hh:mm a').format(dt);
    } catch (_) {}

    final Color typeColor = isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: typeColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: kIconSizeDefault,
              color: typeColor,
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: type label + amount
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isCredit ? 'Credit' : 'Debit',
                      style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold),
                    ),
                    Text(
                      '${isCredit ? '+' : '-'}${amount.toStringAsFixed(2)}',
                      style: TextStyle(color: typeColor, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightBold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Row 2: date + note
                Row(
                  children: [
                    Text(formattedDate, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                    if (note.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 5),
                        child: Text('·', style: TextStyle(fontSize: kFontSizeCaption, color: Color(0xFFCBD5E1))),
                      ),
                      Flexible(
                        child: Text(note, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightMedium), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                // Row 3: balance before → after
                Text(
                  '${balBefore.toStringAsFixed(2)} → ${balAfter.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeCaption, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Credit/Debit Tab ──
  Widget _buildCreditDebitTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Credit/Debit toggle
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                _buildTypeToggle('Credit', 0, const Color(0xFF10B981)),
                _buildTypeToggle('Debit', 1, const Color(0xFFEF4444)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Available credit card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available Credit', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                Text('${_currentCredits.toStringAsFixed(2)}', style: const TextStyle(color: Colors.black, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Amount field
          const Text('Amount', style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
            decoration: InputDecoration(
              hintText: 'Enter amount',
              hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeButtonText, fontFamily: 'Inter'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF3F45C7), width: 1.5)),
            ),
          ),
          const SizedBox(height: 16),

          // Comment field
          const Text('Comment', style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 3,
            style: const TextStyle(fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
            decoration: InputDecoration(
              hintText: 'Add a note (optional)',
              hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeButtonText, fontFamily: 'Inter'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF3F45C7), width: 1.5)),
            ),
          ),
          const SizedBox(height: 24),

          // Submit button
          GestureDetector(
            onTap: _isSubmitting ? null : _handleSubmit,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: _isSubmitting ? const Color(0xFF94A3B8) : (_txnType == 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: _isSubmitting
                  ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                  : Text(
                      _txnType == 0 ? 'Credit ${_amountController.text.isNotEmpty ? _amountController.text : "0"}' : 'Debit ${_amountController.text.isNotEmpty ? _amountController.text : "0"}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightBold),
                    ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildTypeToggle(String label, int index, Color activeColor) {
    final selected = _txnType == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _txnType = index),
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
              color: selected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold,
            ),
          ),
        ),
      ),
    );
  }
}
