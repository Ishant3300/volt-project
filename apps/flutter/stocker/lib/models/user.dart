import 'master.dart';

class User {
  final String id;
  final String name;
  final String username;
  final double credits;
  final double equity;
  final Map<String, double> wallet;
  final String note;
  final double pnlSharing;
  final double brokerageSharing;
  final List<ExchangeConfig> exchangesAllowed;
  final List<String> tradeLimit;
  final List<IntradaySquareoffSetting> intradaySquareoff;
  final double? marginSquareOffPercentage;
  final bool marginSquareOff;
  final bool closeOnly;
  final bool bet;
  final bool freshStoploss;
  final bool changePassOnFirstLogin;
  final String serverId;
  final String masterId;
  final String status;
  final bool activeStatus;
  final String? lastLogin;
  final String? ipAddress;
  final String createdAt;
  final String updatedAt;

  User({
    required this.id,
    required this.name,
    required this.username,
    required this.credits,
    required this.equity,
    this.wallet = const {},
    required this.note,
    required this.pnlSharing,
    required this.brokerageSharing,
    required this.exchangesAllowed,
    required this.tradeLimit,
    required this.intradaySquareoff,
    this.marginSquareOffPercentage,
    required this.marginSquareOff,
    required this.closeOnly,
    required this.bet,
    required this.freshStoploss,
    required this.changePassOnFirstLogin,
    required this.serverId,
    required this.masterId,
    required this.status,
    required this.activeStatus,
    this.lastLogin,
    this.ipAddress,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    // Handle server_id which might be populated as an object
    String serverIdValue;
    if (json['server_id'] is String) {
      serverIdValue = json['server_id'] as String;
    } else if (json['server_id'] is Map) {
      serverIdValue = (json['server_id'] as Map)['_id']?.toString() ??
          (json['server_id'] as Map)['id']?.toString() ??
          '';
    } else {
      serverIdValue = json['server_id']?.toString() ?? '';
    }

    // Handle master_id which might be populated as an object
    String masterIdValue;
    if (json['master_id'] is String) {
      masterIdValue = json['master_id'] as String;
    } else if (json['master_id'] is Map) {
      masterIdValue = (json['master_id'] as Map)['_id']?.toString() ??
          (json['master_id'] as Map)['id']?.toString() ??
          '';
    } else {
      masterIdValue = json['master_id']?.toString() ?? '';
    }

    return User(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      credits:
          json['credits'] != null ? (json['credits'] as num).toDouble() : 0.0,
      equity:
          json['equity'] != null ? (json['equity'] as num).toDouble() : 0.0,
      wallet: json['wallet'] is Map
          ? (json['wallet'] as Map).map((k, v) =>
              MapEntry(k.toString(), (v as num?)?.toDouble() ?? 0.0))
          : <String, double>{},
      note: json['note']?.toString() ?? '',
      pnlSharing: json['pnl_sharing'] != null
          ? (json['pnl_sharing'] as num).toDouble()
          : 0.0,
      brokerageSharing: json['brokerage_sharing'] != null
          ? (json['brokerage_sharing'] as num).toDouble()
          : 0.0,
      exchangesAllowed: json['exchanges_allowed'] != null
          ? (json['exchanges_allowed'] as List)
              .map((e) => ExchangeConfig.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      tradeLimit: json['trade_limit'] != null
          ? List<String>.from(json['trade_limit'] as List)
          : [],
      intradaySquareoff: json['intraday_squareoff'] != null
          ? (json['intraday_squareoff'] as List)
              .map((e) =>
                  IntradaySquareoffSetting.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
      marginSquareOffPercentage: json['margin_square_off_percentage'] != null
          ? (json['margin_square_off_percentage'] as num).toDouble()
          : null,
      marginSquareOff: json['margin_square_off'] as bool? ?? false,
      closeOnly: json['close_only'] as bool? ?? false,
      bet: json['bet'] as bool? ?? false,
      freshStoploss: json['fresh_stoploss'] as bool? ?? false,
      changePassOnFirstLogin:
          json['change_pass_on_first_login'] as bool? ?? false,
      serverId: serverIdValue,
      masterId: masterIdValue,
      status: json['status']?.toString() ?? 'active',
      activeStatus: json['active_status'] as bool? ?? true,
      lastLogin: json['last_login']?.toString(),
      ipAddress: json['ip_address']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'username': username,
      'credits': credits,
      'equity': equity,
      'wallet': wallet,
      'note': note,
      'pnl_sharing': pnlSharing,
      'brokerage_sharing': brokerageSharing,
      'exchanges_allowed': exchangesAllowed.map((e) => e.toJson()).toList(),
      'trade_limit': tradeLimit,
      'intraday_squareoff': intradaySquareoff.map((e) => e.toJson()).toList(),
      if (marginSquareOffPercentage != null)
        'margin_square_off_percentage': marginSquareOffPercentage,
      'margin_square_off': marginSquareOff,
      'change_pass_on_first_login': changePassOnFirstLogin,
      'server_id': serverId,
      'master_id': masterId,
      'status': status,
      if (lastLogin != null) 'last_login': lastLogin,
      if (ipAddress != null) 'ip_address': ipAddress,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class ExchangeConfig {
  final String exchangeName;
  final bool turnover;
  final bool lot;
  final String groupName;

  ExchangeConfig({
    required this.exchangeName,
    required this.turnover,
    required this.lot,
    required this.groupName,
  });

  factory ExchangeConfig.fromJson(Map<String, dynamic> json) {
    return ExchangeConfig(
      exchangeName: json['exchange_name'] as String,
      turnover: json['turnover'] as bool,
      lot: json['lot'] as bool,
      groupName: json['group_name'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exchange_name': exchangeName,
      'turnover': turnover,
      'lot': lot,
      'group_name': groupName,
    };
  }
}

class UserPosition {
  final double realisedPnl;
  final double m2mPnl;
  final double credit;
  final double balance;
  final double equity;

  UserPosition({
    required this.realisedPnl,
    required this.m2mPnl,
    required this.credit,
    required this.balance,
    required this.equity,
  });

  factory UserPosition.fromJson(Map<String, dynamic> json) {
    return UserPosition(
      realisedPnl: (json['realised_pnl'] as num).toDouble(),
      m2mPnl: (json['m2m_pnl'] as num).toDouble(),
      credit: json['credit'] != null ? (json['credit'] as num).toDouble() : 0.0,
      balance:
          json['balance'] != null ? (json['balance'] as num).toDouble() : 0.0,
      equity: (json['equity'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'realised_pnl': realisedPnl,
      'm2m_pnl': m2mPnl,
      'credit': credit,
      'balance': balance,
      'equity': equity,
    };
  }
}
