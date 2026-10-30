/// Utility class to check if market is open for trading.
/// Exchange-specific hours (all times IST):
///   NSE/NFO/BFO/BSE : 9:16 AM – 3:40 PM
///   MCX             : 9:01 AM – 11:30 PM in US summer time,
///                      9:01 AM – 11:55 PM in US winter (from the Monday after
///                      the US clock change — 2 Nov 2026 – 12 Mar 2027)
///   GIFT NIFTY      : Session 1: 6:30 AM – 3:40 PM
///                      Session 2: 4:35 PM – 2:45 AM (next day)
///   GLOBAL/COMEX    : CME/COMEX Globex — near-24h, closed only for the
///                      ~1h daily maintenance break (~2:00–3:30 AM IST in US
///                      summer time, ~3:00–4:30 AM IST in US winter)
///   Others          : 12:00 AM – 2:30 AM  &  7:30 AM – 11:59 PM
/// Special sessions on a closed day (_specialSessions — Sunday 8 Nov 2026
/// Diwali Muhurat: NSE F&O 2:20–3:40 PM, MCX 2:20–3:30 PM). Same calendar as
/// the backend's utils/specialSessions.js and the web's lib/marketHours.ts.
class MarketHours {
  static const int _summerMcxClose = 23 * 60 + 30;
  static const int _winterMcxClose = 23 * 60 + 55;

  /// Special sessions: IST date → { 'NSE' | 'MCX': [open, close] minutes }.
  static const Map<String, Map<String, List<int>>> _specialSessions = {
    '2026-11-08': {
      'NSE': [14 * 60 + 20, 15 * 60 + 40],
      'MCX': [14 * 60 + 20, 15 * 60 + 30],
    },
  };
  static const Map<String, String> _specialSessionText = {
    'NSE': 'Muhurat trading today: F&O 2:20–3:40 PM only',
    'MCX': 'Muhurat trading today: MCX 2:20–3:30 PM only',
  };

  /// Converts the device's current instant to IST wall-clock time via UTC,
  /// rather than trusting `DateTime.now()` to already BE IST. The device's
  /// local timezone previously went unconverted — a user travelling in
  /// Dubai (IST−1:30) at 3:00 PM local (4:30 PM IST) would see the market
  /// as still open past its real 3:40 PM IST close, and honest overseas
  /// users got wrong open/closed results in both directions. This does NOT
  /// protect against a tampered system clock (the backend's own market-
  /// hours enforcement is the real gate for that) — it only fixes
  /// legitimate users in a different timezone from IST getting the wrong
  /// answer.
  static DateTime _nowInIst() {
    final utc = DateTime.now().toUtc();
    return utc.add(const Duration(hours: 5, minutes: 30));
  }

  static String _ymd(DateTime ist) =>
      '${ist.year.toString().padLeft(4, '0')}-${ist.month.toString().padLeft(2, '0')}-${ist.day.toString().padLeft(2, '0')}';

  /// `n`th Sunday (1-based) of a month.
  static DateTime _nthSunday(int year, int month, int n) {
    final firstWeekday = DateTime.utc(year, month, 1).weekday; // 7 = Sunday
    return DateTime.utc(year, month, 1 + (7 - firstWeekday) % 7 + (n - 1) * 7);
  }

  /// US daylight-saving time on this IST date: from the second Sunday of
  /// March to the first Sunday of November.
  static bool _usSummerTime(DateTime ist) {
    final day = DateTime.utc(ist.year, ist.month, ist.day);
    return !day.isBefore(_nthSunday(ist.year, 3, 2)) && day.isBefore(_nthSunday(ist.year, 11, 1));
  }

  static int _mcxClose(DateTime ist) => _usSummerTime(ist) ? _summerMcxClose : _winterMcxClose;

  /// GLOBAL/COMEX daily break [start, end) in IST minutes — an hour later in US winter.
  static List<int> _cmeBreak(DateTime ist) => _usSummerTime(ist) ? [120, 210] : [180, 270];

  static String _clock(int minutes) {
    final h = (minutes ~/ 60) % 24;
    final m = minutes % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
  }

  static bool _isNseExchange(String ex) =>
      ex == 'NSE' || ex == 'NFO' || ex == 'BFO' || ex == 'BSE' || ex.isEmpty;

  /// The special-session window key for this exchange/symbol (never GIFT/GLOBAL/COMEX).
  static String? _sessionKey(String ex, String sym) {
    if (_isGiftNifty(ex, sym)) return null;
    if (ex == 'MCX') return 'MCX';
    if (_isNseExchange(ex)) return 'NSE';
    return null;
  }

