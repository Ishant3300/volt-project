import 'package:flutter/material.dart';
import '../utils/contants.dart';

class TermsView extends StatelessWidget {
  const TermsView({super.key});

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
                    'Rules And Regulations',
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
                  child: Text(
                    'This application is for Educational perpose only.\n\nThis application is not providing tips, news or any information which related to influence.\n\nThere are no monetary transactions involved in this.',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeBody,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightRegular,
                      height: 1.43,
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
}
