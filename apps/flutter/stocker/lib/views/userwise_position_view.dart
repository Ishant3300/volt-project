import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import 'userwise_position_filter_bottom_sheet.dart';

class UserwisePositionView extends StatefulWidget {
  const UserwisePositionView({super.key});
  @override
  State<UserwisePositionView> createState() => _UserwisePositionViewState();
}

class _UserwisePositionViewState extends State<UserwisePositionView> {
  List<Map<String, dynamic>> _positions = [];
  bool _isLoading = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // Filter state
  String? _filterExchange;
  String? _filterTradingsymbol;
  String? _filterUserId;
  String? _filterUserName;

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

  String get _role {
    final p = context.read<UserProfileProvider>();
    if (p.isAdmin) return 'ADMIN';
    if (p.isMaster) return 'MASTER';
    return 'USER';
  }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final params = <String>[];
      if (_filterExchange != null) params.add('exchange=$_filterExchange');
      if (_filterTradingsymbol != null) params.add('tradingsymbol=$_filterTradingsymbol');
      if (_filterUserId != null) params.add('search=');
      final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await ApiService(backendUrl).get('/trade/userwise-positions$qs', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          setState(() => _positions = List<Map<String, dynamic>>.from(body['data']));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    var list = _positions;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) =>
        (p['username'] ?? '').toString().toLowerCase().contains(q) ||
        (p['tradingsymbol'] ?? '').toString().toLowerCase().contains(q) ||
        (p['master_username'] ?? '').toString().toLowerCase().contains(q)
      ).toList();
    }
    if (_filterUserId != null) {
      list = list.where((p) => p['user_id'] == _filterUserId).toList();
    }
    return list;
  }

  bool get _hasActiveFilters =>
      _filterExchange != null || _filterTradingsymbol != null || _filterUserId != null;

  Future<void> _openFilter() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserwisePositionFilterBottomSheet(
        role: _role,
        initialExchange: _filterExchange,
        initialTradingsymbol: _filterTradingsymbol,
        initialUserId: _filterUserId,
        initialUserName: _filterUserName,
      ),
    );
    if (result != null) {
      setState(() {
        _filterExchange = result['exchange'];
        _filterTradingsymbol = result['tradingsymbol'];
        _filterUserId = result['userId'];
        _filterUserName = result['userName'];
      });
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
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
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Userwise Positions',
                  style: TextStyle(color: Colors.black, fontSize: 18,
                    fontFamily: 'Inter', fontWeight: FontWeight.w600)),
              ),
              // Count badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF3F45C7).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('${filtered.length}',
                  style: const TextStyle(color: Color(0xFF3F45C7), fontSize: 13,
                    fontFamily: 'Inter', fontWeight: FontWeight.w700)),
              ),
            ]),
          ),

          // Search + Filter
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
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: const TextStyle(fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w500),
                    decoration: InputDecoration(
                      hintText: 'Search user or instrument...',
                      hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter'),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); },
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
                onTap: _openFilter,
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: _hasActiveFilters ? const Color(0xFF3F45C7) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Icon(Icons.tune,
                    size: 20,
                    color: _hasActiveFilters ? Colors.white : const Color(0xFF94A3B8)),
                ),
              ),
            ]),
          ),

          // Active filter chips
          if (_hasActiveFilters)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                if (_filterExchange != null) _buildChip(_filterExchange!),
                if (_filterTradingsymbol != null) _buildChip(_filterTradingsymbol!),
                if (_filterUserName != null) _buildChip(_filterUserName!),
              ]),
            ),

          const SizedBox(height: 12),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
                : filtered.isEmpty
                    ? Center(child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 48, color: const Color(0xFF94A3B8).withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text('No open positions',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontFamily: 'Inter')),
                        ],
                      ))
                    : RefreshIndicator(
                        color: const Color(0xFF3F45C7),
                        onRefresh: _fetch,
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildCard(filtered[i]),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3F45C7).withValues(alpha: 0.2)),
      ),
      child: Text(label,
        style: const TextStyle(color: Color(0xFF3F45C7), fontSize: 11,
          fontFamily: 'Inter', fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildCard(Map<String, dynamic> pos) {
    final netQty = (pos['net_qty'] as num?)?.toDouble() ?? 0;
    final side = pos['side'] ?? (netQty > 0 ? 'BUY' : 'SELL');
    final avgBuy = (pos['avg_buy_price'] as num?)?.toDouble() ?? 0;
    final avgSell = (pos['avg_sell_price'] as num?)?.toDouble() ?? 0;
    final totalBuyQty = (pos['total_buy_qty'] as num?)?.toDouble() ?? 0;
    final totalSellQty = (pos['total_sell_qty'] as num?)?.toDouble() ?? 0;

    // Realised P&L: closed portion
    double realisedPnl = 0;
    final closedQty = totalBuyQty < totalSellQty ? totalBuyQty : totalSellQty;
    if (closedQty > 0 && avgBuy > 0 && avgSell > 0) {
      realisedPnl = (avgSell - avgBuy) * closedQty;
    }

    final avgRate = side == 'BUY' ? avgBuy : avgSell;
    final marginUsed = avgRate * netQty.abs();
    final isProfit = realisedPnl >= 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Top row: symbol + P&L badge
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pos['tradingsymbol'] ?? '',
                style: const TextStyle(color: Color(0xFF3F45C7), fontSize: 14,
                  fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: -0.3)),
              const SizedBox(height: 2),
              Row(children: [
                Text(pos['exchange'] ?? '',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11,
                    fontFamily: 'Inter', fontWeight: FontWeight.w500, letterSpacing: 0.5)),
                const Text(' · ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                Text(pos['username'] ?? '',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11,
                    fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                if ((pos['master_username'] ?? '').toString().isNotEmpty) ...[
                  const Text(' · ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(pos['master_username'],
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10,
                        fontFamily: 'Inter', fontWeight: FontWeight.w500)),
                  ),
                ],
              ]),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isProfit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${isProfit ? '+' : ''}${realisedPnl.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.white, fontSize: 12,
                fontFamily: 'Inter', fontWeight: FontWeight.w600),
            ),
          ),
        ]),

        const SizedBox(height: 10),

        // Details grid
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Column(children: [
            Row(children: [
              _gridCell('POSITION', side,
                valueColor: side == 'BUY' ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
              _gridCell('OPEN QTY', netQty.abs().toStringAsFixed(0),
                valueColor: const Color(0xFF3F45C7), showRightBorder: false),
            ]),
            Container(height: 1, color: const Color(0xFFF1F5F9)),
            Row(children: [
              _gridCell('MARGIN USED', marginUsed.toStringAsFixed(2)),
              _gridCell('AVG RATE', avgRate.toStringAsFixed(2), showRightBorder: false),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _gridCell(String label, String value, {Color? valueColor, bool showRightBorder = true}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: showRightBorder
              ? const Border(right: BorderSide(color: Color(0xFFF1F5F9)))
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10,
                fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Text(value,
              style: TextStyle(color: valueColor ?? Colors.black, fontSize: 12,
                fontFamily: 'Inter', fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
