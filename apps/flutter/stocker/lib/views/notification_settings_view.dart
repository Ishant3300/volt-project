import 'package:flutter/material.dart';

class NotificationSettingsView extends StatelessWidget {
  const NotificationSettingsView({super.key});

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
                    'Notification Setting',
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
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildToggleItem('Market Order', false),
                      SizedBox(height: 16),
                      _buildToggleItem('Pending Order', true),
                      SizedBox(height: 16),
                      _buildToggleItem('Execute Pending Order', false),
                      SizedBox(height: 16),
                      _buildToggleItem('Delete Pending Order', true),
                      SizedBox(height: 16),
                      _buildToggleItem('Trading Sound', false),
                    ],
                  ),
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

  Widget _buildToggleItem(String title, bool isEnabled) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: const Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        Container(
          width: 40,
          height: 25,
          padding: const EdgeInsets.all(2),
          decoration: ShapeDecoration(
            color: isEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.5),
            ),
          ),
          child: Align(
            alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 23,
              height: 23,
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: OvalBorder(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
