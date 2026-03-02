import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:stocker/models/trade.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/views/trade_card_view.dart';
import 'history_filter_sheet.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
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
    );
  }

  /// Trade tab: shows aggregated open positions (netQty != 0)
  Widget _buildPositionsList() {
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.trades.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        // Only show instruments with open positions (netQty != 0)
        final openPositions =
            provider.positions.where((p) => p.netQty != 0).toList();

        if (openPositions.isEmpty) {
          return const Center(
            child: Text(
              'No open positions.',
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
            itemCount: openPositions.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final position = openPositions[index];
              return _buildPositionCard(position);
            },
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
            .where((t) => t.status.toLowerCase() != 'completed')
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

  void _openPositionCard(PositionAgg position) {
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);

    final isLong = position.netQty > 0;
    final closeQuantity = position.netQty.abs();

    WatchlistItem? existingItem =
        watchlistProvider.getByToken(position.instrumentToken);

    final WatchlistItem itemToUse;
    if (existingItem != null) {
      itemToUse = existingItem;
    } else {
      final instrument = KiteInstrument(
        id: '',
        instrumentToken: position.instrumentToken,
        exchangeToken: '',
        tradingsymbol: position.tradingsymbol,
        name: position.tradingsymbol,
        lastPrice: position.ltp > 0 ? position.ltp : (isLong ? position.avgBuyPrice : position.avgSellPrice),
        strike: 0,
        tickSize: 0.05,
        lotSize: 1,
        instrumentType: '',
        segment: '',
        exchange: position.exchange,
        updatedAt: DateTime.now(),
      );

      itemToUse = WatchlistItem(
        id: position.instrumentToken,
        instrument: instrument,
        currentPrice: position.ltp > 0 ? position.ltp : null,
        lastUpdated: DateTime.now(),
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TradeCardPage(
          item: itemToUse,
          initialOrderType: 'Market Execution',
          initialQuantity: closeQuantity,
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

    return GestureDetector(
      onTap: () => _openPositionCard(position),
      child: Container(
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

  Widget _buildTradeCard(Trade trade) {
    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm:ss a").format(dt).toUpperCase();
    } catch (_) {}

    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color valueColor =
        isBuy ? const Color(0xFF34C759) : const Color(0xFFFF3B30);

    return GestureDetector(
      onTap: () => _openTradeCard(trade),
      child: Container(
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
      ),
    );
  }
}
