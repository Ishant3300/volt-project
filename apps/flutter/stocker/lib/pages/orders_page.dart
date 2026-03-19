import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/views/trade_card_view.dart';
import 'package:stocker/pages/master_instrument_users_page.dart';
import 'package:stocker/services/live_price_service.dart';
import 'package:stocker/views/username_view.dart';
import 'package:stocker/models/master.dart';
import 'package:stocker/services/admin_service.dart';

import 'dart:convert';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class _NumberFormat {
  final double value;
  final String suffix;
  const _NumberFormat(this.value, this.suffix);
}

_NumberFormat _getShortForm(double value) {
  final absVal = value.abs();
  if (absVal >= 1000000000) {
    return _NumberFormat(value / 1000000000, 'B');
  } else if (absVal >= 1000000) {
    return _NumberFormat(value / 1000000, 'M');
  } else if (absVal >= 1000) {
    return _NumberFormat(value / 1000, 'K');
  } else {
    return _NumberFormat(value, '');
  }
}

/// Volume label for a position: "+X LOTS" or "+X QTY".
String _positionVolumeLabel(String exchange, String tradingsymbol, int quantity,
    {bool showPrefix = false, String segment = '', int lotSize = 1}) {
  final seg = segment.toUpperCase();

  // Only MCX-FUT, MCX-OPT, NFO-OPT use lots. Everything else uses quantity.
  final bool isLot = seg == 'MCX-FUT' || seg == 'MCX-OPT' || seg == 'NFO-OPT';

  final prefix =
      showPrefix ? (quantity > 0 ? '+' : (quantity < 0 ? '-' : '')) : '';
  final String unit;
  int displayQty = quantity.abs();

  if (isLot && lotSize > 0) {
    unit = 'LOT';
    displayQty = (displayQty / lotSize).round();
  } else {
    unit = 'QTY';
  }

  return '$prefix$displayQty $unit';
}

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedPositionTokens = {};
  bool _metricsExpanded = false;

  // Master-specific state
  bool _masterLoading = false;
  List<Map<String, dynamic>> _masterPositions = [];

  // Live metrics for master view
  final LivePriceService _livePriceService = LivePriceService();
  List<Map<String, dynamic>> _userMetrics = [];
  final Map<String, double> _ltpMap = {};
  Set<String> _allTokens = {};
  double _masterPositionPnl = 0;

  // Admin-specific state
  bool _adminLoading = false;
  List<Map<String, dynamic>> _adminMasterMetrics = [];
  final Map<String, double> _adminMasterPnl = {}; // master_id → live P&L

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProfile =
          Provider.of<UserProfileProvider>(context, listen: false);
      if (userProfile.isAdmin) {
        _fetchAdminMasterMetrics();
        _setupMasterLivePrices();
      } else if (userProfile.isMaster) {
        _fetchMasterPositions();
        _fetchUserMetrics();
        _setupMasterLivePrices();
      }
    });
  }

  @override
  void dispose() {
    _livePriceService.onTickReceived = null;
    _livePriceService.onConnectionChanged = null;
    final userProfile =
        Provider.of<UserProfileProvider>(context, listen: false);
    if ((userProfile.isMaster || userProfile.isAdmin) &&
        _allTokens.isNotEmpty) {
      _livePriceService.unsubscribe(_allTokens.toList());
    }
    _livePriceService.disconnect();
    super.dispose();
  }

  void _setupMasterLivePrices() {
    _livePriceService.onTickReceived = (tick) {
      final token = tick['instrument_token']?.toString();
      if (token == null) return;
      final price = (tick['last_price'] as num?)?.toDouble();
      if (price == null || !mounted) return;

      setState(() {
        _ltpMap[token] = price;
        _recalcMasterMetrics();
        _recalcAdminMasterPnl();
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
      final storage = SecureStorageService();
      final token = await storage.getToken();
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
    if (_allTokens.isNotEmpty) {
      _livePriceService.subscribe(_allTokens.toList());
    }
  }

  Future<void> _fetchUserMetrics() async {
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final apiService = ApiService(backendUrl);
      final res =
          await apiService.get('/master/positions/user-metrics', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = body['data'] ?? [];
        final Set<String> tokens = {};

        _userMetrics = data.cast<Map<String, dynamic>>();

        for (final user in _userMetrics) {
          final List positions = user['positions'] ?? [];
          for (final pos in positions) {
            final t = pos['instrument_token']?.toString();
            if (t != null) tokens.add(t);
          }
        }

        _allTokens = tokens;
        _recalcMasterMetrics();

        if (_livePriceService.isConnected && tokens.isNotEmpty) {
          _livePriceService.subscribe(tokens.toList());
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching user metrics: $e');
    }
  }

  void _recalcMasterMetrics() {
    double totalPnl = 0;

    for (final user in _userMetrics) {
      final double realised = (user['realised_pnl'] as num?)?.toDouble() ?? 0;
      double floating = 0;
      final List positions = user['positions'] ?? [];

      for (final pos in positions) {
        final String iToken = pos['instrument_token']?.toString() ?? '';
        final int buyQty = (pos['total_buy_qty'] as num?)?.toInt() ?? 0;
        final int sellQty = (pos['total_sell_qty'] as num?)?.toInt() ?? 0;
        final double buyVal = (pos['total_buy_value'] as num?)?.toDouble() ?? 0;
        final double sellVal =
            (pos['total_sell_value'] as num?)?.toDouble() ?? 0;
        final int netQty = buyQty - sellQty;

        final double avgBuy = buyQty > 0 ? buyVal / buyQty : 0;
        final double avgSell = sellQty > 0 ? sellVal / sellQty : 0;
        final double ltp = _ltpMap[iToken] ??
            (pos['avg_buy_price'] as num?)?.toDouble() ??
            (netQty > 0 ? avgBuy : avgSell);

        if (netQty > 0)
          floating += (ltp - avgBuy) * netQty;
        else if (netQty < 0) floating += (avgSell - ltp) * netQty.abs();
      }
      totalPnl += realised + floating;
    }
    _masterPositionPnl = (totalPnl * 100).roundToDouble() / 100;
  }

  // ============================================
  // ADMIN: Fetch all masters with their users' positions
  // ============================================
  Future<void> _fetchAdminMasterMetrics() async {
    setState(() => _adminLoading = true);
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final apiService = ApiService(backendUrl);
      final res = await apiService.get(
        '/master/positions/admin-master-metrics',
        token: token,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = body['data'] ?? [];
        final Set<String> tokens = {};

        _adminMasterMetrics = data.cast<Map<String, dynamic>>();

        // Collect all instrument tokens across all masters
        for (final master in _adminMasterMetrics) {
          final List positions = master['positions'] ?? [];
          for (final pos in positions) {
            final t = pos['instrument_token']?.toString();
            if (t != null) tokens.add(t);
          }
        }

        _allTokens = tokens;
        _recalcAdminMasterPnl();

        if (_livePriceService.isConnected && tokens.isNotEmpty) {
          _livePriceService.subscribe(tokens.toList());
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching admin master metrics: $e');
    } finally {
      if (mounted) setState(() => _adminLoading = false);
    }
  }

  /// Recalculate per-master P&L using live LTP prices.
  void _recalcAdminMasterPnl() {
    for (final master in _adminMasterMetrics) {
      final String masterId = master['master_id'] ?? '';
      final double realised = (master['realised_pnl'] as num?)?.toDouble() ?? 0;
      double floating = 0;
      final List positions = master['positions'] ?? [];

      for (final pos in positions) {
        final String iToken = pos['instrument_token']?.toString() ?? '';
        final int buyQty = (pos['total_buy_qty'] as num?)?.toInt() ?? 0;
        final int sellQty = (pos['total_sell_qty'] as num?)?.toInt() ?? 0;
        final double buyVal = (pos['total_buy_value'] as num?)?.toDouble() ?? 0;
        final double sellVal =
            (pos['total_sell_value'] as num?)?.toDouble() ?? 0;
        final int netQty = buyQty - sellQty;

        final double avgBuy = buyQty > 0 ? buyVal / buyQty : 0;
        final double avgSell = sellQty > 0 ? sellVal / sellQty : 0;
        final double ltp = _ltpMap[iToken] ??
            (pos['avg_buy_price'] as num?)?.toDouble() ??
            (netQty > 0 ? avgBuy : avgSell);

        if (netQty > 0)
          floating += (ltp - avgBuy) * netQty;
        else if (netQty < 0) floating += (avgSell - ltp) * netQty.abs();
      }
      _adminMasterPnl[masterId] =
          ((realised + floating) * 100).roundToDouble() / 100;
    }
  }

  Future<void> _openMasterProfile(String masterId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(
            color: Color(0xFF3F45C7), strokeWidth: 2.5),
      ),
    );
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final res = await adminService.getMasterById(masterId);
      if (!mounted) return;
      Navigator.pop(context); // dismiss loader
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          final master = Master.fromJson(body['data']);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => UsernameView(master: master)),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint('Error opening master profile: $e');
    }
  }

  Future<void> _fetchMasterPositions() async {
    setState(() => _masterLoading = true);
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final apiService = ApiService(backendUrl);
      final res =
          await apiService.get('/master/positions/aggregated', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = body['data'] ?? [];
        setState(() {
          _masterPositions = data.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      debugPrint('Error fetching master positions: $e');
    } finally {
      setState(() => _masterLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = Provider.of<UserProfileProvider>(context);
    if (userProfile.isAdmin) {
      return _buildAdminView();
    }
    if (userProfile.isMaster) {
      return _buildMasterView();
    }
    return _buildUserView();
  }

  // ============================================
  // ADMIN VIEW
  // ============================================
  Widget _buildAdminView() {
    // Calculate total P&L across all masters
    double totalPnl = 0;
    for (final pnl in _adminMasterPnl.values) {
      totalPnl += pnl;
    }
    final bool isTotalPositive = totalPnl >= 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchAdminMasterMetrics,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Total P&L card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
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
                      const Text(
                        'ALL MASTERS P&L',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedFlipCounter(
                        value: totalPnl,
                        fractionDigits: 2,
                        prefix: '₹',
                        textStyle: TextStyle(
                          color: isTotalPositive
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontSize: 24,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_adminMasterMetrics.length} master${_adminMasterMetrics.length != 1 ? "s" : ""}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Masters list
                if (_adminLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(
                          color: Color(0xFF3F45C7), strokeWidth: 2.5),
                    ),
                  )
                else if (_adminMasterMetrics.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
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
                            'No masters found',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    clipBehavior: Clip.antiAlias,
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
                        for (int i = 0;
                            i < _adminMasterMetrics.length;
                            i++) ...[
                          _buildAdminMasterItem(_adminMasterMetrics[i]),
                          if (i < _adminMasterMetrics.length - 1)
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdminMasterItem(Map<String, dynamic> master) {
    final String masterId = master['master_id'] ?? '';
    final String name = master['name'] ?? '';
    final String username = master['username'] ?? '';
    final int userCount = (master['user_count'] as num?)?.toInt() ?? 0;
    final double pnl = _adminMasterPnl[masterId] ?? 0;
    final bool isPnlPositive = pnl >= 0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openMasterProfile(masterId),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF3F45C7).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                  style: const TextStyle(
                    color: Color(0xFF3F45C7),
                    fontSize: 18,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Name + username + user count
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        username,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFCBD5E1))),
                      ),
                      const Icon(Icons.people_outline,
                          size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 3),
                      Text(
                        '$userCount user${userCount != 1 ? "s" : ""}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Live P&L
            AnimatedFlipCounter(
              value: pnl,
              fractionDigits: 2,
              prefix: '₹',
              textStyle: TextStyle(
                color: isPnlPositive
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================
  // MASTER VIEW
  // ============================================
  Widget _buildMasterView() {
    // Calculate totals
    int totalNetQty = 0;
    for (final pos in _masterPositions) {
      totalNetQty += (pos['net_qty'] as num?)?.toInt() ?? 0;
    }

    final bool isPnlPositive = _masterPositionPnl >= 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              _fetchMasterPositions(),
              _fetchUserMetrics(),
            ]);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Master Position Summary Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
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
                      const Text(
                        'MASTER POSITION',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedFlipCounter(
                        value: _masterPositionPnl,
                        fractionDigits: 2,
                        prefix: '₹',
                        textStyle: TextStyle(
                          color: isPnlPositive
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontSize: 24,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${_masterPositions.length} instrument${_masterPositions.length != 1 ? "s" : ""}',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Color(0xFFCBD5E1),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Net Qty: ${totalNetQty > 0 ? "+" : ""}$totalNetQty',
                            style: TextStyle(
                              color: totalNetQty >= 0
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              fontSize: 12,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Instruments list
                if (_masterLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (_masterPositions.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
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
                            child: const Icon(Icons.inventory_2_outlined,
                                size: 28, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No open positions across users',
                            style: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 14,
                              fontFamily: 'Inter',
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    clipBehavior: Clip.antiAlias,
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
                        for (int i = 0; i < _masterPositions.length; i++) ...[
                          _buildMasterPositionItem(_masterPositions[i]),
                          if (i < _masterPositions.length - 1)
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMasterPositionItem(Map<String, dynamic> pos) {
    final String symbol = pos['tradingsymbol'] ?? '';
    final String exchange = pos['exchange'] ?? '';
    final int netQty = (pos['net_qty'] as num?)?.toInt() ?? 0;
    final int userCount = (pos['user_count'] as num?)?.toInt() ?? 0;
    final bool isLong = netQty > 0;
    final Color sideColor =
        isLong ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MasterInstrumentUsersPage(
              instrumentToken: pos['instrument_token'] ?? '',
              tradingsymbol: symbol,
              exchange: exchange,
              netQty: netQty,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          symbol,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                        exchange,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.people_outline,
                          size: 14, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(
                        '$userCount user${userCount != 1 ? "s" : ""}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Net qty badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: sideColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _positionVolumeLabel(exchange, symbol, netQty,
                    showPrefix: isLong,
                    segment: pos['segment'] ?? '',
                    lotSize: (pos['lot_size'] as num?)?.toInt() ?? 1),
                style: TextStyle(
                  color: sideColor,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 20, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  // ============================================
  // USER VIEW (existing, unchanged)
  // ============================================
  Widget _buildUserView() {
    return Consumer<TradeMetricsProvider>(
      builder: (context, provider, child) {
        // Filter out closed positions (netQty == 0)
        final openPositions =
            provider.positions.where((p) => p.netQty != 0).toList();

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
          backgroundColor: const Color(0xFFF8FAFC),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Position Info Card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Align(
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'POSITION',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 14,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 8),
                              AnimatedFlipCounter(
                                value: posPnl,
                                fractionDigits: 2,
                                textStyle: TextStyle(
                                  color: isPosPnlPositive
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFEF4444),
                                  fontSize: 24,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: -12,
                          top: -12,
                          child: GestureDetector(
                            onTap: () {
                              _showInfoSheet(context, posPnl, realised, m2m,
                                  credit, marginUsed, freeMargin, equity);
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Icon(Icons.info_outline,
                                  color: Color(0xFF64748B), size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // P&L Detail Rows
                  Container(
                    width: double.infinity,
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildMetricRow('Realised P&L', realised),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildMetricRow('M2M P&L', m2m),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        _buildMetricRow('Credit', credit),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _metricsExpanded
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Divider(
                                        height: 1, color: Color(0xFFF1F5F9)),
                                    _buildMetricRow('Equity', equity),
                                    const Divider(
                                        height: 1, color: Color(0xFFF1F5F9)),
                                    _buildMetricRow('Margin Used', marginUsed),
                                    const Divider(
                                        height: 1, color: Color(0xFFF1F5F9)),
                                    _buildMetricRow('Free Margin', freeMargin),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                        const Divider(height: 1, color: Color(0xFFF1F5F9)),
                        GestureDetector(
                          onTap: () => setState(
                              () => _metricsExpanded = !_metricsExpanded),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: AnimatedRotation(
                              turns: _metricsExpanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Action Bar (Square Off trigger OR selection controls)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_isSelectionMode) ...[
                        // Cancel button
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSelectionMode = false;
                              _selectedPositionTokens.clear();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                color: Color(0xFF374151),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        // Select All + count
                        Row(
                          children: [
                            Text(
                              '${_selectedPositionTokens.length} selected',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontFamily: 'Inter',
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  if (_selectedPositionTokens.length ==
                                      openPositions.length) {
                                    _selectedPositionTokens.clear();
                                  } else {
                                    _selectedPositionTokens.clear();
                                    _selectedPositionTokens.addAll(openPositions
                                        .map((p) => p.instrumentToken));
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF3F45C7).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _selectedPositionTokens.length ==
                                          openPositions.length
                                      ? 'Deselect All'
                                      : 'Select All',
                                  style: const TextStyle(
                                    color: Color(0xFF3F45C7),
                                    fontSize: 12,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _selectedPositionTokens.isEmpty
                                  ? null
                                  : () => _squareOffSelected(openPositions),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _selectedPositionTokens.isEmpty
                                      ? const Color(0xFFE2E8F0)
                                      : const Color(0xFFFF3B30),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Square Off',
                                  style: TextStyle(
                                    color: _selectedPositionTokens.isEmpty
                                        ? const Color(0xFF9CA3AF)
                                        : Colors.white,
                                    fontSize: 12,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (openPositions.isNotEmpty)
                        const SizedBox.shrink()
                      else
                        const SizedBox.shrink(),
                      if (!_isSelectionMode && openPositions.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isSelectionMode = true;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0).withOpacity(0.5),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_box_outlined,
                                    size: 14, color: Color(0xFF3F45C7)),
                                SizedBox(width: 4),
                                Text(
                                  'Square Off',
                                  style: TextStyle(
                                    color: Color(0xFF3F45C7),
                                    fontSize: 12,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Orders List
                  Container(
                    width: double.infinity,
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (openPositions.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(32.0),
                            child: Text(
                              'No open positions',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 16,
                                fontFamily: 'Inter',
                              ),
                            ),
                          )
                        else
                          ...openPositions.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final pos = entry.value;
                            final isBuy = pos.netQty > 0;
                            final isNegative = pos.floating < 0;
                            final watchlist = Provider.of<WatchlistProvider>(context, listen: false);
                            final wItem = watchlist.getByToken(pos.instrumentToken);
                            final displayName = wItem?.instrument.userFriendlyName ?? pos.tradingsymbol;
                            return Column(
                              children: [
                                _buildOrderItem(
                                  context,
                                  pos,
                                  displayName,
                                  pos.exchange,
                                  '${isBuy ? "BUY" : "SELL"}: ${_positionVolumeLabel(pos.exchange, pos.tradingsymbol, pos.netQty, segment: pos.segment, lotSize: pos.lotSize)}',
                                  isBuy ? pos.avgBuyPrice : pos.avgSellPrice,
                                  pos.ltp,
                                  pos.floating,
                                  isNegative,
                                ),
                                if (idx != openPositions.length - 1)
                                  const Divider(
                                      height: 1, color: Color(0xFFE2E8F0)),
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

  Widget _buildMetricRow(String label, double value) {
    final bool isColored = label.contains('P&L') || label == 'Free Margin';
    final Color valueColor = isColored
        ? (value >= 0 ? const Color(0xFF22C55E) : const Color(0xFFEF4444))
        : const Color(0xFF0F172A);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
          AnimatedFlipCounter(
            value: value,
            fractionDigits: 2,
            prefix: '₹',
            textStyle: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoSheet(
      BuildContext context,
      double posPnl,
      double realised,
      double m2m,
      double credit,
      double marginUsed,
      double freeMargin,
      double equity) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Detailed Values',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 18,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailedRow('Position P&L', posPnl),
                _buildDetailedRow('Realised P&L', realised),
                _buildDetailedRow('M2M P&L', m2m),
                _buildDetailedRow('Credit', credit),
                _buildDetailedRow('Equity', equity),
                _buildDetailedRow('Margin Used', marginUsed),
                _buildDetailedRow('Free Margin', freeMargin),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailedRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _openPositionCard(BuildContext context, PositionAgg position) {
    final watchlistProvider =
        Provider.of<WatchlistProvider>(context, listen: false);

    final isLong = position.netQty > 0;
    final closeQuantity = position.netQty.abs();

    WatchlistItem? existingItem =
        watchlistProvider.getByToken(position.instrumentToken);

    final WatchlistItem itemToUse;
    if (existingItem != null) {
      itemToUse = existingItem;
    } else {
      final instrument = KiteInstrument(
        id: '',
        instrumentToken: position.instrumentToken,
        exchangeToken: '',
        tradingsymbol: position.tradingsymbol,
        name: position.tradingsymbol,
        rawName: position.tradingsymbol,
        displayName: position.tradingsymbol,
        lastPrice: position.ltp > 0
            ? position.ltp
            : (isLong ? position.avgBuyPrice : position.avgSellPrice),
        strike: 0,
        tickSize: 0.05,
        lotSize: 1,
        instrumentType: '',
        segment: '',
        exchange: position.exchange,
        isActive: true,
        updatedAt: DateTime.now(),
      );

      itemToUse = WatchlistItem(
        id: position.instrumentToken,
        instrument: instrument,
        currentPrice: position.ltp > 0 ? position.ltp : null,
        lastUpdated: DateTime.now(),
      );
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TradeCardPage(
          item: itemToUse,
          initialOrderType: 'Market Execution',
          initialQuantity: closeQuantity,
        ),
      ),
    );
  }

  Widget _buildOrderItem(
      BuildContext context,
      PositionAgg position,
      String name,
      String exchange,
      String qtyInfo,
      double atp,
      double cmp,
      double pnl,
      bool isNegative) {
    final Color valueColor =
        isNegative ? const Color(0xFFEF4444) : const Color(0xFF22C55E);

    final bool isSelected =
        _selectedPositionTokens.contains(position.instrumentToken);

    return GestureDetector(
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedPositionTokens.remove(position.instrumentToken);
            } else {
              _selectedPositionTokens.add(position.instrumentToken);
            }
          });
        } else {
          _openPositionCard(context, position);
        }
      },
      onLongPress: () {
        if (!_isSelectionMode) {
          setState(() {
            _isSelectionMode = true;
            _selectedPositionTokens.add(position.instrumentToken);
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        color: isSelected
            ? const Color(0xFFE3F2FD)
            : Colors
                .transparent, // required for full-row tap in gesture detector
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isSelectionMode)
              const Icon(
                Icons.check_box_outline_blank,
                size: 20,
                color: Color(0xFF8E8E93),
              ),
            if (isSelected)
              const Icon(
                Icons.check_box,
                size: 20,
                color: Color(0xFF0A1E46),
              ),
            if (_isSelectionMode) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        exchange,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    qtyInfo,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text(
                        'ATP: ',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      AnimatedFlipCounter(
                        value: atp,
                        fractionDigits: 2,
                        textStyle: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'CMP: ',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      AnimatedFlipCounter(
                        value: cmp,
                        fractionDigits: 2,
                        textStyle: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedFlipCounter(
              value: pnl,
              fractionDigits: 2,
              prefix: '₹',
              textStyle: TextStyle(
                color: valueColor,
                fontSize: 14,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _squareOffSelected(List<PositionAgg> allPositions) async {
    final selectedPositions = allPositions
        .where((p) => _selectedPositionTokens.contains(p.instrumentToken))
        .toList();

    if (selectedPositions.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Square Off Positions',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to square off ${selectedPositions.length} position(s)?\n\n'
                'This will place opposite market orders to close these positions.',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFFEF2F2),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Square Off',
                      style: TextStyle(
                        color: Color(0xFFEF4444), // standard red
                        fontSize: 14,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final apiService = ApiService(backendUrl);
      int successCount = 0;
      int failCount = 0;
      final List<String> errors = [];

      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Place opposite orders for each selected position
      for (final position in selectedPositions) {
        try {
          // Determine opposite side based on net quantity
          final oppositeType = position.netQty > 0 ? 'SELL' : 'BUY';

          // Place market order to close position
          final response = await apiService.post(
            '/trade',
            {
              'instrument_token': position.instrumentToken,
              'tradingsymbol': position.tradingsymbol,
              'exchange': position.exchange,
              'transaction_type': oppositeType,
              'quantity': position.netQty.abs(),
              'order_type': 'MARKET',
              'price': position.ltp > 0
                  ? position.ltp
                  : (position.netQty > 0
                      ? position.avgBuyPrice
                      : position.avgSellPrice),
            },
            token: token,
          );

          if (response.statusCode == 200 || response.statusCode == 201) {
            successCount++;
          } else {
            failCount++;
            final body = jsonDecode(response.body);
            errors.add(
                '${position.tradingsymbol}: ${body['message'] ?? 'Failed'}');
          }
        } catch (e) {
          failCount++;
          errors.add('${position.tradingsymbol}: ${e.toString()}');
        }
      }

      // Close loading dialog
      if (mounted) {
        Navigator.pop(context);
      }

      // Refresh data
      final metricsProvider =
          Provider.of<TradeMetricsProvider>(context, listen: false);
      await metricsProvider.fetchBaseData();

      // Exit selection mode
      setState(() {
        _isSelectionMode = false;
        _selectedPositionTokens.clear();
      });

      // Show result
      if (mounted) {
        String message = '';
        if (successCount > 0 && failCount == 0) {
          message = 'Successfully squared off $successCount position(s)';
        } else if (successCount > 0 && failCount > 0) {
          message = 'Squared off $successCount position(s), $failCount failed';
        } else {
          message = 'Failed to square off positions';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: failCount == 0
                ? const Color(0xFF34C759)
                : const Color(0xFFFF9500),
            duration: const Duration(seconds: 3),
          ),
        );

        // Show errors if any
        if (errors.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Square Off Errors',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 18,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: SingleChildScrollView(
                        child: Text(
                          errors.join('\n'),
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF1F5F9),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Close loading dialog if open
      if (mounted) {
        Navigator.pop(context);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }
}
