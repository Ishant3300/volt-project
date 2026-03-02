class KiteInstrument {
  final String id;
  final String instrumentToken;
  final String exchangeToken;
  final String tradingsymbol;
  final String name;
  final double lastPrice;
  final DateTime? expiry;
  final double strike;
  final double tickSize;
  final int lotSize;
  final String instrumentType;
  final String segment;
  final String exchange;
  final DateTime updatedAt;

  KiteInstrument({
    required this.id,
    required this.instrumentToken,
    required this.exchangeToken,
    required this.tradingsymbol,
    required this.name,
    required this.lastPrice,
    this.expiry,
    required this.strike,
    required this.tickSize,
    required this.lotSize,
    required this.instrumentType,
    required this.segment,
    required this.exchange,
    required this.updatedAt,
  });

  factory KiteInstrument.fromJson(Map<String, dynamic> json) {
    return KiteInstrument(
      id: json['_id'] ?? json['id'] ?? '',
      instrumentToken: json['instrument_token'] ?? '',
      exchangeToken: json['exchange_token'] ?? '',
      tradingsymbol: json['tradingsymbol'] ?? '',
      name: json['name'] ?? '',
      lastPrice: (json['last_price'] ?? 0).toDouble(),
      expiry: json['expiry'] != null ? DateTime.parse(json['expiry']) : null,
      strike: (json['strike'] ?? 0).toDouble(),
      tickSize: (json['tick_size'] ?? 0).toDouble(),
      lotSize: json['lot_size'] ?? 0,
      instrumentType: json['instrument_type'] ?? '',
      segment: json['segment'] ?? '',
      exchange: json['exchange'] ?? '',
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
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
      'last_price': lastPrice,
      'expiry': expiry?.toIso8601String(),
      'strike': strike,
      'tick_size': tickSize,
      'lot_size': lotSize,
      'instrument_type': instrumentType,
      'segment': segment,
      'exchange': exchange,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get displayName {
    if (instrumentType == 'FUT') {
      return '$tradingsymbol FUT';
    } else if (instrumentType == 'CE' || instrumentType == 'PE') {
      return '$tradingsymbol ${strike.toInt()} $instrumentType';
    }
    return tradingsymbol;
  }

  String get expiryDisplay {
    if (expiry == null) return '';
    return '${expiry!.day} ${_getMonthName(expiry!.month)} ${expiry!.year}';
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
}
