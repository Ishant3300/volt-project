/// Utility class to check if market is open for trading
class MarketHours {
  // Indian stock market hours (IST)
  static const int marketOpenHour = 9;
  static const int marketOpenMinute = 15;
  static const int marketCloseHour = 15;
  static const int marketCloseMinute = 30;

  /// Check if the market is currently open
  /// Returns true if current time is between 9:15 AM and 3:30 PM on weekdays
  static bool isMarketOpen() {
    final now = DateTime.now();
    
    // Check if it's a weekend (Saturday = 6, Sunday = 7)
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return false;
    }

    // Convert current time to minutes since midnight for easier comparison
    final currentMinutes = now.hour * 60 + now.minute;
    final openMinutes = marketOpenHour * 60 + marketOpenMinute;
    final closeMinutes = marketCloseHour * 60 + marketCloseMinute;

    return currentMinutes >= openMinutes && currentMinutes <= closeMinutes;
  }

  /// Get a user-friendly message about market status
  static String getMarketStatusMessage() {
    final now = DateTime.now();
    
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
      return 'Market is closed on weekends';
    }

    final currentMinutes = now.hour * 60 + now.minute;
    final openMinutes = marketOpenHour * 60 + marketOpenMinute;
    final closeMinutes = marketCloseHour * 60 + marketCloseMinute;

    if (currentMinutes < openMinutes) {
      return 'Market opens at ${marketOpenHour}:${marketOpenMinute.toString().padLeft(2, '0')} AM';
    } else if (currentMinutes > closeMinutes) {
      return 'Market closed at ${marketCloseHour}:${marketCloseMinute.toString().padLeft(2, '0')} PM';
    }

    return 'Market is open';
  }

  /// Get market open time as formatted string
  static String getMarketOpenTime() {
    return '${marketOpenHour}:${marketOpenMinute.toString().padLeft(2, '0')} AM';
  }

  /// Get market close time as formatted string
  static String getMarketCloseTime() {
    final hour = marketCloseHour > 12 ? marketCloseHour - 12 : marketCloseHour;
    return '$hour:${marketCloseMinute.toString().padLeft(2, '0')} PM';
  }
}
