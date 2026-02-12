import 'package:flutter/material.dart';
import 'history_filter_sheet.dart';
import 'trade_detail_sheet.dart';

class PortfolioPage extends StatefulWidget {
  const PortfolioPage({super.key});

  @override
  State<PortfolioPage> createState() => _PortfolioPageState();
}

class _PortfolioPageState extends State<PortfolioPage> with SingleTickerProviderStateMixin {
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
                  side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
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
                  GestureDetector(
                    onTap: () {
                      showPortfolioFilterSheet(context);
                    },
                    child: Icon(Icons.filter_list, color: const Color(0xFF8E8E93)),
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
                          color: _tabController.index == 0 ? const Color(0xFF22547C) : Colors.transparent,
                          border: Border.all(width: 1, color: const Color(0xFF22547C)),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Trade',
                            style: TextStyle(
                              color: _tabController.index == 0 ? Colors.white : const Color(0xFF333333),
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
                          color: _tabController.index == 1 ? const Color(0xFF22547C) : Colors.transparent,
                          border: Border.all(width: 1, color: const Color(0xFF22547C)),
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Orders',
                            style: TextStyle(
                              color: _tabController.index == 1 ? Colors.white : const Color(0xFF333333),
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

            SizedBox(height: 16),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTradeView(),
                  _buildOrdersView(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTradeView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: 4,
        separatorBuilder: (context, index) => SizedBox(height: 4),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => showTradeDetailSheet(context),
            child: Container(
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: BorderSide(width: 1, color: const Color(0xFFF2F2F7)),
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
                                SizedBox(width: 8),
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFFD1D1D6),
                                    shape: OvalBorder(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'JAN 27',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'BUY: 2500 QTY',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
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
                            '59854.52',
                            style: TextStyle(
                              color: const Color(0xFFFF3B30),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: const Color(0xFF8E8E93)),
                              SizedBox(width: 4),
                              Text(
                                '19 JAN 12:45:00 PM',
                                style: TextStyle(
                                  color: const Color(0xFF8E8E93),
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
                  decoration: ShapeDecoration(
                    color: const Color(0xFFF2F2F7),
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
                          Icon(Icons.person, size: 16, color: Colors.black),
                          SizedBox(width: 6),
                          Text(
                            'Username',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text(
                            'Deals: -520.50',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Duration',
                        style: TextStyle(
                          color: const Color(0xFF22547C),
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
        },
      ),
    );
  }

  Widget _buildOrdersView() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: 4,
        separatorBuilder: (context, index) => SizedBox(height: 4),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => showTradeDetailSheet(context),
            child: Container(
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: BorderSide(width: 1, color: const Color(0xFFF2F2F7)),
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
                                SizedBox(width: 8),
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFFD1D1D6),
                                    shape: OvalBorder(),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'JAN 27',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 14,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'BUY: 2500 QTY',
                              style: TextStyle(
                                color: const Color(0xFF8E8E93),
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
                            '59854.52',
                            style: TextStyle(
                              color: const Color(0xFFFF3B30),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.access_time, size: 16, color: const Color(0xFF8E8E93)),
                              SizedBox(width: 4),
                              Text(
                                '19 JAN 12:45:00 PM',
                                style: TextStyle(
                                  color: const Color(0xFF8E8E93),
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
                  decoration: ShapeDecoration(
                    color: const Color(0xFFF2F2F7),
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
                          Icon(Icons.person, size: 16, color: Colors.black),
                          SizedBox(width: 6),
                          Text(
                            'Username',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text(
                            'Deals: -520.50',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        'Duration',
                        style: TextStyle(
                          color: const Color(0xFF22547C),
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
        },
      ),
    );
  }
}
