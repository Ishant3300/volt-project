import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import '../config/practice_only.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});
  @override
  State<NotificationSettingsView> createState() => _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  bool _isLoading = true;
  bool _isSaving = false;
  // Set when _fetch couldn't confirm the REAL server-side settings — the
  // map below then holds its literal in-file defaults, not the user's
  // actual preferences. Previously this was silently swallowed: a user on
  // a flaky connection saw the defaults rendered as if freshly loaded,
  // and tapping Update PUT those defaults over their real settings.
  bool _loadFailed = false;

  // Settings map — keys match backend field names
  final Map<String, bool> _settings = {
    'market_order': false,
    'pending_order': true,
    'admin_order_execution': false,
    'admin_order_deletion': true,
    'trading_sound': false,
  };

  // Display labels
  static const _labels = {
    'market_order': 'Market Order',
    'pending_order': 'Pending Order',
    // No admins in the practice-only build — these rows are not shown there.
    if (!kPracticeOnly) 'admin_order_execution': 'Admin Order Execution',
    if (!kPracticeOnly) 'admin_order_deletion': 'Admin Order Deletion',
    'trading_sound': 'Trading Sound',
  };

  /// Settings with a row on screen (all of them, except in the
  /// practice-only build).
  Iterable<String> get _shownKeys => _settings.keys.where(_labels.containsKey);

  @override
  void initState() { super.initState(); _fetch(); }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    var loaded = false;
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).get('/auth/notification-settings', token: token);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final ns = data['data']['notification_settings'] as Map<String, dynamic>;
          for (var key in _settings.keys) {
            if (ns.containsKey(key)) _settings[key] = ns[key] == true;
          }
          loaded = true;
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _isLoading = false;
        _loadFailed = !loaded;
      });
    }
  }

  Future<void> _save() async {
    if (_loadFailed) {
      _snack('Could not confirm your current settings — retry loading before saving.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).put('/auth/notification-settings', {'notification_settings': _settings}, token: token);
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        _snack('Settings updated');
      } else {
        _snack(data['message'] ?? 'Failed', isError: true);
      }
    } catch (e) { _snack('Error: $e', isError: true); }
    if (mounted) setState(() => _isSaving = false);
  }

  void _reset() {
    setState(() {
      _settings['market_order'] = false;
      _settings['pending_order'] = true;
      _settings['admin_order_execution'] = false;
      _settings['admin_order_deletion'] = true;
      _settings['trading_sound'] = false;
    });
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? kColorSell : kColorBuy));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          GestureDetector(onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: const Icon(Icons.arrow_back, color: kColorTextPrimary, size: kIconSizeMedium))),
          const SizedBox(width: 12),
          const Text('Notification Settings', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
        ])),

        if (_loadFailed && !_isLoading)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA))),
            child: Row(children: [
              const Expanded(child: Text(
                'Could not load your real settings — showing defaults. Saving now would overwrite your actual preferences.',
                style: TextStyle(color: Color(0xFFB91C1C), fontSize: kFontSizeCaption, fontFamily: kFontFamily),
              )),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _fetch,
                child: const Text('RETRY', style: TextStyle(color: Color(0xFFB91C1C), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
              ),
            ]),
          ),

        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
          : SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: Column(children: _shownKeys.map((key) {
                final isLast = key == _shownKeys.last;
                return Column(children: [
                  _toggleRow(_labels[key]!, _settings[key]!, (v) => setState(() => _settings[key] = v)),
                  if (!isLast) const Divider(height: 24, color: Color(0xFFF1F5F9)),
                ]);
              }).toList()),
            )),
        ),

        // Bottom buttons
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: _reset,
            child: Container(height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
              child: const Text('RESET', style: TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          )),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: _isSaving ? null : _save,
            child: Container(height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(12)),
              child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('UPDATE', style: TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          )),
        ])),
      ])),
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
      GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48, height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: value ? kBrandPrimary : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(14)),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        ),
      ),
    ]);
  }
}
