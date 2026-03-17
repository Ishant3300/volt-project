import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:jwt_decode/jwt_decode.dart';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../models/trade.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/live_price_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import '../utils/date_formatter.dart';
import 'package:intl/intl.dart';
import 'create_user_view.dart';
import 'create_master_view.dart';
import 'group_quantity_view.dart';
import 'margin_squareoff_bottom_sheet.dart';
import 'brokerage_settings_view.dart';
import 'intraday_squareoff_bottom_sheet.dart';
import 'trade_margin_settings_view.dart';
import 'script_quantity_settings_view.dart';
import 'sharing_details_view.dart';
import 'rejection_log_history_view.dart';
import 'settlement_report_view.dart';
import '../pages/transaction_page.dart';
import 'reports_view.dart';

class UsernameView extends StatefulWidget {
  final Master? master;
  final User? user;

  const UsernameView({super.key, this.master, this.user})
      : assert(master != null || user != null,
            'Either master or user must be provided');

  @override
  State<UsernameView> createState() => _UsernameViewState();
}

class _UsernameViewState extends State<UsernameView> {
  int _selectedTabIndex = 0;

  late bool _activeStatus;
  late bool _closeOnly;
  late bool _bet;
  late bool _marginSquare;
  late bool _freshStoploss;

  late Master? _currentMaster;
  late User? _currentUser;

  List<Trade> _trades = [];
  bool _isLoadingTrades = false;
  String? _tradesError;

  // User list state (for Master view)
  List<User> _userList = [];
  bool _isLoadingUsers = false;
  String? _usersError;

  // Live position state (for User and Master view)
  final LivePriceService _livePriceService = LivePriceService();
  final SecureStorageService _storage = SecureStorageService();
  final Map<String, double> _ltpMap = {};
  Set<String> _allTokens = {};
  Map<String, dynamic>? _liveUserMetrics;
  List<Map<String, dynamic>> _livePositions = [];
  bool _isLoadingLivePositions = false;

  @override
  void initState() {
    super.initState();
    _currentMaster = widget.master;
    _currentUser = widget.user;

    _activeStatus = _currentMaster?.activeStatus ?? _currentUser!.activeStatus;
    _closeOnly = _currentMaster?.permissions?.closeOnly ??
        _currentUser?.closeOnly ??
        false;
    _bet = _currentMaster?.permissions?.bet ?? _currentUser?.bet ?? false;
    _marginSquare = _currentMaster?.permissions?.marginSquare ??
        _currentUser?.marginSquareOff ??
        false;
    _freshStoploss = _currentMaster?.permissions?.freshStoploss ??
        _currentUser?.freshStoploss ??
        false;

    _fetchTrades();
    if (_currentUser != null) {
      _fetchLivePositions();
      _setupLivePrices();
    } else {
      // Master view: use live positions too (aggregate all users)
      _fetchLivePositions();
      _setupLivePrices();
      _fetchUserList();
    }
  }

  @override
  void dispose() {
    _livePriceService.onTickReceived = null;
    _livePriceService.onConnectionChanged = null;
    if (_allTokens.isNotEmpty) {
      _livePriceService.unsubscribe(_allTokens.toList());
    }
    _livePriceService.disconnect();
    super.dispose();
  }

  String get username => _currentMaster?.username ?? _currentUser!.username;
  double get credits => _currentMaster?.credits ?? _currentUser!.credits;
  double get balance => _currentMaster?.balance ?? _currentUser!.balance;
  String get createdAt => _currentMaster?.createdAt ?? _currentUser!.createdAt;
  String? get lastLogin => _currentMaster?.lastLogin ?? _currentUser?.lastLogin;
  String? get ipAddress => _currentMaster?.ipAddress ?? _currentUser?.ipAddress;
  List<String> get exchangesAllowed {
    if (_currentMaster != null) return _currentMaster!.exchangesAllowed;
    return _currentUser!.exchangesAllowed.map((e) => e.exchangeName).toList();
  }

  void _setupLivePrices() {
    _livePriceService.onTickReceived = (tick) {
      if (!mounted) return;
      final token = tick['instrument_token']?.toString();
      if (token == null) return;
      final price = (tick['last_price'] as num?)?.toDouble();
      if (price == null) return;
      setState(() {
        _ltpMap[token] = price;
        _recalcLiveMetrics();
      });
    };
    _livePriceService.onConnectionChanged = (connected) {
      if (connected) _authenticateAndSubscribe();
    };
    _livePriceService.connect();
  }

  Future<void> _authenticateAndSubscribe() async {
    try {
      final token = await _storage.getToken();
      if (token != null) {
        final payload = Jwt.parseJwt(token);
        final userId = payload['id'] as String?;
        if (userId != null) _livePriceService.authenticate(userId);
      }
    } catch (e) {
      log('⚠️ Failed to authenticate WebSocket: $e');
    }
    if (_allTokens.isNotEmpty) {
      _livePriceService.subscribe(_allTokens.toList());
    }
  }

