import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animated_flip_counter/animated_flip_counter.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/views/trade_card_view.dart';
import 'package:stocker/pages/master_instrument_users_page.dart';

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

class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  bool _isSelectionMode = false;
  final Set<String> _selectedPositionTokens = {};

  // Master-specific state
  bool _masterLoading = false;
  List<Map<String, dynamic>> _masterPositions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProfile = Provider.of<UserProfileProvider>(context, listen: false);
      if (userProfile.isMaster) {
        _fetchMasterPositions();
      }
    });
  }

  Future<void> _fetchMasterPositions() async {
    setState(() => _masterLoading = true);
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final apiService = ApiService(backendUrl);
      final res = await apiService.get('/master/positions/aggregated', token: token);
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
    if (userProfile.isMaster) {
      return _buildMasterView();
    }
    return _buildUserView();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _fetchMasterPositions,
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
                        'MASTER POSITIONS',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontSize: 12,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_masterPositions.length} instrument${_masterPositions.length != 1 ? "s" : ""}',
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 24,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Net Qty: ${totalNetQty > 0 ? "+" : ""}$totalNetQty',
                        style: TextStyle(
                          color: totalNetQty >= 0
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                        ),
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
                '${isLong ? "+" : ""}$netQty QTY',
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
            const Icon(Icons.chevron_right,
                size: 20, color: Color(0xFF94A3B8)),
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
                              Builder(
                                builder: (context) {
                                  final fmt = _getShortForm(posPnl);
                                  return AnimatedFlipCounter(
                                    value: fmt.value,
                                    fractionDigits: 2,
                                    suffix: fmt.suffix,
                                    textStyle: TextStyle(
                                      color: isPosPnlPositive
                                          ? const Color(0xFF22C55E)
                                          : const Color(0xFFEF4444),
                                      fontSize: 30,
                                      fontFamily: 'Inter',
                                      fontWeight: FontWeight.w700,
                                    ),
                                  );
                                },
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

                  // P&L Grid Card
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
                        _buildGridRow('Realised P&L', realised, 'M2M P&L', m2m),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        _buildGridRow('Credit', credit, 'Equity', equity),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        _buildGridRow('Margin Used', marginUsed, 'Free Margin',
                            freeMargin),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Search bar
                  Container(
                    width: double.infinity,
                    height: 48,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(
                            width: 1, color: Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.search,
                                size: 24, color: Color(0xFF64748B)),
                            SizedBox(width: 10),
                            Text(
                              'Search & Add',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 14,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        Icon(Icons.mic, size: 24, color: Color(0xFF64748B)),
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
                                      provider.positions.length) {
                                    _selectedPositionTokens.clear();
                                  } else {
                                    _selectedPositionTokens.clear();
                                    _selectedPositionTokens.addAll(provider
                                        .positions
                                        .map((p) => p.instrumentToken));
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF22547C).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _selectedPositionTokens.length ==
                                          provider.positions.length
                                      ? 'Deselect All'
                                      : 'Select All',
                                  style: const TextStyle(
                                    color: Color(0xFF22547C),
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
                                  : () =>
                                      _squareOffSelected(provider.positions),
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
                      ] else if (provider.positions.isNotEmpty)
                        const SizedBox.shrink()
                      else
                        const SizedBox.shrink(),
                      if (!_isSelectionMode && provider.positions.isNotEmpty)
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
                                    size: 14, color: Color(0xFF22547C)),
                                SizedBox(width: 4),
                                Text(
                                  'Square Off',
                                  style: TextStyle(
                                    color: Color(0xFF22547C),
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
                        if (provider.positions.isEmpty)
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
                          ...provider.positions.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final pos = entry.value;
                            final isBuy = pos.netQty > 0;
                            final isNegative = pos.floating < 0;
                            return Column(
                              children: [
                                _buildOrderItem(
                                  context,
                                  pos,
                                  pos.tradingsymbol,
                                  pos.exchange,
                                  '${isBuy ? "BUY" : "SELL"}: ${pos.netQty.abs()} QTY',
                                  isBuy ? pos.avgBuyPrice : pos.avgSellPrice,
                                  pos.ltp,
                                  pos.floating,
                                  isNegative,
                                ),
                                if (idx != provider.positions.length - 1)
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

  Widget _buildGridRow(
      String label1, double value1, String label2, double value2) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
              child: _buildGridItem(label1, value1, showRightBorder: true)),
          Expanded(child: _buildGridItem(label2, value2)),
        ],
      ),
    );
  }

  Widget _buildGridItem(String label, double value,
      {bool showRightBorder = false}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: showRightBorder
            ? const Border(
                right: BorderSide(width: 1, color: Color(0xFFE2E8F0)))
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontFamily: 'Inter',
              fontWeight: FontWeight.w500,
            ),
          ),
          Builder(
            builder: (context) {
              final fmt = _getShortForm(value);
              return AnimatedFlipCounter(
                value: fmt.value,
                fractionDigits: 2,
                suffix: fmt.suffix,
                textStyle: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 14,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600,
                ),
              );
            },
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
        lastPrice: position.ltp > 0
            ? position.ltp
            : (isLong ? position.avgBuyPrice : position.avgSellPrice),
        strike: 0,
        tickSize: 0.05,
        lotSize: 1,
        instrumentType: '',
        segment: '',
        exchange: position.exchange,
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
                          fontSize: 16,
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
                          fontSize: 14,
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
                fontSize: 16,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
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
              'price': 0, // Market order
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
