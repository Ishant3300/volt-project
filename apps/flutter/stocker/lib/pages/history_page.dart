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
  bool _masterLoading = false;
  List<Trade> _masterTrades = [];
  int _masterPage = 1;
  int _masterTotalPages = 1;
  bool _masterLoadingMore = false;

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
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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
      final res = await apiService.get(
        '/master/trades?limit=50&page=$page',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar + filter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      child: const Row(
                        children: [
                          Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                          SizedBox(width: 12),
                          Text(
                            'Search & Add',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => showPortfolioFilterSheet(context),
                    child: Container(
                      height: 48,
                      width: 48,
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
                      child: const Icon(Icons.tune,
                          color: Color(0xFF475569), size: 20),
                    ),
                  ),
                ],
              ),
            ),

            // Tab selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 44,
                padding: const EdgeInsets.all(3),
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
                    _buildTabButton(0, 'Trade'),
                    _buildTabButton(1, 'Orders'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _isMaster ? _buildMasterTradesList('completed') : _buildPositionsList(),
                  _isMaster ? _buildMasterTradesList('pending') : _buildOrdersList(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, String label) {
    final isActive = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        child: Container(
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF22547C) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : const Color(0xFF94A3B8),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
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
          color: Color(0xFF22547C),
          strokeWidth: 2.5,
        ),
      );
    }

    final filtered = _masterTrades
        .where((t) => t.status.toLowerCase() == statusFilter)
        .toList();

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
                      size: 32,
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
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
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
                return _buildCompletedTradeCard(trade);
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
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF22547C),
              strokeWidth: 2.5,
            ),
          );
        }

        final completedTrades = provider.trades
            .where((t) => t.status.toLowerCase() == 'completed')
            .toList();

        if (completedTrades.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => provider.fetchBaseData(),
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
                        child: const Icon(Icons.receipt_long,
                            size: 32, color: Color(0xFFCBD5E1)),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'No completed trades',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
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
          onRefresh: () => provider.fetchBaseData(),
          child: Container(
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
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: completedTrades.length,
              separatorBuilder: (context, index) => const Divider(
                height: 1,
                color: Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                return _buildCompletedTradeCard(completedTrades[index]);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrdersList() {
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF22547C),
              strokeWidth: 2.5,
            ),
          );
        }

        final pendingTrades = provider.trades
            .where((t) => t.status.toLowerCase() == 'pending')
            .toList();

        if (pendingTrades.isEmpty) {
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
                  child: const Icon(Icons.pending_actions,
                      size: 32, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 20),
                const Text(
                  'No pending orders',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
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
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: pendingTrades.length,
            separatorBuilder: (context, index) => const Divider(
              height: 1,
              color: Color(0xFFF1F5F9),
            ),
            itemBuilder: (context, index) {
              return _buildTradeCard(pendingTrades[index]);
            },
          ),
        );
      },
    );
  }

  Widget _buildCompletedTradeCard(Trade trade) {
    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final String sideLabel = isBuy ? 'BUY' : 'SELL';

    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm a").format(dt).toUpperCase();
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Symbol + badge
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        trade.tradingSymbol,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
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
                          fontSize: 10,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Metadata row with dot separators
                Row(
                  children: [
                    Text(
                      'Qty ${trade.quantity.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
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
                    Icon(Icons.access_time,
                        size: 11, color: const Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
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
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'PRICE',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 10,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                trade.price.toStringAsFixed(2),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradeCard(Trade trade) {
    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm:ss a").format(dt).toUpperCase();
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
                          trade.tradingSymbol,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
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
                                '${trade.transactionType} · ${trade.quantity.toStringAsFixed(0)} QTY',
                                style: TextStyle(
                                  color: sideColor,
                                  fontSize: 10,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.bold,
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
                                    fontSize: 10,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'PRICE',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        trade.price.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
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
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time,
                          size: 11, color: const Color(0xFF94A3B8)),
                      const SizedBox(width: 3),
                      Text(
                        formattedDate,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 10,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (isPending)
                    GestureDetector(
                      onTap: () => _cancelOrder(trade),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
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
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
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
                              fontSize: 10,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
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
                          '${position.netQty.abs()} QTY @ ${avgPrice.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
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
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.bold,
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
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
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
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Floating: ${position.floating >= 0 ? '+' : ''}${position.floating.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: position.floating >= 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
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
        lastPrice: trade.price,
        strike: 0,
        tickSize: 0.05,
        lotSize: 1,
        instrumentType: '',
        segment: '',
        exchange: trade.exchange,
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
            fontWeight: FontWeight.w600,
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
                fontWeight: FontWeight.w600,
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
