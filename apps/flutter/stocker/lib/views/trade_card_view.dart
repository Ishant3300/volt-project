import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/services/trade_service.dart';
import 'option_chain_view.dart';
import 'market_depth_sheet.dart';
import 'info_sheet.dart';
import 'chart_view.dart';

class TradeCardPage extends StatefulWidget {
  final WatchlistItem item;
  final String? initialOrderType; // 'Buy Limit', 'Sell Limit', or null for default
  final int? initialQuantity;

  const TradeCardPage({
    super.key,
    required this.item,
    this.initialOrderType,
    this.initialQuantity,
  });

  @override
  State<TradeCardPage> createState() => _TradeCardPageState();
}

class _TradeCardPageState extends State<TradeCardPage> {
  int _quantity = 100;
  int _selectedQuickQty = 100;
  static const List<int> _quickQuantities = [100, 200, 500, 1000, 2000, 5000];
  String _orderType = 'Market Execution';
  final List<String> _orderTypes = [
    'Market Execution',
    'Buy Limit',
    'Sell Limit'
  ];
  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TradeService _tradeService = TradeService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuantity != null) {
      _quantity = widget.initialQuantity!;
      _selectedQuickQty = _quickQuantities.contains(_quantity) ? _quantity : -1;
    }
    if (widget.initialOrderType != null) {
      _orderType = widget.initialOrderType!;
    }
    _qtyController.text = _quantity.toString();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _setQuantity(int qty) {
    setState(() {
      _quantity = qty;
      _selectedQuickQty = qty;
      _qtyController.text = qty.toString();
    });
  }

  void _incrementQuantity() {
    setState(() {
      _quantity++;
      _selectedQuickQty = _quickQuantities.contains(_quantity) ? _quantity : -1;
      _qtyController.text = _quantity.toString();
    });
  }

  void _decrementQuantity() {
    if (_quantity > 1) {
      setState(() {
        _quantity--;
        _selectedQuickQty =
            _quickQuantities.contains(_quantity) ? _quantity : -1;
        _qtyController.text = _quantity.toString();
      });
    }
  }

  Future<void> _handleTrade(String transactionType, double currentPrice) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    final currentItem = Provider.of<WatchlistProvider>(context, listen: false)
            .getByToken(widget.item.instrument.instrumentToken) ??
        widget.item;

    final isLimit = _orderType != 'Market Execution';
    final tradePrice = isLimit
        ? (double.tryParse(_priceController.text) ?? currentPrice)
        : currentPrice;

    final result = await _tradeService.placeTrade(
      instrumentToken: currentItem.instrument.instrumentToken,
      tradingSymbol: currentItem.instrument.tradingsymbol,
      exchange: currentItem.instrument.exchange,
      transactionType: transactionType,
      quantity: _quantity,
      price: tradePrice,
      orderType: isLimit ? 'LIMIT' : 'MARKET',
    );

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.$2),
          backgroundColor: result.$1 ? Colors.green : Colors.red,
        ),
      );

      if (result.$1) {
        // Refresh positions and wait for data before navigating back
        await Provider.of<TradeMetricsProvider>(context, listen: false)
            .fetchBaseData();
        if (mounted) {
          Navigator.pop(context);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = SafeArea(
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Header with back button and stock info
            Consumer<WatchlistProvider>(
              builder: (context, provider, child) {
                final currentItem = provider
                        .getByToken(widget.item.instrument.instrumentToken) ??
                    widget.item;
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
                          child:
                              const Icon(Icons.arrow_back, color: Colors.black),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              instrument.name.isNotEmpty
                                  ? instrument.name.toString().toUpperCase()
                                  : instrument.tradingsymbol,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                            currentItem.currentPrice?.toStringAsFixed(2) ??
                                '0.00',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: currentItem.isPositive
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFFF3B30),
                              fontSize: 18,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentItem.changeDisplay.isEmpty
                                ? '--'
                                : currentItem.changeDisplay,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: currentItem.isPositive
                                  ? const Color(0xFF34C759)
                                  : const Color(0xFFFF3B30),
                              fontSize: 13,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),

            // Order Type dropdown
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Order Type',
                    style: TextStyle(
                      color: Color(0xFF2B2B2B),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFD1D1D6)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _orderType,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: Color(0xFF8E8E93)),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _orderType = newValue;
                              if (newValue != 'Market Execution') {
                                final currentItem =
                                    Provider.of<WatchlistProvider>(context,
                                                listen: false)
                                            .getByToken(widget.item.instrument
                                                .instrumentToken) ??
                                        widget.item;
                                
                                // Set appropriate price based on order type
                                final ltp = currentItem.currentPrice ?? 0.0;
                                final spread = ltp * 0.0005;
                                
                                double defaultPrice;
                                if (newValue == 'Buy Limit') {
                                  defaultPrice = currentItem.askPrice ?? (ltp > 0 ? ltp + spread : ltp);
                                } else {
                                  defaultPrice = currentItem.bidPrice ?? (ltp > 0 ? ltp - spread : ltp);
                                }
                                _priceController.text = defaultPrice.toStringAsFixed(2);
                              }
                            });
                          }
                        },
                        items: _orderTypes
                            .map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // User selection dropdown
            Consumer<UserProfileProvider>(
              builder: (context, userProfile, child) {
                if (userProfile.isUser) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
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
                                    Icon(Icons.info_outline,
                                        size: 20, color: Color(0xFF22547C)),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: ShapeDecoration(
                              color: Colors.white,
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(
                                    width: 1, color: Color(0xFFD1D1D6)),
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
                                Icon(Icons.arrow_drop_down,
                                    color: Color(0xFF8E8E93)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFC7C7CC)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _qtyController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                              height: 1.25,
                            ),
                            onChanged: (value) {
                              final newQty = int.tryParse(value);
                              if (newQty != null) {
                                setState(() {
                                  _quantity = newQty;
                                  _selectedQuickQty =
                                      _quickQuantities.contains(_quantity)
                                          ? _quantity
                                          : -1;
                                });
                              }
                            },
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
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Text(
                                '$qty',
                                textAlign: TextAlign.center,
                                maxLines: 1,
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
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),

                  // Price fields + action buttons
                  Consumer<WatchlistProvider>(
                    builder: (context, provider, child) {
                      final currentItem = provider.getByToken(
                              widget.item.instrument.instrumentToken) ??
                          widget.item;
                      
                      // For SELL: show bid price (price at which buyers are willing to buy)
                      // For BUY: show ask price (price at which sellers are willing to sell)
                      // If bid/ask not available, use LTP with a small spread (0.05% typical for liquid instruments)
                      final ltp = currentItem.currentPrice ?? 0.0;
                      final spread = ltp * 0.0005; // 0.05% spread
                      
                      final sellPrice = currentItem.bidPrice ?? (ltp > 0 ? ltp - spread : ltp);
                      final buyPrice = currentItem.askPrice ?? (ltp > 0 ? ltp + spread : ltp);
                      
                      final sellPriceStr = sellPrice.toStringAsFixed(2);
                      final buyPriceStr = buyPrice.toStringAsFixed(2);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_orderType == 'Market Execution') ...[
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
                                      sellPriceStr,
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
                                      _handleTrade('SELL', sellPrice);
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 18),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFFF9500),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
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
                            // Buy side
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
                                      buyPriceStr,
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
                                      _handleTrade('BUY', buyPrice);
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 18),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFF22547C),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                      ),
                                      child: const Text(
                                        'BUY',
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
                          ] else ...[
                            // Place button for limits
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 46,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    decoration: ShapeDecoration(
                                      color: const Color(0xFFF2F2F7),
                                      shape: RoundedRectangleBorder(
                                        side: const BorderSide(
                                            width: 1, color: Color(0xFFC7C7CC)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Center(
                                      child: TextField(
                                        controller: _priceController,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                              RegExp(r'^\d+\.?\d{0,2}')),
                                        ],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 16,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w500,
                                        ),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          hintText: _orderType == 'Buy Limit' ? buyPriceStr : sellPriceStr,
                                          hintStyle: const TextStyle(
                                            color: Color(0xFFC7C7CC),
                                            fontSize: 16,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  GestureDetector(
                                    onTap: () {
                                      final isBuy = _orderType == 'Buy Limit';
                                      _handleTrade(isBuy ? 'BUY' : 'SELL',
                                          isBuy ? buyPrice : sellPrice);
                                    },
                                    child: Container(
                                      width: double.infinity,
                                      height: 56,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 32, vertical: 18),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFF22547C),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
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
                final currentItem = provider
                        .getByToken(widget.item.instrument.instrumentToken) ??
                    widget.item;

                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _buildStatCard(
                          'OPEN',
                          currentItem.open?.toStringAsFixed(2) ??
                              '0.00'),
                      const SizedBox(width: 8),
                      _buildStatCard(
                          'LOW', currentItem.low?.toStringAsFixed(2) ?? '0.00'),
                      const SizedBox(width: 8),
                      _buildStatCard('HIGH',
                          currentItem.high?.toStringAsFixed(2) ?? '0.00'),
                      const SizedBox(width: 8),
                      _buildStatCard(
                          'CLOSE',
                          currentItem.close?.toStringAsFixed(2) ??
                              '0.00'),
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
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChartView(
                            instrument: widget.item.instrument,
                          ),
                        ),
                      );
                    },
                    child: const Row(
                      children: [
                        Icon(Icons.show_chart,
                            size: 16, color: Color(0xFF22547C)),
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
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: Stack(
        children: [
          content,
          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
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
