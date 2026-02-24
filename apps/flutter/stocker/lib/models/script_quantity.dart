class ScriptQuantity {
  final String id;
  final String exchangeName;
  final String scriptName;
  final double lotSize;
  final double maxQty;
  final double brkQty;
  final String createdAt;
  final String updatedAt;

  ScriptQuantity({
    required this.id,
    required this.exchangeName,
    required this.scriptName,
    required this.lotSize,
    required this.maxQty,
    required this.brkQty,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ScriptQuantity.fromJson(Map<String, dynamic> json) {
    return ScriptQuantity(
      id: json['id'] as String,
      exchangeName: json['exchange_name'] as String,
      scriptName: json['script_name'] as String,
      lotSize: (json['lot_size'] as num).toDouble(),
      maxQty: (json['max_qty'] as num).toDouble(),
      brkQty: (json['brk_qty'] as num).toDouble(),
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'exchange_name': exchangeName,
      'script_name': scriptName,
      'lot_size': lotSize,
      'max_qty': maxQty,
      'brk_qty': brkQty,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
