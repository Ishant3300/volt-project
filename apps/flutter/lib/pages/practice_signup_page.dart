import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:stocker/config/practice_session.dart';
import 'package:stocker/services/app_identity.dart';
import 'package:stocker/utils/contants.dart';

/// "Create practice account" — self sign-up for a practice (paper trading)
/// account on the separate practice backend (apex-project
/// docs/practice-trading.md). Simulated prices, practice money in tokens, no
/// real money. On success pops `{email, password}` so the login page signs in
/// through its normal flow.
class PracticeSignupPage extends StatefulWidget {
  const PracticeSignupPage({super.key});

  @override
  State<PracticeSignupPage> createState() => _PracticeSignupPageState();
}

class _PracticeSignupPageState extends State<PracticeSignupPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _tokens = TextEditingController(text: '100000');
  String _experience = 'new';
  final Set<String> _markets = {'NSE_FUT', 'NSE_OPT'};
  bool _busy = false;
  bool _hidePassword = true;

  static const _experiences = {
    'new': 'New to trading',
    'under_1_year': 'Less than 1 year',
    '1_to_3_years': '1 to 3 years',
    'over_3_years': 'More than 3 years',
  };
  static const _marketLabels = {
    'NSE_FUT': 'NSE futures',
    'NSE_OPT': 'NSE options',
    'MCX': 'MCX',
    'GLOBAL': 'Global indices',
    'COMEX': 'COMEX',
  };
  static const _quickTokens = [100000, 1000000, 10000000];

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _tokens.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg), backgroundColor: error ? Colors.red : kColorBuy));
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final email = _email.text.trim().toLowerCase();
    final password = _password.text;
    final tokens = double.tryParse(_tokens.text.replaceAll(',', '').trim());
    if (name.length < 2) return _snack('Enter your name');
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email)) {
      return _snack('Enter a valid email address');
    }
    if (password.length < 6) {
      return _snack('Password must be at least 6 characters');
    }
    if (_markets.isEmpty) return _snack('Select at least one market');
    if (tokens == null || tokens < 1) {
      return _snack('Enter the practice money in tokens');
    }

    setState(() => _busy = true);
    try {
      final res = await http
          .post(
            Uri.parse(
                '${PracticeSession.practiceUrl}/api/auth/practice-signup'),
            headers: {
              'Content-Type': 'application/json',
              if (AppIdentity.userAgent.isNotEmpty)
                'User-Agent': AppIdentity.userAgent,
            },
            body: jsonEncode({
              'name': name,
              'email': email,
              'password': password,
              'experience': _experience,
              'markets': _markets.toList(),
              'tokens': tokens,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final body = jsonDecode(res.body);
      if (res.statusCode == 201 && body['success'] == true) {
        if (!mounted) return;
        Navigator.pop(context, {'email': email, 'password': password});
      } else {
        _snack(body['message']?.toString() ?? 'Could not create the account');
      }
    } catch (_) {
      _snack('Could not reach the server. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            color: kColorTextMuted, fontFamily: kFontFamily, fontSize: 14),
        filled: true,
        fillColor: Colors.white,
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(t,
            style: const TextStyle(
                color: kColorTextPrimary,
                fontFamily: kFontFamily,
                fontSize: 13,
                fontWeight: kFontWeightMedium)),
      );

  String _fmtTokens(int v) {
    final s = v.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: kColorTextPrimary,
        title: const Text('Create practice account',
            style: TextStyle(
                fontFamily: kFontFamily,
                fontSize: 16,
                fontWeight: kFontWeightBold,
                color: kColorTextPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Paper trading only — no real money. Prices are simulated, not real market prices, and change every 30 minutes. This is a practice app to learn and grow.',
                style: TextStyle(
                    fontFamily: kFontFamily,
                    fontSize: 12.5,
                    height: 1.4,
                    color: Color(0xFF92400E)),
              ),
            ),
            _label('Full name'),
            TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: _decoration('Enter your name')),
            _label('Email (your login ID)'),
            TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: _decoration('name@email.com')),
            _label('Password'),
            TextField(
              controller: _password,
              obscureText: _hidePassword,
              decoration: _decoration('At least 6 characters',
                  suffix: IconButton(
                    icon: Icon(_hidePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _hidePassword = !_hidePassword),
                  )),
            ),
            _label('Trading experience'),
            DropdownButtonFormField<String>(
              initialValue: _experience,
              decoration: _decoration(''),
              items: _experiences.entries
                  .map((e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value,
                          style: const TextStyle(
                              fontFamily: kFontFamily, fontSize: 14))))
                  .toList(),
              onChanged: (v) => setState(() => _experience = v ?? 'new'),
            ),
            _label('Markets you trade'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _marketLabels.entries.map((e) {
                final on = _markets.contains(e.key);
                return FilterChip(
                  label: Text(e.value,
                      style: TextStyle(
                          fontFamily: kFontFamily,
                          fontSize: 13,
                          color: on ? kBrandPrimary : kColorTextPrimary)),
                  selected: on,
                  selectedColor: const Color(0xFFEFF6FF),
                  checkmarkColor: kBrandPrimary,
                  onSelected: (v) => setState(
                      () => v ? _markets.add(e.key) : _markets.remove(e.key)),
                );
              }).toList(),
            ),
            _label('Practice money (tokens)'),
            TextField(
              controller: _tokens,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: _decoration('Amount in tokens'),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _quickTokens
                  .map((v) => ActionChip(
                        label: Text('${_fmtTokens(v)} tokens',
                            style: const TextStyle(
                                fontFamily: kFontFamily, fontSize: 12)),
                        onPressed: () =>
                            setState(() => _tokens.text = v.toString()),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 6),
            const Text(
              'Each market you pick starts with this many tokens. Tokens have no money value.',
              style: TextStyle(
                  fontFamily: kFontFamily, fontSize: 12, color: kColorTextMuted),
            ),
            const SizedBox(height: 22),
            GestureDetector(
              onTap: _busy ? null : _submit,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: _busy
                      ? null
                      : const LinearGradient(
                          colors: [kBrandGradientStart, kBrandGradientEnd]),
                  color: _busy ? kColorTextMuted : null,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('CREATE ACCOUNT',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: kFontSizeButtonText,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightBold)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
