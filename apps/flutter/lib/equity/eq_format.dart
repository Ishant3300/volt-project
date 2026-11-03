// Number display for the equity screens — exact, Indian grouping, no currency sign
// (same rule as the rest of the app and the web portal).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stocker/utils/contants.dart';

final NumberFormat _two = NumberFormat('#,##,##0.00', 'en_IN');
final NumberFormat _int = NumberFormat('#,##,##0', 'en_IN');

double eqNum(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

String eqMoney(dynamic v) => v == null ? '—' : _two.format(eqNum(v));
String eqQty(dynamic v) => v == null ? '—' : _int.format(eqNum(v));
String eqSigned(dynamic v) {
  if (v == null) return '—';
  final n = eqNum(v);
  return '${n > 0 ? '+' : ''}${_two.format(n)}';
}

Color eqTone(dynamic v) {
  final n = eqNum(v);
  if (n > 0) return kColorBuy;
  if (n < 0) return kColorSell;
  return kColorTextMuted;
}

String eqDmy(String? d) => d == null || d.length < 10 ? '—' : d.substring(0, 10).split('-').reversed.join('-');

String eqTodayIst() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30)).toIso8601String().substring(0, 10);

/// MTF / NON tag (approved or non-approved script).
Widget eqCategoryTag(bool approved) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: approved ? kTintBlueBg : kChipBg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(approved ? 'MTF' : 'NON',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: approved ? kTintBlueFg : kChipFg)),
    );

/// A small label + value tile used on the account and portfolio screens.
Widget eqTile(String label, String value, {Color? color, String? hint}) => Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: kColorTextMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color ?? kColorTextPrimary)),
        if (hint != null) Text(hint, style: const TextStyle(fontSize: 9, color: kColorTextMuted), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
    );

void eqSnack(BuildContext context, String text, {bool ok = true}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: ok ? kColorBuy : kColorSell));
}
