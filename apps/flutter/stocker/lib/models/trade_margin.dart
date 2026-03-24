class TradeMargin {
  final String exchangeName;
  final String scriptName;
  final String amountType;
  final double tradeMargin;

  TradeMargin({
    required this.exchangeName,
    required this.scriptName,
    required this.amountType,
    required this.tradeMargin,
  });

  factory TradeMargin.fromJson(Map<String, dynamic> json) {
    return TradeMargin(
      exchangeName: json['exchange_name']?.toString() ?? '',
      scriptName: json['script_name']?.toString() ?? '',
      amountType: json['amount_type']?.toString() ?? 'flat',
      tradeMargin: (json['trade_margin'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
