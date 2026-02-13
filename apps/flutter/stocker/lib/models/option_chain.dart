class OptionChainItem {
  final double strike;
  final OptionData? call;
  final OptionData? put;

  OptionChainItem({
    required this.strike,
    this.call,
    this.put,
  });

  factory OptionChainItem.fromJson(Map<String, dynamic> json) {
    return OptionChainItem(
      strike: (json['strike'] as num).toDouble(),
      call: json['CE'] != null ? OptionData.fromJson(json['CE']) : null,
      put: json['PE'] != null ? OptionData.fromJson(json['PE']) : null,
    );
  }
}

class OptionData {
  final String instrumentToken;
  final String tradingSymbol;
  final double lastPrice;
  final double strike;
  final String instrumentType;
  final DateTime? expiry;
  final int? volume;
  final int? buyQuantity;
  final int? sellQuantity;

  OptionData({
    required this.instrumentToken,
    required this.tradingSymbol,
    required this.lastPrice,
    required this.strike,
    required this.instrumentType,
    this.expiry,
    this.volume,
    this.buyQuantity,
    this.sellQuantity,
  });

  factory OptionData.fromJson(Map<String, dynamic> json) {
    return OptionData(
      instrumentToken: json['instrument_token'].toString(),
      tradingSymbol: json['tradingsymbol'] ?? '',
      lastPrice: (json['last_price'] ?? 0).toDouble(),
      strike: (json['strike'] ?? 0).toDouble(),
      instrumentType: json['instrument_type'] ?? '',
      expiry: json['expiry'] != null ? DateTime.parse(json['expiry']) : null,
      volume: json['volume'] as int?,
      buyQuantity: json['buy_quantity'] as int?,
      sellQuantity: json['sell_quantity'] as int?,
    );
  }

  String get changePercent {
    if (lastPrice == 0) return '0.00%';
    // Show volume info if available, otherwise just the price percentage placeholder
    return '${lastPrice.toStringAsFixed(2)}%';
  }
}
