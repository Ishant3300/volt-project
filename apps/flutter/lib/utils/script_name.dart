/// Display name for the Massive-fed GLOBAL index futures and COMEX metals
/// (owner, 12 Nov 2026: "DOW AND OTHER GLOBAL SCRIPT NAME IS COMING IN SHORT"
/// → "DOW JONES 30 18 DEC"). Their tradingsymbol is a raw futures ticker
/// (YMZ6 = Dow Jones December 2026).
///
/// Display only — the tradingsymbol stays the key everywhere (orders,
/// matching, exports; bills / PDFs are untouched).
///
/// The day is the platform's own expiry: the instrument's when the screen has
/// it, otherwise worked out exactly as the backend sets it
/// (apps/backend/scripts/seedGlobalFutures.js):
///   - ES / NQ / YM / RTY: last trade date = 3rd Friday of the month
///   - NKD: last trade date = business day before the 2nd Friday
///   - GC / SI / HG: first notice day = last weekday of the month BEFORE delivery
/// Same rules as the web portal's src/lib/scriptName.ts.
library;

const Map<String, String> _rootNames = {
  'ES': 'S&P 500',
  'NQ': 'Nasdaq 100',
  'YM': 'Dow Jones 30',
  'RTY': 'Russell 2000',
  'NKD': 'Nikkei 225',
  'GC': 'Gold',
  'SI': 'Silver',
  'HG': 'Copper',
};
const Set<String> _comexRoots = {'GC', 'SI', 'HG'};
const String _monthCodes = 'FGHJKMNQUVXZ';
const List<String> _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
final RegExp _tickerRe = RegExp(r'^(ES|NQ|YM|RTY|NKD|GC|SI|HG)([FGHJKMNQUVXZ])(\d{1,2})$');

class GlobalTicker {
  final String root;
  final int month; // 1–12, the contract (delivery) month
  final int year;
  const GlobalTicker(this.root, this.month, this.year);
}

/// `YMZ6` → GlobalTicker('YM', 12, 2026); null for anything else.
GlobalTicker? parseGlobalTicker(String? tradingsymbol, {DateTime? now}) {
  final m = _tickerRe.firstMatch((tradingsymbol ?? '').trim().toUpperCase());
  if (m == null) return null;
  final digitsText = m.group(3)!;
  final digits = int.parse(digitsText);
  final thisYear = (now ?? DateTime.now().toUtc()).year;
  int year;
  if (digitsText.length == 2) {
    year = (thisYear ~/ 100) * 100 + digits;
  } else {
    // One year digit: the nearest year ending in it (a few years back for history).
    year = (thisYear ~/ 10) * 10 + digits;
    if (year < thisYear - 3) {
      year += 10;
    } else if (year > thisYear + 6) {
      year -= 10;
    }
  }
  return GlobalTicker(m.group(1)!, _monthCodes.indexOf(m.group(2)!) + 1, year);
}

DateTime _nthFriday(int year, int month, int n) {
  var d = DateTime.utc(year, month, 1);
  while (d.weekday != DateTime.friday) {
    d = d.add(const Duration(days: 1));
  }
  return d.add(Duration(days: 7 * (n - 1)));
}

DateTime _previousWeekday(DateTime d) {
  var out = d.subtract(const Duration(days: 1));
  while (out.weekday == DateTime.saturday || out.weekday == DateTime.sunday) {
    out = out.subtract(const Duration(days: 1));
  }
  return out;
}

/// The platform expiry for a parsed ticker (UTC midnight).
DateTime derivedExpiry(GlobalTicker t) {
  if (_comexRoots.contains(t.root)) {
    // Last weekday of the month before delivery (day 0 = last day of the previous month).
    var d = DateTime.utc(t.year, t.month, 0);
    while (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }
  if (t.root == 'NKD') return _previousWeekday(_nthFriday(t.year, t.month, 2));
  return _nthFriday(t.year, t.month, 3);
}

DateTime? _validDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final s = value.toString().trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

/// `DOW JONES 30 18 DEC` for a GLOBAL / COMEX futures ticker, or null when the
/// symbol isn't one (callers then show what they showed before).
/// [expiry] may be a DateTime or an ISO string.
String? globalScriptName(String? tradingsymbol, {String? name, Object? expiry}) {
  final t = parseGlobalTicker(tradingsymbol);
  if (t == null) return null;
  final n = (name ?? '').trim();
  final base = (n.isNotEmpty ? n : _rootNames[t.root]!).toUpperCase();
  final given = _validDate(expiry);
  // Expiries are stored as UTC midnight — read them in UTC so no timezone shifts the day.
  final exp = given != null ? given.toUtc() : derivedExpiry(t);
  return '$base ${exp.day} ${_months[exp.month - 1]}';
}

/// Any tradingsymbol for display: the long name for GLOBAL / COMEX tickers, unchanged otherwise.
String scriptLabel(String? tradingsymbol, {String? name, Object? expiry}) =>
    globalScriptName(tradingsymbol, name: name, expiry: expiry) ?? (tradingsymbol ?? '');
