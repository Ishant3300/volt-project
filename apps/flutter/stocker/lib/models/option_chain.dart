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
  final String exchange;
  final String name;
  final DateTime? expiry;
  final int lotSize;
  final int? volume;
  final int? buyQuantity;
  final int? sellQuantity;

  OptionData({
    required this.instrumentToken,
    required this.tradingSymbol,
    required this.lastPrice,
    required this.strike,
    required this.instrumentType,
    this.exchange = '',
    this.name = '',
    this.expiry,
    this.lotSize = 0,
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
      exchange: json['exchange'] ?? '',
      name: json['name'] ?? '',
      expiry: json['expiry'] != null ? DateTime.parse(json['expiry']) : null,
      lotSize: json['lot_size'] ?? 0,
      volume: json['volume'] as int?,
      buyQuantity: json['buy_quantity'] as int?,
      sellQuantity: json['sell_quantity'] as int?,
    );
  }

  String get volumeDisplay {
    if (volume == null || volume == 0) return '--';
    if (volume! >= 100000) return '${(volume! / 100000).toStringAsFixed(1)}L';
    if (volume! >= 1000) return '${(volume! / 1000).toStringAsFixed(1)}K';
    return volume.toString();
  }
}
