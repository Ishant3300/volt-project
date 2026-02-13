import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'option_chain_view.dart';
import 'market_depth_sheet.dart';
import 'info_sheet.dart';

class TradeCardPage extends StatelessWidget {
  final WatchlistItem item;
  
  const TradeCardPage({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header with back button and stock info
              Consumer<WatchlistProvider>(
                builder: (context, provider, child) {
                  final currentItem = provider.getByToken(item.instrument.instrumentToken) ?? item;
                  final instrument = currentItem.instrument;
                  
                  return Container(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(44),
                              ),
                            ),
                            child: Icon(Icons.arrow_back, color: Colors.black),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                instrument.tradingsymbol,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if (instrument.expiry != null) ...[
                                SizedBox(height: 4),
                                Text(
                                  instrument.expiryDisplay,
                                  style: TextStyle(
                                    color: const Color(0xFF8E8E93),
                                    fontSize: 14,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              currentItem.currentPrice?.toStringAsFixed(2) ?? '0.00',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: currentItem.isPositive
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFFF3B30),
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              currentItem.changeDisplay,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: currentItem.isPositive
                                    ? const Color(0xFF34C759)
                                    : const Color(0xFFFF3B30),
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),

              // User selection dropdown
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'User',
                          style: TextStyle(
                            color: const Color(0xFF2B2B2B),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            showInfoSheet(context);
                          },
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: const Color(0xFF22547C)),
                              SizedBox(width: 4),
                              Text(
                                'Info',
                                style: TextStyle(
                                  color: const Color(0xFF22547C),
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
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
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: const Color(0xFF8E8E93)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Trading card
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(16),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Quantity section
                    Text(
                      'Quantity',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '5',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFF2F2F7),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                child: Icon(Icons.remove, size: 16),
                              ),
                              SizedBox(width: 11),
                              Container(
                                width: 32,
                                height: 32,
                                decoration: ShapeDecoration(
                                  color: const Color(0xFFF2F2F7),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                ),
                                child: Icon(Icons.add, size: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 12),
                    // Quick quantity buttons
                    Row(
                      children: [
                        _buildQuantityButton('100', true),
                        SizedBox(width: 6),
                        _buildQuantityButton('200', false),
                        SizedBox(width: 6),
                        _buildQuantityButton('500', false),
                        SizedBox(width: 6),
                        _buildQuantityButton('1000', false),
                      ],
                    ),
                    SizedBox(height: 14),

                    // Market Price
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Market Price',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Edit',
                          style: TextStyle(
                            color: const Color(0xFF22547C),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Text(
                        '59657.50',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    SizedBox(height: 14),

                    // Stop Loss
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Stop Loss',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Container(
                          width: 47,
                          height: 22,
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                          decoration: ShapeDecoration(
                            color: const Color(0xFF34C759),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(45),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 14,
                                height: 14,
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: OvalBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Trigger Price',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  '59657.50',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Limit Price',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: ShapeDecoration(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  '59657.50',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Market stats
              Consumer<WatchlistProvider>(
                builder: (context, provider, child) {
                  final currentItem = provider.getByToken(item.instrument.instrumentToken) ?? item;
                  
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildStatCard('OPEN', currentItem.currentPrice?.toStringAsFixed(2) ?? '0.00'),
                        SizedBox(width: 8),
                        _buildStatCard('LOW', currentItem.low?.toStringAsFixed(2) ?? '0.00'),
                        SizedBox(width: 8),
                        _buildStatCard('HIGH', currentItem.high?.toStringAsFixed(2) ?? '0.00'),
                        SizedBox(width: 8),
                        _buildStatCard('CLOSE', currentItem.currentPrice?.toStringAsFixed(2) ?? '0.00'),
                      ],
                    ),
                  );
                },
              ),

              SizedBox(height: 16),

              // Action links
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OptionChainView(
                              instrument: item.instrument,
                            ),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          Icon(Icons.link, size: 16, color: const Color(0xFF22547C)),
                          SizedBox(width: 4),
                          Text(
                            'Option Chain',
                            style: TextStyle(
                              color: const Color(0xFF22547C),
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.show_chart, size: 16, color: const Color(0xFF22547C)),
                        SizedBox(width: 4),
                        Text(
                          'View chart',
                          style: TextStyle(
                            color: const Color(0xFF22547C),
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        showMarketDepthSheet(context, item.instrument.instrumentToken);
                      },
                      child: Row(
                        children: [
                          Icon(Icons.layers, size: 16, color: const Color(0xFF22547C)),
                          SizedBox(width: 4),
                          Text(
                            'Market Depth',
                            style: TextStyle(
                              color: const Color(0xFF22547C),
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Buy/Sell buttons
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: ShapeDecoration(
                          color: const Color(0xFF22547C),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'BUY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 24),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: ShapeDecoration(
                          color: const Color(0xFFFF9500),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          'SELL',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityButton(String text, bool isSelected) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: ShapeDecoration(
          color: isSelected ? const Color(0xFF22547C) : const Color(0xFFC7C7CC),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? const Color(0xFFF9F9F9) : Colors.black,
            fontSize: 14,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(width: 1, color: const Color(0xFFE5E5EA)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF8E8E93),
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
            SizedBox(height: 6),
            Container(
              width: 25,
              height: 2,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
              ),
            ),
            SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
