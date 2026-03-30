import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/services/trade_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/utils/market_hours.dart';
import 'option_chain_view.dart';
import 'market_depth_sheet.dart';
import 'info_sheet.dart';
import 'chart_view.dart';
import 'package:stocker/services/trade_sound_service.dart';

class TradeCardPage extends StatefulWidget {
  final WatchlistItem item;
  final String?
      initialOrderType; // 'Buy Limit', 'Sell Limit', or null for default
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
  List<int> _quickQuantities = [100, 200, 500, 1000, 2000, 5000];
  String _orderType = 'Market Execution';

  /// Returns the available order types, filtering out Sell Limit for options
  /// when the user has no position. Adds Custom Price for admin only.
  List<String> get _availableOrderTypes {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final base = <String>['Market Execution', 'Buy Limit', 'Sell Limit'];

    if (_isOption) {
      final netQty = _getNetPosition(context);
      if (netQty <= 0) {
        base.remove('Sell Limit');
      }
    }

    if (profile.isAdmin) {
      base.add('Custom Price');
    }

    return base;
  }

  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TradeService _tradeService = TradeService();
  bool _isLoading = false;

  // Lot limit info for any exchange with lot assignments
  LotLimitInfo? _lotLimitInfo;
  bool _isLoadingLotLimit = false;

  // Lot-based entry (for any exchange with lot assignments)
  int _lotCount = 1; // User enters lot count
  final List<int> _quickLots = [1, 2, 3, 4, 5]; // Quick lot buttons
  int _selectedQuickLot = 1;

  // User selection for admin/master
  final TextEditingController _userSearchCtrl = TextEditingController();
  List<Map<String, dynamic>> _userResults = [];
  Map<String, dynamic>? _selectedUser;
  bool _showUserDropdown = false;
  bool _isSearchingUsers = false;

  /// Returns true if this instrument has **lot-based** limits (e.g. MCX-FUT).
  /// Lot mode: user enters number of lots; actual qty = lots × lot_size.
  bool get _hasLotInfo =>
      _lotLimitInfo != null &&
      _lotLimitInfo!.lotSize > 0 &&
      !_lotLimitInfo!.isTurnoverMode;

  /// Returns true if this instrument has **turnover-based** limits (e.g. NFO-FUT, SGX, GLOBAL).
  /// Turnover mode: user enters raw quantity directly; max_qty is enforced.
  bool get _hasTurnoverLimit =>
      _lotLimitInfo != null && _lotLimitInfo!.isTurnoverMode;

  /// Returns the actual quantity to send to backend.
  int get _actualQuantity {
    if (_hasLotInfo) {
      return _lotCount * _lotLimitInfo!.lotSize;
    }
    // For both turnover mode and plain quantity mode, use _quantity directly.
    return _quantity;
  }

  /// Returns true if the current instrument is an option (CE or PE).
  bool get _isOption {
    final type = widget.item.instrument.instrumentType;
    return type == 'CE' || type == 'PE';
  }

  /// Returns the user's net quantity for this exact instrument token.
  /// Positive = long position, 0 or negative = no sellable position.
  int _getNetPosition(BuildContext context) {
    final positions =
        Provider.of<TradeMetricsProvider>(context, listen: false).positions;
    for (final pos in positions) {
      if (pos.instrumentToken == widget.item.instrument.instrumentToken) {
        return pos.netQty;
      }
    }
    return 0;
  }

  @override
  void initState() {
    super.initState();
    _loadQuickQuantities();
    if (widget.initialQuantity != null) {
      _quantity = widget.initialQuantity!;
      _selectedQuickQty = _quickQuantities.contains(_quantity) ? _quantity : -1;
    }
    if (widget.initialOrderType != null) {
      _orderType = widget.initialOrderType!;
    }
    _qtyController.text = _quantity.toString();
    _fetchLotLimit();
  }

