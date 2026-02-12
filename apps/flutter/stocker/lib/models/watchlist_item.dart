import 'package:stocker/models/kite_instrument.dart';

class WatchlistItem {
  final String id;
  final KiteInstrument instrument;
  double? currentPrice;
  double? change;
  double? changePercent;
  double? high;
  double? low;
  DateTime? lastUpdated;

  WatchlistItem({
    required this.id,
    required this.instrument,
    this.currentPrice,
    this.change,
    this.changePercent,
    this.high,
    this.low,
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
