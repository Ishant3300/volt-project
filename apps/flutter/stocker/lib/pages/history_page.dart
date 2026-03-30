import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:stocker/models/trade.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/views/trade_card_view.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'history_filter_sheet.dart';
import 'trade_detail_sheet.dart';

/// Format a Trade's volume as "X LOTS" or "X QTY" using the model's isLotBased getter.
String _tradeVolumeLabel(Trade trade, {bool showSide = false}) {
  final unit = trade.volumeUnit;
  final vol = trade.displayVolume;
  if (showSide) return '${trade.transactionType} · $vol $unit';
  return '$vol $unit';
}

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Master-specific state
  bool _isMaster = false;
  bool _isAdmin = false;
  bool _masterLoading = false;
  List<Trade> _masterTrades = [];
  int _masterPage = 1;
  int _masterTotalPages = 1;
  bool _masterLoadingMore = false;

  // Filter state
  TradeFilterResult? _activeFilters;

  // Search state
  bool _showSearchBar = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Filtered user trades (when filters are active)
  bool _userFilterLoading = false;
  List<Trade>? _filteredUserTrades;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProfile =
          Provider.of<UserProfileProvider>(context, listen: false);
      if (userProfile.isMaster) {
        setState(() => _isMaster = true);
        _fetchMasterTrades();
      } else if (userProfile.isAdmin) {
        setState(() => _isAdmin = true);
        _fetchMasterTrades();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMasterTrades({bool loadMore = false}) async {
    if (loadMore) {
      if (_masterLoadingMore || _masterPage >= _masterTotalPages) return;
      setState(() => _masterLoadingMore = true);
    } else {
      setState(() {
        _masterLoading = true;
        _masterPage = 1;
      });
    }

    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final apiService = ApiService(backendUrl);
      final page = loadMore ? _masterPage + 1 : 1;

      final queryParams = <String>['limit=50', 'page=$page'];
      if (_activeFilters != null) {
        _activeFilters!
            .toQueryParams()
            .forEach((k, v) => queryParams.add('$k=$v'));
      }

      // Both admin and master use /master/trades — backend handles both roles
      final endpoint = '/master/trades?${queryParams.join('&')}';

      final res = await apiService.get(
        endpoint,
        token: token,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? {};
        final List tradesJson = data['trades'] ?? [];
        final trades = tradesJson.map((e) => Trade.fromJson(e)).toList();
        setState(() {
          if (loadMore) {
            _masterTrades.addAll(trades);
          } else {
            _masterTrades = trades;
          }
          _masterPage = data['page'] ?? 1;
          _masterTotalPages = data['pages'] ?? 1;
        });
      }
    } catch (e) {
      debugPrint('Error fetching master trades: $e');
    } finally {
      setState(() {
        _masterLoading = false;
        _masterLoadingMore = false;
      });
    }
  }

  Future<void> _fetchFilteredUserTrades() async {
    if (_activeFilters == null || !_activeFilters!.hasActiveFilters) {
      setState(() => _filteredUserTrades = null);
      return;
    }

    setState(() => _userFilterLoading = true);

    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final userProfile =
          Provider.of<UserProfileProvider>(context, listen: false);
      final userId = userProfile.user?.id;
      if (userId == null || token == null) return;

      final apiService = ApiService(backendUrl);
      final queryParams = <String>['limit=200', 'page=1'];
      _activeFilters!
          .toQueryParams()
          .forEach((k, v) => queryParams.add('$k=$v'));

      final res = await apiService.get(
        '/users/$userId/trades?${queryParams.join('&')}',
        token: token,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final data = body['data'] ?? {};
        final List tradesJson = data['trades'] ?? [];
        setState(() {
          _filteredUserTrades =
              tradesJson.map((e) => Trade.fromJson(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error fetching filtered user trades: $e');
    } finally {
      setState(() => _userFilterLoading = false);
    }
  }

  void _onFiltersApplied(TradeFilterResult? result) {
    setState(() => _activeFilters = result);
    if (_isMaster || _isAdmin) {
      _fetchMasterTrades();
    } else {
      _fetchFilteredUserTrades();
    }
  }

  void _clearFilters() {
    setState(() {
      _activeFilters = null;
      _filteredUserTrades = null;
    });
    if (_isMaster || _isAdmin) {
      _fetchMasterTrades();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasFilters =
        _activeFilters != null && _activeFilters!.hasActiveFilters;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Tabs + filter + search in one row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  // Tab selector (takes available space)
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _buildTabButton(0, 'Trade'),
                          _buildTabButton(1, 'Orders'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Filter button
                  GestureDetector(
                    onTap: () => showPortfolioFilterSheet(
                      context,
                      currentFilters: _activeFilters,
                      onApply: _onFiltersApplied,
                    ),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color:
                            hasFilters ? const Color(0xFF3F45C7) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.tune,
                          color: hasFilters
                              ? Colors.white
                              : const Color(0xFF3F45C7),
                          size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Search button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _showSearchBar = !_showSearchBar;
                        if (!_showSearchBar) {
                          _searchQuery = '';
                          _searchController.clear();
                        }
                      });
                    },
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: _showSearchBar
                            ? const Color(0xFF3F45C7)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(Icons.search,
                          color: _showSearchBar
                              ? Colors.white
                              : const Color(0xFF3F45C7),
                          size: kIconSizeMedium),
                    ),
                  ),
                ],
              ),
            ),

            // Active filter summary bar
            if (hasFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_list,
                          size: kIconSizeSmall, color: Color(0xFF3F45C7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildFilterSummary(),
                          style: const TextStyle(
                            color: Color(0xFF3F45C7),
                            fontSize: kFontSizeSubtitle,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: _clearFilters,
                        child: const Icon(Icons.close,
                            color: Color(0xFF3F45C7), size: kIconSizeDefault),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 4),

            // Search bar (toggled by search icon)
            if (_showSearchBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search,
                          size: 18, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: const TextStyle(
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightRegular,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search by instrument name...',
                            hintStyle: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeBody,
                              fontFamily: 'Inter',
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                            isDense: true,
                          ),
                          onChanged: (val) => setState(
                              () => _searchQuery = val.trim().toUpperCase()),
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.close,
                              size: 18, color: Color(0xFF94A3B8)),
                        ),
                    ],
                  ),
                ),
              ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  (_isMaster || _isAdmin)
                      ? _buildMasterTradesList('completed')
                      : _buildPositionsList(),
                  (_isMaster || _isAdmin)
                      ? _buildMasterTradesList('pending')
                      : _buildOrdersList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}min ago';
      if (diff.inHours < 24) return '${diff.inHours}hr ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('dd MMM').format(dt);
    } catch (_) {
      return '';
    }
  }

  /// Returns a human-readable duration between the opening and closing trade.
  /// e.g. "in 2min", "in 1hr 15min", "in 3d"
  String _tradeDuration(String? openedAt, String closedAt) {
    if (openedAt == null) return _timeAgo(closedAt);
    try {
      final open = DateTime.parse(openedAt);
      final close = DateTime.parse(closedAt);
      final diff = close.difference(open).abs();
      if (diff.inSeconds < 60) return 'in ${diff.inSeconds}s';
      if (diff.inMinutes < 60) return 'in ${diff.inMinutes}min';
      if (diff.inHours < 24) {
        final hrs = diff.inHours;
        final mins = diff.inMinutes % 60;
        return mins > 0 ? 'in ${hrs}hr ${mins}min' : 'in ${hrs}hr';
      }
      final days = diff.inDays;
      final hrs = diff.inHours % 24;
      return hrs > 0 ? 'in ${days}d ${hrs}hr' : 'in ${days}d';
    } catch (_) {
      return _timeAgo(closedAt);
    }
  }

  String _buildFilterSummary() {
    final parts = <String>[];
    if (_activeFilters?.tradingsymbol != null)
      parts.add(_activeFilters!.tradingsymbol!);
    if (_activeFilters?.exchange != null) parts.add(_activeFilters!.exchange!);
    if (_activeFilters?.dateFrom != null || _activeFilters?.dateTo != null)
      parts.add('Date');
    return parts.join(' · ');
  }

  /// Apply local search query filter to a trade list
  List<Trade> _applySearch(List<Trade> trades) {
    if (_searchQuery.isEmpty) return trades;
    return trades
        .where((t) => t.tradingSymbol.toUpperCase().contains(_searchQuery))
        .toList();
  }

  Widget _buildTabButton(int index, String label) {
    final isActive = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF3F45C7) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
                fontSize: kFontSizeBody,
                fontFamily: 'Inter',
                fontWeight: isActive ? kFontWeightSemiBold : kFontWeightMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterTradesList(String statusFilter) {
    if (_masterLoading && _masterTrades.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF3F45C7),
          strokeWidth: 2.5,
        ),
      );
    }

    final filtered = _applySearch(_masterTrades
        .where((t) => t.status.toLowerCase() == statusFilter)
        .toList());

    // Compute per-trade P&L for closing trades
    final perTradePnl = statusFilter == 'completed'
        ? _computePerTradePnl(_masterTrades
            .where((t) => t.status.toLowerCase() == 'completed')
            .toList())
        : <String, _PerTradePnl>{};

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchMasterTrades,
        child: ListView(
          children: [
            const SizedBox(height: 200),
            Center(
              child: Column(
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
                    child: Icon(
                      statusFilter == 'completed'
                          ? Icons.receipt_long
                          : Icons.pending_actions,
                      size: kIconSizeXLarge,
                      color: const Color(0xFFCBD5E1),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    statusFilter == 'completed'
                        ? 'No completed trades from users'
                        : 'No pending orders from users',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchMasterTrades,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
        child: NotificationListener<ScrollNotification>(
          onNotification: (scrollInfo) {
            if (scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200 &&
                !_masterLoadingMore &&
                _masterPage < _masterTotalPages) {
              _fetchMasterTrades(loadMore: true);
            }
            return false;
          },
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: filtered.length + (_masterLoadingMore ? 1 : 0),
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              color: Color(0xFFF1F5F9),
            ),
            itemBuilder: (context, index) {
              if (index >= filtered.length) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              final trade = filtered[index];
              if (statusFilter == 'completed') {
                return _buildCompletedTradeCard(trade,
                    tradePnl: perTradePnl[trade.id]);
              } else {
                return _buildTradeCard(trade);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPositionsList() {
    // If filters are active, show filtered results
    if (_activeFilters != null && _activeFilters!.hasActiveFilters) {
      if (_userFilterLoading) {
        return const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF3F45C7), strokeWidth: 2.5));
      }
      final completedTrades = (_filteredUserTrades ?? [])
          .where((t) => t.status.toLowerCase() == 'completed')
          .toList();
      return _buildTradeListView(completedTrades, 'completed',
          onRefresh: _fetchFilteredUserTrades);
    }

    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF3F45C7),
              strokeWidth: 2.5,
            ),
          );
        }

        final completedTrades = provider.trades
            .where((t) => t.status.toLowerCase() == 'completed')
            .toList();

        return _buildTradeListView(completedTrades, 'completed',
            onRefresh: () => provider.fetchBaseData());
      },
    );
  }

  Widget _buildOrdersList() {
    // If filters are active, show filtered results
    if (_activeFilters != null && _activeFilters!.hasActiveFilters) {
      if (_userFilterLoading) {
        return const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF3F45C7), strokeWidth: 2.5));
      }
      final pendingTrades = (_filteredUserTrades ?? [])
          .where((t) => t.status.toLowerCase() == 'pending')
          .toList();
      return _buildTradeListView(pendingTrades, 'pending',
          onRefresh: _fetchFilteredUserTrades);
    }

    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF3F45C7),
              strokeWidth: 2.5,
            ),
          );
        }

        final pendingTrades = provider.trades
            .where((t) => t.status.toLowerCase() == 'pending')
            .toList();

        return _buildTradeListView(pendingTrades, 'pending');
      },
    );
  }

  Widget _buildTradeListView(List<Trade> trades, String type,
      {Future<void> Function()? onRefresh}) {
    // Apply local search filter
    trades = _applySearch(trades);

    // Compute per-trade P&L for closing trades
    final perTradePnl = type == 'completed'
        ? _computePerTradePnl(trades)
        : <String, _PerTradePnl>{};

    if (trades.isEmpty) {
      final content = Center(
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
              child: Icon(
                type == 'completed'
                    ? Icons.receipt_long
                    : Icons.pending_actions,
                size: kIconSizeXLarge,
                color: const Color(0xFFCBD5E1),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              type == 'completed' ? 'No completed trades' : 'No pending orders',
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: kFontSizeSectionHeader,
                fontFamily: 'Inter',
                fontWeight: kFontWeightSemiBold,
              ),
            ),
          ],
        ),
      );

      if (onRefresh != null) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(children: [const SizedBox(height: 200), content]),
        );
      }
      return content;
    }

    final list = Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: trades.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
        itemBuilder: (context, index) {
          if (type == 'completed') {
            return _buildCompletedTradeCard(trades[index],
                tradePnl: perTradePnl[trades[index].id]);
          } else {
            return _buildTradeCard(trades[index]);
          }
        },
      ),
    );

    if (onRefresh != null) {
      return RefreshIndicator(onRefresh: onRefresh, child: list);
    }
    return list;
  }

  /// Walk completed trades chronologically per instrument.
  /// For every closing trade (SELL when long, BUY when short) compute
  /// the P&L that specific trade realised against the running avg entry price.
  /// Returns a map from trade.id → per-trade P&L info.
  /// Map trade.pnl from backend instead of recalculating (FIFO is handled by server)
  Map<String, _PerTradePnl> _computePerTradePnl(List<Trade> completedTrades) {
    final Map<String, _PerTradePnl> result = {};

    // We still need to track openedAt for duration display using simple FIFO logic locally
    final Map<String, List<Trade>> byInstrument = {};
    for (final t in completedTrades) {
      if (t.status.toLowerCase() != 'completed') continue;
      byInstrument.putIfAbsent(t.instrumentToken, () => []).add(t);
    }

    for (final trades in byInstrument.values) {
      trades.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      int netQty = 0;
      String? openedAt;

      for (final t in trades) {
        final isBuy = t.transactionType.toUpperCase() == 'BUY';
        if (netQty == 0) {
          openedAt = t.createdAt;
          netQty = isBuy ? t.quantity : -t.quantity;
        } else if ((netQty > 0 && isBuy) || (netQty < 0 && !isBuy)) {
          netQty += isBuy ? t.quantity : -t.quantity;
        } else {
          // Closing trade
          result[t.id] =
              _PerTradePnl(pnl: t.pnl, isClosing: true, openedAt: openedAt);
          netQty += isBuy ? t.quantity : -t.quantity;
          if (netQty == 0)
            openedAt = null;
          else if ((netQty > 0 && !isBuy) || (netQty < 0 && isBuy))
            openedAt = t.createdAt;
        }
      }
    }
    return result;
  }

  /// Returns the formatted instrument name for history page display.
  /// Format: "GOLD | 2APR" (uppercase name, pipe, day + abbreviated month)
  String _displayName(Trade trade) {
    final watchlist = Provider.of<WatchlistProvider>(context, listen: false);
    final wItem = watchlist.getByToken(trade.instrumentToken);
    final inst = wItem?.instrument;

    if (inst != null) {
      final base = (inst.name.isNotEmpty ? inst.name : inst.tradingsymbol).toUpperCase();
      if (inst.expiry != null) {
        final day = inst.expiry!.day;
        const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
        final month = months[inst.expiry!.month - 1];
        if (inst.instrumentType == 'CE' || inst.instrumentType == 'PE') {
          return '$base | $day$month ${inst.strike.toInt()} ${inst.instrumentType}';
        }
        return '$base | $day $month';
      }
      return base;
    }
    return trade.tradingSymbol.toUpperCase();
  }

  Widget _buildCompletedTradeCard(Trade trade, {_PerTradePnl? tradePnl}) {
    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final String sideLabel = isBuy ? 'BUY' : 'SELL';

    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm:ss a").format(dt).toUpperCase();
    } catch (_) {}

    // Deals = trade.pnl (FIFO P&L computed by backend: (sell-buy) × qty)
    // Only meaningful for closing trades; 0 for opening trades
    final double deals = trade.pnl;
    final Color dealsColor = deals >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showTradeDetailSheet(context, trade,
          isClosing: tradePnl != null && tradePnl.isClosing),
      child: Column(
        children: [
          // Main content area
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                // Row 1: Instrument name + badge → price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              _displayName(trade),
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: kFontSizeTradeSymbol,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: sideColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              sideLabel,
                              style: TextStyle(
                                color: sideColor,
                                fontSize: kFontSizeTradeBadge,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      trade.price.toStringAsFixed(2),
                      style: TextStyle(
                        color: sideColor,
                        fontSize: kFontSizeTradePrice,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Row 2: Volume → date (only for closed trades)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _tradeVolumeLabel(trade),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: kFontSizeCaption,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                    if ((_isAdmin || _isMaster) || (tradePnl != null && tradePnl.isClosing))
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 11, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeCaption,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Bottom bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(
                top: BorderSide(color: Color(0xFFF1F5F9)),
              ),
            ),
            child: Row(
              children: [
                if (trade.userName != null) ...[
                  const Icon(Icons.person_outline,
                      size: 13, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    trade.userName!,
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: kFontSizeCaption,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                ],
                if (_isAdmin && trade.masterName != null) ...[
                  const SizedBox(width: 14),
                  const Icon(Icons.person_outline,
                      size: 13, color: Color(0xFF94A3B8)),
                  const SizedBox(width: 4),
                  Text(
                    'M:${trade.masterName!}',
                    style: const TextStyle(
                      color: Color(0xFF333333),
                      fontSize: kFontSizeCaption,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                ],
                if (!_isAdmin) ...[
                  if (tradePnl != null && tradePnl.isClosing)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Closed ${_tradeDuration(tradePnl.openedAt, trade.createdAt)}',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: kFontSizeCaption,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    )
                  else ...[
                    const Icon(Icons.access_time, size: 11, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: kFontSizeCaption,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                if (_isAdmin)
                  GestureDetector(
                    onTap: () => _deleteTrade(trade),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFEF4444).withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline,
                              size: 13, color: Color(0xFFEF4444)),
                          SizedBox(width: 4),
                          Text(
                            'DELETE',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontSize: kFontSizeCaption,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (tradePnl != null && tradePnl.isClosing)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: dealsColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Deals: ${deals >= 0 ? '+' : ''}${deals.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: dealsColor,
                        fontSize: kFontSizeCaption,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeCard(Trade trade) {
    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm a").format(dt).toUpperCase();
    } catch (_) {}

    final bool isPending = trade.status.toLowerCase() == 'pending';
    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openTradeCard(trade),
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            // Main content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left side
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Symbol
                        Text(
                          _displayName(trade),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeTradeSymbol,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Metadata row
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: sideColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _tradeVolumeLabel(trade, showSide: true),
                                style: TextStyle(
                                  color: sideColor,
                                  fontSize: kFontSizeTradeBadge,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightSemiBold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (trade.userName != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.person_outline,
                                  size: 11, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  trade.userName!,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: kFontSizeCaption,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightMedium,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_isAdmin && trade.masterName != null) ...[
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              const Icon(Icons.supervisor_account,
                                  size: 11, color: Color(0xFFCBD5E1)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'M: ${trade.masterName!}',
                                  style: const TextStyle(
                                    color: Color(0xFFCBD5E1),
                                    fontSize: kFontSizeCaption,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightMedium,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  // Right side — price
                  Text(
                    trade.price.toStringAsFixed(2),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeTradePrice,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom status bar
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  top: BorderSide(color: Color(0xFFF1F5F9)),
                ),
              ),
              child: Column(
                children: [
                  // Row 1: Date
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 11, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeCaption,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Row 2: Status badge + action buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isPending
                              ? const Color(0xFFFEF3C7)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          trade.status.toUpperCase(),
                          style: TextStyle(
                            color: isPending
                                ? const Color(0xFFB45309)
                                : const Color(0xFFEF4444),
                            fontSize: kFontSizeTradeBadge,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          if (_isAdmin)
                            GestureDetector(
                              onTap: () => _deleteTrade(trade),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: const Color(0xFFEF4444)
                                          .withOpacity(0.4)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.delete_outline,
                                        size: 13, color: Color(0xFFEF4444)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Color(0xFFEF4444),
                                        fontSize: kFontSizeSubtitle,
                                        fontFamily: 'Inter',
                                        fontWeight: kFontWeightSemiBold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_isAdmin && isPending) const SizedBox(width: 8),
                          if (isPending)
                            GestureDetector(
                              onTap: () => _cancelOrder(trade),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 5),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFEF4444).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(PositionAgg position) {
    final isLong = position.netQty > 0;
    final sideLabel = isLong ? 'LONG' : 'SHORT';
    final sideColor =
        isLong ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final avgPrice = isLong ? position.avgBuyPrice : position.avgSellPrice;
    final pnl = position.realised + position.floating;
    final pnlColor =
        pnl >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.transparent,
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      position.tradingsymbol,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizePositionSymbol,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: sideColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            sideLabel,
                            style: TextStyle(
                              color: sideColor,
                              fontSize: kFontSizePositionDetail,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
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
                          '${position.displayVolume} ${position.volumeUnit} @ ${avgPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeCaption,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Right side
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    position.ltp > 0
                        ? position.ltp.toStringAsFixed(2)
                        : avgPrice.toStringAsFixed(2),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizePositionPnl,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        pnl >= 0 ? Icons.north_east : Icons.south_west,
                        size: 12,
                        color: pnlColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          if (position.floating != 0) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    position.exchange,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: kFontSizeCaption,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                  Text(
                    'Floating: ${position.floating >= 0 ? '+' : ''}${position.floating.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: position.floating >= 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      fontSize: kFontSizeCaption,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openTradeCard(Trade trade) {
    final metricsProvider =
        Provider.of<TradeMetricsProvider>(context, listen: false);
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);

    PositionAgg? position;
    try {
      position = metricsProvider.positions.firstWhere(
        (p) => p.instrumentToken == trade.instrumentToken,
      );
    } catch (_) {
      position = null;
    }

    String closeOrderType;
    int closeQuantity;

    if (position != null && position.netQty != 0) {
      closeOrderType = 'Market Execution';
      closeQuantity = position.netQty.abs();
    } else {
      closeOrderType = 'Market Execution';
      closeQuantity = trade.quantity;
    }

    WatchlistItem? existingItem =
        watchlistProvider.getByToken(trade.instrumentToken);

    final WatchlistItem itemToUse;
    if (existingItem != null) {
      itemToUse = existingItem;
    } else {
      final instrument = KiteInstrument(
        id: '',
        instrumentToken: trade.instrumentToken,
        exchangeToken: '',
        tradingsymbol: trade.tradingSymbol,
        name: trade.tradingSymbol,
        rawName: trade.tradingSymbol,
        displayName: trade.tradingSymbol,
        lastPrice: trade.price,
        strike: 0,
        tickSize: 0.05,
        lotSize: 1,
        instrumentType: '',
        segment: '',
        exchange: trade.exchange,
        isActive: true,
        updatedAt: DateTime.now(),
      );

      itemToUse = WatchlistItem(
        id: trade.instrumentToken,
        instrument: instrument,
        currentPrice: trade.price,
        lastUpdated: DateTime.now(),
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TradeCardPage(
          item: itemToUse,
          initialOrderType: closeOrderType,
          initialQuantity: closeQuantity,
        ),
      ),
    );
  }

  Future<void> _deleteTrade(Trade trade) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete Trade',
          style: TextStyle(fontFamily: 'Inter', fontWeight: kFontWeightSemiBold),
        ),
        content: Text(
          'Are you sure you want to permanently delete this ${trade.transactionType} trade for ${trade.tradingSymbol}?',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No',
                style:
                    TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Inter')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Delete',
                style: TextStyle(
                    color: Color(0xFFEF4444),
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightSemiBold)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      if (token == null) throw Exception('Not authenticated');

      final apiService = ApiService(backendUrl);
      final response =
          await apiService.delete('/trade/${trade.id}', token: token);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          if (_isMaster || _isAdmin) {
            await _fetchMasterTrades();
          } else {
            final metricsProvider =
                Provider.of<TradeMetricsProvider>(context, listen: false);
            await metricsProvider.fetchBaseData();
          }
          await Provider.of<UserProfileProvider>(context, listen: false)
              .refreshProfile();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Trade deleted: ${trade.tradingSymbol}'),
                  backgroundColor: const Color(0xFF10B981)),
            );
          }
        } else {
          throw Exception(body['message'] ?? 'Failed to delete trade');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _cancelOrder(Trade trade) async {
    final metricsProvider =
        Provider.of<TradeMetricsProvider>(context, listen: false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Cancel Order',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: kFontWeightSemiBold,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this ${trade.transactionType} order for ${trade.tradingSymbol}?',
          style: const TextStyle(fontFamily: 'Inter'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'No',
              style: TextStyle(
                color: Color(0xFF94A3B8),
                fontFamily: 'Inter',
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontFamily: 'Inter',
                fontWeight: kFontWeightSemiBold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final apiService = ApiService(backendUrl);
      final response = await apiService.put(
        '/trade/${trade.id}/cancel',
        {},
        token: token,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          await metricsProvider.fetchBaseData();
          await Provider.of<UserProfileProvider>(context, listen: false)
              .refreshProfile();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Order cancelled: ${trade.tradingSymbol}'),
                backgroundColor: const Color(0xFF10B981),
              ),
            );
          }
        } else {
          throw Exception(body['message'] ?? 'Failed to cancel order');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}

class _PerTradePnl {
  final double pnl;
  final bool isClosing;
  final String? openedAt; // timestamp of the opening trade
  _PerTradePnl({required this.pnl, required this.isClosing, this.openedAt});
}
