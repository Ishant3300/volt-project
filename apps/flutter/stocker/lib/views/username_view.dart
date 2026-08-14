import "../providers/user_profile_provider.dart";
import "../services/master_service.dart";
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:jwt_decode/jwt_decode.dart';
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
import 'trade_wallet_bottom_sheet.dart';
import 'brokerage_settings_view.dart';
import 'intraday_squareoff_bottom_sheet.dart';
import 'script_quantity_settings_view.dart';
import 'sharing_details_view.dart';
import 'rejection_log_history_view.dart';
import 'settlement_report_view.dart';
import '../pages/transaction_page.dart';
import 'reports_view.dart';
import 'manage_reports_view.dart';

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

  // Sub-master list state (for Master view)
  List<Master> _subMasterList = [];
  bool _isLoadingSubMasters = false;
  String? _subMastersError;

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
      _fetchSubMasterList();
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
  double get balance => _currentMaster?.equity ?? _currentUser!.equity;
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
      });
    };

    // Server-pushed metrics from metricsEngine — update position tab in real-time
    _livePriceService.onMetricsUpdate = (data) {
      if (!mounted) return;
      final userId = data['user_id']?.toString() ?? '';
      // Only apply if this is the user we're viewing
      if (_currentUser != null && userId == _currentUser!.id) {
        setState(() {
          _liveUserMetrics = Map<String, dynamic>.from(data);
          final List positions = data['positions'] ?? [];
          _livePositions = positions.cast<Map<String, dynamic>>();
        });
      }
    };

    // Listen for trade_executed / margin_square_off events to trigger re-fetch
    _livePriceService.onTradeExecuted = (data) {
      if (!mounted) return;
      // Small delay to let metricsEngine finish rebuilding before re-fetching
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _fetchLivePositions();
      });
    };

    // Server-pushed master metrics — update aggregated position tab for master view
    _livePriceService.onMasterMetricsUpdate = (data) {
      if (!mounted || _currentMaster == null) return;
      final List users = data['users'] ?? [];
      for (final u in users) {
        final uid = u['user_id']?.toString() ?? '';
        if (uid.isNotEmpty) {
          _perUserMetricsCache[uid] = Map<String, dynamic>.from(u);
        }
      }
      _reaggregateMasterMetrics();
    };

    _livePriceService.onConnectionChanged = (connected) {
      if (connected) _authenticateAndSubscribe();
    };
    _livePriceService.connect();
  }

  /// When viewing a master's position tab, accumulate per-user metric pushes
  /// to keep the aggregated view live.
  final Map<String, Map<String, dynamic>> _perUserMetricsCache = {};

  void _reaggregateMasterMetrics() {
    // Re-aggregate from all cached user metrics
    double totalRealised = 0,
        totalFloating = 0,
        totalMargin = 0,
        totalCredit = 0;
    double totalEquity = 0, totalFreeMargin = 0;
    final Map<String, Map<String, dynamic>> instrMap = {};

    for (final userMetrics in _perUserMetricsCache.values) {
      totalRealised += (userMetrics['realised_pnl'] as num?)?.toDouble() ?? 0;
      totalFloating += (userMetrics['position_pnl'] as num?)?.toDouble() ?? 0;
      totalMargin += (userMetrics['margin_used'] as num?)?.toDouble() ?? 0;
      totalCredit += (userMetrics['credit'] as num?)?.toDouble() ?? 0;
      totalEquity += (userMetrics['equity'] as num?)?.toDouble() ?? 0;
      totalFreeMargin += (userMetrics['free_margin'] as num?)?.toDouble() ?? 0;

      final List positions = userMetrics['positions'] ?? [];
      for (final pos in positions) {
        final iToken = pos['instrument_token']?.toString() ?? '';
        if (iToken.isEmpty) continue;
        if (!instrMap.containsKey(iToken)) {
          instrMap[iToken] = Map<String, dynamic>.from(pos);
          instrMap[iToken]!['net_qty'] = 0;
          instrMap[iToken]!['floating_pnl'] = 0.0;
        }
        instrMap[iToken]!['net_qty'] = (instrMap[iToken]!['net_qty'] as int) +
            ((pos['net_qty'] as num?)?.toInt() ?? 0);
        instrMap[iToken]!['floating_pnl'] =
            (instrMap[iToken]!['floating_pnl'] as double) +
                ((pos['floating_pnl'] as num?)?.toDouble() ?? 0);
      }
    }

    final livePositions =
        instrMap.values.where((p) => (p['net_qty'] as int) != 0).toList();
    final m2m = totalRealised + totalFloating;
    final equity = totalEquity;
    final freeMargin = totalFreeMargin;

    setState(() {
      _livePositions = livePositions;
      _liveUserMetrics = {
        'credit': _round2(totalCredit),
        'realised_pnl': _round2(totalRealised),
        'position_pnl': _round2(totalFloating),
        'm2m_pnl': _round2(m2m),
        'margin_used': _round2(totalMargin),
        'equity': _round2(equity),
        'free_margin': _round2(freeMargin),
        'positions': livePositions,
      };
    });
  }

  Future<void> _authenticateAndSubscribe() async {
    try {
      final token = await _storage.getToken();
      if (token != null) {
        final payload = Jwt.parseJwt(token);
        final callerRole = payload['role'] as String?;

        // Authenticate as the VIEWED user/master so the server pushes their metrics to this connection
        if (_currentUser != null) {
          _livePriceService.authenticate(_currentUser!.id, role: 'user');
        } else if (_currentMaster != null) {
          _livePriceService.authenticate(_currentMaster!.id, role: 'master');
        } else {
          final userId = payload['id'] as String?;
          if (userId != null)
            _livePriceService.authenticate(userId, role: callerRole);
        }
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

      // Use metricsEngine cached metrics (same data as WebSocket push)
      String url = '/master/positions/live-metrics';
      if (_currentUser != null) {
        url += '?user_id=${_currentUser!.id}';
      } else if (_currentMaster != null) {
        url += '?master_id=${_currentMaster!.id}';
      }

      final response = await apiService.get(url, token: token);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List data = body['data'] ?? [];
        final Set<String> tokens = {};

        if (_currentUser != null && data.isNotEmpty) {
          // Single user metrics
          _liveUserMetrics = Map<String, dynamic>.from(data[0]);
          final List positions = _liveUserMetrics!['positions'] ?? [];
          _livePositions = positions.cast<Map<String, dynamic>>();
          for (final pos in positions) {
            final t = pos['instrument_token']?.toString();
            if (t != null) tokens.add(t);
          }
        } else if (_currentMaster != null && data.isNotEmpty) {
          // Master view: aggregate all users' metrics and seed per-user cache
          double totalRealised = 0,
              totalFloating = 0,
              totalMargin = 0,
              totalCredit = 0;
          double totalEquity = 0, totalFreeMargin = 0;
          final Map<String, Map<String, dynamic>> instrMap = {};

          for (final userMetrics in data) {
            // Seed per-user cache for live WebSocket updates
            final uid = userMetrics['user_id']?.toString() ?? '';
            if (uid.isNotEmpty) {
              _perUserMetricsCache[uid] =
                  Map<String, dynamic>.from(userMetrics);
            }
            totalRealised +=
                (userMetrics['realised_pnl'] as num?)?.toDouble() ?? 0;
            totalFloating +=
                (userMetrics['position_pnl'] as num?)?.toDouble() ?? 0;
            totalMargin +=
                (userMetrics['margin_used'] as num?)?.toDouble() ?? 0;
            totalCredit += (userMetrics['credit'] as num?)?.toDouble() ?? 0;
            totalEquity += (userMetrics['equity'] as num?)?.toDouble() ?? 0;
            totalFreeMargin +=
                (userMetrics['free_margin'] as num?)?.toDouble() ?? 0;

            final List positions = userMetrics['positions'] ?? [];
            for (final pos in positions) {
              final iToken = pos['instrument_token']?.toString() ?? '';
              if (iToken.isEmpty) continue;
              if (!instrMap.containsKey(iToken)) {
                instrMap[iToken] = Map<String, dynamic>.from(pos);
                instrMap[iToken]!['net_qty'] = 0;
                instrMap[iToken]!['floating_pnl'] = 0.0;
              }
              instrMap[iToken]!['net_qty'] =
                  (instrMap[iToken]!['net_qty'] as int) +
                      ((pos['net_qty'] as num?)?.toInt() ?? 0);
              instrMap[iToken]!['floating_pnl'] =
                  (instrMap[iToken]!['floating_pnl'] as double) +
                      ((pos['floating_pnl'] as num?)?.toDouble() ?? 0);
              tokens.add(iToken);
            }
          }

          _livePositions =
              instrMap.values.where((p) => (p['net_qty'] as int) != 0).toList();
          final m2m = totalRealised + totalFloating;
          final equity = totalEquity;
          final freeMargin = totalFreeMargin;
          _liveUserMetrics = {
            'credit': _round2(totalCredit),
            'realised_pnl': _round2(totalRealised),
            'position_pnl': _round2(totalFloating),
            'm2m_pnl': _round2(m2m),
            'margin_used': _round2(totalMargin),
            'equity': _round2(equity),
            'free_margin': _round2(freeMargin),
            'positions': _livePositions,
          };
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
      // Always pass the viewed master's ID to get their hierarchy's users
      final url = '/admin/users?master_id=${_currentMaster!.id}&limit=100';
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

  Future<void> _fetchSubMasterList() async {
    if (_currentMaster == null) return;
    setState(() {
      _isLoadingSubMasters = true;
      _subMastersError = null;
    });
    try {
      final token = await _storage.getToken();
      final apiService = ApiService(backendUrl);
      final url = '/master/masters?parent_id=${_currentMaster!.id}&limit=100';
      final response = await apiService.get(url, token: token);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> mastersJson =
              data['data']['masters'] ?? data['data'] ?? [];
          setState(() {
            _subMasterList =
                mastersJson.map((j) => Master.fromJson(j)).toList();
            _isLoadingSubMasters = false;
          });
        } else {
          setState(() {
            _subMastersError = data['message'] ?? 'Failed';
            _isLoadingSubMasters = false;
          });
        }
      } else {
        setState(() {
          _subMastersError = 'Failed to load sub-masters';
          _isLoadingSubMasters = false;
        });
      }
    } catch (e) {
      setState(() {
        _subMastersError = 'Error: $e';
        _isLoadingSubMasters = false;
      });
    }
  }

  Future<void> _refreshData() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      final isMaster = profileProvider.isMaster;

      if (_currentMaster != null) {
        final response = isMaster
            ? await MasterService(apiService)
                .getChildMasterById(_currentMaster!.id)
            : await AdminService(apiService).getMasterById(_currentMaster!.id);

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
        final response = isMaster
            ? await MasterService(apiService).getUserById(_currentUser!.id)
            : await AdminService(apiService).getUserById(_currentUser!.id);

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
                              color: Colors.black, size: kIconSizeMedium),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        username,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeViewTitle,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold),
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
                              size: kIconSizeSmall, color: Color(0xFF3F45C7)),
                          SizedBox(width: 4),
                          Text('Edit',
                              style: TextStyle(
                                  color: Color(0xFF3F45C7),
                                  fontSize: kFontSizeBodySmall,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightSemiBold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

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
                  if (_currentMaster != null) _buildTab('Masters', 3),
                  if (_currentMaster != null) _buildTab('Users', 4),
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
                          : _selectedTabIndex == 3
                              ? _buildSubMasterListTab()
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
              fontSize: kFontSizeBodySmall,
              fontFamily: 'Inter',
              fontWeight: kFontWeightSemiBold,
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
                _settingRow(kIconCreditDebit, 'Credit/Debit'),
                _settingRow(kIconTradeWallet, 'Trade Wallet'),
                _settingRow(kIconGroupQuantity, 'Group Quantity Settings'),
                if (_currentUser != null)
                  _settingRow(
                      kIconMarginSquareoff, 'Margin SquareOff Settings'),
                _settingRow(kIconBrokerageSettings, 'Brk Settings'),
                _settingRow(kIconIntradaySquareoff, 'Intraday SquareOff'),
                _settingRow(kIconSharingDetails, 'Sharing Details'),
                _settingRow(kIconScriptQuantity, 'Script Quantity Setting',
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
                _settingRow(kIconRejectionLog, 'Rejection Log'),
                _settingRow(kIconGeneratePdfUser, 'Generate PDF'),
                _settingRow(kIconSettlementReport, 'Settlement Report',
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
                      fontSize: kFontSizeBodySmall,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeBodySmall,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightMedium),
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

  Widget _settingRow(dynamic iconOrPath, String label, {bool isLast = false}) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _handleSettingTap(label),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                iconOrPath is String
                    ? SvgPicture.asset(iconOrPath,
                        width: kIconSizeMedium,
                        height: kIconSizeMedium,
                        colorFilter: const ColorFilter.mode(
                            Color(0xFF3F45C7), BlendMode.srcIn))
                    : Icon(iconOrPath as IconData,
                        size: kIconSizeMedium, color: const Color(0xFF3F45C7)),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: kFontSizeBody,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium))),
                const Icon(Icons.chevron_right,
                    size: kIconSizeMedium, color: Color(0xFF94A3B8)),
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
                        fontWeight: kFontWeightSemiBold)),
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
                          fontWeight: kFontWeightSemiBold)),
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

  /// Determine which trades are "closing" trades and their P&L.
  /// Uses the backend-provided pnl field as the primary source of truth.
  /// If trade.pnl != 0, the backend already computed it (handles carry-forward
  /// positions correctly since the server sees all trades including hidden ones).
  /// Falls back to local FIFO pairing only for openedAt duration display.
  Map<String, _PerTradePnl> _computePerTradePnl(List<Trade> completedTrades) {
    final Map<String, _PerTradePnl> result = {};
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

        // Backend marks closing trades with non-zero pnl — trust it directly.
        // This correctly handles carry-forward positions where the opening trade
        // is hidden (trade_type='carry_forward') but pnl was computed server-side.
        if (t.pnl != 0) {
          result[t.id] =
              _PerTradePnl(pnl: t.pnl, isClosing: true, openedAt: openedAt);
          // Update local net qty tracking for duration purposes
          netQty += isBuy ? t.quantity : -t.quantity;
          if (netQty == 0) openedAt = null;
          continue;
        }

        // Track net position locally for openedAt timestamp (duration display)
        if (netQty == 0) {
          openedAt = t.createdAt;
          netQty = isBuy ? t.quantity : -t.quantity;
        } else if ((netQty > 0 && isBuy) || (netQty < 0 && !isBuy)) {
          // Adding to position
          netQty += isBuy ? t.quantity : -t.quantity;
        } else {
          // Closing trade detected by local FIFO (pnl was 0 but it's still closing)
          result[t.id] =
              _PerTradePnl(pnl: t.pnl, isClosing: true, openedAt: openedAt);
          netQty += isBuy ? t.quantity : -t.quantity;
          if (netQty == 0) openedAt = null;
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
                              fontSize: kFontSizeTradeSymbol,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold,
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
                              fontSize: kFontSizeTradeBadge,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold,
                              letterSpacing: 0.3)),
                    ),
                    if (trade.tradeType == 'margin_square_off' ||
                        trade.placedBy == 'SYSTEM') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Text('AUTO SQOFF',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 10,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3)),
                      ),
                    ],
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
                          fontSize: kFontSizeTradeBadge,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(_tradeVolumeLabel(trade),
                        style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeTradeMetadata,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium)),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('·',
                            style: TextStyle(
                                fontSize: kFontSizeTradeMetadata,
                                color: Color(0xFFCBD5E1)))),
                    const Icon(Icons.access_time,
                        size: 11, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 3),
                    Text(formattedDate,
                        style: const TextStyle(
                            color: Color(0xFF94A3B8),
                            fontSize: kFontSizeTradeMetadata,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightMedium)),
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
                                fontSize: kFontSizeTradeMetadata,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightMedium),
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
                      fontSize: kFontSizeTradePrice,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold)),
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
                      fontSize: kFontSizeTradeBadge,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightBold,
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
                            fontSize: kFontSizeTradeSymbol,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold,
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
                          '${trade.transactionType} · ${_tradeVolumeLabel(trade)}',
                          style: TextStyle(
                              color: sideColor,
                              fontSize: kFontSizeTradeBadge,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold,
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
                                    fontSize: kFontSizeTradeMetadata,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightMedium),
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
                          fontSize: kFontSizeTradePrice,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold)),
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
                        fontSize: kFontSizeTradeBadge,
                        fontFamily: 'Inter',
                        fontWeight: kFontWeightSemiBold,
                        letterSpacing: 0.3)),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.access_time, size: 11, color: Color(0xFF94A3B8)),
              const SizedBox(width: 3),
              Text(formattedDate,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: kFontSizeTradeMetadata,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightMedium)),
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
                        fontWeight: kFontWeightSemiBold)),
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
    final double freeMargin = (metrics['free_margin'] as num?)?.toDouble() ?? 0;

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
                if (_currentUser != null) ...[
                  _liveMetricGridRow(
                      'Margin Used', marginUsed, 'Equity', equity),
                  const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  _liveMetricGridRow('Free Margin', freeMargin, '', 0,
                      hideSecond: true),
                ] else ...[
                  _liveMetricGridRow('Margin Used', marginUsed, '', 0,
                      hideSecond: true),
                ],
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
                fontWeight: kFontWeightMedium,
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

    final double avgBuyPrice = (pos['avg_buy_price'] as num?)?.toDouble() ?? 0;
    final double avgSellPrice =
        (pos['avg_sell_price'] as num?)?.toDouble() ?? 0;
    final double avgPrice = isBuy ? avgBuyPrice : avgSellPrice;
    final double ltp =
        _ltpMap[iToken] ?? (pos['ltp'] as num?)?.toDouble() ?? avgPrice;

    // CMP: use server-pushed value from metricsEngine (bid for BUY, ask for SELL)
    // Falls back to LTP if cmp not available
    final double cmp = (pos['cmp'] as num?)?.toDouble() ?? ltp;

    // Use server-pushed floating P&L directly — no local recomputation.
    // metricsEngine is the single source of truth for all metrics.
    double floating = (pos['floating_pnl'] as num?)?.toDouble() ?? 0;

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
                              fontSize: kFontSizePositionSymbol,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold,
                              letterSpacing: -0.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(exchange,
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: kFontSizePositionDetail,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightMedium)),
                          const SizedBox(width: 6),
                          Container(
                              width: 3,
                              height: 3,
                              decoration: const BoxDecoration(
                                  color: Color(0xFFCBD5E1),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(
                              '${isBuy ? "BUY" : "SELL"}: ${_positionVolumeLabel(pos)}',
                              style: TextStyle(
                                  color: sideColor,
                                  fontSize: kFontSizePositionDetail,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightSemiBold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('ATP: ${avgPrice.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: kFontSizePositionDetail,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightMedium)),
                          const SizedBox(width: 12),
                          Text('CMP: ${cmp.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: kFontSizePositionDetail,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightMedium)),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  '${floating >= 0 ? '+' : ''}${floating.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: floating >= 0
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    fontSize: kFontSizePositionPnl,
                    fontFamily: 'Inter',
                    fontWeight: kFontWeightBold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Volume label matching orders_page.dart logic:
  /// Only MCX-FUT, MCX-OPT, NFO-OPT use lots. Everything else uses quantity.
  /// Uses _trades list to look up lot_size/segment (same source as Trades tab).
  String _positionVolumeLabel(Map<String, dynamic> pos) {
    final netQty = ((pos['net_qty'] as num?)?.toInt() ?? 0).abs();
    final String iToken = pos['instrument_token']?.toString() ?? '';
    final exchange = (pos['exchange'] as String? ?? '').toUpperCase();

    // Look up lot_size and segment from the already-fetched trades (same data Trades tab uses)
    int lotSize = (pos['lot_size'] as num?)?.toInt() ?? 1;
    String segment = (pos['segment'] as String? ?? '').toUpperCase();

    // If position data doesn't have segment/lot_size, find it from _trades
    if (segment.isEmpty || lotSize <= 1) {
      for (final t in _trades) {
        if (t.instrumentToken == iToken) {
          if (t.segment.isNotEmpty) segment = t.segment.toUpperCase();
          if (t.lotSize > 1) lotSize = t.lotSize;
          break;
        }
      }
    }

    final bool isLot = segment == 'MCX-FUT' ||
        segment == 'MCX-OPT' ||
        segment == 'NFO-OPT' ||
        (segment.isEmpty && exchange == 'MCX');

    if (isLot && lotSize > 0) {
      final lots = (netQty / lotSize).round();
      return '$lots LOT';
    }
    return '$netQty QTY';
  }

  /// Trade volume label: uses Trade model's isLotBased/lots/quantity.
  String _tradeVolumeLabel(Trade trade) {
    if (trade.isLotBased && trade.lotSize > 0) {
      return '${trade.lots} LOT';
    }
    return '${trade.quantity} QTY';
  }

  Widget _liveMetricGridRow(String l1, double v1, String l2, double v2,
      {bool hideSecond = false}) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
              child: _liveMetricCell(l1, v1, showRightBorder: !hideSecond)),
          if (!hideSecond)
            Expanded(child: _liveMetricCell(l2, v2))
          else
            const Expanded(child: SizedBox()),
        ],
      ),
    );
  }

  Widget _liveMetricCell(String label, double value,
      {bool showRightBorder = false}) {
    final bool isColored = label.contains('P&L') || label == 'Free Margin';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 9,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightSemiBold,
                  letterSpacing: 0.3),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(2),
            style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontFamily: 'Inter',
                fontWeight: kFontWeightBold),
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
            fontSize: kFontSizeNavLabel,
            fontFamily: 'Inter',
            fontWeight: kFontWeightSemiBold,
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
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightMedium)),
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
          // Refresh the user object so Edit page gets the latest state
          await _refreshData();
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
        if (result == true && mounted) {
          await _refreshData();
          _fetchLivePositions(); // Refresh position tab metrics after credit/debit
        }
        break;
      case 'Trade Wallet':
        {
          final walletResult = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => TradeWalletBottomSheet(
                master: _currentMaster, user: _currentUser),
          );
          if (walletResult == true && mounted) {
            await _refreshData();
            _fetchLivePositions(); // Refresh metrics/balances after funding
          }
        }
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
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => BrokerageSettingsView(
                    ownerId: _currentUser?.id ?? _currentMaster?.id,
                    ownerType: _currentUser != null ? 'User' : 'Master')));
        break;
      case 'Intraday SquareOff':
        showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => IntradaySquareoffBottomSheet(
                master: _currentMaster, user: _currentUser));
        break;
      case 'Script Quantity Setting':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ScriptQuantitySettingsView(
                    ownerId: _currentUser?.id ?? _currentMaster?.id,
                    ownerType: _currentUser != null ? 'User' : 'Master')));
        break;
      case 'Sharing Details':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SharingDetailsView(
                    master: _currentMaster, user: _currentUser)));
        break;
      case 'Rejection Log':
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => RejectionLogHistoryView(
                    userId: _currentUser?.id ?? _currentMaster?.id)));
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
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SettlementReportView(
                    master: _currentMaster, user: _currentUser)));
        break;
      case 'Account Limit':
        if (_currentMaster != null) _showAccountLimitSheet();
        break;
    }
  }

  // ── Manage User Report Permissions Sheet ──
  void _showManageUserReportsSheet() {
    final user = _currentUser!;
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final parentPerms = profile.reportPermissions;

    // Current user's report_permissions (from model or default to true)
    final currentPerms = <String, bool>{
      'account_summary': user.reportPermissions?['account_summary'] ?? true,
      'pnl_summary': user.reportPermissions?['pnl_summary'] ?? true,
      'client_summary': user.reportPermissions?['client_summary'] ?? true,
      'settlement_report': user.reportPermissions?['settlement_report'] ?? true,
      'generate_pdf': user.reportPermissions?['generate_pdf'] ?? true,
      'weekly_admin': user.reportPermissions?['weekly_admin'] ?? true,
      'intraday_history': user.reportPermissions?['intraday_history'] ?? true,
      'userwise_open_position': user.reportPermissions?['userwise_open_position'] ?? true,
      'script_quantity': user.reportPermissions?['script_quantity'] ?? true,
      'deleted_trade': user.reportPermissions?['deleted_trade'] ?? true,
      'trade_account': user.reportPermissions?['trade_account'] ?? true,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ManageUserReportsSheet(
        userId: user.id,
        currentPerms: currentPerms,
        parentPerms: parentPerms,
      ),
    );
  }

  // ── Sub-Master List Tab ──
  Widget _buildSubMasterListTab() {
    if (_isLoadingSubMasters) {
      return const Center(
          child: CircularProgressIndicator(
              color: Color(0xFF3F45C7), strokeWidth: 2.5));
    }
    if (_subMastersError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFFEF4444)),
            const SizedBox(height: 12),
            Text(_subMastersError!,
                style: const TextStyle(
                    color: Color(0xFFEF4444),
                    fontSize: 13,
                    fontFamily: 'Inter')),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _fetchSubMasterList,
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
                        fontWeight: kFontWeightSemiBold)),
              ),
            ),
          ],
        ),
      );
    }
    if (_subMasterList.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchSubMasterList,
        child: ListView(children: [
          const SizedBox(height: 200),
          Center(
            child: Column(children: [
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
                child: const Icon(Icons.supervisor_account,
                    size: 32, color: Color(0xFFCBD5E1)),
              ),
              const SizedBox(height: 20),
              const Text('No sub-masters found',
                  style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: kFontWeightSemiBold)),
            ]),
          ),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchSubMasterList,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _subMasterList.length,
        itemBuilder: (context, index) {
          final master = _subMasterList[index];
          return GestureDetector(
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => UsernameView(master: master)),
              );
              if (result == true && mounted) {
                _fetchSubMasterList();
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
              child: Row(children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12)),
                  child: Center(
                    child: Text(
                        master.name.isNotEmpty
                            ? master.name[0].toUpperCase()
                            : 'M',
                        style: const TextStyle(
                            color: Color(0xFF8B5CF6),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightBold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(master.name,
                            style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightSemiBold)),
                        const SizedBox(height: 2),
                        Row(children: [
                          Text(master.username,
                              style: const TextStyle(
                                  color: Color(0xFF94A3B8),
                                  fontSize: 12,
                                  fontFamily: 'Inter',
                                  fontWeight: kFontWeightMedium)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4)),
                            child: const Text('MASTER',
                                style: TextStyle(
                                    color: Color(0xFF8B5CF6),
                                    fontSize: 9,
                                    fontFamily: 'Inter',
                                    fontWeight: kFontWeightBold,
                                    letterSpacing: 0.3)),
                          ),
                        ]),
                      ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(master.credits.toStringAsFixed(2),
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 13,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightSemiBold)),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                        color: master.activeStatus
                            ? const Color(0xFF10B981).withValues(alpha: 0.1)
                            : const Color(0xFFEF4444).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(master.activeStatus ? 'Active' : 'Inactive',
                        style: TextStyle(
                            color: master.activeStatus
                                ? const Color(0xFF10B981)
                                : const Color(0xFFEF4444),
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: kFontWeightSemiBold)),
                  ),
                ]),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: kIconSizeMedium, color: Color(0xFF94A3B8)),
              ]),
            ),
          );
        },
      ),
    );
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
                        fontWeight: kFontWeightSemiBold)),
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
                          fontWeight: kFontWeightSemiBold)),
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
                            fontWeight: kFontWeightBold),
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
                                fontWeight: kFontWeightSemiBold)),
                        const SizedBox(height: 2),
                        Text(user.username,
                            style: const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                                fontFamily: 'Inter',
                                fontWeight: kFontWeightMedium)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${user.credits.toStringAsFixed(2)}',
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontFamily: 'Inter',
                              fontWeight: kFontWeightSemiBold)),
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
                            fontWeight: kFontWeightSemiBold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      size: kIconSizeMedium, color: Color(0xFF94A3B8)),
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
                  const SizedBox(height: 16),
                  const Text('Account Limit',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 18,
                          fontFamily: 'Inter',
                          fontWeight: kFontWeightBold)),
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
                                fontWeight: kFontWeightSemiBold)),
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
                                    fontWeight: kFontWeightMedium),
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
                                        fontWeight: kFontWeightSemiBold))),
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
                                          fontWeight: kFontWeightSemiBold)),
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
                  fontWeight: kFontWeightMedium)),
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
                  fontWeight: kFontWeightSemiBold),
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
                      fontWeight: kFontWeightMedium))),
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
                    fontWeight: kFontWeightSemiBold)),
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
                fontWeight: kFontWeightSemiBold,
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

