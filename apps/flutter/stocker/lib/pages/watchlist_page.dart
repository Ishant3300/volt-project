import 'package:flutter/material.dart';
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

            // Watchlist items
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: 6,
                  separatorBuilder: (context, index) => Divider(height: 1, color: const Color(0xFFD1D1D6)),
                  itemBuilder: (context, index) {
                    bool isNegative = index % 2 == 0;
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TradeCardPage()),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'BANK NIFTY',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 14,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
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
                                        'JAN 27',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 12,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        isNegative ? Icons.arrow_downward : Icons.arrow_upward,
                                        size: 16,
                                        color: isNegative ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        isNegative ? '-456(-70%)' : '35(45%)',
                                        style: TextStyle(
                                          color: isNegative ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
                                          fontSize: 14,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.trending_up, size: 14, color: Colors.black),
                                      SizedBox(width: 2),
                                      Text(
                                        '59854',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 13,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: ShapeDecoration(
                                          color: const Color(0xFF34C759),
                                          shape: OvalBorder(),
                                        ),
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        '59854',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontSize: 13,
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
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: ShapeDecoration(
                                          shape: RoundedRectangleBorder(
                                            side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                                          ),
                                        ),
                                        child: Text(
                                          'L: 59542',
                                          style: TextStyle(
                                            color: const Color(0xFF999999),
                                            fontSize: 11,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 4),
                                      Text(
                                        'H: 59542',
                                        style: TextStyle(
                                          color: const Color(0xFF999999),
                                          fontSize: 11,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w400,
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
                    );
                  },
                ),
              ),
            ),
            
            SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
