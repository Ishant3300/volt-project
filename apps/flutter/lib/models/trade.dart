class Trade {
  final String id;
  final String userId;
  final String? masterId;
  final String instrumentToken;
  final String tradingSymbol;
  final String exchange;
  final String segment; // e.g. MCX-FUT, NFO-FUT, NFO-OPT (from KiteInstrument)
  final String transactionType; // BUY or SELL
  final int quantity;
  final double price;
  final String? orderType;
  final String? productType;
  final String status;
  final String? userName;
  final String? masterName;
  final String createdAt;
  final String updatedAt;
  final int lotSize; // enriched by backend from KiteInstrument.lot_size
  final double pnl; // per-trade P&L computed by backend at execution time
  final double brokerage; // brokerage deducted for this trade
  final double netAmount; // pnl - brokerage
  final String rawName; // raw instrument name from KiteInstrument (for margin lookup)
  final String placedBy; // USER, ADMIN, or MASTER
  final String remarks; // settlement/system trade remarks
  final String tradeType; // regular, carry_forward, margin_square_off

  Trade({
    required this.id,
    required this.userId,
    this.masterId,
    required this.instrumentToken,
    required this.tradingSymbol,
    required this.exchange,
    this.segment = '',
    required this.transactionType,
    required this.quantity,
    required this.price,
    this.orderType,
    this.productType,
    required this.status,
    this.userName,
    this.masterName,
    required this.createdAt,
    required this.updatedAt,
    this.lotSize = 1,
    this.pnl = 0,
    this.brokerage = 0,
    this.netAmount = 0,
    this.rawName = '',
    this.placedBy = 'USER',
    this.remarks = '',
    this.tradeType = 'regular',
  });

  /// True when this trade should be displayed in lots instead of raw quantity.
  /// Only MCX-FUT, MCX-OPT, NFO-OPT, COMEX-FUT use lots. Everything else (NFO-FUT, GLOBAL, etc.) uses quantity.
  bool get isLotBased {
    final seg = segment.toUpperCase();
    return seg == 'MCX-FUT' || seg == 'MCX-OPT' || seg == 'NFO-OPT' || seg == 'COMEX-FUT';
  }

  /// Lot count: quantity ÷ lotSize, rounded. Returns raw quantity if lotSize ≤ 0.
  int get lots => (lotSize > 0) ? (quantity / lotSize).round() : quantity;

  /// Display volume — returns lots count if isLotBased, else raw quantity.
  int get displayVolume => isLotBased ? lots : quantity;

  /// Unit label for display.
  String get volumeUnit => isLotBased ? 'LOT' : 'QTY';

  factory Trade.fromJson(Map<String, dynamic> json) {
    return Trade(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      masterId: json['master_id']?.toString(),
      instrumentToken: json['instrument_token']?.toString() ?? '',
      tradingSymbol: json['tradingsymbol']?.toString() ??
          json['trading_symbol']?.toString() ??
          '',
      exchange: json['exchange']?.toString() ?? '',
      segment: json['segment']?.toString() ?? '',
      transactionType: json['transaction_type']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ??
          (json['executed_quantity'] as num?)?.toInt() ??
          0,
      price: (json['executed_price'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble() ??
          0.0,
      orderType: json['order_type']?.toString(),
      productType: json['product_type']?.toString(),
      status: json['status']?.toString() ?? '',
      userName: json['user_name']?.toString(),
      masterName: json['master_name']?.toString(),
      createdAt: json['executed_at']?.toString() ??
          json['created_at']?.toString() ??
          '',
      updatedAt: json['updated_at']?.toString() ?? '',
      lotSize: (json['lot_size'] as num?)?.toInt() ?? 1,
      pnl: (json['pnl'] as num?)?.toDouble() ?? 0.0,
      brokerage: (json['brokerage'] as num?)?.toDouble() ?? 0.0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0.0,
      rawName: json['raw_name']?.toString() ?? '',
      placedBy: json['placed_by']?.toString() ?? 'USER',
      remarks: json['remarks']?.toString() ?? '',
      tradeType: json['trade_type']?.toString() ?? 'regular',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      if (masterId != null) 'master_id': masterId,
      'instrument_token': instrumentToken,
      'trading_symbol': tradingSymbol,
      'exchange': exchange,
      'segment': segment,
      'transaction_type': transactionType,
      'quantity': quantity,
      'price': price,
      if (orderType != null) 'order_type': orderType,
      if (productType != null) 'product_type': productType,
      'status': status,
      if (userName != null) 'user_name': userName,
      if (masterName != null) 'master_name': masterName,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'lot_size': lotSize,
    };
  }
}
