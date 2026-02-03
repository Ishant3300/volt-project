import 'package:flutter/material.dart';

class ScriptQuantityDetailView extends StatelessWidget {
  const ScriptQuantityDetailView({super.key});

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
                    'Script Qty Details',
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
                        'Search script',
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.filter_list, size: 24, color: const Color(0xFF8E8E93)),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Script Cards List
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 5,
                separatorBuilder: (context, index) => SizedBox(height: 8),
                itemBuilder: (context, index) => _buildScriptCard(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScriptCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Script Name
          Text(
            'NSE ADANIENT 27 JAN 2026',
            style: TextStyle(
              color: const Color(0xFF22547C),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
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
                    Expanded(child: _buildDetailCell('BRK QTY', '100', hasBorder: true)),
                    Expanded(child: _buildDetailCell('QTY MAX', '500', hasBorder: false)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(child: _buildDetailCell('LOT SIZE', '25', hasBorder: true, isLast: true)),
                    Expanded(child: _buildDetailCell('EXCHANGE', 'NSE', hasBorder: false, isLast: true)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailCell(String label, String value, {required bool hasBorder, bool isLast = false}) {
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
              color: Colors.black,
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
