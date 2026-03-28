import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

class _MyHomePageState extends State<MyHomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    const WatchlistPage(),
    const OrdersPage(),
    const PortfolioPage(),
    const ProfilePage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildNavItem(String svgPath, String label, int index) {
    final bool isSelected = _selectedIndex == index;
    final color = isSelected ? const Color(0xFF3F45C7) : const Color(0xFF94A3B8);
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3F45C7).withValues(alpha: 0.08) : Colors.transparent,
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
                fontFamily: 'Inter',
                fontSize: kFontSizeNavLabel,
                fontWeight: isSelected ? kFontWeightSemiBold : kFontWeightMedium,
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
    return Scaffold(
      body: _pages[_selectedIndex],
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
                _buildNavItem(kIconOrders, 'Orders', 1),
                _buildNavItem(kIconHistory, 'History', 2),
                _buildNavItem(kIconProfile, 'Profile', 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
