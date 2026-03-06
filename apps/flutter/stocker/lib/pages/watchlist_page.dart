import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:stocker/pages/instrument_search_page.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import '../views/trade_card_view.dart';

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  @override
  void initState() {
    super.initState();
    // Load watchlist fresh each time this page is shown (e.g. after login) if it's currently empty
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final provider = Provider.of<WatchlistProvider>(context, listen: false);
        if (provider.isEmpty) {
          provider.loadWatchlist();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Security notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFEE2E2)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_user, color: Colors.red, size: 20),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'All profile running in this app is secure. Your data is encrypted.',
                      style: TextStyle(
                        color: Color(0xFFDC2626),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const InstrumentSearchPage(),
                          ),
                        );
                      },
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
                        child: Row(
                          children: [
                            const Icon(Icons.search,
                                color: Color(0xFF94A3B8), size: 20),
                            const SizedBox(width: 12),
                            const Text(
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
                  ),
                  const SizedBox(width: 12),
                  Consumer<WatchlistProvider>(
                    builder: (context, provider, child) {
                      return GestureDetector(
                        onTap: () {
                          provider.loadWatchlist();
                        },
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
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

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
                          Icon(Icons.add_chart,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No instruments in watchlist',
                            style: TextStyle(
                                fontSize: 16, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const InstrumentSearchPage(),
                                ),
                              );
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('Add Instruments'),
                          ),
                          const SizedBox(height: 16),
                          TextButton.icon(
                            onPressed: () {
                              watchlistProvider.loadWatchlist();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh Watchlist'),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => watchlistProvider.loadWatchlist(),
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
                        itemCount: watchlistProvider.items.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Color(0xFFF1F5F9),
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
                              child:
                                  const Icon(Icons.delete, color: Colors.white),
                            ),
                            onDismissed: (direction) {
                              watchlistProvider.removeInstrument(item.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      '${instrument.tradingsymbol} removed from watchlist'),
                                ),
                              );
                            },
                            child:
                                _buildWatchlistCard(context, item, instrument),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchlistCard(
      BuildContext context, dynamic item, dynamic instrument) {
    final bool isPositive = item.isPositive;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
        color: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left side
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
                      if (instrument.expiry != null) ...[
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
                          instrument.expiryDisplay.toString().toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        isPositive ? Icons.north_east : Icons.south_west,
                        size: 14,
                        color: isPositive
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          item.changeDisplay.isEmpty
                              ? '--'
                              : item.changeDisplay,
                          style: TextStyle(
                            color: isPositive
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
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

            const SizedBox(width: 8),

            // Right side — ASK and BID side by side
            Builder(builder: (context) {
              final ltp = item.currentPrice ?? 0.0;
              final spread = ltp * 0.0005;

              final rawAsk = item.askPrice;
              final rawBid = item.bidPrice;
              final effectiveAsk = (rawAsk != null && rawAsk > 0.1)
                  ? rawAsk
                  : (ltp > 0 ? ltp + spread : null);
              final effectiveBid = (rawBid != null && rawBid > 0.1)
                  ? rawBid
                  : (ltp > 0 ? ltp - spread : null);

              return SizedBox(
                width: 180,
                child: Row(
                  children: [
                    // BID
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'BID',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 9,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          effectiveBid != null
                              ? AnimatedFlipCounter(
                                  value: effectiveBid,
                                  fractionDigits: 2,
                                  textStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                )
                              : const Text(
                                  '--',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      color: const Color(0xFFF1F5F9),
                    ),
                    // ASK
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'ASK',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 9,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          effectiveAsk != null
                              ? AnimatedFlipCounter(
                                  value: effectiveAsk,
                                  fractionDigits: 2,
                                  textStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEF4444),
                                  ),
                                )
                              : const Text(
                                  '--',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
