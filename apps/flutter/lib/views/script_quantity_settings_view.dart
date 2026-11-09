import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import '../models/script_quantity.dart';
import '../models/user.dart';
import 'add_script_qty_to_exchange_view.dart';
import '../utils/contants.dart';

class ScriptQuantitySettingsView extends StatefulWidget {
  final String? ownerId;
  final String? ownerType; // 'Master' or 'User'

  const ScriptQuantitySettingsView({super.key, this.ownerId, this.ownerType});

  @override
  State<ScriptQuantitySettingsView> createState() => _ScriptQuantitySettingsViewState();
}

class _ScriptQuantitySettingsViewState extends State<ScriptQuantitySettingsView> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _maxQtyController = TextEditingController();
  final TextEditingController _brkQtyController = TextEditingController();
  final SecureStorageService _storage = SecureStorageService();
  
  String? _selectedExchange;
  final _exchanges = ['NFO-FUT', 'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT', 'GLOBAL'];
  List<ScriptQuantity> _scriptItems = [];
  List<ScriptQuantity> _filteredItems = [];
  Set<String> _selectedIds = {};
  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isAdmin = false;
  /// The last load for the chosen exchange did not succeed — the list on
  /// screen can't be trusted (CREATE is refused until it loads).
  bool _loadFailed = false;

  /// A client's list: per exchange (display name), whether his limits are
  /// read as 'lots' or 'qty' — the same rule the server applies to his orders
  /// (utils/comexLots.js tradingModeFor: COMEX always lots; T/O = quantity;
  /// Lot = lots). 'off' = exchange not enabled for him. Null until loaded.
  Map<String, String>? _clientUnits;

  Future<void> _loadClientUnits() async {
    if (widget.ownerType != 'User' || widget.ownerId == null) return;
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final res = await AdminService(apiService).getUserById(widget.ownerId!);
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body)['data'];
      if (data is! Map<String, dynamic>) return;
      final user = User.fromJson(data);
      final units = <String, String>{};
      for (final ex in user.exchangesAllowed) {
        final name = ex.exchangeName == 'INDICES' ? 'GLOBAL' : ex.exchangeName;
        units[name] = !(ex.turnover || ex.lot)
            ? 'off'
            : name == 'COMEX-FUT'
                ? 'lots'
                : ex.turnover
                    ? 'qty'
                    : 'lots';
      }
      if (mounted) setState(() => _clientUnits = units);
    } catch (e) {
      log('⚠️ Could not load the client\'s lot/qty settings: $e');
    }
  }

  /// "lots" / "qty" for the input hints ("lots or qty" when it depends on the client).
  String get _unitShort {
    if (widget.ownerType != 'User') return 'lots or qty';
    final u = _clientUnits?[_selectedExchange];
    return u == 'lots' || u == 'qty' ? u! : 'lots or qty';
  }

  /// One line under the exchange picker saying how these numbers are read.
  String? get _unitNote {
    final ex = _selectedExchange;
    if (ex == null) return null;
    if (widget.ownerType != 'User') {
      return 'Each client reads these limits as lots or quantity per his own Lot / T-O setting on $ex (COMEX: always lots).';
    }
    final u = _clientUnits?[ex];
    if (_clientUnits == null) return null;
    if (u == 'lots') return 'Limits for this client on $ex are in LOTS (Lot mode).';
    if (u == 'qty') return 'Limits for this client on $ex are in QUANTITY (T/O mode).';
    return '$ex is not enabled for this client.';
  }

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadScriptQuantities();
    _loadClientUnits();
  }

  Future<void> _checkUserRole() async {
    try {
      final role = await _storage.getRole();
      setState(() {
        _isAdmin = role == 'ADMIN';
      });
    } catch (e) {
      log('❌ Error checking user role: $e');
    }
  }

  Future<void> _loadScriptQuantities() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      log('🔄 Loading script quantities');
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);
      
      final effectiveExchange = _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange!;
      final response = _selectedExchange != null
          ? await adminService.getScriptQuantityByExchange(exchangeName: effectiveExchange, limit: 500, ownerId: widget.ownerId)
          : await adminService.getAllScriptQuantities(limit: 100, ownerId: widget.ownerId);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // The exchange endpoint returns data directly as a list, not nested
          final dynamic rawData = data['data'];
          final List<dynamic> items;
          if (rawData is List) {
            items = rawData;
          } else if (rawData is Map) {
            items = rawData['items'] ?? rawData['script_quantities'] ?? [];
          } else {
            items = [];
          }
          setState(() {
            _scriptItems = items.map((json) => ScriptQuantity.fromJson(json)).toList();
            // Keep the search box's filter (it used to show every script while
            // the box still said e.g. "RELIANCE"), and start with nothing ticked.
            _filteredItems = _searchFiltered(_searchController.text);
            _selectedIds.clear();
            _isLoading = false;
          });
          log('✅ Loaded ${_scriptItems.length} script quantities');
          return;
        }
      }
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      log('❌ Error loading script quantities: $e');
      if (mounted) {
        setState(() {
          _loadFailed = true;
          _isLoading = false;
        });
      }
    }
  }

  List<ScriptQuantity> _searchFiltered(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _scriptItems;
    return _scriptItems.where((item) => item.scriptName.toLowerCase().contains(q)).toList();
  }

  void _filterScripts(String query) {
    setState(() {
      _filteredItems = _searchFiltered(query);
      // A tick on a script the search hides would still get the new value on
      // APPLY without the admin seeing it — only visible scripts stay ticked.
      final visible = _filteredItems.map((s) => s.id).toSet();
      _selectedIds.retainWhere(visible.contains);
    });
  }

  /// Who a delete of this row reaches (the server's cascade), in words.
  String get _deleteReach {
    if (widget.ownerType == 'Master') return 'for this master and his direct clients';
    if (widget.ownerType == 'User') return 'for this client';
    return 'for EVERY master and client on the platform';
  }

  /// Block or delete? (9 Nov 2026) Deleting the row removes the limit, and a
  /// script with no limit row has NO quantity limit at all — the old dialog
  /// never said so. Blocking (Max 0) is what "remove this script" usually
  /// means: no new positions, existing ones can still be closed.
  Future<String?> _askRemove(ScriptQuantity item) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${item.scriptName}"?',
            style: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w600)),
        content: Text(
          'Block (recommended): sets Max 0 — no new positions; existing positions can still be closed.\n\n'
          'Delete: removes the limit $_deleteReach — the script then has NO quantity limit at all.',
          style: const TextStyle(fontFamily: kFontFamily),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Delete (no limit)', style: TextStyle(color: kColorSell)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'block'),
            child: const Text('Block (set 0)', style: TextStyle(color: kBrandPrimary)),
          ),
        ],
      ),
    );
  }

  void _snack(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: error ? kColorSell : kColorBuy),
    );
  }

  String _serverMessage(dynamic response, String fallback) {
    try {
      final m = jsonDecode(response.body)['message'];
      if (m is String && m.isNotEmpty) return m;
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }

  /// Max 0 / Breakup 0 for this row (the server applies its own cascade).
  Future<void> _blockScript(ScriptQuantity item) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await AdminService(apiService).updateScriptQuantity(id: item.id, maxQty: 0, brkQty: 0);
      if (response.statusCode == 200) {
        _snack('"${item.scriptName}" blocked (Max 0)');
        _loadScriptQuantities();
      } else {
        _snack(_serverMessage(response, 'Block failed'), error: true);
      }
    } catch (e) {
      _snack('Error: $e', error: true);
    }
  }

  /// Deletes on the server; true only when it really went through.
  Future<bool> _deleteOnServer(ScriptQuantity item) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await AdminService(apiService).deleteScriptQuantity(item.id);
      if (response.statusCode == 200) {
        _snack('"${item.scriptName}" deleted — it now has no quantity limit $_deleteReach');
        return true;
      }
      _snack(_serverMessage(response, 'Delete failed'), error: true);
    } catch (e) {
      _snack('Error: $e', error: true);
    }
    return false;
  }

  void _removeFromList(ScriptQuantity item) {
    setState(() {
      _scriptItems.removeWhere((s) => s.id == item.id);
      _filteredItems.removeWhere((s) => s.id == item.id);
      _selectedIds.remove(item.id);
    });
  }

  /// Swipe or icon: ask, then block or delete. Returns true when the row was
  /// deleted on the server (so a swipe may dismiss it).
  Future<bool> _removeScript(ScriptQuantity item) async {
    final choice = await _askRemove(item);
    if (!mounted || choice == null) return false;
    if (choice == 'block') {
      await _blockScript(item);
      return false;
    }
    return _deleteOnServer(item);
  }

  Future<void> _applyUpdates() async {
    // Only scripts the admin can see in the list (see _filterScripts).
    final visible = {for (final s in _filteredItems) s.id: s};
    final targets = _selectedIds.where(visible.containsKey).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one script')),
      );
      return;
    }

    final maxQty = double.tryParse(_maxQtyController.text.trim());
    final brkQty = double.tryParse(_brkQtyController.text.trim());

    if (maxQty == null && brkQty == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one value to update')),
      );
      return;
    }
    // Whole numbers only (9 Nov 2026): 0.5 used to be cut to 0 — which
    // BLOCKS the script — without a word.
    for (final v in [maxQty, brkQty]) {
      if (v != null && (v < 0 || v != v.roundToDouble())) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Use a whole number of $_unitShort (0 or more) — ${v.toString()} is not allowed'),
          backgroundColor: kColorSell,
        ));
        return;
      }
    }

    // Confirm the exact scope first — one tap on "select all" used to change
    // every script of the account with no warning.
    final names = targets.map((id) => visible[id]!.scriptName).toList();
    final shown = names.take(6).join(', ') + (names.length > 6 ? ' +${names.length - 6} more' : '');
    final values = [
      if (maxQty != null) 'Max Qty ${maxQty.toInt()}',
      if (brkQty != null) 'Breakup ${brkQty.toInt()}',
    ].join(' · ');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Change ${targets.length} script${targets.length == 1 ? '' : 's'}?',
          style: const TextStyle(fontFamily: kFontFamily, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '$values\n\n$shown',
          style: const TextStyle(fontFamily: kFontFamily),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Apply to ${targets.length}', style: const TextStyle(color: kBrandPrimary)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      log('💾 Updating ${targets.length} script quantities');
      final apiService = Provider.of<ApiService>(context, listen: false);
      final adminService = AdminService(apiService);

      // A few at a time, so a long list finishes quickly instead of one by one.
      int successCount = 0;
      for (var i = 0; i < targets.length; i += 5) {
        final batch = targets.skip(i).take(5);
        final responses = await Future.wait(batch.map((id) => adminService.updateScriptQuantity(
              id: id,
              maxQty: maxQty?.toInt(),
              brkQty: brkQty?.toInt(),
            )));
        successCount += responses.where((r) => r.statusCode == 200).length;
      }

      log('✅ Updated $successCount of ${targets.length} script quantities');
      if (mounted) {
        final allDone = successCount == targets.length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allDone
                ? 'Updated $successCount script quantit${successCount == 1 ? 'y' : 'ies'}'
                : 'Updated only $successCount of ${targets.length} — check the list and try again'),
            backgroundColor: allDone ? null : kColorSell,
          ),
        );
        _selectedIds.clear();
        _maxQtyController.clear();
        _brkQtyController.clear();
        _loadScriptQuantities();
      }
    } catch (e) {
      log('❌ Error updating script quantities: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _maxQtyController.dispose();
    _brkQtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            ColoredBox(
              color: kTopBarBg,
              child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back, color: kTopBarFg),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Script Quantity Setting',
                        style: TextStyle(
                          color: kTopBarFg,
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold,
                        ),
                      ),
                    ],
                  ),
                  if (_isAdmin)
                    GestureDetector(
                      onTap: () {
                        if (_selectedExchange == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an exchange first')));
                          return;
                        }
                        // "Existing" is decided from the FULL list as loaded —
                        // not the search-filtered one, and never while loading
                        // or after a failed load: a "new" CREATE resets every
                        // script of the exchange to the default limits (9 Nov 2026).
                        if (_isLoading || _loadFailed) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text('The list has not loaded — wait or reopen, then try again')));
                          return;
                        }
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => AddScriptQtyToExchangeView(
                            exchange: _selectedExchange!,
                            isExistingGroup: _scriptItems.isNotEmpty,
                            ownerId: widget.ownerId,
                            ownerType: widget.ownerType,
                          ),
                        )).then((_) => _loadScriptQuantities());
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: ShapeDecoration(
                          color: kBrandPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        child: const Text(
                          'CREATE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: kFontSizeBody,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),

            // Exchange Selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedExchange,
                    hint: const Text('Select Exchange', style: TextStyle(color: kColorTextMuted, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)),
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: kColorTextMuted),
                    style: const TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
                    items: _exchanges.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) {
                      setState(() => _selectedExchange = v);
                      _loadScriptQuantities();
                    },
                  ),
                ),
              ),
            ),
            if (_unitNote != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  _unitNote!,
                  style: const TextStyle(color: kColorTextMuted, fontSize: kFontSizeCaption, fontFamily: kFontFamily),
                ),
              ),
            const SizedBox(height: 8),

            // Search Bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: ShapeDecoration(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(width: 1, color: Color(0xFFD1D1D6)),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: kIconSizeLarge, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterScripts,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search script',
                        hintStyle: TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: kFontSizeSectionHeader,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightRegular,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (_selectedIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '${_selectedIds.length} of ${_filteredItems.length} selected',
                  style: const TextStyle(
                    color: kBrandPrimary,
                    fontSize: kFontSizeBodySmall,
                    fontFamily: kFontFamily,
                    fontWeight: kFontWeightMedium,
                  ),
                ),
              ),

            // Action Buttons Row
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_selectedIds.length == _filteredItems.length) {
                          _selectedIds.clear();
                        } else {
                          _selectedIds = _filteredItems.map((item) => item.id).toSet();
                        }
                      });
                    },
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _selectedIds.length == _filteredItems.length && _filteredItems.isNotEmpty
                            ? kBrandPrimary
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _selectedIds.length == _filteredItems.length && _filteredItems.isNotEmpty
                              ? kBrandPrimary
                              : const Color(0xFFCBD5E1),
                          width: 1.5,
                        ),
                      ),
                      child: _selectedIds.length == _filteredItems.length && _filteredItems.isNotEmpty
                          ? const Icon(Icons.check, color: Colors.white, size: 12)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _maxQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Max ($_unitShort)',
                          hintStyle: const TextStyle(
                            color: kColorTextPrimary,
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightRegular,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightRegular,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: ShapeDecoration(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: TextField(
                        controller: _brkQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Breakup ($_unitShort)',
                          hintStyle: const TextStyle(
                            color: kColorTextPrimary,
                            fontSize: kFontSizeSubtitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightRegular,
                          ),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizeSubtitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightRegular,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isUpdating ? null : _applyUpdates,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: ShapeDecoration(
                          color: _isUpdating ? const Color(0xFF8E8E93) : kBrandPrimary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isUpdating
                            ? const Center(
                                child: SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Text(
                                'APPLY',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: kFontSizeSubtitle,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightMedium,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Script Items List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: kBrandPrimary),
                    )
                  : _filteredItems.isEmpty
                      ? const Center(
                          child: Text(
                            'No script quantities found',
                            style: TextStyle(
                              color: Color(0xFF8E8E93),
                              fontSize: kFontSizeSectionHeader,
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            final isSelected = _selectedIds.contains(item.id);

                            return Dismissible(
                              key: Key(item.id),
                              direction: _isAdmin ? DismissDirection.endToStart : DismissDirection.none,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                color: kColorSell,
                                child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
                              ),
                              // Block or delete is decided (and done on the server)
                              // before the row is dismissed — a failed delete keeps it.
                              confirmDismiss: (_) => _removeScript(item),
                              onDismissed: (_) => _removeFromList(item),
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedIds.remove(item.id);
                                    } else {
                                      _selectedIds.add(item.id);
                                    }
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    border: Border(
                                      bottom: BorderSide(width: 1, color: Color(0xFFC7C7CC)),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20,
                                        height: 20,
                                        decoration: BoxDecoration(
                                          color: isSelected ? kBrandPrimary : Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isSelected ? kBrandPrimary : const Color(0xFFCBD5E1),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: isSelected
                                            ? const Icon(Icons.check, color: Colors.white, size: 12)
                                            : null,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.scriptName,
                                              style: const TextStyle(
                                                color: Color(0xFF334155),
                                                fontSize: kFontSizeBodySmall,
                                                fontFamily: kFontFamily,
                                                fontWeight: kFontWeightMedium,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Opacity(
                                                    opacity: 0.80,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(0xFFE5E5EA),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Text(
                                                            'Lot ',
                                                            style: TextStyle(
                                                              color: kColorTextPrimary,
                                                              fontSize: kFontSizeCaption,
                                                              fontFamily: kFontFamily,
                                                              fontWeight: kFontWeightRegular,
                                                            ),
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              item.lotSize.toStringAsFixed(0),
                                                              style: const TextStyle(
                                                                color: kColorTextPrimary,
                                                                fontSize: kFontSizeSubtitle,
                                                                fontFamily: kFontFamily,
                                                                fontWeight: kFontWeightMedium,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Opacity(
                                                    opacity: 0.80,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(0xFFE5E5EA),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Text(
                                                            'Brk ',
                                                            style: TextStyle(
                                                              color: kColorTextPrimary,
                                                              fontSize: kFontSizeCaption,
                                                              fontFamily: kFontFamily,
                                                              fontWeight: kFontWeightRegular,
                                                            ),
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              item.brkQty.toStringAsFixed(0),
                                                              style: const TextStyle(
                                                                color: kColorTextPrimary,
                                                                fontSize: kFontSizeSubtitle,
                                                                fontFamily: kFontFamily,
                                                                fontWeight: kFontWeightMedium,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Expanded(
                                                  child: Opacity(
                                                    opacity: 0.80,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: ShapeDecoration(
                                                        color: const Color(0xFFE5E5EA),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          const Text(
                                                            'Max ',
                                                            style: TextStyle(
                                                              color: kColorTextPrimary,
                                                              fontSize: kFontSizeCaption,
                                                              fontFamily: kFontFamily,
                                                              fontWeight: kFontWeightRegular,
                                                            ),
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              item.maxQty.toStringAsFixed(0),
                                                              style: const TextStyle(
                                                                color: kColorTextPrimary,
                                                                fontSize: kFontSizeSubtitle,
                                                                fontFamily: kFontFamily,
                                                                fontWeight: kFontWeightMedium,
                                                              ),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Delete icon button (admin only, alternative to swipe)
                                      if (_isAdmin)
                                        GestureDetector(
                                          onTap: () async {
                                            if (await _removeScript(item)) _removeFromList(item);
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(Icons.delete_outline, size: 18, color: kColorSell),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
