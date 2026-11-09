import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/admin_service.dart';
import '../services/sercure_storage_service.dart';
import 'add_brokerage_to_exchange_view.dart';
import '../utils/contants.dart';
import 'package:stocker/widgets/page_wash.dart';

class BrokerageSettingsView extends StatefulWidget {
  final String? ownerId;
  final String? ownerType; // 'Master' or 'User'

  const BrokerageSettingsView({super.key, this.ownerId, this.ownerType});
  @override
  State<BrokerageSettingsView> createState() => _BrokerageSettingsViewState();
}

class _BrokerageSettingsViewState extends State<BrokerageSettingsView> {
  final _amountCtrl = TextEditingController();
  String? _selectedExchange;
  String _selectedType = 'TURNOVER WISE';
  final _exchanges = [
    'NFO-FUT',
    'NFO-OPT',
    'MCX-FUT',
    'MCX-OPT',
    'COMEX-FUT',
    'GLOBAL'
  ];
  final _types = ['TURNOVER WISE', 'LOT WISE'];
  static const _lotWiseSegments = {'NFO-OPT', 'MCX-FUT', 'MCX-OPT', 'COMEX-FUT'};
  List<Map<String, dynamic>> _items = [];
  Map<String, bool> _selected = {};
  bool _isLoading = false;
  bool _isApplying = false;
  bool _isAdmin = false;

  /// Opened for one account (a master's or client's overview page): only that
  /// account's OWN rates are ever shown or edited here — never the platform
  /// default rows (9 Nov 2026: with no own rows of the forced type the list
  /// used to load the defaults, and Apply then rewrote the platform defaults).
  bool get _accountScoped => widget.ownerId != null;

  /// The account has no rates at all on this exchange (offer to create them).
  bool _noAccountRates = false;

  /// Set when the account's rates on this exchange are the other type than
  /// this exchange's usual one (e.g. COMEX-FUT stored as TURNOVER WISE).
  String? _typeNote;

  /// The last load failed (shown instead of an empty list).
  String? _loadError;

  String get _effectiveExchange =>
      _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange!;

  String get _usualType => _lotWiseSegments.contains(_selectedExchange)
      ? 'LOT WISE'
      : 'TURNOVER WISE';

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkRole() async {
    final role = await SecureStorageService().getRole();
    setState(() => _isAdmin = role == 'ADMIN');
  }

