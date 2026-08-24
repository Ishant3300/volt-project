class KiteInstrument {
  final String id;
  final String instrumentToken;
  final String exchangeToken;
  final String tradingsymbol;
  final String name;
  final String rawName; // Original name from CSV
  final String displayName; // User-friendly mapped/generated name
  final double lastPrice;
  // OHLC from last trading day (populated after settlement)
  final double ohlcOpen;
  final double ohlcHigh;
  final double ohlcLow;
  final double ohlcClose;
  final DateTime? expiry;
  final double strike;
  final double tickSize;
  final int lotSize;
  final String instrumentType;
  final String segment;
  final String exchange;
  final bool isActive;
  final DateTime updatedAt;

  KiteInstrument({
    required this.id,
    required this.instrumentToken,
    required this.exchangeToken,
    required this.tradingsymbol,
    required this.name,
    required this.rawName,
    required this.displayName,
    required this.lastPrice,
    this.ohlcOpen = 0,
    this.ohlcHigh = 0,
    this.ohlcLow = 0,
    this.ohlcClose = 0,
    this.expiry,
    required this.strike,
    required this.tickSize,
    required this.lotSize,
    required this.instrumentType,
    required this.segment,
    required this.exchange,
    required this.isActive,
    required this.updatedAt,
  });

  factory KiteInstrument.fromJson(Map<String, dynamic> json) {
    final name = json['name'] ?? '';
    return KiteInstrument(
      id: json['_id'] ?? json['id'] ?? '',
      instrumentToken: (json['instrument_token'] ?? '').toString(),
      exchangeToken: json['exchange_token'] ?? '',
      tradingsymbol: json['tradingsymbol'] ?? '',
      name: name,
      rawName: json['raw_name'] ?? name,
      displayName: json['display_name'] ?? name,
      lastPrice: (json['last_price'] ?? 0).toDouble(),
      ohlcOpen: (json['ohlc_open'] ?? 0).toDouble(),
      ohlcHigh: (json['ohlc_high'] ?? 0).toDouble(),
      ohlcLow: (json['ohlc_low'] ?? 0).toDouble(),
      ohlcClose: (json['ohlc_close'] ?? 0).toDouble(),
      expiry: json['expiry'] != null
          ? DateTime.tryParse(json['expiry'].toString())
          : null,
      strike: (json['strike'] ?? 0).toDouble(),
      tickSize: (json['tick_size'] ?? 0).toDouble(),
      lotSize: json['lot_size'] ?? 0,
      instrumentType: json['instrument_type'] ?? '',
      segment: json['segment'] ?? '',
      exchange: json['exchange'] ?? '',
      isActive: json['is_active'] ?? true,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'instrument_token': instrumentToken,
      'exchange_token': exchangeToken,
      'tradingsymbol': tradingsymbol,
      'name': name,
      'raw_name': rawName,
      'display_name': displayName,
      'last_price': lastPrice,
      'ohlc_open': ohlcOpen,
      'ohlc_high': ohlcHigh,
      'ohlc_low': ohlcLow,
      'ohlc_close': ohlcClose,
      'expiry': expiry?.toIso8601String(),
      'strike': strike,
      'tick_size': tickSize,
      'lot_size': lotSize,
      'instrument_type': instrumentType,
      'segment': segment,
      'exchange': exchange,
      'is_active': isActive,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Formatted display for search results
  String get formattedDisplayName => userFriendlyName;

  String get expiryDisplay {
    if (expiry == null) return '';
    return '${expiry!.day} ${_getMonthName(expiry!.month)} ${expiry!.year}';
  }

  String get shortExpiryDisplay {
    if (expiry == null) return '';
    return '${expiry!.day} ${_getMonthName(expiry!.month)}';
  }

  String _getMonthName(int month) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    return months[month - 1];
  }

  String _getFullMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return months[month - 1];
  }

  /// User-friendly name: NIFTY 30 March
  String get userFriendlyName {
    final base = name.isNotEmpty ? name : tradingsymbol;
    if (expiry == null) return base;

    final day = expiry!.day;
    final month = _getFullMonthName(expiry!.month);

    if (instrumentType == 'FUT') {
      return '$base $day $month';
    } else if (instrumentType == 'CE' || instrumentType == 'PE') {
      return '$base ${strike.toInt()} $instrumentType $day $month';
    }

    return '$base $day $month';
  }

  /// Check if this is a global index
  bool get isIndex => segment == 'INDICES';

  /// Check if this is a derivative (FUT, CE, PE)
  bool get isDerivative => ['FUT', 'CE', 'PE'].contains(instrumentType);

  /// Check if this is an option (CE or PE)
  bool get isOption => instrumentType == 'CE' || instrumentType == 'PE';

  /// Check if this is a future
  bool get isFuture => instrumentType == 'FUT';
}
