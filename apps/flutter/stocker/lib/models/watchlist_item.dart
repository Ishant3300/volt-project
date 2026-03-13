import 'package:stocker/models/kite_instrument.dart';

class WatchlistItem {
  final String id;
  final KiteInstrument instrument;
  double? currentPrice;
  double? change;
  double? changePercent;
  double? high;
  double? low;
  double? open;
  double? close;
  double? bidPrice;  // Best bid (buy) price
  double? askPrice;  // Best ask (sell) price
  double? upperCircuitLimit;
  double? lowerCircuitLimit;
  DateTime? lastUpdated;

  WatchlistItem({
    required this.id,
    required this.instrument,
    this.currentPrice,
    this.change,
    this.changePercent,
    this.high,
    this.low,
    this.open,
    this.close,
    this.bidPrice,
    this.askPrice,
    this.upperCircuitLimit,
    this.lowerCircuitLimit,
    this.lastUpdated,
  });

  WatchlistItem copyWith({
    String? id,
    KiteInstrument? instrument,
    double? currentPrice,
    double? change,
    double? changePercent,
    double? high,
    double? low,
    double? open,
    double? close,
    double? bidPrice,
    double? askPrice,
    double? upperCircuitLimit,
    double? lowerCircuitLimit,
    DateTime? lastUpdated,
  }) {
    return WatchlistItem(
      id: id ?? this.id,
      instrument: instrument ?? this.instrument,
      currentPrice: currentPrice ?? this.currentPrice,
      change: change ?? this.change,
      changePercent: changePercent ?? this.changePercent,
      high: high ?? this.high,
      low: low ?? this.low,
      open: open ?? this.open,
      close: close ?? this.close,
      bidPrice: bidPrice ?? this.bidPrice,
      askPrice: askPrice ?? this.askPrice,
      upperCircuitLimit: upperCircuitLimit ?? this.upperCircuitLimit,
      lowerCircuitLimit: lowerCircuitLimit ?? this.lowerCircuitLimit,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  bool get isPositive => (change ?? 0) >= 0;

  String get changeDisplay {
    if (change == null || changePercent == null) return '';
    
    // Cap display percentage to reasonable range
    final displayPercent = changePercent!.clamp(-99.99, 999.99);
    
    final sign = isPositive ? '+' : '';
    return '$sign${change!.toStringAsFixed(2)}(${displayPercent.toStringAsFixed(2)}%)';
  }
}
