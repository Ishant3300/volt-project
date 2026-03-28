import 'package:flutter/material.dart';
import '../utils/contants.dart';

class EditMasterView extends StatelessWidget {
  final String name;
  final bool isActive;
  final String balance;
  final String credit;
  final String plShare;

  const EditMasterView({
    super.key,
    required this.name,
    required this.isActive,
    required this.balance,
    required this.credit,
    required this.plShare,
  });

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
                    'Master Management',
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

            // Master details card
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: List.generate(
                      8,
                      (index) => _buildMasterCard(
                        index == 0 ? name : 'MS-${['JOHN', 'DOE', 'NISHIT', 'RAHUL', 'LAPTOP', 'YASH', 'KRISHNA'][index - 1]}',
                        index == 2 || index == 4 || index == 6 ? false : true,
                        index == 7 ? '15,251' : '50,00,000',
                        '15,251',
                        '15.6%',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterCard(String masterName, bool active, String bal, String cred, String pl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                masterName,
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
                  color: active ? const Color(0xFF34C759) : const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  active ? 'ACTIVE' : 'INACTIVE',
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
                'BALANCE: $bal',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
              Text(
                'CREDIT: $cred',
                style: TextStyle(
                  color: const Color(0xFF999999),
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                ),
              ),
              Text(
                'PL SHARE: $pl',
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
