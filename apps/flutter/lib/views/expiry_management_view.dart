import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../utils/contants.dart';

/// Manual expiry management — two deliberately separate controls:
///
///  1. Expiry toggle: flips every instrument sharing one exact expiry date
///     within a segment on/off for trading, in one call.
///  2. MCX square-off: closes every open MCX position system-wide, in
///     batches — its own manual action, not tied to the toggle above.
///
/// No automatic timing anywhere — both actions only ever happen when an
/// admin taps them here.
class ExpiryManagementView extends StatefulWidget {
  const ExpiryManagementView({super.key});

  @override
  State<ExpiryManagementView> createState() => _ExpiryManagementViewState();
}

class _ExpiryManagementViewState extends State<ExpiryManagementView> {
  static const _segments = ['NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT', 'GLOBAL'];
  String _selectedSegment = 'NFO-FUT';
  List<Map<String, dynamic>> _rows = [];
  bool _isLoading = false;
  String? _loadError;

  Map<String, dynamic>? _run;
  Timer? _pollTimer;
  bool _startingSquareOff = false;

  late final AdminService _adminService;

  @override
  void initState() {
    super.initState();
    _adminService = AdminService(Provider.of<ApiService>(context, listen: false));
    _fetchExpiries();
    _fetchLatestRun();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchExpiries() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final res = await _adminService.getExpiries(_selectedSegment);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _rows = List<Map<String, dynamic>>.from(body['data'] ?? []);
          });
        } else {
          setState(() => _loadError = body['message'] ?? 'Failed to load expiries');
        }
      } else {
        setState(() => _loadError = 'Failed to load expiries');
      }
    } catch (e) {
      log('⚠️ Error fetching expiries: $e');
      setState(() => _loadError = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchLatestRun() async {
    try {
      final res = await _adminService.getMcxSquareOffLatest();
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          setState(() => _run = Map<String, dynamic>.from(body['data']));
          if (_run?['status'] == 'running') _startPolling();
        }
      }
    } catch (e) {
      log('⚠️ Error fetching latest square-off run: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final runId = _run?['_id'];
      if (runId == null) return;
      try {
        final res = await _adminService.getMcxSquareOffStatus(runId.toString());
        if (res.statusCode == 200) {
          final body = jsonDecode(res.body);
          if (body['success'] == true) {
            setState(() => _run = Map<String, dynamic>.from(body['data']));
            if (_run?['status'] != 'running') _pollTimer?.cancel();
          }
        }
      } catch (_) {
        // transient — next tick retries
      }
    });
  }

  Future<void> _confirmToggle(Map<String, dynamic> row) async {
    final bool nextEnabled = row['enabled'] != true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(nextEnabled ? 'Open expiry for trading?' : 'Close expiry for trading?'),
        content: Text(
          'This will ${nextEnabled ? 'open' : 'close'} ${row['count']} $_selectedSegment '
          'instrument(s) expiring ${_formatDate(row['expiry'])} '
          '${nextEnabled ? 'for new trades.' : 'to new trades. Existing open positions are not affected.'}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await _adminService.toggleExpiry(
        segment: _selectedSegment,
        expiry: row['expiry'].toString(),
        enabled: nextEnabled,
        reason: nextEnabled ? null : 'Expiry closed for trading (admin)',
      );
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        _fetchExpiries();
      } else {
        _showSnack(body['message'] ?? 'Failed to update expiry');
      }
    } catch (e) {
      _showSnack('Error: $e');
    }
  }

  Future<void> _confirmSquareOff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Square off all MCX positions?'),
        content: const Text(
          'This will immediately close every open MCX position across every client at current market price, '
          'in batches. This cannot be undone. It runs in the background — progress shows on this page.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _startingSquareOff = true);
    try {
      final res = await _adminService.startMcxSquareOff();
      final body = jsonDecode(res.body);
      if (res.statusCode == 200 && body['success'] == true) {
        setState(() {
          _run = {
            '_id': body['data']['runId'],
            'segment': 'MCX',
            'status': 'running',
            'total_users': body['data']['totalUsers'],
            'processed_users': 0,
            'positions_closed': 0,
            'failed_users': [],
          };
        });
        _startPolling();
      } else {
        _showSnack(body['message'] ?? 'Failed to start square-off');
      }
    } catch (e) {
      _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _startingSquareOff = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFFEF4444)),
    );
  }

  String _formatDate(dynamic iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso.toString());
    if (d == null) return iso.toString();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _run?['status'] == 'running';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
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
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Expiry Management',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: kFontSizeViewTitle,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  const Text(
                    'Expiry toggle',
                    style: TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Manually open/close a whole expiry batch for trading',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeCaption, fontFamily: kFontFamily),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _segments.map((s) {
                      final selected = s == _selectedSegment;
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedSegment = s);
                          _fetchExpiries();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? kBrandPrimary.withValues(alpha: 0.1) : Colors.white,
                            border: Border.all(color: selected ? kBrandPrimary : const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            s,
                            style: TextStyle(
                              color: selected ? kBrandPrimary : const Color(0xFF64748B),
                              fontSize: kFontSizeCaption,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightMedium,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5)),
                    )
                  else if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(_loadError!, style: const TextStyle(color: Color(0xFFEF4444), fontFamily: kFontFamily)),
                    )
                  else if (_rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('No upcoming expiries found.', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: kFontFamily)),
                    )
                  else
                    ..._rows.map((row) => _expiryRow(row)),

                  const SizedBox(height: 28),
                  const Divider(color: Color(0xFFE2E8F0)),
                  const SizedBox(height: 16),
                  const Text(
                    'MCX square-off',
                    style: TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Close every open MCX position system-wide, in batches. Separate from the toggle above — trigger each independently.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeCaption, fontFamily: kFontFamily),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: (!isRunning && !_startingSquareOff) ? _confirmSquareOff : null,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: isRunning ? 0.05 : 0.1),
                        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: isRunning ? 0.2 : 0.6)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        isRunning ? 'Square-off in progress…' : 'Square off all MCX positions',
                        style: TextStyle(
                          color: const Color(0xFFEF4444).withValues(alpha: isRunning ? 0.6 : 1),
                          fontSize: kFontSizeBody,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ),
                  ),
                  if (_run != null) _runStatusCard(_run!),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expiryRow(Map<String, dynamic> row) {
    final enabled = row['enabled'] == true;
    final mixed = row['mixed'] == true;
    final rawNames = List<String>.from(row['rawNames'] ?? const []);
    final rawNamesLabel = rawNames.length > 4
        ? '${rawNames.take(4).join(', ')} +${rawNames.length - 4} more'
        : (rawNames.isEmpty ? '—' : rawNames.join(', '));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatDate(row['expiry']),
                    style: const TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                const SizedBox(height: 2),
                Text(rawNamesLabel,
                    style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
                const SizedBox(height: 2),
                Text('${row['count']} instrument(s)',
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              mixed ? 'Mixed' : (enabled ? 'Open' : 'Closed'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mixed ? const Color(0xFFF59E0B) : (enabled ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                fontSize: kFontSizeCaption,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightMedium,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _confirmToggle(row),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    enabled ? 'Close' : 'Open',
                    style: const TextStyle(color: Color(0xFF475569), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _runStatusCard(Map<String, dynamic> run) {
    final status = run['status'] as String? ?? 'running';
    final failed = List<dynamic>.from(run['failed_users'] ?? []);
    Color statusColor = const Color(0xFFF59E0B);
    if (status == 'completed') statusColor = const Color(0xFF10B981);
    if (status == 'failed') statusColor = const Color(0xFFEF4444);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Status: $status',
                  style: TextStyle(color: statusColor, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${run['processed_users'] ?? 0} / ${run['total_users'] ?? 0} client(s) processed — ${run['positions_closed'] ?? 0} position(s) closed',
            style: const TextStyle(color: Colors.black, fontSize: kFontSizeCaption, fontFamily: kFontFamily),
          ),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${failed.length} client(s) failed to close — check server logs',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: kFontSizeCaption, fontFamily: kFontFamily),
            ),
          ],
        ],
      ),
    );
  }
}
