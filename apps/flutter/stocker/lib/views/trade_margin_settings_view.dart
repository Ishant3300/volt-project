import 'package:flutter/material.dart';

class TradeMarginSettingsView extends StatefulWidget {
  const TradeMarginSettingsView({super.key});

  @override
  State<TradeMarginSettingsView> createState() => _TradeMarginSettingsViewState();
}

class _TradeMarginSettingsViewState extends State<TradeMarginSettingsView> {
  int _selectedItemIndex = 1;
  final TextEditingController _amountController = TextEditingController();

  final List<Map<String, dynamic>> _tradeMarginItems = [
    {'name': 'Astral', 'value': '5.0', 'isSelected': false},
    {'name': 'BajajFinance', 'value': '5.0', 'isSelected': true},
    {'name': 'CholaFin', 'value': '5.0', 'isSelected': false},
    {'name': 'HCL', 'value': '5.0', 'isSelected': false},
    {'name': 'Hinda', 'value': '5.0', 'isSelected': false},
    {'name': 'Coforge', 'value': '5.0', 'isSelected': false},
    {'name': 'Kotak Bank', 'value': '5.0', 'isSelected': false},
    {'name': 'HDFC', 'value': '5.0', 'isSelected': false},
  ];

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

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
                    'Trade Margin Setting',
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

            // Two Dropdowns Side by Side
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
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
                          Icon(Icons.keyboard_arrow_down, color: const Color(0xFF8E8E93)),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 13),
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
                          Icon(Icons.keyboard_arrow_down, color: const Color(0xFF8E8E93)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 8),

            // Amount Input and Apply Button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                      ),
                      child: TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Amount',
                          hintStyle: TextStyle(
                            color: const Color(0xFF8E8E93),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      String amount = _amountController.text;
                      if (amount.isNotEmpty) {
                        print('Applied amount: $amount');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF22547C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                      ),
                      child: Text(
                        'APPLY',
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
                ],
              ),
            ),

            SizedBox(height: 16),

            // Header Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 2, color: const Color(0xFF8E8E93)),
                            borderRadius: BorderRadius.circular(44),
                          ),
                        ),
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Script Name',
                        style: TextStyle(
                          color: const Color(0xFF8E8E93),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Trade Margin',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: const Color(0xFF8E8E93),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 12),

            // Trade Margin Items List
            Expanded(
              child: ListView.builder(
                itemCount: _tradeMarginItems.length,
                itemBuilder: (context, index) {
                  final item = _tradeMarginItems[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        for (int i = 0; i < _tradeMarginItems.length; i++) {
                          _tradeMarginItems[i]['isSelected'] = false;
                        }
                        _tradeMarginItems[index]['isSelected'] = true;
                        _selectedItemIndex = index;
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: ShapeDecoration(
                                  color: item['isSelected'] ? const Color(0xFF22547C) : Colors.white,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      width: 2,
                                      color: item['isSelected'] ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                                    ),
                                    borderRadius: BorderRadius.circular(44),
                                  ),
                                ),
                                child: item['isSelected']
                                    ? Icon(Icons.check, size: 12, color: Colors.white)
                                    : null,
                              ),
                              SizedBox(width: 7),
                              Text(
                                item['name'],
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            item['value'],
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
