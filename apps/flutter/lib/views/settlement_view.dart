import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/live_price_service.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';

class SettlementView extends StatefulWidget {
  const SettlementView({super.key});

  @override
  State<SettlementView> createState() => _SettlementViewState();
}

class _SettlementViewState extends State<SettlementView> {
  final LivePriceService _livePriceService = LivePriceService();
  bool _isLoading = false;
  Map<String, dynamic>? _status;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _setupWebSocket();
    // Poll every 3 seconds as backup
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_status?['running'] == true || _isLoading) _fetchStatus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _livePriceService.onSettlementProgress = null;
    _livePriceService.disconnect();
    super.dispose();
  }

  void _setupWebSocket() {
    _livePriceService.onSettlementProgress = (data) {
      if (mounted) setState(() => _status = data);
    };

    _livePriceService.onConnectionChanged = (connected) {
      if (connected) _authenticateWebSocket();
    };

    _livePriceService.connect();
  }

  Future<void> _authenticateWebSocket() async {
    try {
      final token = await SecureStorageService().getToken();
      if (token != null) {
        // Backend derives identity from the verified token; no client-claimed id.
        _livePriceService.authenticate(token);
      }
    } catch (_) {}
  }

  Future<void> _fetchStatus() async {
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl)
          .get('/admin/settlement/status', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && mounted) {
          setState(() => _status = body['data']);
        }
      }
    } catch (_) {}
  }

  Future<void> _startSettlement() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start Settlement?',
            style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: kFontSizeViewTitle,
                fontWeight: kFontWeightSemiBold)),
        content: const Text(
          'This will close all open positions at settlement price and re-open them for the new week. This action cannot be undone.',
          style: TextStyle(
              fontFamily: kFontFamily,
              fontSize: kFontSizeBody,
              fontWeight: kFontWeightRegular),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Start', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl)
          .post('/admin/settlement/start', {}, token: token);
      final body = jsonDecode(res.body);
      if (body['success'] == true) {
        setState(() => _status = body['data']);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(body['message'] ?? 'Failed'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _phaseLabel(String? phase) {
    switch (phase) {
      case 'fetching_prices':
        return 'Fetching close prices...';
      case 'cancelling_pending':
        return 'Cancelling pending orders...';
      case 'processing':
        return 'Settling positions...';
      case 'done':
        return 'Settlement complete';
      case 'error':
        return 'Settlement failed';
      default:
        return 'Idle';
    }
  }

  @override
  Widget build(BuildContext context) {
    final phase = _status?['phase'] ?? 'idle';
    final isRunning = _status?['running'] == true;
    final total = _status?['total'] ?? 0;
    final processed = _status?['processed'] ?? 0;
    final pct = _status?['percentage'] ?? 0;
    final currentInst = _status?['currentInstrument'] ?? '';
    final isDone = phase == 'done';
    final isError = phase == 'error';
    final profile = Provider.of<UserProfileProvider>(context, listen: false);
    final canTrigger = profile.isSuperAdmin ||
        (profile.adminPermissions.contains('SETTLEMENT_TRIGGER') &&
            !profile.isWatchOnlyAdmin);

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
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
                                blurRadius: 4)
                          ]),
                      child: const Icon(Icons.arrow_back,
                          color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text('Settlement',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: kFontSizeViewTitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold)),
                ],
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 24),

                    // Status card
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isDone
                                    ? Icons.check_circle
                                    : isError
                                        ? Icons.error
                                        : isRunning
                                            ? Icons.sync
                                            : Icons.schedule,
                                color: isDone
                                    ? const Color(0xFF10B981)
                                    : isError
                                        ? const Color(0xFFEF4444)
                                        : isRunning
                                            ? kBrandPrimary
                                            : const Color(0xFF94A3B8),
                                size: kIconSizeLarge,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _phaseLabel(phase),
                                  style: TextStyle(
                                    color: isDone
                                        ? const Color(0xFF10B981)
                                        : isError
                                            ? const Color(0xFFEF4444)
                                            : Colors.black,
                                    fontSize: kFontSizeSectionHeader,
                                    fontFamily: kFontFamily,
                                    fontWeight: kFontWeightSemiBold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isRunning || isDone) ...[
                            const SizedBox(height: 16),
                            // Show phase-specific info during fetching (before positions are counted)
                            if (phase == 'fetching_prices') ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: kBrandPrimary),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'Loading settlement prices from database...',
                                        style: TextStyle(
                                            color: Color(0xFF64748B),
                                            fontSize: kFontSizeCaption,
                                            fontFamily: kFontFamily,
                                            fontWeight: kFontWeightMedium,
                                            height: 1.4),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: total > 0 ? processed / total : 0,
                                  minHeight: 8,
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      isDone
                                          ? const Color(0xFF10B981)
                                          : kBrandPrimary),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('$processed / $total positions',
                                      style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: kFontSizeCaption,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightRegular)),
                                  Text('$pct%',
                                      style: const TextStyle(
                                          color: kBrandPrimary,
                                          fontSize: kFontSizeCaption,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightSemiBold)),
                                ],
                              ),
                              if (currentInst.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(currentInst,
                                    style: const TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: kFontSizeCaption,
                                        fontFamily: kFontFamily,
                                        fontWeight: kFontWeightRegular),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ],
                            ],
                          ],
                          if (isDone) ...[
                            const SizedBox(height: 16),
                            _statRow('Positions closed',
                                '${_status?['closedTrades'] ?? 0}'),
                            _statRow('Positions re-opened',
                                '${_status?['reopenedTrades'] ?? 0}'),
                            _statRow('Users affected',
                                '${_status?['usersAffected'] ?? 0}'),
                            _statRow('Prices fetched',
                                '${_status?['pricesFetched'] ?? 0}'),
                            _statRow('Active trades in DB',
                                '${_status?['activeTradesInDb'] ?? '?'}'),
                          ],
                          if (isError) ...[
                            const SizedBox(height: 12),
                            Text(_status?['error'] ?? 'Unknown error',
                                style: const TextStyle(
                                    color: Color(0xFFEF4444),
                                    fontSize: kFontSizeCaption,
                                    fontFamily: kFontFamily)),
                          ],
                        ],
                      ),
                    ),

                    const Spacer(),

                    if (!isRunning && !canTrigger)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Text(
                          profile.isWatchOnlyAdmin
                              ? 'Watch-only admins cannot make changes.'
                              : 'Missing the "Trigger settlement" permission.',
                          style: const TextStyle(
                              color: Color(0xFFB45309),
                              fontSize: kFontSizeCaption,
                              fontFamily: kFontFamily),
                        ),
                      ),
                    // Start button
                    if (!isRunning)
                      Padding(
                        padding: EdgeInsets.only(
                            bottom:
                                24 + MediaQuery.of(context).viewPadding.bottom),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: (_isLoading || !canTrigger)
                                ? null
                                : _startSettlement,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandPrimary,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : Text(
                                    isDone ? 'Run Again' : 'Start Settlement',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: kFontSizeButtonText,
                                        fontFamily: kFontFamily,
                                        fontWeight: kFontWeightSemiBold)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: kFontSizeBody,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightRegular)),
          Text(value,
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: kFontSizeBody,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold)),
        ],
      ),
    );
  }
}