// ── Bottom sheet for managing a User's report permissions ──
class _ManageUserReportsSheet extends StatefulWidget {
  final String userId;
  final Map<String, bool> currentPerms;
  final Map<String, bool> parentPerms;

  const _ManageUserReportsSheet({
    required this.userId,
    required this.currentPerms,
    required this.parentPerms,
  });

  @override
  State<_ManageUserReportsSheet> createState() => _ManageUserReportsSheetState();
}

class _ManageUserReportsSheetState extends State<_ManageUserReportsSheet> {
  late Map<String, bool> _perms;
  bool _isUpdating = false;
  bool _hasChanges = false;

  // Only the report permissions relevant to Users
  static const _labels = {
    'account_summary': 'Account Summary',
    'generate_pdf': 'Generate PDF',
    'intraday_history': 'Intraday History',
    'userwise_open_position': 'Userwise Position',
    'script_quantity': 'Script Quantity',
    'deleted_trade': 'Deleted Trade',
    'trade_account': 'Rejection Log',
  };

  @override
  void initState() {
    super.initState();
    _perms = Map.from(widget.currentPerms);
  }

  Future<void> _save() async {
    setState(() => _isUpdating = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final res = await api.put(
        '/master/users/${widget.userId}/report-permissions',
        {'report_permissions': _perms},
        token: token,
      );
      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Report permissions updated'),
            backgroundColor: Color(0xFF10B981),
          ));
        }
      } else {
        final body = jsonDecode(res.body);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(body['message'] ?? 'Failed to update'),
            backgroundColor: const Color(0xFFEF4444),
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          const Text('Manage Reports', style: TextStyle(
            color: Colors.black, fontSize: kFontSizeSectionHeader,
            fontFamily: 'Inter', fontWeight: kFontWeightBold,
          )),
          const SizedBox(height: 16),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _labels.entries.map((e) {
                final parentHas = widget.parentPerms[e.key] ?? true;
                return _buildToggle(e.key, e.value, parentHas);
              }).toList(),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: 16, right: 16, top: 12,
              bottom: 16 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: GestureDetector(
              onTap: _isUpdating || !_hasChanges ? null : _save,
              child: Container(
                width: double.infinity, height: 50,
                decoration: BoxDecoration(
                  color: _isUpdating || !_hasChanges
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF3F45C7),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: _isUpdating
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('UPDATE', style: TextStyle(
                          color: Colors.white, fontSize: kFontSizeButtonText,
                          fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle(String key, String label, bool parentHas) {
    final value = _perms[key] ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(
                  color: parentHas ? Colors.black : const Color(0xFF94A3B8),
                  fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightMedium,
                )),
                if (!parentHas)
                  const Text('Disabled by parent', style: TextStyle(
                    color: Color(0xFFEF4444), fontSize: 11, fontFamily: 'Inter',
                  )),
              ],
            ),
          ),
          GestureDetector(
            onTap: parentHas ? () {
              setState(() {
                _perms[key] = !value;
                _hasChanges = true;
              });
            } : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 26, padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: !parentHas
                    ? const Color(0xFFE2E8F0)
                    : value
                        ? const Color(0xFF3F45C7)
                        : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value && parentHas ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(width: 22, height: 22, decoration: BoxDecoration(
                  color: parentHas ? Colors.white : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                )),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
