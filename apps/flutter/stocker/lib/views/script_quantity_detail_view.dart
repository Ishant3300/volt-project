import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class ScriptQuantityDetailView extends StatefulWidget {
  const ScriptQuantityDetailView({super.key});
  @override
  State<ScriptQuantityDetailView> createState() => _ScriptQuantityDetailViewState();
}

class _ScriptQuantityDetailViewState extends State<ScriptQuantityDetailView> {
  bool _isLoading = false;
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  // User flow
  List<Map<String, dynamic>> _userExchanges = [];
  String? _selectedExchange;

  // Admin/Master flow
  List<Map<String, dynamic>> _allExchanges = [];
  String? _selectedAdminExchange;
  String? _selectedLot;

  // Sorting
  int _sortCol = 0; // 0=symbol, 1=brkQty, 2=maxQty
  bool _sortAsc = true;

  @override
  void initState() { super.initState(); _fetch(); }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  Future<void> _fetch() async {
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final profile = context.read<UserProfileProvider>();
      if (profile.isUser) {
        await _fetchUserData(token);
      } else {
        await _fetchAllLots(token);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchUserData(String? token) async {
    final res = await ApiService(backendUrl).get('/trade/script-qty-details', token: token);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body['success'] == true && body['data'] != null) {
        setState(() {
          _userExchanges = List<Map<String, dynamic>>.from(body['data']['exchanges'] ?? []);
          if (_userExchanges.isNotEmpty && _selectedExchange == null) {
            _selectedExchange = _userExchanges.first['exchange_name'];
          }
        });
      }
    }
  }

