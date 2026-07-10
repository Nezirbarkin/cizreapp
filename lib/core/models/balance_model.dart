/// Bakiye Modeli
/// Kullanıcının bakiye bilgilerini tutar
class UserBalance {
  final String id;
  final String userId;
  final double balance;
  final double lockedBalance;
  final double totalEarned;
  final double totalSpent;
  final double totalRefunds;
  final double totalWithdrawn;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserBalance({
    required this.id,
    required this.userId,
    required this.balance,
    this.lockedBalance = 0,
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.totalRefunds = 0,
    this.totalWithdrawn = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Kullanılabilir bakiye (toplam - kilitli)
  double get availableBalance => balance - lockedBalance;

  /// Bakiye denklemi kontrolü:
  /// bakiye = yüklenen - harcanan + iade - çekilen
  /// yüklenen = totalEarned (yükleme + bonus vb., iade HARİÇ)
  /// iade = totalRefunds (iptal iadeleri vb.)
  bool get isConsistent {
    final expected = totalEarned - totalSpent + totalRefunds - totalWithdrawn;
    return (balance - expected).abs() < 0.01;
  }

  factory UserBalance.fromJson(Map<String, dynamic> json) {
    return UserBalance(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      lockedBalance: (json['locked_balance'] as num?)?.toDouble() ?? 0,
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0,
      totalSpent: (json['total_spent'] as num?)?.toDouble() ?? 0,
      totalRefunds: (json['total_refunds'] as num?)?.toDouble() ?? 0,
      totalWithdrawn: (json['total_withdrawn'] as num?)?.toDouble() ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'balance': balance,
      'locked_balance': lockedBalance,
      'total_earned': totalEarned,
      'total_spent': totalSpent,
      'total_refunds': totalRefunds,
      'total_withdrawn': totalWithdrawn,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserBalance copyWith({
    String? id,
    String? userId,
    double? balance,
    double? lockedBalance,
    double? totalEarned,
    double? totalSpent,
    double? totalRefunds,
    double? totalWithdrawn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserBalance(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      balance: balance ?? this.balance,
      lockedBalance: lockedBalance ?? this.lockedBalance,
      totalEarned: totalEarned ?? this.totalEarned,
      totalSpent: totalSpent ?? this.totalSpent,
      totalRefunds: totalRefunds ?? this.totalRefunds,
      totalWithdrawn: totalWithdrawn ?? this.totalWithdrawn,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// Satıcı Kazanç Özeti
class SellerEarningsSummary {
  final int totalOrders;
  final double totalGross;
  final double totalCommission;
  final double totalNet;
  final double pendingAmount;
  final double availableAmount;
  final double withdrawnAmount;
  final double minWithdrawal;
  final double withdrawalFeePercent;

  SellerEarningsSummary({
    required this.totalOrders,
    required this.totalGross,
    required this.totalCommission,
    required this.totalNet,
    required this.pendingAmount,
    required this.availableAmount,
    required this.withdrawnAmount,
    required this.minWithdrawal,
    required this.withdrawalFeePercent,
  });

  double calculateFee(double amount) {
    return (amount * withdrawalFeePercent / 100 * 100).round() / 100;
  }

  double netWithdrawable(double amount) {
    return amount - calculateFee(amount);
  }

  factory SellerEarningsSummary.fromJson(Map<String, dynamic> json) {
    return SellerEarningsSummary(
      totalOrders: json['total_orders'] as int? ?? 0,
      totalGross: (json['total_gross'] as num?)?.toDouble() ?? 0,
      totalCommission: (json['total_commission'] as num?)?.toDouble() ?? 0,
      totalNet: (json['total_net'] as num?)?.toDouble() ?? 0,
      pendingAmount: (json['pending_amount'] as num?)?.toDouble() ?? 0,
      availableAmount: (json['available_amount'] as num?)?.toDouble() ?? 0,
      withdrawnAmount: (json['withdrawn_amount'] as num?)?.toDouble() ?? 0,
      minWithdrawal: (json['min_withdrawal'] as num?)?.toDouble() ?? 50,
      withdrawalFeePercent: (json['withdrawal_fee_percent'] as num?)?.toDouble() ?? 2,
    );
  }
}
