/// Utility class to check if market is open for trading.
/// Exchange-specific hours (all times IST):
///   NSE/NFO/BFO/BSE : 9:16 AM – 3:30 PM
///   MCX             : 9:01 AM – 11:30 PM
///   GIFT NIFTY      : Session 1: 6:30 AM – 3:40 PM
///                      Session 2: 4:35 PM – 2:45 AM (next day)
///   Others          : 12:00 AM – 2:30 AM  &  7:30 AM – 11:59 PM
class MarketHours {
  /// Check if market is open for the given exchange + tradingsymbol.
  /// Falls back to NSE hours when no exchange is provided.
  static bool isMarketOpen({String? exchange, String? tradingsymbol}) {
    
    final now = DateTime.now();

    // Weekends are off for all exchanges
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }

    final mins = now.hour * 60 + now.minute;
    final ex = (exchange ?? '').toUpperCase();
    final sym = (tradingsymbol ?? '').toUpperCase();

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
      // 9:01 AM (541) – 11:30 PM (1410)
      return mins >= 541 && mins <= 1410;
    }

    if (ex == 'NSE' || ex == 'NFO' || ex == 'BFO' || ex == 'BSE' || ex.isEmpty) {
      // 9:16 AM (556) – 3:30 PM (930)
      return mins >= 556 && mins <= 930;
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
    final now = DateTime.now();

    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return 'Market closed on weekends';
    }

    final ex = (exchange ?? '').toUpperCase();
    final sym = (tradingsymbol ?? '').toUpperCase();

    if (_isGiftNifty(ex, sym)) {
      return 'GIFT NIFTY: 6:30 AM–3:40 PM & 4:35 PM–2:45 AM';
    }
    if (ex == 'MCX') {
      return 'MCX hours: 9:01 AM – 11:30 PM';
    }
    if (ex == 'NSE' || ex == 'NFO' || ex == 'BFO' || ex == 'BSE' || ex.isEmpty) {
      return 'Market hours: 9:16 AM – 3:30 PM';
    }
    return 'Trading hours: 12–2:30 AM & 7:30 AM–11:59 PM';
  }

  static bool _isGiftNifty(String exchange, String symbol) {
    // GIFT NIFTY typically trades on NSE with a specific symbol
    return symbol.contains('GIFTNIFTY') || symbol.contains('GIFT_NIFTY');
  }
}
