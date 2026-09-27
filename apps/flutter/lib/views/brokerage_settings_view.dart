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

  Future<void> _fetch() async {
    if (_selectedExchange == null) return;
    setState(() {
      _isLoading = true;
      _items = [];
      _selected = {};
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final effectiveExchange =
          _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange!;
      final token = await SecureStorageService().getToken();
      final userQuery =
          widget.ownerId != null ? '&user_id=${widget.ownerId}' : '';
      final res = await apiService.get(
        '/admin/brokerage-settings/exchange/$effectiveExchange?type=${Uri.encodeComponent(_selectedType)}&limit=2000$userQuery',
        token: token,
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          List<dynamic> items = data['data']['items'] ?? [];

          // If no user-specific records, fall back to global for display
          if (items.isEmpty && widget.ownerId != null) {
            final globalRes = await apiService.get(
              '/admin/brokerage-settings/exchange/$effectiveExchange?type=${Uri.encodeComponent(_selectedType)}&limit=2000',
              token: token,
            );
            if (globalRes.statusCode == 200) {
              final gData = jsonDecode(globalRes.body);
              if (gData['success'] == true) {
                items = gData['data']['items'] ?? [];
              }
            }
          }

          List<Map<String, dynamic>> filtered = [];
          for (var s in items) {
            filtered.add({
              'id': s['id'],
              'script_name': s['script_name'],
              'brk_value': s['brk_value'],
              'type': s['type'],
              'exchange_name': s['exchange_name']
            });
          }
          setState(() => _items = filtered);
        }
      }
    } catch (e) {
      log('❌ Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    setState(() => _isApplying = true);
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final token = await SecureStorageService().getToken();

      // If owner-specific and no items exist yet, create user-specific records first
      if (widget.ownerId != null && _items.isEmpty) {
        final effectiveExchange =
            _selectedExchange == 'GLOBAL' ? 'INDICES' : _selectedExchange!;
        await apiService.post(
            '/admin/brokerage-settings/bulk-create',
            {
              'exchange_name': effectiveExchange,
              'type': _selectedType,
              'default_brk_value': value,
              'user_id': widget.ownerId,
            },
            token: token);
        await _fetch();
      }

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
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
          child: Column(children: [
        // Header
        Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
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
                          ]),
                      child: const Icon(Icons.arrow_back,
                          color: kColorTextPrimary, size: kIconSizeMedium))),
              const SizedBox(width: 12),
              const Expanded(
                  child: Text('Brokerage Settings',
                      style: TextStyle(
                          color: kColorTextPrimary,
                          fontSize: kFontSizeViewTitle,
                          fontFamily: kFontFamily,
                          fontWeight: kFontWeightSemiBold))),
              if (_isAdmin) ...[
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
              : _items.isEmpty
                  ? Center(
                      child: Text(
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
      ])),
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
