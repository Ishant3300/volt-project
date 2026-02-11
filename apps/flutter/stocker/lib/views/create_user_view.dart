import 'package:flutter/material.dart';

class CreateUserView extends StatelessWidget {
  const CreateUserView({super.key});

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
              child: Text(
                'Create User',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 16,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Form content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Type
                    _buildDropdownField('User Type'),
                    SizedBox(height: 27),

                    // Personal Details Section
                    Text(
                      'PERSONAL DETAILS',
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: [
                          _buildTextField('Name'),
                          SizedBox(height: 16),
                          _buildTextField('Username'),
                          SizedBox(height: 16),
                          _buildTextField('Password'),
                          SizedBox(height: 16),
                          _buildTextField('Confirm Password'),
                          SizedBox(height: 16),
                          _buildTextField('Credit'),
                          SizedBox(height: 16),
                          _buildTextField('Note/Remark'),
                        ],
                      ),
                    ),
                    SizedBox(height: 27),

                    // Partnership Share Detail
                    Text(
                      'PARTNERSHIP SHARE DETAIL',
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 16),
                    _buildShareSection('Profit & Loss sharing'),
                    SizedBox(height: 16),
                    _buildShareSection('BRK SHARING'),
                    SizedBox(height: 27),

                    // Exchange Allow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'EXCHANGE ALLOW',
                          style: TextStyle(
                            color: const Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(Icons.add, size: 24, color: Colors.black),
                      ],
                    ),
                    SizedBox(height: 11),
                    _buildExchangeGrid(),
                    SizedBox(height: 27),

                    // High Low Between Trade Limit
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'HIGH LOW BETWEEN TRADE LIMIT',
                          style: TextStyle(
                            color: const Color(0xFF8E8E93),
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(Icons.add, size: 24, color: Colors.black),
                      ],
                    ),
                    SizedBox(height: 11),
                    _buildExchangeGrid(),
                    SizedBox(height: 27),
                  ],
                ),
              ),
            ),

            // Create User Button
            Container(
              margin: const EdgeInsets.all(16),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              decoration: ShapeDecoration(
                color: const Color(0xFF22547C),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                'CREATE USER',
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
    );
  }

  Widget _buildDropdownField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              borderRadius: BorderRadius.circular(8),
            ),
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
              Icon(Icons.arrow_drop_down, color: const Color(0xFF8E8E93)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            'Placeholder',
            style: TextStyle(
              color: const Color(0xFF8E8E93),
              fontSize: 16,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildShareSection(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Placeholder',
              style: TextStyle(
                color: const Color(0xFF8E8E93),
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Placeholder',
                    style: TextStyle(
                      color: const Color(0xFF8E8E93),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Placeholder',
                    style: TextStyle(
                      color: const Color(0xFF8E8E93),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeGrid() {
    final exchanges = ['NSE', 'MCX', 'SGX', 'CALLPUT', 'OTHERS', 'MCX-OPT'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildExchangeItem(exchanges[0])),
              SizedBox(width: 8),
              Expanded(child: _buildExchangeItem(exchanges[1])),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildExchangeItem(exchanges[2])),
              SizedBox(width: 8),
              Expanded(child: _buildExchangeItem(exchanges[3])),
            ],
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildExchangeItem(exchanges[4])),
              SizedBox(width: 8),
              Expanded(child: _buildExchangeItem(exchanges[5])),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExchangeItem(String name) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.check_box_outline_blank, size: 24, color: Colors.black),
          SizedBox(width: 10),
          Text(
            name,
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
