import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';

class OrdersPage extends StatelessWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        final double posPnl = provider.positionPnl;
        final double m2m = provider.m2mPnl;
        final double realised = provider.realisedPnl;
        final double credit = provider.credit;
        final double marginUsed = provider.marginUsed;

        // Equity = Credit + M2M P&L
        final double equity = credit + m2m;

        // Free Margin = Equity - Margin Used
        final double freeMargin = equity - marginUsed;

        final isPosPnlPositive = posPnl >= 0;

        return Scaffold(
          backgroundColor: const Color(0xFFF7F8FC),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Position Info Card
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                          width: 1,
                          color: Color(0xFFD1D1D6),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'POSITION',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          posPnl.toStringAsFixed(2),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isPosPnlPositive
                                ? const Color(0xFF34C759)
                                : const Color(0xFFFF3B30),
                            fontSize: 20,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // P&L Grid Card
                  Container(
                    width: double.infinity,
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                          width: 1,
                          color: Color(0xFFD1D1D6),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildGridRow(
                            'REALISED P&L',
                            realised.toStringAsFixed(2),
                            'M2M P&L',
                            m2m.toStringAsFixed(2)),
                        _buildGridRow('CREDIT', credit.toStringAsFixed(2),
                            'EQUITY', equity.toStringAsFixed(2)),
                        _buildGridRow(
                            'MARGIN USED',
                            marginUsed.toStringAsFixed(2),
                            'FREE MARGIN',
                            freeMargin.toStringAsFixed(2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Equity and Credit Info Bar (Dark Blue)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: const BoxDecoration(color: Color(0xFF22547C)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Equity: ${equity.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          'Credit: ${credit.toStringAsFixed(2)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  Container(
                    width: double.infinity,
                    height: 48,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                          width: 1,
                          color: Color(0xFFD1D1D6),
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.search,
                                size: 24, color: Color(0xFF8E8E93)),
                            SizedBox(width: 10),
                            Text(
                              'Search & Add',
                              style: TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.mic, size: 24, color: Color(0xFF8E8E93)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Orders List
                  Container(
                    width: double.infinity,
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (provider.positions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text(
                              'No open positions',
                              style: TextStyle(
                                color: Color(0xFF8E8E93),
                                fontSize: 16,
                              ),
                            ),
                          )
                        else
                          ...provider.positions.map((pos) {
                            final isBuy = pos.netQty > 0;
                            final isNegative = pos.floating < 0;
                            return Column(
                              children: [
                                _buildOrderItem(
                                  pos.tradingsymbol,
                                  pos.exchange, // Use exchange instead of date
                                  '${isBuy ? "BUY" : "SELL"}: ${pos.netQty.abs()} QTY',
                                  isBuy
                                      ? pos.avgBuyPrice.toStringAsFixed(2)
                                      : pos.avgSellPrice.toStringAsFixed(2),
                                  pos.ltp.toStringAsFixed(2),
                                  pos.floating.toStringAsFixed(2),
                                  (pos.netQty.abs() * pos.ltp)
                                      .toStringAsFixed(2), // Current value
                                  isNegative,
                                ),
                                if (pos != provider.positions.last)
                                  const Divider(
                                      height: 1, color: Color(0xFFC7C7CC)),
                              ],
                            );
                          }),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridRow(
      String label1, String value1, String label2, String value2) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(width: 1, color: Color(0xFFD1D1D6))),
      ),
      child: Row(
        children: [
          Expanded(
              child: _buildGridItem(label1, value1, showRightBorder: true)),
          Expanded(child: _buildGridItem(label2, value2)),
        ],
      ),
    );
  }

  Widget _buildGridItem(String label, String value,
      {bool showRightBorder = false}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: showRightBorder
            ? const Border(
                right: BorderSide(width: 1, color: Color(0xFFD1D1D6)))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(String name, String date, String qtyInfo, String atp,
      String cmp, String pnl, String value, bool isNegative) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w400)),
                    const SizedBox(width: 8),
                    Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                            color: Color(0xFFD9D9D9), shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(date,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w400)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(qtyInfo,
                    style: const TextStyle(
                        color: Color(0xFF999999), fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text('ATP: $atp',
                        style: const TextStyle(
                            color: Color(0xFF999999), fontSize: 12)),
                    const SizedBox(width: 16),
                    Text('CMP: $cmp',
                        style: const TextStyle(
                            color: Color(0xFF999999), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(isNegative ? Icons.arrow_downward : Icons.arrow_upward,
                      size: 16,
                      color: isNegative
                          ? const Color(0xFFFF3B30)
                          : const Color(0xFF34C759)),
                  const SizedBox(width: 4),
                  Text(pnl,
                      style: TextStyle(
                          color: isNegative
                              ? const Color(0xFFFF3B30)
                              : const Color(0xFF34C759),
                          fontSize: 12)),
                ],
              ),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w400)),
            ],
          ),
        ],
      ),
    );
  }
}
