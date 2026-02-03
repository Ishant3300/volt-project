import 'package:flutter/material.dart';

class AccountDetailView extends StatelessWidget {
  const AccountDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(17),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Account Detail',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Icon(Icons.close, color: Colors.black),
                ],
              ),
            ),

            // Security notice
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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

            SizedBox(height: 16),

            // Account details card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Username', 'Demonishit', true),
                  _buildDetailRow('Server Name', 'MoneyStock', true),
                  _buildDetailRow('Device Name', 'iPhone11', true),
                  _buildDetailRow('Device Version', '18.5', true),
                  _buildDetailRow('Last Logged', '27/01/2026 5:35:45 PM', true),
                  _buildDetailRow('App Version', '2.1.2', false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool showBorder) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: showBorder
            ? Border(
                bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              )
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          Text(
            value,
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
