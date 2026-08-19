enum PointLedgerDirection {
  credit,
  debit;

  static PointLedgerDirection fromJson(Object? value) => value == 'debit'
      ? PointLedgerDirection.debit
      : PointLedgerDirection.credit;
}

enum PointLedgerEntryType {
  adRewardCredit('ad_reward_credit'),
  digitalOrderDebit('digital_order_debit'),
  digitalOrderRefund('digital_order_refund'),
  adminCorrectionCredit('admin_correction_credit'),
  adminCorrectionDebit('admin_correction_debit'),
  expiryDebit('expiry_debit'),
  profileFeatureDebit('profile_feature_debit'),
  unknown('unknown');

  final String dbValue;
  const PointLedgerEntryType(this.dbValue);

  static PointLedgerEntryType fromJson(Object? value) =>
      PointLedgerEntryType.values.firstWhere(
        (type) => type.dbValue == value,
        orElse: () => PointLedgerEntryType.unknown,
      );

  String get label => switch (this) {
    PointLedgerEntryType.adRewardCredit => 'Doğrulanmış reklam puanı',
    PointLedgerEntryType.digitalOrderDebit => 'Dijital siparişte kullanıldı',
    PointLedgerEntryType.digitalOrderRefund => 'Dijital sipariş iadesi',
    PointLedgerEntryType.adminCorrectionCredit => 'Puan düzeltmesi',
    PointLedgerEntryType.adminCorrectionDebit => 'Puan düzeltmesi',
    PointLedgerEntryType.expiryDebit => 'Süresi dolan puan',
    PointLedgerEntryType.profileFeatureDebit => 'Profil özelliği satın alımı',
    PointLedgerEntryType.unknown => 'Puan işlemi',
  };
}

class UserPointAccount {
  final String userId;
  final int balancePoints;
  final int lifetimeEarnedPoints;
  final int lifetimeSpentPoints;
  final int lifetimeRefundedPoints;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserPointAccount({
    required this.userId,
    required this.balancePoints,
    required this.lifetimeEarnedPoints,
    required this.lifetimeSpentPoints,
    required this.lifetimeRefundedPoints,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserPointAccount.fromJson(Map<String, dynamic> json) {
    return UserPointAccount(
      userId: json['user_id'] as String,
      balancePoints: _integer(json['balance_points']),
      lifetimeEarnedPoints: _integer(json['lifetime_earned_points']),
      lifetimeSpentPoints: _integer(json['lifetime_spent_points']),
      lifetimeRefundedPoints: _integer(json['lifetime_refunded_points']),
      version: _integer(json['version']),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class PointLedgerEntry {
  final String id;
  final String userId;
  final PointLedgerEntryType entryType;
  final PointLedgerDirection direction;
  final int points;
  final int balanceBeforePoints;
  final int balanceAfterPoints;
  final String referenceType;
  final String referenceId;
  final DateTime createdAt;

  const PointLedgerEntry({
    required this.id,
    required this.userId,
    required this.entryType,
    required this.direction,
    required this.points,
    required this.balanceBeforePoints,
    required this.balanceAfterPoints,
    required this.referenceType,
    required this.referenceId,
    required this.createdAt,
  });

  factory PointLedgerEntry.fromJson(Map<String, dynamic> json) {
    return PointLedgerEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      entryType: PointLedgerEntryType.fromJson(json['entry_type']),
      direction: PointLedgerDirection.fromJson(json['direction']),
      points: _integer(json['points']),
      balanceBeforePoints: _integer(json['balance_before_points']),
      balanceAfterPoints: _integer(json['balance_after_points']),
      referenceType: json['reference_type'] as String,
      referenceId: json['reference_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get signedPointsLabel =>
      '${direction == PointLedgerDirection.credit ? '+' : '-'}$points puan';
}

int _integer(Object? value) => value is num ? value.toInt() : 0;
