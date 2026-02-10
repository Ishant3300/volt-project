import 'package:flutter/material.dart';

class SetQuantityValuesView extends StatelessWidget {
  const SetQuantityValuesView({super.key});

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
                    child: Icon(Icons.arrow_back, size: 24, color: Colors.black),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Set Quantity Values',
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

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildQuantityRow('2', '5'),
                    SizedBox(height: 12),
                    _buildQuantityRow('10', '50'),
                    SizedBox(height: 12),
                    _buildQuantityRow('100', '200'),
                    SizedBox(height: 12),
                    _buildQuantityRow('500', '1000'),
                    SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF22547C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'ADD BOX',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom buttons
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: ShapeDecoration(
                        color: const Color(0xFFD1D1D6),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'RESET',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF22547C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'UPDATE',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityRow(String value1, String value2) {
    return Row(
      children: [
        Expanded(child: _buildQuantityBox(value1)),
        SizedBox(width: 13),
        Expanded(child: _buildQuantityBox(value2)),
      ],
    );
  }

  Widget _buildQuantityBox(String value) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Center(
        child: Text(
          value,
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
