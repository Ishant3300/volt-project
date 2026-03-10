import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import '../home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String _selectedServer = 'Select Server';
  bool _isLoading = false;

  void _login() async {
    if (_selectedServer == 'Select Server') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a server'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter username'), backgroundColor: Colors.red),
      );
      return;
    }
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter password'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final authData = AuthenticateData(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      final response = await authService.login(data: authData);

      if (mounted) {
        if (response.success) {
          final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
          await profileProvider.fetchProfile();

          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message), backgroundColor: Colors.green),
          );

          final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
          await watchlistProvider.loadWatchlist();

          final tradeMetricsProvider = Provider.of<TradeMetricsProvider>(context, listen: false);
          await tradeMetricsProvider.fetchBaseData();

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MyHomePage(title: 'Stocker App')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                // Main login form
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('STOCKER', style: TextStyle(color: Color(0xFF22547C), fontSize: 40, fontFamily: 'Inter', fontWeight: FontWeight.w800)),
                      const SizedBox(height: 13),
                      const Text(
                        'To sign in to an account in the application,\nenter your username and password',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w400),
                      ),
                      const SizedBox(height: 24),

                      // Server field
                      _buildFieldLabel('Server'),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedServer == 'Select Server' ? null : _selectedServer,
                            hint: const Text('Select Server', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 15, fontFamily: 'Inter')),
                            items: ['test'].map((String value) {
                              return DropdownMenuItem<String>(value: value, child: Text(value));
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) setState(() => _selectedServer = newValue);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Username field
                      _buildFieldLabel('Username'),
                      const SizedBox(height: 8),
                      _buildTextField(_usernameController, 'Enter Username', false),
                      const SizedBox(height: 20),

                      // Password field
                      _buildFieldLabel('Password'),
                      const SizedBox(height: 8),
                      _buildTextField(_passwordController, 'Enter Password', true),
                      const SizedBox(height: 16),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: const Text('Forgot password?', style: TextStyle(color: Color(0xFF22547C), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(height: 24),

                      // Continue button
                      GestureDetector(
                        onTap: _isLoading ? null : _login,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: _isLoading ? const Color(0xFF94A3B8) : const Color(0xFF22547C),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('CONTINUE', style: TextStyle(color: Colors.white, fontSize: 15, fontFamily: 'Inter', fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                // Terms
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'By clicking "Continue", I have read and agree\nwith the ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: 'Inter')),
                      TextSpan(text: 'Term & Privacy Policy', style: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w500, decoration: TextDecoration.underline)),
                    ]),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: 0.3)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, fontFamily: 'Inter', fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 15, fontFamily: 'Inter'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF22547C), width: 1.5)),
      ),
    );
  }
}
