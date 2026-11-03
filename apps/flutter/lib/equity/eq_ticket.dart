// Equity order ticket — the same ticket for clients and for masters/admin (who pick
// the client). Shows what the server checks: held / can sell (no short selling),
// per-script and total limit room, MTF / NON rates, live depth, and whether a MARKET
// order is allowed now (low-volume rules — otherwise LIMIT only).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';
import 'eq_format.dart';
import 'eq_live.dart';

Future<void> showEqTicket(BuildContext context,
    {required int token, required String symbol, String side = 'B', String? clientId, required bool isManager}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => MultiProvider(
      providers: [
        Provider<EqApi>.value(value: context.read<EqApi>()),
        ChangeNotifierProvider<EqLive>.value(value: context.read<EqLive>()),
      ],
      child: _Ticket(token: token, symbol: symbol, side: side, clientId: clientId, isManager: isManager),
    ),
  );
}

class _Ticket extends StatefulWidget {
  final int token;
  final String symbol;
  final String side;
  final String? clientId;
  final bool isManager;
  const _Ticket({required this.token, required this.symbol, required this.side, this.clientId, required this.isManager});
  @override
  State<_Ticket> createState() => _TicketState();
}

class _TicketState extends State<_Ticket> {
  late String _side = widget.side;
  String _type = 'MARKET';
  String? _clientId;
  List<dynamic> _clients = [];
  Map<String, dynamic>? _preview;
  String? _error;
  String? _result;
  bool _resultOk = true;
  bool _busy = false;
  final _qty = TextEditingController();
  final _limit = TextEditingController();

