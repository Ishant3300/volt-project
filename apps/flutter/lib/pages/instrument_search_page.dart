import 'package:stocker/widgets/nse_ban_chip.dart';
import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/services/kite_service.dart';
import '../utils/contants.dart';
import 'package:stocker/widgets/page_wash.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/views/trade_card_view.dart';

class InstrumentSearchPage extends StatefulWidget {
  /// Segment tab to open on ('ALL', 'NFO-FUT', 'MCX-FUT', 'GLOBAL', …) — the
  /// watchlist opens search on its own open segment.
  final String initialTab;

  const InstrumentSearchPage({super.key, this.initialTab = 'ALL'});

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
    {'key': 'COMEX-FUT', 'label': 'COMEX'},
    {'key': 'GLOBAL', 'label': 'GLOBAL'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (_tabs.any((t) => t['key'] == widget.initialTab)) _activeTab = widget.initialTab;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      // Opened on a segment: list it straight away, like tapping its tab.
      if (_activeTab != 'ALL') _browseCategoryInstruments();
      // Fresh permissions, so a segment an admin just allowed (or removed)
      // shows up here at once.
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      if (profile.isUser) profile.fetchProfile();
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
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      _performSearch(query);
    });
  }

  /// Futures unless options are asked for: "silver" → "silver FUT" (the
  /// server's own FUT alias — futures only, every segment incl. GLOBAL/COMEX/
  /// GIFT); a strike number or call/put/CE/PE/option word → as typed, options
  /// included ("silver 180000 call"). Commas inside a number are dropped
  /// ("180,000"). The NFO OPT / MCX OPT tabs still search as typed.
  String _searchText(String query) {
    if (_activeTab == 'NFO-OPT' || _activeTab == 'MCX-OPT') return query.trim();
    final q = query.replaceAllMapped(RegExp(r'(\d),(?=\d)'), (m) => m[1]!).trim();
    final wantsOptions = RegExp(r'\b\d{3,}\b').hasMatch(q) ||
        RegExp(r'\b(ce|pe|call|put|opt|option|options)\b', caseSensitive: false).hasMatch(q);
    if (wantsOptions || RegExp(r'\bfut(ures?)?\b', caseSensitive: false).hasMatch(q)) return q;
    return '$q FUT';
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
        _searchText(query),
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
      if (mounted) setState(() => _isSearching = false);
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
      if (mounted) setState(() => _isSearching = false);
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
      if (mounted) setState(() => _isLoadingMore = false);
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
        _searchText(_lastQuery),
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
      if (mounted) setState(() => _isLoadingMore = false);
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

    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    for (final item in items) {
      final map = Map<String, dynamic>.from(item as Map);
      final type = (map['instrument_type'] ?? '').toString();
      final segment = (map['segment'] ?? '').toString();
      final exchange = (map['exchange'] ?? '').toString();
      // Only segments this client is allowed (server search already filters;
      // tab browsing doesn't).
      if (!profile.allowsSegment(segment.isNotEmpty ? segment : exchange)) continue;
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

  Future<void> _addToWatchlist(KiteInstrument instrument) async {
    // Investor mode may add scripts to its watchlist (owner, 9 Nov 2026) —
    // orders stay blocked (trade_card_view.dart).
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);
    if (!watchlistProvider.contains(instrument.instrumentToken)) {
      final displayName = instrument.globalName ??
          (instrument.name.isNotEmpty ? instrument.name : instrument.tradingsymbol);
      final added = await watchlistProvider.addInstrument(instrument);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added
              ? '$displayName added'
              : 'Could not add $displayName — try again'),
          backgroundColor:
              added ? kColorBuy : kColorSell,
          duration: Duration(seconds: added ? 1 : 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      body: PageWash(child: SafeArea(
        child: Column(
          children: [
            _buildSearchHeader(),
            const SizedBox(height: 8),
            _buildFilterTabs(),
            const SizedBox(height: 12),
            Expanded(child: _buildSearchResults()),
          ],
        ),
      )),
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
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightRegular,
                ),
                decoration: const InputDecoration(
                  hintText: 'Try: NIFTY FUT, BANKNIFTY CE, 22000 PE',
                  hintStyle: TextStyle(
                    color: kColorTextMuted,
                    fontSize: kFontSizeBody,
                    fontFamily: kFontFamily,
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
                      color: kColorTextMuted, size: kIconSizeDefault),
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
            // A client sees only the segments their account is allowed.
            children: _tabs
                .where((tab) => tab['key'] == 'ALL' ||
                    Provider.of<UserProfileProvider>(context).allowsSegment(tab['key']))
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
            fontFamily: kFontFamily,
            fontWeight: isActive ? kFontWeightSemiBold : kFontWeightMedium,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final wp = Provider.of<WatchlistProvider>(context);
    final query = _searchController.text.trim();
    if (query.isEmpty && !_isBrowseMode && !_isSearching) {
      return _buildEmptyState();
    }
    // Watchlist matches at once (no server wait), then the server's results
    // without repeating them. The previous results stay on screen while a new
    // answer loads (thin bar on top) instead of a blank spinner.
    final local = query.isEmpty ? const <KiteInstrument>[] : _watchlistMatches(wp, query);
    final localTokens = local.map((i) => i.instrumentToken).toSet();
    final sections = <Map<String, dynamic>>[
      if (local.isNotEmpty) {'label': 'In your watchlist', 'instruments': local},
      for (final g in _groupedResults)
        {
          'label': g['label'] as String? ?? 'Other',
          'instruments': ((g['items'] as List<dynamic>?) ?? const [])
              .map((it) => KiteInstrument.fromJson(Map<String, dynamic>.from(it)))
              .where((i) => !localTokens.contains(i.instrumentToken))
              .toList(),
        },
    ].where((sec) => (sec['instruments'] as List).isNotEmpty).toList();

    if (sections.isEmpty) {
      if (_isSearching) {
        return const Center(
          child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5),
        );
      }
      if (query.isEmpty && !_isBrowseMode) return _buildEmptyState();
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
            itemCount: sections.length + (_isLoadingMore ? 1 : 0),
            itemBuilder: (context, groupIndex) {
              // Load more indicator at the end
              if (groupIndex == sections.length) {
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

              final group = sections[groupIndex];
              final label = group['label'] as String;
              final items = group['instruments'] as List<KiteInstrument>;

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
                        color: kColorTextMuted,
                        fontFamily: kFontFamily,
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
        if (_isSearching)
          const Positioned(
            top: 0,
            left: 28,
            right: 28,
            child: LinearProgressIndicator(minHeight: 2, color: kBrandPrimary, backgroundColor: Colors.transparent),
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
                        size: kIconSizeSmall, color: kColorTextMuted),
                    const SizedBox(width: 6),
                    Text(
                      _hasMore
                          ? '${_allItems.length} of $_totalResults results'
                          : '$_totalResults results',
                      style: const TextStyle(
                        fontSize: kFontSizeSubtitle,
                        fontWeight: kFontWeightMedium,
                        color: Color(0xFF475569),
                        fontFamily: kFontFamily,
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

  static const List<String> _monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const Map<String, Color> _typeTextColours = {'FUT': kBrandPrimary, 'CE': Color(0xFF16A34A), 'PE': Color(0xFFD92D20)};

  /// "RELIANCE", "RELIANCE 1200 CE" — the expiry goes in its own part.
  String _rowName(KiteInstrument i) {
    // GLOBAL / COMEX (YMZ6): "DOW JONES 30" — the date follows in its own part.
    final global = i.globalName;
    if (global != null) {
      final date = i.shortExpiryDisplay;
      return date.isNotEmpty && global.endsWith(' $date')
          ? global.substring(0, global.length - date.length - 1)
          : global;
    }
    final t = i.instrumentType;
    final base = i.name.isNotEmpty ? i.name : i.tradingsymbol;
    if ((t == 'CE' || t == 'PE') && i.strike > 0) {
      final k = i.strike == i.strike.roundToDouble() ? i.strike.toInt().toString() : i.strike.toString();
      return '$base $k $t';
    }
    if (i.expiry == null) return i.userFriendlyName;
    return base;
  }

  String _shortDate(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.day} ${_monthsShort[l.month - 1]}';
  }

  /// Order window for a script — the watchlist's own row if it is there,
  /// otherwise a temporary one (as the option chain does); a script not in
  /// the watchlist is added once an order goes through. [side] 'BUY'/'SELL'
  /// opens it on that side only (B / S buttons).
  void _openTicket(KiteInstrument instrument, {String? side}) {
    final wp = Provider.of<WatchlistProvider>(context, listen: false);
    final existing = wp.getByToken(instrument.instrumentToken);
    final item = existing ??
        WatchlistItem(
          id: 'search_${instrument.instrumentToken}',
          instrument: instrument,
          currentPrice: instrument.lastPrice > 0 ? instrument.lastPrice : null,
        );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TradeCardPage(
          item: item,
          forceSide: side,
          addToWatchlistOnOrder: existing == null,
        ),
      ),
    );
  }

  /// Watchlist scripts matching what is typed — shown at once, before the
  /// server answers (every word must appear; CALL/PUT read as CE/PE).
  List<KiteInstrument> _watchlistMatches(WatchlistProvider wp, String query) {
    final words = query
        .toUpperCase()
        .replaceAll(',', '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && w != 'FUT' && w != 'FUTURES')
        .map((w) => w == 'CALL' ? 'CE' : w == 'PUT' ? 'PE' : w)
        .toList();
    if (words.isEmpty) return const [];
    final out = <KiteInstrument>[];
    for (final w in wp.items) {
      final inst = w.instrument;
      if (_activeTab != 'ALL' && UserProfileProvider.normalizeSegment(inst.segment) != _activeTab) continue;
      final hay = '${inst.name} ${inst.tradingsymbol} ${inst.userFriendlyName}'.toUpperCase();
      if (words.every(hay.contains)) out.add(inst);
      if (out.length >= 6) break;
    }
    return out;
  }

  Widget _quickButton(String label, Color fg, Color bg, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Text(label,
            style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: kFontFamily)),
      ),
    );
  }

  /// One result: name (+ strike/type) and short expiry on one line, type ·
  /// lot · last price under it; B / S open the order window on that side, +
  /// adds only (✓ = already in the watchlist). Tapping the name opens it too.
  Widget _buildInstrumentRow(KiteInstrument instrument) {
    final typeLabel = instrument.instrumentType.isNotEmpty
        ? instrument.instrumentType
        : (instrument.isIndex ? 'IDX' : instrument.exchange);
    final typeColour = _typeTextColours[instrument.instrumentType] ?? const Color(0xFF64748B);
    final date = _shortDate(instrument.expiry);
    const capStyle = TextStyle(
      fontSize: kFontSizeCaption,
      color: kColorTextMuted,
      fontFamily: kFontFamily,
      fontWeight: kFontWeightMedium,
    );

    return Consumer<WatchlistProvider>(
      builder: (context, watchlistProvider, _) {
        final isAdded = watchlistProvider.contains(instrument.instrumentToken);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openTicket(instrument),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(child: _buildHighlightedText(_rowName(instrument), _searchController.text)),
                          if (date.isNotEmpty) ...[
                            const SizedBox(width: 5),
                            Text(date,
                                style: const TextStyle(
                                  fontSize: kFontSizeBody,
                                  color: Color(0xFF5B6478),
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightMedium,
                                )),
                          ],
                          if (instrument.nseBanned) const NseBanChip(),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: typeLabel,
                              style: TextStyle(
                                  color: typeColour,
                                  fontSize: kFontSizeCaption,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightSemiBold)),
                          if (instrument.lotSize > 0) TextSpan(text: '  ·  LOT ${instrument.lotSize}', style: capStyle),
                          if (instrument.lastPrice > 0)
                            TextSpan(text: '  ·  ${instrument.lastPrice.toStringAsFixed(2)}', style: capStyle),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _quickButton('B', const Color(0xFF2E6BE5), const Color(0xFFEAF1FE),
                  () => _openTicket(instrument, side: 'BUY')),
              const SizedBox(width: 6),
              _quickButton('S', const Color(0xFFD92D20), const Color(0xFFFDECEA),
                  () => _openTicket(instrument, side: 'SELL')),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isAdded ? null : () => _addToWatchlist(instrument),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isAdded ? const Color(0xFFECFDF3) : Colors.white,
                    border: isAdded ? null : Border.all(color: const Color(0xFFCFDDFB), width: 1.5),
                  ),
                  child: Icon(
                    isAdded ? Icons.check : Icons.add,
                    size: 17,
                    color: isAdded ? const Color(0xFF16A34A) : kBrandPrimary,
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
          fontFamily: kFontFamily,
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
          fontFamily: kFontFamily,
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
          fontFamily: kFontFamily,
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
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try: NIFTY, GOLD, RELIANCE 1200 CE',
            style: TextStyle(
              color: kColorTextMuted,
              fontSize: kFontSizeBodySmall,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightRegular,
            ),
          ),
          const SizedBox(height: 18),
          // One tap to search a popular script.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final name in const ['NIFTY', 'BANKNIFTY', 'GOLD', 'SILVER', 'CRUDEOIL', 'NATURALGAS'])
                GestureDetector(
                  onTap: () {
                    _searchController.text = name;
                    _searchController.selection = TextSelection.collapsed(offset: name.length);
                    _onSearchChanged(name);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE1E6F2)),
                    ),
                    child: Text(name,
                        style: const TextStyle(
                          color: kBrandPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: kFontFamily,
                        )),
                  ),
                ),
            ],
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
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try different keywords like:\nNIFTY FUT, BANKNIFTY CE, RELIANCE',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: kColorTextMuted,
              fontSize: kFontSizeBodySmall,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightRegular,
            ),
          ),
        ],
      ),
    );
  }
}
