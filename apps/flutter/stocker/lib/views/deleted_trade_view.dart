import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class DeletedTradeView extends StatefulWidget {
  const DeletedTradeView({super.key});
  @override
  State<DeletedTradeView> createState() => _DeletedTradeViewState();
}

class _DeletedTradeViewState extends State<DeletedTradeView> {
  List<Map<String, dynamic>> _trades = [];
  bool _isLoading = false;
  int _total = 0;
  int _page = 1;
  final _limit = 50;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  DateTime? _filterDate;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch({bool append = false}) async {
    if (!append) setState(() { _isLoading = true; _page = 1; });
    try {
      final token = await SecureStorageService().getToken();
      final params = <String>['page=$_page', 'limit=$_limit'];
      if (_searchQuery.isNotEmpty) params.add('search=$_searchQuery');
      if (_filterDate != null) {
        params.add('date=${DateFormat('yyyy-MM-dd').format(_filterDate!)}');
      }
      final qs = params.join('&');
      final res = await ApiService(backendUrl).get('/trade/deleted-trades?$qs', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          final list = List<Map<String, dynamic>>.from(body['data'] ?? []);
          setState(() {
            if (append) { _trades.addAll(list); } else { _trades = list; }
            _total = body['total'] ?? list.length;
          });
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _loadMore() {
    if (_trades.length < _total) {
      _page++;
      _fetch(append: true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: kBrandPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _filterDate = picked);
      _fetch();
    }
  }

  void _clearDate() {
    setState(() => _filterDate = null);
    _fetch();
  }

  String _fmtDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd MMM yyyy · HH:mm').format(dt);
    } catch (_) { return dateStr; }
  }

  @override
  Widget build(BuildContext context) {
    final role = context.read<UserProfileProvider>();
    final showUserInfo = role.isAdmin || role.isMaster;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Deleted Trades',
                  style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle,
                    fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$_total',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: kFontSizeBodySmall,
                    fontFamily: 'Inter', fontWeight: kFontWeightBold)),
              ),
            ]),
          ),

          // Search + Date filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) {
                      _searchQuery = v;
                      _fetch();
                    },
                    style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
                    decoration: InputDecoration(
                      hintText: 'Search script...',
                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: 'Inter'),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () { _searchCtrl.clear(); _searchQuery = ''; _fetch(); },
                              child: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8)))
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _filterDate != null ? kBrandPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Icon(Icons.calendar_today, size: 18,
                    color: _filterDate != null ? Colors.white : const Color(0xFF94A3B8)),
                ),
              ),
            ]),
          ),

          // Date chip
          if (_filterDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: kBrandPrimary.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(DateFormat('dd MMM yyyy').format(_filterDate!),
                      style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeNavLabel,
                        fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: _clearDate,
                      child: const Icon(Icons.close, size: kIconSizeSmall, color: kBrandPrimary),
                    ),
                  ]),
                ),
              ]),
            ),

          const SizedBox(height: 12),

          // Table header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(children: [
              const Expanded(flex: 3,
                child: Text('SCRIPT', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel,
                  fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5))),
              if (showUserInfo)
                const Expanded(flex: 2,
                  child: Text('USER', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel,
                    fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5))),
              const Expanded(flex: 3,
                child: Text('DELETED AT', textAlign: TextAlign.right,
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel,
                    fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5))),
            ]),
          ),

          // List
          Expanded(
            child: _isLoading && _trades.isEmpty
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
                : _trades.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 48, color: const Color(0xFF94A3B8).withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text('No deleted trades',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: 'Inter')),
                        ],
                      ))
                    : NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n is ScrollEndNotification && n.metrics.extentAfter < 100) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: RefreshIndicator(
                          color: kBrandPrimary,
                          onRefresh: _fetch,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _trades.length,
                            itemBuilder: (_, i) => _buildRow(_trades[i], i, showUserInfo),
                          ),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> t, int index, bool showUserInfo) {
    final symbol = t['tradingsymbol'] ?? '';
    final exchange = t['exchange'] ?? '';
    final txnType = t['transaction_type'] ?? '';
    final qty = t['quantity'] ?? t['executed_quantity'] ?? 0;
    final price = t['executed_price'] ?? t['price'] ?? 0;
    final username = t['username'] ?? '';
    final masterUsername = t['master_username'] ?? '';
    final deletedAt = _fmtDate(t['deleted_at']?.toString());
    final isBuy = txnType == 'BUY';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: index % 2 == 0 ? Colors.white : const Color(0xFFFAFBFC),
        border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9), width: 0.5)),
      ),
      child: Row(children: [
        Expanded(flex: 3, child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(symbol,
              style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeBodySmall,
                fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: -0.3),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Wrap(spacing: 4, runSpacing: 2, children: [
              Text(exchange,
                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption,
                  fontFamily: 'Inter', fontWeight: kFontWeightMedium, letterSpacing: 0.5)),
              const Text('·', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: isBuy ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(txnType,
                  style: TextStyle(
                    color: isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    fontSize: kFontSizeCaption, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
              ),
              const Text('·', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption)),
              Text('$qty @ ${(price as num).toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeCaption,
                  fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
            ]),
          ],
        )),
        if (showUserInfo)
          Expanded(flex: 2, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(username,
                style: const TextStyle(color: Colors.black, fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter', fontWeight: kFontWeightSemiBold),
                maxLines: 1, overflow: TextOverflow.ellipsis),
              if (masterUsername.isNotEmpty)
                Text(masterUsername,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption,
                    fontFamily: 'Inter', fontWeight: kFontWeightMedium),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          )),
        Expanded(flex: 3, child: Text(deletedAt, textAlign: TextAlign.right,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeNavLabel,
            fontFamily: 'Inter', fontWeight: kFontWeightMedium))),
      ]),
    );
  }
}
