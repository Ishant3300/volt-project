class IntradaySquareoffSetting {
  final String exchangeName;
  final bool enabled;

  IntradaySquareoffSetting({
    required this.exchangeName,
    required this.enabled,
  });

  factory IntradaySquareoffSetting.fromJson(Map<String, dynamic> json) {
    return IntradaySquareoffSetting(
      exchangeName: json['exchange_name'] as String,
      enabled: json['enabled'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'exchange_name': exchangeName,
      'enabled': enabled,
    };
  }
}

class MasterPermissions {
  final bool accountSummary;
  final bool pnlSummary;
  final bool clientSummary;
  final bool settlementReport;
  final bool generatePdf;
  final bool weeklyAdmin;
  final bool intradayHistory;
  final bool userwiseOpenPosition;
  final bool scriptQuantity;
  final bool deletedTrade;
  final bool tradeAccount;
  final bool closeOnly;
  final bool bet;
  final bool marginSquare;
  final bool freshStoploss;

  MasterPermissions({
    required this.accountSummary,
    required this.pnlSummary,
    required this.clientSummary,
    required this.settlementReport,
    required this.generatePdf,
    required this.weeklyAdmin,
    required this.intradayHistory,
    required this.userwiseOpenPosition,
    required this.scriptQuantity,
    required this.deletedTrade,
    required this.tradeAccount,
    required this.closeOnly,
    required this.bet,
    required this.marginSquare,
    required this.freshStoploss,
  });

  factory MasterPermissions.fromJson(Map<String, dynamic> json) {
    return MasterPermissions(
      accountSummary: json['account_summary'] as bool? ?? true,
      pnlSummary: json['pnl_summary'] as bool? ?? true,
      clientSummary: json['client_summary'] as bool? ?? true,
      settlementReport: json['settlement_report'] as bool? ?? true,
      generatePdf: json['generate_pdf'] as bool? ?? true,
      weeklyAdmin: json['weekly_admin'] as bool? ?? true,
      intradayHistory: json['intraday_history'] as bool? ?? true,
      userwiseOpenPosition: json['userwise_open_position'] as bool? ?? true,
      scriptQuantity: json['script_quantity'] as bool? ?? true,
      deletedTrade: json['deleted_trade'] as bool? ?? true,
      tradeAccount: json['trade_account'] as bool? ?? true,
      closeOnly: json['close_only'] as bool? ?? false,
      bet: json['bet'] as bool? ?? false,
      marginSquare: json['margin_square'] as bool? ?? false,
      freshStoploss: json['fresh_stoploss'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'account_summary': accountSummary,
      'pnl_summary': pnlSummary,
      'client_summary': clientSummary,
      'settlement_report': settlementReport,
      'generate_pdf': generatePdf,
      'weekly_admin': weeklyAdmin,
      'intraday_history': intradayHistory,
      'userwise_open_position': userwiseOpenPosition,
      'script_quantity': scriptQuantity,
      'deleted_trade': deletedTrade,
      'trade_account': tradeAccount,
      'close_only': closeOnly,
      'bet': bet,
      'margin_square': marginSquare,
      'fresh_stoploss': freshStoploss,
    };
  }
}

class AccountLimit {
  final bool enabled;
  final int maxMasters;
  final int maxUsers;

  AccountLimit({
    required this.enabled,
    required this.maxMasters,
    required this.maxUsers,
  });

  factory AccountLimit.fromJson(Map<String, dynamic> json) {
    return AccountLimit(
      enabled: json['enabled'] as bool? ?? false,
      maxMasters: (json['max_masters'] as num?)?.toInt() ?? 0,
      maxUsers: (json['max_users'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'max_masters': maxMasters,
      'max_users': maxUsers,
    };
  }
}

class Master {
  final String id;
  final String name;
  final String username;
  final double credits;
  final double equity;
  final Map<String, double> wallet;
  final String note;
  final double pnlSharing;
  final double brokerageSharing;
  final List<String> exchangesAllowed;
  final List<String> tradeLimit;
  final List<IntradaySquareoffSetting> intradaySquareoff;
  final double? marginSquareOffPercentage;
  final bool addMaster;
  final bool changePassOnFirstLogin;
  final String serverId;
  final String? adminId;
  final String? masterId;
  final double? maxCredit;
  final String status;
  final bool activeStatus;
  final String? lastDueBill;
  final String? lastLogin;
  final String? ipAddress;
  final List<String>? exchanges;
  final MasterPermissions? permissions;
  final AccountLimit? accountLimit;
  final String createdAt;
  final String updatedAt;

  Master({
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
    required this.addMaster,
    required this.changePassOnFirstLogin,
    required this.serverId,
    this.adminId,
    this.masterId,
    this.maxCredit,
    required this.status,
    required this.activeStatus,
    this.lastDueBill,
    this.lastLogin,
    this.ipAddress,
    this.exchanges,
    this.permissions,
    this.accountLimit,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Master.fromJson(Map<String, dynamic> json) {
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

    // Handle admin_id which might be populated as an object
    String? adminIdValue;
    if (json['admin_id'] == null) {
      adminIdValue = null;
    } else if (json['admin_id'] is String) {
      adminIdValue = json['admin_id'] as String;
    } else if (json['admin_id'] is Map) {
      adminIdValue = (json['admin_id'] as Map)['_id']?.toString() ??
          (json['admin_id'] as Map)['id']?.toString();
    } else {
      adminIdValue = json['admin_id']?.toString();
    }

    // Handle master_id which might be populated as an object
    String? masterIdValue;
    if (json['master_id'] == null) {
      masterIdValue = null;
    } else if (json['master_id'] is String) {
      masterIdValue = json['master_id'] as String;
    } else if (json['master_id'] is Map) {
      masterIdValue = (json['master_id'] as Map)['_id']?.toString() ??
          (json['master_id'] as Map)['id']?.toString();
    } else {
      masterIdValue = json['master_id']?.toString();
    }

    return Master(
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
          ? List<String>.from(json['exchanges_allowed'] as List)
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
      addMaster: json['add_master'] as bool? ?? false,
      changePassOnFirstLogin:
          json['change_pass_on_first_login'] as bool? ?? false,
      serverId: serverIdValue,
      adminId: adminIdValue,
      masterId: masterIdValue,
      maxCredit: json['max_credit'] != null
          ? (json['max_credit'] as num).toDouble()
          : null,
      status: json['status']?.toString() ?? 'active',
      activeStatus: json['active_status'] as bool? ?? true,
      lastDueBill: json['last_due_bill']?.toString(),
      lastLogin: json['last_login']?.toString(),
      ipAddress: json['ip_address']?.toString(),
      exchanges: json['exchanges'] != null
          ? List<String>.from(json['exchanges'] as List)
          : null,
      permissions: json['permissions'] != null
          ? MasterPermissions.fromJson(
              json['permissions'] as Map<String, dynamic>)
          : null,
      accountLimit: json['account_limit'] != null
          ? AccountLimit.fromJson(
              json['account_limit'] as Map<String, dynamic>)
          : null,
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
      'exchanges_allowed': exchangesAllowed,
      'trade_limit': tradeLimit,
      'intraday_squareoff': intradaySquareoff.map((e) => e.toJson()).toList(),
      if (marginSquareOffPercentage != null)
        'margin_square_off_percentage': marginSquareOffPercentage,
      'add_master': addMaster,
      'change_pass_on_first_login': changePassOnFirstLogin,
      'server_id': serverId,
      if (adminId != null) 'admin_id': adminId,
      if (masterId != null) 'master_id': masterId,
      if (maxCredit != null) 'max_credit': maxCredit,
      'status': status,
      'active_status': activeStatus,
      if (lastDueBill != null) 'last_due_bill': lastDueBill,
      if (lastLogin != null) 'last_login': lastLogin,
      if (ipAddress != null) 'ip_address': ipAddress,
      if (exchanges != null) 'exchanges': exchanges,
      if (permissions != null) 'permissions': permissions!.toJson(),
      if (accountLimit != null) 'account_limit': accountLimit!.toJson(),
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}

class MasterPosition {
  final double realisedPnl;
  final double m2mPnl;
  final double credit;
  final double balance;
  final double equity;
  final double marginUsed;
  final double freeMargin;

  MasterPosition({
    required this.realisedPnl,
    required this.m2mPnl,
    required this.credit,
    required this.balance,
    required this.equity,
    required this.marginUsed,
    required this.freeMargin,
  });

  factory MasterPosition.fromJson(Map<String, dynamic> json) {
    return MasterPosition(
      realisedPnl: (json['realised_pnl'] as num).toDouble(),
      m2mPnl: (json['m2m_pnl'] as num).toDouble(),
      credit: json['credit'] != null ? (json['credit'] as num).toDouble() : 0.0,
      balance:
          json['balance'] != null ? (json['balance'] as num).toDouble() : 0.0,
      equity: (json['equity'] as num).toDouble(),
      marginUsed: (json['margin_used'] as num).toDouble(),
      freeMargin: (json['free_margin'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'realised_pnl': realisedPnl,
      'm2m_pnl': m2mPnl,
      'credit': credit,
      'balance': balance,
      'equity': equity,
      'margin_used': marginUsed,
      'free_margin': freeMargin,
    };
  }
}
