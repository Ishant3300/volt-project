import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/providers/feature_unlock_provider.dart';
import 'utils/contants.dart';
import 'pages/watchlist_page.dart';
import 'pages/orders_page.dart';
import 'pages/history_page.dart';
import 'pages/profile_page.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const WatchlistPage(),
    const OrdersPage(),
    const PortfolioPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-lock the instant the app leaves the foreground — a backgrounded
    // app that gets glanced at or reopened by someone else should never
    // still show the unlocked feature set.
    if (state == AppLifecycleState.paused) {
      final unlock = Provider.of<FeatureUnlockProvider>(context, listen: false);
      unlock.lock();
      if (_selectedIndex != 0) setState(() => _selectedIndex = 0);
    }
  }

  // Hidden unlock gesture: 4 taps on the Watchlist nav icon within 2s of
  // the first one reveals the full app. Total-time budget rather than a
  // strict per-tap rhythm — easy to land by hand while still requiring a
  // fast, deliberate burst rather than 4 taps spread out over time.
  DateTime? _firstWatchlistTap;
  int _watchlistTapCount = 0;

  void _registerWatchlistUnlockTap() {
    final now = DateTime.now();
    final first = _firstWatchlistTap;

    if (first == null || now.difference(first) > const Duration(milliseconds: 2000)) {
      _firstWatchlistTap = now;
      _watchlistTapCount = 1;
      return;
    }

    _watchlistTapCount++;
    if (_watchlistTapCount >= 4) {
      _watchlistTapCount = 0;
      _firstWatchlistTap = null;
      Provider.of<FeatureUnlockProvider>(context, listen: false).unlock();
    }
  }

  void _onItemTapped(int index) {
    if (index == 0) _registerWatchlistUnlockTap();
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildNavItem(String svgPath, String label, int index) {
    final bool isSelected = _selectedIndex == index;
    final color =
        isSelected ? kBrandPrimary : const Color(0xFF94A3B8);
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? kBrandPrimary.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              svgPath,
              width: kFontSizeNavIcon,
              height: kFontSizeNavIcon,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: kFontSizeNavLabel,
                fontWeight:
                    isSelected ? kFontWeightSemiBold : kFontWeightMedium,
                color: color,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUnlocked = context.watch<FeatureUnlockProvider>().isUnlocked;
    final effectiveIndex =
        (!isUnlocked && (_selectedIndex == 1 || _selectedIndex == 2))
            ? 0
            : _selectedIndex;
    return Scaffold(
      body: Column(
        children: [
          // Investor mode banner (only shown when logged in with investor password)
          Consumer<InvestorModeProvider>(
            builder: (context, investor, _) {
              if (!investor.isInvestor) return const SizedBox.shrink();
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                color: const Color(0xFF64748B),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.lock_outline, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Investor Mode (Read Only)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: kFontFamily,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Expanded(child: _pages[effectiveIndex]),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(kIconWatchlist, 'Watchlist', 0),
                if (isUnlocked) _buildNavItem(kIconOrders, 'Orders', 1),
                if (isUnlocked) _buildNavItem(kIconHistory, 'History', 2),
                _buildNavItem(kIconProfile, 'Profile', 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
