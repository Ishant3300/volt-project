import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class FreshStoplossLimitView extends StatefulWidget {
  const FreshStoplossLimitView({super.key});
  @override
  State<FreshStoplossLimitView> createState() => _FreshStoplossLimitViewState();
}

class _FreshStoplossLimitViewState extends State<FreshStoplossLimitView> {
  String? _selectedExchange;
  final List<String> _exchanges = [
    'NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'GLOBAL', 'SGX'
  ];
  List<Map<String, dynamic>> _limits = [];
  bool _isLoading = false;
  bool _hasInitialized = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized && _selectedExchange == null) {
        setState(() {
          _selectedExchange = _exchanges.first;
          _hasInitialized = true;
        });
        _fetchLimits();
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchLimits() async {
    if (_selectedExchange == null) return;
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final effectiveExchange = _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange;
      final res = await ApiService(backendUrl).get(
        '/admin/fresh-stoploss-limits?exchange_name=$effectiveExchange&limit=1000',
        token: token,
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true) {
          setState(() => _limits = List<Map<String, dynamic>>.from(body['data'] ?? []));
        }
      }
    } catch (e) {
      log('Error fetching fresh stoploss limits: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _limits;
    final q = _searchQuery.toLowerCase();
    return _limits.where((l) => (l['raw_name'] ?? '').toString().toLowerCase().contains(q)).toList();
  }

  void _showBulkCreateDialog() {
    final timeCtrl = TextEditingController(text: '30');
    final priceCtrl = TextEditingController(text: '100');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Set Limits for $_selectedExchange',
            style: const TextStyle(fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, fontSize: kFontSizeSectionHeader)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('This will create/update limits for ALL instruments in this segment.',
              style: TextStyle(fontSize: kFontSizeBodySmall, color: Color(0xFF94A3B8), fontFamily: kFontFamily)),
          const SizedBox(height: 14),
          _dialogField(timeCtrl, 'Time (minutes)', 'e.g. 30'),
          const SizedBox(height: 10),
          _dialogField(priceCtrl, 'Price Offset', 'e.g. 100'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await _bulkCreate(int.tryParse(timeCtrl.text) ?? 0, double.tryParse(priceCtrl.text) ?? 0);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(10)),
              child: const Text('Create', style: TextStyle(color: Colors.white, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, fontSize: kFontSizeBodySmall)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkCreate(int time, double price) async {
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final effectiveExchange = _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange;
      final res = await ApiService(backendUrl).post(
        '/admin/fresh-stoploss-limits/bulk-create',
        {'exchange_name': effectiveExchange, 'time_minutes': time, 'price_offset': price},
        token: token,
      );
      if (res.statusCode == 200 && mounted) {
        final body = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(body['message'] ?? 'Done'),
          backgroundColor: const Color(0xFF10B981),
        ));
        _fetchLimits();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBulkUpdateDialog() {
    final timeCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Bulk Update $_selectedExchange',
            style: const TextStyle(fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, fontSize: kFontSizeSectionHeader)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Update time and/or price for ALL instruments in this segment. Leave blank to keep current value.',
              style: TextStyle(fontSize: kFontSizeBodySmall, color: Color(0xFF94A3B8), fontFamily: kFontFamily)),
          const SizedBox(height: 14),
          _dialogField(timeCtrl, 'Time (minutes)', 'Leave blank to skip'),
          const SizedBox(height: 10),
          _dialogField(priceCtrl, 'Price Offset', 'Leave blank to skip'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await _bulkUpdate(int.tryParse(timeCtrl.text), double.tryParse(priceCtrl.text));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(10)),
              child: const Text('Update All', style: TextStyle(color: Colors.white, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, fontSize: kFontSizeBodySmall)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _bulkUpdate(int? time, double? price) async {
    if (time == null && price == null) return;
    setState(() => _isLoading = true);
    try {
      final token = await SecureStorageService().getToken();
      final effectiveExchange = _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange;
      final body = <String, dynamic>{'exchange_name': effectiveExchange};
      if (time != null) body['time_minutes'] = time;
      if (price != null) body['price_offset'] = price;
      final res = await ApiService(backendUrl).put('/admin/fresh-stoploss-limits/bulk-update', body, token: token);
      if (res.statusCode == 200 && mounted) {
        final respBody = jsonDecode(res.body);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(respBody['message'] ?? 'Updated'), backgroundColor: const Color(0xFF10B981)));
        _fetchLimits();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final timeCtrl = TextEditingController(text: '${item['time_minutes'] ?? 0}');
    final priceCtrl = TextEditingController(text: '${item['price_offset'] ?? 0}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(item['raw_name'] ?? '',
            style: const TextStyle(fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, fontSize: kFontSizeSectionHeader, color: kBrandPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dialogField(timeCtrl, 'Time (minutes)', ''),
          const SizedBox(height: 10),
          _dialogField(priceCtrl, 'Price Offset', ''),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF94A3B8), fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          GestureDetector(
            onTap: () async {
              Navigator.pop(ctx);
              await _updateSingle(item['_id'], int.tryParse(timeCtrl.text) ?? 0, double.tryParse(priceCtrl.text) ?? 0);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(10)),
              child: const Text('Save', style: TextStyle(color: Colors.white, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, fontSize: kFontSizeBodySmall)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateSingle(String id, int time, double price) async {
    try {
      final token = await SecureStorageService().getToken();
      final res = await ApiService(backendUrl).put(
        '/admin/fresh-stoploss-limits/$id',
        {'time_minutes': time, 'price_offset': price},
        token: token,
      );
      if (res.statusCode == 200 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated'), backgroundColor: Color(0xFF10B981)));
        _fetchLimits();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFEF4444)));
    }
  }

  Widget _dialogField(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
      style: const TextStyle(fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        filled: true, fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBrandPrimary, width: 1.5)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(child: Column(children: [
        // Header
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(width: 40, height: 40,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
              child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium)),
          ),
          const SizedBox(width: 12),
          const Text('Fresh Stop-Loss Limits', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
        ])),

        // Exchange chips
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SizedBox(height: 36,
          child: ListView.separated(
            scrollDirection: Axis.horizontal, itemCount: _exchanges.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final ex = _exchanges[i];
              final sel = ex == _selectedExchange;
              return GestureDetector(
                onTap: () { setState(() => _selectedExchange = ex); _fetchLimits(); },
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 16), alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? kBrandPrimary : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: sel ? null : Border.all(color: const Color(0xFFE2E8F0))),
                  child: Text(ex, style: TextStyle(color: sel ? Colors.white : const Color(0xFF64748B), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
              );
            },
          ),
        )),
        const SizedBox(height: 12),

        // Action buttons
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          Expanded(child: GestureDetector(
            onTap: _showBulkCreateDialog,
            child: Container(height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(12)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add, color: Colors.white, size: 18), SizedBox(width: 6),
                Text('Create All', style: TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
              ])),
          )),
          const SizedBox(width: 8),
          Expanded(child: GestureDetector(
            onTap: _limits.isEmpty ? null : _showBulkUpdateDialog,
            child: Container(height: 42, alignment: Alignment.center,
              decoration: BoxDecoration(color: _limits.isEmpty ? const Color(0xFFE2E8F0) : Colors.white, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _limits.isEmpty ? const Color(0xFFE2E8F0) : kBrandPrimary)),
              child: Text('Update All', style: TextStyle(color: _limits.isEmpty ? const Color(0xFF94A3B8) : kBrandPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold))),
          )),
        ])),
        const SizedBox(height: 12),

        // Search
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(height: 42,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
          child: TextField(
            controller: _searchCtrl, onChanged: (v) => setState(() => _searchQuery = v.trim()),
            style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
            decoration: const InputDecoration(
              hintText: 'Search instrument...', hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
              prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
              contentPadding: EdgeInsets.symmetric(vertical: 12), border: InputBorder.none)),
        )),
        const SizedBox(height: 6),

        // Count
        if (!_isLoading)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
              child: Text('${filtered.length} instruments', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)))),
        const SizedBox(height: 6),

        // List
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5))
          : filtered.isEmpty
            ? const Center(child: Text('No limits set. Tap "Create All" to initialize.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)))
            : RefreshIndicator(onRefresh: _fetchLimits, child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: filtered.length,
                itemBuilder: (_, i) => _buildLimitCard(filtered[i])))),
      ])),
    );
  }

  Widget _buildLimitCard(Map<String, dynamic> item) {
    final rawName = item['raw_name'] ?? '';
    final time = item['time_minutes'] ?? 0;
    final price = (item['price_offset'] as num?)?.toDouble() ?? 0;
    return GestureDetector(
      onTap: () => _showEditDialog(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rawName, style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeButtonText, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Row(children: [
              _valuePill('Time', '${time}min'),
              const SizedBox(width: 8),
              _valuePill('Price', price.toStringAsFixed(0)),
            ]),
          ])),
          const Icon(Icons.edit_outlined, size: kIconSizeDefault, color: Color(0xFF94A3B8)),
        ]),
      ),
    );
  }

  Widget _valuePill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label: ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
        Text(value, style: const TextStyle(color: Color(0xFF334155), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
      ]),
    );
  }
}
