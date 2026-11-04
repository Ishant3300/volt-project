import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/investor_mode_provider.dart';
import 'package:stocker/services/trade_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/utils/market_hours.dart';
import 'option_chain_view.dart';
import 'market_depth_sheet.dart';
import 'info_sheet.dart';
import 'chart_view.dart';
import 'package:stocker/config/practice_session.dart';
import 'package:stocker/services/trade_sound_service.dart';
import 'package:stocker/widgets/page_wash.dart';

/// Client-side option validation is intentionally advisory. A missing local
/// position can mean the admin selected another user or metrics have not synced;
/// the backend performs the authoritative exact-token ownership check inside
/// the trade transaction.
String? validateLocalOptionSell({
  required bool isAdmin,
  required bool isOption,
  required String transactionType,
  required int requestedQuantity,
  required int? knownNetQuantity,
}) {
  if (isAdmin || !isOption || transactionType != 'SELL') return null;
  if (knownNetQuantity == null || knownNetQuantity <= 0) return null;
  if (requestedQuantity > knownNetQuantity) {
    return 'You can only sell up to $knownNetQuantity units (your current holding).';
  }
  return null;
}

class TradeCardPage extends StatefulWidget {
  final WatchlistItem item;
  final String?
      initialOrderType; // 'Buy Limit', 'Sell Limit', or null for default
  final int? initialQuantity;
  final String?
      forceSide; // 'BUY' or 'SELL' — only show this button (for pending orders)
  /// Pre-selects the client this order is placed for (admin/master only) —
  /// same effect as searching and picking them in the user field below, just
  /// done up front. Used when opened from that client's own account-detail
  /// Position tab, where the client is already known and re-searching for
  /// them would be redundant. Map shape matches _selectUser's own param
  /// (needs at least 'id' and 'username'/'name').
  final Map<String, dynamic>? initialSelectedUser;

  /// Opened from search for a script not in the watchlist: once an order goes
  /// through it is added to the watchlist (1 Nov 2026).
  final bool addToWatchlistOnOrder;

  const TradeCardPage({
    super.key,
    required this.item,
    this.initialOrderType,
    this.initialQuantity,
    this.forceSide,
    this.initialSelectedUser,
    this.addToWatchlistOnOrder = false,
  });

  @override
  State<TradeCardPage> createState() => _TradeCardPageState();
}

class _TradeCardPageState extends State<TradeCardPage> {
  int _quantity = 100;
  int _selectedQuickQty = 100;
  List<int> _quickQuantities = [100, 200, 500, 1000, 2000, 5000];

  // Tab-based order type: 0=Market, 1=Limit, 2=Stop, 3=Custom (admin only)
  int _selectedTab = 0;

  // Custom-tab-only, admin-only: bypasses brokerage for this one trade when on.
  // Everything else about the trade (price, quantity, P&L) is unaffected.
  bool _carryForwardNoBrokerage = false;

  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TradeService _tradeService = TradeService();
  bool _isLoading = false;

  // Guards against a double-pop: the manual back-arrow tap and the
  // auto-close-on-success path (after placeTrade() resolves) both call
  // Navigator.pop(context), and `mounted` alone doesn't stop that — it
  // stays true through the pop transition, so a back-arrow tap while an
  // order is still in flight could fire both pops in quick succession,
  // closing this screen AND the watchlist screen underneath it, leaving a
  // blank route. Routing every close through here means only the first
  // call ever actually pops.
  bool _hasClosed = false;
  void _closeTicket() {
    if (_hasClosed) return;
    _hasClosed = true;
    Navigator.pop(context);
  }

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
  // The selected client's open position in this script (master/admin), from
  // GET /master/positions/live-metrics?user_id= — null = none / not loaded.
  Map<String, dynamic>? _clientPosition;
  String? _clientPositionFor;
  bool _showUserDropdown = false;
  bool _isSearchingUsers = false;
  Timer? _userSearchDebounce;
  int _userSearchPage = 1;
  bool _hasMoreUsers = true;
  bool _isLoadingMoreUsers = false;
  String _lastUserQuery = '';
  final ScrollController _userDropdownScrollCtrl = ScrollController();

  /// Returns true if this instrument has **lot-based** limits (e.g. MCX-FUT).
  /// Lot mode: user enters number of lots; actual qty = lots × lot_size.
  bool get _hasLotInfo =>
      (_mcxLotsOnly && _lotSizeForEntry > 0) ||
      (_lotLimitInfo != null &&
          _lotLimitInfo!.lotSize > 0 &&
          !_lotLimitInfo!.isTurnoverMode);

  /// MCX futures and COMEX trade in whole lots only (server rule since 4 Nov
  /// 2026) — the box always takes LOTS for them, for every role, whatever the
  /// client's Lot/Turnover tick and even before the lot info has loaded.
  bool get _mcxLotsOnly {
    final seg = widget.item.instrument.segment.toUpperCase();
    return seg == 'MCX-FUT' || seg == 'COMEX-FUT';
  }

  /// Lot size for lot entry: the client's own (lot info) when known, else the contract's.
  int get _lotSizeForEntry => (_lotLimitInfo?.lotSize ?? 0) > 0
      ? _lotLimitInfo!.lotSize
      : widget.item.instrument.lotSize;

  /// Returns true if this instrument has **turnover-based** limits (e.g. NFO-FUT, SGX, GLOBAL).
  /// Turnover mode: user enters raw quantity directly; max_qty is enforced.
  bool get _hasTurnoverLimit =>
      !_mcxLotsOnly && _lotLimitInfo != null && _lotLimitInfo!.isTurnoverMode;

  /// Returns the actual quantity to send to backend.
  int get _actualQuantity {
    if (_hasLotInfo) {
      return _lotCount * _lotSizeForEntry;
    }
    // For both turnover mode and plain quantity mode, use _quantity directly.
    return _quantity;
  }

  /// Returns true if the current instrument is an option (CE or PE).
  bool get _isOption {
    final type = widget.item.instrument.instrumentType;
    return type == 'CE' || type == 'PE';
  }

  /// Returns the locally known net quantity for this exact instrument token.
  /// Null means metrics do not contain the position and the backend must decide.
  int? _getKnownNetPosition(BuildContext context) {
    final positions =
        Provider.of<TradeMetricsProvider>(context, listen: false).positions;
    final targetToken = widget.item.instrument.instrumentToken.toString();
    for (final pos in positions) {
      if (pos.instrumentToken.toString() == targetToken) {
        return pos.netQty;
      }
    }
    return null;
  }

  /// Maps initialOrderType string to tab index.
  int _mapInitialOrderTypeToTab(String orderType) {
    switch (orderType) {
      case 'Market Execution':
        return 0;
      case 'Buy Limit':
      case 'Sell Limit':
        return 1;
      case 'Buy Stop':
      case 'Sell Stop':
        return 2;
      case 'Custom Price':
        return 3;
      default:
        return 0;
    }
  }

