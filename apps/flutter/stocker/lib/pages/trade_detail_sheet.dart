import 'package:flutter/material.dart';

class TradeDetailSheet extends StatefulWidget {
  const TradeDetailSheet({super.key});

  @override
  State<TradeDetailSheet> createState() => _TradeDetailSheetState();
}

class _TradeDetailSheetState extends State<TradeDetailSheet> {
  int _selectedTab = 0; // 0: Detail, 1: Buy, 2: Sell

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(
        top: 24,
        left: 16,
        right: 16,
        bottom: 56,
      ),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'NSE CONCOR JAN 27',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '516.5',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFFF3B30),
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          // Tab selector
          Container(
            width: double.infinity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      decoration: ShapeDecoration(
                        color: _selectedTab == 0 ? const Color(0xFF22547C) : Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 1,
                            color: const Color(0xFF22547C),
                          ),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Detail',
                          style: TextStyle(
                            color: _selectedTab == 0 ? Colors.white : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      decoration: ShapeDecoration(
                        color: _selectedTab == 1 ? const Color(0xFF22547C) : Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 1,
                            color: const Color(0xFF22547C),
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Buy',
                          style: TextStyle(
                            color: _selectedTab == 1 ? Colors.white : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTab = 2),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                      decoration: ShapeDecoration(
                        color: _selectedTab == 2 ? const Color(0xFF22547C) : Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            width: 1,
                            color: const Color(0xFF22547C),
                          ),
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Sell',
                          style: TextStyle(
                            color: _selectedTab == 2 ? Colors.white : Colors.black,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            height: 1.25,
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
          if (_selectedTab == 0) _buildDetailTab(),
          if (_selectedTab == 1) _buildBuyTab(),
          if (_selectedTab == 2) _buildSellTab(),
          
          SizedBox(height: 16),

          // Close button
          Container(
            width: double.infinity,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                decoration: ShapeDecoration(
                  color: const Color(0xFFD1D1D6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Center(
                  child: Text(
                    'CLOSE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildDetailRow('Username', 'SGDEMO'),
        _buildDetailRow('Execution', '24 JAN 2026 | 10:32:45'),
        _buildDetailRow('Symbol', 'NSE 3600 JAN 27'),
        _buildDetailRow('Type', 'Buy/Market'),
        _buildDetailRow('Quantity', '500'),
        _buildDetailRow('Price', '1203.2'),
        _buildDetailRow('Deal', '0.0'),
        _buildDetailRow('Quantity', '200'),
        _buildDetailRow('Order Method', 'IOS'),
        _buildDetailRow('SquareOff Qty', '1.0'),
        _buildDetailRow('BRK', '117.5'),
        _buildDetailRow('Ref Price', '516'),
        _buildDetailRow('IP', '115.251.521.52'),
        _buildDetailRow('Device', '34439F37-85448-58F5541-5524'),
      ],
    );
  }

  Widget _buildBuyTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Buy badge and timestamp
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: ShapeDecoration(
                color: const Color(0xFF22547C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                'BUY: 500 QTY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  height: 1.67,
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: const Color(0xFF999999)),
                SizedBox(width: 4),
                Text(
                  '19 JAN 12:45:00 PM',
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
        SizedBox(height: 16),
        _buildDetailRow('Username', 'SGDEMO'),
        _buildDetailRow('Execution', '24 JAN 2026 | 10:32:45'),
        _buildDetailRow('Symbol', 'NSE 3600 JAN 27'),
        _buildDetailRow('Type', 'Buy/Market'),
        _buildDetailRow('Quantity', '500'),
        _buildDetailRow('Price', '1203.2'),
        _buildDetailRow('Deal', '0.0'),
        _buildDetailRow('Quantity', '200'),
        _buildDetailRow('Order Method', 'IOS'),
        _buildDetailRow('SquareOff Qty', '1.0'),
        _buildDetailRow('BRK', '117.5'),
        _buildDetailRow('Ref Price', '516'),
        _buildDetailRow('IP', '115.251.521.52'),
        _buildDetailRow('Device', '34439F37-85448-58F5541-5524'),
      ],
    );
  }

  Widget _buildSellTab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Sell badge and timestamp
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: ShapeDecoration(
                color: const Color(0xFFFF3B30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              ),
              child: Text(
                'SELL:200 QTY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                  height: 1.67,
                ),
              ),
            ),
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: const Color(0xFF999999)),
                SizedBox(width: 4),
                Text(
                  '19 JAN 12:45:00 PM',
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
        SizedBox(height: 16),
        _buildDetailRow('Username', 'SGDEMO'),
        _buildDetailRow('Execution', '24 JAN 2026 | 12:32:45'),
        _buildDetailRow('Symbol', 'NSE 3600 JAN 27'),
        _buildDetailRow('Type', 'Sell/Market'),
        _buildDetailRow('Quantity', '200'),
        _buildDetailRow('Price', '1452.50'),
        _buildDetailRow('Deal', '0.0'),
        _buildDetailRow('Quantity', '200'),
        _buildDetailRow('Order Method', 'IOS'),
        _buildDetailRow('SquareOff Qty', '1.0'),
        _buildDetailRow('BRK', '117.5'),
        _buildDetailRow('Ref Price', '516'),
        _buildDetailRow('IP', '115.251.521.52'),
        _buildDetailRow('Device', '34439F37-85448-58F5541-5524'),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            width: 1,
            color: const Color(0xFFE5E5EA),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showTradeDetailSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const TradeDetailSheet(),
  );
}