  @override
  void initState() {
    super.initState();
    _clientId = widget.clientId;
    context.read<EqLive>().add([widget.token]);
    if (widget.isManager) {
      context.read<EqApi>().clients().then((l) {
        if (mounted) setState(() => _clients = l.where((c) => c['status'] == 'active').toList());
      }).catchError((_) {});
    }
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    if (widget.isManager && (_clientId == null || _clientId!.isEmpty)) return;
    try {
      final p = await context.read<EqApi>().preview(widget.token, clientId: widget.isManager ? _clientId : null);
      if (mounted) setState(() { _preview = p; _error = null; });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    final q = int.tryParse(_qty.text.trim());
    if (q == null || q <= 0) { setState(() { _result = 'Enter a whole number of shares.'; _resultOk = false; }); return; }
    final lim = double.tryParse(_limit.text.trim());
    if (_type == 'LIMIT' && (lim == null || lim <= 0)) { setState(() { _result = 'Enter a limit price.'; _resultOk = false; }); return; }
    setState(() { _busy = true; _result = null; });
    try {
      final o = await context.read<EqApi>().placeOrder({
        if (widget.isManager) 'client_id': _clientId,
        'instrument_token': widget.token, 'side': _side, 'qty': q, 'order_type': _type,
        if (_type == 'LIMIT') 'limit_price': lim,
      });
      final text = o['status'] == 'FILLED'
          ? 'Filled ${eqQty(o['filled_qty'])} @ ${eqMoney(o['avg_price'])}'
          : ((o['reason'] ?? '').toString().isNotEmpty ? o['reason'].toString() : 'Order placed');
      setState(() { _result = text; _resultOk = true; });
      _loadPreview();
    } catch (e) {
      setState(() { _result = e.toString(); _resultOk = false; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _sideButton(String s, String label, dynamic price) {
    final on = _side == s;
    final color = s == 'B' ? kColorBuy : kColorSell;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _side = s),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: on ? color.withValues(alpha: 0.10) : kChipBg,
            border: Border.all(color: on ? color : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: on ? color : kChipFg)),
            Text(eqMoney(price), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: on ? color : kColorTextPrimary)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final live = context.watch<EqLive>().quotes[widget.token];
    final q = live ?? (_preview?['quote'] as Map?)?.cast<String, dynamic>();
    final p = _preview;
    final marketBlock = p == null ? null : (_side == 'B' ? p['market']['market_buy'] : p['market']['market_sell']);
    final depth = q?['depth'] as Map?;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text(widget.symbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              if (p != null) eqCategoryTag(p['stock']['mtf'] == true),
              const Spacer(),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
            if (widget.isManager) ...[
              DropdownButtonFormField<String>(
                initialValue: _clientId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Client', isDense: true),
                items: _clients.map((c) => DropdownMenuItem<String>(value: c['_id'] as String, child: Text('${c['name']} (${c['username']})'))).toList(),
                onChanged: (v) { setState(() { _clientId = v; _preview = null; }); _loadPreview(); },
              ),
              const SizedBox(height: 8),
            ],
            Row(children: [
              _sideButton('S', 'SELL', q?['bid_price'] ?? q?['last_price']),
              const SizedBox(width: 8),
              _sideButton('B', 'BUY', q?['ask_price'] ?? q?['last_price']),
            ]),
            if (q != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('LTP ${eqMoney(q['last_price'])}  O ${eqMoney(q['open'])}  H ${eqMoney(q['high'])}  L ${eqMoney(q['low'])}  C ${eqMoney(q['close'])}',
                    style: const TextStyle(fontSize: 11, color: kColorTextMuted)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: _qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Shares', isDense: true))),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Type', isDense: true),
                  items: const [DropdownMenuItem(value: 'MARKET', child: Text('Market')), DropdownMenuItem(value: 'LIMIT', child: Text('Limit'))],
                  onChanged: (v) => setState(() => _type = v ?? 'MARKET'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _limit, enabled: _type == 'LIMIT', keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Limit price', isDense: true))),
            ]),
            if (_type == 'MARKET' && marketBlock != null)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: kTintAmberBg, borderRadius: BorderRadius.circular(8)),
                child: Text(marketBlock.toString(), style: const TextStyle(fontSize: 12, color: kTintAmberFg)),
              ),
            if (p?['market']['closed'] != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(p!['market']['closed'].toString(), style: const TextStyle(fontSize: 12, color: kColorTextMuted))),
            if (p != null) ...[
              const SizedBox(height: 10),
              Text('${p['rates']['category']} · interest ${p['rates']['interest_pct']}% / yr · brokerage intraday ${p['rates']['brokerage']['intraday']}${p['rates']['brokerage']['mode'] == 'PCT' ? '%' : ''} · carry ${p['rates']['brokerage']['carry']}${p['rates']['brokerage']['mode'] == 'PCT' ? '%' : ''}',
                  style: const TextStyle(fontSize: 11, color: kColorTextMuted)),
              Text('Held ${eqQty(p['held'])} · can sell ${eqQty(p['sellable'])}', style: const TextStyle(fontSize: 12)),
              Text('This stock: room ${eqMoney(p['limits']['per_script']['room'])} of ${eqMoney(p['limits']['per_script']['limit'])}', style: const TextStyle(fontSize: 12)),
              Text('Total: room ${eqMoney(p['limits']['total']['room'])} of ${eqMoney(p['limits']['total']['limit'])}', style: const TextStyle(fontSize: 12)),
            ],
            if (depth != null) ...[
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (final k in ['buy', 'sell'])
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k == 'buy' ? 'BIDS' : 'OFFERS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: k == 'buy' ? kColorBuy : kColorSell)),
                      for (final l in (depth[k] as List? ?? []))
                        Text('${eqMoney(l['price'])}   ${eqQty(l['qty'])}', style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
              ]),
            ],
            const SizedBox(height: 6),
            const Text('Low volume: orders fill only against the real NSE depth and a share of the volume the stock trades — big orders may fill in parts. Day order: unfilled part expires at 15:30.',
                style: TextStyle(fontSize: 10, color: kColorTextMuted)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: const TextStyle(color: kColorSell, fontSize: 12))),
            if (_result != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_result!, style: TextStyle(color: _resultOk ? kColorBuy : kColorSell, fontSize: 13, fontWeight: FontWeight.w600))),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _busy || p == null ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: _side == 'B' ? kColorBuy : kColorSell, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              child: Text(_busy ? 'Placing…' : (_side == 'B' ? 'BUY' : 'SELL')),
            ),
          ]),
        ),
      ),
    );
  }
}
