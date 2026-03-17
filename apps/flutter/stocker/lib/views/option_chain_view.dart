import 'dart:async';
import 'package:flutter/material.dart';
import 'package:stocker/models/kite_instrument.dart';
import 'package:stocker/models/option_chain.dart';
import 'package:stocker/models/watchlist_item.dart';
import 'package:stocker/services/api_service.dart';
import 'package:stocker/services/kite_service.dart';
import 'package:stocker/utils/contants.dart';
import 'trade_card_view.dart';

class OptionChainView extends StatefulWidget {
  final KiteInstrument instrument;
  const OptionChainView({super.key, required this.instrument});
  @override
  State<OptionChainView> createState() => _OptionChainViewState();
}

class _OptionChainViewState extends State<OptionChainView> {
  List<OptionChainItem> _optionChain = [];
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  late final KiteService _kiteService;

  // Expiry management
  List<DateTime> _availableExpiries = [];
  DateTime? _selectedExpiry;

  @override
  void initState() {
    super.initState();
    _kiteService = KiteService(ApiService(backendUrl));
    _loadOptionChain();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// Derive the base symbol to send to the backend.
  /// The backend does `new RegExp('^${tradingSymbol}', 'i')` against the
  /// `tradingsymbol` field, so we need the root name that all CE/PE contracts
  /// share as a prefix (e.g. "NIFTY", "BANKNIFTY", "US 30").
  String _deriveBaseSymbol() {
    final inst = widget.instrument;
    final type = inst.instrumentType;

    // If the instrument itself is already an option or future, extract the
    // base from its tradingsymbol by stripping the date+strike+CE/PE suffix.
    if (type == 'CE' || type == 'PE' || type == 'FUT') {
      // The `name` field on KiteInstrument is the underlying name
      // e.g. for "NIFTY26MAR22500CE" the name is "NIFTY"
      // e.g. for "US 3026MAR22500CE" the name is "US 30"
      if (inst.name.isNotEmpty) return inst.name;
    }

    // For EQ / index instruments, `name` is the full name like "NIFTY 50",
    // but the option contracts use just "NIFTY" as prefix. The
    // `tradingsymbol` for the index is "NIFTY 50" — we need "NIFTY".
    // However, for commodities like "US 30", the options use "US 30" prefix.
    // So use `name` if it's a known multi-word symbol, else use tradingsymbol.
    if (inst.name.isNotEmpty) return inst.name;
    return inst.tradingsymbol;
  }

  Future<void> _loadOptionChain() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final symbol = _deriveBaseSymbol();
      final expiryStr = _selectedExpiry != null
          ? '${_selectedExpiry!.year}-${_selectedExpiry!.month.toString().padLeft(2, '0')}-${_selectedExpiry!.day.toString().padLeft(2, '0')}'
          : null;
      final chain = await _kiteService.getOptionChain(symbol, expiry: expiryStr);
      _extractExpiries(chain);
      setState(() { _optionChain = chain; _isLoading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _silentRefresh() async {
    if (_isLoading || _optionChain.isEmpty) return;
    try {
      final symbol = _deriveBaseSymbol();
      final expiryStr = _selectedExpiry != null
          ? '${_selectedExpiry!.year}-${_selectedExpiry!.month.toString().padLeft(2, '0')}-${_selectedExpiry!.day.toString().padLeft(2, '0')}'
          : null;
      final chain = await _kiteService.getOptionChain(symbol, expiry: expiryStr);
      if (mounted) setState(() => _optionChain = chain);
    } catch (_) {}
  }

  void _extractExpiries(List<OptionChainItem> chain) {
    final expirySet = <DateTime>{};
    for (final item in chain) {
      if (item.call?.expiry != null) expirySet.add(_dateOnly(item.call!.expiry!));
      if (item.put?.expiry != null) expirySet.add(_dateOnly(item.put!.expiry!));
    }
    final sorted = expirySet.toList()..sort();
    if (mounted && _availableExpiries.isEmpty && sorted.isNotEmpty) {
      setState(() { _availableExpiries = sorted; });
    }
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _fmtExpiry(DateTime d) {
    const months = ['JAN','FEB','MAR','APR','MAY','JUN','JUL','AUG','SEP','OCT','NOV','DEC'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  void _onExpiryChanged(DateTime? expiry) {
    setState(() => _selectedExpiry = expiry);
    _loadOptionChain();
  }

  void _openTradeCard(OptionData option) {
    final inst = KiteInstrument(
      id: '',
      instrumentToken: option.instrumentToken,
      exchangeToken: '',
      tradingsymbol: option.tradingSymbol,
      name: option.name,
      rawName: option.name,
      displayName: '${option.name} ${option.strike.toInt()} ${option.instrumentType}',
      lastPrice: option.lastPrice,
      expiry: option.expiry,
      strike: option.strike,
      tickSize: 0.05,
      lotSize: option.lotSize,
      instrumentType: option.instrumentType,
      segment: 'NFO-OPT',
      exchange: option.exchange.isNotEmpty ? option.exchange : 'NFO',
      isActive: true,
      updatedAt: DateTime.now(),
    );
    final item = WatchlistItem(
      id: 'oc_${option.instrumentToken}',
      instrument: inst,
      currentPrice: option.lastPrice,
    );
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => TradeCardPage(item: item),
    ));
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
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    'Option Chain',
                    style: const TextStyle(color: Colors.black, fontSize: 18, fontFamily: 'Inter', fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _deriveBaseSymbol(),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w500, letterSpacing: -0.3),
                  ),
                ]),
              ),
              // Live indicator
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  const Text('LIVE', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontFamily: 'Inter', fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                ]),
              ),
            ]),
          ),

          // Expiry selector
          if (_availableExpiries.isNotEmpty)
            Container(
              height: 38,
              margin: const EdgeInsets.only(bottom: 12),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _availableExpiries.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) return _buildExpiryChip('All', _selectedExpiry == null, () => _onExpiryChanged(null));
                  final exp = _availableExpiries[i - 1];
                  final isSelected = _selectedExpiry != null && _dateOnly(_selectedExpiry!) == _dateOnly(exp);
                  return _buildExpiryChip(_fmtExpiry(exp), isSelected, () => _onExpiryChanged(exp));
                },
              ),
            ),

          // Column headers
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(children: const [
              Expanded(child: _HeaderLabel('CALL', alignment: TextAlign.center)),
              Expanded(child: _HeaderLabel('VOL', alignment: TextAlign.center)),
              SizedBox(width: 70, child: _HeaderLabel('STRIKE', alignment: TextAlign.center)),
              Expanded(child: _HeaderLabel('VOL', alignment: TextAlign.center)),
              Expanded(child: _HeaderLabel('PUT', alignment: TextAlign.center)),
            ]),
          ),

          // Chain data
          Expanded(child: _buildBody()),
        ]),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF3F45C7), strokeWidth: 2.5));
    }
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 40, color: Color(0xFFEF4444)),
          const SizedBox(height: 12),
          Text('Failed to load option chain', style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(_error!, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontFamily: 'Inter'), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _loadOptionChain,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFF3F45C7), borderRadius: BorderRadius.circular(10)),
              child: const Text('Retry', style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ));
    }
    if (_optionChain.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.show_chart, size: 40, color: const Color(0xFF94A3B8).withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        const Text('No option chain data', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
      ]));
    }
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _optionChain.length,
        itemBuilder: (_, i) => _buildRow(_optionChain[i], i),
      ),
    );
  }

  Widget _buildRow(OptionChainItem item, int index) {
    final isEven = index % 2 == 0;
    return Container(
      decoration: BoxDecoration(
        color: isEven ? Colors.white : const Color(0xFFFAFBFC),
        border: Border(bottom: BorderSide(color: const Color(0xFFF1F5F9), width: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(children: [
          // CALL price — tappable
          Expanded(child: _buildPriceCell(item.call, const Color(0xFF10B981), () {
            if (item.call != null) _openTradeCard(item.call!);
          })),
          // CALL volume
          Expanded(child: _buildVolCell(item.call?.volumeDisplay ?? '--')),
          // Strike
          SizedBox(
            width: 70,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border.symmetric(vertical: BorderSide(color: const Color(0xFFF1F5F9), width: 0.5)),
              ),
              child: Text(
                item.strike.toStringAsFixed(item.strike == item.strike.roundToDouble() ? 0 : 2),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF3F45C7), fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w700, letterSpacing: -0.3),
              ),
            ),
          ),
          // PUT volume
          Expanded(child: _buildVolCell(item.put?.volumeDisplay ?? '--')),
          // PUT price — tappable
          Expanded(child: _buildPriceCell(item.put, const Color(0xFFEF4444), () {
            if (item.put != null) _openTradeCard(item.put!);
          })),
        ]),
      ),
    );
  }

  Widget _buildPriceCell(OptionData? data, Color accentColor, VoidCallback onTap) {
    if (data == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('--', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, fontFamily: 'Inter')),
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(
            data.lastPrice > 0 ? data.lastPrice.toStringAsFixed(2) : '--',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black, fontSize: 13, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: -0.3),
          ),
          if (data.lotSize > 0) ...[
            const SizedBox(height: 2),
            Text(
              'Lot ${data.lotSize}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontFamily: 'Inter', fontWeight: FontWeight.w500),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _buildVolCell(String vol) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(vol, textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Inter', fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildExpiryChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3F45C7) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? null : [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Text(label, style: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF64748B),
          fontSize: 12, fontFamily: 'Inter', fontWeight: FontWeight.w600,
        )),
      ),
    );
  }
}

class _HeaderLabel extends StatelessWidget {
  final String text;
  final TextAlign alignment;
  const _HeaderLabel(this.text, {this.alignment = TextAlign.center});
  @override
  Widget build(BuildContext context) {
    return Text(text, textAlign: alignment, style: const TextStyle(
      color: Color(0xFF94A3B8), fontSize: 11, fontFamily: 'Inter', fontWeight: FontWeight.w600, letterSpacing: 0.5,
    ));
  }
}
