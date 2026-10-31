import 'dart:async';

import 'package:stocker/widgets/nse_ban_chip.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/pages/instrument_search_page.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import '../utils/contants.dart';
import '../views/trade_card_view.dart';
import '../widgets/announcement_banner.dart';

/// Cosmetic only — the "x/100" counter next to the search pill. Not a real
/// cap: neither `WatchlistProvider`/`WatchlistService` nor the backend
/// enforces any watchlist size limit today, so this never blocks
/// `addInstrument`, it's purely a display number matching the reference design.
const int _kWatchlistDisplayCap = 100;

/// Segment tabs, in the order a client swipes through them (same as the web
/// client watchlist, apex-web-portal ClientWatchlist.tsx, 31 Oct 2026).
const List<MapEntry<String, String>> _kSegmentTabs = [
  MapEntry('NFO-FUT', 'NSE FUT'),
  MapEntry('MCX-FUT', 'MCX FUT'),
  MapEntry('GLOBAL', 'GLOBAL'),
  MapEntry('COMEX-FUT', 'COMEX'),
  MapEntry('NFO-OPT', 'NSE OPT'),
  MapEntry('MCX-OPT', 'MCX OPT'),
];

/// Shown until the client's allowed segments are known.
const Set<String> _kDefaultSegments = {'NFO-FUT', 'MCX-FUT', 'GLOBAL', 'COMEX-FUT'};

class WatchlistPage extends StatefulWidget {
  const WatchlistPage({super.key});

  @override
  State<WatchlistPage> createState() => _WatchlistPageState();
}

/// Watchlist by segment: NSE FUT → MCX FUT → GLOBAL → COMEX (then the option
/// segments), one tab per segment the client may trade plus any segment they
/// still hold scripts in. Swipe the list sideways or tap a tab. "Search & add"
/// searches every allowed segment; a script added from it takes you to its
/// segment's tab with the new row highlighted. Still one watchlist on the
/// server — the tabs only group it. Removing a script is through Edit (a sideways swipe
/// now changes the tab, so swipe-to-delete would remove scripts by accident).
class _WatchlistPageState extends State<WatchlistPage> {
  /// Last open tab, kept while the app runs.
  static String _lastSegment = _kSegmentTabs.first.key;

  bool _editMode = false;
  /// The row just added from search — highlighted for a few seconds.
  String? _highlightId;
  Timer? _highlightTimer;
  PageController? _pageController;
  String _pagesKey = '';
  final ScrollController _tabScroll = ScrollController();

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
  void dispose() {
    _highlightTimer?.cancel();
    _pageController?.dispose();
    _tabScroll.dispose();
    super.dispose();
  }

  /// A script's tab (GLOBAL is stored as INDICES on older rows — same permission).
  static String _segmentOf(dynamic instrument) =>
      UserProfileProvider.normalizeSegment(instrument.segment as String?);

  /// The tabs to show: allowed segments (or the four futures segments until
  /// known) plus any segment the client still holds scripts in.
  List<MapEntry<String, String>> _tabsFor(List<dynamic> items, Set<String>? allowed) {
    final present = items.map((i) => _segmentOf(i.instrument)).toSet();
    final tabs = _kSegmentTabs
        .where((t) => (allowed ?? _kDefaultSegments).contains(t.key) || present.contains(t.key))
        .toList();
    for (final seg in present) {
      if (seg.isNotEmpty && !_kSegmentTabs.any((t) => t.key == seg)) tabs.add(MapEntry(seg, seg));
    }
    return tabs.isEmpty ? _kSegmentTabs.where((t) => _kDefaultSegments.contains(t.key)).toList() : tabs;
  }

