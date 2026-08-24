import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/user_profile_provider.dart';
import '../services/api_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';

class AccountSummaryView extends StatefulWidget {
  const AccountSummaryView({super.key});
  @override
  State<AccountSummaryView> createState() => _AccountSummaryViewState();
}

class _AccountSummaryViewState extends State<AccountSummaryView> {
  bool _isLoading = false;
  String _selectedWeek = 'previous_week';
  final _weekOptions = ['this_week', 'previous_week', 'custom'];
  final _weekLabels = {'this_week': 'This Week', 'previous_week': 'Previous Week', 'custom': 'Custom period'};

  // Custom date range
  DateTime? _fromDate;
  DateTime? _toDate;

  // Mode checkboxes — credit is exclusive
  bool _showPnl = true;
  bool _showBrk = true;
  bool _showCredit = false;

  // User selection (admin/master)
  List<Map<String, dynamic>> _users = [];
  Map<String, dynamic>? _selectedUser;
  final _userSearchCtrl = TextEditingController();

  // Search
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Data
  List<Map<String, dynamic>> _instruments = [];
  List<Map<String, dynamic>> _creditRows = [];
  Map<String, dynamic> _totals = {};
  String _weekLabel = '';

  @override
  void initState() {
    super.initState();
    final profile = context.read<UserProfileProvider>();
    if (!profile.isUser) _fetchUsers();
  }

  @override
  void dispose() {
    _userSearchCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    try {
      final token = await SecureStorageService().getToken();
      final profile = context.read<UserProfileProvider>();
      final endpoint = profile.isAdmin ? '/admin/users?limit=500' : '/master/users?limit=500';
      final res = await ApiService(backendUrl).get(endpoint, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final nested = body['data'];
        final List list = nested is Map ? (nested['users'] ?? []) : (nested ?? []);
        setState(() => _users = list.cast<Map<String, dynamic>>());
      }
    } catch (_) {}
  }

