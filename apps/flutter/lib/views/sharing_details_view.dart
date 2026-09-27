import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/master.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class SharingDetailsView extends StatefulWidget {
  final Master? master;
  final User? user;

  const SharingDetailsView({super.key, this.master, this.user});

  @override
  State<SharingDetailsView> createState() => _SharingDetailsViewState();
}

class _SharingDetailsViewState extends State<SharingDetailsView> {
  int _selectedTabIndex = 0;
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _masterInfo;
  List<Map<String, dynamic>> _children = [];

  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _fetchSharingDetails();
  }

  Future<void> _fetchSharingDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final token = await _storage.getToken();
      final apiService = ApiService(backendUrl);
      final role = await _storage.getRole();

      String url = '/master/sharing-details';
      if (role == 'ADMIN' && widget.master != null) {
        url += '?master_id=${widget.master!.id}';
      } else if (role == 'ADMIN' && widget.user != null) {
        url += '?master_id=${widget.user!.masterId}';
      }

      final response = await apiService.get(url, token: token);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['success'] == true) {
          setState(() {
            _masterInfo = body['data']['master'];
            _children = List<Map<String, dynamic>>.from(
                body['data']['children'] ?? []);
            _isLoading = false;
          });
        } else {
          setState(() {
            _error = body['message'] ?? 'Failed to load';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _error = 'Failed to load sharing details';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  String get _title {
    if (widget.master != null) return '${widget.master!.username} - Sharing';
    if (widget.user != null) return '${widget.user!.username} - Sharing';
    return 'Sharing Details';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
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
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Icon(Icons.arrow_back,
                          color: kColorTextPrimary, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        color: kColorTextPrimary,
                        fontSize: kFontSizeViewTitle,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Tab buttons
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildTabButton('Brk Sharing', 0, isLeft: true),
                  _buildTabButton('P&L Sharing', 1, isLeft: false),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Content
            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String label, int index, {required bool isLeft}) {
    final selected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: ShapeDecoration(
            color: selected ? kBrandPrimary : Colors.white,
            shape: RoundedRectangleBorder(
              side: const BorderSide(width: 1, color: kBrandPrimary),
              borderRadius: BorderRadius.only(
                topLeft: isLeft ? const Radius.circular(8) : Radius.zero,
                bottomLeft: isLeft ? const Radius.circular(8) : Radius.zero,
                topRight: !isLeft ? const Radius.circular(8) : Radius.zero,
                bottomRight: !isLeft ? const Radius.circular(8) : Radius.zero,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF333333),
              fontSize: kFontSizeBody,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightMedium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: kBrandPrimary));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(
                    color: Color(0xFF8E8E93),
                    fontSize: kFontSizeBody,
                    fontFamily: kFontFamily)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _fetchSharingDetails,
              child: const Text('Retry',
                  style: TextStyle(
                      color: kBrandPrimary,
                      fontSize: kFontSizeBody,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold)),
            ),
          ],
        ),
      );
    }

    final isBrk = _selectedTabIndex == 0;
    final allEntries = <Map<String, dynamic>>[];

    // Add master at top
    if (_masterInfo != null) allEntries.add(_masterInfo!);
    allEntries.addAll(_children);

    if (allEntries.isEmpty) {
      return const Center(
        child: Text('No sharing data found',
            style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: kFontSizeBody,
                fontFamily: kFontFamily)),
      );
    }

    return RefreshIndicator(
      color: kBrandPrimary,
      onRefresh: _fetchSharingDetails,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: allEntries.length,
        itemBuilder: (context, index) {
          final entry = allEntries[index];
          final isMasterEntry = index == 0 && _masterInfo != null;
          return _buildSharingCard(entry, isBrk, isMasterEntry: isMasterEntry);
        },
      ),
    );
  }

  Widget _buildSharingCard(Map<String, dynamic> entry, bool isBrk,
      {bool isMasterEntry = false}) {
    final username = entry['username'] ?? '';
    final name = entry['name'] ?? '';
    final role = entry['role'] ?? 'USER';
    final double sharing = isBrk
        ? (entry['brokerage_sharing'] as num?)?.toDouble() ?? 0
        : (entry['pnl_sharing'] as num?)?.toDouble() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMasterEntry
            ? kBrandPrimary.withValues(alpha: 0.04)
            : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isMasterEntry
            ? Border.all(color: kBrandPrimary.withValues(alpha: 0.2))
            : null,
        boxShadow: isMasterEntry
            ? null
            : [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 2)),
              ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isMasterEntry
                  ? kBrandPrimary.withValues(alpha: 0.12)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: TextStyle(
                  color: isMasterEntry
                      ? kBrandPrimary
                      : const Color(0xFF64748B),
                  fontSize: kFontSizeBody,
                  fontFamily: kFontFamily,
                  fontWeight: kFontWeightSemiBold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name + role
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: const TextStyle(
                    color: kColorTextPrimary,
                    fontSize: kFontSizeName,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightName,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (name.isNotEmpty)
                      Text(
                        name,
                        style: const TextStyle(
                          color: kColorTextMuted,
                          fontSize: kFontSizeCaption,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightRegular,
                        ),
                      ),
                    if (name.isNotEmpty) const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: role == 'MASTER'
                            ? const Color(0xFFFFF3E0)
                            : const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isMasterEntry ? 'PARENT' : role,
                        style: TextStyle(
                          color: role == 'MASTER'
                              ? const Color(0xFFE65100)
                              : const Color(0xFF2E7D32),
                          fontSize: kFontSizeBadge,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Sharing percentage
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kBrandPrimary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${sharing.toStringAsFixed(sharing.truncateToDouble() == sharing ? 0 : 1)}%',
              style: const TextStyle(
                color: kBrandPrimary,
                fontSize: kFontSizeBody,
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
