import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import 'package:stocker/utils/market_hours.dart';

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
  final ex = exchange.toUpperCase();

  // Only MCX-FUT, MCX-OPT, NFO-OPT use lots. Everything else uses quantity.
  // Fall back to exchange='MCX' if segment is not available from backend.
  final bool isLot = seg == 'MCX-FUT' ||
      seg == 'MCX-OPT' ||
      seg == 'NFO-OPT' ||
      (seg.isEmpty && ex == 'MCX');

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
  double _masterRealisedPnl = 0;
  double _masterM2mPnl = 0;

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
      });
    };

    // Server-pushed master metrics (from metricsEngine)
    _livePriceService.onMasterMetricsUpdate = (data) {
      if (!mounted) return;
      setState(() {
        // Use server-computed values directly (single source of truth)
        double totalRealised = 0;
        double totalPositionPnl = 0;

        final List users = data['users'] ?? [];
        for (final u in users) {
          final uid = u['user_id']?.toString() ?? '';
          totalRealised += (u['realised_pnl'] as num?)?.toDouble() ?? 0;
          totalPositionPnl += (u['position_pnl'] as num?)?.toDouble() ?? 0;

          if (uid.isEmpty) continue;
          for (final um in _userMetrics) {
            if (um['user_id']?.toString() == uid) {
              um['equity'] = u['equity'];
              um['m2m_pnl'] = u['m2m_pnl'];
              um['position_pnl'] = u['position_pnl'];
              um['realised_pnl'] = u['realised_pnl'];
              um['positions'] = u['positions'];
              break;
            }
          }
        }

        _masterRealisedPnl = (totalRealised * 100).roundToDouble() / 100;
        _masterPositionPnl = (totalPositionPnl * 100).roundToDouble() / 100;
        _masterM2mPnl = ((totalRealised + totalPositionPnl) * 100).roundToDouble() / 100;
      });
    };

    // Server-pushed admin metrics (from metricsEngine)
    _livePriceService.onAdminMetricsUpdate = (data) {
      if (!mounted) return;
      setState(() {
        for (final item in data) {
          final mid = item['master_id']?.toString() ?? '';
          final pnl = (item['total_pnl'] as num?)?.toDouble() ?? 0;
          if (mid.isNotEmpty) _adminMasterPnl[mid] = pnl;
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
      final storage = SecureStorageService();
      final token = await storage.getToken();
      if (token != null) {
        final payload = Jwt.parseJwt(token);
        final userId = payload['id'] as String?;
        final role = payload['role'] as String?;
        if (userId != null) {
          _livePriceService.authenticate(userId, role: role);
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
    // Use server-computed values from metricsEngine (single source of truth)
    // Don't compute locally — just sum the per-user metrics
    double totalRealised = 0;
    double totalPositionPnl = 0;

    for (final user in _userMetrics) {
      totalRealised += (user['realised_pnl'] as num?)?.toDouble() ?? 0;
      totalPositionPnl += (user['position_pnl'] as num?)?.toDouble() ?? 0;
    }

    _masterRealisedPnl = (totalRealised * 100).roundToDouble() / 100;
    _masterPositionPnl = (totalPositionPnl * 100).roundToDouble() / 100;
    _masterM2mPnl = ((totalRealised + totalPositionPnl) * 100).roundToDouble() / 100;
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

  /// Use server-computed per-master P&L from metricsEngine (no local recalculation).
  void _recalcAdminMasterPnl() {
    for (final master in _adminMasterMetrics) {
      final String masterId = master['master_id'] ?? '';
      final double realised = (master['realised_pnl'] as num?)?.toDouble() ?? 0;
      final double positionPnl = (master['position_pnl'] as num?)?.toDouble() ?? 0;
      _adminMasterPnl[masterId] = ((realised + positionPnl) * 100).roundToDouble() / 100;
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
        final positions = data.cast<Map<String, dynamic>>();

        // Enrich with lot_size/segment from kite instrument lookup
        final tokens = positions
            .map((p) => p['instrument_token']?.toString() ?? '')
            .where((t) => t.isNotEmpty)
            .toSet();
        if (tokens.isNotEmpty) {
          try {
            final infoRes = await apiService.get(
                '/kite/instruments/info?tokens=${tokens.join(',')}',
                token: token);
            if (infoRes.statusCode == 200) {
              final infoBody = jsonDecode(infoRes.body);
              final List infoList = infoBody['data'] ?? [];
              final Map<String, Map<String, dynamic>> infoMap = {};
              for (final inst in infoList) {
                final t = inst['instrument_token']?.toString() ?? '';
                if (t.isNotEmpty) infoMap[t] = Map<String, dynamic>.from(inst);
              }
              for (final pos in positions) {
                final t = pos['instrument_token']?.toString() ?? '';
                final info = infoMap[t];
                if (info != null) {
                  pos['lot_size'] = info['lot_size'] ?? 1;
                  pos['segment'] = info['segment'] ?? '';
                }
              }
            }
          } catch (_) {}
        }

        setState(() {
          _masterPositions = positions;
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
                // Total P&L value
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                            totalPnl.toStringAsFixed(2),
                            style: TextStyle(
                        color: isTotalPositive
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                        fontSize: 20,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightBold,
                          ),
                    ),
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
                              fontSize: kFontSizeBody,
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
                    fontSize: kFontSizeViewTitle,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightBold,
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
                      fontSize: kFontSizeTradeSymbol,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
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
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: kFontSizeCaption, color: Color(0xFFCBD5E1))),
                      ),
                      const Icon(Icons.people_outline,
                          size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 3),
                      Text(
                        '$userCount user${userCount != 1 ? "s" : ""}',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Live P&L
            Text(
                            pnl.toStringAsFixed(2),
                            style: TextStyle(
                color: isPnlPositive
                    ? const Color(0xFF22C55E)
                    : const Color(0xFFEF4444),
                fontSize: kFontSizeBody,
                fontFamily: 'Inter',
                fontWeight: kFontWeightBold,
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
  String _masterSearchQuery = '';

  Widget _buildMasterView() {
    final bool isPnlPositive = _masterPositionPnl >= 0;
    final bool isRealisedPositive = _masterRealisedPnl >= 0;
    final bool isM2mPositive = _masterM2mPnl >= 0;

    // Filter positions by search query
    final filteredPositions = _masterSearchQuery.isEmpty
        ? _masterPositions
        : _masterPositions.where((pos) {
            final symbol =
                (pos['tradingsymbol'] ?? '').toString().toUpperCase();
            final exchange = (pos['exchange'] ?? '').toString().toUpperCase();
            final query = _masterSearchQuery.toUpperCase();
            return symbol.contains(query) || exchange.contains(query);
          }).toList();

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
                // Master Position P&L value
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                            _masterPositionPnl.toStringAsFixed(2),
                            style: TextStyle(
                        color: isPnlPositive
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                        fontSize: 20,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightBold,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Realised P&L and M2M P&L rows
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Realised P&L',
                                style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                            Text(_masterRealisedPnl.toStringAsFixed(2),
                                style: TextStyle(
                                    color: isRealisedPositive ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                    fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('TOTAL P&L',
                                style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                            Text(_masterM2mPnl.toStringAsFixed(2),
                                style: TextStyle(
                                    color: isM2mPositive ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                                    fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Search bar
                Container(
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
                          style: const TextStyle(
                            fontSize: kFontSizeBodySmall,
                            color: Color(0xFF0F172A),
                            fontFamily: 'Inter',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Search instrument...',
                            hintStyle: TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeBodySmall,
                              fontFamily: 'Inter',
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 10),
                          ),
                          onChanged: (v) =>
                              setState(() => _masterSearchQuery = v),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Instruments list
                if (_masterLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (filteredPositions.isEmpty)
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
                          Text(
                            _masterSearchQuery.isEmpty
                                ? 'No open positions across users'
                                : 'No matching instruments',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: kFontSizeBody,
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
                            i < filteredPositions.length;
                            i++) ...[
                          _buildMasterPositionItem(filteredPositions[i]),
                          if (i < filteredPositions.length - 1)
                            const Divider(
                                height: 1, color: Color(0xFFF1F5F9)),
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

    // Parse tradingsymbol into user-friendly name
    final String displayName = _friendlySymbolName(symbol);

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
                  Text(
                    displayName,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: kFontSizeTradeSymbol,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                      letterSpacing: -0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        exchange,
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: kFontSizeCaption, color: Color(0xFFCBD5E1))),
                      ),
                      const Icon(Icons.people_outline,
                          size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 3),
                      Text(
                        '$userCount',
                        style: const TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: kFontSizeSubtitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
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
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightBold,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: kIconSizeMedium, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  /// Parse tradingsymbol like "GOLD26APRFUT" or "NIFTY2530622500CE"
  /// into a user-friendly name like "GOLD | 26 APR FUT" or "NIFTY | 22500 CE"
  String _friendlySymbolName(String symbol) {
    if (symbol.isEmpty) return symbol;

    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ];

    for (final month in months) {
      final monthIdx = symbol.toUpperCase().indexOf(month);
      if (monthIdx > 0) {
        final basePart = symbol.substring(0, monthIdx);
        final afterMonth = symbol.substring(monthIdx + month.length);

        String name = '';
        String dateDigits = '';
        for (int i = 0; i < basePart.length; i++) {
          if (basePart[i].contains(RegExp(r'[0-9]'))) {
            dateDigits = basePart.substring(i);
            break;
          }
          name += basePart[i];
        }

        if (afterMonth == 'FUT') {
          return '$name | $dateDigits $month FUT';
        }

        String suffix = '';
        String strike = afterMonth;
        if (afterMonth.endsWith('CE')) {
          suffix = 'CE';
          strike = afterMonth.substring(0, afterMonth.length - 2);
        } else if (afterMonth.endsWith('PE')) {
          suffix = 'PE';
          strike = afterMonth.substring(0, afterMonth.length - 2);
        }

        if (suffix.isNotEmpty && strike.isNotEmpty) {
          return '$name | $strike $suffix $month';
        }
        if (suffix.isNotEmpty) {
          return '$name | $suffix $month';
        }

        return '$name | $dateDigits $month $afterMonth'.trim();
      }
    }

    return symbol.toUpperCase();
  }

  // ============================================
  // USER VIEW (existing, unchanged)
  // ============================================
  bool _expiredCheckDone = false;

  /// Check for expired instrument positions and auto-squareoff
  Future<void> _checkAndSquareOffExpired(List<PositionAgg> openPositions, WatchlistProvider watchlistProvider) async {
    if (_expiredCheckDone) return;
    _expiredCheckDone = true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiredTokens = <String>[];

    for (final pos in openPositions) {
      final wItem = watchlistProvider.getByToken(pos.instrumentToken);
      final expiry = wItem?.instrument.expiry;
      if (expiry != null) {
        final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
        if (expiryDate.isBefore(today)) {
          expiredTokens.add(pos.instrumentToken);
        }
      }
    }

    if (expiredTokens.isEmpty) return;

    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      if (token == null) return;

      final apiService = ApiService(backendUrl);
      final res = await apiService.post('/trade/auto-squareoff-expired', {
        'instrument_tokens': expiredTokens,
      }, token: token);

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final squaredOff = (body['data']?['squared_off'] as List?)?.length ?? 0;
        if (squaredOff > 0 && mounted) {
          Provider.of<TradeMetricsProvider>(context, listen: false).fetchBaseData();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Auto squared off $squaredOff expired position(s)'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error auto-squaring off expired positions: $e');
    }
  }

  Widget _buildUserView() {
    return Consumer2<TradeMetricsProvider, WatchlistProvider>(
      builder: (context, provider, watchlistProvider, child) {
        // Filter out closed positions (netQty == 0)
        final openPositions =
            provider.positions.where((p) => p.netQty != 0).toList();

        // Check for expired positions on first load
        if (openPositions.isNotEmpty && !_expiredCheckDone) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _checkAndSquareOffExpired(openPositions, watchlistProvider);
          });
        }

        final double posPnl = provider.positionPnl;
        final double m2m = provider.m2mPnl;
        final double realised = provider.realisedPnl;
        final double credit = provider.credit;
        final double marginUsed = provider.marginUsed;

        // Use server-calculated equity & free margin when available
        final double equity = provider.equity;
        final double freeMargin = provider.freeMargin;

        final isPosPnlPositive = posPnl >= 0;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: SafeArea(
            child: Column(
              children: [
                // Fixed metrics section (not scrollable)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Position P&L value
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                            posPnl.toStringAsFixed(2),
                            style: TextStyle(
                          color: isPosPnlPositive
                              ? const Color(0xFF22C55E)
                              : const Color(0xFFEF4444),
                          fontSize: kFontSizePageTitle,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightBold,
                          ),
                      ),
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
                                size: kIconSizeMedium,
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
                                fontSize: kFontSizeSubtitle,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold,
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
                                fontSize: kFontSizeSubtitle,
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
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
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
                                    fontSize: kFontSizeSubtitle,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightSemiBold,
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
                                    size: kIconSizeSmall, color: Color(0xFF3F45C7)),
                                SizedBox(width: 4),
                                Text(
                                  'Square Off',
                                  style: TextStyle(
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
                  const SizedBox(height: 12),
                    ],
                  ),
                ),

                // Scrollable positions list
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => Provider.of<TradeMetricsProvider>(context, listen: false).fetchBaseData(),
                    child: openPositions.isEmpty
                      ? ListView(
                          children: const [
                            Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Center(
                                child: Text(
                                  'No open positions',
                                  style: TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: kFontSizeSectionHeader,
                                    fontFamily: 'Inter',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                  width: 1, color: Color(0xFFE2E8F0)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: openPositions.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                            itemBuilder: (context, idx) {
                            final pos = openPositions[idx];
                            final isBuy = pos.netQty > 0;
                            final watchlist = Provider.of<WatchlistProvider>(context, listen: false);
                            final wItem = watchlist.getByToken(pos.instrumentToken);
                            final displayName = wItem?.instrument.userFriendlyName ?? pos.tradingsymbol;
                            final ltp = pos.ltp;
                            final fallbackSpread = ltp * 0.0005;
                            final cmp = pos.cmp > 0
                                ? pos.cmp
                                : isBuy
                                    ? (wItem?.bidPrice ?? (ltp > 0 ? ltp - fallbackSpread : ltp))
                                    : (wItem?.askPrice ?? (ltp > 0 ? ltp + fallbackSpread : ltp));
                            final floating = pos.floating;
                            final isNegative = floating < 0;
                              return _buildOrderItem(
                                  context,
                                  pos,
                                  displayName,
                                  pos.exchange,
                                  '${isBuy ? "BUY" : "SELL"}: ${_positionVolumeLabel(pos.exchange, pos.tradingsymbol, pos.netQty, segment: pos.segment, lotSize: pos.lotSize)}',
                                  isBuy ? pos.avgBuyPrice : pos.avgSellPrice,
                                  cmp,
                                  floating,
                                  isNegative,
                              );
                            },
                          ),
                        ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
              fontSize: kFontSizeBodySmall,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          Text(
                            value.toStringAsFixed(2),
                            style: TextStyle(
              color: valueColor,
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
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
                    fontSize: kFontSizeViewTitle,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightBold,
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
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightMedium,
            ),
          ),
          Text(
            value.toStringAsFixed(2),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: kFontSizeBody,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
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
            if (_isSelectionMode && !isSelected)
              const Icon(
                Icons.check_box_outline_blank,
                size: kIconSizeMedium,
                color: Color(0xFF8E8E93),
              ),
            if (_isSelectionMode && isSelected)
              const Icon(
                Icons.check_box,
                size: kIconSizeMedium,
                color: Color(0xFF0A1E46),
              ),
            if (_isSelectionMode) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: kFontSizePositionSymbol,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        qtyInfo,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: kFontSizePositionDetail,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
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
                          fontSize: kFontSizePositionDetail,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Text(
                        'ATP: ',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: kFontSizePositionDetail,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
                        ),
                      ),
                      Text(
                            atp.toStringAsFixed(2),
                            style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: kFontSizePositionDetail,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
                          ),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'CMP: ',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: kFontSizePositionDetail,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
                        ),
                      ),
                      Text(
                            cmp.toStringAsFixed(2),
                            style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: kFontSizePositionDetail,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightRegular,
                          ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
                            pnl.toStringAsFixed(2),
                            style: TextStyle(
                color: valueColor,
                fontSize: kFontSizePositionPnl,
                fontFamily: 'Inter',
                fontWeight: kFontWeightSemiBold,
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
                  fontSize: kFontSizeViewTitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightBold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Are you sure you want to square off ${selectedPositions.length} position(s)?\n\n'
                'This will place opposite market orders to close these positions.',
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
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
                        fontSize: kFontSizeBody,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
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
                        fontSize: kFontSizeBody,
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
          // Check market hours for this instrument
          final ex = position.exchange;
          final sym = position.tradingsymbol;
          if (!MarketHours.isMarketOpen(exchange: ex, tradingsymbol: sym)) {
            failCount++;
            errors.add('${position.tradingsymbol}: ${MarketHours.getMarketStatusMessage(exchange: ex, tradingsymbol: sym)}');
            continue;
          }

          // Determine opposite side based on net quantity
          final oppositeType = position.netQty > 0 ? 'SELL' : 'BUY';

          // Place market order to close position
          final response = await apiService.post(
            '/trade',
            {
              'instrument_token': position.instrumentToken,
              'tradingsymbol': position.tradingsymbol,
              'exchange': position.exchange,
              'segment': position.segment,
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
      if (mounted) {
        try {
          final metricsProvider =
              Provider.of<TradeMetricsProvider>(context, listen: false);
          await metricsProvider.fetchBaseData();
        } catch (_) {}
      }

      // Exit selection mode
      if (mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedPositionTokens.clear();
        });
      }

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
                        fontSize: kFontSizeViewTitle,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightBold,
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
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightRegular,
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
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold,
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
