// Equity orders and trades. Open orders can be cancelled; refused orders stay listed
// with the reason (the equity rejection log). Refreshes on 'cash_order' pushes.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';
import 'eq_format.dart';
import 'eq_live.dart';
import 'package:stocker/utils/account_label.dart';

class EqOrdersPage extends StatefulWidget {
  final bool isManager;
  final String? clientId;
  const EqOrdersPage({super.key, required this.isManager, this.clientId});
  @override
  State<EqOrdersPage> createState() => _EqOrdersPageState();
}

class _EqOrdersPageState extends State<EqOrdersPage> {
  bool _showTrades = false;
  List<dynamic> _orders = [];
  List<dynamic> _trades = [];
  Map<String, String> _names = {};
  String? _error;
  StreamSubscription? _sub;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = context.read<EqLive>().orderEvents.listen((_) => _load());
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _load());
    if (widget.isManager && widget.clientId == null) {
      context.read<EqApi>().clients().then((l) {
        if (mounted) setState(() => _names = {for (final c in l) c['_id'] as String: accountLabel(c['name'], c['username'])});
      }).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final api = context.read<EqApi>();
    try {
      final today = eqTodayIst();
      final o = await api.orders(clientId: widget.clientId, date: today);
      final t = await api.trades(clientId: widget.clientId, date: today);
      if (mounted) setState(() { _orders = o; _trades = t; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _cancel(String id) async {
    try {
      await context.read<EqApi>().cancelOrder(id);
      await _load();
    } catch (e) {
      if (mounted) eqSnack(context, e.toString(), ok: false);
    }
  }

  Color _statusColor(String s) => switch (s) {
        'OPEN' => kTintAmberFg,
        'FILLED' => kColorBuy,
        'REJECTED' => kColorSell,
        _ => kColorTextMuted,
      };

  @override
  Widget build(BuildContext context) {
    final showClient = widget.isManager && widget.clientId == null;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          for (final (label, trades) in [('Orders today', false), ('Trades today', true)])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(label), selected: _showTrades == trades, onSelected: (_) => setState(() => _showTrades = trades)),
            ),
        ]),
      ),
      if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: kColorSell))),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(children: [
            if (!_showTrades && _orders.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No orders today.', style: TextStyle(color: kColorTextMuted)))),
            if (_showTrades && _trades.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No trades today.', style: TextStyle(color: kColorTextMuted)))),
            if (!_showTrades)
              for (final o in _orders)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(o['side'] == 'B' ? 'BUY' : 'SELL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: o['side'] == 'B' ? kColorBuy : kColorSell)),
                      const SizedBox(width: 6),
                      Text(o['tradingsymbol'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 6),
                      eqCategoryTag(o['mtf'] == true),
                      const Spacer(),
                      Text(o['status'] == 'REJECTED' ? 'REFUSED' : o['status'].toString(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(o['status'].toString()))),
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      '${o['order_type'] == 'LIMIT' ? 'Limit ${eqMoney(o['limit_price'])}' : 'Market'} · ${eqQty(o['filled_qty'])} / ${eqQty(o['qty'])} filled${o['avg_price'] != null ? ' @ ${eqMoney(o['avg_price'])}' : ''}',
                      style: const TextStyle(fontSize: 11, color: kColorTextMuted),
                    ),
                    if (showClient) Text(_names[o['client_id']] ?? '', style: const TextStyle(fontSize: 11, color: kColorBuy)),
                    if ((o['reason'] ?? '').toString().isNotEmpty) Text(o['reason'].toString(), style: const TextStyle(fontSize: 11)),
                    if (o['status'] == 'OPEN')
                      Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => _cancel(o['_id'] as String), child: const Text('Cancel'))),
                  ]),
                ),
            if (_showTrades)
              for (final t in _trades)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    Text(t['side'] == 'B' ? 'BUY' : 'SELL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: t['side'] == 'B' ? kColorBuy : kColorSell)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t['tradingsymbol'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('${t['add_time'].toString().substring(11)}${showClient ? '  ·  ${_names[t['client_id']] ?? ''}' : ''}', style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
                      ]),
                    ),
                    Text('${eqQty(t['qty'])} @ ${eqMoney(t['price'])}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    ]);
  }
}