  Future<void> _fetchLivePositions() async {
    setState(() => _isLoadingLivePositions = true);
    try {
      final token = await _storage.getToken();
      final apiService = ApiService(backendUrl);
      // Admin needs to pass master_id or user_id so backend knows what to fetch
      final role = await _storage.getRole();
      String url = '/master/positions/user-metrics';
      if (role == 'ADMIN') {
        if (_currentMaster != null) {
          url += '?master_id=${_currentMaster!.id}';
        } else if (_currentUser != null) {
          url += '?user_id=${_currentUser!.id}';
        }
      }
      final response = await apiService.get(url, token: token);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List data = body['data'] ?? [];
        final Set<String> tokens = {};

        if (_currentUser != null) {
          // User view: find this specific user's data
          final targetId = _currentUser?.id ?? '';
          for (final user in data) {
            final uid = user['user_id']?.toString() ?? '';
            if (uid == targetId) {
              _liveUserMetrics = Map<String, dynamic>.from(user);
              final List positions = user['positions'] ?? [];
              _livePositions = positions.cast<Map<String, dynamic>>();
              for (final pos in positions) {
                final t = pos['instrument_token']?.toString();
                if (t != null) tokens.add(t);
              }
              break;
            }
          }
        } else {
          // Master view: aggregate all users' positions into master-level metrics
          _liveUserMetrics = _aggregateMasterMetrics(data);
          _livePositions = (_liveUserMetrics!['positions'] as List)
              .cast<Map<String, dynamic>>();
          for (final pos in _livePositions) {
            final t = pos['instrument_token']?.toString();
            if (t != null) tokens.add(t);
          }
        }

        _allTokens = tokens;
        if (_livePriceService.isConnected && tokens.isNotEmpty) {
          _livePriceService.subscribe(tokens.toList());
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      log('Error fetching live positions: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLivePositions = false);
    }
  }

  /// Aggregate all users' positions into a single master-level summary.
  Map<String, dynamic> _aggregateMasterMetrics(List data) {
    final Map<String, Map<String, dynamic>> instrMap = {};
    double totalRealised = 0;
    double totalBalance = 0;
    double totalMarginUsed = 0;

    for (final user in data) {
      totalRealised += (user['realised_pnl'] as num?)?.toDouble() ?? 0;
      totalBalance += (user['balance'] as num?)?.toDouble() ?? 0;
      totalMarginUsed += (user['margin_used'] as num?)?.toDouble() ?? 0;

      final List positions = user['positions'] ?? [];
      for (final pos in positions) {
        final iToken = pos['instrument_token']?.toString() ?? '';
        if (iToken.isEmpty) continue;
        if (!instrMap.containsKey(iToken)) {
          instrMap[iToken] = {
            'instrument_token': iToken,
            'tradingsymbol': pos['tradingsymbol'],
            'exchange': pos['exchange'],
            'total_buy_qty': 0,
            'total_sell_qty': 0,
            'total_buy_value': 0.0,
            'total_sell_value': 0.0,
          };
        }
        final agg = instrMap[iToken]!;
        agg['total_buy_qty'] += (pos['total_buy_qty'] as num?)?.toInt() ?? 0;
        agg['total_sell_qty'] += (pos['total_sell_qty'] as num?)?.toInt() ?? 0;
        agg['total_buy_value'] +=
            (pos['total_buy_value'] as num?)?.toDouble() ?? 0;
        agg['total_sell_value'] +=
            (pos['total_sell_value'] as num?)?.toDouble() ?? 0;
      }
    }

    // Compute net_qty and avg prices for each aggregated instrument
    final List<Map<String, dynamic>> positions = [];
    double totalFloating = 0;

    for (final agg in instrMap.values) {
      final int buyQty = agg['total_buy_qty'] as int;
      final int sellQty = agg['total_sell_qty'] as int;
      final double buyVal = agg['total_buy_value'] as double;
      final double sellVal = agg['total_sell_value'] as double;
      final int netQty = buyQty - sellQty;
      final double avgBuy = buyQty > 0 ? buyVal / buyQty : 0;
      final double avgSell = sellQty > 0 ? sellVal / sellQty : 0;

      agg['net_qty'] = netQty;
      agg['avg_buy_price'] = avgBuy;
      agg['avg_sell_price'] = avgSell;

      if (netQty != 0) {
        final double ltp =
            _ltpMap[agg['instrument_token']] ?? (netQty > 0 ? avgBuy : avgSell);
        double floating = 0;
        if (netQty > 0)
          floating = (ltp - avgBuy) * netQty;
        else
          floating = (avgSell - ltp) * netQty.abs();
        totalFloating += floating;
        positions.add(Map<String, dynamic>.from(agg));
      }
    }

    final double m2m = totalRealised + totalFloating;
    final double equity = totalBalance + m2m;

    return {
      'balance': totalBalance,
      'realised_pnl': _round2(totalRealised),
      'position_pnl': _round2(totalFloating),
      'm2m_pnl': _round2(m2m),
      'margin_used': _round2(totalMarginUsed),
      'equity': _round2(equity),
      'free_margin': _round2(equity - totalMarginUsed),
      'positions': positions,
    };
  }

  void _recalcLiveMetrics() {
    if (_liveUserMetrics == null) return;

    if (_currentMaster != null) {
      // Master view: re-aggregate from _livePositions using fresh LTP
      double totalFloating = 0;

      for (final pos in _livePositions) {
        final String iToken = pos['instrument_token']?.toString() ?? '';
        final int netQty = (pos['net_qty'] as num?)?.toInt() ?? 0;
        final double avgBuy = (pos['avg_buy_price'] as num?)?.toDouble() ?? 0;
        final double avgSell = (pos['avg_sell_price'] as num?)?.toDouble() ?? 0;
        final double ltp = _ltpMap[iToken] ?? (netQty > 0 ? avgBuy : avgSell);

        double floating = 0;
        if (netQty > 0)
          floating = (ltp - avgBuy) * netQty;
        else if (netQty < 0) floating = (avgSell - ltp) * netQty.abs();
        totalFloating += floating;
      }

      final double totalRealised =
          (_liveUserMetrics!['realised_pnl'] as num?)?.toDouble() ?? 0;
      final double totalBalance =
          (_liveUserMetrics!['balance'] as num?)?.toDouble() ?? 0;
      final double marginUsed =
          (_liveUserMetrics!['margin_used'] as num?)?.toDouble() ?? 0;
      final double m2m = totalRealised + totalFloating;
      final double equity = totalBalance + m2m;

      _liveUserMetrics!['position_pnl'] = _round2(totalFloating);
      _liveUserMetrics!['m2m_pnl'] = _round2(m2m);
      _liveUserMetrics!['equity'] = _round2(equity);
      _liveUserMetrics!['free_margin'] = _round2(equity - marginUsed);
      return;
    }

    // User view: trust realised_pnl from backend, only update floating.
    final user = _liveUserMetrics!;
    final List positions = user['positions'] ?? [];
    if (positions.isEmpty) {
      // If no positions, just ensure M2M = realised
      final double realised = (user['realised_pnl'] as num?)?.toDouble() ?? 0;
      final double balance = (user['balance'] as num?)?.toDouble() ?? 0;
      final double marginUsed = (user['margin_used'] as num?)?.toDouble() ?? 0;
      user['position_pnl'] = 0.0;
      user['m2m_pnl'] = _round2(realised);
      user['equity'] = _round2(balance + realised);
      user['free_margin'] = _round2((balance + realised) - marginUsed);
      return;
    }

    final double balance = (user['balance'] as num?)?.toDouble() ?? 0;
    final double realised = (user['realised_pnl'] as num?)?.toDouble() ?? 0;
    double totalFloating = 0;

    for (final pos in positions) {
      final String iToken = pos['instrument_token']?.toString() ?? '';
      final int buyQty = (pos['total_buy_qty'] as num?)?.toInt() ?? 0;
      final int sellQty = (pos['total_sell_qty'] as num?)?.toInt() ?? 0;
      final double buyVal = (pos['total_buy_value'] as num?)?.toDouble() ?? 0;
      final double sellVal = (pos['total_sell_value'] as num?)?.toDouble() ?? 0;
      final int netQty = buyQty - sellQty;

      final double avgBuy = buyQty > 0 ? buyVal / buyQty : 0;
      final double avgSell = sellQty > 0 ? sellVal / sellQty : 0;
      final double ltp = _ltpMap[iToken] ??
          (pos['avg_buy_price'] as num?)?.toDouble() ??
          (netQty > 0 ? avgBuy : avgSell);

      if (netQty > 0)
        totalFloating += (ltp - avgBuy) * netQty;
      else if (netQty < 0) totalFloating += (avgSell - ltp) * netQty.abs();
    }

    final double m2m = realised + totalFloating;
    final double marginUsed = (user['margin_used'] as num?)?.toDouble() ?? 0;
    final double equity = balance + m2m;

    user['position_pnl'] = _round2(totalFloating);
    user['m2m_pnl'] = _round2(m2m);
    user['equity'] = _round2(equity);
    user['free_margin'] = _round2(equity - marginUsed);
  }

  double _round2(double v) => (v * 100).roundToDouble() / 100;

  Future<void> _fetchTrades() async {
    setState(() {
      _isLoadingTrades = true;
      _tradesError = null;
    });
    try {
      // Use /master/trades for both master and admin (backend supports both roles)
      final token = await _storage.getToken();
      final apiService = ApiService(backendUrl);
      final queryParams = <String>['page=1', 'limit=50'];
      if (_currentUser != null) queryParams.add('user_id=${_currentUser!.id}');
      if (_currentMaster != null)
        queryParams.add('master_id=${_currentMaster!.id}');
      final response = await apiService
          .get('/master/trades?${queryParams.join('&')}', token: token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> tradesJson = data['data']['trades'] ?? [];
          setState(() {
            _trades = tradesJson.map((j) => Trade.fromJson(j)).toList();
            _isLoadingTrades = false;
          });
        } else {
          setState(() {
            _tradesError = data['message'] ?? 'Failed';
            _isLoadingTrades = false;
          });
        }
      } else {
        setState(() {
          _tradesError = 'Failed to load trades';
          _isLoadingTrades = false;
        });
      }
    } catch (e) {
      setState(() {
        _tradesError = 'Error: $e';
        _isLoadingTrades = false;
      });
    }
  }

  Future<void> _fetchUserList() async {
    if (_currentMaster == null) return;
    setState(() {
      _isLoadingUsers = true;
      _usersError = null;
    });
    try {
      final token = await _storage.getToken();
      final apiService = ApiService(backendUrl);
      // Admin uses /admin/users?master_id=X, Master uses /master/users (auto-filtered)
      final role = await _storage.getRole();
      final String url;
      if (role == 'ADMIN') {
        url = '/admin/users?master_id=${_currentMaster!.id}&limit=100';
      } else {
        url = '/master/users?limit=100';
      }
      final response = await apiService.get(url, token: token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> usersJson = data['data']['users'] ?? [];
          setState(() {
            _userList = usersJson.map((j) => User.fromJson(j)).toList();
            _isLoadingUsers = false;
          });
        } else {
          setState(() {
            _usersError = data['message'] ?? 'Failed';
            _isLoadingUsers = false;
          });
        }
      } else {
        setState(() {
          _usersError = 'Failed to load users';
          _isLoadingUsers = false;
        });
      }
    } catch (e) {
      setState(() {
        _usersError = 'Error: $e';
        _isLoadingUsers = false;
      });
    }
  }

