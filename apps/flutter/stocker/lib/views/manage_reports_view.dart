import 'package:flutter/material.dart';

class ManageReportsView extends StatelessWidget {
  const ManageReportsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
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
                      'Manage Reports',
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

              SizedBox(height: 16),

              // Select User/Master
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select User/Master',
                      style: TextStyle(
                        color: const Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(width: 1, color: const Color(0xFFD1D1D6)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select Item',
                            style: TextStyle(
                              color: const Color(0xFF8E8E93),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Search
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search, color: const Color(0xFF8E8E93)),
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
              ),

              SizedBox(height: 16),

              // Report toggles
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildToggleItem('Account Summary', false),
                    SizedBox(height: 16),
                    _buildToggleItem('P&L Summary', true),
                    SizedBox(height: 16),
                    _buildToggleItem('Client Summary', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Settlement Report', true),
                    SizedBox(height: 16),
                    _buildToggleItem('Generate PDF', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Weekly Admin', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Intraday History', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Userwise Open Position', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Script Quantity', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Deleted Trade', false),
                    SizedBox(height: 16),
                    _buildToggleItem('Trade Account', false),
                  ],
                ),
              ),

              SizedBox(height: 40),
            ],
          ),
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
          decoration: BoxDecoration(
            color: isEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
            borderRadius: BorderRadius.circular(12.5),
          ),
          child: Align(
            alignment: isEnabled ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