  Future<void> _fetch() async {
    if (_selectedWeek == 'custom' && (_fromDate == null || _toDate == null)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select both dates')));
      return;
    }
    setState(() { _isLoading = true; _instruments = []; _creditRows = []; });
    try {
      final token = await SecureStorageService().getToken();
      final mode = _showCredit ? 'credit' : (_showBrk ? 'brokerage' : 'pnl');
      String url = '/account-summary?week=$_selectedWeek&mode=$mode&limit=500';
      if (_selectedWeek == 'custom' && _fromDate != null && _toDate != null) {
        url += '&from=${_fmtIso(_fromDate!)}&to=${_fmtIso(_toDate!)}';
      }
      if (_selectedUser != null) {
        final uid = _selectedUser!['id'] ?? _selectedUser!['_id'] ?? '';
        url += '&user_id=$uid';
      }
      if (_searchQuery.isNotEmpty) url += '&search=$_searchQuery';

      final res = await ApiService(backendUrl).get(url, token: token);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        if (body['success'] == true && body['data'] != null) {
          final data = body['data'];
          setState(() {
            _weekLabel = data['week'] ?? '';
            if (_showCredit) {
              _creditRows = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
            } else {
              _instruments = List<Map<String, dynamic>>.from(data['instruments'] ?? []);
              _totals = Map<String, dynamic>.from(data['totals'] ?? {});
            }
          });
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _fmtIso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now()),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: kBrandPrimary)), child: child!),
    );
    if (picked != null) setState(() { if (isFrom) _fromDate = picked; else _toDate = picked; });
  }

  void _onCreditToggle(bool? val) {
    setState(() {
      _showCredit = val ?? false;
      if (_showCredit) { _showPnl = false; _showBrk = false; }
    });
  }

  void _onPnlToggle(bool? val) {
    setState(() { _showPnl = val ?? false; if (_showPnl) _showCredit = false; });
  }

  void _onBrkToggle(bool? val) {
    setState(() { _showBrk = val ?? false; if (_showBrk) _showCredit = false; });
  }

  void _clear() {
    setState(() {
      _instruments = []; _creditRows = []; _totals = {};
      _searchCtrl.clear(); _searchQuery = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<UserProfileProvider>();
    final isUser = profile.isUser;
    final dateFmt = DateFormat('dd-MM-yyyy');

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
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: kIconSizeMedium),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Account Summary', style: TextStyle(color: Colors.black, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
            ]),
          ),

          // Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              // Week dropdown
              _buildDropdown(_selectedWeek, _weekOptions.map((k) => k).toList(), (v) => setState(() => _selectedWeek = v!), displayMap: _weekLabels),
              if (_selectedWeek == 'custom') ...[
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: GestureDetector(onTap: () => _pickDate(true), child: _dateBox(_fromDate != null ? dateFmt.format(_fromDate!) : 'From'))),
                  const SizedBox(width: 8),
                  Expanded(child: GestureDetector(onTap: () => _pickDate(false), child: _dateBox(_toDate != null ? dateFmt.format(_toDate!) : 'To'))),
                ]),
              ],
              const SizedBox(height: 8),

              // User dropdown (admin/master)
              if (!isUser)
                _buildDropdown(
                  _selectedUser != null ? (_selectedUser!['username'] ?? '') : '__all__',
                  ['__all__', ..._users.map((u) => u['username'] as String? ?? '')],
                  (v) => setState(() => _selectedUser = v == '__all__' ? null : _users.firstWhere((u) => u['username'] == v, orElse: () => <String, dynamic>{})),
                  displayMap: {'__all__': 'All Users', ..._users.fold<Map<String, String>>({}, (m, u) { m[u['username'] ?? ''] = '${u['name'] ?? u['username']}'; return m; })},
                ),
              if (!isUser) const SizedBox(height: 8),

              // Checkboxes
              Row(children: [
                _checkbox('P&L', _showPnl, _onPnlToggle),
                const SizedBox(width: 16),
                _checkbox('Brk', _showBrk, _onBrkToggle),
                const SizedBox(width: 16),
                _checkbox('Credit', _showCredit, _onCreditToggle),
              ]),
              const SizedBox(height: 8),

              // Clear + View buttons
              Row(children: [
                Expanded(child: GestureDetector(
                  onTap: _clear,
                  child: Container(
                    height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: const Text('Clear', style: TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: GestureDetector(
                  onTap: _isLoading ? null : _fetch,
                  child: Container(
                    height: 42, alignment: Alignment.center,
                    decoration: BoxDecoration(color: kBrandPrimary, borderRadius: BorderRadius.circular(12)),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('View', style: TextStyle(color: Colors.white, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
                  ),
                )),
              ]),
              const SizedBox(height: 8),

              // Search
              Container(
                height: 42,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  style: const TextStyle(fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
                  decoration: const InputDecoration(
                    hintText: 'Search exchange or script',
                    hintStyle: TextStyle(color: Color(0xFFCBD5E1), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily),
                    prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),

          // Results
          Expanded(child: _buildResults()),
        ]),
      ),
    );
  }


  // ── Helper widgets ──

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged, {Map<String, String>? displayMap}) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : items.first,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF94A3B8)),
          style: const TextStyle(color: Colors.black, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightMedium),
          items: items.map((k) => DropdownMenuItem(value: k, child: Text(displayMap?[k] ?? k, overflow: TextOverflow.ellipsis))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _dateBox(String text) {
    final isPlaceholder = text == 'From' || text == 'To';
    return Container(
      height: 42, alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Row(children: [
        Icon(Icons.calendar_today, size: kIconSizeSmall, color: isPlaceholder ? const Color(0xFFCBD5E1) : kBrandPrimary),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(color: isPlaceholder ? const Color(0xFFCBD5E1) : Colors.black, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  Widget _checkbox(String label, bool value, ValueChanged<bool?> onChanged) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 20, height: 20,
        child: Checkbox(
          value: value, onChanged: onChanged,
          activeColor: kBrandPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
    ]);
  }

  // ── Results ──

  Widget _buildResults() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2.5));
    }

    if (_showCredit) return _buildCreditResults();
    return _buildInstrumentResults();
  }

  Widget _buildInstrumentResults() {
    if (_instruments.isEmpty) {
      return const Center(child: Text('No data', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)));
    }

    final totalPnl = _d(_totals['pnl']);
    final totalBrk = _d(_totals['brokerage']);
    final totalTrades = (_totals['trades'] as num?)?.toInt() ?? 0;

    return Column(children: [
      // Totals bar
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
        child: Row(children: [
          _totalPill('P&L', totalPnl, colored: true),
          const SizedBox(width: 10),
          if (_showBrk) ...[_totalPill('Brk', totalBrk), const SizedBox(width: 10)],
          _totalPill('Trades', totalTrades.toDouble(), plain: true),
          const Spacer(),
          if (_weekLabel.isNotEmpty)
            Flexible(child: Text(_weekLabel, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily), overflow: TextOverflow.ellipsis)),
        ]),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('${_instruments.length} instruments', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _instruments.length,
          itemBuilder: (_, i) => _instrumentCard(_instruments[i]),
        ),
      ),
    ]);
  }

  Widget _totalPill(String label, double value, {bool colored = false, bool plain = false}) {
    final text = plain ? value.toInt().toString() : _fmtSigned(value);
    final color = colored ? _pnlColor(value) : const Color(0xFF334155);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
      Text(text, style: TextStyle(color: color, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
    ]);
  }

  Widget _instrumentCard(Map<String, dynamic> inst) {
    final symbol = inst['tradingsymbol'] ?? '';
    final exchange = inst['exchange'] ?? '';
    final buyQty = (inst['buy_qty'] as num?)?.toInt() ?? 0;
    final sellQty = (inst['sell_qty'] as num?)?.toInt() ?? 0;
    final buyAmt = _d(inst['buy_amount']);
    final sellAmt = _d(inst['sell_amount']);
    final pnl = _d(inst['pnl']);
    final brokerage = _d(inst['brokerage']);
    final netQty = (inst['net_qty'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Symbol + exchange
        Row(children: [
          Expanded(child: Text(symbol, style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeBodySmall, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: -0.3))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
            child: Text(exchange, style: const TextStyle(color: Color(0xFF64748B), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          ),
        ]),
        const SizedBox(height: 8),

        // Buy / Sell grid
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
          child: Column(children: [
            Row(children: [
              _gridCell('BUY QTY', '$buyQty', const Color(0xFF10B981), showRight: true),
              _gridCell('SELL QTY', '$sellQty', const Color(0xFFEF4444), showRight: false),
            ]),
            Container(height: 1, color: const Color(0xFFF1F5F9)),
            Row(children: [
              _gridCell('BUY AMT', _fmt(buyAmt), const Color(0xFF10B981), showRight: true),
              _gridCell('SELL AMT', _fmt(sellAmt), const Color(0xFFEF4444), showRight: false),
            ]),
          ]),
        ),
        const SizedBox(height: 8),

        // P&L + Brokerage + Net Qty row
        Row(children: [
          _summaryChip('P&L', _fmtSigned(pnl), _pnlColor(pnl)),
          const SizedBox(width: 6),
          if (_showBrk) ...[_summaryChip('BRK', _fmt(brokerage), const Color(0xFF64748B)), const SizedBox(width: 6)],
          if (netQty != 0) _summaryChip('NET', '$netQty', const Color(0xFF94A3B8)),
        ]),
      ]),
    );
  }

  Widget _gridCell(String label, String value, Color valueColor, {required bool showRight}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(border: showRight ? const Border(right: BorderSide(color: Color(0xFFF1F5F9))) : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(value, style: TextStyle(color: valueColor, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
        ]),
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: const Color(0xFFFAFBFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFF1F5F9))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$label ', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBadge, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: 0.3)),
        Text(value, style: TextStyle(color: color, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
      ]),
    );
  }

  // ── Credit results ──

  Widget _buildCreditResults() {
    if (_creditRows.isEmpty) {
      return const Center(child: Text('No transactions', style: TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeBodySmall, fontFamily: kFontFamily)));
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Align(alignment: Alignment.centerLeft,
          child: Text('${_creditRows.length} transactions', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightMedium))),
      ),
      const SizedBox(height: 6),
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _creditRows.length,
          itemBuilder: (_, i) => _creditCard(_creditRows[i]),
        ),
      ),
    ]);
  }

  Widget _creditCard(Map<String, dynamic> tx) {
    final type = tx['type'] ?? '';
    final amount = _d(tx['amount']);
    final before = _d(tx['balance_before']);
    final after = _d(tx['balance_after']);
    final username = tx['username'] ?? '';
    final note = tx['note'] ?? '';
    final createdAt = tx['created_at'] ?? '';
    final isCredit = type == 'CREDIT';
    final typeColor = isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444);

    String timeStr = '';
    if (createdAt is String && createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        timeStr = DateFormat('dd MMM yy, hh:mm a').format(dt);
      } catch (_) {
        timeStr = createdAt;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Type badge + username + timestamp
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(type, style: TextStyle(color: typeColor, fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontWeight: kFontWeightBold)),
          ),
          const SizedBox(width: 8),
          if (username.isNotEmpty)
            Text(username.toUpperCase(), style: const TextStyle(color: kBrandPrimary, fontSize: kFontSizeSubtitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold, letterSpacing: -0.3)),
          const Spacer(),
          Text(timeStr, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeCaption, fontFamily: kFontFamily)),
        ]),
        const SizedBox(height: 8),

        // 2×2 grid: Opening / Closing / Credit / Debit
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFF1F5F9))),
          child: Column(children: [
            Row(children: [
              _gridCell('OPENING', _fmt(before), const Color(0xFF334155), showRight: true),
              _gridCell('CLOSING', _fmt(after), const Color(0xFF334155), showRight: false),
            ]),
            Container(height: 1, color: const Color(0xFFF1F5F9)),
            Row(children: [
              _gridCell(isCredit ? 'CREDIT' : 'DEBIT', _fmt(amount), typeColor, showRight: true),
              _gridCell('CHANGE', _fmtSigned(after - before), _pnlColor(after - before), showRight: false),
            ]),
          ]),
        ),

        // Note
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(note, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: kFontSizeNavLabel, fontFamily: kFontFamily, fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }

  // ── Formatters ──

  Color _pnlColor(double v) => v >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444);
  String _fmt(double v) => v.toStringAsFixed(2);
  String _fmtSigned(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';
  double _d(dynamic v) => (v as num?)?.toDouble() ?? 0.0;
}
