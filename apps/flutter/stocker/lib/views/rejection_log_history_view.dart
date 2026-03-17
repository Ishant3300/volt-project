import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class RejectionLogHistoryView extends StatefulWidget {
  const RejectionLogHistoryView({super.key});

  @override
  State<RejectionLogHistoryView> createState() =>
      _RejectionLogHistoryViewState();
}

class _RejectionLogHistoryViewState extends State<RejectionLogHistoryView> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _page = 1;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLogs({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _logs = [];
    }
    if (!_hasMore || (_isLoading && !refresh && _logs.isNotEmpty)) return;
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final api = ApiService(backendUrl);
      String url = '/trade/rejection-log?page=$_page&limit=30';
      if (_searchQuery.isNotEmpty) url += '&search=$_searchQuery';
      final res = await api.get(url, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List list = body['data'] ?? [];
        final int total = body['total'] ?? 0;
        setState(() {
          _logs.addAll(list.cast<Map<String, dynamic>>());
          _hasMore = _logs.length < total;
          _page++;
        });
      }
    } catch (e) {
      debugPrint('Error fetching rejection log: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _onSearch() {
    _searchQuery = _searchController.text.trim();
    _fetchLogs(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    final isUser =
        Provider.of<UserProfileProvider>(context, listen: false).isUser;

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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text('Rejection Log',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),

            // Search bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
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
              child: TextField(
                controller: _searchController,
                onSubmitted: (_) => _onSearch(),
                style: const TextStyle(
                    fontSize: 14,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: 'Search by script name...',
                  hintStyle: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 14,
                      fontFamily: 'Inter'),
                  prefixIcon: const Icon(Icons.search,
                      color: Color(0xFF94A3B8), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _fetchLogs(refresh: true);
                          },
                          child: const Icon(Icons.close,
                              color: Color(0xFF94A3B8), size: 18),
                        )
                      : null,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Count
            if (!_isLoading || _logs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${_logs.length} entries',
                    style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 11,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            const SizedBox(height: 8),

            // List
            Expanded(
              child: _isLoading && _logs.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF3F45C7), strokeWidth: 2.5))
                  : _logs.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: () => _fetchLogs(refresh: true),
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (scroll) {
                              if (scroll.metrics.pixels >=
                                      scroll.metrics.maxScrollExtent - 100 &&
                                  _hasMore &&
                                  !_isLoading) {
                                _fetchLogs();
                              }
                              return false;
                            },
                            child: ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _logs.length + (_hasMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _logs.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(
                                        child: CircularProgressIndicator(
                                            color: Color(0xFF3F45C7),
                                            strokeWidth: 2)),
                                  );
                                }
                                return _buildLogCard(_logs[index], isUser);
                              },
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            child: const Icon(Icons.check_circle_outline,
                size: 28, color: Color(0xFF10B981)),
          ),
          const SizedBox(height: 16),
          const Text('No rejected trades',
              style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 15,
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log, bool isUser) {
    final String symbol = log['tradingsymbol'] ?? '';
    final String exchange = log['exchange'] ?? '';
    final String txnType = log['transaction_type'] ?? '';
    final String orderType = log['order_type'] ?? '';
    final double qty = (log['quantity'] as num?)?.toDouble() ?? 0;
    final double price = (log['price'] as num?)?.toDouble() ?? 0;
    final String status = log['status'] ?? '';
    final String remarks = log['remarks'] ?? '';
    final String username = log['username'] ?? '';
    final String dateStr = log['updated_at'] ?? log['created_at'] ?? '';

    final bool isBuy = txnType == 'BUY';
    final Color sideColor =
        isBuy ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    if (status == 'deleted') {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'DELETED';
      statusIcon = Icons.delete_outline;
    } else if (status == 'cancelled') {
      statusColor = const Color(0xFFB45309);
      statusLabel = 'CANCELLED';
      statusIcon = Icons.cancel_outlined;
    } else {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'REJECTED';
      statusIcon = Icons.error_outline;
    }

    String formattedDate = '';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      formattedDate = DateFormat('dd MMM yyyy · hh:mm a').format(dt);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Symbol + BUY/SELL badge + Status badge
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(symbol,
                          style: const TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8)),
                      child: Text(txnType,
                          style: TextStyle(
                              color: sideColor,
                              fontSize: 10,
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3)),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Order details
          Row(
            children: [
              Text('$orderType · ${qty.toStringAsFixed(0)} Qty · ₹${price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500)),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Text('·',
                      style: TextStyle(
                          fontSize: 10, color: Color(0xFFCBD5E1)))),
              Text(exchange,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 4),

          // Row 3: Date + username
          Row(
            children: [
              Text(formattedDate,
                  style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 10,
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500)),
              if (!isUser && username.isNotEmpty) ...[
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Text('·',
                        style: TextStyle(
                            fontSize: 10, color: Color(0xFFCBD5E1)))),
                const Icon(Icons.person_outline,
                    size: 11, color: Color(0xFFCBD5E1)),
                const SizedBox(width: 3),
                Text(username,
                    style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 10,
                        fontFamily: 'Inter',
                        fontWeight: FontWeight.w500)),
              ],
            ],
          ),

          // Remarks
          if (remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: statusColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(remarks,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontFamily: 'Inter',
                            fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
