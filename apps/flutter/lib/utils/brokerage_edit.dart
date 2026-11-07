import 'dart:convert';

/// Edit forms (7 Nov 2026): a segment's brokerage is saved only when it was
/// changed, so an unrelated edit (password, limits…) never flattens an
/// account's per-script rates to one value; a segment holding several rates
/// is flagged as "mixed"; and a refused save (e.g. below the parent's rate)
/// is reported instead of silently ignored.

/// 2 → "2", 1.75 → "1.75" — the same text the rate field shows.
String brokerageText(num v) => v % 1 == 0 ? v.toInt().toString() : v.toString();

/// True when an account's rows for one segment don't all share one rate.
bool brokerageIsMixed(List items) {
  final values = <num>{};
  for (final i in items) {
    final v = i is Map ? i['brk_value'] : null;
    if (v is num) values.add(v);
  }
  return values.length > 1;
}

/// Null when the save went through, else a short reason for the snack bar.
String? brokerageSaveError(String exchange, dynamic res) {
  if (res.statusCode == 200 || res.statusCode == 201) return null;
  String msg = '';
  try {
    msg = (jsonDecode(res.body)['message'] ?? '').toString();
  } catch (_) {}
  return '$exchange: ${msg.isEmpty ? 'not saved (${res.statusCode})' : msg}';
}
