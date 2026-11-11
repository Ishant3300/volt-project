import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../pages/login_page.dart';
import '../services/broker_view_service.dart';
import '../services/multi_account_service.dart';
import '../services/sercure_storage_service.dart';
import '../utils/contants.dart';
import '../utils/date_formatter.dart';
import 'broker_share_view.dart' show BrokerStatementPanel;

/// Broker login in the app (owner, 12 Nov 2026) — VIEW ONLY, like the web
/// Broker View: his earnings (the Ledger-style statement table) and the
/// clients linked to him (summary, open positions, trades). Nothing here can
/// change anything; the server refuses every non-GET broker request.

final NumberFormat _money = NumberFormat('#,##,##0.00', 'en_IN');
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
String _fmt(Object? v) => _money.format(_d(v));
Color _tone(double v) => v > 0 ? kColorBuy : (v < 0 ? kColorSell : kColorTextPrimary);

const TextStyle _body = TextStyle(color: kColorTextPrimary, fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium);
const TextStyle _muted = TextStyle(color: kColorTextMuted, fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightMedium);
const TextStyle _title = TextStyle(color: kTopBarFg, fontSize: kFontSizeViewTitle, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold);

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(14)}) => Container(
      width: double.infinity,
      padding: padding,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(side: const BorderSide(width: 1, color: Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
      ),
      child: child,
    );

Widget _viewOnlyChip() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
      child: const Text('View only', style: TextStyle(color: Color(0xFF92400E), fontSize: kFontSizeCaption, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
    );

Widget _tabs(List<String> labels, int selected, ValueChanged<int> onTap) => Row(
      children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: ShapeDecoration(
                  color: selected == i ? kBrandPrimary : Colors.white,
                  shape: RoundedRectangleBorder(
                    side: const BorderSide(width: 1, color: kBrandPrimary),
                    borderRadius: BorderRadius.horizontal(
                      left: i == 0 ? const Radius.circular(8) : Radius.zero,
                      right: i == labels.length - 1 ? const Radius.circular(8) : Radius.zero,
                    ),
                  ),
                ),
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(color: selected == i ? Colors.white : const Color(0xFF333333), fontSize: kFontSizeBody, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
              ),
            ),
          ),
      ],
    );

/* ------------------------------------------------------------------ home */

class BrokerHomeView extends StatefulWidget {
  const BrokerHomeView({super.key});

  @override
  State<BrokerHomeView> createState() => _BrokerHomeViewState();
}

class _BrokerHomeViewState extends State<BrokerHomeView> {
  final BrokerViewService _svc = BrokerViewService();
  int _tab = 0;
  String _name = '';
  List<Map<String, dynamic>>? _clients;
  String? _clientsError;

  @override
  void initState() {
    super.initState();
    _svc.me().then((m) {
      if (mounted) setState(() => _name = '${m['name'] ?? m['username'] ?? ''}');
    }).catchError((Object _) {});
    _loadClients();
  }

  Future<void> _loadClients() async {
    try {
      final list = await _svc.clients();
      if (mounted) {
        setState(() {
          _clients = list;
          _clientsError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _clientsError = '$e');
    }
  }

  Future<void> _signOut() async {
    final storage = SecureStorageService();
    final multi = MultiAccountService();
    final active = await multi.getActiveKey();
    if (active != null) await multi.removeAccount(active);
    await storage.deleteToken();
    await storage.deleteRole();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [const Text('Broker View', style: _title), const SizedBox(width: 8), _viewOnlyChip()]),
                    if (_name.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(_name, style: _muted)),
                  ]),
                ),
                TextButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout, size: 18, color: kColorSell),
                  label: const Text('Sign out', style: TextStyle(color: kColorSell, fontFamily: kFontFamily, fontWeight: kFontWeightMedium)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _tabs(const ['My earnings', 'Clients'], _tab, (i) => setState(() => _tab = i)),
            ),
            const SizedBox(height: 12),
            Expanded(child: _tab == 0 ? _earnings() : _clientsList()),
          ],
        ),
      ),
    );
  }

  Widget _earnings() => ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          BrokerStatementPanel(loader: () => _svc.statement(weeks: 12)),
        ],
      );

  Widget _clientsList() {
    if (_clientsError != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_clientsError!, style: _body, textAlign: TextAlign.center)));
    final list = _clients;
    if (list == null) return const Center(child: CircularProgressIndicator(color: kBrandPrimary));
    return RefreshIndicator(
      onRefresh: _loadClients,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text('${list.length} ${list.length == 1 ? 'client' : 'clients'} linked to you · live', style: _muted),
          const SizedBox(height: 8),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No clients linked to you yet.', style: _muted))),
          for (final c in list) ...[
            _card(
              padding: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BrokerClientView(userId: '${c['user_id']}', name: '${c['name']}', username: '${c['username']}'))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c['name']}', style: _body.copyWith(fontWeight: kFontWeightSemiBold)),
                        const SizedBox(height: 2),
                        Text('${c['username']}${c['master'] is Map ? ' · ${(c['master'] as Map)['name'] ?? ''}' : ''}', style: _muted),
                        const SizedBox(height: 4),
                        Text('${c['open_positions_count'] ?? 0} open · Credit ${_fmt(c['credit'])}', style: _muted),
                      ]),
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      const Text('M2M', style: _muted),
                      Text(_fmt(c['m2m_pnl']), style: _body.copyWith(color: _tone(_d(c['m2m_pnl'])), fontWeight: kFontWeightBold)),
                    ]),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: kColorTextMuted),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/* --------------------------------------------------------------- one client */

