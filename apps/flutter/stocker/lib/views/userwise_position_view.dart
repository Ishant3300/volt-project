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
      final qs = params.isNotEmpty ? '?${params.join('&')}' : '';
      final res = await ApiService(backendUrl).get('/trade/userwise-positions$qs', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          setState(() => _positions = List<Map<String, dynamic>>.from(body['data']));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => UserwisePositionFilterBottomSheet(
        role: _role, initialExchange: _filterExchange,
        initialTradingsymbol: _filterTradingsymbol,
        initialUserId: _filterUserId, initialUserName: _filterUserName,
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

  String _volumeLabel(Map<String, dynamic> pos) {
    final netQty = ((pos['net_qty'] as num?)?.toInt() ?? 0).abs();
    final segment = (pos['segment'] as String? ?? '').toUpperCase();
    final exchange = (pos['exchange'] as String? ?? '').toUpperCase();
    final lotSize = (pos['lot_size'] as num?)?.toInt() ?? 1;
    final bool isLot = segment == 'MCX-FUT' || segment == 'MCX-OPT' || segment == 'NFO-OPT' || (segment.isEmpty && exchange == 'MCX');
    if (isLot && lotSize > 0) return '${(netQty / lotSize).round()}';
    return '$netQty';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium)),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Userwise Open Position', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: kBrandPrimary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                child: Text('${filtered.length}', style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: Container(height: 44,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                child: TextField(controller: _searchCtrl, onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
                  decoration: InputDecoration(hintText: 'Search user or instrument...', hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                    suffixIcon: _searchQuery.isNotEmpty ? GestureDetector(onTap: () { _searchCtrl.clear(); setState(() => _searchQuery = ''); }, child: const Icon(Icons.close, size: 18, color: Color(0xFF94A3B8))) : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12), border: InputBorder.none)),
              )),
              const SizedBox(width: 10),
              GestureDetector(onTap: _openFilter, child: Container(width: 44, height: 44,
                decoration: BoxDecoration(color: _hasActiveFilters ? kBrandPrimary : Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                child: Icon(Icons.tune, size: kIconSizeMedium, color: _hasActiveFilters ? Colors.white : const Color(0xFF94A3B8)))),
            ]),
          ),
          if (_hasActiveFilters)
            Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Wrap(spacing: 8, runSpacing: 6, children: [
                if (_filterExchange != null) _chip(_filterExchange!),
                if (_filterTradingsymbol != null) _chip(_filterTradingsymbol!),
                if (_filterUserName != null) _chip(_filterUserName!),
              ])),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
                : filtered.isEmpty
                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.inbox_outlined, size: 48, color: const Color(0xFF94A3B8).withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        const Text('No open positions', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: kFontFamily))]))
                    : RefreshIndicator(color: kBrandPrimary, onRefresh: _fetch,
                        child: ListView.separated(padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (_, i) => _buildRow(filtered[i]))),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBrandPrimary.withValues(alpha: 0.2))),
      child: Text(label, style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)));
  }

  Widget _buildRow(Map<String, dynamic> pos) {
    final symbol = pos['tradingsymbol'] ?? '';
    final exchange = pos['exchange'] ?? '';
    final username = pos['username'] ?? '';
    final masterUsername = pos['master_username'] ?? '';
    final side = pos['side'] ?? 'BUY';
    final marginUsed = (pos['margin_used'] as num?)?.toDouble() ?? 0;
    final avgRate = (pos['avg_rate'] as num?)?.toDouble() ?? 0;
    final vol = _volumeLabel(pos);
    final sideColor = side == 'BUY' ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final floatingPnl = (pos['floating_pnl'] as num?)?.toDouble() ?? 0;
    final pnlColor = floatingPnl >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Row 1: Symbol + side badge → P&L badge
        Row(children: [
          Expanded(child: Row(children: [
            Flexible(child: Text('$exchange $symbol',
              style: const TextStyle(color: Colors.black, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(color: sideColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(side, style: TextStyle(color: sideColor, fontSize: kFontSizeBadge, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: pnlColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
            child: Text('${floatingPnl >= 0 ? '+' : ''}${floatingPnl.toStringAsFixed(2)}',
              style: TextStyle(color: pnlColor, fontSize: kFontSizeBadge, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
        ]),
        const SizedBox(height: 5),
        // Row 2: 4-column grid — Username | Qty | Avg Rate | Margin
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          child: Row(children: [
            Expanded(child: _gridCell('User', username.isNotEmpty ? (masterUsername.isNotEmpty ? '$username ($masterUsername)' : username) : '--', showRight: true)),
            Expanded(child: _gridCell('Qty', side == 'SELL' ? '-$vol' : vol, valueColor: sideColor, showRight: true)),
            Expanded(child: _gridCell('Avg Rate', avgRate.toStringAsFixed(2), showRight: true)),
            Expanded(child: _gridCell('Margin', marginUsed.toStringAsFixed(2), showRight: false)),
          ]),
        ),
      ]),
    );
  }

  Widget _gridCell(String label, String value, {Color? valueColor, bool showRight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: showRight ? const Border(right: BorderSide(color: Color(0xFFF1F5F9))) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBadge, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
        const SizedBox(height: 1),
        Text(value, style: TextStyle(color: valueColor ?? Colors.black, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}
