import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class LoginHistoryView extends StatefulWidget {
  const LoginHistoryView({super.key});

  @override
  State<LoginHistoryView> createState() => _LoginHistoryViewState();
}

class _LoginHistoryViewState extends State<LoginHistoryView> {
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _fetchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List.from(_entries);
      } else {
        _filtered = _entries.where((e) {
          final username = (e['username'] ?? '').toString().toLowerCase();
          final name = (e['name'] ?? '').toString().toLowerCase();
          return username.contains(q) || name.contains(q);
        }).toList();
      }
    });
  }

  Future<void> _fetchHistory() async {
    setState(() => _isLoading = true);
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final api = ApiService(backendUrl);

      final profileProvider = Provider.of<UserProfileProvider>(context, listen: false);
      final isUser = profileProvider.isUser;
      final endpoint = isUser
          ? '/my/login-history?limit=200'
          : '/master/login-history?limit=200';

      final res = await api.get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = body['data'] ?? [];
        setState(() {
          _entries = data.cast<Map<String, dynamic>>();
          _filtered = List.from(_entries);
        });
      }
    } catch (e) {
      debugPrint('Error fetching login history: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
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
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Login History', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                  const Spacer(),
                  Text('${_filtered.length} entries', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                ],
              ),
            ),

            // Search bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
                decoration: const InputDecoration(
                  hintText: 'Search by name or username...',
                  hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBody, fontFamily: 'Inter'),
                  prefixIcon: Icon(Icons.search, color: Color(0xFF94A3B8), size: kIconSizeMedium),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _fetchHistory,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) => _buildCard(_filtered[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
            child: const Icon(Icons.history, size: 28, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 16),
          const Text('No login history', style: TextStyle(color: Color(0xFF475569), fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> entry) {
    final username = entry['username'] ?? '';
    final name = entry['name'] ?? username;
    final role = (entry['role'] ?? 'USER').toString().toUpperCase();
    final ip = entry['ip_address'] ?? '-';
    final lastLogin = entry['logged_in_at'];

    String formattedDate = '-';
    if (lastLogin != null) {
      try {
        final dt = DateTime.parse(lastLogin.toString()).toLocal();
        formattedDate = DateFormat('dd MMM yyyy · hh:mm a').format(dt);
      } catch (_) {}
    }

    final roleColor = role == 'ADMIN'
        ? const Color(0xFFEF4444)
        : role == 'MASTER'
            ? const Color(0xFF3F45C7)
            : const Color(0xFF10B981);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar + name + role badge
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Center(child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?', style: TextStyle(color: roleColor, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightBold))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: roleColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(role, style: TextStyle(color: roleColor, fontSize: kFontSizeBadge, fontFamily: 'Inter', fontWeight: kFontWeightBold, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: username · date · IP — all on separate labeled lines
          Row(
            children: [
              _infoChip(Icons.person_outline, username),
              const SizedBox(width: 12),
              _infoChip(Icons.access_time, formattedDate),
              const SizedBox(width: 12),
              _infoChip(Icons.language, ip),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: kFontSizeBodySmall, color: const Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightMedium),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
