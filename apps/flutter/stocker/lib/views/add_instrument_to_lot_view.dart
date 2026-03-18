import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/kite_service.dart';
import '../models/kite_instrument.dart';

class AddInstrumentToLotView extends StatefulWidget {
  final String exchange;
  final String lotName;

  // Edit mode parameters (optional)
  final String? existingId;
  final String? existingInstrumentId;
  final String? existingInstrumentSymbol;
  final double? existingMaxQty;
  final double? existingBreakQty;
  final double? existingLotSize;

  const AddInstrumentToLotView({
    super.key,
    required this.exchange,
    required this.lotName,
    this.existingId,
    this.existingInstrumentId,
    this.existingInstrumentSymbol,
    this.existingMaxQty,
    this.existingBreakQty,
    this.existingLotSize,
  });

  bool get isEditMode => existingId != null;

  @override
  State<AddInstrumentToLotView> createState() => _AddInstrumentToLotViewState();
}

class _AddInstrumentToLotViewState extends State<AddInstrumentToLotView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _maxQtyController = TextEditingController();
  final TextEditingController _breakQtyController = TextEditingController();
  final TextEditingController _lotSizeController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _groupedResults = [];
  List<dynamic> _allItems = [];
  KiteInstrument? _selectedInstrument;
  bool _isSearching = false;
  bool _isAdding = false;
  Timer? _debounceTimer;
  int _totalResults = 0;

  static const int _fetchLimit = 200;
  static const int _pageSize = 50;
  int _displayCount = _pageSize;

  static const Map<String, Color> typeColors = {
    'FUT': Color(0xFF3B82F6),
    'CE': Color(0xFF10B981),
    'PE': Color(0xFFEF4444),
    'EQ': Color(0xFF64748B),
    'IDX': Color(0xFF8B5CF6),
  };

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Pre-populate fields if in edit mode
    if (widget.isEditMode) {
      _maxQtyController.text = widget.existingMaxQty?.toStringAsFixed(0) ?? '';
      _breakQtyController.text =
          widget.existingBreakQty?.toStringAsFixed(0) ?? '';
      _lotSizeController.text =
          widget.existingLotSize?.toStringAsFixed(0) ?? '';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.isEditMode) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _maxQtyController.dispose();
    _breakQtyController.dispose();
    _lotSizeController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_displayCount < _allItems.length) {
        setState(() {
          _displayCount =
              (_displayCount + _pageSize).clamp(0, _allItems.length);
          _groupedResults =
              _buildGroupsFromItems(_allItems.take(_displayCount).toList());
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        _groupedResults = [];
        _allItems = [];
        _displayCount = _pageSize;
        _totalResults = 0;
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);

      // Map exchange (now segment) to category for smart search
      String category = 'ALL';
      if (widget.exchange == 'MCX-FUT' || widget.exchange == 'MCX') {
        category = 'MCX-FUT';
      } else if (widget.exchange == 'MCX-OPT') {
        category = 'MCX-OPT';
      } else if (widget.exchange == 'NFO-FUT' || widget.exchange == 'NFO') {
        category = 'NSE-FUT';
      } else if (widget.exchange == 'NFO-OPT') {
        category = 'NSE-OPT';
      } else if (widget.exchange == 'INDICES') {
        category = 'NSEIX';
      } else if (widget.exchange == 'NSE') {
        category =
            'NSE-FUT'; // Default for NSE EQ if needed, or better define a category
      }

      final result = await kiteService.smartSearchInstruments(
        query,
        category: category,
        limit: _fetchLimit,
      );

      if (!mounted || _searchController.text != query) return;

      final groups = result['groups'] as List<dynamic>? ?? [];
      final total = result['total'] as int? ?? 0;

      final allItems = <dynamic>[];
      for (final g in groups) {
        final items = (g as Map)['items'] as List<dynamic>? ?? [];
        allItems.addAll(items);
      }

      setState(() {
        _allItems = allItems;
        _totalResults = total;
        _displayCount = _pageSize.clamp(0, allItems.length);
        _groupedResults =
            _buildGroupsFromItems(allItems.take(_displayCount).toList());
        _isSearching = false;
      });
    } catch (e) {
      log('❌ Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  List<Map<String, dynamic>> _buildGroupsFromItems(List<dynamic> items) {
    final groups = <String, List<dynamic>>{};
    final groupOrder = [
      'Index',
      'NFO Futures',
      'NFO Options',
      'MCX Futures',
      'MCX Options',
      'Equity',
      'Other'
    ];

    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final type = (map['instrument_type'] ?? '').toString();
      final segment = (map['segment'] ?? '').toString();
      final exchange = (map['exchange'] ?? '').toString();
      String label;
      if (segment == 'INDICES' || type == 'IDX') {
        label = 'Index';
      } else if (segment == 'NFO-FUT' || (exchange == 'NFO' && type == 'FUT')) {
        label = 'NFO Futures';
      } else if (segment == 'NFO-OPT' ||
          (exchange == 'NFO' && (type == 'CE' || type == 'PE'))) {
        label = 'NFO Options';
      } else if (segment == 'MCX-FUT' || (exchange == 'MCX' && type == 'FUT')) {
        label = 'MCX Futures';
      } else if (segment == 'MCX-OPT' ||
          (exchange == 'MCX' && (type == 'CE' || type == 'PE'))) {
        label = 'MCX Options';
      } else if (type == 'EQ') {
        label = 'Equity';
      } else {
        label = 'Other';
      }
      groups.putIfAbsent(label, () => []);
      groups[label]!.add(item);
    }

    final result = <Map<String, dynamic>>[];
    for (final key in groupOrder) {
      if (groups.containsKey(key) && groups[key]!.isNotEmpty) {
        result.add({'label': key, 'items': groups[key]});
      }
    }
    return result;
  }

  Color _getTypeColor(String? instrumentType) {
    return typeColors[instrumentType] ?? const Color(0xFF64748B);
  }

  void _selectInstrument(KiteInstrument instrument) {
    setState(() {
      _selectedInstrument = instrument;
      _groupedResults = [];
      _allItems = [];
      _searchController.clear();
      // Pre-fill lot size from instrument
      _lotSizeController.text = instrument.lotSize.toString();
    });
  }

  Future<void> _addInstrument() async {
    // For edit mode without selected instrument, use existing data
    final instrumentId = _selectedInstrument?.instrumentToken.toString() ??
        widget.existingInstrumentId;
    final instrumentSymbol =
        _selectedInstrument?.tradingsymbol ?? widget.existingInstrumentSymbol;

    if (instrumentId == null || instrumentSymbol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select an instrument'),
            backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    final maxQty = double.tryParse(_maxQtyController.text);
    final breakQty = double.tryParse(_breakQtyController.text);
    final lotSize = double.tryParse(_lotSizeController.text);

    if (maxQty == null || breakQty == null || lotSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter valid numbers'),
            backgroundColor: Color(0xFFEF4444)),
      );
      return;
    }

    setState(() => _isAdding = true);

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      http.Response response;

      // Determine exchange name (use segment for MCX instruments)
      final instrumentExchange = _selectedInstrument?.exchange ?? widget.exchange;
      final instrumentSegment = _selectedInstrument?.segment ?? '';
      final exchangeName = instrumentSegment.isNotEmpty &&
              (instrumentSegment.toUpperCase() == 'MCX-FUT' ||
                  instrumentSegment.toUpperCase() == 'MCX-OPT')
          ? instrumentSegment
          : instrumentExchange;

      if (widget.isEditMode) {
        // Update existing instrument
        response = await adminService.updateGroupedQuantity(
          id: widget.existingId!,
          instrumentId: instrumentId,
          instrumentSymbol: instrumentSymbol,
          maxQty: maxQty,
          breakQty: breakQty,
          lotSize: lotSize,
        );
      } else {
        // Create new instrument
        response = await adminService.createGroupedQuantity(
          exchangeName: exchangeName,
          lotName: widget.lotName,
          instrumentId: instrumentId,
          instrumentSymbol: instrumentSymbol,
          maxQty: maxQty,
          breakQty: breakQty,
          lotSize: lotSize,
        );
      }

      setState(() => _isAdding = false);

      final successCode = widget.isEditMode ? 200 : 201;
      if (response.statusCode == successCode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.isEditMode
                  ? 'Instrument updated successfully'
                  : 'Instrument added successfully'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        final data = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(data['message'] ??
                    'Failed to ${widget.isEditMode ? 'update' : 'add'} instrument'),
                backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    } catch (e) {
      setState(() => _isAdding = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // In edit mode, show form directly without search
    final showForm = _selectedInstrument != null || widget.isEditMode;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            if (!showForm) ...[
              _buildSearchBar(),
              const SizedBox(height: 12),
              Expanded(child: _buildSearchResults()),
            ] else ...[
              Expanded(child: _buildSelectedInstrumentForm()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
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
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child:
                  const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.isEditMode ? 'Edit Instrument' : 'Add Instrument',
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600)),
                Text('${widget.exchange} · ${widget.lotName}',
                    style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 12,
                        fontFamily: 'Inter')),
              ],
            ),
          ),
        ],
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
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16, right: 8),
              child: Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF0F172A),
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  hintText: 'Search ${widget.exchange} instruments...',
                  hintStyle: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 14,
                      fontFamily: 'Inter'),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            if (_isSearching)
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF3F45C7))),
              )
            else if (_searchController.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _performSearch('');
                },
                child: const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child:
                  const Icon(Icons.search, size: 32, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 20),
            Text('Search ${widget.exchange} instruments',
                style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text('Try: GOLD, SILVER, CRUDEOIL',
                style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontFamily: 'Inter')),
          ],
        ),
      );
    }

    if (_groupedResults.isEmpty && !_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ],
              ),
              child: const Icon(Icons.search_off,
                  size: 32, color: Color(0xFFCBD5E1)),
            ),
            const SizedBox(height: 20),
            const Text('No results found',
                style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2))
            ],
          ),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _groupedResults.length +
                (_displayCount < _allItems.length ? 1 : 0),
            itemBuilder: (context, groupIndex) {
              if (groupIndex == _groupedResults.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Color(0xFF3F45C7), strokeWidth: 2))),
                );
              }

              final group = _groupedResults[groupIndex];
              final label = group['label'] as String? ?? 'Other';
              final items = group['items'] as List<dynamic>? ?? [];

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
                            letterSpacing: 0.5)),
                  ),
                  ...items.asMap().entries.map((entry) {
                    final isLast = entry.key == items.length - 1;
                    return Column(
                      children: [
                        _buildInstrumentRow(entry.value),
                        if (!isLast)
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      ],
                    );
                  }),
                ],
              );
            },
          ),
        ),
        if (_totalResults > 0)
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2))
                  ],
                ),
                child: Text('$_totalResults results',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                        fontFamily: 'Inter')),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInstrumentRow(dynamic item) {
    final instrument = KiteInstrument.fromJson(Map<String, dynamic>.from(item));
    final typeColor = _getTypeColor(instrument.instrumentType);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectInstrument(instrument),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                instrument.instrumentType.isNotEmpty
                    ? instrument.instrumentType
                    : (instrument.isIndex ? 'IDX' : instrument.exchange),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: typeColor,
                    fontFamily: 'Inter',
                    letterSpacing: 0.3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: _buildHighlight(
                          instrument.userFriendlyName,
                          _searchController.text,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(instrument.tradingsymbol,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500)),
                      if (!instrument.isIndex) ...[
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('·',
                                style: TextStyle(
                                    fontSize: 10, color: Color(0xFFCBD5E1)))),
                        Text('LOT ${instrument.lotSize}',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF94A3B8),
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.add_circle_outline,
                size: 22, color: Color(0xFF3F45C7)),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlight(String text, String query) {
    if (query.isEmpty) {
      return Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
              fontFamily: 'Inter',
              letterSpacing: -0.3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
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
    if (starts.isEmpty) {
      return Text(text,
          style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF0F172A),
              fontFamily: 'Inter',
              letterSpacing: -0.3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis);
    }
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

  Widget _buildSelectedInstrumentForm() {
    // Use selected instrument or existing data for edit mode
    final instrument = _selectedInstrument;
    final isEditWithoutNewSelection = widget.isEditMode && instrument == null;

    // Determine display values
    final displaySymbol = instrument?.tradingsymbol ??
        widget.existingInstrumentSymbol ??
        'Unknown';
    final displayType = instrument?.instrumentType ?? '';
    final displayExpiry = instrument?.expiryDisplay ?? '';
    final displayLotSize =
        instrument?.lotSize ?? widget.existingLotSize?.toInt() ?? 0;
    final typeColor = _getTypeColor(displayType);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Selected instrument card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          displayType.isNotEmpty
                              ? displayType
                              : widget.exchange,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: typeColor,
                              fontFamily: 'Inter')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(displaySymbol,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                  fontFamily: 'Inter')),
                          if (displayExpiry.isNotEmpty)
                            Text(displayExpiry.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF94A3B8),
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    // Only show close button if not in edit mode without new selection
                    if (!isEditWithoutNewSelection)
                      GestureDetector(
                        onTap: () => setState(() => _selectedInstrument = null),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.close,
                              size: 18, color: Color(0xFFEF4444)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Exchange Lot Size',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                              fontFamily: 'Inter')),
                      Text('$displayLotSize',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF3F45C7),
                              fontFamily: 'Inter')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Quantity inputs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Quantity Settings',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF0F172A),
                        fontFamily: 'Inter')),
                const SizedBox(height: 16),
                _buildInputField(
                    'Max Lots', _maxQtyController, 'Maximum lots allowed'),
                const SizedBox(height: 12),
                _buildInputField('Break Lots', _breakQtyController,
                    'Break quantity for orders'),
                const SizedBox(height: 12),
                _buildInputField(
                    'Lot Size', _lotSizeController, 'Quantity per lot'),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Add/Update button
          GestureDetector(
            onTap: _isAdding ? null : _addInstrument,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                color: _isAdding
                    ? const Color(0xFF3F45C7).withValues(alpha: 0.6)
                    : const Color(0xFF3F45C7),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF3F45C7).withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Center(
                child: _isAdding
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(
                        widget.isEditMode
                            ? 'UPDATE INSTRUMENT'
                            : 'ADD INSTRUMENT',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Inter',
                            letterSpacing: 0.5)),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildInputField(
      String label, TextEditingController controller, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
                fontFamily: 'Inter',
                letterSpacing: 0.3)),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0F172A),
                fontFamily: 'Inter'),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFCBD5E1),
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}
