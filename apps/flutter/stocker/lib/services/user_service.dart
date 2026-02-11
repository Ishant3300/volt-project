

class User {
  final String id;
  final String username;
  final String serverId;
  final int credit;
  final int currentCredit;
  final int balance;
  final List<String> exchangeSupport;
  final String masterId;
  final String status;
  final String? activeToken;
  final String? deletedAt;
  final String createdAt;
  final String updatedAt;

  User({
    required this.id,
    required this.username,
    required this.serverId,
    required this.credit,
    required this.currentCredit,
    required this.balance,
    required this.exchangeSupport,
    required this.masterId,
    required this.status,
    this.activeToken,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      serverId: json['server_id'],
      credit: json['credit'],
      currentCredit: json['current_credit'],
      balance: json['balance'],
      exchangeSupport: List<String>.from(json['exchanges_support'] ?? []),
      masterId: json['master_id'].toString(),
      status: json['status'],
      activeToken: json['active_token'],
      deletedAt: json['deleted_at'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'server_id': serverId,
      'credit': credit,
      'current_credit': currentCredit,
      'balance': balance,
      'exchanges_support': exchangeSupport,
      'master_id': masterId,
      'status': status,
      'active_token': activeToken,
      'deleted_at': deletedAt,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}