  Future<void> _refreshData() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      if (_currentMaster != null) {
        final response = await adminService.getMasterById(_currentMaster!.id);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _currentMaster = Master.fromJson(data['data']);
              _activeStatus = _currentMaster!.activeStatus;
              _closeOnly = _currentMaster!.permissions?.closeOnly ?? false;
              _bet = _currentMaster!.permissions?.bet ?? false;
              _marginSquare =
                  _currentMaster!.permissions?.marginSquare ?? false;
              _freshStoploss =
                  _currentMaster!.permissions?.freshStoploss ?? false;
            });
          }
        }
      } else if (_currentUser != null) {
        final response = await adminService.getUserById(_currentUser!.id);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            setState(() {
              _currentUser = User.fromJson(data['data']);
              _activeStatus = _currentUser!.activeStatus;
              _closeOnly = _currentUser!.closeOnly;
              _bet = _currentUser!.bet;
              _marginSquare = _currentUser!.marginSquareOff;
              _freshStoploss = _currentUser!.freshStoploss;
            });
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context, true),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2)),
                            ],
                          ),
                          child: const Icon(Icons.arrow_back,
                              color: Colors.black, size: 20),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        username,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _currentMaster != null
                              ? CreateMasterView(master: _currentMaster)
                              : CreateUserView(user: _currentUser),
                        ),
                      );
                      if (result == true && mounted) await _refreshData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit_outlined,
                              size: 14, color: Color(0xFF3F45C7)),
                          SizedBox(width: 4),
                          Text('Edit',
                              style: TextStyle(
                                  color: Color(0xFF3F45C7),
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Credit / Balance
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('CREDIT',
                            style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 4),
                        Text('₹${credits.toStringAsFixed(2)}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  Container(
                      width: 1, height: 36, color: const Color(0xFFF1F5F9)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('BALANCE',
                              style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 10,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                          const SizedBox(height: 4),
                          Text('₹${balance.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                children: [
                  _buildTab('Overview', 0),
                  _buildTab('Trades', 1),
                  _buildTab('Position', 2),
                  if (_currentMaster != null) _buildTab('Users', 3),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Tab content
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildOverviewTab()
                  : _selectedTabIndex == 1
                      ? _buildTradelistTab()
                      : _selectedTabIndex == 2
                          ? _buildPositionTab()
                          : _buildUserListTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final selected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF3F45C7) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF94A3B8),
              fontSize: 13,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  // ── Overview Tab ──
  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info card
          _card(
            child: Column(
              children: [
                _infoRow('Created', DateFormatter.formatDateTime(createdAt)),
                _infoRow('Last Login', DateFormatter.formatDateTime(lastLogin)),
                _infoRow('IP Address', ipAddress ?? 'N/A'),
                _infoRow('Exchanges', exchangesAllowed.join(', '),
                    isLast: true),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('CONTROL'),
          const SizedBox(height: 12),

          _card(
            child: Column(
              children: [
                _buildControlToggle('User Status', _activeStatus),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildControlToggle('Close Only', _closeOnly),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildControlToggle('BET', _bet),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildControlToggle('Margin Square Off', _marginSquare),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _buildControlToggle('Fresh Stop-Loss', _freshStoploss),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('SETTINGS'),
          const SizedBox(height: 12),

          _card(
            child: Column(
              children: [
                _settingRow(
                    Icons.account_balance_wallet_outlined, 'Credit/Debit'),
                _settingRow(Icons.grid_view_rounded, 'Group Quantity Settings'),
                _settingRow(Icons.shield_outlined, 'Margin SquareOff Settings'),
                _settingRow(Icons.tune_outlined, 'Brk Settings'),
                _settingRow(Icons.schedule_outlined, 'Intraday SquareOff'),
                _settingRow(Icons.trending_up_outlined, 'Trade Margin'),
                _settingRow(Icons.share_outlined, 'Sharing Details'),
                _settingRow(Icons.list_alt_outlined, 'Script Quantity Setting',
                    isLast: _currentMaster == null),
                if (_currentMaster != null)
                  _settingRow(
                      Icons.admin_panel_settings_outlined, 'Account Limit',
                      isLast: true),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionLabel('ACTION'),
          const SizedBox(height: 12),

          _card(
            child: Column(
              children: [
                _settingRow(Icons.error_outline, 'Rejection Log'),
                _settingRow(Icons.picture_as_pdf_outlined, 'Generate PDF'),
                _settingRow(Icons.description_outlined, 'Settlement Report',
                    isLast: true),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool isLast = false}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }

  Widget _settingRow(IconData icon, String label, {bool isLast = false}) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleSettingTap(label),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(icon, size: 20, color: const Color(0xFF3F45C7)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500))),
                const Icon(Icons.chevron_right,
                    size: 18, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }

  // ── Tradelist Tab ──
  Widget _buildTradelistTab() {
    if (_isLoadingTrades) {
      return const Center(
          child: CircularProgressIndicator(
              color: Color(0xFF3F45C7), strokeWidth: 2.5));
    }
    if (_tradesError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(_tradesError!,
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontFamily: 'Inter')),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _fetchTrades,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF3F45C7),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }

    final completedTrades = _trades
        .where((t) =>
            t.status.toLowerCase() == 'completed' ||
            t.status.toLowerCase() == 'success')
        .toList();
    final pendingTrades =
        _trades.where((t) => t.status.toLowerCase() == 'pending').toList();

    // Compute per-trade P&L
    final perTradePnl = _computePerTradePnl(completedTrades);

    if (_trades.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchTrades,
        child: ListView(
          children: [
            const SizedBox(height: 200),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ]),
                    child: const Icon(Icons.receipt_long,
                        size: 32, color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 20),
                  const Text('No trades found',
                      style: TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchTrades,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: completedTrades.length + pendingTrades.length,
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
          itemBuilder: (context, index) {
            if (index < completedTrades.length) {
              final trade = completedTrades[index];
              return _buildCompletedTradeCard(trade,
                  tradePnl: perTradePnl[trade.id]);
            }
            return _buildPendingTradeCard(
                pendingTrades[index - completedTrades.length]);
          },
        ),
      ),
    );
  }

  /// Map trade.pnl from backend instead of recalculating (FIFO is handled by server)
  Map<String, _PerTradePnl> _computePerTradePnl(List<Trade> completedTrades) {
    final Map<String, _PerTradePnl> result = {};
    // We still need to track openedAt for duration display using simple FIFO logic locally
    final Map<String, List<Trade>> byInstrument = {};
    for (final t in completedTrades) {
      byInstrument.putIfAbsent(t.instrumentToken, () => []).add(t);
    }
    for (final trades in byInstrument.values) {
      trades.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      int netQty = 0;
      String? openedAt;
      for (final t in trades) {
        final isBuy = t.transactionType.toUpperCase() == 'BUY';
        if (netQty == 0) {
          openedAt = t.createdAt;
          netQty = isBuy ? t.quantity : -t.quantity;
        } else if ((netQty > 0 && isBuy) || (netQty < 0 && !isBuy)) {
          netQty += isBuy ? t.quantity : -t.quantity;
        } else {
          // Closing trade
          result[t.id] =
              _PerTradePnl(pnl: t.pnl, isClosing: true, openedAt: openedAt);
          netQty += isBuy ? t.quantity : -t.quantity;
          if (netQty == 0)
            openedAt = null;
          else if ((netQty > 0 && !isBuy) || (netQty < 0 && isBuy))
            openedAt = t.createdAt;
        }
      }
    }
    return result;
  }

  String _tradeDuration(String? openedAt, String closedAt) {
    if (openedAt == null) return _timeAgo(closedAt);
    try {
      final open = DateTime.parse(openedAt);
      final close = DateTime.parse(closedAt);
      final diff = close.difference(open).abs();
      if (diff.inSeconds < 60) return 'in ${diff.inSeconds}s';
      if (diff.inMinutes < 60) return 'in ${diff.inMinutes}min';
      if (diff.inHours < 24) {
        final hrs = diff.inHours;
        final mins = diff.inMinutes % 60;
        return mins > 0 ? 'in ${hrs}hr ${mins}min' : 'in ${hrs}hr';
      }
      final days = diff.inDays;
      final hrs = diff.inHours % 24;
      return hrs > 0 ? 'in ${days}d ${hrs}hr' : 'in ${days}d';
    } catch (_) {
      return _timeAgo(closedAt);
    }
  }

  String _timeAgo(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
      if (diff.inMinutes < 60) return '${diff.inMinutes}min ago';
      if (diff.inHours < 24) return '${diff.inHours}hr ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return DateFormat('dd MMM').format(dt);
    } catch (_) {
      return '';
    }
  }

  Widget _buildCompletedTradeCard(Trade trade, {_PerTradePnl? tradePnl}) {
    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final String sideLabel = isBuy ? 'BUY' : 'SELL';
    final bool isClosing = tradePnl != null && tradePnl.isClosing;

    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm a").format(dt).toUpperCase();
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(trade.tradingSymbol,
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(sideLabel,
                          style: TextStyle(
                              color: sideColor,
                              fontSize: 10,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3)),
                    ),
                  ],
                ),
                if (isClosing) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Closed ${_tradeDuration(tradePnl.openedAt, trade.createdAt)}',
                      style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 10,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text('Qty ${trade.quantity.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500)),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: 10, color: Color(0xFFCBD5E1)))),
                    const Icon(Icons.access_time,
                        size: 11, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text(formattedDate,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500)),
                  ],
                ),
                if (trade.userName != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 11, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(trade.userName!,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 10,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(trade.price.toStringAsFixed(2),
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.bold)),
              if (isClosing) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (tradePnl.pnl >= 0
                            ? const Color(0xFF10B981)
                            : const Color(0xFFEF4444))
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'P&L ${tradePnl.pnl >= 0 ? '+' : ''}${tradePnl.pnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: tradePnl.pnl >= 0
                          ? const Color(0xFF10B981)
                          : const Color(0xFFEF4444),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingTradeCard(Trade trade) {
    final bool isBuy = trade.transactionType.toUpperCase() == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    String formattedDate = trade.createdAt;
    try {
      final DateTime dt = DateTime.parse(trade.createdAt).toLocal();
      formattedDate = DateFormat("dd MMM hh:mm:ss a").format(dt).toUpperCase();
    } catch (_) {}

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trade.tradingSymbol,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                          '${trade.transactionType} · ${trade.quantity.toStringAsFixed(0)} QTY',
                          style: TextStyle(
                              color: sideColor,
                              fontSize: 10,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3)),
                    ),
                    if (trade.userName != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 11, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(trade.userName!,
                                style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 10,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(trade.price.toStringAsFixed(2),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9)))),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text('PENDING',
                    style: TextStyle(
                        color: Color(0xFFB45309),
                        fontSize: 10,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.access_time, size: 11, color: Color(0xFF94A3B8)),
              const SizedBox(width: 3),
              Text(formattedDate,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Position Tab ──
  Widget _buildPositionTab() {
    // Both master and user now use the live position tab
    return _buildLivePositionTab();
  }

  Widget _buildLivePositionTab() {
    if (_isLoadingLivePositions) {
      return const Center(
          child: CircularProgressIndicator(color: Color(0xFF3F45C7)));
    }
    if (_liveUserMetrics == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.trending_flat, size: 40, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text('No position data',
                style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontFamily: 'Inter')),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _fetchLivePositions,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF3F45C7),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Refresh',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    final metrics = _liveUserMetrics!;
    final double positionPnl =
        (metrics['position_pnl'] as num?)?.toDouble() ?? 0;
    final double realisedPnl =
        (metrics['realised_pnl'] as num?)?.toDouble() ?? 0;
    final double m2mPnl = (metrics['m2m_pnl'] as num?)?.toDouble() ?? 0;
    final double credit =
        _currentMaster?.credits ?? (metrics['credit'] as num?)?.toDouble() ?? 0;
    final double marginUsed = (metrics['margin_used'] as num?)?.toDouble() ?? 0;
    final double equity = (metrics['equity'] as num?)?.toDouble() ?? 0;

    return RefreshIndicator(
      onRefresh: _fetchLivePositions,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          // 6-metric summary card
          _card(
            child: Column(
              children: [
                _liveMetricGridRow(
                    'Position P&L', positionPnl, 'Realised P&L', realisedPnl),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _liveMetricGridRow('M2M P&L', m2mPnl, 'Credit', credit),
                const Divider(height: 1, color: Color(0xFFF1F5F9)),
                _liveMetricGridRow('Margin Used', marginUsed, 'Equity', equity),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Position count label
          Text(
            '${_livePositions.length} open position${_livePositions.length != 1 ? "s" : ""}${_currentMaster != null ? " (aggregated)" : ""}',
            style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 12),
          // Position cards
          ..._livePositions.map((pos) => _buildLivePositionCard(pos)),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildLivePositionCard(Map<String, dynamic> pos) {
    final String symbol = pos['tradingsymbol'] ?? '';
    final String exchange = pos['exchange'] ?? '';
    final String iToken = pos['instrument_token']?.toString() ?? '';
    final int netQty = (pos['net_qty'] as num?)?.toInt() ?? 0;
    final bool isBuy = netQty > 0;
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    final int buyQty = (pos['total_buy_qty'] as num?)?.toInt() ?? 0;
    final int sellQty = (pos['total_sell_qty'] as num?)?.toInt() ?? 0;
    final double buyVal = (pos['total_buy_value'] as num?)?.toDouble() ?? 0;
    final double sellVal = (pos['total_sell_value'] as num?)?.toDouble() ?? 0;
    final double avgBuy = buyQty > 0 ? buyVal / buyQty : 0;
    final double avgSell = sellQty > 0 ? sellVal / sellQty : 0;
    final double avgPrice = isBuy ? avgBuy : avgSell;
    final double ltp = _ltpMap[iToken] ??
        (pos['avg_buy_price'] as num?)?.toDouble() ??
        avgPrice;

    double floating = 0;
    if (netQty > 0)
      floating = (ltp - avgBuy) * netQty;
    else if (netQty < 0) floating = (avgSell - ltp) * netQty.abs();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(symbol,
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(exchange,
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(width: 6),
                          Container(
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFCBD5E1),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text('Avg: ₹${avgPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 11,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        '${isBuy ? "BUY" : "SELL"} ${_positionVolumeLabel(pos)}',
                        style: TextStyle(
                            color: sideColor,
                            fontSize: 11,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color:
                              const Color(0xFF3F45C7).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('LTP ',
                              style: TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 9,
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5)),
                          AnimatedFlipCounter(
                            value: ltp,
                            fractionDigits: 2,
                            prefix: '₹',
                            textStyle: const TextStyle(
                                color: Color(0xFF3F45C7),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('FLOATING P&L',
                    style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 10,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
                AnimatedFlipCounter(
                  value: floating,
                  fractionDigits: 2,
                  prefix: floating >= 0 ? '+₹' : '₹',
                  textStyle: TextStyle(
                    color: floating >= 0
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _positionVolumeLabel(Map<String, dynamic> pos) {
    final netQty = ((pos['net_qty'] as num?)?.toInt() ?? 0).abs();
    final exchange = (pos['exchange'] as String? ?? '').toUpperCase();
    final symbol = (pos['tradingsymbol'] as String? ?? '').toUpperCase();
    final segment = (pos['segment'] as String? ?? '').toUpperCase();
    final lotSize = (pos['lot_size'] as num?)?.toInt() ?? 1;

    bool isLotBased = false;
    if (segment.isNotEmpty) {
      isLotBased =
          segment == 'MCX-FUT' || segment == 'MCX-OPT' || segment == 'NFO-FUT';
    } else if (exchange == 'MCX') {
      isLotBased = true;
    } else if (exchange == 'NFO') {
      isLotBased = symbol.endsWith('FUT');
    }

    if (isLotBased && lotSize > 0) {
      final lots = (netQty / lotSize).round();
      return '$lots LOT';
    }
    return '$netQty QTY';
  }

  Widget _liveMetricGridRow(String l1, double v1, String l2, double v2) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(child: _liveMetricCell(l1, v1, showRightBorder: true)),
          Expanded(child: _liveMetricCell(l2, v2)),
        ],
      ),
    );
  }

  Widget _liveMetricCell(String label, double value,
      {bool showRightBorder = false}) {
    final bool isColored = label.contains('P&L') || label == 'Equity';
    final Color valueColor = isColored
        ? (value >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444))
        : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: showRightBorder
            ? const Border(
                right: BorderSide(width: 1, color: Color(0xFFF1F5F9)))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(label.toUpperCase(),
                style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 4),
          AnimatedFlipCounter(
            value: value,
            fractionDigits: 2,
            textStyle: TextStyle(
                color: valueColor,
                fontSize: 12,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Shared helpers ──

  Widget _sectionLabel(String text) {
    return Text(text,
        style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5));
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _buildControlToggle(String label, bool isOn) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500)),
          GestureDetector(
            onTap: () => _handleToggle(label, !isOn),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              height: 26,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isOn ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleToggle(String label, bool newValue) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      if (label == 'User Status') {
        if (_currentMaster != null) {
          final r = await adminService.updateMasterStatus(
              masterId: _currentMaster!.id, activeStatus: newValue);
          if (r.statusCode == 200) setState(() => _activeStatus = newValue);
        } else {
          final r = await adminService.updateUserDetails(
              userId: _currentUser!.id, activeStatus: newValue);
          if (r.statusCode == 200) setState(() => _activeStatus = newValue);
        }
        return;
      }

      if (_currentUser != null) {
        final r = await adminService.updateUserDetails(
          userId: _currentUser!.id,
          closeOnly: label == 'Close Only' ? newValue : null,
          bet: label == 'BET' ? newValue : null,
          marginSquareOff: label == 'Margin Square Off' ? newValue : null,
          freshStoploss: label == 'Fresh Stop-Loss' ? newValue : null,
        );
        if (r.statusCode == 200) {
          setState(() {
            if (label == 'Close Only') _closeOnly = newValue;
            if (label == 'BET') _bet = newValue;
            if (label == 'Margin Square Off') _marginSquare = newValue;
            if (label == 'Fresh Stop-Loss') _freshStoploss = newValue;
          });
        }
        return;
      }

      if (_currentMaster != null) {
        final cp = _currentMaster!.permissions ??
            MasterPermissions(
              accountSummary: false,
              pnlSummary: false,
              clientSummary: false,
              settlementReport: false,
              generatePdf: false,
              weeklyAdmin: false,
              intradayHistory: false,
              userwiseOpenPosition: false,
              scriptQuantity: false,
              deletedTrade: false,
              tradeAccount: false,
              closeOnly: _closeOnly,
              bet: _bet,
              marginSquare: _marginSquare,
              freshStoploss: _freshStoploss,
            );

        final updated = MasterPermissions(
          accountSummary: cp.accountSummary,
          pnlSummary: cp.pnlSummary,
          clientSummary: cp.clientSummary,
          settlementReport: cp.settlementReport,
          generatePdf: cp.generatePdf,
          weeklyAdmin: cp.weeklyAdmin,
          intradayHistory: cp.intradayHistory,
          userwiseOpenPosition: cp.userwiseOpenPosition,
          scriptQuantity: cp.scriptQuantity,
          deletedTrade: cp.deletedTrade,
          tradeAccount: cp.tradeAccount,
          closeOnly: label == 'Close Only' ? newValue : _closeOnly,
          bet: label == 'BET' ? newValue : _bet,
          marginSquare: label == 'Margin Square Off' ? newValue : _marginSquare,
          freshStoploss: label == 'Fresh Stop-Loss' ? newValue : _freshStoploss,
        );

        final r = await adminService.updateMasterPermissions(
            masterId: _currentMaster!.id, permissions: updated);
        if (r.statusCode == 200) {
          setState(() {
            if (label == 'Close Only') _closeOnly = newValue;
            if (label == 'BET') _bet = newValue;
            if (label == 'Margin Square Off') _marginSquare = newValue;
            if (label == 'Fresh Stop-Loss') _freshStoploss = newValue;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFEF4444)));
      }
    }
  }

  void _handleSettingTap(String label) async {
    switch (label) {
      case 'Credit/Debit':
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  TransactionPage(master: _currentMaster, user: _currentUser)),
        );
        if (result == true && mounted) await _refreshData();
        break;
      case 'Group Quantity Settings':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const GroupQuantityView()));
        break;
      case 'Margin SquareOff Settings':
        showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => MarginSquareoffBottomSheet(
                master: _currentMaster, user: _currentUser));
        break;
      case 'Brk Settings':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BrokerageSettingsView()));
        break;
      case 'Intraday SquareOff':
        showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => IntradaySquareoffBottomSheet(
                master: _currentMaster, user: _currentUser));
        break;
      case 'Trade Margin':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TradeMarginSettingsView()));
        break;
      case 'Script Quantity Setting':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ScriptQuantitySettingsView()));
        break;
      case 'Sharing Details':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SharingDetailsView()));
        break;
      case 'Rejection Log':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RejectionLogHistoryView()));
        break;
      case 'Generate PDF':
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => GeneratePdfBottomSheet(
            preselectedUserId: _currentUser?.id ?? _currentMaster?.id,
            preselectedUserName: username,
          ),
        );
        break;
      case 'Settlement Report':
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettlementReportView()));
        break;
      case 'Account Limit':
        if (_currentMaster != null) _showAccountLimitSheet();
        break;
    }
  }

  // ── User List Tab ──
  Widget _buildUserListTab() {
    if (_isLoadingUsers) {
      return const Center(
          child: CircularProgressIndicator(
              color: Color(0xFF3F45C7), strokeWidth: 2.5));
    }
    if (_usersError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(_usersError!,
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontFamily: 'Inter')),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _fetchUserList,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFF3F45C7),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Retry',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );
    }
    if (_userList.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchUserList,
        child: ListView(
          children: [
            const SizedBox(height: 200),
            Center(
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ]),
                    child: const Icon(Icons.people_outline,
                        size: 32, color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 20),
                  const Text('No users found',
                      style: TextStyle(
                          color: Color(0xFF475569),
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchUserList,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _userList.length,
        itemBuilder: (context, index) {
          final user = _userList[index];
          return GestureDetector(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UsernameView(user: user)),
              );
              if (result == true && mounted) {
                _fetchUserList();
                _refreshData();
              }
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                        style: const TextStyle(
                            color: Color(0xFF3F45C7),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(user.username,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('₹${user.balance.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: user.activeStatus
                              ? const Color(0xFF10B981).withValues(alpha: 0.1)
                              : const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          user.activeStatus ? 'Active' : 'Inactive',
                          style: TextStyle(
                            color: user.activeStatus
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: 18, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Account Limit Bottom Sheet ──
  void _showAccountLimitSheet() async {
    if (_currentMaster == null) return;

    // Fetch current account limit data
    final apiService = Provider.of<ApiService>(context, listen: false);
    final adminService = AdminService(apiService);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AccountLimitSheet(
        masterId: _currentMaster!.id,
        adminService: adminService,
      ),
    );
  }
}

class _AccountLimitSheet extends StatefulWidget {
  final String masterId;
  final AdminService adminService;

  const _AccountLimitSheet(
      {required this.masterId, required this.adminService});

  @override
  State<_AccountLimitSheet> createState() => _AccountLimitSheetState();
}

class _AccountLimitSheetState extends State<_AccountLimitSheet> {
  bool _enabled = false;
  final TextEditingController _maxMastersController =
      TextEditingController(text: '0');
  final TextEditingController _maxUsersController =
      TextEditingController(text: '0');
  int _mastersCreated = 0;
  int _usersCreated = 0;
  Map<String, dynamic>? _parentLimit;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _maxMastersController.dispose();
    _maxUsersController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final response =
          await widget.adminService.getAccountLimit(widget.masterId);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final d = data['data'];
          setState(() {
            _enabled = d['enabled'] ?? false;
            _maxMastersController.text = (d['max_masters'] ?? 0).toString();
            _maxUsersController.text = (d['max_users'] ?? 0).toString();
            _mastersCreated = d['masters_created'] ?? 0;
            _usersCreated = d['users_created'] ?? 0;
            _parentLimit = d['parent_limit'];
            _isLoading = false;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final response = await widget.adminService.updateAccountLimit(
        masterId: widget.masterId,
        enabled: _enabled,
        maxMasters: int.tryParse(_maxMastersController.text) ?? 0,
        maxUsers: int.tryParse(_maxUsersController.text) ?? 0,
      );
      if (response.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Account limit updated'),
              backgroundColor: Color(0xFF10B981)),
        );
        Navigator.pop(context);
      } else {
        final body = jsonDecode(response.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(body['message'] ?? 'Failed'),
                backgroundColor: const Color(0xFFEF4444)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: _isLoading
          ? const SizedBox(
              height: 200,
              child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF3F45C7))))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                            color: const Color(0xFFCBD5E1),
                            borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 16),
                  const Text('Account Limit',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                      'Set limits on how many accounts this master can create',
                      style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 13,
                          fontFamily: 'Inter')),
                  const SizedBox(height: 20),

                  // Enable toggle
                  _sheetCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Limit Enabled',
                            style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600)),
                        GestureDetector(
                          onTap: () => setState(() => _enabled = !_enabled),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 44,
                            height: 26,
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: _enabled
                                  ? const Color(0xFF3F45C7)
                                  : const Color(0xFFCBD5E1),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: AnimatedAlign(
                              duration: const Duration(milliseconds: 200),
                              alignment: _enabled
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_enabled) ...[
                    const SizedBox(height: 16),
                    // Max Masters
                    _sheetCard(
                      child: Column(
                        children: [
                          _limitInputRow('Max Masters', _maxMastersController),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _limitInputRow('Max Clients', _maxUsersController),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    // Stats
                    _sheetCard(
                      child: Column(
                        children: [
                          _statRow('Masters', _mastersCreated,
                              int.tryParse(_maxMastersController.text) ?? 0),
                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          _statRow('Clients', _usersCreated,
                              int.tryParse(_maxUsersController.text) ?? 0),
                        ],
                      ),
                    ),

                    if (_parentLimit != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF3F45C7).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 16, color: Color(0xFF3F45C7)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Parent limit: ${_parentLimit!['max_masters']} masters, ${_parentLimit!['max_users']} clients',
                                style: const TextStyle(
                                    color: Color(0xFF3F45C7),
                                    fontSize: 12,
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 24),
                  // Buttons
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: const Color(0xFFF1F5F9)),
                            ),
                            child: const Center(
                                child: Text('Cancel',
                                    style: TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 14,
                                        fontFamily: 'Inter',
                                        fontWeight: FontWeight.w600))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _isSaving ? null : _save,
                          child: Container(
                            height: 48,
                            decoration: BoxDecoration(
                              color: _isSaving
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF3F45C7),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: _isSaving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2))
                                  : const Text('Save',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontFamily: 'Inter',
                                          fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _sheetCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
  }

  Widget _limitInputRow(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500)),
          SizedBox(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero),
              onChanged: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(String label, int created, int max) {
    final remaining = max - created;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 13,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$created created',
                style: const TextStyle(
                    color: Color(0xFF3F45C7),
                    fontSize: 11,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (remaining > 0
                      ? const Color(0xFF10B981)
                      : const Color(0xFFEF4444))
                  .withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$remaining left',
              style: TextStyle(
                color: remaining > 0
                    ? const Color(0xFF10B981)
                    : const Color(0xFFEF4444),
                fontSize: 11,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PerTradePnl {
  final double pnl;
  final bool isClosing;
  final String? openedAt;
  _PerTradePnl({required this.pnl, required this.isClosing, this.openedAt});
}
