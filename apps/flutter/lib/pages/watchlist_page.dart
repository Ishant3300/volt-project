import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/pages/instrument_search_page.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import '../utils/contants.dart';
import '../views/trade_card_view.dart';
import '../widgets/announcement_banner.dart';

/// Cosmetic only — the "x/100" counter next to the search pill. Not a real
/// cap: neither `WatchlistProvider`/`WatchlistService` nor the backend
/// enforces any watchlist size limit today, so this never blocks
/// `addInstrument`, it's purely a display number matching the reference design.
const int _kWatchlistDisplayCap = 100;

enum _InstrumentFilter { all, equityIndex, futures, options }

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

class _WatchlistPageState extends State<WatchlistPage> {
  bool _editMode = false;
  _InstrumentFilter _filter = _InstrumentFilter.all;

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

  bool _matchesFilter(dynamic instrument) {
    if (_filter == _InstrumentFilter.all) return true;
    final instType = instrument.instrumentType ?? '';
    final isOption = instType == 'CE' || instType == 'PE';
    final isFut = instType == 'FUT';
    switch (_filter) {
      case _InstrumentFilter.futures:
        return isFut;
      case _InstrumentFilter.options:
        return isOption;
      case _InstrumentFilter.equityIndex:
        return !isFut && !isOption;
      case _InstrumentFilter.all:
        return true;
    }
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    final picked = await showModalBottomSheet<_InstrumentFilter>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        Widget option(_InstrumentFilter value, String label) {
          return ListTile(
            title: Text(
              label,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 15,
                fontWeight: _filter == value ? FontWeight.w700 : FontWeight.w400,
                color: const Color(0xFF111827),
              ),
            ),
            trailing: _filter == value
                ? const Icon(Icons.check, color: kBrandPrimary, size: 20)
                : null,
            onTap: () => Navigator.pop(sheetContext, value),
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              option(_InstrumentFilter.all, 'All'),
              option(_InstrumentFilter.equityIndex, 'Equity & index'),
              option(_InstrumentFilter.futures, 'Futures'),
              option(_InstrumentFilter.options, 'Options'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) setState(() => _filter = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header — title + edit + filter
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Quotes',
                      style: TextStyle(
                        fontFamily: kFontFamily,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1D20),
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _editMode = !_editMode),
                    tooltip: _editMode ? 'Done' : 'Edit watchlist',
                    icon: Icon(
                      _editMode ? Icons.check : Icons.edit_outlined,
                      size: 20,
                      color: _editMode ? kBrandPrimary : const Color(0xFF6B7280),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showFilterSheet(context),
                    tooltip: 'Filter',
                    icon: Icon(
                      Icons.filter_list,
                      size: 20,
                      color: _filter != _InstrumentFilter.all
                          ? kBrandPrimary
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),

            // Search pill with a live count/cap indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Color(0xFF8E95A2), size: 18),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Search & add',
                          style: TextStyle(
                            color: Color(0xFF8E95A2),
                            fontSize: 14,
                            fontFamily: kFontFamily,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Consumer<WatchlistProvider>(
                        builder: (context, watchlistProvider, child) => Text(
                          '${watchlistProvider.items.length}/$_kWatchlistDisplayCap',
                          style: const TextStyle(
                            color: Color(0xFF8E95A2),
                            fontSize: 14,
                            fontFamily: kFontFamily,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

                  final visibleItems = watchlistProvider.items
                      .where((item) => _matchesFilter(item.instrument))
                      .toList();

                  if (visibleItems.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.filter_list_off,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            'No instruments match this filter',
                            style: TextStyle(
                                fontSize: kFontSizeSectionHeader,
                                color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _filter = _InstrumentFilter.all),
                            child: const Text('Clear filter'),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => watchlistProvider.loadWatchlist(),
                    child: ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: visibleItems.length,
                      separatorBuilder: (context, index) => const Divider(
                        height: 1,
                        color: Color(0xFFF0F2F5),
                      ),
                      itemBuilder: (context, index) {
                        final item = visibleItems[index];
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
                            color: kColorSell,
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
                                backgroundColor: removed ? null : kColorSell,
                              ),
                            );
                          },
                          child: _buildWatchlistRow(
                              context, item, instrument, watchlistProvider),
                        );
                      },
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

  Widget _buildWatchlistRow(BuildContext context, dynamic item,
      dynamic instrument, WatchlistProvider watchlistProvider) {
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.white,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Left side — 3 stacked lines
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line 1: change + % change
                  Text(
                    item.changeDisplay.isEmpty ? '--' : item.changeDisplay,
                    style: TextStyle(
                      color: isPositive ? kColorBuy : kColorSell,
                      fontSize: 12,
                      fontFamily: kFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Line 2: script title
                  Text(
                    _buildInstrumentTitle(
                        instrument, instType, strike, isOption, isFut),
                    style: const TextStyle(
                      color: Color(0xFF111417),
                      fontSize: 16,
                      fontFamily: kFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  // Line 3: expiry/date
                  if (instrument.expiry != null)
                    Text(
                      instrument.expiryMonthDayDisplay,
                      style: const TextStyle(
                        color: Color(0xFF7C828D),
                        fontSize: 12,
                        fontFamily: kFontFamily,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Right side — Bid/LTP + Ask, each with an L:/H: subtext
            Builder(builder: (context) {
              final ltp = item.currentPrice ?? 0.0;
              final spread = ltp * 0.0005;

              final rawAsk = item.askPrice;
              final rawBid = item.bidPrice;
              // A missing/zero raw bid or ask falls back to a fabricated
              // ltp ± spread guess so the row isn't blank — but that guess
              // must never look identical to a real quote, or the user has
              // no way to tell a genuine market depth price from a filler.
              final askIsSynthetic = !(rawAsk != null && rawAsk > 0.1);
              final bidIsSynthetic = !(rawBid != null && rawBid > 0.1);
              final effectiveAsk = askIsSynthetic
                  ? (ltp > 0 ? ltp + spread : null)
                  : rawAsk;
              final effectiveBid = bidIsSynthetic
                  ? (ltp > 0 ? ltp - spread : null)
                  : rawBid;
              const syntheticColor = Color(0xFF94A3B8);

              // Determine tick color: blue if price went up, red if down,
              // neutral if unchanged OR no previous tick to compare against
              // yet. This used to fall to red for BOTH of those cases too —
              // every instrument showed red on first load (before any
              // second tick arrived) and stayed red forever if the price
              // never actually moved, reading as a market-wide sell-off.
              const neutralTickColor = Color(0xFF1A1D20);
              Color tickColor(double? prev, double? current) {
                if (prev == null || current == null || current == prev) {
                  return neutralTickColor;
                }
                return current > prev ? kColorBuy : kColorSell;
              }

              final prevBid = item.previousBidPrice;
              final prevAsk = item.previousAskPrice;
              final Color bidColor = tickColor(prevBid, effectiveBid);
              final Color askColor = tickColor(prevAsk, effectiveAsk);

              final double? high = item.high;
              final double? low = item.low;

              // 17px bold tabular price, with the decimal segment rendered
              // smaller — same tick-color/synthetic-price logic as before,
              // just split across two TextSpans for the size difference.
              Widget priceText(double? value, Color color, bool synthetic) {
                if (value == null) {
                  return Text(
                    '--',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontFamily: kFontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: syntheticColor,
                    ),
                  );
                }
                final parts = value.toStringAsFixed(2).split('.');
                final resolvedColor = synthetic ? syntheticColor : color;
                final fontStyle =
                    synthetic ? FontStyle.italic : FontStyle.normal;
                return Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: parts[0],
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          fontStyle: fontStyle,
                          color: resolvedColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: '.${parts[1]}',
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontStyle: fontStyle,
                          color: resolvedColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.end,
                );
              }

              Widget captionText(String label, double? value) {
                return Text(
                  (value != null && value > 0)
                      ? '$label: ${value.toStringAsFixed(2)}'
                      : '$label: --',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF7C828D),
                  ),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        priceText(effectiveBid, bidColor, bidIsSynthetic),
                        const SizedBox(height: 2),
                        captionText('L', low),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 84,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        priceText(effectiveAsk, askColor, askIsSynthetic),
                        const SizedBox(height: 2),
                        captionText('H', high),
                      ],
                    ),
                  ),
                  if (_editMode) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      onPressed: () async {
                        final investorMode = Provider.of<InvestorModeProvider>(
                            context,
                            listen: false);
                        if (investorMode.isInvestor) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Watchlist editing is not available in investor mode'),
                                backgroundColor: Color(0xFF64748B)),
                          );
                          return;
                        }
                        final removed =
                            await watchlistProvider.removeInstrument(item.id);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(removed
                                ? '${instrument.tradingsymbol} removed from watchlist'
                                : 'Could not remove ${instrument.tradingsymbol} — try again'),
                            backgroundColor: removed ? null : kColorSell,
                          ),
                        );
                      },
                      icon: const Icon(Icons.remove_circle_outline,
                          size: 20, color: kColorSell),
                    ),
                  ],
                ],
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
