// Equity portfolio. Client: own account (client money, margin used, funded, interest,
// P&L since month-end, limits) + holdings. Master / admin: totals over the tree + every
// holding with its client. MTM moves with live prices: (LTP − net average) × qty.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';
import 'eq_format.dart';
import 'eq_live.dart';
import 'package:stocker/utils/account_label.dart';

/// Holdings list; [showClient] adds the client name (manager view).
class EqHoldingsList extends StatelessWidget {
  final List<dynamic> holdings;
  final bool showClient;
  const EqHoldingsList({super.key, required this.holdings, this.showClient = false});

  @override
  Widget build(BuildContext context) {
    final quotes = context.watch<EqLive>().quotes;
    if (holdings.isEmpty) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No holdings.', style: TextStyle(color: kColorTextMuted))));
    }
    return Column(children: [
      for (final h in holdings)
        Builder(builder: (_) {
          final token = (h['instrument_token'] as num?)?.toInt();
          final ltp = token != null ? (quotes[token]?['last_price'] ?? h['ltp']) : h['ltp'];
          final qty = eqNum(h['qty']);
          final mtm = (eqNum(ltp) - eqNum(h['avg_price'])) * qty;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(h['script'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    eqCategoryTag(h['approved'] == true),
                  ]),
                  if (showClient && h['client'] != null) Text(accountLabel(h['client']['name'], h['client']['username']), style: const TextStyle(fontSize: 11, color: kColorBuy)),
                  Text('${eqQty(qty)} @ ${eqMoney(h['avg_price'])} (net)  ·  margin ${eqMoney(h['margin'])}', style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(eqSigned(mtm), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: eqTone(mtm))),
                Text('LTP ${eqMoney(ltp)}', style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
              ]),
            ]),
          );
        }),
    ]);
  }
}

/// One client's live account (also used on a client's page for masters/admin).
class EqAccountView extends StatefulWidget {
  final String? clientId;
  const EqAccountView({super.key, this.clientId});
  @override
  State<EqAccountView> createState() => _EqAccountViewState();
}

class _EqAccountViewState extends State<EqAccountView> {
  Map<String, dynamic>? _acc;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await context.read<EqApi>().account(clientId: widget.clientId);
      if (!mounted) return;
      setState(() { _acc = a; _error = null; });
      context.read<EqLive>().add((a['holdings'] as List).map((h) => (h['instrument_token'] as num).toInt()));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _acc == null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: kColorSell)));
    if (_acc == null) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final s = _acc!['summary'] as Map;
    final holdings = _acc!['holdings'] as List;
    final quotes = context.watch<EqLive>().quotes;
    double liveMtm = 0;
    double liveValue = 0;
    for (final h in holdings) {
      final t = (h['instrument_token'] as num?)?.toInt();
      final ltp = eqNum(t != null ? (quotes[t]?['last_price'] ?? h['ltp']) : h['ltp']);
      liveMtm += (ltp - eqNum(h['avg_price'])) * eqNum(h['qty']);
      liveValue += ltp * eqNum(h['qty']);
    }
    final pnl = eqNum(s['booked_pnl']) + liveMtm;
    final limits = s['limits'] as Map;
    final rates = s['rates'] as Map;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (s['loss_alert'] == true)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: kColorLossBadgeBg, borderRadius: BorderRadius.circular(8)),
          child: Text('Loss alert: ${eqMoney(s['loss_pct_of_money'])}% of client money (alert at 80%). No automatic cut.', style: const TextStyle(color: kColorSell, fontSize: 12)),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Text(accountLabel(_acc!['client']['name'], _acc!['client']['username']), style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: GridView.count(
          crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 2.3,
          children: [
            eqTile('Client money', eqMoney(s['client_money'])),
            eqTile('Holdings value', eqMoney(liveValue)),
            eqTile('Margin used', eqMoney(s['margin_used']), hint: 'MTF ${eqMoney(s['margin_approved'])} · non ${eqMoney(s['margin_non_approved'])}'),
            eqTile('Funded', eqMoney(s['funded']), color: eqNum(s['funded']) > 0 ? kTintAmberFg : null, hint: 'charged interest'),
            eqTile('Interest this month', eqMoney(s['interest_this_month']), hint: '${rates['interest_approved_pct']}% MTF · ${rates['interest_non_approved_pct']}% non'),
            eqTile('P&L since month-end', eqSigned(pnl), color: eqTone(pnl), hint: 'booked ${eqSigned(s['booked_pnl'])} · open ${eqSigned(liveMtm)}'),
            eqTile('Total limit used', '${eqMoney(limits['total_use_pct'])}%', hint: '${eqMoney(limits['total_used'])} of ${eqMoney(limits['total_limit'])}'),
            eqTile('Brokerage this month', eqMoney(s['brokerage_this_month'])),
          ],
        ),
      ),
      const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('HOLDINGS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kSectionLabelColor))),
      EqHoldingsList(holdings: holdings),
    ]);
  }
}

class EqPortfolioPage extends StatefulWidget {
  final bool isManager;
  const EqPortfolioPage({super.key, required this.isManager});
  @override
  State<EqPortfolioPage> createState() => _EqPortfolioPageState();
}

class _EqPortfolioPageState extends State<EqPortfolioPage> {
  Map<String, dynamic>? _data;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    if (widget.isManager) {
      _load();
      _poll = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await context.read<EqApi>().holdings();
      if (!mounted) return;
      setState(() { _data = d; _error = null; });
      context.read<EqLive>().add((d['holdings'] as List).map((h) => (h['instrument_token'] as num).toInt()));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isManager) return ListView(children: const [EqAccountView(), SizedBox(height: 24)]);
    if (_error != null && _data == null) return Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: kColorSell)));
    if (_data == null) return const Center(child: CircularProgressIndicator());
    final t = _data!['totals'] as Map;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6, crossAxisSpacing: 6, childAspectRatio: 2.4,
            children: [
              eqTile('Clients', eqQty(t['clients'])),
              eqTile('Holdings value', eqMoney(t['holdings_value'])),
              eqTile('Open MTM', eqSigned(t['open_mtm']), color: eqTone(t['open_mtm'])),
              eqTile('Funded', eqMoney(t['funded'])),
              eqTile('Interest this month', eqMoney(t['interest_this_month'])),
              eqTile('Loss alerts', eqQty(t['loss_alerts']), color: eqNum(t['loss_alerts']) > 0 ? kColorSell : null),
            ],
          ),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(12, 0, 12, 4), child: Text('HOLDINGS BY CLIENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kSectionLabelColor))),
        EqHoldingsList(holdings: _data!['holdings'] as List, showClient: true),
        const SizedBox(height: 24),
      ]),
    );
  }
}
