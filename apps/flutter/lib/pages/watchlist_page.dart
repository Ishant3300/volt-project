import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/pages/instrument_search_page.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import '../utils/contants.dart';
import '../views/trade_card_view.dart';
import '../widgets/announcement_banner.dart';

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
                                color: Color(0xFF94A3B8),
                                size: kIconSizeMedium),
                            const SizedBox(width: 12),
                            const Text(
                              'Search & Add',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: kFontSizeBody,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightRegular,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Announcement marquee
            const AnnouncementBanner(),

            // Watchlist items
            Expanded(
              child: Consumer<WatchlistProvider>(
                builder: (context, watchlistProvider, child) {
                  if (watchlistProvider.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (watchlistProvider.isEmpty &&
                      watchlistProvider.error != null) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.wifi_off,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            "Couldn't load your watchlist",
                            style: TextStyle(
                                fontSize: kFontSizeSectionHeader,
                                color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () {
                              watchlistProvider.loadWatchlist();
                            },
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
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
                                fontSize: kFontSizeSectionHeader,
                                color: Colors.grey[600]),
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
                      child: Column(
                        children: [
                          // Header row with BID / ASK / HIGH / LOW labels
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    'SCRIPTS',
                                    style: TextStyle(
                                      color: Color(0xFF94A3B8),
                                      fontSize: kFontSizeCaption,
                                      fontFamily: kFontFamily,
                                      fontWeight: kFontWeightSemiBold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 180,
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'BID',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: kFontSizeCaption,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightSemiBold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 21),
                                          const Expanded(
                                            child: Text(
                                              'ASK',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: kFontSizeCaption,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightSemiBold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Expanded(
                                            child: Text(
                                              'HIGH',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: kFontSizeCaption,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightSemiBold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: 21),
                                          const Expanded(
                                            child: Text(
                                              'LOW',
                                              textAlign: TextAlign.end,
                                              style: TextStyle(
                                                color: Color(0xFF94A3B8),
                                                fontSize: kFontSizeCaption,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightSemiBold,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          // List
                          Expanded(
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              itemCount: watchlistProvider.items.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(
                                height: 1,
                                color: Color(0xFFF1F5F9),
                              ),
                              itemBuilder: (context, index) {
                                final item = watchlistProvider.items[index];
                                final instrument = item.instrument;

                                return Dismissible(
                                  key: Key(item.id),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (direction) async {
                                    final investorMode =
                                        Provider.of<InvestorModeProvider>(
                                            context,
                                            listen: false);
                                    if (investorMode.isInvestor) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                            content: Text(
                                                'Watchlist editing is not available in investor mode'),
                                            backgroundColor: Color(0xFF64748B)),
                                      );
                                      return false;
                                    }
                                    return true;
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.only(right: 20),
                                    color: Colors.red,
                                    child: const Icon(Icons.delete,
                                        color: Colors.white),
                                  ),
                                  onDismissed: (direction) async {
                                    final removed = await watchlistProvider
                                        .removeInstrument(item.id);
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(removed
                                            ? '${instrument.tradingsymbol} removed from watchlist'
                                            : 'Could not remove ${instrument.tradingsymbol} — try again'),
                                        backgroundColor: removed
                                            ? null
                                            : const Color(0xFFEF4444),
                                      ),
                                    );
                                  },
                                  child: _buildWatchlistCard(
                                      context, item, instrument),
                                );
                              },
                            ),
                          ),
                        ],
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
    final String instType = instrument.instrumentType ?? '';
    final double strike = instrument.strike ?? 0.0;
    final bool isOption = instType == 'CE' || instType == 'PE';
    final bool isFut = instType == 'FUT';

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left side
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name line: "NIFTY FUT" or "ADANIENT 1680 CE"
                  Text(
                    _buildInstrumentTitle(
                        instrument, instType, strike, isOption, isFut),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeTradeSymbol,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Expiry row
                  if (instrument.expiry != null)
                    Text(
                      instrument.expiryDisplay.toString().toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: kFontSizeCaption,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Row(
                    children: [
                      Icon(
                        isPositive ? Icons.north_east : Icons.south_west,
                        size: kIconSizeSmall,
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
                            fontSize: kFontSizePositionDetail,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
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

            // Right side — BID/ASK + HIGH/LOW
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

              // Determine tick color: blue if price went up, red if down,
              // neutral if unchanged OR no previous tick to compare against
              // yet. This used to fall to red for BOTH of those cases too —
              // every instrument showed red on first load (before any
              // second tick arrived) and stayed red forever if the price
              // never actually moved, reading as a market-wide sell-off.
              const neutralTickColor = Color(0xFF0F172A);
              Color tickColor(double? prev, double? current) {
                if (prev == null || current == null || current == prev) {
                  return neutralTickColor;
                }
                return current > prev ? kBrandPrimary : const Color(0xFFEF4444);
              }

              final prevBid = item.previousBidPrice;
              final prevAsk = item.previousAskPrice;
              final Color bidColor = tickColor(prevBid, effectiveBid);
              final Color askColor = tickColor(prevAsk, effectiveAsk);

              final double? high = item.high;
              final double? low = item.low;

              return SizedBox(
                width: 180,
                child: Column(
                  children: [
                    // BID / ASK row
                    Row(
                      children: [
                        Expanded(
                          child: effectiveBid != null
                              ? Text(
                                  effectiveBid.toStringAsFixed(2),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceMain,
                                    fontWeight: kFontWeightSemiBold,
                                    color: bidColor,
                                  ),
                                )
                              : Text(
                                  '--',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceMain,
                                    fontWeight: kFontWeightSemiBold,
                                    color: bidColor,
                                  ),
                                ),
                        ),
                        Container(
                          width: 1,
                          height: 28,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: const Color(0xFFF1F5F9),
                        ),
                        Expanded(
                          child: effectiveAsk != null
                              ? Text(
                                  effectiveAsk.toStringAsFixed(2),
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceMain,
                                    fontWeight: kFontWeightSemiBold,
                                    color: askColor,
                                  ),
                                )
                              : Text(
                                  '--',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceMain,
                                    fontWeight: kFontWeightSemiBold,
                                    color: askColor,
                                  ),
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // HIGH / LOW row
                    Row(
                      children: [
                        Expanded(
                          child: (high != null && high > 0)
                              ? Text(
                                  high.toStringAsFixed(2),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceSecondary,
                                    fontWeight: kFontWeightSemiBold,
                                    color: Color(0xFF475569),
                                  ),
                                )
                              : const Text(
                                  '--',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceSecondary,
                                    fontWeight: kFontWeightSemiBold,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                        ),
                        Container(
                          width: 1,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 10),
                          color: const Color(0xFFF1F5F9),
                        ),
                        Expanded(
                          child: (low != null && low > 0)
                              ? Text(
                                  low.toStringAsFixed(2),
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceSecondary,
                                    fontWeight: kFontWeightSemiBold,
                                    color: Color(0xFF475569),
                                  ),
                                )
                              : const Text(
                                  '--',
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontFamily: kFontFamily,
                                    fontSize: kFontSizePriceSecondary,
                                    fontWeight: kFontWeightSemiBold,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                        ),
                      ],
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

  /// Build title like "GOLD", "NIFTY FUT", "ADANIENT 1680 CE"
  String _buildInstrumentTitle(dynamic instrument, String instType,
      double strike, bool isOption, bool isFut) {
    final name = instrument.name.isNotEmpty
        ? instrument.name.toString().toUpperCase()
        : instrument.tradingsymbol.toString();

    if (isOption && strike > 0) {
      final strikeStr = strike == strike.roundToDouble()
          ? strike.toInt().toString()
          : strike.toStringAsFixed(2);
      return '$name $strikeStr $instType';
    }
    if (isFut) return '$name FUT';
    return name;
  }
}
