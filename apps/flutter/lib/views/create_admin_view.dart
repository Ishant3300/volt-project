import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/super_admin_service.dart';
import '../utils/contants.dart';

/// Super Admin only. New admins get every permission granted by default
/// (backend default when `permissions` is omitted) — restricted afterward
/// from the admin's own management screen.
class CreateAdminView extends StatefulWidget {
  const CreateAdminView({super.key});

  @override
  State<CreateAdminView> createState() => _CreateAdminViewState();
}

class _CreateAdminViewState extends State<CreateAdminView> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final response = await SuperAdminService(api).createAdmin(
        username: username,
        password: password,
      );
      final body = jsonDecode(response.body);

      if (response.statusCode == 201 && body['success'] == true) {
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() => _error = body['message'] ?? 'Failed to create admin');
      }
    } catch (e) {
      setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back, color: kColorTextPrimary, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Create Admin', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'New admins are created with every permission granted. Restrict them afterward from their own management screen.',
                        style: TextStyle(color: kColorTextMuted, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightRegular),
                      ),
                      const SizedBox(height: 16),
                      if (_error != null) ...[
                        Text(_error!, style: const TextStyle(color: kColorSell, fontSize: kFontSizeBody, fontFamily: kFontFamily)),
                        const SizedBox(height: 12),
                      ],
                      const Text('Username', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1D1D6))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Password', style: TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFD1D1D6))),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBrandPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isSubmitting
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Create admin', style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