  Future<void> _fetchAllLots(String? token) async {
    final res = await ApiService(backendUrl).get('/trade/script-qty-all-lots', token: token);
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      if (body['success'] == true && body['data'] != null) {
        final exchanges = List<Map<String, dynamic>>.from(body['data']['exchanges'] ?? []);
        setState(() {
          _allExchanges = exchanges;
          if (exchanges.isNotEmpty && _selectedAdminExchange == null) {
            _selectedAdminExchange = exchanges.first['exchange_name'];
            final lots = List<Map<String, dynamic>>.from(exchanges.first['lots'] ?? []);
            if (lots.isNotEmpty) _selectedLot = lots.first['lot_name'];
          }
        });
      }
    }
  }

  // ── Helpers ──
  Map<String, dynamic>? get _currentUserExchange {
    if (_selectedExchange == null) return null;
    return _userExchanges.firstWhere(
      (e) => e['exchange_name'] == _selectedExchange, orElse: () => <String, dynamic>{});
  }

  List<Map<String, dynamic>> get _currentAdminLots {
    if (_selectedAdminExchange == null) return [];
    final ex = _allExchanges.firstWhere(
      (e) => e['exchange_name'] == _selectedAdminExchange, orElse: () => <String, dynamic>{});
    return List<Map<String, dynamic>>.from(ex['lots'] ?? []);
  }

  List<Map<String, dynamic>> get _instruments {
    final profile = context.read<UserProfileProvider>();
    List<Map<String, dynamic>> list;

    if (profile.isUser) {
      final ex = _currentUserExchange;
      if (ex == null) return [];
      list = List<Map<String, dynamic>>.from(ex['instruments'] ?? []);
    } else {
      if (_selectedLot == null) return [];
      final lots = _currentAdminLots;
      final lot = lots.firstWhere((l) => l['lot_name'] == _selectedLot, orElse: () => <String, dynamic>{});
      list = List<Map<String, dynamic>>.from(lot['instruments'] ?? []);
    }

    // Filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((i) => (i['instrument_symbol'] ?? '').toString().toLowerCase().contains(q)).toList();
    }

    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_sortCol) {
        case 1:
          cmp = ((a['break_qty'] as num?) ?? 0).compareTo((b['break_qty'] as num?) ?? 0);
          break;
        case 2:
          cmp = ((a['max_qty'] as num?) ?? 0).compareTo((b['max_qty'] as num?) ?? 0);
          break;
        case 3:
          cmp = ((a['lot_size'] as num?) ?? 0).compareTo((b['lot_size'] as num?) ?? 0);
          break;
        default:
          cmp = (a['instrument_symbol'] ?? '').toString().compareTo((b['instrument_symbol'] ?? '').toString());
      }
      return _sortAsc ? cmp : -cmp;
    });

    return list;
  }

  void _onSort(int col) {
    setState(() {
      if (_sortCol == col) { _sortAsc = !_sortAsc; } else { _sortCol = col; _sortAsc = true; }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileProvider>();
    final isUser = profile.isUser;
    final data = _instruments;

    // Group name for display
    String groupName = '';
    if (isUser) {
      groupName = (_currentUserExchange?['group_name'] ?? '').toString();
    } else if (_selectedLot != null && _selectedLot != '__GLOBAL__') {
      groupName = _selectedLot!;
    }

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
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Script Quantity',
                    style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                  if (!isUser)
                    const Text('All Lots (Read Only)',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                ]),
              ),
            ]),
          ),

          // Exchange + Lot dropdowns (side by side)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              // Exchange dropdown
              Expanded(child: _buildDropdown(
                value: isUser ? _selectedExchange : _selectedAdminExchange,
                items: isUser
                    ? _userExchanges.map((e) => e['exchange_name'] as String).toList()
                    : _allExchanges.map((e) => e['exchange_name'] as String).toList(),
                onChanged: (v) {
                  if (isUser) {
                    setState(() => _selectedExchange = v);
                  } else {
                    setState(() {
                      _selectedAdminExchange = v;
                      final lots = _currentAdminLots;
                      _selectedLot = lots.isNotEmpty ? lots.first['lot_name'] : null;
                    });
                  }
                },
              )),
              // Lot dropdown (admin/master only)
              if (!isUser && _currentAdminLots.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(child: _buildDropdown(
                  value: _selectedLot,
                  items: _currentAdminLots.map((l) {
                    final n = l['lot_name'] as String;
                    return n == '__GLOBAL__' ? '__GLOBAL__' : n;
                  }).toList(),
                  displayMap: {'__GLOBAL__': 'Global Scripts'},
                  onChanged: (v) => setState(() => _selectedLot = v),
                )),
              ],
            ]),
          ),

          const SizedBox(height: 12),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
                decoration: InputDecoration(
                  hintText: 'Search script...',
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: 'Inter'),
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

          const SizedBox(height: 12),

          // Group name banner
          if (groupName.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: Row(children: [
                Text('Group Name :  ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                Text(groupName, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
              ]),
            ),

          // Table header
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: groupName.isEmpty ? const BorderRadius.vertical(top: Radius.circular(16)) : null,
              border: Border(top: BorderSide(color: const Color(0xFFF1F5F9))),
            ),
            child: Row(children: [
              _headerCell('Symbol', 0, flex: 3),
              _headerCell('Brk Qty', 1, flex: 2),
              _headerCell('Max Qty', 2, flex: 2),
              _headerCell('Lot Size', 3, flex: 2),
            ]),
          ),

          // Table body
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
                : data.isEmpty
                    ? Center(child: Text(
                        _getEmptyMessage(isUser),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: 'Inter')))
                    : Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                        ),
                        child: RefreshIndicator(
                          color: const Color(0xFF3F45C7),
                          onRefresh: _fetch,
                          child: ListView.builder(
                            padding: EdgeInsets.zero,
                            itemCount: data.length,
                            itemBuilder: (_, i) => _buildRow(data[i], i),
                          ),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  String _getEmptyMessage(bool isUser) {
    if (isUser) return _userExchanges.isEmpty ? 'No exchanges assigned' : 'No scripts found';
    return _allExchanges.isEmpty ? 'No lots configured' : 'No scripts found';
  }

  Widget _headerCell(String label, int col, {int flex = 1}) {
    final isSorted = _sortCol == col;
    return Expanded(
      flex: flex,
      child: GestureDetector(
        onTap: () => _onSort(col),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.only(left: col == 0 ? 14 : 0),
          child: Row(
            mainAxisAlignment: col == 0 ? MainAxisAlignment.start : MainAxisAlignment.end,
            children: [
              Text(label, style: TextStyle(
                color: isSorted ? const Color(0xFF3F45C7) : const Color(0xFF94A3B8),
                fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
              const SizedBox(width: 2),
              Icon(
                isSorted ? (_sortAsc ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
                size: 13, color: isSorted ? const Color(0xFF3F45C7) : const Color(0xFF94A3B8)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> inst, int index) {
    final symbol = inst['instrument_symbol'] ?? '';
    final brkQty = (inst['break_qty'] as num?)?.toDouble() ?? 0;
    final maxQty = (inst['max_qty'] as num?)?.toDouble() ?? 0;
    final lotSize = (inst['lot_size'] as num?)?.toDouble() ?? 0;
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFAFBFC),
        border: Border(bottom: BorderSide(color: const Color(0xFFF1F5F9), width: 0.5)),
      ),
      child: Row(children: [
        // Symbol
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(symbol,
              style: const TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: -0.3)),
          ),
        ),
        // Breakup Qty
        Expanded(
          flex: 2,
          child: Text(brkQty.toStringAsFixed(1), textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
        ),
        // Max Qty
        Expanded(
          flex: 2,
          child: Text(maxQty.toStringAsFixed(1), textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
        ),
        // Lot Size
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Text(lotSize.toStringAsFixed(1), textAlign: TextAlign.right,
              style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
          ),
        ),
      ]),
    );
  }

  Widget _buildDropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    Map<String, String>? displayMap,
  }) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8)),
          style: const TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold),
          items: items.map((e) => DropdownMenuItem(
            value: e,
            child: Text(displayMap?[e] ?? e, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
