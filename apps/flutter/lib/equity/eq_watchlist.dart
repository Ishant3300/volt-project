// Equity watchlist: search NSE stocks, add / remove, live prices, B / S open the ticket.
// Its own list (eqcash_watchlist) — the F&O watchlist is not touched.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:stocker/utils/contants.dart';
import 'eq_api.dart';
import 'eq_format.dart';
import 'eq_live.dart';
import 'eq_ticket.dart';

class EqWatchlistPage extends StatefulWidget {
  final bool isManager;
  const EqWatchlistPage({super.key, required this.isManager});
  @override
  State<EqWatchlistPage> createState() => _EqWatchlistPageState();
}

class _EqWatchlistPageState extends State<EqWatchlistPage> {
  List<dynamic> _items = [];
  List<dynamic> _results = [];
  bool _loading = true;
  String? _error;
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await context.read<EqApi>().watchlist();
      if (!mounted) return;
      setState(() { _items = l; _loading = false; _error = null; });
      _watch();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  void _watch() {
    final tokens = <int>{
      ..._items.map((i) => (i['instrument_token'] as num).toInt()),
      ..._results.map((i) => (i['instrument_token'] as num).toInt()),
    };
    context.read<EqLive>().add(tokens);
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _results = []); return; }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final r = await context.read<EqApi>().search(q.trim());
        if (!mounted) return;
        setState(() => _results = r);
        _watch();
      } catch (_) {}
    });
  }

  Future<void> _add(int token) async {
    try {
      await context.read<EqApi>().addToWatchlist(token);
      await _load();
    } catch (e) {
      if (mounted) eqSnack(context, e.toString(), ok: false);
    }
  }

  Future<void> _remove(int token) async {
    try { await context.read<EqApi>().removeFromWatchlist(token); } catch (_) {}
    await _load();
  }

  Widget _row(Map item, {required bool inList}) {
    final token = (item['instrument_token'] as num).toInt();
    final q = context.watch<EqLive>().quotes[token] ?? (item['quote'] as Map?)?.cast<String, dynamic>();
    final symbol = item['tradingsymbol'].toString();
    final listed = _items.any((i) => (i['instrument_token'] as num).toInt() == token);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: () => showEqTicket(context, token: token, symbol: symbol, isManager: widget.isManager),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(symbol, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                eqCategoryTag(item['mtf'] == true),
              ]),
              Text(item['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: kColorTextMuted)),
            ]),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(eqMoney(q?['last_price']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          Text(q?['change_percent'] == null ? '—' : '${eqSigned(q!['change_percent'])}%', style: TextStyle(fontSize: 11, color: eqTone(q?['change_percent']))),
        ]),
        const SizedBox(width: 8),
        _btn('B', kColorBuy, () => showEqTicket(context, token: token, symbol: symbol, side: 'B', isManager: widget.isManager)),
        const SizedBox(width: 4),
        _btn('S', kColorSell, () => showEqTicket(context, token: token, symbol: symbol, side: 'S', isManager: widget.isManager)),
        if (inList)
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _remove(token), icon: const Icon(Icons.close, size: 16, color: kColorTextMuted))
        else if (listed)
          const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.check, size: 16, color: kColorBuy))
        else
          IconButton(visualDensity: VisualDensity.compact, onPressed: () => _add(token), icon: const Icon(Icons.add, size: 18, color: kColorBuy)),
      ]),
    );
  }

  Widget _btn(String t, Color c, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 26, height: 26, alignment: Alignment.center,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6)),
          child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            controller: _search,
            onChanged: _onSearch,
            decoration: InputDecoration(
              hintText: 'Search NSE stock — RELIANCE, INFY…',
              prefixIcon: const Icon(Icons.search),
              filled: true, fillColor: Colors.white, isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        for (final r in _results) _row(r as Map, inList: false),
        if (_results.isNotEmpty) const Divider(),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: kColorSell))),
        if (!_loading && _items.isEmpty && _error == null)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Search above and tap + to add a stock.', style: TextStyle(color: kColorTextMuted)))),
        for (final i in _items) _row(i as Map, inList: true),
        const SizedBox(height: 24),
      ]),
    );
  }
}
