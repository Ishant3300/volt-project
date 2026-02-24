import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'option_chain_view.dart';
import 'market_depth_sheet.dart';
import 'info_sheet.dart';

class TradeCardPage extends StatefulWidget {
  final WatchlistItem item;

  const TradeCardPage({super.key, required this.item});

  @override
  State<TradeCardPage> createState() => _TradeCardPageState();
}

class _TradeCardPageState extends State<TradeCardPage> {
  int _quantity = 100;
  int _selectedQuickQty = 100;
  static const List<int> _quickQuantities = [100, 200, 500, 1000, 2000, 5000];

  void _setQuantity(int qty) {
    setState(() {
      _quantity = qty;
      _selectedQuickQty = qty;
    });
  }

  void _incrementQuantity() {
    setState(() {
      _quantity++;
      _selectedQuickQty = _quickQuantities.contains(_quantity) ? _quantity : -1;
    });
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
        _selectedQuickQty = _quickQuantities.contains(_quantity) ? _quantity : -1;
      });
    }
  }

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
                  final currentItem =
                      provider.getByToken(widget.item.instrument.instrumentToken) ?? widget.item;
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
                            child: const Icon(Icons.arrow_back, color: Colors.black),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                instrument.tradingsymbol,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                              if (instrument.expiry != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  instrument.expiryDisplay,
                                  style: const TextStyle(
                                    color: Color(0xFF8E8E93),
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
                            const SizedBox(height: 4),
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
                        const Text(
                          'User',
                          style: TextStyle(
                            color: Color(0xFF2B2B2B),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => showInfoSheet(context),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, size: 20, color: Color(0xFF22547C)),
                              SizedBox(width: 4),
                              Text(
                                'Info',
                                style: TextStyle(
                                  color: Color(0xFF22547C),
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
                    const SizedBox(height: 8),
                    Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select Item',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

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
                    // Quantity label
                    const Text(
                      'Quantity',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 16,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quantity input with +/- buttons
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$_quantity',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                          ),
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _decrementQuantity,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFFF2F2F7),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4)),
                                  ),
                                  child: const Icon(Icons.remove, size: 16),
                                ),
                              ),
                              const SizedBox(width: 11),
                              GestureDetector(
                                onTap: _incrementQuantity,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFFF2F2F7),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4)),
                                  ),
                                  child: const Icon(Icons.add, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Quick quantity buttons
                    Row(
                      children: _quickQuantities.map((qty) {
                        final isSelected = _selectedQuickQty == qty;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => _setQuantity(qty),
                            child: Container(
                              margin: EdgeInsets.only(
                                left: qty == _quickQuantities.first ? 0 : 3,
                                right: qty == _quickQuantities.last ? 0 : 3,
                              ),
                              padding: const EdgeInsets.all(10),
                              decoration: ShapeDecoration(
                                color: isSelected
                                    ? const Color(0xFF22547C)
                                    : const Color(0xFFC7C7CC),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              child: Text(
                                '$qty',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFFF9F9F9)
                                      : Colors.black,
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // Price fields + action buttons
                    Consumer<WatchlistProvider>(
                      builder: (context, provider, child) {
                        final currentItem =
                            provider.getByToken(widget.item.instrument.instrumentToken) ??
                                widget.item;
                        final priceStr =
                            currentItem.currentPrice?.toStringAsFixed(2) ?? '0.00';

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sell side
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 46,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 13),
                                    decoration: ShapeDecoration(
                                      color: const Color(0xFFF2F2F7),
                                      shape: RoundedRectangleBorder(
                                        side: const BorderSide(
                                            width: 1, color: Color(0xFFC7C7CC)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Text(
                                      priceStr,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w500,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  GestureDetector(
                                    onTap: () {
                                      // TODO: handle sell
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 18),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFFF9500),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text(
                                        'SELL',
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
                            const SizedBox(width: 14),
                            // Buy/Place side
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 46,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 13),
                                    decoration: ShapeDecoration(
                                      color: const Color(0xFFF2F2F7),
                                      shape: RoundedRectangleBorder(
                                        side: const BorderSide(
                                            width: 1, color: Color(0xFFC7C7CC)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Text(
                                      priceStr,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 16,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w500,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  GestureDetector(
                                    onTap: () {
                                      // TODO: handle place/buy
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 18),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFF22547C),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8)),
                                      ),
                                      child: const Text(
                                        'PLACE',
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
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Market stats
              Consumer<WatchlistProvider>(
                builder: (context, provider, child) {
                  final currentItem =
                      provider.getByToken(widget.item.instrument.instrumentToken) ?? widget.item;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        _buildStatCard(
                            'OPEN', currentItem.currentPrice?.toStringAsFixed(2) ?? '0.00'),
                        const SizedBox(width: 8),
                        _buildStatCard('LOW', currentItem.low?.toStringAsFixed(2) ?? '0.00'),
                        const SizedBox(width: 8),
                        _buildStatCard('HIGH', currentItem.high?.toStringAsFixed(2) ?? '0.00'),
                        const SizedBox(width: 8),
                        _buildStatCard(
                            'CLOSE', currentItem.currentPrice?.toStringAsFixed(2) ?? '0.00'),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

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
                              instrument: widget.item.instrument,
                            ),
                          ),
                        );
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.link, size: 16, color: Color(0xFF22547C)),
                          SizedBox(width: 4),
                          Text(
                            'Option Chain',
                            style: TextStyle(
                              color: Color(0xFF22547C),
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Row(
                      children: [
                        Icon(Icons.show_chart, size: 16, color: Color(0xFF22547C)),
                        SizedBox(width: 4),
                        Text(
                          'View chart',
                          style: TextStyle(
                            color: Color(0xFF22547C),
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        showMarketDepthSheet(
                            context, widget.item.instrument.instrumentToken);
                      },
                      child: const Row(
                        children: [
                          Icon(Icons.layers, size: 16, color: Color(0xFF22547C)),
                          SizedBox(width: 4),
                          Text(
                            'Market Depth',
                            style: TextStyle(
                              color: Color(0xFF22547C),
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

              const SizedBox(height: 24),
            ],
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
            side: const BorderSide(width: 1, color: Color(0xFFE5E5EA)),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 25,
              height: 2,
              decoration: const BoxDecoration(color: Color(0xFFD1D1D6)),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