class BrokerClientView extends StatefulWidget {
  final String userId;
  final String name;
  final String username;
  const BrokerClientView({super.key, required this.userId, required this.name, required this.username});

  @override
  State<BrokerClientView> createState() => _BrokerClientViewState();
}

class _BrokerClientViewState extends State<BrokerClientView> {
  final BrokerViewService _svc = BrokerViewService();
  int _tab = 0;
  Map<String, dynamic>? _client;
  List<Map<String, dynamic>>? _trades;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_svc.client(widget.userId), _svc.trades(widget.userId)]);
      if (!mounted) return;
      setState(() {
        _client = results[0] as Map<String, dynamic>;
        _trades = results[1] as List<Map<String, dynamic>>;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Map get _m => (_client?['metrics'] as Map?) ?? const {};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: kTopBarTile, borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.arrow_back, color: kTopBarFg, size: kIconSizeMedium),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text('${widget.name}  ${widget.username}', style: _title, overflow: TextOverflow.ellipsis)),
              _viewOnlyChip(),
            ]),
          ),
          Expanded(
            child: _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: _body, textAlign: TextAlign.center)))
                : _client == null
                    ? const Center(child: CircularProgressIndicator(color: kBrandPrimary))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                          children: [
                            _summary(),
                            const SizedBox(height: 12),
                            _tabs(const ['Positions', 'Trades'], _tab, (i) => setState(() => _tab = i)),
                            const SizedBox(height: 10),
                            if (_tab == 0) ..._positions() else ..._tradeRows(),
                          ],
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(String label, Object? v, {bool tone = false}) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: _muted),
          const SizedBox(height: 2),
          Text(_fmt(v), style: _body.copyWith(color: tone ? _tone(_d(v)) : null, fontWeight: kFontWeightSemiBold)),
        ]),
      );

  Widget _summary() => _card(
        child: Column(children: [
          Row(children: [_stat('M2M', _m['m2m_pnl'], tone: true), _stat('Realised', _m['realised_pnl'], tone: true), _stat('Open P&L', _m['position_pnl'], tone: true)]),
          const SizedBox(height: 12),
          Row(children: [_stat('Credit', _m['credit']), _stat('Margin used', _m['margin_used']), _stat('Equity', _m['equity'])]),
          if (_client?['master'] is Map) ...[
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: Text('Master: ${(_client!['master'] as Map)['name'] ?? ''}', style: _muted)),
          ],
        ]),
      );

  List<Widget> _positions() {
    final list = (_m['positions'] as List? ?? const []).whereType<Map>().toList();
    if (list.isEmpty) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No open positions.', style: _muted)))];
    return [
      for (final p in list) ...[
        _card(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p['tradingsymbol'] ?? ''}', style: _body.copyWith(fontWeight: kFontWeightSemiBold)),
                const SizedBox(height: 3),
                Text(
                  'Qty ${_d(p['net_qty']) == _d(p['net_qty']).roundToDouble() ? _d(p['net_qty']).toStringAsFixed(0) : _d(p['net_qty'])}'
                  ' · Avg ${_fmt(_d(p['net_qty']) >= 0 ? p['avg_buy_price'] : p['avg_sell_price'])} · LTP ${_fmt(p['ltp'])}',
                  style: _muted,
                ),
              ]),
            ),
            Text(_fmt(p['floating_pnl']), style: _body.copyWith(color: _tone(_d(p['floating_pnl'])), fontWeight: kFontWeightBold)),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }

  List<Widget> _tradeRows() {
    final list = _trades ?? const [];
    if (list.isEmpty) return const [Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No trades.', style: _muted)))];
    return [
      for (final t in list) ...[
        _card(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: '${t['transaction_type']}' == 'BUY' ? kColorBuyBadgeBg : kColorSellBadgeBg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('${t['transaction_type'] ?? ''}',
                  style: TextStyle(color: '${t['transaction_type']}' == 'BUY' ? kColorBuy : kColorSell, fontSize: kFontSizeBadge, fontFamily: kFontFamily, fontWeight: kFontWeightBadge)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['tradingsymbol'] ?? ''}', style: _body),
                const SizedBox(height: 2),
                Text('${DateFormatter.formatDateTime('${t['executed_at'] ?? t['createdAt'] ?? ''}')} · ${t['status'] ?? ''}', style: _muted),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('${t['executed_quantity'] ?? t['quantity'] ?? ''}', style: _body),
              Text('@ ${_fmt(t['executed_price'] ?? t['price'])}', style: _muted),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    ];
  }
}
