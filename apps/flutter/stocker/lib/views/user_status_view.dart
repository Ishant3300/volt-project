import 'package:flutter/material.dart';
import '../utils/contants.dart';

class UserStatusView extends StatelessWidget {
  const UserStatusView({super.key});

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
                    child: Icon(Icons.arrow_back, size: kIconSizeLarge, color: Colors.black),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'User Status',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                ],
              ),
            ),

            // List of users
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: List.generate(
                  15,
                  (index) => _buildUserCard(
                    'DEMO1NISHIT',
                    index == 3 ? false : true,
                    '15,251',
                    '15,251',
                    '15.6%',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(String name, bool isActive, String balance, String credit, String plShare) {
    return Container(
      margin: const EdgeInsets.only(bottom: 1),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isActive ? 'ACTIVE' : 'INACTIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: kFontSizeCaption,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightRegular,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'BALANCE: $balance',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
              Text(
                'CREDIT: $credit',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
              Text(
                'PL SHARE: $plShare',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
