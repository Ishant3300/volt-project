import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class ChangePasswordView extends StatefulWidget {
  const ChangePasswordView({super.key});
  @override
  State<ChangePasswordView> createState() => _ChangePasswordViewState();
}

class _ChangePasswordViewState extends State<ChangePasswordView> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;

  @override
  void dispose() { _currentCtrl.dispose(); _newCtrl.dispose(); _confirmCtrl.dispose(); super.dispose(); }

  void _reset() { _currentCtrl.clear(); _newCtrl.clear(); _confirmCtrl.clear(); }

  Future<void> _update() async {
    final current = _currentCtrl.text.trim();
    final newPass = _newCtrl.text.trim();
    final confirm = _confirmCtrl.text.trim();

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _snack('Please fill all fields', isError: true); return;
    }
    if (newPass.length < 6) {
      _snack('New password must be at least 6 characters', isError: true); return;
    }
    if (newPass != confirm) {
      _snack('New password and confirm password do not match', isError: true); return;
    }
    if (current == newPass) {
      _snack('New password must be different from current', isError: true); return;
    }

    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).post(
        '/auth/change-password',
        {'current_password': current, 'new_password': newPass},
        token: token,
      );
      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['success'] == true) {
        _snack('Password changed successfully');
        _reset();
      } else {
        _snack(data['message'] ?? 'Failed to change password', isError: true);
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981)));
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
              child: const Icon(Icons.arrow_back, color: Colors.black, size: 20))),
          const SizedBox(width: 12),
          const Text('Change Password', style: TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
        ])),

        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _field('Current Password', _currentCtrl, _obscureCurrent, () => setState(() => _obscureCurrent = !_obscureCurrent)),
            const SizedBox(height: 20),
            _field('New Password', _newCtrl, _obscureNew, () => setState(() => _obscureNew = !_obscureNew)),
            const SizedBox(height: 20),
            _field('Confirm Password', _confirmCtrl, _obscureConfirm, () => setState(() => _obscureConfirm = !_obscureConfirm)),
          ]),
        ))),

        // Bottom buttons
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: _reset,
            child: Container(height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(12)),
              child: const Text('RESET', style: TextStyle(color: Color(0xFF334155), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600))),
          )),
          const SizedBox(width: 12),
          Expanded(child: GestureDetector(
            onTap: _isLoading ? null : _update,
            child: Container(height: 48, alignment: Alignment.center,
              decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(12)),
              child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('UPDATE', style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w600))),
          )),
        ])),
      ])),
    );
  }

  Widget _field(String label, TextEditingController ctrl, bool obscure, VoidCallback toggleObscure) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Color(0xFF334155), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Container(height: 48,
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: TextField(controller: ctrl, obscureText: obscure,
          style: const TextStyle(fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: 'Enter $label'.toLowerCase(), hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14), border: InputBorder.none,
            suffixIcon: GestureDetector(onTap: toggleObscure,
              child: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: const Color(0xFF94A3B8))),
          )),
      ),
    ]);
  }
}
