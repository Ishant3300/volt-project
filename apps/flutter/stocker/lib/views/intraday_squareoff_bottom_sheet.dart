import 'package:flutter/material.dart';

class IntradaySquareoffBottomSheet extends StatefulWidget {
  const IntradaySquareoffBottomSheet({super.key});

  @override
  State<IntradaySquareoffBottomSheet> createState() => _IntradaySquareoffBottomSheetState();
}

class _IntradaySquareoffBottomSheetState extends State<IntradaySquareoffBottomSheet> {
  bool _nseEnabled = false;
  bool _mcxEnabled = true;
  bool _mcxOptEnabled = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 24,
        left: 16,
        right: 16,
        bottom: 56,
      ),
      decoration: const ShapeDecoration(
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
          // Header
          Container(
            width: double.infinity,
            child: Row(
              children: [
                Text(
                  'Intraday SquareOff Settings',
                  textAlign: TextAlign.center,
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

          SizedBox(height: 16),

          // Toggle Section
          Container(
            width: double.infinity,
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Column(
              children: [
                // NSE Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'NSE',
                      style: TextStyle(
                        color: const Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _nseEnabled = !_nseEnabled),
                      child: Container(
                        width: 40,
                        height: 25,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: ShapeDecoration(
                          color: _nseEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.50),
                          ),
                        ),
                        child: Align(
                          alignment: _nseEnabled ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: 23,
                            height: 23,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: OvalBorder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24),

                // MCX Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MCX',
                      style: TextStyle(
                        color: const Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _mcxEnabled = !_mcxEnabled),
                      child: Container(
                        width: 40,
                        height: 25,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: ShapeDecoration(
                          color: _mcxEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.50),
                          ),
                        ),
                        child: Align(
                          alignment: _mcxEnabled ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: 23,
                            height: 23,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: OvalBorder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: 24),

                // MCX-OPT Toggle
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'MCX-OPT',
                      style: TextStyle(
                        color: const Color(0xFF2B2B2B),
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _mcxOptEnabled = !_mcxOptEnabled),
                      child: Container(
                        width: 40,
                        height: 25,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: ShapeDecoration(
                          color: _mcxOptEnabled ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.50),
                          ),
                        ),
                        child: Align(
                          alignment: _mcxOptEnabled ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: 23,
                            height: 23,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: OvalBorder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 16),

          // Buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                    decoration: ShapeDecoration(
                      color: const Color(0xFFD1D1D6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text(
                      'CLOSE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Handle update logic here
                    print('NSE: $_nseEnabled, MCX: $_mcxEnabled, MCX-OPT: $_mcxOptEnabled');
                    Navigator.pop(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
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
              ),
            ],
          ),
        ],
      ),
    );
  }
}
