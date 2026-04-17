import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'send_message_view.dart';
import 'manage_reports_view.dart';
import 'trade_margin_settings_view.dart';
import 'brokerage_settings_view.dart';
import 'group_quantity_view.dart';
import 'script_quantity_settings_view.dart';
import 'fresh_stoploss_limit_view.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class AdminSettingsView extends StatefulWidget {
  const AdminSettingsView({super.key});

  @override
  State<AdminSettingsView> createState() => _AdminSettingsViewState();
}

class _AdminSettingsViewState extends State<AdminSettingsView> {
  bool _totpEnabled = false;
  bool _totpConfigured = false;
  bool _totpLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTotpStatus();
  }

  Future<void> _fetchTotpStatus() async {
    try {
      final token = await SecureStorageService().getToken();
      final apiService = ApiService(backendUrl);
      final res = await apiService.get('/admin/totp/status', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            _totpEnabled = body['data']['enabled'] ?? false;
            _totpConfigured = body['data']['configured'] ?? false;
            _totpLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      log('Error fetching TOTP status: $e');
    }
    if (mounted) setState(() => _totpLoading = false);
  }

  Future<void> _handleTotpToggle(bool value) async {
    if (value) {
      // Enable TOTP — generate QR and show setup
      await _showTotpSetup();
    } else {
      // Disable TOTP
      final confirmed = await _showConfirmDialog(
        'Disable Two-Factor Auth?',
        'This will remove your TOTP configuration. You can re-enable it later.',
      );
      if (confirmed == true) {
        try {
          final token = await SecureStorageService().getToken();
          final apiService = ApiService(backendUrl);
          await apiService.post('/admin/totp/toggle', {'enabled': false}, token: token);
          setState(() {
            _totpEnabled = false;
            _totpConfigured = false;
          });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
            );
          }
        }
      }
    }
  }

  Future<void> _showTotpSetup() async {
    try {
      final token = await SecureStorageService().getToken();
      final apiService = ApiService(backendUrl);
      final res = await apiService.post('/admin/totp/generate', {}, token: token);
      if (res.statusCode != 200) {
        throw Exception('Failed to generate TOTP');
      }
      final body = jsonDecode(res.body);
      final qrDataUrl = body['data']['qr_data_url'] as String;
      final secret = body['data']['secret'] as String;

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _TotpSetupSheet(
          qrDataUrl: qrDataUrl,
          secret: secret,
          onVerified: () {
            setState(() {
              _totpEnabled = true;
              _totpConfigured = true;
            });
          },
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleTotpReset() async {
    final confirmed = await _showConfirmDialog(
      'Reset TOTP?',
      'Your current authenticator configuration will be cleared. You will need to scan a new QR code.',
    );
    if (confirmed == true) {
      try {
        final token = await SecureStorageService().getToken();
        final apiService = ApiService(backendUrl);
        await apiService.post('/admin/totp/reset', {}, token: token);
        setState(() {
          _totpConfigured = false;
          _totpEnabled = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('TOTP reset. Re-enable to configure a new one.'), backgroundColor: Color(0xFF10B981)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<bool?> _showConfirmDialog(String title, String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: const TextStyle(fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBody, fontFamily: 'Inter'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Text('Confirm', style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                        child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Admin Settings', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                  ],
                ),
              ),

              // Security section
              _sectionLabel('SECURITY'),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    // TOTP toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      child: Row(
                        children: [
                          Container(
                            width: kMenuIconCircleSize, height: kMenuIconCircleSize,
                            decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                            child: const Center(child: Icon(Icons.lock_outline, size: kMenuIconSize, color: Color(0xFF1E3A8A))),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Two-Factor Auth (TOTP)', style: TextStyle(color: Color(0xFF1E293B), fontSize: kFontSizeMenuItem, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                                SizedBox(height: 2),
                                Text('Authenticator app verification', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter')),
                              ],
                            ),
                          ),
                          if (_totpLoading)
                            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF3F45C7)))
                          else
                            GestureDetector(
                              onTap: () => _handleTotpToggle(!_totpEnabled),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 44, height: 26,
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: _totpEnabled ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                                  borderRadius: BorderRadius.circular(13)),
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 200),
                                  alignment: _totpEnabled ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_totpEnabled && _totpConfigured) ...[
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _settingRow(context, Icons.refresh, 'Reset TOTP Configuration', _handleTotpReset, isLast: true),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Management section
              _sectionLabel('MANAGEMENT'),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    _settingRow(context, Icons.mail_outline, 'Send Message',
                        () => _push(context, const SendMessageView())),
                    _divider(),
                    _settingRow(context, Icons.description_outlined, 'Manage Reports',
                        () => _push(context, const ManageReportsView()), isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Settings section
              _sectionLabel('SETTINGS'),
              const SizedBox(height: 12),
              _card(
                child: Column(
                  children: [
                    _settingRow(context, Icons.grid_view_rounded, 'Group Quantity',
                        () => _push(context, const GroupQuantityView())),
                    _divider(),
                    _settingRow(context, Icons.list_alt_outlined, 'Script Quantity',
                        () => _push(context, const ScriptQuantitySettingsView())),
                    _divider(),
                    _settingRow(context, Icons.tune_outlined, 'Brokerage Settings',
                        () => _push(context, const BrokerageSettingsView())),
                    _divider(),
                    _settingRow(context, Icons.trending_up_outlined, 'Trade Margin',
                        () => _push(context, const TradeMarginSettingsView())),
                    _divider(),
                    _settingRow(context, Icons.shield_outlined, 'Fresh Stop-Loss Limits',
                        () => _push(context, const FreshStoplossLimitView()), isLast: true),
                  ],
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  static Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(text, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
    );
  }

  static Widget _card({required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: child,
    );
  }

  static Widget _divider() => const Divider(height: 1, color: Color(0xFFF1F5F9));

  static Widget _settingRow(BuildContext context, IconData icon, String label, VoidCallback onTap, {bool isLast = false}) {
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Container(
                  width: kMenuIconCircleSize, height: kMenuIconCircleSize,
                  decoration: const BoxDecoration(color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                  child: Center(child: Icon(icon, size: kMenuIconSize, color: const Color(0xFF1E3A8A))),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF1E293B), fontSize: kFontSizeMenuItem, fontFamily: 'Inter', fontWeight: kFontWeightMedium))),
                const Icon(Icons.chevron_right, size: kMenuChevronSize, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}


// ── TOTP Setup Bottom Sheet ──
class _TotpSetupSheet extends StatefulWidget {
  final String qrDataUrl;
  final String secret;
  final VoidCallback onVerified;

  const _TotpSetupSheet({
    required this.qrDataUrl,
    required this.secret,
    required this.onVerified,
  });

  @override
  State<_TotpSetupSheet> createState() => _TotpSetupSheetState();
}

class _TotpSetupSheetState extends State<_TotpSetupSheet> {
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _verified = false;

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter 6-digit code'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isVerifying = true);
    try {
      final token = await SecureStorageService().getToken();
      final apiService = ApiService(backendUrl);
      final res = await apiService.post('/admin/totp/verify-setup', {'token': code}, token: token);
      final body = jsonDecode(res.body);

      if (res.statusCode == 200 && body['success'] == true) {
        setState(() => _verified = true);
        widget.onVerified();
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) Navigator.pop(context);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(body['message'] ?? 'Invalid code'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base64Data = widget.qrDataUrl.contains(',')
        ? widget.qrDataUrl.split(',').last
        : widget.qrDataUrl;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
            ),

            if (_verified) ...[
              const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 64),
              const SizedBox(height: 16),
              const Text('TOTP Activated!', style: TextStyle(fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightBold, color: Color(0xFF10B981))),
            ] else ...[
              const Text('Setup Two-Factor Authentication',
                  style: TextStyle(fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightBold, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              const Text('Scan this QR code with your authenticator app\n(Google Authenticator, Microsoft Authenticator, etc.)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: kFontSizeBodySmall, fontFamily: 'Inter', color: Color(0xFF64748B))),
              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))]),
                child: Image.memory(base64Decode(base64Data), width: 200, height: 200),
              ),
              const SizedBox(height: 16),

              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.secret));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Secret copied to clipboard'), backgroundColor: Color(0xFF3F45C7)),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(widget.secret, style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium, color: Color(0xFF64748B), letterSpacing: 1))),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy, size: 14, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text("Can't scan? Tap to copy the secret key", style: TextStyle(fontSize: kFontSizeSubtitle, fontFamily: 'Inter', color: Color(0xFF94A3B8))),
              const SizedBox(height: 24),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Enter the 6-digit code from your app', style: TextStyle(fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightMedium, color: Color(0xFF475569))),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, fontFamily: 'Inter', fontWeight: kFontWeightBold, letterSpacing: 8),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: const TextStyle(color: Color(0xFFCBD5E1), letterSpacing: 8),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF3F45C7), width: 1.5)),
                ),
              ),
              const SizedBox(height: 20),

              GestureDetector(
                onTap: _isVerifying ? null : _verify,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: _isVerifying ? null : const LinearGradient(colors: [Color(0xFFC6529E), Color(0xFF3B43C9)]),
                    color: _isVerifying ? const Color(0xFF94A3B8) : null,
                    borderRadius: BorderRadius.circular(14)),
                  child: Center(
                    child: _isVerifying
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('ACTIVATE TOTP', style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