  /// Search every allowed segment (or one, from an empty tab's "Add" button).
  /// Back on the watchlist, the last script added is shown: its segment's tab
  /// opens and its row is highlighted, so it's clear where it went.
  Future<void> _openSearch(BuildContext context, {String initialTab = 'ALL'}) async {
    final provider = Provider.of<WatchlistProvider>(context, listen: false);
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final before = provider.items.map((i) => i.id).toSet();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => InstrumentSearchPage(initialTab: initialTab),
      ),
    );
    if (!mounted) return;
    final added = provider.items.where((i) => !before.contains(i.id)).toList();
    if (added.isEmpty) return;
    final last = added.last;
    final segment = _segmentOf(last.instrument);
    setState(() {
      _lastSegment = segment;
      _highlightId = last.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = _tabsFor(provider.items, profile.allowedSegments);
      final index = tabs.indexWhere((t) => t.key == segment);
      if (index >= 0 && (_pageController?.hasClients ?? false)) _pageController!.jumpToPage(index);
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  void _selectTab(int index, List<MapEntry<String, String>> tabs) {
    if (index < 0 || index >= tabs.length) return;
    setState(() => _lastSegment = tabs[index].key);
    _pageController?.animateToPage(index, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserProfileProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final tabs = _tabsFor(watchlistProvider.items, profile.allowedSegments);
    int activeIndex = tabs.indexWhere((t) => t.key == _lastSegment);
    if (activeIndex < 0) activeIndex = 0;

    // A new page set (tabs changed) gets a fresh controller on the open tab.
    final key = tabs.map((t) => t.key).join(',');
    if (key != _pagesKey || _pageController == null) {
      // The old controller is still attached to the PageView until this
      // frame swaps it — dispose it after the frame, not now.
      final old = _pageController;
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _pageController = PageController(initialPage: activeIndex);
      _pagesKey = key;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header — title + edit
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
                ],
              ),
            ),

            // Search pill — searches the open tab's segment
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: GestureDetector(
                onTap: () => _openSearch(context),
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
                          'Search & add — all segments',
                          style: TextStyle(
                            color: Color(0xFF8E95A2),
                            fontSize: 14,
                            fontFamily: kFontFamily,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      Text(
                        '${watchlistProvider.items.length}/$_kWatchlistDisplayCap',
                        style: const TextStyle(
                          color: Color(0xFF8E95A2),
                          fontSize: 14,
                          fontFamily: kFontFamily,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Announcement marquee
            const AnnouncementBanner(),

            // Segment tabs
            SizedBox(
              height: 44,
              child: ListView.separated(
                controller: _tabScroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: tabs.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final selected = index == activeIndex;
                  final count = watchlistProvider.items.where((i) => _segmentOf(i.instrument) == tab.key).length;
                  return GestureDetector(
                    onTap: () => _selectTab(index, tabs),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected ? kBrandPrimary.withValues(alpha: 0.10) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? kBrandPrimary : const Color(0xFFE5E7EB)),
                      ),
                      child: Text(
                        '${tab.value}  $count',
                        style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? kBrandPrimary : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Watchlist items — one page per tab, swipe between them
            Expanded(
              child: Builder(builder: (context) {
                if (watchlistProvider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (watchlistProvider.isEmpty && watchlistProvider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          "Couldn't load your watchlist",
                          style: TextStyle(fontSize: kFontSizeSectionHeader, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: () => watchlistProvider.loadWatchlist(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                return PageView.builder(
                  controller: _pageController,
                  itemCount: tabs.length,
                  onPageChanged: (index) => setState(() => _lastSegment = tabs[index].key),
                  itemBuilder: (context, pageIndex) {
                    final tab = tabs[pageIndex];
                    final pageItems = watchlistProvider.items
                        .where((item) => _segmentOf(item.instrument) == tab.key)
                        .toList();

                    if (pageItems.isEmpty) {
                      return RefreshIndicator(
                        onRefresh: () => watchlistProvider.loadWatchlist(),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.add_chart, size: 56, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Center(
                              child: Text(
                                'No ${tab.value} scripts yet',
                                style: TextStyle(fontSize: kFontSizeSectionHeader, color: Colors.grey[600]),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: () => _openSearch(context, initialTab: tab.key),
                                icon: const Icon(Icons.add),
                                label: Text('Add ${tab.value}'),
                              ),
                            ),
                            if (tabs.length > 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Center(
                                  child: Text(
                                    'Swipe for another segment',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () => watchlistProvider.loadWatchlist(),
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: pageItems.length,
                        separatorBuilder: (context, index) => const Divider(
                          height: 1,
                          color: Color(0xFFF0F2F5),
                        ),
                        itemBuilder: (context, index) {
                          final item = pageItems[index];
                          return _buildWatchlistRow(context, item, item.instrument, watchlistProvider);
                        },
                      ),
                    );
                  },
                );
              }),
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
    // Price columns size to the screen instead of a fixed 84dp each, so on
    // a narrow phone the instrument name keeps enough room.
    final double priceColWidth =
        (MediaQuery.sizeOf(context).width * 0.2).clamp(64.0, 84.0);

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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: item.id == _highlightId ? kBrandPrimary.withValues(alpha: 0.10) : Colors.white,
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
                      fontSize: 11,
                      fontFamily: kFontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1),
                  // Line 2: script title
                  // Shrinks a long name (e.g. BANKNIFTY 57800 CE) to fit
                  // the available width instead of cutting it to "…".
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _buildInstrumentTitle(
                              instrument, instType, strike, isOption, isFut),
                          style: const TextStyle(
                            color: Color(0xFF111417),
                            fontSize: 14,
                            fontFamily: kFontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                        ),
                        if (instrument.nseBanned) const NseBanChip(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 1),
                  // Line 3: expiry/date
                  if (instrument.expiry != null)
                    Text(
                      instrument.expiryMonthDayDisplay,
                      style: const TextStyle(
                        color: Color(0xFF7C828D),
                        fontSize: 11,
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
                      fontSize: 15,
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
                          fontSize: 15,
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
                          fontSize: 11,
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
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF7C828D),
                  ),
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: priceColWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        priceText(effectiveBid, bidColor, bidIsSynthetic),
                        const SizedBox(height: 2),
                        captionText('L', low),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: priceColWidth,
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
                        // A script the client holds stays until the position is closed.
                        if (watchlistProvider.isHeld(instrument.instrumentToken)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'You hold an open position in ${instrument.tradingsymbol} — it stays on your watchlist until the position is closed.'),
                              backgroundColor: const Color(0xFF64748B),
                            ),
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
                                : watchlistProvider.lastRemoveError ??
                                    'Could not remove ${instrument.tradingsymbol} — try again'),
                            backgroundColor: removed ? null : kColorSell,
                          ),
                        );
                      },
                      icon: Icon(Icons.remove_circle_outline,
                          size: 20,
                          color: watchlistProvider.isHeld(instrument.instrumentToken)
                              ? const Color(0xFF94A3B8)
                              : kColorSell),
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
