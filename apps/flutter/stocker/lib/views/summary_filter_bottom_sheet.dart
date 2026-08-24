import 'package:flutter/material.dart';
import '../utils/contants.dart';

class SummaryFilterBottomSheet extends StatefulWidget {
  const SummaryFilterBottomSheet({super.key});

  @override
  State<SummaryFilterBottomSheet> createState() => _SummaryFilterBottomSheetState();
}

class _SummaryFilterBottomSheetState extends State<SummaryFilterBottomSheet> {
  int _selectedTabIndex = 2; // Credit is selected by default

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 56),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Text(
            'Summary Filter',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black,
              fontSize: kFontSizeSheetTitle,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),

          SizedBox(height: 16),

          // Date Range Picker
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'From - To Date',
                  style: TextStyle(
                    color: const Color(0xFF8E8E93),
                    fontSize: kFontSizeSheetHint,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                Icon(Icons.calendar_today, size: kIconSizeMedium, color: const Color(0xFF222222)),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Select Item Dropdown
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
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
                    fontSize: kFontSizeSheetHint,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightRegular,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: const Color(0xFF8E8E93)),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Tab Buttons (P&L, Brk, Credit)
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTabIndex = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    decoration: ShapeDecoration(
                      color: _selectedTabIndex == 0 ? kBrandPrimary : Colors.white,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(width: 1, color: kBrandPrimary),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(8),
                          bottomLeft: Radius.circular(8),
                        ),
                      ),
                    ),
                    child: Text(
                      'P&L',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedTabIndex == 0 ? Colors.white : const Color(0xFF333333),
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTabIndex = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    decoration: ShapeDecoration(
                      color: _selectedTabIndex == 1 ? kBrandPrimary : Colors.white,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(width: 1, color: kBrandPrimary),
                      ),
                    ),
                    child: Text(
                      'Brk',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedTabIndex == 1 ? Colors.white : const Color(0xFF333333),
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTabIndex = 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                    decoration: ShapeDecoration(
                      color: _selectedTabIndex == 2 ? kBrandPrimary : Colors.white,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(width: 1, color: kBrandPrimary),
                        borderRadius: BorderRadius.only(
                          topRight: Radius.circular(8),
                          bottomRight: Radius.circular(8),
                        ),
                      ),
                    ),
                    child: Text(
                      'Credit',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _selectedTabIndex == 2 ? Colors.white : const Color(0xFF333333),
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: 16),

          // Action Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Clear filter logic
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFD1D1D6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'CLEAR',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeButtonText,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Apply filter and close
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: kBrandPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'VIEW',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: kFontSizeButtonText,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                      ),
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
}
