class Position {
  final double realisedPnl;
  final double m2mPnl;
  final double credit;
  final double equity;
  final double marginUsed;
  final double freeMargin;
  final String lastUpdated;

  Position({
    required this.realisedPnl,
    required this.m2mPnl,
    required this.credit,
    required this.equity,
    required this.marginUsed,
    required this.freeMargin,
    required this.lastUpdated,
  });

  factory Position.fromJson(Map<String, dynamic> json) {
    final position = json['position'] ?? {};
    return Position(
      realisedPnl: (position['realised_pnl'] as num?)?.toDouble() ?? 0.0,
      m2mPnl: (position['m2m_pnl'] as num?)?.toDouble() ?? 0.0,
      credit: (position['credit'] as num?)?.toDouble() ?? 0.0,
      equity: (position['equity'] as num?)?.toDouble() ?? 0.0,
      marginUsed: (position['margin_used'] as num?)?.toDouble() ?? 0.0,
      freeMargin: (position['free_margin'] as num?)?.toDouble() ?? 0.0,
      lastUpdated: json['last_updated']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'position': {
        'realised_pnl': realisedPnl,
        'm2m_pnl': m2mPnl,
        'credit': credit,
        'equity': equity,
        'margin_used': marginUsed,
        'free_margin': freeMargin,
      },
      'last_updated': lastUpdated,
    };
  }
}
