import 'package:flutter/material.dart';
import 'edit_master_view.dart';

class MasterManagementView extends StatelessWidget {
  const MasterManagementView({super.key});

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
                    'Master Management',
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

            // List of masters
            Expanded(
              child: Builder(
                builder: (context) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildMasterCard(context, 'MS-INSHANT', true, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-JOHN', true, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-DOE', false, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-NISHIT', true, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-RAHUL', false, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-LAPTOP', true, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-YASH', false, '50,00,000', '15,251', '15.6%'),
                    _buildMasterCard(context, 'MS-KRISHNA', true, '15,251', '15,251', '15.6%'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasterCard(BuildContext context, String name, bool isActive, String balance, String credit, String plShare) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditMasterView(
              name: name,
              isActive: isActive,
              balance: balance,
              credit: credit,
              plShare: plShare,
            ),
          ),
        );
      },
      child: Container(
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
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
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
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
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
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'CREDIT: $credit',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'PL SHARE: $plShare',
                  style: TextStyle(
                    color: const Color(0xFF999999),
                    fontSize: 12,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
