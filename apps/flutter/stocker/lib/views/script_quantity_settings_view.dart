import 'package:flutter/material.dart';

class ScriptQuantitySettingsView extends StatefulWidget {
  const ScriptQuantitySettingsView({super.key});

  @override
  State<ScriptQuantitySettingsView> createState() => _ScriptQuantitySettingsViewState();
}

class _ScriptQuantitySettingsViewState extends State<ScriptQuantitySettingsView> {
  int _selectedItemIndex = 2;

  final List<Map<String, dynamic>> _scriptItems = [
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': false},
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': false},
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': true},
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': false},
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': false},
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': false},
    {'name': 'ADANIENSOL', 'lotSize': '500.00', 'brkQty': '500.00', 'qtyMax': '500.00', 'isSelected': false},
  ];

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
                    'Script Quantity Setting',
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

            // Search Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 24, color: const Color(0xFF8E8E93)),
                  SizedBox(width: 10),
                  Text(
                    'Search script',
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

            // Action Buttons Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: ShapeDecoration(
                      color: const Color(0xFFE5E5EA),
                      shape: OvalBorder(),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Max Qty',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Breakup',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 7),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF22547C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'APPLY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
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

            // Script Items List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _scriptItems.length,
                itemBuilder: (context, index) {
                  final item = _scriptItems[index];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        for (int i = 0; i < _scriptItems.length; i++) {
                          _scriptItems[i]['isSelected'] = false;
                        }
                        _scriptItems[index]['isSelected'] = true;
                        _selectedItemIndex = index;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                          borderRadius: index == 0
                              ? BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  topRight: Radius.circular(12),
                                )
                              : index == _scriptItems.length - 1
                                  ? BorderRadius.only(
                                      bottomLeft: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                    )
                                  : BorderRadius.zero,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: ShapeDecoration(
                              color: item['isSelected'] ? const Color(0xFF22547C) : const Color(0xFFE5E5EA),
                              shape: OvalBorder(),
                            ),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      item['name'],
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Last Update: 21/12/2026 5:23:00',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Opacity(
                                        opacity: 0.80,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: ShapeDecoration(
                                            color: const Color(0xFFE5E5EA),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'Lot size ',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 10,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Text(
                                                item['lotSize'],
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 12,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Opacity(
                                        opacity: 0.80,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: ShapeDecoration(
                                            color: const Color(0xFFE5E5EA),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: Row(
                                            children: [
                                              Text(
                                                'Brk Qty ',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 10,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Flexible(
                                                child: Text(
                                                  item['brkQty'],
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 12,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Expanded(
                                      child: Opacity(
                                        opacity: 0.80,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: ShapeDecoration(
                                            color: const Color(0xFFE5E5EA),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                          ),
                                          child: Row(
                                            children: [
                                              Text(
                                                'Qty Max ',
                                                style: TextStyle(
                                                  color: Colors.black,
                                                  fontSize: 10,
                                                  fontFamily: 'Inter',
                                                  fontWeight: FontWeight.w400,
                                                ),
                                              ),
                                              Flexible(
                                                child: Text(
                                                  item['qtyMax'],
                                                  style: TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 12,
                                                    fontFamily: 'Inter',
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
