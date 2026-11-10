import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/trade_metrics_provider.dart';
import '../utils/contants.dart';
import '../utils/profit_hold.dart';

const Color _kHoldBg = Color(0xFFE5E7EB);
const Color _kHoldText = Color(0xFF4B5563);
const Color _kChipBg = Color(0xFFFEF3C7);
const Color _kChipText = Color(0xFF92400E);

/// The order card's closing button while the profit-book hold applies: a grey,
/// untappable timer instead of SELL / BUY (utils/profit_hold.dart). With no
/// lock it is exactly the GestureDetector it replaces.
class HoldGate extends StatelessWidget {
  final HoldLock? lock;
  final VoidCallback? onTap;
  final Widget child;
  final String unit;
  const HoldGate({super.key, required this.lock, required this.onTap, required this.child, this.unit = 'qty'});

  @override
  Widget build(BuildContext context) {
    final l = lock;
    if (l == null) return GestureDetector(onTap: onTap, child: child);
    return Container(
      height: 56,
      width: double.infinity,
      decoration: BoxDecoration(color: _kHoldBg, borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.schedule, size: 18, color: _kHoldText),
              const SizedBox(width: 6),
              Text(formatHoldLeft(l.left),
                  style: const TextStyle(color: _kHoldText, fontSize: kFontSizeSectionHeader, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
            ],
          ),
          Text(l.freeNow > 0 ? 'In profit · up to ${l.freeNow} $unit now' : 'In profit · close after timer',
              style: const TextStyle(color: _kHoldText, fontSize: 11, fontFamily: kFontFamily)),
        ],
      ),
    );
  }
}

/// Amber "Profit close in 6:41" under a position while closing it now would be
/// refused (in profit, inside the hold). Ticks every second; gone otherwise.
class ProfitHoldChip extends StatefulWidget {
  final PositionAgg position;
  const ProfitHoldChip({super.key, required this.position});

  @override
  State<ProfitHoldChip> createState() => _ProfitHoldChipState();
}

class _ProfitHoldChipState extends State<ProfitHoldChip> {
  Timer? _tick;

  void _sync() {
    if (widget.position.profitHold != null) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant ProfitHoldChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.position;
    // The position's CMP is the closing price: bid for a BUY position, ask for a SELL one.
    final lock = profitHoldLock(
      hold: p.profitHold,
      netQty: p.netQty,
      side: p.netQty > 0 ? 'SELL' : 'BUY',
      orderType: 'MARKET',
      price: 0,
      bid: p.cmp,
      ask: p.cmp,
      qty: p.netQty.abs(),
    );
    if (lock == null) return const SizedBox.shrink();
    final text = lock.freeNow > 0
        ? 'Close ${lock.freeNow} now · rest in ${formatHoldLeft(lock.left)}'
        : 'Profit close in ${formatHoldLeft(lock.left)}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: _kChipBg, borderRadius: BorderRadius.circular(6)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule, size: 13, color: _kChipText),
            const SizedBox(width: 4),
            Text(text, style: const TextStyle(color: _kChipText, fontSize: 11, fontFamily: kFontFamily, fontWeight: kFontWeightSemiBold)),
          ],
        ),
      ),
    );
  }
}
