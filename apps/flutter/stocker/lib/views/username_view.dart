import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../models/trade.dart';
import '../models/position.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../utils/date_formatter.dart';
import 'create_user_view.dart';
import 'create_master_view.dart';
import 'credit_debit_bottom_sheet.dart';
import 'group_quantity_view.dart';
import 'margin_squareoff_bottom_sheet.dart';
import 'brokerage_settings_view.dart';
import 'intraday_squareoff_bottom_sheet.dart';
import 'trade_margin_settings_view.dart';
import 'script_quantity_settings_view.dart';
import 'sharing_details_view.dart';
import 'rejection_log_history_view.dart';
import 'settlement_report_view.dart';

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

  // Local state for permissions that can be updated
  late bool _activeStatus;
  late bool _closeOnly;
  late bool _bet;
  late bool _marginSquare;
  late bool _freshStoploss;

  // Local state for master/user data that can be updated
  late Master? _currentMaster;
  late User? _currentUser;

  // Trade list state
  List<Trade> _trades = [];
  bool _isLoadingTrades = false;
  String? _tradesError;

  // Position state
  Position? _position;
  bool _isLoadingPosition = false;
  String? _positionError;

  @override
  void initState() {
    super.initState();
    _currentMaster = widget.master;
    _currentUser = widget.user;

    // Initialize local state from the master/user object
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

    // Fetch trades and position when initialized
    _fetchTrades();
    _fetchPosition();
  }

  Future<void> _fetchPosition() async {
    if (_currentMaster == null) {
      // Position is only available for masters, not users
      return;
    }

    setState(() {
      _isLoadingPosition = true;
      _positionError = null;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.getMasterPosition(_currentMaster!.id);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _position = Position.fromJson(data['data']);
            _isLoadingPosition = false;
          });
        } else {
          setState(() {
            _positionError = data['message'] ?? 'Failed to load position';
            _isLoadingPosition = false;
          });
        }
      } else {
        setState(() {
          _positionError = 'Failed to load position';
          _isLoadingPosition = false;
        });
      }
    } catch (e) {
      setState(() {
        _positionError = 'Error: $e';
        _isLoadingPosition = false;
      });
    }
  }

  Future<void> _fetchTrades() async {
    setState(() {
      _isLoadingTrades = true;
      _tradesError = null;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      final response = await adminService.getAllTrades(
        masterId: _currentMaster?.id,
        userId: _currentUser?.id,
        limit: 50,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final List<dynamic> tradesJson = data['data']['trades'] ?? [];
          setState(() {
            _trades = tradesJson.map((json) => Trade.fromJson(json)).toList();
            _isLoadingTrades = false;
          });
        } else {
          setState(() {
            _tradesError = data['message'] ?? 'Failed to load trades';
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

  Future<void> _refreshData() async {
    if (_currentMaster != null) {
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final adminService = AdminService(apiService);

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
      } catch (e) {
        print('Error refreshing master data: $e');
      }
    } else if (_currentUser != null) {
      try {
        final apiService = Provider.of<ApiService>(context, listen: false);
        final adminService = AdminService(apiService);

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
      } catch (e) {
        print('Error refreshing user data: $e');
      }
    }
  }

  // Helper getters to access common fields
  String get username => _currentMaster?.username ?? _currentUser!.username;
  double get credits => _currentMaster?.credits ?? _currentUser!.credits;
  double get balance => _currentMaster?.balance ?? _currentUser!.balance;
  String get createdAt => _currentMaster?.createdAt ?? _currentUser!.createdAt;
  String? get lastLogin => _currentMaster?.lastLogin ?? _currentUser?.lastLogin;
  String? get ipAddress => _currentMaster?.ipAddress ?? _currentUser?.ipAddress;
  List<String> get exchangesAllowed {
    if (_currentMaster != null) {
      return _currentMaster!.exchangesAllowed;
    } else {
      return _currentUser!.exchangesAllowed.map((e) => e.exchangeName).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
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
                        onTap: () => Navigator.pop(
                            context, true), // Return true to trigger refresh
                        child: Icon(Icons.arrow_back, color: Colors.black),
                      ),
                      SizedBox(width: 12),
                      Text(
                        username,
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: () async {
                      if (_currentMaster != null) {
                        // Navigate to CreateMasterView with master data for editing
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CreateMasterView(master: _currentMaster),
                          ),
                        );

                        // Refresh data if update was successful
                        if (result == true && mounted) {
                          await _refreshData();
                        }
                      } else {
                        // Navigate to CreateUserView with user data for editing
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                CreateUserView(user: _currentUser),
                          ),
                        );

                        // Refresh data if update was successful
                        if (result == true && mounted) {
                          await _refreshData();
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: ShapeDecoration(
                        color: const Color(0xFF8E8E93),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text(
                            'Edit',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Credit/Balance Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(10),
              decoration: ShapeDecoration(
                color: const Color(0xFFE5E5EA),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Credit: ${credits.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  Text(
                    'Balance: ${balance.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Tab buttons
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 0
                              ? const Color(0xFF22547C)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                                width: 1, color: const Color(0xFF22547C)),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(8),
                              bottomLeft: Radius.circular(8),
                            ),
                          ),
                        ),
                        child: Text(
                          'Overview',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 0
                                ? Colors.white
                                : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 1
                              ? const Color(0xFF22547C)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                                width: 1, color: const Color(0xFF22547C)),
                          ),
                        ),
                        child: Text(
                          'Tradelist',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 1
                                ? Colors.white
                                : const Color(0xFF333333),
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedTabIndex = 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 11),
                        decoration: ShapeDecoration(
                          color: _selectedTabIndex == 2
                              ? const Color(0xFF22547C)
                              : Colors.white,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                                width: 1, color: const Color(0xFF22547C)),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(8),
                              bottomRight: Radius.circular(8),
                            ),
                          ),
                        ),
                        child: Text(
                          'Position',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _selectedTabIndex == 2
                                ? Colors.white
                                : Colors.black,
                            fontSize: 16,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 16),

            // Tab Content
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildOverviewTab()
                  : _selectedTabIndex == 1
                      ? _buildTradelistTab()
                      : _buildPositionTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // User Info Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                    'Created Date', DateFormatter.formatDateTime(createdAt),
                    showBorder: true),
                _buildInfoRow(
                    'Last Login', DateFormatter.formatDateTime(lastLogin),
                    showBorder: true),
                _buildInfoRow('IP Address', ipAddress ?? 'N/A',
                    showBorder: true),
                _buildInfoRow('Exchanges', exchangesAllowed.join(', '),
                    showBorder: false),
              ],
            ),
          ),

          SizedBox(height: 24),

          // CONTROL Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CONTROL',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Control Toggles
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildToggleRow('User Status', _activeStatus),
                SizedBox(height: 16),
                _buildToggleRow('Close Only', _closeOnly),
                SizedBox(height: 16),
                _buildToggleRow('BET', _bet),
                SizedBox(height: 16),
                _buildToggleRow('Margin Square Off', _marginSquare),
                SizedBox(height: 16),
                _buildToggleRow('Fresh Stop-Loss', _freshStoploss),
              ],
            ),
          ),

          SizedBox(height: 24),

          // CONTROL Section 2
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'CONTROL',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Settings List
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildSettingRow('Credit/Debit', Icons.account_balance_wallet,
                    showBorder: true),
                _buildSettingRow('Group Quantity Settings', Icons.settings,
                    showBorder: true),
                _buildSettingRow('Margin SquareOff Settings', Icons.settings,
                    showBorder: true),
                _buildSettingRow('Brk Settings', Icons.settings,
                    showBorder: true),
                _buildSettingRow('Intraday SquareOff', Icons.settings,
                    showBorder: true),
                _buildSettingRow('Trade Margin', Icons.settings,
                    showBorder: true),
                _buildSettingRow('Sharing Details', Icons.share,
                    showBorder: true),
                _buildSettingRow('Script Quantity Setting', Icons.settings,
                    showBorder: false),
              ],
            ),
          ),

          SizedBox(height: 24),

          // ACTION Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ACTION',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          SizedBox(height: 8),

          // Action List
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Column(
              children: [
                _buildSettingRow('Rejection Log', Icons.error_outline,
                    showBorder: true),
                _buildSettingRow('Generate PDF', Icons.picture_as_pdf,
                    showBorder: true),
                _buildSettingRow('Settlement Report', Icons.description,
                    showBorder: false),
              ],
            ),
          ),

          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTradelistTab() {
    return Column(
      children: [
        // Search bar (placeholder for now)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.search, size: 24, color: const Color(0xFF8E8E93)),
                  SizedBox(width: 10),
                  Text(
                    'Search trades',
                    style: TextStyle(
                      color: const Color(0xFF8E8E93),
                      fontSize: 16,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _fetchTrades,
                child: Icon(Icons.refresh,
                    size: 24, color: const Color(0xFF8E8E93)),
              ),
            ],
          ),
        ),

        SizedBox(height: 8),

        // Trade list
        Expanded(
          child: _isLoadingTrades
              ? Center(
                  child:
                      CircularProgressIndicator(color: const Color(0xFF22547C)),
                )
              : _tradesError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              size: 48, color: Colors.red),
                          SizedBox(height: 16),
                          Text(
                            _tradesError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.red, fontSize: 14),
                          ),
                          SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchTrades,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22547C),
                            ),
                            child: Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _trades.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long,
                                  size: 48, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'No trades found',
                                style:
                                    TextStyle(color: Colors.grey, fontSize: 16),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _fetchTrades,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _trades.length,
                            separatorBuilder: (context, index) =>
                                SizedBox(height: 8),
                            itemBuilder: (context, index) =>
                                _buildTradeCard(_trades[index]),
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildPositionTab() {
    if (_currentMaster == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Position data is only available for masters',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPosition,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            // Summary Card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: BorderSide(width: 1, color: const Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoadingPosition
                  ? Container(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(
                            color: const Color(0xFF22547C)),
                      ),
                    )
                  : _positionError != null
                      ? Container(
                          height: 200,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.error_outline,
                                    size: 48, color: Colors.red),
                                SizedBox(height: 16),
                                Text(
                                  _positionError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      color: Colors.red, fontSize: 14),
                                ),
                                SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _fetchPosition,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF22547C),
                                  ),
                                  child: Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: ShapeDecoration(
                                      shape: RoundedRectangleBorder(
                                        side: BorderSide(
                                            width: 1,
                                            color: const Color(0xFFD1D1D6)),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'REALISED P&L',
                                          style: TextStyle(
                                            color: const Color(0xFF8E8E93),
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          _position?.realisedPnl
                                                  .toStringAsFixed(2) ??
                                              '0.0',
                                          style: TextStyle(
                                            color:
                                                (_position?.realisedPnl ?? 0) >=
                                                        0
                                                    ? Colors.green
                                                    : Colors.red,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'M2M P&L',
                                          style: TextStyle(
                                            color: const Color(0xFF8E8E93),
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          _position?.m2mPnl
                                                  .toStringAsFixed(2) ??
                                              '0.0',
                                          style: TextStyle(
                                            color: (_position?.m2mPnl ?? 0) >= 0
                                                ? Colors.green
                                                : Colors.red,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: ShapeDecoration(
                                      shape: RoundedRectangleBorder(
                                        side: BorderSide(
                                            width: 1,
                                            color: const Color(0xFFD1D1D6)),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'CREDIT',
                                          style: TextStyle(
                                            color: const Color(0xFF8E8E93),
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          _position?.credit
                                                  .toStringAsFixed(2) ??
                                              '0.0',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'EQUITY',
                                          style: TextStyle(
                                            color: const Color(0xFF8E8E93),
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          _position?.equity
                                                  .toStringAsFixed(2) ??
                                              '0.0',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: ShapeDecoration(
                                      shape: RoundedRectangleBorder(
                                        side: BorderSide(
                                            width: 1,
                                            color: const Color(0xFFD1D1D6)),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'MARGIN USED',
                                          style: TextStyle(
                                            color: const Color(0xFF8E8E93),
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          _position?.marginUsed
                                                  .toStringAsFixed(2) ??
                                              '0.0',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'FREE MARGIN',
                                          style: TextStyle(
                                            color: const Color(0xFF8E8E93),
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                        Text(
                                          _position?.freeMargin
                                                  .toStringAsFixed(2) ??
                                              '0.0',
                                          style: TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontFamily: 'Inter',
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
            ),

            SizedBox(height: 16),

            // Last Updated Info
            if (_position != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.access_time,
                        size: 16, color: const Color(0xFF8E8E93)),
                    SizedBox(width: 8),
                    Text(
                      'Last updated: ${DateFormatter.formatDateTime(_position!.lastUpdated)}',
                      style: TextStyle(
                        color: const Color(0xFF8E8E93),
                        fontSize: 12,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),

            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildTradeCard(Trade trade) {
    final isSuccess = trade.status.toLowerCase() == 'success' ||
        trade.status.toLowerCase() == 'completed';
    final isBuy = trade.transactionType.toUpperCase() == 'BUY';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(Icons.person, size: 24, color: Colors.black),
              SizedBox(height: 4),
              Text(
                trade.userName?.toUpperCase() ?? 'USER',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${trade.exchange} ${trade.tradingSymbol}',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: ShapeDecoration(
                        color: isSuccess
                            ? const Color(0xFF34C759)
                            : const Color(0xFFFF3B30),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      child: Text(
                        trade.status.toUpperCase(),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            width: 1, color: const Color(0xFFD1D1D6))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${isBuy ? "BUY" : "SELL"}: ${trade.quantity} @ ₹${trade.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: isBuy
                              ? const Color(0xFF34C759)
                              : const Color(0xFFFF3B30),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.access_time,
                              size: 16, color: const Color(0xFF999999)),
                          SizedBox(width: 4),
                          Text(
                            DateFormatter.formatDateTime(trade.createdAt),
                            style: TextStyle(
                              color: const Color(0xFF999999),
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {required bool showBorder}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: showBorder
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
              ),
            )
          : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w400,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow(String label, bool isOn) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: const Color(0xFF2B2B2B),
            fontSize: 16,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w500,
          ),
        ),
        GestureDetector(
          onTap: () async {
            final newValue = !isOn;

            // Handle User Status separately (uses different API)
            if (label == 'User Status') {
              try {
                final apiService =
                    Provider.of<ApiService>(context, listen: false);
                final adminService = AdminService(apiService);

                if (_currentMaster != null) {
                  final response = await adminService.updateMasterStatus(
                    masterId: _currentMaster!.id,
                    activeStatus: newValue,
                  );

                  if (response.statusCode == 200) {
                    setState(() {
                      _activeStatus = newValue;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Status updated successfully')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update status')),
                    );
                  }
                } else {
                  // Update user status
                  final response = await adminService.updateUserDetails(
                    userId: _currentUser!.id,
                    activeStatus: newValue,
                  );

                  if (response.statusCode == 200) {
                    setState(() {
                      _activeStatus = newValue;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Status updated successfully')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to update status')),
                    );
                  }
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
              return;
            }

            // For Margin Square Off on users
            if (label == 'Margin Square Off' && _currentUser != null) {
              try {
                final apiService =
                    Provider.of<ApiService>(context, listen: false);
                final adminService = AdminService(apiService);

                final response = await adminService.updateUserDetails(
                  userId: _currentUser!.id,
                  marginSquareOff: newValue,
                );

                if (response.statusCode == 200) {
                  setState(() {
                    _marginSquare = newValue;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content:
                            Text('Margin Square Off updated successfully')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Failed to update Margin Square Off')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
              return;
            }

            // For Close Only, BET, Fresh Stop-Loss on users
            if (_currentUser != null &&
                (label == 'Close Only' ||
                    label == 'BET' ||
                    label == 'Fresh Stop-Loss')) {
              try {
                final apiService =
                    Provider.of<ApiService>(context, listen: false);
                final adminService = AdminService(apiService);

                String fieldName = '';

                switch (label) {
                  case 'Close Only':
                    fieldName = 'Close Only';
                    break;
                  case 'BET':
                    fieldName = 'BET';
                    break;
                  case 'Fresh Stop-Loss':
                    fieldName = 'Fresh Stop-Loss';
                    break;
                }

                final response = await adminService.updateUserDetails(
                  userId: _currentUser!.id,
                  closeOnly: label == 'Close Only' ? newValue : null,
                  bet: label == 'BET' ? newValue : null,
                  freshStoploss: label == 'Fresh Stop-Loss' ? newValue : null,
                );

                if (response.statusCode == 200) {
                  setState(() {
                    switch (label) {
                      case 'Close Only':
                        _closeOnly = newValue;
                        break;
                      case 'BET':
                        _bet = newValue;
                        break;
                      case 'Fresh Stop-Loss':
                        _freshStoploss = newValue;
                        break;
                    }
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$fieldName updated successfully')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to update $fieldName')),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
              return;
            }

            // For other user permissions (not applicable)
            if (_currentUser != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('This permission is not available for users')),
              );
              return;
            }

            // For master permissions
            if (_currentMaster == null) return;

            final currentPermissions = _currentMaster!.permissions ??
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

            MasterPermissions updatedPermissions;

            switch (label) {
              case 'Close Only':
                updatedPermissions = MasterPermissions(
                  accountSummary: currentPermissions.accountSummary,
                  pnlSummary: currentPermissions.pnlSummary,
                  clientSummary: currentPermissions.clientSummary,
                  settlementReport: currentPermissions.settlementReport,
                  generatePdf: currentPermissions.generatePdf,
                  weeklyAdmin: currentPermissions.weeklyAdmin,
                  intradayHistory: currentPermissions.intradayHistory,
                  userwiseOpenPosition: currentPermissions.userwiseOpenPosition,
                  scriptQuantity: currentPermissions.scriptQuantity,
                  deletedTrade: currentPermissions.deletedTrade,
                  tradeAccount: currentPermissions.tradeAccount,
                  closeOnly: newValue,
                  bet: _bet,
                  marginSquare: _marginSquare,
                  freshStoploss: _freshStoploss,
                );
                break;
              case 'BET':
                updatedPermissions = MasterPermissions(
                  accountSummary: currentPermissions.accountSummary,
                  pnlSummary: currentPermissions.pnlSummary,
                  clientSummary: currentPermissions.clientSummary,
                  settlementReport: currentPermissions.settlementReport,
                  generatePdf: currentPermissions.generatePdf,
                  weeklyAdmin: currentPermissions.weeklyAdmin,
                  intradayHistory: currentPermissions.intradayHistory,
                  userwiseOpenPosition: currentPermissions.userwiseOpenPosition,
                  scriptQuantity: currentPermissions.scriptQuantity,
                  deletedTrade: currentPermissions.deletedTrade,
                  tradeAccount: currentPermissions.tradeAccount,
                  closeOnly: _closeOnly,
                  bet: newValue,
                  marginSquare: _marginSquare,
                  freshStoploss: _freshStoploss,
                );
                break;
              case 'Margin Square Off':
                updatedPermissions = MasterPermissions(
                  accountSummary: currentPermissions.accountSummary,
                  pnlSummary: currentPermissions.pnlSummary,
                  clientSummary: currentPermissions.clientSummary,
                  settlementReport: currentPermissions.settlementReport,
                  generatePdf: currentPermissions.generatePdf,
                  weeklyAdmin: currentPermissions.weeklyAdmin,
                  intradayHistory: currentPermissions.intradayHistory,
                  userwiseOpenPosition: currentPermissions.userwiseOpenPosition,
                  scriptQuantity: currentPermissions.scriptQuantity,
                  deletedTrade: currentPermissions.deletedTrade,
                  tradeAccount: currentPermissions.tradeAccount,
                  closeOnly: _closeOnly,
                  bet: _bet,
                  marginSquare: newValue,
                  freshStoploss: _freshStoploss,
                );
                break;
              case 'Fresh Stop-Loss':
                updatedPermissions = MasterPermissions(
                  accountSummary: currentPermissions.accountSummary,
                  pnlSummary: currentPermissions.pnlSummary,
                  clientSummary: currentPermissions.clientSummary,
                  settlementReport: currentPermissions.settlementReport,
                  generatePdf: currentPermissions.generatePdf,
                  weeklyAdmin: currentPermissions.weeklyAdmin,
                  intradayHistory: currentPermissions.intradayHistory,
                  userwiseOpenPosition: currentPermissions.userwiseOpenPosition,
                  scriptQuantity: currentPermissions.scriptQuantity,
                  deletedTrade: currentPermissions.deletedTrade,
                  tradeAccount: currentPermissions.tradeAccount,
                  closeOnly: _closeOnly,
                  bet: _bet,
                  marginSquare: _marginSquare,
                  freshStoploss: newValue,
                );
                break;
              default:
                return;
            }

            // Call API to update permissions
            try {
              final apiService =
                  Provider.of<ApiService>(context, listen: false);
              final adminService = AdminService(apiService);

              final response = await adminService.updateMasterPermissions(
                masterId: _currentMaster!.id,
                permissions: updatedPermissions,
              );

              if (response.statusCode == 200) {
                setState(() {
                  switch (label) {
                    case 'Close Only':
                      _closeOnly = newValue;
                      break;
                    case 'BET':
                      _bet = newValue;
                      break;
                    case 'Margin Square Off':
                      _marginSquare = newValue;
                      break;
                    case 'Fresh Stop-Loss':
                      _freshStoploss = newValue;
                      break;
                  }
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Permission updated successfully')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to update permission')),
                );
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          },
          child: Container(
            width: 40,
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: ShapeDecoration(
              color: isOn ? const Color(0xFF22547C) : const Color(0xFF8E8E93),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.50)),
            ),
            child: Align(
              alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 23,
                height: 23,
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: OvalBorder(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingRow(String label, IconData icon,
      {required bool showBorder}) {
    return GestureDetector(
      onTap: () async {
        if (label == 'Credit/Debit') {
          final result = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => CreditDebitBottomSheet(
              master: _currentMaster,
              user: _currentUser,
            ),
          );

          // If credit/debit was successful, refresh the data
          if (result == true && mounted) {
            await _refreshData();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Transaction successful')),
            );
          }
        } else if (label == 'Group Quantity Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const GroupQuantityView()),
          );
        } else if (label == 'Margin SquareOff Settings') {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => MarginSquareoffBottomSheet(
              master: _currentMaster,
              user: _currentUser,
            ),
          );
        } else if (label == 'Brk Settings') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const BrokerageSettingsView()),
          );
        } else if (label == 'Intraday SquareOff') {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => IntradaySquareoffBottomSheet(
              master: _currentMaster,
              user: _currentUser,
            ),
          );
        } else if (label == 'Trade Margin') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const TradeMarginSettingsView()),
          );
        } else if (label == 'Script Quantity Setting') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const ScriptQuantitySettingsView()),
          );
        } else if (label == 'Sharing Details') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SharingDetailsView()),
          );
        } else if (label == 'Rejection Log') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const RejectionLogHistoryView()),
          );
        } else if (label == 'Settlement Report') {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const SettlementReportView()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: showBorder
            ? BoxDecoration(
                border: Border(
                  bottom: BorderSide(width: 1, color: const Color(0xFFC7C7CC)),
                ),
              )
            : null,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: Colors.black),
                SizedBox(width: 16),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            Icon(Icons.chevron_right, size: 24, color: Colors.black),
          ],
        ),
      ),
    );
  }
}
