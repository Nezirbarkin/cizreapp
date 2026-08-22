import 'package:flutter/material.dart';

enum ProfileFeatureKind { effect, avatarEffect, coverEffect, icon, badge }

/// Enum -> `profile_feature_catalog.kind` sütunundaki metin değeri.
String kindToDbValue(ProfileFeatureKind kind) => switch (kind) {
  ProfileFeatureKind.effect => 'effect',
  ProfileFeatureKind.avatarEffect => 'avatar_effect',
  ProfileFeatureKind.coverEffect => 'cover_effect',
  ProfileFeatureKind.icon => 'icon',
  ProfileFeatureKind.badge => 'badge',
};

class ProfileFeature {
  final String assignmentId;
  final String id;
  final String code;
  final ProfileFeatureKind kind;
  final String name;
  final String description;
  final String rendererKey;
  final Color primaryColor;
  final Color? secondaryColor;
  final Map<String, dynamic> config;
  final int priority;
  final bool isEnabled;
  final bool isClaimed;
  final bool isSelfClaimed;
  final bool isUserClaimable;
  final DateTime? startsAt;
  final DateTime? expiresAt;
  final int? pointsPriceMonthly;
  final int? pointsPriceYearly;
  final String? purchasePlan;
  final int? purchasedPoints;
  final bool isPurchased;
  final int? unlockAfterOrders;

  /// Kullanıcı bu özelliğe şu an gerçekten sahip mi (süresi geçmemiş atama).
  /// `get_my_profile_feature_catalog` doldurur; eski RPC'lerde false gelir.
  final bool isOwned;

  /// Katalogdaki iki ücretsiz özellikten biri mi.
  final bool isFree;

  /// Admin tarafından verilmiş mi (kullanıcı kaldıramaz).
  final bool isAdminGranted;

  /// Kullanıcının tamamlanmış sipariş sayısı [unlockAfterOrders] eşiğini
  /// karşılıyor mu — karşılıyorsa puan ödemeden talep edilebilir.
  final bool orderUnlockMet;

  const ProfileFeature({
    required this.assignmentId,
    required this.id,
    required this.code,
    required this.kind,
    required this.name,
    required this.description,
    required this.rendererKey,
    required this.primaryColor,
    required this.secondaryColor,
    required this.config,
    required this.priority,
    this.isEnabled = true,
    this.isClaimed = false,
    this.isSelfClaimed = false,
    this.isUserClaimable = false,
    this.startsAt,
    this.expiresAt,
    this.pointsPriceMonthly,
    this.pointsPriceYearly,
    this.purchasePlan,
    this.purchasedPoints,
    this.isPurchased = false,
    this.unlockAfterOrders,
    this.isOwned = false,
    this.isFree = false,
    this.isAdminGranted = false,
    this.orderUnlockMet = false,
  });

  /// Ne ücretsiz, ne siparişle açılmış, ne de satın alınmış — yani hâlâ kilitli.
  bool get isLocked => !isOwned && !isFree && !orderUnlockMet;

  /// Puanla satın alınabilir bir plan tanımlı mı.
  bool get hasPointsPrice =>
      pointsPriceMonthly != null || pointsPriceYearly != null;

  factory ProfileFeature.fromMap(Map<String, dynamic> map) {
    return ProfileFeature(
      assignmentId: (map['assignment_id'] ?? '').toString(),
      id: (map['feature_id'] ?? map['id'] ?? '').toString(),
      code: (map['code'] ?? '').toString(),
      kind: _parseKind((map['kind'] ?? '').toString()),
      name: (map['name'] ?? 'Özellik').toString(),
      description: (map['description'] ?? '').toString(),
      rendererKey: (map['renderer_key'] ?? '').toString(),
      primaryColor: parseFeatureColor(map['primary_color']?.toString()),
      secondaryColor: map['secondary_color'] == null
          ? null
          : parseFeatureColor(map['secondary_color'].toString()),
      config: Map<String, dynamic>.from(map['config'] as Map? ?? const {}),
      priority: (map['priority'] as num?)?.toInt() ?? 0,
      isEnabled: map['is_enabled'] as bool? ?? true,
      isClaimed: map['is_claimed'] as bool? ?? false,
      isSelfClaimed: map['is_self_claimed'] as bool? ?? false,
      isUserClaimable: map['is_user_claimable'] as bool? ?? false,
      startsAt: DateTime.tryParse((map['starts_at'] ?? '').toString()),
      expiresAt: DateTime.tryParse((map['expires_at'] ?? '').toString()),
      pointsPriceMonthly: (map['points_price_monthly'] as num?)?.toInt(),
      pointsPriceYearly: (map['points_price_yearly'] as num?)?.toInt(),
      purchasePlan: map['purchase_plan']?.toString(),
      purchasedPoints: (map['purchased_points'] as num?)?.toInt(),
      isPurchased: map['is_purchased'] as bool? ?? false,
      unlockAfterOrders: (map['unlock_after_orders'] as num?)?.toInt(),
      isOwned: map['is_owned'] as bool? ?? false,
      isFree: map['is_free'] as bool? ?? map['is_user_claimable'] as bool? ?? false,
      isAdminGranted: map['is_admin_granted'] as bool? ?? false,
      orderUnlockMet: map['order_unlock_met'] as bool? ?? false,
    );
  }

  static ProfileFeatureKind _parseKind(String value) {
    if (value == 'avatar_effect') return ProfileFeatureKind.avatarEffect;
    if (value == 'cover_effect') return ProfileFeatureKind.coverEffect;
    return ProfileFeatureKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => ProfileFeatureKind.icon,
    );
  }

  double configDouble(String key, double fallback) {
    final value = config[key];
    return value is num ? value.toDouble() : fallback;
  }

  String configString(String key, String fallback) =>
      config[key]?.toString() ?? fallback;
}

Color parseFeatureColor(String? value) {
  final normalized = (value ?? '#2196F3').replaceAll('#', '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  return Color(int.tryParse(hex, radix: 16) ?? 0xFF2196F3);
}

class ProfileFeatureUser {
  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;

  const ProfileFeatureUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
  });

  factory ProfileFeatureUser.fromMap(Map<String, dynamic> map) {
    return ProfileFeatureUser(
      id: map['id'].toString(),
      username: (map['username'] ?? '').toString(),
      fullName: (map['full_name'] ?? map['username'] ?? '').toString(),
      avatarUrl: map['avatar_url']?.toString(),
    );
  }
}
