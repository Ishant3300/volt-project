// Equity "More": statement (client), clients list + client page (master / admin),
// change password, sign out. Creating accounts, month-end and settings stay on the web
// for the test build.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/pages/login_page.dart';
import 'package:stocker/services/sercure_storage_service.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';
import 'eq_format.dart';
import 'eq_live.dart';
import 'eq_orders.dart';
import 'eq_portfolio.dart';
import 'package:stocker/utils/account_label.dart';

class EqStatementView extends StatefulWidget {
  final String? clientId;
  const EqStatementView({super.key, this.clientId});
  @override
  State<EqStatementView> createState() => _EqStatementViewState();
}

class _EqStatementViewState extends State<EqStatementView> {
  Map<String, dynamic>? _st;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = eqTodayIst();
    context.read<EqApi>().statement(clientId: widget.clientId, from: '${today.substring(0, 8)}01', to: today).then((s) {
      if (mounted) setState(() => _st = s);
    }).catchError((e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  String _drcr(dynamic v) {
    final n = eqNum(v);
    if (n.abs() < 0.005) return '0.00';
    return '${eqMoney(n.abs())} ${n >= 0 ? 'Cr' : 'Dr'}';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: kColorSell)));
    if (_st == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final rows = _st!['rows'] as List;
    final c = _st!['closing'] as Map;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text('This month · ${eqDmy(_st!['from'])} to ${eqDmy(_st!['to'])}', style: const TextStyle(fontSize: 11, color: kColorTextMuted)),
      ),
      for (final r in rows)
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(eqDmy(r['date']), style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
              const Spacer(),
              if (eqNum(r['credit']) > 0) Text('+${eqMoney(r['credit'])}', style: const TextStyle(fontSize: 11, color: kColorBuy)),
              if (eqNum(r['debit']) > 0) Text('-${eqMoney(r['debit'])}', style: const TextStyle(fontSize: 11, color: kColorSell)),
            ]),
            Text(r['particulars'].toString(), style: const TextStyle(fontSize: 12)),
            Text('Money ${_drcr(r['money'])} · margin ${eqMoney(r['margin'])} · funded ${eqMoney(r['funded'])}${eqNum(r['interest']) > 0 ? ' · interest ${eqMoney(r['interest'])}' : ''}',
                style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text('Closing: client money ${_drcr(c['money'])} · margin ${eqMoney(c['margin'])} · funded ${eqMoney(c['funded'])} · interest not yet posted ${eqMoney(c['interest_not_posted'])}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 16), child: Text('Full statement with PDF: web portal → Statement.', style: TextStyle(fontSize: 10, color: kColorTextMuted))),
    ]);
  }
}

class EqClientsView extends StatefulWidget {
  const EqClientsView({super.key});
  @override
  State<EqClientsView> createState() => _EqClientsViewState();
}

class _EqClientsViewState extends State<EqClientsView> {
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<EqApi>().accounts();
      if (mounted) setState(() { _data = d; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: kColorSell)));
    if (_data == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final accounts = _data!['accounts'] as List;
    if (accounts.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Text('No equity clients yet — create them on the web portal (Equity → Clients).', style: TextStyle(color: kColorTextMuted)));
    }
    return Column(children: [
      for (final a in accounts)
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MultiProvider(
                providers: [
                  Provider<EqApi>.value(value: context.read<EqApi>()),
                  ChangeNotifierProvider<EqLive>.value(value: context.read<EqLive>()),
                ],
                child: EqClientPage(clientId: a['client']['_id'] as String, title: accountLabel(a['client']['name'], a['client']['username'])),
              ))),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(accountLabel(a['client']['name'], a['client']['username']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('money ${eqMoney(a['summary']['client_money'])}  ·  funded ${eqMoney(a['summary']['funded'])}',
                      style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(eqSigned(a['summary']['pnl_since_month_end']), style: TextStyle(fontWeight: FontWeight.w700, color: eqTone(a['summary']['pnl_since_month_end']))),
                if (a['summary']['loss_alert'] == true) const Text('Loss alert', style: TextStyle(fontSize: 10, color: kColorSell)),
              ]),
              const Icon(Icons.chevron_right, color: kColorTextMuted),
            ]),
          ),
        ),
    ]);
  }
}

class EqClientPage extends StatelessWidget {
  final String clientId;
  final String title;
  const EqClientPage({super.key, required this.clientId, required this.title});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: kPageBg,
        appBar: AppBar(
          title: Text(title),
          bottom: const TabBar(tabs: [Tab(text: 'Account'), Tab(text: 'Orders'), Tab(text: 'Statement')]),
        ),
        body: TabBarView(children: [
          ListView(children: [EqAccountView(clientId: clientId)]),
          EqOrdersPage(isManager: true, clientId: clientId),
          ListView(children: [EqStatementView(clientId: clientId)]),
        ]),
      ),
    );
  }
}

class EqPasswordPage extends StatefulWidget {
  final bool forced;
  final VoidCallback? onDone;
  const EqPasswordPage({super.key, this.forced = false, this.onDone});
  @override
  State<EqPasswordPage> createState() => _EqPasswordPageState();
}

class _EqPasswordPageState extends State<EqPasswordPage> {
  final _cur = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _msg;

  Future<void> _save() async {
    if (_next.text.length < 6) { setState(() => _msg = 'New password: at least 6 characters.'); return; }
    if (_next.text != _confirm.text) { setState(() => _msg = 'The new passwords don\'t match.'); return; }
    setState(() { _busy = true; _msg = null; });
    try {
      await context.read<EqApi>().changePassword(_cur.text, _next.text);
      if (!mounted) return;
      eqSnack(context, 'Password changed');
      if (widget.onDone != null) { widget.onDone!(); } else { Navigator.pop(context); }
    } catch (e) {
      setState(() => _msg = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kPageBg,
      appBar: AppBar(title: Text(widget.forced ? 'Set a new password' : 'Change password'), automaticallyImplyLeading: !widget.forced),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (widget.forced) const Text('Set a new password before continuing — required on your first login.', style: TextStyle(color: kColorTextMuted)),
        TextField(controller: _cur, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
        TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'New password')),
        TextField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, style: const TextStyle(color: kColorSell))),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
      ]),
    );
  }
}

/// Ends the equity session on this phone and returns to sign-in.
Future<void> eqSignOut(BuildContext context) async {
  final s = SecureStorageService();
  await s.deleteToken();
  await s.deleteRole();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginPage()), (r) => false);
}

class EqMorePage extends StatelessWidget {
  final String role;
  const EqMorePage({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final isManager = role != 'CASH_CLIENT';
    final isAdmin = role == 'ADMIN';
    return ListView(children: [
      if (isManager) ...[
        const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('EQUITY CLIENTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kSectionLabelColor))),
        const EqClientsView(),
      ] else ...[
        const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('STATEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kSectionLabelColor))),
        const EqStatementView(),
      ],
      const Divider(),
      if (!isAdmin)
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: const Text('Change password'),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => Provider<EqApi>.value(value: context.read<EqApi>(), child: const EqPasswordPage()))),
        ),
      if (!isAdmin)
        ListTile(leading: const Icon(Icons.logout, color: kColorSell), title: const Text('Sign out', style: TextStyle(color: kColorSell)), onTap: () => eqSignOut(context)),
      const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Test build: creating masters and clients, money entries, month-end and settings are on the web portal (Equity menu).',
            style: TextStyle(fontSize: 10, color: kColorTextMuted)),
      ),
    ]);
  }
}
