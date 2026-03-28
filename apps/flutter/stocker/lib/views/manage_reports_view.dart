import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/master.dart';
import '../services/admin_service.dart';
import '../services/api_service.dart';
import '../utils/contants.dart';

class ManageReportsView extends StatefulWidget {
  const ManageReportsView({super.key});

  @override
  State<ManageReportsView> createState() => _ManageReportsViewState();
}

class _ManageReportsViewState extends State<ManageReportsView> {
  List<Master> _masters = [];
  Master? _selectedMaster;
  bool _isLoadingMasters = true;
  bool _isUpdating = false;
  bool _hasChanges = false;

  Map<String, bool> _permissions = {};
  Map<String, bool> _original = {};

  static const _permLabels = {
    'account_summary': 'Account Summary',
    'pnl_summary': 'P&L Summary',
    'client_summary': 'Client Summary',
    'settlement_report': 'Settlement Report',
    'generate_pdf': 'Generate PDF',
    'weekly_admin': 'Weekly Admin',
    'intraday_history': 'Intraday History',
    'userwise_open_position': 'Userwise Position',
    'script_quantity': 'Script Quantity',
    'deleted_trade': 'Deleted Trade',
    'trade_account': 'Trade Account',
  };

  @override
  void initState() {
    super.initState();
    _fetchMasters();
  }

  Future<void> _fetchMasters() async {
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final res = await AdminService(api).getAllMasters(page: 1, limit: 100);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final List list = data['data']['masters'] ?? [];
          setState(() {
            _masters = list.map((j) { try { return Master.fromJson(j); } catch (_) { return null; } }).whereType<Master>().toList();
            _isLoadingMasters = false;
          });
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingMasters = false);
  }

  void _selectMaster(Master master) {
    final p = master.permissions;
    final perms = <String, bool>{
      'account_summary': p?.accountSummary ?? false,
      'pnl_summary': p?.pnlSummary ?? false,
      'client_summary': p?.clientSummary ?? false,
      'settlement_report': p?.settlementReport ?? false,
      'generate_pdf': p?.generatePdf ?? false,
      'weekly_admin': p?.weeklyAdmin ?? false,
      'intraday_history': p?.intradayHistory ?? false,
      'userwise_open_position': p?.userwiseOpenPosition ?? false,
      'script_quantity': p?.scriptQuantity ?? false,
      'deleted_trade': p?.deletedTrade ?? false,
      'trade_account': p?.tradeAccount ?? false,
    };
    setState(() {
      _selectedMaster = master;
      _permissions = perms;
      _original = Map.from(perms);
      _hasChanges = false;
    });
  }

  Future<void> _update() async {
    if (_selectedMaster == null || !_hasChanges) return;
    setState(() => _isUpdating = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final admin = AdminService(api);
      final cp = _selectedMaster!.permissions;
      final updated = MasterPermissions(
        accountSummary: _permissions['account_summary']!,
        pnlSummary: _permissions['pnl_summary']!,
        clientSummary: _permissions['client_summary']!,
        settlementReport: _permissions['settlement_report']!,
        generatePdf: _permissions['generate_pdf']!,
        weeklyAdmin: _permissions['weekly_admin']!,
        intradayHistory: _permissions['intraday_history']!,
        userwiseOpenPosition: _permissions['userwise_open_position']!,
        scriptQuantity: _permissions['script_quantity']!,
        deletedTrade: _permissions['deleted_trade']!,
        tradeAccount: _permissions['trade_account']!,
        closeOnly: cp?.closeOnly ?? false,
        bet: cp?.bet ?? false,
        marginSquare: cp?.marginSquare ?? false,
        freshStoploss: cp?.freshStoploss ?? false,
      );
      final res = await admin.updateMasterPermissions(masterId: _selectedMaster!.id, permissions: updated);
      if (res.statusCode == 200) {
        setState(() { _hasChanges = false; _original = Map.from(_permissions); });
        _snack('Permissions updated');
      } else {
        _snack('Failed to update', isError: true);
      }
    } catch (e) {
      _snack('Error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
    ));
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
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                      ),
                      child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Manage Reports', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                ],
              ),
            ),

            // Master selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _card(
                child: GestureDetector(
                  onTap: () => _showMasterSheet(),
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3F45C7).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_outline, size: 18, color: Color(0xFF3F45C7)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedMaster?.name ?? 'Select Master',
                              style: TextStyle(
                                color: _selectedMaster != null ? Colors.black : const Color(0xFF94A3B8),
                                fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold,
                              ),
                            ),
                            if (_selectedMaster != null)
                              Text(_selectedMaster!.username, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down, size: kIconSizeMedium, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Permissions list
            Expanded(
              child: _selectedMaster == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64, height: 64,
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))]),
                            child: const Icon(Icons.admin_panel_settings_outlined, size: 28, color: Color(0xFFCBD5E1)),
                          ),
                          const SizedBox(height: 16),
                          const Text('Select a master to manage permissions', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBody, fontFamily: 'Inter')),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        const Text('PERMISSIONS', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.5)),
                        const SizedBox(height: 12),
                        _card(
                          child: Column(
                            children: _permLabels.entries.map((e) {
                              final isLast = e.key == _permLabels.keys.last;
                              return Column(
                                children: [
                                  _toggleRow(e.value, _permissions[e.key] ?? false, (v) {
                                    setState(() { _permissions[e.key] = v; _hasChanges = true; });
                                  }),
                                  if (!isLast) const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _isUpdating || !_hasChanges ? null : _update,
                          child: Container(
                            width: double.infinity, height: 52,
                            decoration: BoxDecoration(
                              color: _isUpdating || !_hasChanges ? const Color(0xFF94A3B8) : const Color(0xFF3F45C7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: _isUpdating
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('UPDATE PERMISSIONS', style: TextStyle(color: Colors.white, fontSize: kFontSizeButtonText, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showMasterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
        decoration: const BoxDecoration(
          color: Color(0xFFF8FAFC),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text('Select Master', style: TextStyle(color: Colors.black, fontSize: kFontSizeSectionHeader, fontFamily: 'Inter', fontWeight: kFontWeightBold)),
            const SizedBox(height: 16),
            if (_isLoadingMasters)
              const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _masters.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                  itemBuilder: (_, i) {
                    final m = _masters[i];
                    final sel = _selectedMaster?.id == m.id;
                    return GestureDetector(
                      onTap: () { _selectMaster(m); Navigator.pop(context); },
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                        color: sel ? const Color(0xFF3F45C7).withValues(alpha: 0.05) : Colors.transparent,
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: const Color(0xFF3F45C7).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                              child: Center(child: Text(m.name.isNotEmpty ? m.name[0].toUpperCase() : '?', style: const TextStyle(color: Color(0xFF3F45C7), fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightBold))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.name, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightSemiBold)),
                                  Text(m.username, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeSubtitle, fontFamily: 'Inter', fontWeight: kFontWeightMedium)),
                                ],
                              ),
                            ),
                            if (sel) const Icon(Icons.check_circle, size: kIconSizeMedium, color: Color(0xFF3F45C7)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: child,
    );
  }

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.black, fontSize: kFontSizeBody, fontFamily: 'Inter', fontWeight: kFontWeightMedium))),
          GestureDetector(
            onTap: () => onChanged(!value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 26, padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? const Color(0xFF3F45C7) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 200),
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