  /// Check if market is open for the given exchange + tradingsymbol.
  /// Falls back to NSE hours when no exchange is provided.
  static bool isMarketOpen({String? exchange, String? tradingsymbol}) {
    final now = _nowInIst();
    final mins = now.hour * 60 + now.minute;
    final ex = (exchange ?? '').toUpperCase();
    final sym = (tradingsymbol ?? '').toUpperCase();

    // Weekends are off for all exchanges — except a special session's own window.
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      final key = _sessionKey(ex, sym);
      final window = key == null ? null : _specialSessions[_ymd(now)]?[key];
      return window != null && mins >= window[0] && mins <= window[1];
    }

    // GIFT NIFTY — check by tradingsymbol containing "NIFTY" on NSE_INDEX or
    // the exchange being "NSE" with the specific GIFT NIFTY symbol
    if (_isGiftNifty(ex, sym)) {
      // Session 1: 6:30 AM (390) – 3:40 PM (940)
      // Session 2: 4:35 PM (995) – 2:45 AM next day (165)
      //   i.e. 995..1440 today  OR  0..165 next-day (which is "today" at runtime)
      if (mins >= 390 && mins <= 940) return true;
      if (mins >= 995) return true; // 4:35 PM onwards
      if (mins <= 165) return true; // midnight – 2:45 AM
      return false;
    }

    if (ex == 'MCX') {
      // 9:01 AM (541) – 11:30 PM (1410), or 11:55 PM (1435) in US winter
      return mins >= 541 && mins <= _mcxClose(now);
    }

    if (ex == 'GLOBAL' || ex == 'COMEX') {
      // Closed only for CME/COMEX Globex's daily maintenance break:
      // ~2:00–3:30 AM IST in US summer time, ~3:00–4:30 AM in US winter.
      final brk = _cmeBreak(now);
      return mins < brk[0] || mins >= brk[1];
    }

    if (_isNseExchange(ex)) {
      // 9:16 AM (556) – 3:40 PM (940). Close is 3:40 PM, not the commonly-known
      // 3:30 PM cash-market close — confirmed against this platform's own
      // intraday square-off cron (cronService.js: NSE/NFO fires at 3:41 PM).
      return mins >= 556 && mins <= 940;
    }

    // Others: two sessions
    // Session 1: 12:00 AM (0) – 2:30 AM (150)
    // Session 2: 7:30 AM (450) – 11:59 PM (1439)
    if (mins <= 150) return true;
    if (mins >= 450) return true;
    return false;
    // return true;
  }

  /// User-friendly message about market status for the given exchange.
  static String getMarketStatusMessage({String? exchange, String? tradingsymbol}) {
    final now = _nowInIst();
    final ex = (exchange ?? '').toUpperCase();
    final sym = (tradingsymbol ?? '').toUpperCase();

    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      final key = _sessionKey(ex, sym);
      if (key != null && _specialSessions[_ymd(now)]?[key] != null) {
        return _specialSessionText[key]!;
      }
      return 'Market closed on weekends';
    }

    if (_isGiftNifty(ex, sym)) {
      return 'GIFT NIFTY: 6:30 AM–3:40 PM & 4:35 PM–2:45 AM';
    }
    if (ex == 'MCX') {
      return 'MCX hours: 9:01 AM – ${_clock(_mcxClose(now))}';
    }
    if (ex == 'GLOBAL' || ex == 'COMEX') {
      final brk = _cmeBreak(now);
      return 'Daily maintenance break: ${_clock(brk[0])} – ${_clock(brk[1])}';
    }
    if (_isNseExchange(ex)) {
      return 'Market hours: 9:16 AM – 3:40 PM';
    }
    return 'Trading hours: 12–2:30 AM & 7:30 AM–11:59 PM';
  }

  static bool _isGiftNifty(String exchange, String symbol) {
    // Real KiteInstrument tradingsymbol is literally "GIFT NIFTY" (with a
    // space) — confirmed against a real document. Neither of the two
    // no-space variants below ever actually matched it, silently falling
    // this instrument through to the generic two-session fallback hours
    // below instead of its own real near-24h schedule. Strip
    // whitespace/underscores before comparing so any of these spellings
    // match.
    final normalized = symbol.replaceAll(RegExp(r'[\s_]'), '');
    return normalized.contains('GIFTNIFTY');
  }
}
