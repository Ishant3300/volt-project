import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/live_price_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/views/trade_card_view.dart';

class MasterInstrumentUsersPage extends StatefulWidget {
  final String instrumentToken;
  final String tradingsymbol;
  final String exchange;
  final int netQty;

  const MasterInstrumentUsersPage({
    super.key,
    required this.instrumentToken,
    required this.tradingsymbol,
    required this.exchange,
    required this.netQty,
  });

  @override
  State<MasterInstrumentUsersPage> createState() =>
      _MasterInstrumentUsersPageState();
}

class _MasterInstrumentUsersPageState extends State<MasterInstrumentUsersPage> {
  final ApiService _apiService = ApiService(backendUrl);
  final SecureStorageService _storage = SecureStorageService();
  final LivePriceService _livePriceService = LivePriceService();
  bool _isLoading = true;

  // Per-user breakdown for this instrument (for the card list)
  List<Map<String, dynamic>> _users = [];

  // Per-user full metrics (6 metrics across all instruments)
  Map<String, Map<String, dynamic>> _userMetrics = {};

  // Live LTP for this instrument
  double? _ltp;

  // All instrument tokens across all users' positions (for live subscription)
  Set<String> _allTokens = {};

  // LTP map for all instruments (for recalculating metrics live)
  final Map<String, double> _ltpMap = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchData();
    _setupLivePrices();
  }

  @override
  void dispose() {
    if (_allTokens.isNotEmpty) {
      _livePriceService.unsubscribe(_allTokens.toList());
    }
    _livePriceService.disconnect();
    _searchController.dispose();
    super.dispose();
  }

  void _setupLivePrices() {
    _livePriceService.onTickReceived = (tick) {
      final token = tick['instrument_token']?.toString();
      if (token == null) return;
      final price = (tick['last_price'] as num?)?.toDouble();
      if (price == null || !mounted) return;

      setState(() {
        _ltpMap[token] = price;
        if (token == widget.instrumentToken) {
          _ltp = price;
        }
      });
    };

    // Server-pushed metrics from metricsEngine — use for accurate P&L
    _livePriceService.onMetricsUpdate = (data) {
      if (!mounted) return;
      final userId = data['user_id']?.toString() ?? '';
      if (userId.isEmpty) return;
      setState(() {
        _userMetrics[userId] = Map<String, dynamic>.from(data);
      });
    };

    // Server-pushed master metrics — update all users at once
    _livePriceService.onMasterMetricsUpdate = (data) {
      if (!mounted) return;
      final List users = data['users'] ?? [];
      setState(() {
        for (final u in users) {
          final uid = u['user_id']?.toString() ?? '';
          if (uid.isNotEmpty) {
            _userMetrics[uid] = Map<String, dynamic>.from(u);
          }
        }
      });
    };

    _livePriceService.onConnectionChanged = (connected) {
      if (connected) {
        _authenticateAndSubscribe();
      }
    };

    _livePriceService.connect();
  }

  Future<void> _authenticateAndSubscribe() async {
    try {
      final token = await _storage.getToken();
      if (token != null) {
        // Backend derives identity from the verified token; no client-claimed id.
        _livePriceService.authenticate(token);
      }
    } catch (e) {
      log('⚠️ Failed to authenticate WebSocket: $e');
    }
    // Subscribe to all tokens we know about
    final tokens = _allTokens.toList();
    if (tokens.isNotEmpty) {
      _livePriceService.subscribe(tokens);
    }
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final token = await _storage.getToken();

      // Fetch both endpoints in parallel
      final results = await Future.wait([
        _apiService.get(
          '/master/positions/aggregated/${widget.instrumentToken}',
          token: token,
        ),
        _apiService.get(
          '/master/positions/user-metrics',
          token: token,
        ),
      ]);

      // Parse instrument breakdown
      if (results[0].statusCode == 200) {
        final body = jsonDecode(results[0].body);
        final List users = body['data']?['users'] ?? [];
        _users = users.cast<Map<String, dynamic>>();
      }

      // Parse user metrics
      if (results[1].statusCode == 200) {
        final body = jsonDecode(results[1].body);
        final List data = body['data'] ?? [];
        final Map<String, Map<String, dynamic>> metricsMap = {};
        final Set<String> tokens = {widget.instrumentToken};

        for (final user in data) {
          final uid = user['user_id']?.toString() ?? '';
          metricsMap[uid] = Map<String, dynamic>.from(user);

          // Collect all instrument tokens from user positions for live subscription
          final List positions = user['positions'] ?? [];
          for (final pos in positions) {
            final t = pos['instrument_token']?.toString();
            if (t != null) tokens.add(t);
          }
        }

        _userMetrics = metricsMap;
        _allTokens = tokens;

        // Subscribe to all tokens if already connected
        if (_livePriceService.isConnected && tokens.isNotEmpty) {
          _livePriceService.subscribe(tokens.toList());
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error fetching data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Opens the order ticket directly for this client + script, instead of
  /// the old flow (loading dialog -> fetch full user -> full account
  /// overview page). Mirrors username_view.dart's _openTradeCardFor: no
  /// network call needed, since everything the ticket needs is already on
  /// this page — the matching entry in this user's already-fetched
  /// _userMetrics positions (same source the P&L figure on this card reads
  /// from) carries lot_size/segment, with the widget-level exchange as a
  /// fallback if that position isn't found for some reason.
  void _openTradeTicket(Map<String, dynamic> user) {
    final String userId = user['user_id']?.toString() ?? '';
    if (userId.isEmpty) return;

    Map<String, dynamic>? positionData;
    final userMetrics = _userMetrics[userId];
    if (userMetrics != null) {
      final List positions = userMetrics['positions'] ?? [];
      for (final pos in positions) {
        if (pos['instrument_token']?.toString() == widget.instrumentToken) {
          positionData = Map<String, dynamic>.from(pos);
          break;
        }
      }
    }

    final instrument = KiteInstrument(
      id: '',
      instrumentToken: widget.instrumentToken,
      exchangeToken: '',
      tradingsymbol: widget.tradingsymbol,
      name: widget.tradingsymbol,
      rawName: widget.tradingsymbol,
      displayName: widget.tradingsymbol,
      lastPrice: _ltp ?? 0,
      strike: 0,
      tickSize: 0.05,
      lotSize: (positionData?['lot_size'] as num?)?.toInt() ?? 1,
      instrumentType: '',
      segment: positionData?['segment'] ?? widget.exchange,
      exchange: positionData?['exchange'] ?? widget.exchange,
      isActive: true,
      updatedAt: DateTime.now(),
    );
    final item = WatchlistItem(
      id: widget.instrumentToken,
      instrument: instrument,
      currentPrice: _ltp,
      lastUpdated: DateTime.now(),
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TradeCardPage(
          item: item,
          initialSelectedUser: {
            'id': userId,
            'name': user['name'],
            'username': user['username'],
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isNetLong = widget.netQty > 0;
    final Color sideColor =
        isNetLong ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    final query = _searchQuery.toLowerCase();
    final filteredUsers = query.isEmpty
        ? _users
        : _users.where((u) {
            final name = (u['name'] ?? '').toString().toLowerCase();
            final username = (u['username'] ?? '').toString().toLowerCase();
            return name.contains(query) || username.contains(query);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                    child: Container(
                      height: 40,
                      width: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: kIconSizeDefault, color: Color(0xFF475569)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.tradingsymbol,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeSectionHeader,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              widget.exchange,
                              style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: kFontSizeSubtitle,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightMedium,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              width: 4,
                              height: 4,
                              decoration: const BoxDecoration(
                                color: Color(0xFFCBD5E1),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Net: ${widget.netQty > 0 ? "+" : ""}${widget.netQty}',
                              style: TextStyle(
                                color: sideColor,
                                fontSize: kFontSizeSubtitle,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightSemiBold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // LTP badge
                  if (_ltp != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: kBrandPrimary.withValues(alpha: 0.08),
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
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightSemiBold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _ltp!.toStringAsFixed(2),
                            style: const TextStyle(
                              color: kBrandPrimary,
                              fontSize: kFontSizeBody,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightBold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Icon(Icons.search,
                          size: 18, color: Color(0xFF94A3B8)),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        style: const TextStyle(
                          fontSize: kFontSizeBodySmall,
                          color: Color(0xFF0F172A),
                          fontFamily: kFontFamily,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Search client...',
                          hintStyle: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeBodySmall,
                            fontFamily: kFontFamily,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                        ),
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // User count label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    _searchQuery.isEmpty
                        ? '${_users.length} user${_users.length != 1 ? "s" : ""} with open positions'
                        : '${filteredUsers.length} of ${_users.length} user${_users.length != 1 ? "s" : ""}',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: kFontSizeSubtitle,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightMedium,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Users list
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredUsers.isEmpty
                      ? _buildEmptyState(
                          isSearching: _searchQuery.isNotEmpty)
                      : RefreshIndicator(
                          onRefresh: _fetchData,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: filteredUsers.length,
                            itemBuilder: (context, index) {
                              return _buildUserCard(filteredUsers[index]);
                            },
                          ),
                        ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({bool isSearching = false}) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
                isSearching ? Icons.search_off : Icons.people_outline,
                size: 28, color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),
          Text(
            isSearching
                ? 'No clients match your search'
                : 'No users with open positions',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: kFontSizeBody,
              fontFamily: kFontFamily,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final String userId = user['user_id']?.toString() ?? '';
    final int netQty = user['net_qty'] ?? 0;
    final String side = user['side'] ?? 'FLAT';
    final bool isBuy = side == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final double avgPrice = (isBuy
                ? (user['avg_buy_price'] as num?)
                : (user['avg_sell_price'] as num?))
            ?.toDouble() ??
        0.0;

    // Floating P&L for THIS instrument from metricsEngine (single source of truth)
    double? instrumentPnl;
    final userMetrics = _userMetrics[userId];
    if (userMetrics != null) {
      final List positions = userMetrics['positions'] ?? [];
      for (final pos in positions) {
        if (pos['instrument_token']?.toString() == widget.instrumentToken) {
          instrumentPnl = (pos['floating_pnl'] as num?)?.toDouble();
          break;
        }
      }
    }
    // Fallback to local LTP calculation if metricsEngine data not available yet
    if (instrumentPnl == null && _ltp != null) {
      if (isBuy) {
        instrumentPnl =
            (_ltp! - ((user['avg_buy_price'] as num?)?.toDouble() ?? 0)) *
                netQty;
      } else {
        instrumentPnl =
            (((user['avg_sell_price'] as num?)?.toDouble() ?? 0) - _ltp!) *
                netQty.abs();
      }
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (userId.isNotEmpty) _openTradeTicket(user);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // User header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  // Avatar
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kBrandPrimary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        (user['name'] ?? 'U')[0].toUpperCase(),
                        style: const TextStyle(
                          color: kBrandPrimary,
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightBold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user['name'] ?? 'Unknown',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeName,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightName,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${user['username'] ?? ''}',
                          style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightRegular,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Side badge + instrument P&L
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$side ${netQty.abs()} QTY',
                          style: TextStyle(
                            color: sideColor,
                            fontSize: kFontSizeNavLabel,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightBold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Avg: ',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeNavLabel,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightMedium,
                            ),
                          ),
                          Text(
                            avgPrice.toStringAsFixed(2),
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeNavLabel,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightMedium,
                            ),
                          ),
                        ],
                      ),
                      if (instrumentPnl != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          '${instrumentPnl >= 0 ? '+' : ''}${instrumentPnl.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: instrumentPnl >= 0
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightBold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
