import 'package:flutter/material.dart';
import '../services/announcement_service.dart';
import '../utils/contants.dart';

class SendMessageView extends StatefulWidget {
  const SendMessageView({super.key});

  @override
  State<SendMessageView> createState() => _SendMessageViewState();
}

class _SendMessageViewState extends State<SendMessageView> {
  final _messageCtrl = TextEditingController();
  bool _isSending = false;
  bool _isClearing = false;
  String? _currentMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final msg = await AnnouncementService().fetchActive();
    if (mounted) setState(() => _currentMessage = msg);
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_messageCtrl.text.trim().isEmpty) {
      _snack('Please enter a message', isError: true);
      return;
    }
    setState(() => _isSending = true);
    final ok = await AnnouncementService().send(_messageCtrl.text.trim());
    if (mounted) {
      if (ok) {
        _snack('Announcement sent to all users');
        setState(() => _currentMessage = _messageCtrl.text.trim());
        _messageCtrl.clear();
      } else {
        _snack('Failed to send', isError: true);
      }
      setState(() => _isSending = false);
    }
  }

  Future<void> _clear() async {
    setState(() => _isClearing = true);
    final ok = await AnnouncementService().clear();
    if (mounted) {
      if (ok) {
        _snack('Announcement cleared');
        setState(() => _currentMessage = null);
      } else {
        _snack('Failed to clear', isError: true);
      }
      setState(() => _isClearing = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
    ));
  }

  @override
  Widget build(BuildContext context) {
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
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Announcement', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current announcement
                    if (_currentMessage != null && _currentMessage!.isNotEmpty) ...[
                      const Text('CURRENT ANNOUNCEMENT', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity, padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFFEE2E2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.campaign, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(_currentMessage!, style: const TextStyle(color: Color(0xFFDC2626), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold))),
                            GestureDetector(
                              onTap: _isClearing ? null : _clear,
                              child: _isClearing
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEF4444)))
                                  : const Icon(Icons.close, size: 18, color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // New announcement
                    const Text('NEW ANNOUNCEMENT', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('This message will appear as a scrolling banner on all users\' Watchlist and Profile pages.',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium, height: 1.4)),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _messageCtrl,
                            maxLines: 4,
                            style: const TextStyle(fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
                            decoration: const InputDecoration(
                              hintText: 'Type your announcement...',
                              hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: 'Inter'),
                              border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFFF1F5F9))),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: Color(0xFFF1F5F9))),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12)), borderSide: BorderSide(color: kBrandPrimary)),
                              contentPadding: EdgeInsets.all(14),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _isSending ? null : _send,
                      child: Container(
                        width: double.infinity, height: 52,
                        decoration: BoxDecoration(
                          color: _isSending ? const Color(0xFF94A3B8) : kBrandPrimary,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: _isSending
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('SEND ANNOUNCEMENT', style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
