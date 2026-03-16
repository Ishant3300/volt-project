import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/kite_service.dart';
import '../models/kite_instrument.dart';

class CreateBrokerageView extends StatefulWidget {
  const CreateBrokerageView({super.key});
  @override
  State<CreateBrokerageView> createState() => _CreateBrokerageViewState();
}

class _CreateBrokerageViewState extends State<CreateBrokerageView> {
  String _selectedExchange = 'ALL';
  String _selectedType = 'TURNOVER WISE';
  final _exchanges = [
    'ALL',
    'NFO-FUT',
    'NFO-OPT',
    'MCX-FUT',
    'MCX-OPT',
    'GLOBAL',
    'SGX'
  ];
  final _types = ['TURNOVER WISE', 'LOT WISE'];

  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  List<dynamic> _allItems = [];
  List<Map<String, dynamic>> _groupedResults = [];
  int _displayCount = 50;
  int _totalResults = 0;
  bool _isSearching = false;
  final _scrollCtrl = ScrollController();

  static const Map<String, Color> _typeColors = {
    'FUT': Color(0xFF3B82F6),
    'CE': Color(0xFF10B981),
    'PE': Color(0xFFEF4444),
    'EQ': Color(0xFF64748B),
    'IDX': Color(0xFF8B5CF6),
  };

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      if (_displayCount < _allItems.length) {
        setState(() {
          _displayCount = (_displayCount + 50).clamp(0, _allItems.length);
          _groupedResults =
              _buildGroups(_allItems.take(_displayCount).toList());
        });
      }
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() {
        _allItems = [];
        _groupedResults = [];
        _totalResults = 0;
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    try {
      final kite = Provider.of<KiteService>(context, listen: false);
      final result = await kite.smartSearchInstruments(q,
          category: _selectedExchange == 'ALL' ? 'ALL' : _selectedExchange,
          limit: 200);

      if (!mounted || _searchCtrl.text != q) return;

      final groups = result['groups'] as List<dynamic>? ?? [];
      final total = result['total'] as int? ?? 0;
      final all = <dynamic>[];
      for (final g in groups) {
        all.addAll((g as Map)['items'] as List<dynamic>? ?? []);
      }
      setState(() {
        _allItems = all;
        _totalResults = total;
        _displayCount = 50.clamp(0, all.length);
        _groupedResults = _buildGroups(all.take(_displayCount).toList());
        _isSearching = false;
      });
    } catch (e) {
      log('Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  List<Map<String, dynamic>> _buildGroups(List<dynamic> items) {
    final map = <String, List<dynamic>>{};
    final groupOrder = [
      'Index',
      'Futures',
      'Call Options (CE)',
      'Put Options (PE)',
      'MCX-OPT',
      'Other'
    ];

    for (final item in items) {
      final m = Map<String, dynamic>.from(item as Map);
      final type = (m['instrument_type'] ?? '').toString();
      final seg = (m['segment'] ?? '').toString();
      final exchange = (m['exchange'] ?? '').toString();
      String label;
      if (seg == 'INDICES' || type == 'IDX')
        label = 'Index';
      else if (type == 'FUT')
        label = 'Futures';
      else if (seg == 'MCX-OPT' ||
          (exchange == 'MCX' && (type == 'CE' || type == 'PE')))
        label = 'MCX-OPT';
      else if (type == 'CE')
        label = 'Call Options (CE)';
      else if (type == 'PE')
        label = 'Put Options (PE)';
      else
        label = 'Other';
      map.putIfAbsent(label, () => []).add(item);
    }

    final result = <Map<String, dynamic>>[];
    for (final key in groupOrder) {
      if (map.containsKey(key) && map[key]!.isNotEmpty) {
        result.add({'label': key, 'items': map[key]});
      }
    }
    return result;
  }

  void _showAddDialog(KiteInstrument inst) {
    final valueCtrl = TextEditingController();
    String localType = _selectedType;
    bool adding = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) => AlertDialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('Add Brokerage',
                    style: TextStyle(
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        fontSize: 16)),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inst.tradingsymbol,
                          style: const TextStyle(
                              color: Color(0xFF22547C),
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3)),
                      const SizedBox(height: 14),
                      _dialogDropdown(
                          localType, _types, (v) => setD(() => localType = v!)),
                      const SizedBox(height: 12),
                      _dialogField(valueCtrl, 'Brokerage value'),
                    ]),
                actions: [
                  TextButton(
                      onPressed: adding ? null : () => Navigator.pop(ctx),
                      child: const Text('Cancel',
                          style: TextStyle(
                              color: Color(0xFF94A3B8), fontFamily: 'Inter'))),
                  GestureDetector(
                    onTap: adding
                        ? null
                        : () async {
                            final v = double.tryParse(valueCtrl.text);
                            if (v == null || v <= 0) return;
                            setD(() => adding = true);
                            try {
                              final apiService =
                                  Provider.of<ApiService>(ctx, listen: false);
                              final r = await AdminService(apiService)
                                  .createBrokerageSettings(
                                      type: localType,
                                      exchangeName: inst.exchange,
                                      scriptName: inst.tradingsymbol,
                                      brkValue: v);
                              setD(() => adding = false);
                              if (r.statusCode == 201) {
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text('Created'),
                                          backgroundColor: Color(0xFF10B981)));
                              } else {
                                final d = jsonDecode(r.body);
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text(d['message'] ?? 'Failed'),
                                          backgroundColor:
                                              const Color(0xFFEF4444)));
                              }
                            } catch (e) {
                              setD(() => adding = false);
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                          color: const Color(0xFF22547C),
                          borderRadius: BorderRadius.circular(10)),
                      child: adding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Add',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                    ),
                  ),
                ],
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
          child: Column(children: [
        _buildHeader(),
        const SizedBox(height: 8),
        _buildExchangeTabs(),
        const SizedBox(height: 12),
        _buildSearchBar(),
        const SizedBox(height: 12),
        Expanded(child: _buildResults()),
      ])),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]),
              child:
                  const Icon(Icons.arrow_back, color: Colors.black, size: 20)),
        ),
        const SizedBox(width: 12),
        const Text('Create Brokerage',
            style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildExchangeTabs() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _exchanges.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final ex = _exchanges[i];
          final sel = ex == _selectedExchange;
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedExchange = ex;
              });
              if (_searchCtrl.text.isNotEmpty) _search(_searchCtrl.text);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: sel ? const Color(0xFF22547C) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      sel ? null : Border.all(color: const Color(0xFFE2E8F0))),
              child: Text(ex,
                  style: TextStyle(
                      color: sel ? Colors.white : const Color(0xFF64748B),
                      fontSize: 13,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          const Padding(
              padding: EdgeInsets.only(left: 16, right: 8),
              child: Icon(Icons.search, color: Color(0xFF94A3B8), size: 20)),
          Expanded(
              child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400),
            decoration: const InputDecoration(
                hintText: 'Search instruments...',
                hintStyle: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontFamily: 'Inter'),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14)),
            onChanged: _onSearchChanged,
          )),
          if (_isSearching)
            const Padding(
                padding: EdgeInsets.only(right: 14),
                child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF22547C))))
          else if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                _search('');
              },
              child: const Padding(
                  padding: EdgeInsets.only(right: 14),
                  child: Icon(Icons.close, color: Color(0xFF94A3B8), size: 18)),
            ),
        ]),
      ),
    );
  }

  Widget _buildResults() {
    if (_searchCtrl.text.isEmpty) {
      return const Center(
          child: Text('Search for an instrument to add',
              style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontFamily: 'Inter')));
    }
    if (_isSearching && _groupedResults.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(
              color: Color(0xFF22547C), strokeWidth: 2.5));
    }
    if (_groupedResults.isEmpty) {
      return const Center(
          child: Text('No results found',
              style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontFamily: 'Inter')));
    }
    return Stack(children: [
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2))
            ]),
        child: ListView.builder(
          controller: _scrollCtrl,
          padding: const EdgeInsets.only(bottom: 60),
          itemCount: _groupedResults.length +
              (_displayCount < _allItems.length ? 1 : 0),
          itemBuilder: (ctx, gi) {
            if (gi == _groupedResults.length) {
              return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Color(0xFF22547C), strokeWidth: 2))));
            }
            final group = _groupedResults[gi];
            final label = group['label'] as String;
            final items = group['items'] as List<dynamic>;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      color: const Color(0xFFF8FAFC),
                      child: Text(label.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'Inter',
                              letterSpacing: 0.5))),
                  ...items.asMap().entries.map((e) => Column(children: [
                        _buildRow(e.value),
                        if (e.key < items.length - 1)
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ])),
                ]);
          },
        ),
      ),
      if (_totalResults > 0)
        Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Center(
                child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ]),
              child: Text(
                  _displayCount < _allItems.length
                      ? '$_displayCount of $_totalResults results'
                      : '$_totalResults results',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF475569),
                      fontFamily: 'Inter')),
            ))),
    ]);
  }

  Widget _buildRow(dynamic item) {
    final inst =
        KiteInstrument.fromJson(Map<String, dynamic>.from(item as Map));
    final typeColor =
        _typeColors[inst.instrumentType] ?? const Color(0xFF64748B);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showAddDialog(inst),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Container(
              width: 38,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                  inst.instrumentType.isNotEmpty
                      ? inst.instrumentType
                      : inst.exchange,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: typeColor,
                      fontFamily: 'Inter',
                      letterSpacing: 0.3))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _buildHighlight(inst.userFriendlyName, _searchCtrl.text),
                const SizedBox(height: 3),
                Row(children: [
                  Text(inst.tradingsymbol,
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500)),
                  const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 5),
                      child: Text('·',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFFCBD5E1)))),
                  Text('LOT ${inst.lotSize}',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500)),
                ]),
              ])),
          const Icon(Icons.add_circle_outline,
              size: 20, color: Color(0xFF22547C)),
        ]),
      ),
    );
  }

  Widget _buildHighlight(String text, String query) {
    if (query.isEmpty)
      return Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
              fontFamily: 'Inter',
              letterSpacing: -0.3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    final tokens = query.toUpperCase().split(RegExp(r'\s+'));
    final upper = text.toUpperCase();
    final starts = <int>[], ends = <int>[];
    for (final t in tokens) {
      if (t.isEmpty) continue;
      int s = 0;
      while (true) {
        final i = upper.indexOf(t, s);
        if (i == -1) break;
        starts.add(i);
        ends.add(i + t.length);
        s = i + 1;
      }
    }
    if (starts.isEmpty)
      return Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
              fontFamily: 'Inter',
              letterSpacing: -0.3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    final ranges = <List<int>>[];
    final sorted = List.generate(starts.length, (i) => i)
      ..sort((a, b) => starts[a].compareTo(starts[b]));
    for (final i in sorted) {
      if (ranges.isEmpty || starts[i] > ranges.last[1])
        ranges.add([starts[i], ends[i]]);
      else if (ends[i] > ranges.last[1]) ranges.last[1] = ends[i];
    }
    final spans = <TextSpan>[];
    int last = 0;
    for (final r in ranges) {
      if (r[0] > last) spans.add(TextSpan(text: text.substring(last, r[0])));
      spans.add(TextSpan(
          text: text.substring(r[0], r[1]),
          style: const TextStyle(
              backgroundColor: Color(0xFFFEF08A),
              fontWeight: FontWeight.w700)));
      last = r[1];
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Color(0xFF0F172A),
                fontFamily: 'Inter',
                letterSpacing: -0.3),
            children: spans));
  }

  Widget _dialogDropdown(
      String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0))),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down,
                    size: 18, color: Color(0xFF94A3B8)),
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500),
                items: items
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged: onChanged)));
  }

  Widget _dialogField(TextEditingController ctrl, String hint) {
    return TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(
            fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w500),
        decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
                color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF22547C), width: 1.5))));
  }
}
