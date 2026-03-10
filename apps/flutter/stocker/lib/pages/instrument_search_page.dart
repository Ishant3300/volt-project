import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/services/kite_service.dart';

class InstrumentSearchPage extends StatefulWidget {
  const InstrumentSearchPage({super.key});

  @override
  State<InstrumentSearchPage> createState() => _InstrumentSearchPageState();
}

class _InstrumentSearchPageState extends State<InstrumentSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _groupedResults = [];
  final Map<String, KiteInstrument> _selectedInstruments = {};
  bool _isSearching = false;
  String _activeTab = 'ALL';
  Timer? _debounceTimer;
  int _totalResults = 0;

  // Pagination: fetch large batch, render incrementally
  static const int _fetchLimit = 200;
  static const int _pageSize = 50;
  List<dynamic> _allItems = []; // flat list of all fetched items
  int _displayCount = _pageSize;
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, String>> _tabs = [
    {'key': 'ALL', 'label': 'ALL'},
    {'key': 'NSE-FUT', 'label': 'NSE FUT'},
    {'key': 'MCX-FUT', 'label': 'MCX FUT'},
    {'key': 'NSE-OPT', 'label': 'CALLPUT'},
    {'key': 'MCX-OPT', 'label': 'MCX OPT'},
    {'key': 'OTHERS', 'label': 'OTHERS'},
  ];

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_displayCount < _allItems.length) {
        setState(() {
          _displayCount = (_displayCount + _pageSize).clamp(0, _allItems.length);
          _groupedResults = _buildGroupsFromItems(_allItems.take(_displayCount).toList());
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

    setState(() {
      _isSearching = true;
    });

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);

      log('🔍 Performing smart search: "$query" (category: $_activeTab)');

      final result = await kiteService.smartSearchInstruments(
        query,
        category: _activeTab,
        limit: _fetchLimit,
      );

      final groups = result['groups'] as List<dynamic>? ?? [];
      final total = result['total'] as int? ?? 0;

      // Flatten all items from all groups for client-side pagination
      final allItems = <dynamic>[];
      for (final g in groups) {
        final items = (g as Map)['items'] as List<dynamic>? ?? [];
        allItems.addAll(items);
      }

      setState(() {
        _allItems = allItems;
        _totalResults = total;
        _displayCount = _pageSize.clamp(0, allItems.length);
        _groupedResults = _buildGroupsFromItems(allItems.take(_displayCount).toList());
        _isSearching = false;
      });

      log('   ✅ Got ${groups.length} groups with $total total results');
    } catch (e) {
      log('   ❌ Search error: $e');
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Search failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Re-group a flat list of items into label-based groups for display
  List<Map<String, dynamic>> _buildGroupsFromItems(List<dynamic> items) {
    final groups = <String, List<dynamic>>{};
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final type = (map['instrument_type'] ?? '').toString();
      final segment = (map['segment'] ?? '').toString();
      String label;
      if (segment == 'INDICES' || type == 'IDX') {
        label = 'Index';
      } else if (type == 'FUT') {
        label = 'Futures';
      } else if (type == 'CE') {
        label = 'Call Options (CE)';
      } else if (type == 'PE') {
        label = 'Put Options (PE)';
      } else if (type == 'EQ') {
        label = 'Equity';
      } else {
        label = 'Other';
      }
      groups.putIfAbsent(label, () => []);
      groups[label]!.add(item);
    }
    return groups.entries.map((e) => {'label': e.key, 'items': e.value}).toList();
  }

  void _saveSelected() {
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);
    int addedCount = 0;

    for (var instrument in _selectedInstruments.values) {
      if (!watchlistProvider.contains(instrument.instrumentToken)) {
        watchlistProvider.addInstrument(instrument);
        addedCount++;
      }
    }

    if (addedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$addedCount instrument(s) added to watchlist'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
    }
    Navigator.pop(context);
  }

  Color _getTypeColor(String? instrumentType) {
    return typeColors[instrumentType] ?? const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            const SizedBox(height: 8),
            _buildFilterTabs(),
            const SizedBox(height: 12),
            Expanded(child: _buildSearchResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 16, right: 8),
                      child:
                          Icon(Icons.arrow_back, color: Color(0xFF475569), size: 20),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF0F172A),
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Try: NIFTY FUT, BANKNIFTY CE, 22000 PE',
                        hintStyle: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _searchController.clear();
                        _performSearch('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(right: 16),
                        child:
                            Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: _selectedInstruments.isEmpty ? null : _saveSelected,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: _selectedInstruments.isEmpty
                    ? const Color(0xFF22547C).withOpacity(0.4)
                    : const Color(0xFF22547C),
                borderRadius: BorderRadius.circular(16),
                boxShadow: _selectedInstruments.isNotEmpty
                    ? [
                        BoxShadow(
                          color: const Color(0xFF22547C).withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  _selectedInstruments.isEmpty
                      ? 'SAVE'
                      : 'SAVE (${_selectedInstruments.length})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            children: _tabs
                .map((tab) => _buildTab(tab['key']!, tab['label']!))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTab(String key, String label) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          _activeTab = key;
        });
        if (_searchController.text.isNotEmpty) {
          _performSearch(_searchController.text);
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF22547C) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'Inter',
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF22547C),
          strokeWidth: 2.5,
        ),
      );
    }

    if (_searchController.text.isEmpty) {
      return _buildEmptyState();
    }

    if (_groupedResults.isEmpty) {
      return _buildNoResultsState();
    }

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: _groupedResults.length + (_displayCount < _allItems.length ? 1 : 0),
            itemBuilder: (context, groupIndex) {
              // Load more indicator at the end
              if (groupIndex == _groupedResults.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF22547C), strokeWidth: 2))),
                );
              }

              final group = _groupedResults[groupIndex];
              final label = group['label'] as String? ?? 'Other';
              final items = group['items'] as List<dynamic>? ?? [];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Group header
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFFF8FAFC),
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF94A3B8),
                        fontFamily: 'Inter',
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  ...items.asMap().entries.map((entry) {
                    final isLast = entry.key == items.length - 1;
                    return Column(
                      children: [
                        _buildInstrumentRow(entry.value),
                        if (!isLast)
                          const Divider(
                            height: 1,
                            color: Color(0xFFF1F5F9),
                          ),
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
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search, size: 14, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      _displayCount < _allItems.length
                          ? '$_displayCount of $_totalResults results'
                          : '$_totalResults results',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF475569),
                        fontFamily: 'Inter',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInstrumentRow(dynamic item) {
    final instrument = KiteInstrument.fromJson(Map<String, dynamic>.from(item));
    final isSelected =
        _selectedInstruments.containsKey(instrument.instrumentToken);
    final typeColor = _getTypeColor(instrument.instrumentType);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          if (isSelected) {
            _selectedInstruments.remove(instrument.instrumentToken);
          } else {
            _selectedInstruments[instrument.instrumentToken] = instrument;
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected ? const Color(0xFFF0F9FF) : Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Type badge
            Container(
              width: 38,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: typeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                instrument.instrumentType.isNotEmpty
                    ? instrument.instrumentType
                    : instrument.exchange,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: typeColor,
                  fontFamily: 'Inter',
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: _buildHighlightedText(
                          instrument.tradingsymbol,
                          _searchController.text,
                        ),
                      ),
                      if (instrument.expiryDisplay.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFFCBD5E1),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          instrument.expiryDisplay.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'Inter',
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        instrument.exchange,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFCBD5E1))),
                      ),
                      Text(
                        'LOT ${instrument.lotSize}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF94A3B8),
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (instrument.strike > 0) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6),
                          child: Text('·',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFFCBD5E1))),
                        ),
                        Text(
                          '₹${instrument.strike.toInt()}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isSelected ? const Color(0xFF22547C) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF22547C)
                      : const Color(0xFFCBD5E1),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Color(0xFF0F172A),
          fontFamily: 'Inter',
          letterSpacing: -0.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final queryTokens = query.toUpperCase().split(RegExp(r'\s+'));
    final textUpper = text.toUpperCase();

    List<int> matchStarts = [];
    List<int> matchEnds = [];

    for (final token in queryTokens) {
      if (token.isEmpty) continue;
      int start = 0;
      while (true) {
        final index = textUpper.indexOf(token, start);
        if (index == -1) break;
        matchStarts.add(index);
        matchEnds.add(index + token.length);
        start = index + 1;
      }
    }

    if (matchStarts.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Color(0xFF0F172A),
          fontFamily: 'Inter',
          letterSpacing: -0.3,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final ranges = <List<int>>[];
    final sortedIndices = List.generate(matchStarts.length, (i) => i)
      ..sort((a, b) => matchStarts[a].compareTo(matchStarts[b]));

    for (final i in sortedIndices) {
      if (ranges.isEmpty || matchStarts[i] > ranges.last[1]) {
        ranges.add([matchStarts[i], matchEnds[i]]);
      } else {
        ranges.last[1] =
            matchEnds[i] > ranges.last[1] ? matchEnds[i] : ranges.last[1];
      }
    }

    final spans = <TextSpan>[];
    int lastEnd = 0;

    for (final range in ranges) {
      if (range[0] > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, range[0])));
      }
      spans.add(TextSpan(
        text: text.substring(range[0], range[1]),
        style: const TextStyle(
          backgroundColor: Color(0xFFFEF08A),
          fontWeight: FontWeight.w700,
        ),
      ));
      lastEnd = range[1];
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Color(0xFF0F172A),
          fontFamily: 'Inter',
          letterSpacing: -0.3,
        ),
        children: spans,
      ),
    );
  }

  Widget _buildEmptyState() {
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
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.search, size: 32, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Search for instruments',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try: NIFTY FUT, BANKNIFTY CE, 22000 PE',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
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
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.search_off,
                size: 32, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No results found',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try different keywords like:\nNIFTY FUT, BANKNIFTY CE, RELIANCE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