  Future<void> _fetchLotLimit() async {
    // For admin/master, wait until they select a user
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    if (!profile.isUser && !profile.isMaster) return;

    setState(() => _isLoadingLotLimit = true);

    final info = await _tradeService.getLotLimit(
      exchange: widget.item.instrument.segment,
      instrumentToken: widget.item.instrument.instrumentToken,
      tradingSymbol: widget.item.instrument.tradingsymbol,
      rawName: widget.item.instrument.rawName,
    );

    if (mounted) {
      setState(() {
        _lotLimitInfo = info;
        _isLoadingLotLimit = false;

        if (info != null && info.lotSize > 0) {
          if (info.isTurnoverMode) {
            // Turnover mode: default to 1 quantity
            _quantity = 1;
            _selectedQuickQty = _quickQuantities.contains(1) ? 1 : -1;
            _qtyController.text = '1';
          } else {
            // Lot mode: default to 1 lot
            _lotCount = 1;
            _selectedQuickLot = 1;
            _qtyController.text = '1';
          }
        }
      });
    }
  }

  Future<void> _loadQuickQuantities() async {
    final vals = await SecureStorageService().getQuickQuantities();
    if (mounted) {
      setState(() {
        _quickQuantities = vals;
        if (!_quickQuantities.contains(_selectedQuickQty)) {
          _selectedQuickQty =
              _quickQuantities.isNotEmpty ? _quickQuantities.first : -1;
        }
      });
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    _userSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() {
        _userResults = [];
        _showUserDropdown = false;
      });
      return;
    }
    setState(() => _isSearchingUsers = true);
    try {
      final token = await SecureStorageService().getToken();
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      final endpoint = profile.isAdmin
          ? '/admin/users?limit=20&search=$query'
          : '/master/users?limit=20&search=$query';
      final res = await ApiService(backendUrl).get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final nested = body['data'];
        final List list =
            nested is Map ? (nested['users'] ?? []) : (nested ?? []);
        setState(() {
          _userResults = list.cast<Map<String, dynamic>>();
          _showUserDropdown = _userResults.isNotEmpty;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingUsers = false);
  }

  void _selectUser(Map<String, dynamic> user) {
    setState(() {
      _selectedUser = user;
      _userSearchCtrl.text = user['username'] ?? user['name'] ?? '';
      _showUserDropdown = false;
      _userResults = [];
    });
    // Re-fetch lot limit for the selected user
    _fetchLotLimitForUser();
  }

  Future<void> _fetchLotLimitForUser() async {
    setState(() => _isLoadingLotLimit = true);

    // Clear cache to force re-fetch for new user
    _tradeService.clearCache();

    final userId = _selectedUser != null
        ? (_selectedUser!['id'] ?? _selectedUser!['_id'])?.toString()
        : null;

    final info = await _tradeService.getLotLimit(
      exchange: widget.item.instrument.segment,
      instrumentToken: widget.item.instrument.instrumentToken,
      tradingSymbol: widget.item.instrument.tradingsymbol,
      rawName: widget.item.instrument.rawName,
      userId: userId,
    );

    if (mounted) {
      setState(() {
        _lotLimitInfo = info;
        _isLoadingLotLimit = false;

        if (info != null && info.lotSize > 0) {
          if (info.isTurnoverMode) {
            _quantity = 1;
            _selectedQuickQty = _quickQuantities.contains(1) ? 1 : -1;
            _qtyController.text = '1';
          } else {
            _lotCount = 1;
            _selectedQuickLot = 1;
            _qtyController.text = '1';
          }
        }
      });
    }
  }

  void _setQuantity(int qty) {
    setState(() {
      if (_hasLotInfo) {
        // For lot-based entry, qty is lot count
        _lotCount = qty;
        _selectedQuickLot = qty;
        _qtyController.text = qty.toString();
      } else {
        _quantity = qty;
        _selectedQuickQty = qty;
        _qtyController.text = qty.toString();
      }
    });
  }

  void _incrementQuantity() {
    setState(() {
      if (_hasLotInfo) {
        // For lot-based entry, increment lot count by 1
        _lotCount++;
        _selectedQuickLot = _quickLots.contains(_lotCount) ? _lotCount : -1;
        _qtyController.text = _lotCount.toString();
      } else {
        _quantity++;
        _selectedQuickQty =
            _quickQuantities.contains(_quantity) ? _quantity : -1;
        _qtyController.text = _quantity.toString();
      }
    });
  }

  void _decrementQuantity() {
    setState(() {
      if (_hasLotInfo) {
        // For lot-based entry, decrement lot count by 1 (min 1)
        if (_lotCount > 1) {
          _lotCount--;
          _selectedQuickLot = _quickLots.contains(_lotCount) ? _lotCount : -1;
          _qtyController.text = _lotCount.toString();
        }
      } else {
        if (_quantity > 1) {
          _quantity--;
          _selectedQuickQty =
              _quickQuantities.contains(_quantity) ? _quantity : -1;
          _qtyController.text = _quantity.toString();
        }
      }
    });
  }

  Future<void> _handleTrade(String transactionType, double currentPrice) async {
    if (_isLoading) return;

    // Check market hours for this instrument's exchange
    final ex = widget.item.instrument.exchange;
    final sym = widget.item.instrument.tradingsymbol;
    if (!MarketHours.isMarketOpen(exchange: ex, tradingsymbol: sym)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(MarketHours.getMarketStatusMessage(
              exchange: ex, tradingsymbol: sym)),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    // Lot validation for exchanges with lot assignments
    if (_hasLotInfo) {
      if (_lotCount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minimum order is 1 lot'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }
      if (_lotCount > _lotLimitInfo!.maxLots) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'You are allowed max ${_lotLimitInfo!.maxLots} lots for this instrument'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        return;
      }
    }

    // Turnover mode: validate raw quantity against max_qty
    if (_hasTurnoverLimit) {
      if (_quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quantity must be at least 1'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
        return;
      }
      if (_quantity > _lotLimitInfo!.maxQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Maximum allowed quantity is ${_lotLimitInfo!.maxQty} for this instrument'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
        return;
      }
    }

    // Block option sell if user doesn't hold this option
    if (transactionType == 'SELL' && _isOption) {
      final netQty = _getNetPosition(context);
      if (netQty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Option selling is not allowed. You must own this option before you can sell it.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (_actualQuantity > netQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'You can only sell up to $netQty units (your current holding).'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final currentItem = Provider.of<WatchlistProvider>(context, listen: false)
            .getByToken(widget.item.instrument.instrumentToken) ??
        widget.item;

    final isLimit = _orderType == 'Buy Limit' || _orderType == 'Sell Limit';
    final isCustomPrice = _orderType == 'Custom Price';
    final tradePrice = (isLimit || isCustomPrice)
        ? (double.tryParse(_priceController.text) ?? currentPrice)
        : currentPrice;

    // Circuit limit validation
    final upper = currentItem.upperCircuitLimit;
    final lower = currentItem.lowerCircuitLimit;
    if (upper != null && tradePrice > upper) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Price ${tradePrice.toStringAsFixed(2)} exceeds upper circuit limit ${upper.toStringAsFixed(2)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }
    if (lower != null && tradePrice < lower) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Price ${tradePrice.toStringAsFixed(2)} is below lower circuit limit ${lower.toStringAsFixed(2)}'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final result = await _tradeService.placeTrade(
      instrumentToken: currentItem.instrument.instrumentToken,
      tradingSymbol: currentItem.instrument.tradingsymbol,
      exchange: currentItem.instrument.exchange,
      segment: currentItem.instrument.segment,
      transactionType: transactionType,
      quantity:
          _actualQuantity, // Use actual quantity (lots * lot_size for MCX)
      price: tradePrice,
      orderType: isLimit ? 'LIMIT' : 'MARKET',
      userId: _selectedUser != null
          ? (_selectedUser!['id'] ?? _selectedUser!['_id'])?.toString()
          : null,
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
        // Play trade bell sound if enabled
        TradeSoundService().playIfEnabled();
        // Refresh positions and wait for data before navigating back
        await Provider.of<TradeMetricsProvider>(context, listen: false)
            .fetchBaseData();
        // Refresh balance
        await Provider.of<UserProfileProvider>(context, listen: false)
            .refreshProfile();
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
                              instrument.userFriendlyName,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: kFontSizeViewTitle,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            // Expiry row removed as it is now in the title
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3F45C7)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'LTP',
                                  style: TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: kFontSizeBadge,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${(currentItem.currentPrice ?? 0.0).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: Color(0xFF3F45C7),
                                    fontSize: kFontSizeBody,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightBold,
                                  ),
                                ),
                              ],
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
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              fontSize: kFontSizeNavLabel,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium,
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
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
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
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
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
                                  defaultPrice = currentItem.askPrice ??
                                      (ltp > 0 ? ltp + spread : ltp);
                                } else {
                                  defaultPrice = currentItem.bidPrice ??
                                      (ltp > 0 ? ltp - spread : ltp);
                                }
                                _priceController.text =
                                    defaultPrice.toStringAsFixed(2);
                              }
                            });
                          }
                        },
                        items: _availableOrderTypes
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
                if (userProfile.isUser || userProfile.isMaster) {
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
                                  fontSize: kFontSizeSectionHeader,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightMedium,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => showInfoSheet(context),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        size: kIconSizeMedium, color: Color(0xFF3F45C7)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Info',
                                      style: TextStyle(
                                        color: Color(0xFF3F45C7),
                                        fontSize: kFontSizeSectionHeader,
                                        fontFamily: 'Inter',
                                        fontWeight: kFontWeightMedium,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Searchable user field
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
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _userSearchCtrl,
                                    onChanged: _searchUsers,
                                    style: const TextStyle(
                                      color: Colors.black,
                                      fontSize: kFontSizeButtonText,
                                      fontFamily: 'Inter',
                                      fontWeight: kFontWeightRegular,
                                    ),
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: _selectedUser != null
                                          ? null
                                          : 'Search user by name...',
                                      hintStyle: const TextStyle(
                                        color: Color(0xFF8E8E93),
                                        fontSize: kFontSizeButtonText,
                                        fontFamily: 'Inter',
                                        fontWeight: kFontWeightRegular,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                if (_isSearchingUsers)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF3F45C7)),
                                  )
                                else if (_selectedUser != null)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedUser = null;
                                        _userSearchCtrl.clear();
                                        _userResults = [];
                                        _showUserDropdown = false;
                                      });
                                    },
                                    child: const Icon(Icons.close,
                                        size: kIconSizeDefault, color: Color(0xFF8E8E93)),
                                  )
                                else
                                  const Icon(Icons.search,
                                      size: kIconSizeMedium, color: Color(0xFF8E8E93)),
                              ],
                            ),
                          ),
                          // Dropdown results
                          if (_showUserDropdown)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              constraints: const BoxConstraints(maxHeight: 180),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFFD1D1D6)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: _userResults.length,
                                itemBuilder: (_, i) {
                                  final u = _userResults[i];
                                  final name = u['name'] ?? '';
                                  final uname = u['username'] ?? '';
                                  return GestureDetector(
                                    onTap: () => _selectUser(u),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: const Color(0xFFF1F5F9),
                                            width: i < _userResults.length - 1
                                                ? 1
                                                : 0,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.person_outline,
                                              size: kIconSizeDefault,
                                              color: Color(0xFF94A3B8)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '$name (@$uname)',
                                              style: const TextStyle(
                                                color: Colors.black,
                                                fontSize: kFontSizeBody,
                                                fontFamily: 'Inter',
                                                fontWeight: kFontWeightRegular,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
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
                  // Quantity/Lots label - changes based on lot assignment
                  Text(
                    _hasLotInfo ? 'Lots' : 'Quantity',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium,
                      height: 1.25,
                    ),
                  ),
                  if (_hasTurnoverLimit) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Max: ${_lotLimitInfo!.maxQty} qty',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: kFontSizeSubtitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightRegular,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Quantity/Lots input with +/- buttons
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
                              fontSize: kFontSizeSectionHeader,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightMedium,
                              height: 1.25,
                            ),
                            onChanged: (value) {
                              final newVal = int.tryParse(value);
                              if (newVal != null) {
                                setState(() {
                                  if (_hasLotInfo) {
                                    _lotCount = newVal;
                                    _selectedQuickLot =
                                        _quickLots.contains(_lotCount)
                                            ? _lotCount
                                            : -1;
                                  } else {
                                    _quantity = newVal;
                                    _selectedQuickQty =
                                        _quickQuantities.contains(_quantity)
                                            ? _quantity
                                            : -1;
                                  }
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
                                child: const Icon(Icons.remove, size: kIconSizeDefault),
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
                                child: const Icon(Icons.add, size: kIconSizeDefault),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Quick buttons - Lots for exchanges with lot assignments, Quantities for others
                  if (_hasLotInfo) ...[
                    // Quick lot buttons (1, 2, 3, 4, 5)
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickLots.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final lot = _quickLots[i];
                          final isSelected = _selectedQuickLot == lot;
                          return GestureDetector(
                            onTap: () => _setQuantity(lot),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 8),
                              decoration: ShapeDecoration(
                                color: isSelected
                                    ? const Color(0xFF3F45C7)
                                    : const Color(0xFFC7C7CC),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$lot Lot${lot > 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFFF9F9F9)
                                      : Colors.black,
                                  fontSize: kFontSizeBody,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightMedium,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ] else ...[
                    // Quick quantity buttons
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _quickQuantities.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (_, i) {
                          final qty = _quickQuantities[i];
                          final isSelected = _selectedQuickQty == qty;
                          return GestureDetector(
                            onTap: () => _setQuantity(qty),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: ShapeDecoration(
                                color: isSelected
                                    ? const Color(0xFF3F45C7)
                                    : const Color(0xFFC7C7CC),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$qty',
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFFF9F9F9)
                                      : Colors.black,
                                  fontSize: kFontSizeBody,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightRegular,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── Turnover-mode info banner ─────────────────────────────
                  if (_hasTurnoverLimit) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF3F45C7)
                                .withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: kIconSizeDefault, color: Color(0xFF3F45C7)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Max qty: ',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${_lotLimitInfo!.maxQty}',
                                        style: const TextStyle(
                                          color: Color(0xFF3F45C7),
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightSemiBold,
                                        ),
                                      ),
                                      if (_lotLimitInfo!.breakQty > 0) ...[
                                        const TextSpan(
                                          text: '  •  Break qty: ',
                                          style: TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: kFontSizeSubtitle,
                                            fontFamily: 'Inter',
                                          ),
                                        ),
                                        TextSpan(
                                          text: '${_lotLimitInfo!.breakQty}',
                                          style: const TextStyle(
                                            color: Color(0xFF3F45C7),
                                            fontSize: kFontSizeSubtitle,
                                            fontFamily: 'Inter',
                                            fontWeight: kFontWeightSemiBold,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: kIconSizeSmall, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  'Order: $_quantity qty',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Lot Info Banner (for lot-based exchanges) ─────────────
                  if (_isLoadingLotLimit) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF3F45C7)),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Loading lot info...',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: kFontSizeSubtitle,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_hasLotInfo) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFF3F45C7)
                                .withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Group name if available
                          if (_lotLimitInfo!.groupName != null &&
                              _lotLimitInfo!.groupName!.isNotEmpty) ...[
                            Row(
                              children: [
                                const Icon(Icons.folder_outlined,
                                    size: kIconSizeSmall, color: Color(0xFF94A3B8)),
                                const SizedBox(width: 6),
                                Text(
                                  _lotLimitInfo!.groupName!,
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: kFontSizeNavLabel,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightMedium,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          // Lot info row
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: kIconSizeDefault, color: Color(0xFF3F45C7)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: '1 Lot = ',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${_lotLimitInfo!.lotSize} qty',
                                        style: const TextStyle(
                                          color: Color(0xFF3F45C7),
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightSemiBold,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: '  •  Max: ',
                                        style: TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: 'Inter',
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${_lotLimitInfo!.maxLots} Lots',
                                        style: const TextStyle(
                                          color: Color(0xFF3F45C7),
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightSemiBold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          // Order preview row
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: kIconSizeSmall, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Text(
                                  'Order: $_lotCount Lot${_lotCount > 1 ? 's' : ''} = $_actualQuantity qty',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

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

                      final sellPrice = currentItem.bidPrice ??
                          (ltp > 0 ? ltp - spread : ltp);
                      final buyPrice = currentItem.askPrice ??
                          (ltp > 0 ? ltp + spread : ltp);

                      final sellPriceStr = sellPrice.toStringAsFixed(2);
                      final buyPriceStr = buyPrice.toStringAsFixed(2);

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_orderType == 'Market Execution') ...[
                            // Sell side
                            Builder(builder: (context) {
                              final sellDisabled =
                                  _isOption && _getNetPosition(context) <= 0;
                              return Expanded(
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
                                              width: 1,
                                              color: Color(0xFFC7C7CC)),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          sellPrice.toStringAsFixed(2),
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: kFontSizeSectionHeader,
                                            fontFamily: 'Inter',
                                            fontWeight: kFontWeightMedium,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    GestureDetector(
                                      onTap: sellDisabled
                                          ? null
                                          : () {
                                              _handleTrade('SELL', sellPrice);
                                            },
                                      child: Opacity(
                                        opacity: sellDisabled ? 0.4 : 1.0,
                                        child: Container(
                                          width: double.infinity,
                                          height: 56,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 32, vertical: 18),
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                Color(0xFFFF3C00),
                                                Color(0xFF7A0F37),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            sellDisabled
                                                ? 'SELL'
                                                : 'SELL',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: kFontSizeSectionHeader,
                                              fontFamily: 'Inter',
                                              fontWeight: kFontWeightSemiBold,
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
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
                                    child: Center(
                                      child: Text(
                                        buyPrice.toStringAsFixed(2),
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: kFontSizeSectionHeader,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightMedium,
                                          height: 1.25,
                                        ),
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
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Color(0xFFC6529E),
                                            Color(0xFF3B43C9),
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'BUY',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: kFontSizeSectionHeader,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightSemiBold,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (_orderType == 'Custom Price') ...[
                            // Custom Price: price input + SELL/BUY buttons
                            Expanded(
                              child: Column(
                                children: [
                                  Container(
                                    width: double.infinity,
                                    height: 46,
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    decoration: ShapeDecoration(
                                      color: const Color(0xFFF2F2F7),
                                      shape: RoundedRectangleBorder(
                                        side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    child: Center(
                                      child: TextField(
                                        controller: _priceController,
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                                        ],
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: kFontSizeSectionHeader,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightMedium,
                                        ),
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          hintText: 'Enter price',
                                          hintStyle: TextStyle(
                                            color: Color(0xFFC7C7CC),
                                            fontSize: kFontSizeSectionHeader,
                                            fontFamily: 'Inter',
                                            fontWeight: kFontWeightMedium,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            final customPrice = double.tryParse(_priceController.text);
                                            if (customPrice == null || customPrice <= 0) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Enter a valid price'), backgroundColor: Color(0xFFEF4444)),
                                              );
                                              return;
                                            }
                                            _handleTrade('SELL', customPrice);
                                          },
                                          child: Container(
                                            height: 56,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                                colors: [Color(0xFFFF3C00), Color(0xFF7A0F37)],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Center(
                                              child: Text('SELL', style: TextStyle(color: Colors.white, fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            final customPrice = double.tryParse(_priceController.text);
                                            if (customPrice == null || customPrice <= 0) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Enter a valid price'), backgroundColor: Color(0xFFEF4444)),
                                              );
                                              return;
                                            }
                                            _handleTrade('BUY', customPrice);
                                          },
                                          child: Container(
                                            height: 56,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.centerLeft,
                                                end: Alignment.centerRight,
                                                colors: [Color(0xFFC6529E), Color(0xFF3B43C9)],
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: const Center(
                                              child: Text('BUY', style: TextStyle(color: Colors.white, fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
                                          fontSize: kFontSizeSectionHeader,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightMedium,
                                        ),
                                        decoration: InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding: EdgeInsets.zero,
                                          hintText: _orderType == 'Buy Limit'
                                              ? buyPriceStr
                                              : sellPriceStr,
                                          hintStyle: const TextStyle(
                                            color: Color(0xFFC7C7CC),
                                            fontSize: kFontSizeSectionHeader,
                                            fontFamily: 'Inter',
                                            fontWeight: kFontWeightMedium,
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
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: _orderType == 'Buy Limit'
                                              ? [
                                                  const Color(0xFFC6529E),
                                                  const Color(0xFF3B43C9),
                                                ]
                                              : [
                                                  const Color(0xFFFF3C00),
                                                  const Color(0xFF7A0F37),
                                                ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'PLACE',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: kFontSizeSectionHeader,
                                          fontFamily: 'Inter',
                                          fontWeight: kFontWeightSemiBold,
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
                      _buildStatCard('OPEN',
                          currentItem.open?.toStringAsFixed(2) ?? '0.00'),
                      const SizedBox(width: 8),
                      _buildStatCard(
                          'LOW', currentItem.low?.toStringAsFixed(2) ?? '0.00'),
                      const SizedBox(width: 8),
                      _buildStatCard('HIGH',
                          currentItem.high?.toStringAsFixed(2) ?? '0.00'),
                      const SizedBox(width: 8),
                      _buildStatCard('CLOSE',
                          currentItem.close?.toStringAsFixed(2) ?? '0.00'),
                    ],
                  ),
                );
              },
            ),

            const SizedBox(height: 16),

            // Market closed warning
            Builder(
              builder: (context) {
                final ex = widget.item.instrument.exchange;
                final sym = widget.item.instrument.tradingsymbol;
                if (MarketHours.isMarketOpen(exchange: ex, tradingsymbol: sym))
                  return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: kIconSizeDefault, color: Color(0xFFEF4444)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          MarketHours.getMarketStatusMessage(
                              exchange: ex, tradingsymbol: sym),
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontSize: kFontSizeSubtitle,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
                          ),
                        ),
                      ),
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
                        Icon(Icons.link, size: kIconSizeDefault, color: Color(0xFF3F45C7)),
                        SizedBox(width: 4),
                        Text(
                          'Option Chain',
                          style: TextStyle(
                            color: Color(0xFF3F45C7),
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
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
                            size: kIconSizeDefault, color: Color(0xFF3F45C7)),
                        SizedBox(width: 4),
                        Text(
                          'View chart',
                          style: TextStyle(
                            color: Color(0xFF3F45C7),
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
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
                        Icon(Icons.layers, size: kIconSizeDefault, color: Color(0xFF3F45C7)),
                        SizedBox(width: 4),
                        Text(
                          'Market Depth',
                          style: TextStyle(
                            color: Color(0xFF3F45C7),
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
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
                fontSize: kFontSizeSubtitle,
                fontFamily: 'Inter',
                fontWeight: kFontWeightRegular,
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
                fontSize: kFontSizeBody,
                fontFamily: 'Inter',
                fontWeight: kFontWeightMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
