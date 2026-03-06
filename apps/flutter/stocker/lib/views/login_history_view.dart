import 'package:flutter/material.dart';

class LoginHistoryView extends StatelessWidget {
  const LoginHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.arrow_back,
                        size: 24, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(width: 16),
                  const Text(
                    'Login History',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 24,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.search,
                          size: 24, color: const Color(0xFF8E8E93)),
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
                  Icon(Icons.filter_list,
                      size: 24, color: const Color(0xFF8E8E93)),
                ],
              ),
            ),

            SizedBox(height: 24),

            // Table Headers
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'USERNAME',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'DATE & TIME',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 6),

            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  itemCount: 10,
                  itemBuilder: (context, index) => _buildHistoryRow(
                    isFirst: index == 0,
                    isLast: index == 9,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryRow({bool isFirst = false, bool isLast = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: !isLast
            ? const Border(
                bottom: BorderSide(width: 1, color: Color(0xFFF1F5F9)),
              )
            : null,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'USERNAME',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(
            child: Text(
              '12/12/12 12:43:56',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
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