  /// The rows for this exchange and type — the account's own when the screen
  /// is account-scoped, else the platform defaults. Null on error.
  Future<List<dynamic>?> _getRows(String type) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final token = await SecureStorageService().getToken();
    final userQuery = _accountScoped ? '&user_id=${widget.ownerId}' : '';
    final res = await apiService.get(
      '/admin/brokerage-settings/exchange/$_effectiveExchange?type=${Uri.encodeComponent(type)}&limit=2000$userQuery',
      token: token,
    );
    final data = jsonDecode(res.body);
    if (res.statusCode == 200 && data['success'] == true) {
      return (data['data']?['items'] as List<dynamic>?) ?? [];
    }
    _loadError = (data is Map && data['message'] is String)
        ? data['message'] as String
        : 'Could not load rates (${res.statusCode})';
    return null;
  }

  Future<void> _fetch() async {
    if (_selectedExchange == null) return;
    setState(() {
      _isLoading = true;
      _items = [];
      _selected = {};
      _noAccountRates = false;
      _typeNote = null;
      _loadError = null;
    });
    try {
      List<dynamic>? items;
      if (!_accountScoped) {
        items = await _getRows(_selectedType);
      } else {
        // The account's own rows of this exchange's usual type; if it has
        // none, the account may hold the other type — show those (its real
        // rates). Never the platform defaults.
        var type = _usualType;
        items = await _getRows(type);
        if (items != null && items.isEmpty) {
          final other = type == 'LOT WISE' ? 'TURNOVER WISE' : 'LOT WISE';
          final otherItems = await _getRows(other);
          if (otherItems != null && otherItems.isNotEmpty) {
            items = otherItems;
            type = other;
            _typeNote = "This account's ${_selectedExchange!} rates are $other.";
          }
        }
        _selectedType = type;
        _noAccountRates = items != null && items.isEmpty;
      }
      if (items == null) return;
      final filtered = <Map<String, dynamic>>[
        for (final s in items)
          {
            'id': s['id'],
            'script_name': s['script_name'],
            'brk_value': s['brk_value'],
            'type': s['type'],
            'exchange_name': s['exchange_name'],
          }
      ];
      if (mounted) setState(() => _items = filtered);
    } catch (e) {
      log('❌ Error: $e');
      _loadError = 'Could not load rates: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Account-scoped, the account has no rates on this exchange yet: create
  /// them for THIS account (every script of the exchange at the typed value).
  /// The server refuses a value below the account's master's rate.
  Future<void> _createForAccount() async {
    if (!_accountScoped || _selectedExchange == null || _isApplying) return;
    final value = double.tryParse(_amountCtrl.text);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter the rate to create, then tap Create')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create rates for this account?'),
        content: Text(
            'Every ${_selectedExchange!} script for this account will be set to $value ($_selectedType). Platform default rates are not changed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isApplying = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final token = await SecureStorageService().getToken();
      final res = await apiService.post(
          '/admin/brokerage-settings/bulk-create',
          {
            'exchange_name': _effectiveExchange,
            'type': _selectedType,
            'default_brk_value': value,
            'user_id': widget.ownerId,
          },
          token: token);
      final body = jsonDecode(res.body);
      if (!mounted) return;
      final done = (res.statusCode == 200 || res.statusCode == 201) &&
          body['success'] == true;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(done
              ? 'Created ${body['data']?['inserted'] ?? ''} rate(s) for this account'
              : (body['message'] ?? 'Create failed (${res.statusCode})')),
          backgroundColor: done ? kColorBuy : kColorSell));
      if (done) {
        _amountCtrl.clear();
        await _fetch();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  Future<void> _apply() async {
    if (_selectedExchange == null || _isApplying) return;
    final value = double.tryParse(_amountCtrl.text);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid value')));
      return;
    }
    final scripts =
        _selected.entries.where((e) => e.value).map((e) => e.key).toList();
    if (scripts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select at least one script')));
      return;
    }
    // Account-scoped with no own rates: nothing to update here (see
    // _createForAccount) — never send rows that aren't this account's.
    if (_accountScoped && _noAccountRates) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This account has no rates here yet — use Create')));
      return;
    }
    setState(() => _isApplying = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final token = await SecureStorageService().getToken();

      // Collect IDs of selected items
      final ids = <String>[];
      for (var item in _items) {
        if (scripts.contains(item['script_name'])) {
          ids.add(item['id']);
        }
      }

      if (ids.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No records to update')));
        }
        setState(() => _isApplying = false);
        return;
      }

      final res = await apiService.put(
          '/admin/brokerage-settings/bulk-update',
          {
            'ids': ids,
            'brk_value': value,
            'type': _selectedType,
          },
          token: token);
      if (mounted) {
        final body = jsonDecode(res.body);
        if (res.statusCode == 200 && body['success'] == true) {
          final modified = body['data']?['modified'] ?? ids.length;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Updated $modified script(s)'),
              backgroundColor: kColorBuy));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(body['message'] ?? 'Update failed'),
              backgroundColor: kColorSell));
        }
        _amountCtrl.clear();
        _selected.clear();
        _fetch();
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _toggleAll() {
    final allSelected =
        _items.every((i) => _selected[i['script_name']] == true);
    setState(() {
      for (var i in _items) {
        _selected[i['script_name']] = !allSelected;
      }
    });
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
                          color: kTopBarFg, size: kIconSizeMedium))),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    const Text('Brokerage Settings',
                        style: TextStyle(
                            color: kTopBarFg,
                            fontSize: kFontSizeViewTitle,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold)),
                    Text(
                        _accountScoped
                            ? "This account's own rates"
                            : 'Platform default rates',
                        style: const TextStyle(
                            color: kTopBarFg,
                            fontSize: kFontSizeCaption,
                            fontFamily: kFontFamily)),
                  ])),
              // Create edits the PLATFORM DEFAULT rows (AddBrokerageToExchangeView
              // has no account) — only on the Admin Settings screen, never on
              // an account's page (9 Nov 2026).
              if (_isAdmin && !_accountScoped) ...[
                GestureDetector(
                  onTap: () {
                    if (_selectedExchange == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Select an exchange first')));
                      return;
                    }
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddBrokerageToExchangeView(
                            exchange: _selectedExchange!,
                            type: _selectedType,
                            isExistingGroup: _items.isNotEmpty,
                          ),
                        )).then((_) => _fetch());
                  },
                  child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: kBrandPrimary,
                          borderRadius: BorderRadius.circular(10)),
                      child:
                          const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.add,
                            color: Colors.white, size: kIconSizeDefault),
                        SizedBox(width: 4),
                        Text('Create',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: kFontSizeSubtitle,
                                fontFamily: kFontFamily,
                                fontWeight: kFontWeightSemiBold))
                      ])),
                ),
              ],
            ])),
        ),

        // Dropdowns
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                  child: _dropdown(
                      _selectedExchange, ['__hint__', ..._exchanges], (v) {
                setState(() {
                  _selectedExchange = v == '__hint__' ? null : v;
                  if (_selectedExchange != null) {
                    _selectedType = _lotWiseSegments.contains(_selectedExchange)
                        ? 'LOT WISE'
                        : 'TURNOVER WISE';
                  }
                });
                _fetch();
              }, displayMap: {'__hint__': 'Exchange'})),
              const SizedBox(width: 8),
              Expanded(
                  child: _dropdown(
                      _selectedType,
                      _types,
                      _selectedExchange == null
                          ? (v) {
                              setState(() => _selectedType = v!);
                              _fetch();
                            }
                          : null)),
            ])),
        const SizedBox(height: 8),

        // Value + Apply
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                  child: Container(
                height: 42,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12)),
                    border: Border.all(color: const Color(0xFFE2E8F0))),
                child: TextField(
                    controller: _amountCtrl,
                    keyboardType: _selectedType == 'LOT WISE'
                        ? TextInputType.number
                        : const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: _selectedType == 'LOT WISE'
                        ? [FilteringTextInputFormatter.digitsOnly]
                        : null,
                    style: const TextStyle(
                        fontSize: kFontSizeBodySmall,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightMedium),
                    decoration: const InputDecoration(
                        hintText: 'Value',
                        hintStyle: TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: kFontSizeBodySmall,
                            fontFamily: kFontFamily),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: InputBorder.none)),
              )),
              GestureDetector(
                  onTap: _isApplying ? null : _apply,
                  child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          color: _isApplying
                              ? const Color(0xFF94A3B8)
                              : kBrandPrimary,
                          borderRadius: const BorderRadius.only(
                              topRight: Radius.circular(12),
                              bottomRight: Radius.circular(12))),
                      child: _isApplying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text('Apply',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: kFontSizeBodySmall,
                                  fontFamily: kFontFamily,
                                  fontWeight: kFontWeightSemiBold)))),
            ])),
        const SizedBox(height: 10),
        if (_typeNote != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(_typeNote!,
                  style: const TextStyle(
                      color: kColorTextMuted,
                      fontSize: kFontSizeCaption,
                      fontFamily: kFontFamily))),

        // Table header
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                GestureDetector(
                    onTap: _items.isNotEmpty ? _toggleAll : null,
                    child: _headerCheck()),
                const SizedBox(width: 10),
                const Expanded(
                    child: Text('SCRIPT',
                        style: TextStyle(
                            color: kColorTextMuted,
                            fontSize: kFontSizeCaption,
                            fontFamily: kFontFamily,
                            fontWeight: kFontWeightSemiBold,
                            letterSpacing: 0.5))),
                const Text('BRK VALUE',
                    style: TextStyle(
                        color: kColorTextMuted,
                        fontSize: kFontSizeCaption,
                        fontFamily: kFontFamily,
                        fontWeight: kFontWeightSemiBold,
                        letterSpacing: 0.5)),
              ]),
            )),
        const SizedBox(height: 4),

        // List
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      color: kBrandPrimary, strokeWidth: 2.5))
              : _loadError != null
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_loadError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: kColorSell,
                                  fontSize: kFontSizeBodySmall,
                                  fontFamily: kFontFamily))))
                  : _items.isEmpty
                  ? Center(
                      child: _accountScoped && _noAccountRates
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                        'No rates yet for this account on ${_selectedExchange ?? ''}.\nType the rate above and tap Create.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            color: kColorTextMuted,
                                            fontSize: kFontSizeBodySmall,
                                            fontFamily: kFontFamily)),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                        onPressed: _isApplying
                                            ? null
                                            : _createForAccount,
                                        child: const Text(
                                            'Create for this account')),
                                  ]))
                          : Text(
                              _selectedExchange == null
                                  ? 'Select an exchange'
                                  : 'No settings found',
                              style: const TextStyle(
                                  color: kColorTextMuted,
                                  fontSize: kFontSizeBodySmall,
                                  fontFamily: kFontFamily)))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final name = item['script_name'] as String;
                        final sel = _selected[name] ?? false;
                        return GestureDetector(
                          onTap: () => setState(() => _selected[name] = !sel),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: const Color(0xFFF1F5F9),
                                        width: i < _items.length - 1 ? 1 : 0))),
                            child: Row(children: [
                              _checkCircle(sel),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          color: Color(0xFF334155),
                                          fontSize: kFontSizeBodySmall,
                                          fontFamily: kFontFamily,
                                          fontWeight: kFontWeightMedium))),
                              Text('${item['brk_value']}',
                                  style: const TextStyle(
                                      color: kBrandPrimary,
                                      fontSize: kFontSizeBodySmall,
                                      fontFamily: kFontFamily,
                                      fontWeight: kFontWeightBold)),
                            ]),
                          ),
                        );
                      }),
        ),
      ]))),
    );
  }

  Widget _dropdown(
      String? value, List<String> items, ValueChanged<String?>? onChanged,
      {Map<String, String>? displayMap}) {
    return Opacity(
      opacity: onChanged == null ? 0.6 : 1.0,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2))
            ]),
        child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: kColorTextMuted),
          style: const TextStyle(
              color: kColorTextPrimary,
              fontSize: kFontSizeBodySmall,
              fontFamily: kFontFamily,
              fontWeight: kFontWeightMedium),
          items: items
              .map((k) => DropdownMenuItem(
                  value: k,
                  child: Text(displayMap?[k] ?? k,
                      overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: onChanged,
        )),
      ),
    );
  }

  Widget _headerCheck() {
    final all = _items.isNotEmpty &&
        _items.every((i) => _selected[i['script_name']] == true);
    return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            color: all ? kBrandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: all ? kBrandPrimary : const Color(0xFFCBD5E1),
                width: 1.5)),
        child: all
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null);
  }

  Widget _checkCircle(bool sel) {
    return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
            color: sel ? kBrandPrimary : Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
                color: sel ? kBrandPrimary : const Color(0xFFCBD5E1),
                width: 1.5)),
        child: sel
            ? const Icon(Icons.check, size: 12, color: Colors.white)
            : null);
  }
}
