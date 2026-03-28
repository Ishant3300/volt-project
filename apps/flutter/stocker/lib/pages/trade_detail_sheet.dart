import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stocker/models/trade.dart';
import '../utils/contants.dart';

class TradeDetailSheet extends StatefulWidget {
  final Trade trade;
  final bool isClosing;
  const TradeDetailSheet(
      {super.key, required this.trade, this.isClosing = false});

  @override
  State<TradeDetailSheet> createState() => _TradeDetailSheetState();
}

class _TradeDetailSheetState extends State<TradeDetailSheet> {
  Trade get trade => widget.trade;

  String get _formattedDate {
    try {
      final dt = DateTime.parse(trade.createdAt).toLocal();
      return DateFormat('dd MMM yyyy | hh:mm:ss a').format(dt).toUpperCase();
    } catch (_) {
      return trade.createdAt;
    }
  }

  bool get _isBuy => trade.transactionType.toUpperCase() == 'BUY';

  Color get _sideColor =>
      _isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

  String get _sideLabel => _isBuy ? 'BUY' : 'SELL';

  String get _displayStatus {
    final raw = trade.status.toLowerCase();
    if (raw == 'completed') {
      return widget.isClosing ? 'CLOSED' : 'EXECUTED';
    }
    return trade.status.toUpperCase();
  }

  // Use the Trade model's built-in lot/qty logic
  String get _volumeUnit => trade.isLotBased ? 'Lots' : 'Quantity';
  int get _volumeValue => trade.displayVolume;
  String _getFormattedVolume() =>
      '$_sideLabel · ${trade.displayVolume} ${trade.volumeUnit}';

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [

          // Header card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trade.tradingSymbol,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightBold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _sideColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getFormattedVolume(),
                              style: TextStyle(
                                color: _sideColor,
                                fontSize: kFontSizeNavLabel,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              trade.exchange,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: kFontSizeNavLabel,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${trade.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeViewTitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightBold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: trade.status.toLowerCase() == 'completed'
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _displayStatus,
                        style: TextStyle(
                          color: trade.status.toLowerCase() == 'completed'
                              ? const Color(0xFF10B981)
                              : const Color(0xFFB45309),
                          fontSize: kFontSizeCaption,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Detail rows
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trade.userName != null)
                      _buildRow('User', trade.userName!),
                    _buildRow('Execution', _formattedDate),
                    _buildRow('Symbol', trade.tradingSymbol),
                    _buildRow('Exchange', trade.exchange),
                    _buildRow(
                        'Type', '$_sideLabel / ${trade.orderType ?? 'MARKET'}'),
                    _buildRow(_volumeUnit, _volumeValue.toString()),
                    _buildRow('Price', '${trade.price.toStringAsFixed(2)}'),
                    if (trade.productType != null)
                      _buildRow('Product', trade.productType!),
                    _buildRow('Status', _displayStatus),
                    if (trade.masterName != null)
                      _buildRow('Master', trade.masterName!),
                  ],
                ),
              ),
            ),
          ),

          // Close button
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.of(context).viewPadding.bottom),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF3F45C7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: kFontSizeButtonText,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightSemiBold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: kFontSizeBodySmall,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.black,
                fontSize: kFontSizeBodySmall,
                fontFamily: 'Inter',
                fontWeight: kFontWeightSemiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showTradeDetailSheet(BuildContext context, Trade trade,
    {bool isClosing = false}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => TradeDetailSheet(trade: trade, isClosing: isClosing),
  );
}