  // Keeps this script's live price ticking while the screen is open, even
  // when it isn't in the watchlist (see WatchlistProvider.track).
  WatchlistProvider? _watchlist;
  // Waiting a moment for a fresh quote before placing (stale-quote guard).
  bool _awaitingQuote = false;

  @override
  void initState() {
    super.initState();
    _watchlist = Provider.of<WatchlistProvider>(context, listen: false);
    _watchlist!.track(widget.item);
    _loadQuickQuantities();

    if (widget.initialSelectedUser != null) {
      _selectedUser = widget.initialSelectedUser;
      _userSearchCtrl.text = widget.initialSelectedUser!['username'] ??
          widget.initialSelectedUser!['name'] ??
          '';
      _fetchLotLimitForUser();
    }

    // Pre-fill quantity from initialQuantity or from current position
    if (widget.initialQuantity != null) {
      _quantity = widget.initialQuantity!;
      _selectedQuickQty = _quickQuantities.contains(_quantity) ? _quantity : -1;
    } else {
      // If opened from watchlist (no initialQuantity), check for open position
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final netQty = _getKnownNetPosition(context) ?? 0;
        if (netQty != 0 && mounted) {
          setState(() {
            _quantity = netQty.abs();
            _selectedQuickQty =
                _quickQuantities.contains(_quantity) ? _quantity : -1;
            _qtyController.text = _quantity.toString();
            if (_mcxLotsOnly && _lotSizeForEntry > 0) {
              final lots = (netQty.abs() / _lotSizeForEntry).round();
              _lotCount = lots > 0 ? lots : 1;
              _selectedQuickLot = _quickLots.contains(_lotCount) ? _lotCount : -1;
              _qtyController.text = _lotCount.toString();
            }
          });
        }
      });
    }

    if (widget.initialOrderType != null) {
      _selectedTab = _mapInitialOrderTypeToTab(widget.initialOrderType!);
    }
    _qtyController.text = _quantity.toString();
    if (_mcxLotsOnly && _lotSizeForEntry > 0) {
      final lots = widget.initialQuantity != null
          ? (widget.initialQuantity! / _lotSizeForEntry).round()
          : 1;
      _lotCount = lots > 0 ? lots : 1;
      _selectedQuickLot = _quickLots.contains(_lotCount) ? _lotCount : -1;
      _qtyController.text = _lotCount.toString();
    }
    _fetchLotLimit();
  }

  Future<void> _fetchLotLimit() async {
    // For admin/master, wait until they select a user
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    if (!profile.isUser) return;

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
          // Check if user has an open position for this instrument
          final netQty = _getKnownNetPosition(context) ?? 0;
          if (netQty != 0 && widget.initialQuantity == null) {
            // Pre-fill from open position
            final absQty = netQty.abs();
            if (info.isTurnoverMode && !_mcxLotsOnly) {
              _quantity = absQty;
              _selectedQuickQty =
                  _quickQuantities.contains(absQty) ? absQty : -1;
              _qtyController.text = absQty.toString();
            } else {
              // Convert raw quantity to lots
              final lots =
                  info.lotSize > 0 ? (absQty / info.lotSize).round() : absQty;
              _lotCount = lots > 0 ? lots : 1;
              _selectedQuickLot =
                  _quickLots.contains(_lotCount) ? _lotCount : -1;
              _qtyController.text = _lotCount.toString();
            }
          } else if (widget.initialQuantity != null && (!info.isTurnoverMode || _mcxLotsOnly)) {
            // initialQuantity was passed (e.g. from orders page square-off) — convert to lots
            final lots = info.lotSize > 0
                ? (widget.initialQuantity! / info.lotSize).round()
                : widget.initialQuantity!;
            _lotCount = lots > 0 ? lots : 1;
            _selectedQuickLot = _quickLots.contains(_lotCount) ? _lotCount : -1;
            _qtyController.text = _lotCount.toString();
          } else if (info.isTurnoverMode && !_mcxLotsOnly) {
            _quantity = widget.initialQuantity ?? 1;
            _selectedQuickQty =
                _quickQuantities.contains(_quantity) ? _quantity : -1;
            _qtyController.text = _quantity.toString();
          } else {
            // No position, no initialQuantity — default to 1 lot
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
    _watchlist?.untrack(widget.item.instrument.instrumentToken);
    _qtyController.dispose();
    _priceController.dispose();
    _userSearchCtrl.dispose();
    _userSearchDebounce?.cancel();
    _userDropdownScrollCtrl.dispose();
    super.dispose();
  }

  void _onUserFieldTap() {
    if (_userResults.isEmpty && !_showUserDropdown) {
      _fetchUsers('');
    } else {
      setState(() => _showUserDropdown = _userResults.isNotEmpty);
    }
  }

  Future<void> _searchUsers(String query) async {
    _userSearchDebounce?.cancel();

    if (query.isEmpty) {
      // Immediately show all users
      _fetchUsers('');
      return;
    }

    _userSearchDebounce = Timer(const Duration(milliseconds: 400), () {
      _fetchUsers(query);
    });
  }

  Future<void> _fetchUsers(String query) async {
    if (mounted) setState(() => _isSearchingUsers = true);
    _lastUserQuery = query;
    _userSearchPage = 1;
    _hasMoreUsers = true;

    try {
      final token = await SecureStorageService().getToken();
      if (!mounted) return;
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      final searchParam = query.isNotEmpty ? '&search=$query' : '';
      final endpoint = profile.isAdmin
          ? '/admin/users?limit=20&page=1$searchParam'
          : '/master/users?limit=20&page=1$searchParam';
      final res = await ApiService(backendUrl).get(endpoint, token: token);
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body);
        final nested = body['data'];
        final List list =
            nested is Map ? (nested['users'] ?? []) : (nested ?? []);
        final total = nested is Map ? (nested['total'] ?? 0) : list.length;
        setState(() {
          _userResults = list.cast<Map<String, dynamic>>();
          _showUserDropdown = _userResults.isNotEmpty;
          _hasMoreUsers = _userResults.length < total;
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isSearchingUsers = false);
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMoreUsers || !_hasMoreUsers) return;
    setState(() => _isLoadingMoreUsers = true);

    try {
      final nextPage = _userSearchPage + 1;
      final token = await SecureStorageService().getToken();
      if (!mounted) return;
      final profile = Provider.of<UserProfileProvider>(context, listen: false);
      final searchParam =
          _lastUserQuery.isNotEmpty ? '&search=$_lastUserQuery' : '';
      final endpoint = profile.isAdmin
          ? '/admin/users?limit=20&page=$nextPage$searchParam'
          : '/master/users?limit=20&page=$nextPage$searchParam';
      final res = await ApiService(backendUrl).get(endpoint, token: token);
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body);
        final nested = body['data'];
        final List list =
            nested is Map ? (nested['users'] ?? []) : (nested ?? []);
        final total = nested is Map ? (nested['total'] ?? 0) : list.length;
        if (list.isNotEmpty) {
          setState(() {
            _userSearchPage = nextPage;
            _userResults.addAll(list.cast<Map<String, dynamic>>());
            _hasMoreUsers = _userResults.length < total;
          });
        } else {
          setState(() => _hasMoreUsers = false);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMoreUsers = false);
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
    _loadClientPosition();
  }

  /// The selected client's position in this script (live-metrics, one request).
  Future<void> _loadClientPosition() async {
    final uid = _selectedUser == null
        ? null
        : (_selectedUser!['id'] ?? _selectedUser!['_id'])?.toString();
    setState(() {
      _clientPosition = null;
      _clientPositionFor = uid;
    });
    if (uid == null || uid.isEmpty) return;
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl)
          .get('/master/positions/live-metrics?user_id=$uid', token: token);
      if (res.statusCode != 200 || !mounted || _clientPositionFor != uid) return;
      final body = jsonDecode(res.body);
      final data = (body['data'] as List?) ?? const [];
      final positions = data.isNotEmpty && data.first is Map
          ? ((data.first as Map)['positions'] as List?) ?? const []
          : const [];
      final target = widget.item.instrument.instrumentToken.toString();
      Map<String, dynamic>? found;
      for (final pos in positions) {
        if (pos is Map &&
            pos['instrument_token']?.toString() == target &&
            ((pos['net_qty'] as num?) ?? 0) != 0) {
          found = Map<String, dynamic>.from(pos);
          break;
        }
      }
      if (mounted && _clientPositionFor == uid) {
        setState(() => _clientPosition = found);
      }
    } catch (_) {}
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
          if (info.isTurnoverMode && !_mcxLotsOnly) {
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

  /// Reports an order this screen blocked before sending it, so it shows in
  /// the Rejection Log (who, when, which script, why). Clients only — admin
  /// and master blocks are their own UI. Fire-and-forget: never awaited and
  /// never changes what the user sees.
  /// The logged-in client isn't allowed this instrument's segment.
  bool _segmentNotPermitted(UserProfileProvider profile) =>
      profile.isUser && !profile.allowsSegment(widget.item.instrument.segment);

  String _notPermittedMessage(int net) {
    final seg = UserProfileProvider.normalizeSegment(widget.item.instrument.segment);
    return 'Your account is not permitted to trade $seg. Contact your master/admin.'
        '${net != 0 ? ' You can only close your existing ${net.abs()} qty position.' : ''}';
  }

  void _reportBlocked(
      String code, String message, String transactionType, double price) {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    if (profile.isAdmin || profile.isMaster) return;
    final orderType = _selectedTab == 1
        ? 'LIMIT'
        : _selectedTab == 2
            ? 'SL'
            : 'MARKET';
    _tradeService.reportBlockedOrder(
      instrumentToken: widget.item.instrument.instrumentToken,
      transactionType: transactionType,
      quantity: _actualQuantity,
      orderType: orderType,
      price: price,
      code: code,
      message: message,
    );
  }

  // Practice accounts: no ₹ — amounts are tokens.
  String get _cur => PracticeSession.isActive ? '' : '₹';

  Future<void> _handleTrade(String transactionType, double currentPrice) async {
    if (_isLoading || _awaitingQuote) return;
    if (!mounted) return;

    // Block trades in investor mode (read-only access)
    final investorMode =
        Provider.of<InvestorModeProvider>(context, listen: false);
    if (investorMode.isInvestor) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trading is not available in investor mode'),
          backgroundColor: Color(0xFF64748B),
        ),
      );
      return;
    }

    // Admin and Master must select a user before placing a trade
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    if ((profile.isAdmin || profile.isMaster) && _selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a user to trade on behalf of'),
          backgroundColor: kColorSell,
        ),
      );
      return;
    }

    // A segment this client isn't allowed: only closing an existing position
    // goes through (same rule the server enforces) — say so up front instead
    // of failing on some other check (938184 got a stale-price message, 26 Oct).
    if (_segmentNotPermitted(profile)) {
      final net = _getKnownNetPosition(context) ?? 0;
      final closing = (transactionType == 'SELL' && net > 0) ||
          (transactionType == 'BUY' && net < 0);
      if (!closing) {
        final msg = _notPermittedMessage(net);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: kColorSell),
        );
        _reportBlocked('NOT_PERMITTED', msg, transactionType, currentPrice);
        return;
      }
    }

    // Check market hours for this instrument's exchange (admin/master bypass this)
    if (!profile.isAdmin && !profile.isMaster) {
      final ex = widget.item.instrument.exchange;
      final sym = widget.item.instrument.tradingsymbol;
      if (!MarketHours.isMarketOpen(exchange: ex, tradingsymbol: sym)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(MarketHours.getMarketStatusMessage(
                exchange: ex, tradingsymbol: sym)),
            backgroundColor: kColorSell,
          ),
        );
        _reportBlocked('MARKET_CLOSED', MarketHours.getMarketStatusMessage(exchange: ex, tradingsymbol: sym), transactionType, currentPrice);
        return;
      }
    }

    // Stale-quote guard: a bid/ask that hasn't ticked in a while is a sign
    // of thin/no volume (or a dropped feed) — trading against it risks a
    // fill at a price that no longer reflects the real market. Blocks the
    // trade with a rejection message rather than just warning, and stays
    // blocked on every retry until WatchlistProvider actually applies a
    // fresh tick (lastUpdated only advances on a genuine tick, so the
    // computed age here keeps growing — and keeps blocking — on its own
    // with no extra state to track). `currentItem` itself is still needed
    // below regardless of role — only the rejection is gated. Admin (only
    // — Master still gets this guard) bypasses the rejection, per explicit
    // instruction: unlike the market-hours check above, this one isn't
    // meant to exempt Master too.
    // Scripts not in the watchlist tick too while this screen is open
    // (WatchlistProvider.track). When the quote is stale at the tap — just
    // reconnected, or just opened — wait up to 3 s for a fresh tick before
    // calling it low volume; a genuinely thin script still stays blocked.
    const staleQuoteThreshold = Duration(seconds: 25);
    final watchlist = Provider.of<WatchlistProvider>(context, listen: false);
    final quoteToken = widget.item.instrument.instrumentToken;
    bool isFresh(WatchlistItem i) =>
        i.lastUpdated != null &&
        DateTime.now().difference(i.lastUpdated!) <= staleQuoteThreshold;
    var currentItem = watchlist.getByToken(quoteToken) ?? widget.item;
    // Practice accounts: simulated prices step every 30 minutes by design,
    // so the stale-quote guard never applies to them.
    if (!profile.isAdmin && !PracticeSession.isActive && !isFresh(currentItem)) {
      _awaitingQuote = true;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(const SnackBar(
        content: Text('Getting live price…'),
        duration: Duration(seconds: 3),
      ));
      try {
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 200));
          if (!mounted) return;
          currentItem = watchlist.getByToken(quoteToken) ?? widget.item;
          if (isFresh(currentItem)) break;
        }
      } finally {
        _awaitingQuote = false;
      }
      messenger.hideCurrentSnackBar();
      if (isFresh(currentItem) && _selectedTab == 0) {
        // Market order: use the fresh quote, not the one shown at the tap.
        final ltp = currentItem.currentPrice ?? 0.0;
        final spread = ltp * 0.0005;
        currentPrice = transactionType == 'BUY'
            ? (currentItem.askPrice ?? (ltp > 0 ? ltp + spread : ltp))
            : (currentItem.bidPrice ?? (ltp > 0 ? ltp - spread : ltp));
      }
    }
    if (!profile.isAdmin && !PracticeSession.isActive && !isFresh(currentItem)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Low volume — price hasn\'t updated recently. Trade blocked until a fresh quote arrives.'),
          backgroundColor: kColorSell,
        ),
      );
      _reportBlocked('STALE_QUOTE', 'Low volume — price hasn\'t updated recently. Trade blocked until a fresh quote arrives.', transactionType, currentPrice);
      return;
    }

    // Lot validation for exchanges with lot assignments
    if (_hasLotInfo) {
      if (_lotCount <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Minimum order is 1 lot'),
            backgroundColor: kColorSell,
          ),
        );
        _reportBlocked('MIN_QTY', 'Minimum order is 1 lot', transactionType, currentPrice);
        return;
      }
      if (_lotLimitInfo != null &&
          !_lotLimitInfo!.isTurnoverMode &&
          _lotCount > _lotLimitInfo!.maxLots) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'You are allowed max ${_lotLimitInfo!.maxLots} lots for this instrument'),
            backgroundColor: kColorSell,
          ),
        );
        _reportBlocked('MAX_LOTS', 'You are allowed max ${_lotLimitInfo!.maxLots} lots for this instrument (requested $_lotCount)', transactionType, currentPrice);
        return;
      }
    }

    // Turnover mode: validate raw quantity against max_qty
    if (_hasTurnoverLimit) {
      if (_quantity <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Quantity must be at least 1'),
            backgroundColor: kColorSell,
          ),
        );
        _reportBlocked('MIN_QTY', 'Quantity must be at least 1', transactionType, currentPrice);
        return;
      }
      if (_quantity > _lotLimitInfo!.maxQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Maximum allowed quantity is ${_lotLimitInfo!.maxQty} for this instrument'),
            backgroundColor: kColorSell,
          ),
        );
        _reportBlocked('MAX_QTY', 'Maximum allowed quantity is ${_lotLimitInfo!.maxQty} for this instrument (requested $_quantity)', transactionType, currentPrice);
        return;
      }
    }

    // Local metrics can be absent or belong to the logged-in admin rather than
    // the selected user. Only reject a known oversell here; exact ownership is
    // authoritatively validated by the backend inside the trade transaction.
    final optionSellError = validateLocalOptionSell(
      isAdmin: profile.isAdmin || profile.isMaster,
      isOption: _isOption,
      transactionType: transactionType,
      requestedQuantity: _actualQuantity,
      knownNetQuantity: _getKnownNetPosition(context),
    );
    if (optionSellError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(optionSellError),
          backgroundColor: Colors.red,
        ),
      );
      _reportBlocked('OPTION_SELL', optionSellError, transactionType, currentPrice);
      return;
    }

    // currentItem already resolved above, by the stale-quote guard.

    // Determine orderType string from selected tab
    // 0=Market, 1=Limit, 2=Stop (SL), 3=Custom (MARKET with custom price)
    final String orderType;
    switch (_selectedTab) {
      case 1:
        orderType = 'LIMIT';
        break;
      case 2:
        orderType = 'SL';
        break;
      case 0:
      case 3:
      default:
        orderType = 'MARKET';
        break;
    }

    final bool usesCustomPrice =
        _selectedTab == 1 || _selectedTab == 2 || _selectedTab == 3;
    final tradePrice = usesCustomPrice
        ? (double.tryParse(_priceController.text) ?? currentPrice)
        : currentPrice;

    // For Limit orders only: validate price against CMP
    // BUY: price must be below or equal to CMP
    // SELL: price must be above or equal to CMP
    // Stop orders skip this — backend handles offset restriction for SL orders
    if (_selectedTab == 1) {
      final cmp = currentItem.currentPrice ?? 0.0;
      if (cmp > 0) {
        if (transactionType == 'BUY' && tradePrice > cmp) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Buy price $_cur${tradePrice.toStringAsFixed(2)} cannot be above CMP $_cur${cmp.toStringAsFixed(2)}'),
              backgroundColor: kColorSell,
            ),
          );
          _reportBlocked('LIMIT_PRICE', 'Buy price $_cur${tradePrice.toStringAsFixed(2)} cannot be above CMP $_cur${cmp.toStringAsFixed(2)}', transactionType, tradePrice);
          return;
        }
        if (transactionType == 'SELL' && tradePrice < cmp) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Sell price $_cur${tradePrice.toStringAsFixed(2)} cannot be below CMP $_cur${cmp.toStringAsFixed(2)}'),
              backgroundColor: kColorSell,
            ),
          );
          _reportBlocked('LIMIT_PRICE', 'Sell price $_cur${tradePrice.toStringAsFixed(2)} cannot be below CMP $_cur${cmp.toStringAsFixed(2)}', transactionType, tradePrice);
          return;
        }
      }
    }

    // Circuit limit validation
    final upper = currentItem.upperCircuitLimit;
    final lower = currentItem.lowerCircuitLimit;
    if (upper != null && tradePrice > upper) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Price ${tradePrice.toStringAsFixed(2)} exceeds upper circuit limit ${upper.toStringAsFixed(2)}'),
          backgroundColor: kColorSell,
        ),
      );
      _reportBlocked('CIRCUIT', 'Price ${tradePrice.toStringAsFixed(2)} exceeds upper circuit limit ${upper.toStringAsFixed(2)}', transactionType, tradePrice);
      return;
    }
    if (lower != null && tradePrice < lower) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Price ${tradePrice.toStringAsFixed(2)} is below lower circuit limit ${lower.toStringAsFixed(2)}'),
          backgroundColor: kColorSell,
        ),
      );
      _reportBlocked('CIRCUIT', 'Price ${tradePrice.toStringAsFixed(2)} is below lower circuit limit ${lower.toStringAsFixed(2)}', transactionType, tradePrice);
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
      orderType: orderType,
      userId: _selectedUser != null
          ? (_selectedUser!['id'] ?? _selectedUser!['_id'])?.toString()
          : null,
      noBrokerage: _selectedTab == 3 && _carryForwardNoBrokerage,
    );

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.$2),
        backgroundColor: result.$1 ? Colors.green : Colors.red,
        duration: const Duration(seconds: 1),
      ),
    );

    if (result.$1) {
      // Play trade bell sound if enabled
      TradeSoundService().playIfEnabled();
      // Traded straight from search: the script joins the watchlist.
      if (widget.addToWatchlistOnOrder && mounted) {
        try {
          final wp = Provider.of<WatchlistProvider>(context, listen: false);
          if (!wp.contains(widget.item.instrument.instrumentToken)) {
            await wp.addInstrument(widget.item.instrument);
          }
        } catch (_) {}
      }
      // Refresh positions and wait for data before navigating back
      try {
        if (mounted) {
          await Provider.of<TradeMetricsProvider>(context, listen: false)
              .fetchBaseData();
        }
        if (mounted) {
          await Provider.of<UserProfileProvider>(context, listen: false)
              .refreshProfile();
        }
      } catch (_) {}
      if (mounted) {
        _closeTicket();
      }
    }
  }

  /// Builds a single tab button for the order type selector.
  Widget _buildTabButton(String label, int tabIndex) {
    final isSelected = _selectedTab == tabIndex;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTab = tabIndex;
            // Pre-fill price for Limit/Stop tabs
            if (tabIndex == 1 || tabIndex == 2) {
              final currentItem =
                  Provider.of<WatchlistProvider>(context, listen: false)
                          .getByToken(widget.item.instrument.instrumentToken) ??
                      widget.item;
              final ltp = currentItem.currentPrice ?? 0.0;
              final spread = ltp * 0.0005;
              final askPrice =
                  currentItem.askPrice ?? (ltp > 0 ? ltp + spread : ltp);
              _priceController.text = askPrice.toStringAsFixed(2);
            }
          });
        },
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color:
                isSelected ? kBrandPrimary : kChipBg,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : kChipFg,
              fontSize: kFontSizeBody,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    // Masters and admins must select a user before trading
    final bool isMasterBlocked =
        (profile.isMaster || profile.isAdmin) && _selectedUser == null;

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
                  // Brand top bar (colour only, 1 Nov 2026).
                  color: kTopBarBg,
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _closeTicket,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: ShapeDecoration(
                            color: kTopBarTile,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(44),
                            ),
                          ),
                          child:
                              const Icon(Icons.arrow_back, color: kTopBarFg),
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
                                color: kTopBarFg,
                                fontSize: kFontSizeViewTitle,
                                fontFamily: kFontFamily,
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
                              color: kTopBarTile,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text(
                                  'LTP',
                                  style: TextStyle(
                                    color: kTopBarFgMuted,
                                    fontSize: kFontSizeBadge,
                                    fontFamily: kFontFamily,
                                    fontWeight: kFontWeightSemiBold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  '${(currentItem.currentPrice ?? 0.0).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    color: kTopBarFg,
                                    fontSize: kFontSizeBody,
                                    fontFamily: kFontFamily,
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
                            style: const TextStyle(
                              // On the blue top bar (the sign is in the text).
                              color: kTopBarFgMuted,
                              fontSize: kFontSizeNavLabel,
                              fontFamily: kFontFamily,
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

            // Order Type tabs
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
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildTabButton('Market', 0),
                      const SizedBox(width: 6),
                      _buildTabButton('Limit', 1),
                      const SizedBox(width: 6),
                      _buildTabButton('Stop', 2),
                      if (profile.isAdmin) ...[
                        const SizedBox(width: 6),
                        _buildTabButton('Custom', 3),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Info button (visible to regular users only — admin/master see it in user section)
            Consumer<UserProfileProvider>(
              builder: (context, userProfile, child) {
                if (!userProfile.isUser) {
                  return const SizedBox
                      .shrink(); // Admin/Master has info in user section
                }
                return Padding(
                  padding:
                      const EdgeInsets.only(left: 16, right: 16, bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      GestureDetector(
                        onTap: () => showInfoSheet(
                          context,
                          instrumentToken:
                              widget.item.instrument.instrumentToken,
                          tradingsymbol: widget.item.instrument.tradingsymbol,
                          lotSize: _lotLimitInfo?.lotSize,
                          maxQty: _lotLimitInfo?.maxQty,
                          breakQty: _lotLimitInfo?.breakQty,
                          groupName: _lotLimitInfo?.groupName,
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: kIconSizeMedium,
                                color: kBrandPrimary),
                            SizedBox(width: 4),
                            Text(
                              'Info',
                              style: TextStyle(
                                color: kBrandPrimary,
                                fontSize: kFontSizeBody,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

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
                                  fontSize: kFontSizeSectionHeader,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightMedium,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => showInfoSheet(
                                  context,
                                  instrumentToken:
                                      widget.item.instrument.instrumentToken,
                                  tradingsymbol:
                                      widget.item.instrument.tradingsymbol,
                                  lotSize: _lotLimitInfo?.lotSize,
                                  maxQty: _lotLimitInfo?.maxQty,
                                  breakQty: _lotLimitInfo?.breakQty,
                                  groupName: _lotLimitInfo?.groupName,
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        size: kIconSizeMedium,
                                        color: kBrandPrimary),
                                    SizedBox(width: 4),
                                    Text(
                                      'Info',
                                      style: TextStyle(
                                        color: kBrandPrimary,
                                        fontSize: kFontSizeSectionHeader,
                                        fontFamily: kFontFamily,
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
                                    onTap: _onUserFieldTap,
                                    style: const TextStyle(
                                      color: kColorTextPrimary,
                                      fontSize: kFontSizeButtonText,
                                      fontFamily: kFontFamily,
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
                                        fontFamily: kFontFamily,
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
                                        color: kBrandPrimary),
                                  )
                                else if (_selectedUser != null)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedUser = null;
                                        _clientPosition = null;
                                        _clientPositionFor = null;
                                        _userSearchCtrl.clear();
                                        _userResults = [];
                                        _showUserDropdown = false;
                                      });
                                    },
                                    child: const Icon(Icons.close,
                                        size: kIconSizeDefault,
                                        color: Color(0xFF8E8E93)),
                                  )
                                else
                                  const Icon(Icons.search,
                                      size: kIconSizeMedium,
                                      color: Color(0xFF8E8E93)),
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
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification is ScrollEndNotification &&
                                      notification.metrics.pixels >=
                                          notification.metrics.maxScrollExtent -
                                              50) {
                                    _loadMoreUsers();
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _userDropdownScrollCtrl,
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: _userResults.length +
                                      (_hasMoreUsers ? 1 : 0),
                                  itemBuilder: (_, i) {
                                    if (i == _userResults.length) {
                                      return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 8),
                                        child: Center(
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: kBrandPrimary),
                                          ),
                                        ),
                                      );
                                    }
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
                                                color: kColorTextMuted),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '$name (@$uname)',
                                                style: const TextStyle(
                                                  color: kColorTextPrimary,
                                                  fontSize: kFontSizeBody,
                                                  fontFamily: kFontFamily,
                                                  fontWeight:
                                                      kFontWeightRegular,
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
                      color: kColorTextPrimary,
                      fontSize: kFontSizeSectionHeader,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium,
                      height: 1.25,
                    ),
                  ),
                  if (_hasTurnoverLimit) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Max: ${_lotLimitInfo!.maxQty} qty',
                      style: const TextStyle(
                        color: kColorTextMuted,
                        fontSize: kFontSizeSubtitle,
                        fontFamily: kFontFamily,
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
                            width: 1, color: Color(0xFFE1E6F2)),
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
                              color: kColorTextPrimary,
                              fontSize: kFontSizeSectionHeader,
                              fontFamily: kFontFamily,
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
                                  color: kChipBg,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4)),
                                ),
                                child: const Icon(Icons.remove,
                                    size: kIconSizeDefault),
                              ),
                            ),
                            const SizedBox(width: 11),
                            GestureDetector(
                              onTap: _incrementQuantity,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: ShapeDecoration(
                                  color: kChipBg,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4)),
                                ),
                                child: const Icon(Icons.add,
                                    size: kIconSizeDefault),
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
                                    ? kBrandPrimary
                                    : kChipBg,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$lot Lot${lot > 1 ? 's' : ''}',
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFFF9F9F9)
                                      : kChipFg,
                                  fontSize: kFontSizeBody,
                                  fontFamily: kFontFamily,
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
                                    ? kBrandPrimary
                                    : kChipBg,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6)),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$qty',
                                style: TextStyle(
                                  color: isSelected
                                      ? const Color(0xFFF9F9F9)
                                      : kChipFg,
                                  fontSize: kFontSizeBody,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightRegular,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (_qtyLotSize > 1) _buildLotQuickRow(),
                  ],

                  // ── Turnover-mode info banner ─────────────────────────────
                  if (_hasTurnoverLimit) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: kBrandPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: kBrandPrimary
                                .withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.info_outline,
                                  size: kIconSizeDefault,
                                  color: kBrandPrimary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: 'Max qty: ',
                                        style: TextStyle(
                                          color: kColorTextMuted,
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: kFontFamily,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${_lotLimitInfo!.maxQty}',
                                        style: const TextStyle(
                                          color: kBrandPrimary,
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightSemiBold,
                                        ),
                                      ),
                                      if (_lotLimitInfo!.breakQty > 0) ...[
                                        const TextSpan(
                                          text: '  •  Break qty: ',
                                          style: TextStyle(
                                            color: kColorTextMuted,
                                            fontSize: kFontSizeSubtitle,
                                            fontFamily: kFontFamily,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '${_lotLimitInfo!.breakQty}',
                                          style: const TextStyle(
                                            color: kBrandPrimary,
                                            fontSize: kFontSizeSubtitle,
                                            fontFamily: kFontFamily,
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
                              color: kColorBuy
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: kIconSizeSmall,
                                    color: kColorBuy),
                                const SizedBox(width: 6),
                                Text(
                                  'Order: $_quantity qty',
                                  style: const TextStyle(
                                    color: kColorBuy,
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: kFontFamily,
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
                        color: kBrandPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kBrandPrimary),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Loading lot info...',
                            style: TextStyle(
                              color: kColorTextMuted,
                              fontSize: kFontSizeSubtitle,
                              fontFamily: kFontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_hasLotInfo &&
                      _lotLimitInfo != null &&
                      !_lotLimitInfo!.isTurnoverMode) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: kBrandPrimary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: kBrandPrimary
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
                                    size: kIconSizeSmall,
                                    color: kColorTextMuted),
                                const SizedBox(width: 6),
                                Text(
                                  _lotLimitInfo!.groupName!,
                                  style: const TextStyle(
                                    color: kColorTextMuted,
                                    fontSize: kFontSizeNavLabel,
                                    fontFamily: kFontFamily,
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
                                  size: kIconSizeDefault,
                                  color: kBrandPrimary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      const TextSpan(
                                        text: '1 Lot = ',
                                        style: TextStyle(
                                          color: kColorTextMuted,
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: kFontFamily,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${_lotLimitInfo!.lotSize} qty',
                                        style: const TextStyle(
                                          color: kBrandPrimary,
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightSemiBold,
                                        ),
                                      ),
                                      const TextSpan(
                                        text: '  •  Max: ',
                                        style: TextStyle(
                                          color: kColorTextMuted,
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: kFontFamily,
                                        ),
                                      ),
                                      TextSpan(
                                        text: '${_lotLimitInfo!.maxLots} Lots',
                                        style: const TextStyle(
                                          color: kBrandPrimary,
                                          fontSize: kFontSizeSubtitle,
                                          fontFamily: kFontFamily,
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
                              color: kColorBuy
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline,
                                    size: kIconSizeSmall,
                                    color: kColorBuy),
                                const SizedBox(width: 6),
                                Text(
                                  'Order: $_lotCount Lot${_lotCount > 1 ? 's' : ''} = $_actualQuantity qty',
                                  style: const TextStyle(
                                    color: kColorBuy,
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: kFontFamily,
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

                      if (_selectedTab == 0) {
                        // ── Market tab: SELL and BUY with bid/ask prices ──
                        final showSell = widget.forceSide == null ||
                            widget.forceSide == 'SELL';
                        final showBuy = widget.forceSide == null ||
                            widget.forceSide == 'BUY';
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sell side
                            if (showSell)
                              Builder(builder: (context) {
                                final sellDisabled = isMasterBlocked ||
                                    (_isOption &&
                                        !profile.isAdmin &&
                                        !profile.isMaster &&
                                        _getKnownNetPosition(context) != null &&
                                        _getKnownNetPosition(context)! <= 0);
                                return Expanded(
                                  child: Column(
                                    children: [
                                      Container(
                                        width: double.infinity,
                                        height: 46,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16, vertical: 13),
                                        decoration: ShapeDecoration(
                                          color: const Color(0xFFFFF8F7),
                                          shape: RoundedRectangleBorder(
                                            side: const BorderSide(
                                                width: 1,
                                                color: Color(0xFFF3D3CF)),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            sellPrice.toStringAsFixed(2),
                                            style: const TextStyle(
                                              color: kColorTextPrimary,
                                              fontSize: kFontSizeSectionHeader,
                                              fontFamily: kFontFamily,
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
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: const Text(
                                              'SELL',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    kFontSizeSectionHeader,
                                                fontFamily: kFontFamily,
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
                            if (showSell && showBuy) const SizedBox(width: 14),
                            // Buy side
                            if (showBuy)
                              Expanded(
                                child: Column(
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      height: 46,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 13),
                                      decoration: ShapeDecoration(
                                        color: const Color(0xFFF6F9FF),
                                        shape: RoundedRectangleBorder(
                                          side: const BorderSide(
                                              width: 1,
                                              color: Color(0xFFCFDDFB)),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                      child: Center(
                                        child: Text(
                                          buyPrice.toStringAsFixed(2),
                                          style: const TextStyle(
                                            color: kColorTextPrimary,
                                            fontSize: kFontSizeSectionHeader,
                                            fontFamily: kFontFamily,
                                            fontWeight: kFontWeightMedium,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    GestureDetector(
                                      onTap: isMasterBlocked
                                          ? null
                                          : () {
                                              _handleTrade('BUY', buyPrice);
                                            },
                                      child: Opacity(
                                        opacity: isMasterBlocked ? 0.4 : 1.0,
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
                                                kBrandGradientStart,
                                                kBrandGradientEnd,
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'BUY',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: kFontSizeSectionHeader,
                                              fontFamily: kFontFamily,
                                              fontWeight: kFontWeightSemiBold,
                                              height: 1.25,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      } else if (_selectedTab == 1 || _selectedTab == 2) {
                        // ── Limit / Stop tab: price input + SELL and BUY side by side ──
                        final sellDisabled = isMasterBlocked ||
                            (_isOption &&
                                !profile.isAdmin &&
                                !profile.isMaster &&
                                _getKnownNetPosition(context) != null &&
                                _getKnownNetPosition(context)! <= 0);
                        final showSell = widget.forceSide == null ||
                            widget.forceSide == 'SELL';
                        final showBuy = widget.forceSide == null ||
                            widget.forceSide == 'BUY';
                        return Column(
                          children: [
                            // Price input field
                            Container(
                              width: double.infinity,
                              height: 46,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: kColorTextPrimary,
                                    fontSize: kFontSizeSectionHeader,
                                    fontFamily: kFontFamily,
                                    fontWeight: kFontWeightMedium,
                                  ),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: buyPrice.toStringAsFixed(2),
                                    hintStyle: const TextStyle(
                                      color: Color(0xFFC7C7CC),
                                      fontSize: kFontSizeSectionHeader,
                                      fontFamily: kFontFamily,
                                      fontWeight: kFontWeightMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            // SELL and BUY buttons side by side
                            Row(
                              children: [
                                // SELL button
                                if (showSell)
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: sellDisabled
                                          ? null
                                          : () {
                                              final price = double.tryParse(
                                                  _priceController.text);
                                              if (price == null || price <= 0) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'Enter a valid price'),
                                                      backgroundColor:
                                                          kColorSell),
                                                );
                                                return;
                                              }
                                              _handleTrade('SELL', price);
                                            },
                                      child: Opacity(
                                        opacity: sellDisabled ? 0.4 : 1.0,
                                        child: Container(
                                          height: 56,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                Color(0xFFFF3C00),
                                                Color(0xFF7A0F37),
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'SELL',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    kFontSizeSectionHeader,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightSemiBold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (showSell && showBuy)
                                  const SizedBox(width: 14),
                                // BUY button
                                if (showBuy)
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: isMasterBlocked
                                          ? null
                                          : () {
                                              final price = double.tryParse(
                                                  _priceController.text);
                                              if (price == null || price <= 0) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'Enter a valid price'),
                                                      backgroundColor:
                                                          kColorSell),
                                                );
                                                return;
                                              }
                                              _handleTrade('BUY', price);
                                            },
                                      child: Opacity(
                                        opacity: isMasterBlocked ? 0.4 : 1.0,
                                        child: Container(
                                          height: 56,
                                          decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                kBrandGradientStart,
                                                kBrandGradientEnd,
                                              ],
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              'BUY',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    kFontSizeSectionHeader,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightSemiBold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      } else {
                        // ── Custom tab (admin only): price input + SELL/BUY buttons ──
                        return Column(
                          children: [
                            Container(
                              width: double.infinity,
                              height: 46,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
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
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d+\.?\d{0,2}')),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: kColorTextPrimary,
                                    fontSize: kFontSizeSectionHeader,
                                    fontFamily: kFontFamily,
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
                                      fontFamily: kFontFamily,
                                      fontWeight: kFontWeightMedium,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'No brokerage on this trade',
                                  style: TextStyle(
                                    color: Color(0xFF2B2B2B),
                                    fontSize: kFontSizeBody,
                                    fontFamily: kFontFamily,
                                    fontWeight: kFontWeightMedium,
                                  ),
                                ),
                                Switch(
                                  value: _carryForwardNoBrokerage,
                                  onChanged: (value) {
                                    setState(() {
                                      _carryForwardNoBrokerage = value;
                                    });
                                  },
                                  activeThumbColor: kBrandGradientEnd,
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      final customPrice = double.tryParse(
                                          _priceController.text);
                                      if (customPrice == null ||
                                          customPrice <= 0) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('Enter a valid price'),
                                              backgroundColor:
                                                  kColorSell),
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
                                          colors: [
                                            Color(0xFFFF3C00),
                                            Color(0xFF7A0F37)
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: Text('SELL',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    kFontSizeSectionHeader,
                                                fontFamily: kFontFamily,
                                                fontWeight:
                                                    kFontWeightSemiBold)),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      final customPrice = double.tryParse(
                                          _priceController.text);
                                      if (customPrice == null ||
                                          customPrice <= 0) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('Enter a valid price'),
                                              backgroundColor:
                                                  kColorSell),
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
                                          colors: [
                                            kBrandGradientStart,
                                            kBrandGradientEnd
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Center(
                                        child: Text('BUY',
                                            style: TextStyle(
                                                color: Colors.white,
                                                fontSize:
                                                    kFontSizeSectionHeader,
                                                fontFamily: kFontFamily,
                                                fontWeight:
                                                    kFontWeightSemiBold)),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      }
                    },
                  ),
                  _buildOhlcLine(),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Open position in this script (own / selected client's)
            _buildPositionSection(context),

            // Segment not permitted for this client
            Builder(
              builder: (context) {
                final profile = Provider.of<UserProfileProvider>(context);
                if (!_segmentNotPermitted(profile)) return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: kColorSell.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.block, size: kIconSizeDefault, color: kColorSell),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _notPermittedMessage(_getKnownNetPosition(context) ?? 0),
                          style: const TextStyle(
                            color: kColorSell,
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightMedium,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Market closed warning (hidden for admin)
            Builder(
              builder: (context) {
                final profile =
                    Provider.of<UserProfileProvider>(context, listen: false);
                if (profile.isAdmin) return const SizedBox.shrink();
                final ex = widget.item.instrument.exchange;
                final sym = widget.item.instrument.tradingsymbol;
                if (MarketHours.isMarketOpen(exchange: ex, tradingsymbol: sym))
                  return const SizedBox.shrink();
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: kColorSell.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time,
                          size: kIconSizeDefault, color: kColorSell),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          MarketHours.getMarketStatusMessage(
                              exchange: ex, tradingsymbol: sym),
                          style: const TextStyle(
                            color: kColorSell,
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
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
                  // Hidden for a client who isn't allowed this underlying's options.
                  if (Provider.of<UserProfileProvider>(context).allowsSegment(
                      OptionChainView.optionSegmentFor(widget.item.instrument)))
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
                        Icon(Icons.link,
                            size: kIconSizeDefault, color: kBrandPrimary),
                        SizedBox(width: 4),
                        Text(
                          'Option Chain',
                          style: TextStyle(
                            color: kBrandPrimary,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
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
                            size: kIconSizeDefault, color: kBrandPrimary),
                        SizedBox(width: 4),
                        Text(
                          'View chart',
                          style: TextStyle(
                            color: kBrandPrimary,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
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
                        Icon(Icons.layers,
                            size: kIconSizeDefault, color: kBrandPrimary),
                        SizedBox(width: 4),
                        Text(
                          'Market Depth',
                          style: TextStyle(
                            color: kBrandPrimary,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
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

    return PopScope(
      canPop: !_isLoading,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        body: PageWash(child: AbsorbPointer(
          absorbing: _isLoading,
          child: Stack(
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
        )),
      ),
    );
  }

  /// Lot size for the lot row: the order limits' lot size, else the script's.
  int get _qtyLotSize {
    final fromInfo = _lotLimitInfo?.lotSize ?? 0;
    return fromInfo > 0 ? fromInfo : widget.item.instrument.lotSize;
  }

  /// 1 lot … 5 lot under the quantity buttons (quantity-mode scripts): fills
  /// the quantity with that many lots.
  Widget _buildLotQuickRow() {
    final size = _qtyLotSize;
    final lotsNow = (_quantity > 0 && _quantity % size == 0) ? _quantity ~/ size : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            for (int i = 0; i < _quickLots.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () => _setQuantity(_quickLots[i] * size),
                  child: Container(
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: lotsNow == _quickLots[i]
                          ? kBrandPrimary.withValues(alpha: 0.08)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: lotsNow == _quickLots[i]
                            ? kBrandPrimary
                            : kBrandPrimary.withValues(alpha: 0.3),
                        width: lotsNow == _quickLots[i] ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '${_quickLots[i]} lot',
                      maxLines: 1,
                      style: TextStyle(
                        color: kBrandPrimary,
                        fontSize: kFontSizeBody,
                        fontFamily: kFontFamily,
                        fontWeight: lotsNow == _quickLots[i]
                            ? kFontWeightSemiBold
                            : kFontWeightMedium,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          lotsNow > 0 ? '$lotsNow lot = $_quantity qty' : '1 lot = $size qty',
          style: const TextStyle(
            color: kColorTextMuted,
            fontSize: 11,
            fontFamily: kFontFamily,
          ),
        ),
      ],
    );
  }

  /// O H L C on one line under SELL/BUY (was four boxes below the ticket).
  Widget _buildOhlcLine() {
    return Consumer<WatchlistProvider>(
      builder: (context, provider, _) {
        final item =
            provider.getByToken(widget.item.instrument.instrumentToken) ??
                widget.item;
        Widget cell(String key, double? value) => Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$key ',
                        style: const TextStyle(
                          color: kColorTextMuted,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                      TextSpan(
                        text: (value ?? 0).toStringAsFixed(2),
                        style: const TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.only(top: 10),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFF0F1F4))),
          ),
          child: Row(
            children: [
              cell('O', item.open),
              cell('H', item.high),
              cell('L', item.low),
              cell('C', item.close),
            ],
          ),
        );
      },
    );
  }

  /// The open position in this script: the client's own, or (master/admin)
  /// the selected client's. Nothing when there is none.
  Widget _buildPositionSection(BuildContext context) {
    final profile = Provider.of<UserProfileProvider>(context);
    if (profile.isAdmin || profile.isMaster) {
      final p = _clientPosition;
      if (_selectedUser == null || p == null) return const SizedBox.shrink();
      final net = ((p['net_qty'] as num?) ?? 0).toInt();
      if (net == 0) return const SizedBox.shrink();
      final avg = ((net > 0 ? p['avg_buy_price'] : p['avg_sell_price']) as num?)
              ?.toDouble() ??
          0;
      final lotSize = (p['lot_size'] as num?)?.toInt() ?? 0;
      final name =
          (_selectedUser!['name'] ?? _selectedUser!['username'] ?? 'Client')
              .toString();
      return Consumer<WatchlistProvider>(
        builder: (context, provider, _) {
          final item =
              provider.getByToken(widget.item.instrument.instrumentToken) ??
                  widget.item;
          final ltp = (item.currentPrice != null && item.currentPrice! > 0)
              ? item.currentPrice!
              : ((p['ltp'] as num?)?.toDouble() ?? avg);
          // Same exit price as the positions engine: bid for a long, ask for a short.
          final side = net > 0 ? item.bidPrice : item.askPrice;
          final cmp = (side != null && side > 0) ? side : ltp;
          final pnl = net > 0 ? (cmp - avg) * net : (avg - cmp) * net.abs();
          return _positionCard(
              "${name.toUpperCase()}'S POSITION", net, avg, ltp, pnl, lotSize);
        },
      );
    }
    return Consumer<TradeMetricsProvider>(
      builder: (context, metrics, _) {
        final target = widget.item.instrument.instrumentToken.toString();
        PositionAgg? pos;
        for (final p in metrics.positions) {
          if (p.instrumentToken.toString() == target && p.netQty != 0) {
            pos = p;
            break;
          }
        }
        if (pos == null) return const SizedBox.shrink();
        final avg = pos.netQty > 0 ? pos.avgBuyPrice : pos.avgSellPrice;
        return _positionCard('YOUR POSITION', pos.netQty, avg,
            pos.ltp > 0 ? pos.ltp : avg, pos.floating, pos.lotSize);
      },
    );
  }

  /// Positions-page style card: side, qty @ average, live price, open P&L.
  Widget _positionCard(
      String label, int net, double avg, double ltp, double pnl, int lotSize) {
    final isLong = net > 0;
    final sideColor = isLong ? kColorBuy : kColorSell;
    final pnlColor = pnl >= 0 ? kColorBuy : kColorSell;
    final qty = net.abs();
    final lots =
        (lotSize > 1 && qty % lotSize == 0) ? ' (${qty ~/ lotSize} lot)' : '';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 6),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kColorTextMuted,
                fontSize: 11,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightMedium,
                letterSpacing: 0.4,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E9F0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.instrument.tradingsymbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizePositionSymbol,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: sideColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isLong ? 'LONG' : 'SHORT',
                              style: TextStyle(
                                color: sideColor,
                                fontSize: kFontSizePositionDetail,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightSemiBold,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$qty qty$lots @ ${avg.toStringAsFixed(2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: kColorTextMuted,
                                fontSize: kFontSizeCaption,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightMedium,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      ltp.toStringAsFixed(2),
                      style: const TextStyle(
                        color: kColorTextPrimary,
                        fontSize: kFontSizePositionPnl,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          pnl >= 0 ? Icons.north_east : Icons.south_west,
                          size: 12,
                          color: pnlColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: pnlColor,
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
