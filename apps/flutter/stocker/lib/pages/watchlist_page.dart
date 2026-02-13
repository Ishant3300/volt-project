import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/pages/instrument_search_page.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import '../views/trade_card_view.dart';

class WatchlistPage extends StatelessWidget {
  const WatchlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Security notice
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(4),
              decoration: ShapeDecoration(
                color: const Color(0x19FF3B30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.security, color: const Color(0xFFFF3B30), size: 18),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'All profile running in this app is secure. The new',
                      style: TextStyle(
                        color: const Color(0xFFFF3B30),
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InstrumentSearchPage(),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: const Color(0xFF8E8E93)),
                    SizedBox(width: 10),
                    Text(
                      'Search & Add',
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    Spacer(),
                    Icon(Icons.filter_list, color: const Color(0xFF8E8E93)),
                  ],
                ),
              ),
            ),

            SizedBox(height: 16),

            // Watchlist items
            Expanded(
              child: Consumer<WatchlistProvider>(
                builder: (context, watchlistProvider, child) {
                  if (watchlistProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (watchlistProvider.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_chart, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No instruments in watchlist',
                            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const InstrumentSearchPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Instruments'),
                          ),
                        ],
                      ),
                    );
                  }

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: watchlistProvider.items.length,
                      separatorBuilder: (context, index) => Divider(
                        height: 1,
                        color: const Color(0xFFD1D1D6),
                      ),
                      itemBuilder: (context, index) {
                        final item = watchlistProvider.items[index];
                        final instrument = item.instrument;

                        return Dismissible(
                          key: Key(item.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20),
                            color: Colors.red,
                            child: const Icon(Icons.delete, color: Colors.white),
                          ),
                          onDismissed: (direction) {
                            watchlistProvider.removeInstrument(item.id);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${instrument.tradingsymbol} removed from watchlist',
                                ),
                              ),
                            );
                          },
                          child: _buildWatchlistCard(context, item, instrument),
                        );
                      },
                    ),
                  );
                },
              ),
            ),

            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistCard(BuildContext context, dynamic item, dynamic instrument) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TradeCardPage(item: item),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left side - Name, expiry, change
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          instrument.name.isNotEmpty
                              ? instrument.name.toString().toUpperCase()
                              : instrument.tradingsymbol,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (instrument.expiry != null) ...[
                        SizedBox(width: 6),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: ShapeDecoration(
                            color: const Color(0xFFD9D9D9),
                            shape: OvalBorder(),
                          ),
                        ),
                        SizedBox(width: 6),
                        Text(
                          instrument.expiryDisplay,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        item.isPositive ? '↑' : '↓',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: item.isPositive
                              ? const Color(0xFF34C759)
                              : const Color(0xFFFF3B30),
                        ),
                      ),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.changeDisplay.isEmpty ? '--' : item.changeDisplay,
                          style: TextStyle(
                            color: item.isPositive
                                ? const Color(0xFF34C759)
                                : const Color(0xFFFF3B30),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(width: 8),

            // Right side - Price, LTP, High/Low
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Chart icon + price
                    Icon(Icons.show_chart, size: 16, color: Colors.black),
                    SizedBox(width: 4),
                    Text(
                      item.currentPrice?.toStringAsFixed(2) ?? '0.00',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    SizedBox(width: 8),
                    // Green dot + LTP
                    Container(
                      width: 8,
                      height: 8,
                      decoration: ShapeDecoration(
                        color: const Color(0xFF34C759),
                        shape: OvalBorder(),
                      ),
                    ),
                    SizedBox(width: 2),
                    Text(
                      item.currentPrice?.toStringAsFixed(2) ?? '0.00',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.only(top: 2, right: 8, bottom: 2),
                      decoration: ShapeDecoration(
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 1,
                            color: const Color(0xFFC7C7CC),
                          ),
                        ),
                      ),
                      child: Text(
                        'L: ${item.low?.toStringAsFixed(1) ?? '0.0'}',
                        style: TextStyle(
                          color: const Color(0xFF999999),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'H: ${item.high?.toStringAsFixed(1) ?? '0.0'}',
                      style: TextStyle(
                        color: const Color(0xFF999999),
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
    );
  }
}
