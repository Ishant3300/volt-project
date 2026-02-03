import 'package:flutter/material.dart';

class EditUserView extends StatelessWidget {
  const EditUserView({super.key});

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
                    'Update User',
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 8),

                    // User Type
                    Text(
                      'User Type',
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
                          Icon(Icons.keyboard_arrow_down, size: 24, color: Colors.black),
                        ],
                      ),
                    ),

                    SizedBox(height: 24),

                    // PERSONAL DETAILS
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name
                          Text(
                            'Name',
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

                          SizedBox(height: 16),

                          // Username
                          Text(
                            'Username',
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

                          SizedBox(height: 16),

                          // Credit
                          Text(
                            'Credit',
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

                          SizedBox(height: 16),

                          // Note/Remark
                          Text(
                            'Note/Remark',
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
                      ),
                    ),

                    SizedBox(height: 24),

                    // EXCHANGE DETAIL
                    Text(
                      'EXCHANGE DETAIL',
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Column(
                        children: List.generate(5, (index) => _buildExchangeRow()).expand((widget) => [widget, SizedBox(height: 16)]).toList()..removeLast(),
                      ),
                    ),

                    SizedBox(height: 24),

                    // HIGH LOW BETWEEN TRADE LIMIT
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

                    SizedBox(height: 16),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildExchangeChip('NSE')),
                              SizedBox(width: 8),
                              Expanded(child: _buildExchangeChip('MCX')),
                            ],
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildExchangeChip('SGX')),
                              SizedBox(width: 8),
                              Expanded(child: _buildExchangeChip('CALLPUT')),
                            ],
                          ),
                          SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: _buildExchangeChip('OTHERS')),
                              SizedBox(width: 8),
                              Expanded(child: _buildExchangeChip('MCX-OPT')),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 24),

                    // UPDATE Button
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF22547C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'UPDATE',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExchangeRow() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.check_box_outline_blank, size: 24, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'NSE',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.check_box_outline_blank, size: 24, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'Turnover',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.check_box_outline_blank, size: 24, color: Colors.black),
                  SizedBox(width: 8),
                  Text(
                    'Lot',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: 12),
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
              Icon(Icons.keyboard_arrow_down, size: 24, color: Colors.black),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildExchangeChip(String label) {
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_box_outline_blank, size: 24, color: Colors.black),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
