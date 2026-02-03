import 'package:flutter/material.dart';
import 'userwise_position_filter_bottom_sheet.dart';

class UpperwisePositionView extends StatelessWidget {
  const UpperwisePositionView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.arrow_back, color: Colors.black),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Userwise Position',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search, size: 24, color: const Color(0xFF8E8E93)),
                      SizedBox(width: 10),
                      Text(
                        'Search users',
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const UserwisePositionFilterBottomSheet(),
                      );
                    },
                    child: Icon(Icons.filter_list, size: 24, color: const Color(0xFF8E8E93)),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Position Cards List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 3,
                separatorBuilder: (context, index) => SizedBox(height: 8),
                itemBuilder: (context, index) => _buildPositionCard(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPositionCard(int index) {
    final isLoss = index == 0;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'NSE ADANI 27 JAN 2026',
                style: TextStyle(
                  color: const Color(0xFF22547C),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: ShapeDecoration(
                  color: isLoss ? const Color(0xFFFF3B30) : const Color(0xFF34C759),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
                child: Text(
                  isLoss ? '-22542.251' : '+15420.50',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 8),

          // Details Grid
          Container(
            decoration: ShapeDecoration(
              shape: RoundedRectangleBorder(
                side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildDetailCell('USERNAME', 'YASH11', hasBorder: true)),
                    Expanded(child: _buildDetailCell('P&L', '-25%', hasBorder: false, isRed: isLoss)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildDetailCell('POSITION', 'BUY', hasBorder: true)),
                    Expanded(child: _buildDetailCell('OPEN QUANTITY', '100.00', hasBorder: false, isBlue: true)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildDetailCell('MARGIN USED', '322541.5', hasBorder: true, isLast: true)),
                    Expanded(child: _buildDetailCell('AVG RATE', '2099.5', hasBorder: false, isLast: true)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCell(String label, String value, {required bool hasBorder, bool isLast = false, bool isRed = false, bool isBlue = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          side: hasBorder && !isLast ? BorderSide(width: 1, color: const Color(0xFFD1D1D6)) : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF8E8E93),
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isRed ? const Color(0xFFFF3B30) : isBlue ? const Color(0xFF22547C) : Colors.black,
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
