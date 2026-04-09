import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:stocker/providers/watchlist_provider.dart';
import 'package:stocker/providers/user_profile_provider.dart';
import 'package:stocker/services/auth_service.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/providers/trade_metrics_provider.dart';
import 'package:stocker/services/firebase_service.dart';
import '../home_page.dart';
import '../utils/contants.dart';

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
  List<Map<String, dynamic>> _servers = [];
  bool _isLoadingServers = false;

  @override
  void initState() {
    super.initState();
    _fetchServers();
  }

  Future<void> _fetchServers() async {
    setState(() => _isLoadingServers = true);
    try {
      final res = await ApiService(backendUrl).get('/servers');
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          final data = body['data'];
          final List serverList = data is Map ? (data['servers'] ?? []) : (data ?? []);
          setState(() {
            _servers = serverList.cast<Map<String, dynamic>>();
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingServers = false);
  }

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
      final apiService = Provider.of<ApiService>(context, listen: false);
      final authData = AuthenticateData(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );

      apiService.setInitializing(true);
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

          // Register FCM token with backend
          await FirebaseService().registerToken();

          apiService.setInitializing(false);

          // Check if disclaimer has been accepted
          const storage = FlutterSecureStorage();
          final accepted = await storage.read(key: 'disclaimer_accepted');
          if (!mounted) return;

          if (accepted == 'true') {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MyHomePage(title: 'Stocker App')),
            );
          } else {
            _showDisclaimerDialog();
          }
        } else {
          apiService.setInitializing(false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Provider.of<ApiService>(context, listen: false).setInitializing(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showDisclaimerDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('⚠️', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(
                'Important Notice',
                style: TextStyle(
                  fontSize: kFontSizeSectionHeader,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightBold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'APEX is a simulation-based trading platform designed for educational purposes only.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: kFontSizeBody,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightSemiBold,
                  color: const Color(0xFF334155),
                ),
              ),
              const SizedBox(height: 16),
              _buildBulletPoint('No real money trading is supported'),
              _buildBulletPoint('No deposits or withdrawals are possible'),
              _buildBulletPoint('All trades, prices, and profits/losses are simulated or based on delayed data'),
              _buildBulletPoint('APEX does not provide financial or investment advice'),
              const SizedBox(height: 16),
              Text(
                'By continuing, you acknowledge that you are using a virtual trading environment and not a real brokerage service.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: kFontSizeSubtitle,
                  fontFamily: 'Inter',
                  fontWeight: kFontWeightRegular,
                  color: const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              // I Understand & Continue
              GestureDetector(
                onTap: () async {
                  const storage = FlutterSecureStorage();
                  await storage.write(key: 'disclaimer_accepted', value: 'true');
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MyHomePage(title: 'Stocker App')),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFFC6529E), Color(0xFF3B43C9)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      'I Understand & Continue',
                      style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightBold),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Exit App
              GestureDetector(
                onTap: () => exit(0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Center(
                    child: Text(
                      'Exit App',
                      style: TextStyle(color: const Color(0xFF64748B), fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: kFontSizeBodySmall,
                fontFamily: 'Inter',
                fontWeight: kFontWeightRegular,
                color: const Color(0xFF64748B),
              ),
            ),
          ),
        ],
      ),
    );
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
                      // Logo
                      SvgPicture.asset(
                        'assets/Subtract.svg',
                        width: 80,
                        height: 80,
                      ),
                      const SizedBox(height: 12),
                      Text('APEX', style: TextStyle(color: Color(0xFF0F172A), fontSize: kFontSizeLoginTitle, fontFamily: 'Inter', fontWeight: kFontWeightBold, letterSpacing: 3)),
                      const SizedBox(height: 8),
                      Text(
                        'To sign in to an account in the application,\nenter your username and password',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightRegular),
                      ),
                      const SizedBox(height: 16),

                      // Server field
                      _buildFieldLabel('Server'),
                      const SizedBox(height: 6),
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
                            hint: Text(
                              _isLoadingServers ? 'Loading...' : 'Select Server',
                              style: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeButtonText, fontFamily: 'Inter'),
                            ),
                            isExpanded: true,
                            items: _servers.map((s) {
                              final name = s['name']?.toString() ?? '';
                              return DropdownMenuItem<String>(value: name, child: Text(name));
                            }).toList(),
                            onChanged: (String? newValue) {
                              if (newValue != null) setState(() => _selectedServer = newValue);
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Username field
                      _buildFieldLabel('Username'),
                      const SizedBox(height: 6),
                      _buildTextField(_usernameController, 'Enter Username', false),
                      const SizedBox(height: 14),

                      // Password field
                      _buildFieldLabel('Password'),
                      const SizedBox(height: 6),
                      _buildTextField(_passwordController, 'Enter Password', true),
                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Forgot password?', style: TextStyle(color: Color(0xFF3F45C7), fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                      ),
                      const SizedBox(height: 16),

                      // Continue button
                      GestureDetector(
                        onTap: _isLoading ? null : _login,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            gradient: _isLoading
                                ? null
                                : const LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Color(0xFFC6529E),
                                      Color(0xFF3B43C9),
                                    ],
                                  ),
                            color: _isLoading ? const Color(0xFF94A3B8) : null,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : Text('CONTINUE', style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
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
                      const TextSpan(text: 'By clicking "Continue", I have read and agree\nwith the ', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter')),
                      TextSpan(text: 'Term & Privacy Policy', style: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium, decoration: TextDecoration.underline)),
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
      child: Text(label, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, bool obscure) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeButtonText, fontFamily: 'Inter'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF3F45C7), width: 1.5)),
      ),
    );
  }
}
