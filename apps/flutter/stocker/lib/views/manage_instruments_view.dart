import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class ManageInstrumentsView extends StatefulWidget {
  const ManageInstrumentsView({super.key});

  @override
  State<ManageInstrumentsView> createState() => _ManageInstrumentsViewState();
}

class _ManageInstrumentsViewState extends State<ManageInstrumentsView> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<dynamic> _instruments = [];
  List<String> _segments = [];
  String? _selectedSegment;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadSegments();
    _loadInstruments();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 300 &&
        !_isLoadingMore && _page < _totalPages) {
      _loadMore();
    }
  }

  Future<void> _loadSegments() async {
    try {
      final token = await SecureStorageService().getToken();
      final api = ApiService(backendUrl);
      final res = await api.get('/admin/instruments/segments', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() => _segments = List<String>.from(body['data']));
        }
      }
    } catch (e) {
      log('Error loading segments: $e');
    }
  }

  Future<void> _loadInstruments({bool reset = true}) async {
    if (reset) {
      setState(() { _isLoading = true; _page = 1; _instruments = []; });
    }
    try {
      final token = await SecureStorageService().getToken();
      final api = ApiService(backendUrl);
      final params = <String>['page=$_page', 'limit=50'];
      if (_searchController.text.isNotEmpty) params.add('search=${Uri.encodeComponent(_searchController.text)}');
      if (_selectedSegment != null) params.add('segment=$_selectedSegment');
      final res = await api.get('/admin/instruments?${params.join('&')}', token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() {
            if (reset) {
              _instruments = body['data'];
            } else {
              _instruments.addAll(body['data']);
            }
            _total = body['pagination']['total'];
            _totalPages = body['pagination']['pages'];
            _isLoading = false;
            _isLoadingMore = false;
          });
          return;
        }
      }
    } catch (e) {
      log('Error loading instruments: $e');
    }
    if (mounted) setState(() { _isLoading = false; _isLoadingMore = false; });
  }

  Future<void> _loadMore() async {
    setState(() { _isLoadingMore = true; _page++; });
    await _loadInstruments(reset: false);
  }

  Future<void> _toggleEnabled(dynamic inst) async {
    final id = inst['_id'] ?? inst['id'];
    final currentEnabled = inst['enabled'] ?? true;
    try {
      final token = await SecureStorageService().getToken();
      final api = ApiService(backendUrl);
      final res = await api.put('/admin/instruments/$id/toggle', {'enabled': !currentEnabled}, token: token);
      if (res.statusCode == 200) {
        setState(() => inst['enabled'] = !currentEnabled);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${inst['tradingsymbol']} ${!currentEnabled ? 'enabled' : 'disabled'}'),
              backgroundColor: !currentEnabled ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      log('Error toggling instrument: $e');
    }
  }

  Future<void> _deleteInstrument(dynamic inst) async {
    final id = inst['_id'] ?? inst['id'];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Delete Instrument?', style: TextStyle(fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
              const SizedBox(height: 12),
              Text('${inst['tradingsymbol']} will be deactivated.\nExisting positions can still be closed.',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBody, fontFamily: 'Inter'), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)))),
                )),
                const SizedBox(width: 12),
                Expanded(child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12)),
                    child: const Center(child: Text('Delete', style: TextStyle(color: Colors.white, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)))),
                )),
              ]),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final token = await SecureStorageService().getToken();
      final api = ApiService(backendUrl);
      final res = await api.delete('/admin/instruments/$id', token: token);
      if (res.statusCode == 200) {
        setState(() {
          inst['deleted_at'] = DateTime.now().toIso8601String();
          inst['enabled'] = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${inst['tradingsymbol']} deactivated'), backgroundColor: const Color(0xFFEF4444), duration: const Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      log('Error deleting instrument: $e');
    }
  }

  Future<void> _restoreInstrument(dynamic inst) async {
    final id = inst['_id'] ?? inst['id'];
    try {
      final token = await SecureStorageService().getToken();
      final api = ApiService(backendUrl);
      final res = await api.put('/admin/instruments/$id/restore', {}, token: token);
      if (res.statusCode == 200) {
        setState(() {
          inst['deleted_at'] = null;
          inst['enabled'] = true;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${inst['tradingsymbol']} restored'), backgroundColor: const Color(0xFF10B981), duration: const Duration(seconds: 1)),
          );
        }
      }
    } catch (e) {
      log('Error restoring instrument: $e');
    }
  }

  String _formatExpiry(dynamic expiry) {
    if (expiry == null) return '';
    try {
      final d = DateTime.parse(expiry.toString());
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${d.day} ${months[d.month - 1]}';
    } catch (_) {
      return '';
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
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(width: 40, height: 40,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                    child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Manage Instruments', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                  Text('$_total instruments', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: 'Inter')),
                ])),
              ]),
            ),
            // Search
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(height: 44,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: kFontSizeBody, fontFamily: 'Inter'),
                  decoration: InputDecoration(
                    hintText: 'Search by name or symbol...',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: 'Inter'),
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? GestureDetector(onTap: () { _searchController.clear(); _loadInstruments(); },
                            child: const Icon(Icons.close, size: 16, color: Color(0xFF94A3B8)))
                        : null,
                    border: InputBorder.none, isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (_) => _loadInstruments(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Segment filter chips
            if (_segments.isNotEmpty)
              SizedBox(height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _filterChip('ALL', _selectedSegment == null, () { setState(() => _selectedSegment = null); _loadInstruments(); }),
                    ..._segments.map((s) => _filterChip(s, _selectedSegment == s, () { setState(() => _selectedSegment = s); _loadInstruments(); })),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
                  : _instruments.isEmpty
                      ? const Center(child: Text('No instruments found', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: 'Inter')))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _instruments.length + (_isLoadingMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _instruments.length) {
                              return const Padding(padding: EdgeInsets.all(16),
                                child: Center(child: SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2))));
                            }
                            return _buildInstrumentCard(_instruments[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF3F45C7) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: active ? null : Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(label, style: TextStyle(
          fontSize: kFontSizeCaption, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold,
          color: active ? Colors.white : const Color(0xFF64748B),
        )),
      ),
    );
  }

  Widget _buildInstrumentCard(dynamic inst) {
    final enabled = inst['enabled'] ?? true;
    final isDeleted = inst['deleted_at'] != null;
    final type = inst['instrument_type'] ?? '';

    Color typeColor;
    if (type == 'FUT') {
      typeColor = const Color(0xFF3B82F6);
    } else if (type == 'CE') {
      typeColor = const Color(0xFF10B981);
    } else if (type == 'PE') {
      typeColor = const Color(0xFFEF4444);
    } else {
      typeColor = const Color(0xFF8B5CF6);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDeleted ? const Color(0xFFF1F5F9) : (enabled ? Colors.white : const Color(0xFFFEF2F2)),
        borderRadius: BorderRadius.circular(16),
        border: isDeleted ? Border.all(color: const Color(0xFFCBD5E1)) : (enabled ? null : Border.all(color: const Color(0xFFFECACA))),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          // Type badge
          Container(
            width: 36, padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(color: typeColor.withValues(alpha: isDeleted ? 0.05 : 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(type.isNotEmpty ? type : 'IDX', textAlign: TextAlign.center,
              style: TextStyle(fontSize: kFontSizeCaption, fontWeight: kFontWeightSemiBold, color: isDeleted ? const Color(0xFF94A3B8) : typeColor, fontFamily: 'Inter')),
          ),
          const SizedBox(width: 10),
          // Info
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(inst['display_name'] ?? inst['raw_name'] ?? inst['tradingsymbol'] ?? '',
                  style: TextStyle(fontSize: kFontSizeBody, fontWeight: kFontWeightSemiBold, fontFamily: 'Inter',
                    color: isDeleted ? const Color(0xFF94A3B8) : const Color(0xFF0F172A)),
                  overflow: TextOverflow.ellipsis)),
                if (isDeleted) ...[
                  const SizedBox(width: 6),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                    child: const Text('DELETED', style: TextStyle(fontSize: 8, fontWeight: kFontWeightBold, color: Color(0xFFEF4444), fontFamily: 'Inter'))),
                ],
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Flexible(child: Text(inst['tradingsymbol'] ?? '', style: TextStyle(fontSize: kFontSizeCaption,
                  color: isDeleted ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8), fontFamily: 'Inter', fontWeight: kFontWeightMedium, letterSpacing: 0.3),
                  overflow: TextOverflow.ellipsis)),
                if ((inst['lot_size'] ?? 1) > 0) ...[
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('·', style: TextStyle(color: Color(0xFFCBD5E1)))),
                  Text('LOT ${inst['lot_size'] ?? 1}', style: TextStyle(fontSize: kFontSizeCaption,
                    color: isDeleted ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8), fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                ],
                if (inst['expiry'] != null) ...[
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('·', style: TextStyle(color: Color(0xFFCBD5E1)))),
                  Text(_formatExpiry(inst['expiry']), style: TextStyle(fontSize: kFontSizeCaption,
                    color: isDeleted ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8), fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                ],
              ]),
            ]),
          ),
          // Actions: Toggle + Delete/Restore
          if (!isDeleted) ...[
            GestureDetector(
              onTap: () => _toggleEnabled(inst),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 40, height: 24, padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: enabled ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(12)),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 200),
                  alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _deleteInstrument(inst),
              child: Container(width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444))),
            ),
          ] else ...[
            GestureDetector(
              onTap: () => _restoreInstrument(inst),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(8)),
                child: const Text('Restore', style: TextStyle(color: Colors.white, fontSize: kFontSizeCaption, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
