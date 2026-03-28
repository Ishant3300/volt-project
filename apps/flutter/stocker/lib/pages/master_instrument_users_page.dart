import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:stocker/models/user.dart' as user_model;
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/live_price_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'package:stocker/views/username_view.dart';

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
        _recalcMetricsWithLtp();
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
        final payload = Jwt.parseJwt(token);
        final userId = payload['id'] as String?;
        if (userId != null) {
          _livePriceService.authenticate(userId);
        }
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

  /// Recalculate per-user metrics using live LTP values.
  /// Mirrors the exact logic from TradeMetricsProvider._calculateMetrics()
  void _recalcMetricsWithLtp() {
    for (final entry in _userMetrics.entries) {
      final user = entry.value;
      final List positions = user['positions'] ?? [];
      if (positions.isEmpty) continue;

      final double balance = (user['balance'] as num?)?.toDouble() ?? 0;

      double totalRealised = 0;
      double totalFloating = 0;

      for (final pos in positions) {
        final String iToken = pos['instrument_token']?.toString() ?? '';
        final int totalBuyQty = _getIntFromPos(pos, 'total_buy_qty');
        final int totalSellQty = _getIntFromPos(pos, 'total_sell_qty');
        final double totalBuyValue = _getDoubleFromPos(pos, 'total_buy_value');
        final double totalSellValue = _getDoubleFromPos(pos, 'total_sell_value');
        final int netQty = totalBuyQty - totalSellQty;

        final double avgBuyPrice =
            totalBuyQty > 0 ? totalBuyValue / totalBuyQty : 0;
        final double avgSellPrice =
            totalSellQty > 0 ? totalSellValue / totalSellQty : 0;

        // Use live LTP if available, else fall back to avg price
        final double ltp = _ltpMap[iToken] ??
            (pos['avg_buy_price'] as num?)?.toDouble() ??
            avgBuyPrice;

        double realised = 0;
        double floating = 0;

        if (netQty > 0) {
          realised = totalSellValue - (totalSellQty * avgBuyPrice);
          floating = (ltp - avgBuyPrice) * netQty;
        } else if (netQty < 0) {
          realised = (totalBuyQty * avgSellPrice) - totalBuyValue;
          floating = (avgSellPrice - ltp) * netQty.abs();
        } else {
          realised = totalSellValue - totalBuyValue;
          floating = 0;
        }

        totalRealised += realised;
        totalFloating += floating;

        // Margin — we don't have margin rules on frontend here,
        // so keep the server-computed value as base
      }

      final double m2m = totalRealised + totalFloating;
      final double marginUsed =
          (user['margin_used'] as num?)?.toDouble() ?? 0;
      final double equity = balance + m2m;
      final double freeMargin = equity - marginUsed;

      user['realised_pnl'] = _round2(totalRealised);
      user['position_pnl'] = _round2(totalFloating);
      user['m2m_pnl'] = _round2(m2m);
      user['equity'] = _round2(equity);
      user['free_margin'] = _round2(freeMargin);
    }
  }

  int _getIntFromPos(dynamic pos, String key) {
    return (pos[key] as num?)?.toInt() ?? 0;
  }

  double _getDoubleFromPos(dynamic pos, String key) {
    return (pos[key] as num?)?.toDouble() ?? 0;
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  Future<void> _openUserProfile(String userId) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final token = await _storage.getToken();
      final res = await _apiService.get('/master/users/$userId', token: token);

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          final user = user_model.User.fromJson(body['data']);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsernameView(user: user),
            ),
          );
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load user details')),
      );
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isNetLong = widget.netQty > 0;
    final Color sideColor =
        isNetLong ? const Color(0xFF10B981) : const Color(0xFFEF4444);

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
                            fontFamily: 'Inter',
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
                                fontFamily: 'Inter',
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
                                fontFamily: 'Inter',
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
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
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
                          _ltp!.toStringAsFixed(2),
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
                ],
              ),
            ),

            // User count label
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_users.length} user${_users.length != 1 ? "s" : ""} with open positions',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: kFontSizeSubtitle,
                      fontFamily: 'Inter',
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
                  : _users.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _fetchData,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              return _buildUserCard(_users[index]);
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

  Widget _buildEmptyState() {
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
            child: const Icon(Icons.people_outline,
                size: 28, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),
          const Text(
            'No users with open positions',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
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
        ?.toDouble() ?? 0.0;

    // Floating P&L for THIS instrument using live LTP
    double? instrumentPnl;
    if (_ltp != null) {
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
        if (userId.isNotEmpty) _openUserProfile(userId);
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
                    color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      (user['name'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF3F45C7),
                        fontSize: kFontSizeSectionHeader,
                        fontFamily: 'Inter',
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
                          fontFamily: 'Inter',
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
                          fontFamily: 'Inter',
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
                          fontFamily: 'Inter',
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
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium,
                          ),
                        ),
                        Text(
                            avgPrice.toStringAsFixed(2),
                            style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeNavLabel,
                            fontFamily: 'Inter',
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
                          fontFamily: 'Inter',
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
