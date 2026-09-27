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
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _total = 0;
  final int _pageSize = 30;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _scrollController.addListener(_onScroll);
    _fetchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
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
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
      _entries = [];
      _filtered = [];
    });
    try {
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final api = ApiService(backendUrl);

      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      final isUser = profileProvider.isUser;
      final endpoint = isUser
          ? '/my/login-history?page=1&limit=$_pageSize'
          : '/master/login-history?page=1&limit=$_pageSize';

      final res = await api.get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = body['data'] ?? [];
        final total = body['total'] ?? 0;
        setState(() {
          _entries = data.cast<Map<String, dynamic>>();
          _filtered = List.from(_entries);
          _total = total;
          _hasMore = _entries.length < total;
        });
      }
    } catch (e) {
      debugPrint('Error fetching login history: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _currentPage + 1;
      final storage = SecureStorageService();
      final token = await storage.getToken();
      final api = ApiService(backendUrl);

      final profileProvider =
          Provider.of<UserProfileProvider>(context, listen: false);
      final isUser = profileProvider.isUser;
      final endpoint = isUser
          ? '/my/login-history?page=$nextPage&limit=$_pageSize'
          : '/master/login-history?page=$nextPage&limit=$_pageSize';

      final res = await api.get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final List data = body['data'] ?? [];
        if (data.isNotEmpty) {
          setState(() {
            _currentPage = nextPage;
            _entries.addAll(data.cast<Map<String, dynamic>>());
            _applyFilter();
            _hasMore = _entries.length < _total;
          });
        } else {
          setState(() => _hasMore = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading more login history: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
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
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: kColorTextPrimary, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Login History',
                      style: TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizeViewTitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold)),
                  const Spacer(),
                  Text(_isLoading ? '...' : '${_filtered.length} of $_total',
                      style: const TextStyle(
                          color: kColorTextMuted,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium)),
                ],
              ),
            ),

            // Search bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 2))
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                    fontSize: kFontSizeBody,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightMedium),
                decoration: const InputDecoration(
                  hintText: 'Search by name or username...',
                  hintStyle: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: kFontSizeBody,
                      fontFamily: kFontFamily),
                  prefixIcon: Icon(Icons.search,
                      color: kColorTextMuted, size: kIconSizeMedium),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: kBrandPrimary, strokeWidth: 2.5))
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          onRefresh: _fetchHistory,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filtered.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == _filtered.length) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                          color: kBrandPrimary,
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              return _buildCard(_filtered[index]);
                            },
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]),
            child:
                const Icon(Icons.history, size: 28, color: Color(0xFFCBD5E1)),
          ),
          const SizedBox(height: 16),
          const Text('No login history',
              style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: kFontSizeButtonText,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold)),
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
        ? kColorSell
        : role == 'MASTER'
            ? kBrandPrimary
            : kColorBuy;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar + name + role badge
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: Center(
                    child: Text(
                        username.isNotEmpty ? username[0].toUpperCase() : '?',
                        style: TextStyle(
                            color: roleColor,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightBold))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: kColorTextPrimary,
                        fontSize: kFontSizeBody,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: roleColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(role,
                    style: TextStyle(
                        color: roleColor,
                        fontSize: kFontSizeBadge,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightBold,
                        letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: username · date · IP
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
          Icon(icon, size: kFontSizeBodySmall, color: kColorTextMuted),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                  color: kColorTextMuted,
                  fontSize: kFontSizeNavLabel,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightMedium),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
