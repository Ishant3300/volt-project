class Trade {
  final String id;
  final String userId;
  final String? masterId;
  final String instrumentToken;
  final String tradingSymbol;
  final String exchange;
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

  Trade({
    required this.id,
    required this.userId,
    this.masterId,
    required this.instrumentToken,
    required this.tradingSymbol,
    required this.exchange,
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
  });

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
      transactionType: json['transaction_type']?.toString() ?? '',
      quantity:
          json['executed_quantity'] as int? ?? json['quantity'] as int? ?? 0,
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
    };
  }
}
