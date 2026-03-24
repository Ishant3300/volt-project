class BrokerageRule {
  final String exchangeName;
  final String scriptName;
  final String type; // 'TURNOVER WISE' or 'LOT WISE'
  final double brkValue;

  BrokerageRule({
    required this.exchangeName,
    required this.scriptName,
    required this.type,
    required this.brkValue,
  });

  factory BrokerageRule.fromJson(Map<String, dynamic> json) {
    return BrokerageRule(
      exchangeName: json['exchange_name']?.toString() ?? '',
      scriptName: json['script_name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      brkValue: (json['brk_value'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
