class MarketDepth {
  final String instrumentToken;
  final OhlcData? ohlc;
  final double? lastPrice;
  final double? volume;

  MarketDepth({
    required this.instrumentToken,
    this.ohlc,
    this.lastPrice,
    this.volume,
  });

  factory MarketDepth.fromJson(Map<String, dynamic> json) {
    // Handle nested structure from Kite API
    final data = json[json.keys.first] as Map<String, dynamic>?;
    
    return MarketDepth(
      instrumentToken: json.keys.first,
      ohlc: data?['ohlc'] != null ? OhlcData.fromJson(data!['ohlc']) : null,
      lastPrice: (data?['last_price'] as num?)?.toDouble(),
      volume: (data?['volume'] as num?)?.toDouble(),
    );
  }
}

class OhlcData {
  final double open;
  final double high;
  final double low;
  final double close;

  OhlcData({
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  factory OhlcData.fromJson(Map<String, dynamic> json) {
    return OhlcData(
      open: (json['open'] ?? 0).toDouble(),
      high: (json['high'] ?? 0).toDouble(),
      low: (json['low'] ?? 0).toDouble(),
      close: (json['close'] ?? 0).toDouble(),
    );
  }
}
