import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/services/kite_service.dart';
import '../utils/contants.dart';

class InstrumentSearchPage extends StatefulWidget {
  const InstrumentSearchPage({super.key});

  @override
  State<InstrumentSearchPage> createState() => _InstrumentSearchPageState();
}

class _InstrumentSearchPageState extends State<InstrumentSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _groupedResults = [];
  bool _isSearching = false;
  String _activeTab = 'ALL';
  Timer? _debounceTimer;
  int _totalResults = 0;
  bool _hasMore = false;
  int _currentPage = 1;
  bool _isLoadingMore = false;
  String _lastQuery = '';
  List<dynamic> _allItems = [];
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, String>> _tabs = [
    {'key': 'ALL', 'label': 'ALL'},
    {'key': 'NFO-FUT', 'label': 'NFO FUT'},
    {'key': 'NFO-OPT', 'label': 'NFO OPT'},
    {'key': 'MCX-FUT', 'label': 'MCX FUT'},
    {'key': 'MCX-OPT', 'label': 'MCX OPT'},
    {'key': 'GLOBAL', 'label': 'GLOBAL'},
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
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _isBrowseMode = false;
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) {
      // If a specific tab is selected (not ALL), browse all instruments in that category
      if (_activeTab != 'ALL') {
        _browseCategoryInstruments();
        return;
      }
      setState(() {
        _groupedResults = [];
        _allItems = [];
        _totalResults = 0;
        _hasMore = false;
        _currentPage = 1;
        _lastQuery = '';
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _currentPage = 1;
      _allItems = [];
      _lastQuery = query;
    });

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);
      final result = await kiteService.smartSearchInstruments(
        query,
        category: _activeTab,
        limit: 10,
        page: 1,
      );

      if (!mounted || _searchController.text != query) return;

      final groups = result['groups'] as List<dynamic>? ?? [];
      final total = result['total'] as int? ?? 0;
      final hasMore = result['hasMore'] as bool? ?? false;

      final items = <dynamic>[];
      for (final g in groups) {
        final gItems = (g as Map)['items'] as List<dynamic>? ?? [];
        items.addAll(gItems);
      }

      setState(() {
        _allItems = items;
        _totalResults = total;
        _hasMore = hasMore;
        _groupedResults = _buildGroupsFromItems(items);
        _isSearching = false;
      });
    } catch (e) {
      log('   ❌ Search error: $e');
      setState(() => _isSearching = false);
    }
  }

  /// Browse all instruments in the selected category (when search is empty).
  bool _isBrowseMode = false;

  Future<void> _browseCategoryInstruments() async {
    setState(() {
      _isSearching = true;
      _currentPage = 1;
      _allItems = [];
      _lastQuery = '';
      _isBrowseMode = true;
    });

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);
      final result = await kiteService.browseInstruments(
        category: _activeTab,
        limit: 100,
        page: 1,
      );

      if (!mounted) return;

      final groups = result['groups'] as List<dynamic>? ?? [];
      final total = result['total'] as int? ?? 0;
      final hasMore = result['hasMore'] as bool? ?? false;

      final items = <dynamic>[];
      for (final g in groups) {
        final gItems = (g as Map)['items'] as List<dynamic>? ?? [];
        items.addAll(gItems);
      }

      setState(() {
        _allItems = items;
        _totalResults = total;
        _hasMore = hasMore;
        _groupedResults = _buildGroupsFromItems(items);
        _isSearching = false;
      });
    } catch (e) {
      log('   ❌ Browse error: $e');
      setState(() => _isSearching = false);
    }
  }

  Future<void> _loadMoreBrowse() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);
      final nextPage = _currentPage + 1;
      final result = await kiteService.browseInstruments(
        category: _activeTab,
        limit: 100,
        page: nextPage,
      );

      if (!mounted) return;

      final groups = result['groups'] as List<dynamic>? ?? [];
      final hasMore = result['hasMore'] as bool? ?? false;

      final newItems = <dynamic>[];
      for (final g in groups) {
        final gItems = (g as Map)['items'] as List<dynamic>? ?? [];
        newItems.addAll(gItems);
      }

      setState(() {
        _currentPage = nextPage;
        _hasMore = hasMore;
        _allItems.addAll(newItems);
        _groupedResults = _buildGroupsFromItems(_allItems);
        _isLoadingMore = false;
      });
    } catch (e) {
      log('   ❌ Load more browse error: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isBrowseMode) {
      return _loadMoreBrowse();
    }
    if (_isLoadingMore || !_hasMore || _lastQuery.isEmpty) return;

    setState(() => _isLoadingMore = true);

    try {
      final kiteService = Provider.of<KiteService>(context, listen: false);
      final nextPage = _currentPage + 1;
      final result = await kiteService.smartSearchInstruments(
        _lastQuery,
        category: _activeTab,
        limit: 10,
        page: nextPage,
      );

      if (!mounted) return;

      final groups = result['groups'] as List<dynamic>? ?? [];
      final hasMore = result['hasMore'] as bool? ?? false;

      final newItems = <dynamic>[];
      for (final g in groups) {
        final gItems = (g as Map)['items'] as List<dynamic>? ?? [];
        newItems.addAll(gItems);
      }

      setState(() {
        _currentPage = nextPage;
        _hasMore = hasMore;
        _allItems.addAll(newItems);
        _groupedResults = _buildGroupsFromItems(_allItems);
        _isLoadingMore = false;
      });
    } catch (e) {
      log('   ❌ Load more error: $e');
      setState(() => _isLoadingMore = false);
    }
  }

  /// Re-group a flat list of items into label-based groups for display
  /// Groups are ordered: Index, Futures, Call Options, Put Options, Other
  List<Map<String, dynamic>> _buildGroupsFromItems(List<dynamic> items) {
    final groups = <String, List<dynamic>>{};
    final groupOrder = [
      'Index',
      'Futures',
      'Call Options (CE)',
      'Put Options (PE)',
      'MCX-OPT',
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
      } else if (type == 'FUT') {
        label = 'Futures';
      } else if (segment == 'MCX-OPT' ||
          (exchange == 'MCX' && (type == 'CE' || type == 'PE'))) {
        label = 'MCX-OPT';
      } else if (type == 'CE') {
        label = 'Call Options (CE)';
      } else if (type == 'PE') {
        label = 'Put Options (PE)';
      } else {
        label = 'Other';
      }
      groups.putIfAbsent(label, () => []);
      groups[label]!.add(item);
    }

    // Return groups in defined order
    final result = <Map<String, dynamic>>[];
    for (final key in groupOrder) {
      if (groups.containsKey(key) && groups[key]!.isNotEmpty) {
        result.add({'label': key, 'items': groups[key]});
      }
    }
    return result;
  }

  void _addToWatchlist(KiteInstrument instrument) {
    // Block in investor mode
    final investorMode =
        Provider.of<InvestorModeProvider>(context, listen: false);
    if (investorMode.isInvestor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Watchlist editing is not available in investor mode'),
            backgroundColor: Color(0xFF64748B)),
      );
      return;
    }

    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);
    if (!watchlistProvider.contains(instrument.instrumentToken)) {
      watchlistProvider.addInstrument(instrument);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${instrument.name.isNotEmpty ? instrument.name : instrument.tradingsymbol} added'),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 1),
        ),
      );
    }
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
                child: Icon(Icons.arrow_back,
                    color: Color(0xFF475569), size: kIconSizeMedium),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                style: const TextStyle(
                  fontSize: kFontSizeBody,
                  color: Color(0xFF0F172A),
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
                decoration: const InputDecoration(
                  hintText: 'Try: NIFTY FUT, BANKNIFTY CE, 22000 PE',
                  hintStyle: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: kFontSizeBody,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightRegular,
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
                  child: Icon(Icons.close,
                      color: Color(0xFF94A3B8), size: kIconSizeDefault),
                ),
              ),
          ],
        ),
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
          _isBrowseMode = false;
        });
        if (_searchController.text.isNotEmpty) {
          _performSearch(_searchController.text);
        } else if (key != 'ALL') {
          _browseCategoryInstruments();
        } else {
          setState(() {
            _groupedResults = [];
            _allItems = [];
            _totalResults = 0;
            _hasMore = false;
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? kBrandPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: kFontSizeSubtitle,
            fontFamily: 'Inter',
            fontWeight: isActive ? kFontWeightSemiBold : kFontWeightMedium,
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
          color: kBrandPrimary,
          strokeWidth: 2.5,
        ),
      );
    }

    if (_searchController.text.isEmpty && !_isBrowseMode) {
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
            itemCount: _groupedResults.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, groupIndex) {
              // Load more indicator at the end
              if (groupIndex == _groupedResults.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: kBrandPrimary, strokeWidth: 2))),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    color: const Color(0xFFF8FAFC),
                    child: Text(
                      label.toUpperCase(),
                      style: const TextStyle(
                        fontSize: kFontSizeCaption,
                        fontWeight: kFontWeightSemiBold,
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
                    const Icon(Icons.search,
                        size: kIconSizeSmall, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 6),
                    Text(
                      _hasMore
                          ? '${_allItems.length} of $_totalResults results'
                          : '$_totalResults results',
                      style: const TextStyle(
                        fontSize: kFontSizeSubtitle,
                        fontWeight: kFontWeightMedium,
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
    final typeColor = _getTypeColor(instrument.instrumentType);

    return Consumer<WatchlistProvider>(
      builder: (context, watchlistProvider, _) {
        final isAdded = watchlistProvider.contains(instrument.instrumentToken);

        return Container(
          padding: const EdgeInsets.all(16),
          color: Colors.transparent,
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
                      : (instrument.isIndex ? 'IDX' : instrument.exchange),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: kFontSizeCaption,
                    fontWeight: kFontWeightSemiBold,
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
                            instrument.userFriendlyName,
                            _searchController.text,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          instrument.tradingsymbol,
                          style: const TextStyle(
                            fontSize: kFontSizeCaption,
                            fontWeight: kFontWeightMedium,
                            color: Color(0xFF94A3B8),
                            fontFamily: 'Inter',
                            letterSpacing: 0.3,
                          ),
                        ),
                        if (instrument.lotSize > 0) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('·',
                                style: TextStyle(
                                    fontSize: kFontSizeCaption,
                                    color: Color(0xFFCBD5E1))),
                          ),
                          Text(
                            'LOT ${instrument.lotSize}',
                            style: const TextStyle(
                              fontSize: kFontSizeCaption,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium,
                            ),
                          ),
                        ],
                        if (instrument.strike > 0) ...[
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('·',
                                style: TextStyle(
                                    fontSize: kFontSizeCaption,
                                    color: Color(0xFFCBD5E1))),
                          ),
                          Text(
                            '${instrument.strike.toInt()}',
                            style: const TextStyle(
                              fontSize: kFontSizeCaption,
                              color: Color(0xFF94A3B8),
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Add / Added indicator
              GestureDetector(
                onTap: isAdded ? null : () => _addToWatchlist(instrument),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAdded
                        ? const Color(0xFF10B981).withOpacity(0.1)
                        : kBrandPrimary.withOpacity(0.1),
                  ),
                  child: Icon(
                    isAdded ? Icons.check : Icons.add,
                    size: kIconSizeDefault,
                    color: isAdded
                        ? const Color(0xFF10B981)
                        : kBrandPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHighlightedText(String text, String query) {
    if (query.isEmpty) {
      return Text(
        text,
        style: const TextStyle(
          fontWeight: kFontWeightSemiBold,
          fontSize: kFontSizeBody,
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
          fontWeight: kFontWeightSemiBold,
          fontSize: kFontSizeBody,
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
          fontWeight: kFontWeightBold,
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
          fontWeight: kFontWeightSemiBold,
          fontSize: kFontSizeBody,
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
            child: const Icon(Icons.search,
                size: kIconSizeXLarge, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Search for instruments',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: kFontSizeSectionHeader,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try: NIFTY FUT, BANKNIFTY CE, 22000 PE',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: kFontSizeBodySmall,
              fontFamily: 'Inter',
              fontWeight: kFontWeightRegular,
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
                size: kIconSizeXLarge, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 20),
          const Text(
            'No results found',
            style: TextStyle(
              color: Color(0xFF475569),
              fontSize: kFontSizeSectionHeader,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try different keywords like:\nNIFTY FUT, BANKNIFTY CE, RELIANCE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: kFontSizeBodySmall,
              fontFamily: 'Inter',
              fontWeight: kFontWeightRegular,
            ),
          ),
        ],
      ),
    );
  }
}
