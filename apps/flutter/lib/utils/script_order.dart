/// Script order for bills and position lists: name A→Z, one name's several
/// expiries nearest first (same order as the web portal's bill and
/// positions — apex-web-portal src/lib/pdf.ts / src/lib/risk.ts).
library;

import 'comex_bill.dart';

const Map<String, int> _months = {
  'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
  'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
};

final RegExp _symbolMonth = RegExp(r'(\d{2})(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)');
// Bill heading "NIFTY 24NOV2026" / "NIFTY 22500 CE 24NOV2026".
final RegExp _billDate = RegExp(r'\s+(\d{2})(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(\d{4})$');
// Report display name "NIFTY 24 NOV FUT" / "NIFTY 22500 CE 24 NOV".
final RegExp _shortDate = RegExp(r'\s+\d{1,2}\s+(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(\s+FUT)?$');

/// Expiry read from a futures symbol (`NIFTY26NOVFUT` → 2026·11) for ordering; 0 when there is none.
int symbolExpiryKey(String tradingsymbol) {
  final m = _symbolMonth.firstMatch(tradingsymbol.toUpperCase());
  if (m == null) return 0;
  return (2000 + int.parse(m.group(1)!)) * 10000 + _months[m.group(2)]! * 100;
}

/// Compares two scripts by name, then expiry, then trading symbol.
int compareScripts(String nameA, int expiryA, String symbolA, String nameB, int expiryB, String symbolB) {
  final byName = nameA.toUpperCase().compareTo(nameB.toUpperCase());
  if (byName != 0) return byName;
  final byExpiry = expiryA.compareTo(expiryB);
  if (byExpiry != 0) return byExpiry;
  return symbolA.compareTo(symbolB);
}

String _str(dynamic v) => (v ?? '').toString();

/// Bill / trade-report instruments (maps from GET /api/trade/report) in script
/// order — COMEX scripts (in dollars) together after all the others, so their
/// conversion line sits right under the whole group.
List<dynamic> sortBillInstruments(List<dynamic> instruments) {
  String nameOf(dynamic i) {
    final bill = _str(i['bill_name']).toUpperCase();
    if (bill.isNotEmpty) return bill.replaceFirst(_billDate, '');
    final display = _str(i['display_name']).toUpperCase();
    if (display.isNotEmpty) return display.replaceFirst(_shortDate, '');
    return _str(i['tradingsymbol']).toUpperCase();
  }

  int expiryOf(dynamic i) {
    final m = _billDate.firstMatch(_str(i['bill_name']).toUpperCase());
    if (m != null) {
      return int.parse(m.group(3)!) * 10000 + _months[m.group(2)]! * 100 + int.parse(m.group(1)!);
    }
    return symbolExpiryKey(_str(i['tradingsymbol']));
  }

  final list = [...instruments];
  int comexLast(dynamic i) => isComexExchange(i['exchange']) ? 1 : 0;
  list.sort((a, b) {
    final byComex = comexLast(a).compareTo(comexLast(b));
    if (byComex != 0) return byComex;
    return compareScripts(
        nameOf(a), expiryOf(a), _str(a['tradingsymbol']),
        nameOf(b), expiryOf(b), _str(b['tradingsymbol']));
  });
  return list;
}

/// Position maps (raw_name / name / tradingsymbol) in script order.
List<T> sortPositionMaps<T>(List<T> positions) {
  String nameOf(dynamic p) {
    final raw = _str(p['raw_name']);
    if (raw.isNotEmpty) return raw;
    final name = _str(p['name']);
    if (name.isNotEmpty) return name;
    return _str(p['tradingsymbol']);
  }

  final list = [...positions];
  list.sort((a, b) {
    final sa = _str((a as dynamic)['tradingsymbol']);
    final sb = _str((b as dynamic)['tradingsymbol']);
    return compareScripts(nameOf(a), symbolExpiryKey(sa), sa, nameOf(b), symbolExpiryKey(sb), sb);
  });
  return list;
}
