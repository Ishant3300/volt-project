import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:stocker/models/trade.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
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
  bool _isSelectionMode = false;
  final Set<String> _selectedTradeIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        // Exit selection mode when switching tabs
        _isSelectionMode = false;
        _selectedTradeIds.clear();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: _isSelectionMode
          ? AppBar(
              backgroundColor: const Color(0xFF22547C),
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedTradeIds.clear();
                  });
                },
              ),
              title: const Text(
                'Select Trades to Square Off',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar
            Container(
              margin: const EdgeInsets.all(16),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 10),
                  const Text(
                    'Search & Add',
                    style: TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      showPortfolioFilterSheet(context);
                    },
                    child:
                        const Icon(Icons.filter_list, color: Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ),

            // Tab selector
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 42,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _tabController.index == 0
                              ? const Color(0xFF22547C)
                              : Colors.transparent,
                          border: Border.all(
                              width: 1, color: const Color(0xFF22547C)),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Trade',
                            style: TextStyle(
                              color: _tabController.index == 0
                                  ? Colors.white
                                  : const Color(0xFF333333),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(1),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _tabController.index == 1
                              ? const Color(0xFF22547C)
                              : Colors.transparent,
                          border: Border.all(
                              width: 1, color: const Color(0xFF22547C)),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Orders',
                            style: TextStyle(
                              color: _tabController.index == 1
                                  ? Colors.white
                                  : const Color(0xFF333333),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPositionsList(),
                  _buildOrdersList(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0 && !_isSelectionMode
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _isSelectionMode = true;
                });
              },
              backgroundColor: const Color(0xFF22547C),
              icon: const Icon(Icons.check_box, color: Colors.white),
              label: const Text(
                'Square Off',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }

  /// Trade tab: shows individual completed trades
  Widget _buildPositionsList() {
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Show all completed trades (not aggregated)
        final completedTrades = provider.trades
            .where((t) => t.status.toLowerCase() == 'completed')
            .toList();

        if (completedTrades.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => provider.fetchBaseData(),
            child: ListView(
              children: const [
                SizedBox(height: 200),
                Center(
                  child: Text(
                    'No completed trades.',
                    style: TextStyle(
                      color: Color(0xFF8E8E93),
                      fontSize: 16,
                      fontFamily: 'Inter',
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.fetchBaseData(),
          child: Column(
            children: [
              // Square Off button bar
              if (_isSelectionMode)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF22547C),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_selectedTradeIds.length} selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setState(() {
                                if (_selectedTradeIds.length == completedTrades.length) {
                                  _selectedTradeIds.clear();
                                } else {
                                  _selectedTradeIds.clear();
                                  _selectedTradeIds.addAll(completedTrades.map((t) => t.id));
                                }
                              });
                            },
                            child: Text(
                              _selectedTradeIds.length == completedTrades.length
                                  ? 'Deselect All'
                                  : 'Select All',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _selectedTradeIds.isEmpty
                                ? null
                                : () => _squareOffSelected(completedTrades),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF3B30),
                              disabledBackgroundColor: const Color(0xFF8E8E93),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            child: const Text(
                              'Square Off',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: completedTrades.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final trade = completedTrades[index];
                      final isSelected = _selectedTradeIds.contains(trade.id);
                      return _buildCompletedTradeCard(trade, isSelected);
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Orders tab: shows pending/cancelled/rejected trades
  Widget _buildOrdersList() {
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final pendingTrades = provider.trades
            .where((t) => t.status.toLowerCase() == 'pending')
            .toList();

        if (pendingTrades.isEmpty) {
          return const Center(
            child: Text(
              'No pending orders.',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 16,
                fontFamily: 'Inter',
              ),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            itemCount: pendingTrades.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final trade = pendingTrades[index];
              return _buildTradeCard(trade);
            },
          ),
        );
      },
    );
  }

  Widget _buildCompletedTradeCard(Trade trade, bool isSelected) {
    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
    final String sideLabel = isBuy ? 'BUY' : 'SELL';

    // Get current market price from watchlist provider
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);
    final item = watchlistProvider.getByToken(trade.instrumentToken);
    final currentPrice = item?.currentPrice ?? trade.price;

    // Calculate P&L (simplified - actual P&L would need position context)
    // For now, show difference between current price and trade price
    double pnl = 0;
    if (isBuy) {
      pnl = (currentPrice - trade.price) * trade.quantity;
    } else {
      pnl = (trade.price - currentPrice) * trade.quantity;
    }

    return GestureDetector(
      onTap: _isSelectionMode
          ? () {
              setState(() {
                if (isSelected) {
                  _selectedTradeIds.remove(trade.id);
                } else {
                  _selectedTradeIds.add(trade.id);
                }
              });
            }
          : null,
      onLongPress: () {
        setState(() {
          _isSelectionMode = true;
          _selectedTradeIds.add(trade.id);
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          color: isSelected ? const Color(0xFFE3F2FD) : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: isSelected ? 2 : 1,
              color: isSelected ? const Color(0xFF22547C) : const Color(0xFFF2F2F7),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Symbol and checkbox
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    trade.tradingSymbol,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (_isSelectionMode)
                  Icon(
                    isSelected ? Icons.check_circle : Icons.circle_outlined,
                    color: isSelected ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                    size: 24,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // SELL/BUY with bag icon and quantity, and P&L
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: ShapeDecoration(
                        color: sideColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text(
                        sideLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.shopping_bag, size: 16, color: Color(0xFF8E8E93)),
                    const SizedBox(width: 4),
                    Text(
                      '${trade.quantity}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: pnl >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ATP and CMP
            Row(
              children: [
                const Text(
                  'ATP ',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  trade.price.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Color(0xFFFF3B30),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  '|',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 16),
                const Text(
                  'CMP ',
                  style: TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  currentPrice.toStringAsFixed(2),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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
        isLong ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
    final avgPrice = isLong ? position.avgBuyPrice : position.avgSellPrice;
    final pnl = position.realised + position.floating;
    final pnlColor = pnl >= 0 ? const Color(0xFF34C759) : const Color(0xFFFF3B30);

    return Container(
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
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
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: ShapeDecoration(
                                color: sideColor,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4)),
                              ),
                              child: Text(
                                sideLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${position.netQty.abs()} QTY @ ${avgPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        position.ltp > 0
                            ? position.ltp.toStringAsFixed(2)
                            : avgPrice.toStringAsFixed(2),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: pnlColor,
                          fontSize: 13,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: const ShapeDecoration(
                color: Color(0xFFF2F2F7),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    position.exchange,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    'Floating: ${position.floating >= 0 ? '+' : ''}${position.floating.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: position.floating >= 0
                          ? const Color(0xFF34C759)
                          : const Color(0xFFFF3B30),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
  }

  void _openTradeCard(Trade trade) {
    final metricsProvider =
        Provider.of<TradeMetricsProvider>(context, listen: false);
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);

    // Find the net position for this instrument from aggregated positions
    PositionAgg? position;
    try {
      position = metricsProvider.positions.firstWhere(
        (p) => p.instrumentToken == trade.instrumentToken,
      );
    } catch (_) {
      position = null;
    }

    // Determine the closing side and quantity based on net position
    // netQty > 0 means net long → need to SELL to close
    // netQty < 0 means net short → need to BUY to close
    // netQty == 0 means flat → default to opposite of this trade
    String closeOrderType;
    int closeQuantity;

    if (position != null && position.netQty != 0) {
      final isLong = position.netQty > 0;
      closeOrderType = isLong ? 'Market Execution' : 'Market Execution';
      closeQuantity = position.netQty.abs();
    } else {
      // Position is flat or not found — use the individual trade info
      final isBuy = trade.transactionType.toUpperCase() == 'BUY';
      closeOrderType = isBuy ? 'Market Execution' : 'Market Execution';
      closeQuantity = trade.quantity;
    }

    // Check if instrument is in watchlist for live price data
    WatchlistItem? existingItem =
        watchlistProvider.getByToken(trade.instrumentToken);

    final WatchlistItem itemToUse;
    if (existingItem != null) {
      itemToUse = existingItem;
    } else {
      // Build a WatchlistItem from the trade data
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

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Order'),
        content: Text(
          'Are you sure you want to cancel this ${trade.transactionType} order for ${trade.tradingSymbol}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Yes, Cancel',
              style: TextStyle(color: Color(0xFFFF3B30)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Get token
      final storage = SecureStorageService();
      final token = await storage.getToken();
      
      if (token == null) {
        throw Exception('Not authenticated');
      }

      // Call backend cancel endpoint
      final apiService = ApiService(backendUrl);
      final response = await apiService.put(
        '/trade/${trade.id}/cancel',
        {},
        token: token,
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          // Refresh data
          await metricsProvider.fetchBaseData();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Order cancelled: ${trade.tradingSymbol}'),
                backgroundColor: const Color(0xFF34C759),
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
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  Future<void> _squareOffSelected(List<Trade> allTrades) async {
    final selectedTrades = allTrades.where((t) => _selectedTradeIds.contains(t.id)).toList();

    if (selectedTrades.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Square Off Positions'),
        content: Text(
          'Are you sure you want to square off ${selectedTrades.length} trade(s)?\n\n'
          'This will place opposite market orders to close these positions.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Square Off',
              style: TextStyle(color: Color(0xFFFF3B30)),
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
      int successCount = 0;
      int failCount = 0;
      final List<String> errors = [];

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Place opposite orders for each selected trade
      for (final trade in selectedTrades) {
        try {
          // Determine opposite side
          final oppositeType = trade.transactionType.toUpperCase() == 'BUY' ? 'SELL' : 'BUY';
          
          // Place market order to close position
          final response = await apiService.post(
            '/trade',
            {
              'instrument_token': trade.instrumentToken,
              'tradingsymbol': trade.tradingSymbol,
              'exchange': trade.exchange,
              'transaction_type': oppositeType,
              'quantity': trade.quantity,
              'order_type': 'MARKET',
              'price': 0, // Market order
            },
            token: token,
          );

          if (response.statusCode == 200 || response.statusCode == 201) {
            successCount++;
          } else {
            failCount++;
            final body = jsonDecode(response.body);
            errors.add('${trade.tradingSymbol}: ${body['message'] ?? 'Failed'}');
          }
        } catch (e) {
          failCount++;
          errors.add('${trade.tradingSymbol}: ${e.toString()}');
        }
      }

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Refresh data
      final metricsProvider = Provider.of<TradeMetricsProvider>(context, listen: false);
      await metricsProvider.fetchBaseData();

      // Exit selection mode
      setState(() {
        _isSelectionMode = false;
        _selectedTradeIds.clear();
      });

      // Show result
      if (mounted) {
        String message = '';
        if (successCount > 0 && failCount == 0) {
          message = 'Successfully squared off $successCount position(s)';
        } else if (successCount > 0 && failCount > 0) {
          message = 'Squared off $successCount position(s), $failCount failed';
        } else {
          message = 'Failed to square off positions';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: failCount == 0 ? const Color(0xFF34C759) : const Color(0xFFFF9500),
            duration: const Duration(seconds: 3),
          ),
        );

        // Show errors if any
        if (errors.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Square Off Errors'),
              content: SingleChildScrollView(
                child: Text(errors.join('\n')),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  Widget _buildTradeCard(Trade trade) {
    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm:ss a").format(dt).toUpperCase();
    } catch (_) {}

    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color valueColor =
        isBuy ? const Color(0xFF34C759) : const Color(0xFFFF3B30);
    final bool isPending = trade.status.toLowerCase() == 'pending';

    return Container(
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFF2F2F7)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => _openTradeCard(trade),
            child: Container(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trade.tradingSymbol,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${trade.transactionType}: ${trade.quantity} QTY',
                          style: const TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        trade.price.toStringAsFixed(2),
                        style: TextStyle(
                          color: valueColor,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: Color(0xFF8E8E93)),
                          const SizedBox(width: 4),
                          Text(
                            formattedDate,
                            style: const TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const ShapeDecoration(
              color: Color(0xFFF2F2F7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 16, color: Colors.black),
                    const SizedBox(width: 6),
                    Text(
                      trade.userName ?? 'User',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'Status: ${trade.status.toUpperCase()}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                if (isPending)
                  GestureDetector(
                    onTap: () => _cancelOrder(trade),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  const Text(
                    'Duration',
                    style: TextStyle(
                      color: Color(0xFF22547C),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.underline,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
