import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'group_quantity_lot_detail_view.dart';
import 'add_instrument_to_lot_view.dart';
import '../utils/contants.dart';
import 'package:stocker/widgets/page_wash.dart';

class GroupQuantityView extends StatefulWidget {
  const GroupQuantityView({super.key});
  @override
  State<GroupQuantityView> createState() => _GroupQuantityViewState();
}

class _GroupQuantityViewState extends State<GroupQuantityView> {
  String? _selectedExchange;
  final List<String> _exchanges = [
    'NFO-FUT',
    'NFO-OPT',
    'MCX-FUT',
    'MCX-OPT',
    'COMEX-FUT',
    'GLOBAL'
  ];
  Map<String, int> _lotCounts = {};
  bool _isLoading = false;
  /// The group list for this exchange did not load — creating a group is
  /// refused until it does (the duplicate-name check needs the list).
  bool _loadFailed = false;
  bool _hasInitialized = false;
  bool _isAdmin = false;
  final SecureStorageService _storage = SecureStorageService();

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_hasInitialized && _selectedExchange == null) {
        setState(() {
          _selectedExchange = _exchanges.first;
          _hasInitialized = true;
        });
        _fetchGroupQuantities();
      }
    });
  }

  Future<void> _checkUserRole() async {
    final role = await _storage.getRole();
    setState(() => _isAdmin = role == 'ADMIN');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasInitialized && _selectedExchange != null) _fetchGroupQuantities();
  }

  /// Every group of the selected exchange with its script count — per
  /// exchange and per group (9 Nov 2026). It used to read the newest 1,000
  /// group rows of ALL exchanges (6,494 exist), so older groups were missing
  /// or showed short counts.
  Future<void> _fetchGroupQuantities() async {
    if (_selectedExchange == null) return;
    log('📊 Fetching group quantities for: $_selectedExchange');
    setState(() {
      _isLoading = true;
      _loadFailed = false;
      _lotCounts = {};
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      final effectiveExchange =
          _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange!;
      final namesRes = await adminService.getLotNamesByExchange(effectiveExchange);
      final namesBody = jsonDecode(namesRes.body);
      if (namesRes.statusCode != 200 || namesBody['success'] != true) {
        if (mounted) setState(() => _loadFailed = true);
        return;
      }
      final names = List<String>.from(namesBody['data'] ?? const [])..sort();
      final counts = await Future.wait(names.map((name) async {
        final r = await adminService.getGroupInstruments(
            exchangeName: effectiveExchange, lotName: name, limit: 1);
        if (r.statusCode != 200) return -1;
        final total = jsonDecode(r.body)['data']?['total'];
        return total is num ? total.toInt() : -1;
      }));
      if (counts.contains(-1) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Some group counts could not be loaded — pull down to retry')));
      }
      if (mounted) {
        setState(() {
          _lotCounts = {
            for (var i = 0; i < names.length; i++) names[i]: counts[i] < 0 ? 0 : counts[i]
          };
        });
      }
    } catch (e) {
      log('❌ Error: $e');
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showCreateLotDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Create New Lot',
            style: TextStyle(
                fontFamily: kFontFamily,
                fontWeight: kFontWeightSemiBold,
                fontSize: kFontSizeSectionHeader)),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Enter a name for the new lot.',
                  style: TextStyle(
                      fontSize: kFontSizeBodySmall,
                      color: kColorTextMuted,
                      fontFamily: kFontFamily)),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                style: const TextStyle(
                    fontSize: kFontSizeBody,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightMedium),
                decoration: InputDecoration(
                  hintText: 'Lot name',
                  hintStyle: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: kFontSizeBodySmall,
                      fontFamily: kFontFamily),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                          color: kBrandPrimary, width: 1.5)),
                ),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(
                      color: kColorTextMuted,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold))),
          GestureDetector(
            onTap: () {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              // A NEW group with an existing name used to reset that whole
              // group's limits to the defaults (9 Nov 2026) — refused here;
              // the list must have loaded to check.
              if (_isLoading || _loadFailed) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('The group list has not loaded — try again in a moment')));
                return;
              }
              final clash = _lotCounts.keys
                  .where((k) => k.toLowerCase() == name.toLowerCase())
                  .toList();
              if (clash.isNotEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('A group named "${clash.first}" already exists on ${_selectedExchange!} — open it from the list to edit it'),
                    backgroundColor: kColorSell));
                return;
              }
              Navigator.pop(ctx);
              Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AddInstrumentToLotView(
                              exchange: _selectedExchange!,
                              lotName: name,
                              isExistingGroup: false)))
                  .then((_) => _fetchGroupQuantities());
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                  color: kBrandPrimary,
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('Next',
                  style: TextStyle(
                      color: Colors.white,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold,
                      fontSize: kFontSizeBodySmall)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      body: PageWash(child: SafeArea(
          child: Column(children: [
        // Header
        ColoredBox(
          color: kTopBarBg,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: kTopBarTile,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.02),
                              blurRadius: 4,
                              offset: const Offset(0, 2))
                        ]),
                    child: const Icon(Icons.arrow_back,
                        color: kTopBarFg, size: kIconSizeMedium)),
              ),
              const SizedBox(width: 12),
              const Text('Group Quantity',
                  style: TextStyle(
                      color: kTopBarFg,
                      fontSize: kFontSizeViewTitle,
                      fontFamily: kFontFamily,
                      fontWeight: kFontWeightSemiBold)),
            ])),
        ),

        // Exchange chips
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _exchanges.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final ex = _exchanges[i];
                  final sel = ex == _selectedExchange;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedExchange = ex);
                      _fetchGroupQuantities();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? kBrandPrimary : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: sel
                            ? null
                            : Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(ex,
                          style: TextStyle(
                              color:
                                  sel ? Colors.white : const Color(0xFF64748B),
                              fontSize: kFontSizeBodySmall,
                              fontFamily: kFontFamily,
                              fontWeight: kFontWeightSemiBold)),
                    ),
                  );
                },
              ),
            )),
        const SizedBox(height: 12),

        // Create button (admin only)
        if (_isAdmin && _selectedExchange != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: _showCreateLotDialog,
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: kBrandPrimary,
                      borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: Colors.white, size: 18),
                        SizedBox(width: 6),
                        Text('Create New Lot',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: kFontSizeBody,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightSemiBold)),
                      ]),
                ),
              )),
        if (_isAdmin && _selectedExchange != null) const SizedBox(height: 12),

        // Count label
        if (!_isLoading && _lotCounts.isNotEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${_lotCounts.length} lots',
                      style: const TextStyle(
                          color: kColorTextMuted,
                          fontSize: kFontSizeNavLabel,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightMedium)))),
        const SizedBox(height: 6),

        // Lots list
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: kBrandPrimary, strokeWidth: 2.5))
              : _lotCounts.isEmpty
                  ? Center(
                      child: Text(
                          _isAdmin
                              ? 'No lots found. Create one!'
                              : 'No lots available',
                          style: const TextStyle(
                              color: kColorTextMuted,
                              fontSize: kFontSizeBodySmall,
                              fontFamily: kFontFamily)))
                  : RefreshIndicator(
                      onRefresh: _fetchGroupQuantities,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _lotCounts.length,
                        itemBuilder: (_, i) {
                          final lotName = _lotCounts.keys.elementAt(i);
                          final count = _lotCounts[lotName] ?? 0;
                          return GestureDetector(
                            onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            GroupQuantityLotDetailView(
                                                exchange: _selectedExchange!,
                                                lotName: lotName)))
                                .then((_) => _fetchGroupQuantities()),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                        color: kColorTextPrimary
                                            .withValues(alpha: 0.02),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2))
                                  ]),
                              child: Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(lotName,
                                          style: const TextStyle(
                                              color: kBrandPrimary,
                                              fontSize: kFontSizeButtonText,
                                              fontFamily: kFontFamily,
                                              fontWeight: kFontWeightSemiBold,
                                              letterSpacing: -0.3)),
                                      const SizedBox(height: 4),
                                      Text('$count instruments',
                                          style: const TextStyle(
                                              color: kColorTextMuted,
                                              fontSize: kFontSizeSubtitle,
                                              fontFamily: kFontFamily)),
                                    ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(8)),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text('VIEW',
                                            style: TextStyle(
                                                color: kBrandPrimary,
                                                fontSize: kFontSizeNavLabel,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightBold,
                                                letterSpacing: 0.3)),
                                        SizedBox(width: 2),
                                        Icon(Icons.chevron_right,
                                            size: kIconSizeDefault, color: kBrandPrimary),
                                      ]),
                                ),
                              ]),
                            ),
                          );
                        },
                      )),
        ),
      ]))),
    );
  }
}
