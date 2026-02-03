import 'package:flutter/material.dart';

class BrokerageSettingsView extends StatefulWidget {
  const BrokerageSettingsView({super.key});

  @override
  State<BrokerageSettingsView> createState() => _BrokerageSettingsViewState();
}

class _BrokerageSettingsViewState extends State<BrokerageSettingsView> {
  int _selectedTabIndex = 0;
  int _selectedItemIndex = 1;
  final TextEditingController _amountController = TextEditingController();

  final List<Map<String, dynamic>> _brokerageItems = [
    {'name': '3600NE', 'value': '5.0', 'isSelected': false},
    {'name': '3600NE', 'value': '5.0', 'isSelected': true},
    {'name': '3600NE', 'value': '5.0', 'isSelected': false},
    {'name': '3600NE', 'value': '5.0', 'isSelected': false},
    {'name': '3600NE', 'value': '5.0', 'isSelected': false},
    {'name': '3600NE', 'value': '5.0', 'isSelected': false},
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
                    'Brokerage Setting',
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

            // Tab buttons
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 0 ? const Color(0xFF22547C) : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFF22547C)),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                        ),
                        child: Text(
                          'Turnover Wise',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 0 ? Colors.white : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
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
                          color: _selectedTabIndex == 1 ? const Color(0xFF22547C) : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFF22547C)),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                        ),
                        child: Text(
                          'Lot Wise',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 1 ? Colors.white : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Select Exchange Dropdown
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
                    'Select Exchange',
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
                          borderRadius: BorderRadius.circular(8),
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
                  SizedBox(width: 13),
                  GestureDetector(
                    onTap: () {
                      // Handle apply logic
                      String amount = _amountController.text;
                      if (amount.isNotEmpty) {
                        print('Applied amount: $amount');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF22547C),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    'Brk Value',
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

            // Brokerage Items List
            Expanded(
              child: ListView.builder(
                itemCount: _brokerageItems.length,
                itemBuilder: (context, index) {
                  final item = _brokerageItems[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        for (int i = 0; i < _brokerageItems.length; i++) {
                          _brokerageItems[i]['isSelected'] = false;
                        }
                        _brokerageItems[index]['isSelected'] = true;
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
