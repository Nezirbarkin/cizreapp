import 'ad_settings_model.dart';

/// Admin'in "Reklam Ayarları" ekranında gördüğü tek yanıt paketi. Yalnız adminler
/// için dönen `admin_reward_points_overview` RPC'sinin Dart karşılığıdır.
class AdminRewardOverview {
  final AdminRewardConfig config;
  final AdminRewardToday today;
  final List<AdminRewardRecentSession> recent;
  final List<AdminRewardTopEarner> topEarners;

  const AdminRewardOverview({
    required this.config,
    required this.today,
    required this.recent,
    required this.topEarners,
  });

  factory AdminRewardOverview.fromJson(Map<String, dynamic> json) {
    return AdminRewardOverview(
      config: AdminRewardConfig.fromJson(
        Map<String, dynamic>.from(json['config'] as Map? ?? const {}),
      ),
      today: AdminRewardToday.fromJson(
        Map<String, dynamic>.from(json['today'] as Map? ?? const {}),
      ),
      recent: ((json['recent'] as List?) ?? const [])
          .map((e) => AdminRewardRecentSession.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(growable: false),
      topEarners: ((json['top_earners'] as List?) ?? const [])
          .map((e) => AdminRewardTopEarner.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList(growable: false),
    );
  }
}

/// AdMob/SSV bağlantı durumu dahil tam puan yapılandırması. `AdSettings` ile
/// örtüşür ancak admin'e AdMob App/Unit ID'lerini de açar.
class AdminRewardConfig {
  final bool testMode;
  final String? admobAppIdAndroid;
  final String? admobAppIdIos;
  final String? admobRewardedUnitIdAndroid;
  final String? admobRewardedUnitIdIos;
  final int rewardMinPoints;
  final int rewardMaxPoints;
  final int maxDailyRewardPoints;
  final int pointsPerTry;
  final int rewardPolicyVersion;
  final RewardFeatureMode rewardFeatureMode;
  final bool rewardPointsSchemaReady;
  final bool rewardPointsEarnEnabled;
  final bool rewardPointsSsvRequired;
  final bool rewardPointsSsvEnabled;
  final bool rewardPointsSpendEnabled;
  final bool rewardPointsEligibleProductsEnabled;
  final bool rewardPointsAdminReportingEnabled;
  final bool legacyAdTlGrantDisabled;
  final int maxViewsPerDay;
  final int maxViewsPerHour;
  final int cooldownSeconds;
  final int fraudHashRetentionDays;

  const AdminRewardConfig({
    this.testMode = false,
    this.admobAppIdAndroid,
    this.admobAppIdIos,
    this.admobRewardedUnitIdAndroid,
    this.admobRewardedUnitIdIos,
    this.rewardMinPoints = 0,
    this.rewardMaxPoints = 0,
    this.maxDailyRewardPoints = 0,
    this.pointsPerTry = 0,
    this.rewardPolicyVersion = 0,
    this.rewardFeatureMode = RewardFeatureMode.disabled,
    this.rewardPointsSchemaReady = false,
    this.rewardPointsEarnEnabled = false,
    this.rewardPointsSsvRequired = true,
    this.rewardPointsSsvEnabled = false,
    this.rewardPointsSpendEnabled = false,
    this.rewardPointsEligibleProductsEnabled = false,
    this.rewardPointsAdminReportingEnabled = false,
    this.legacyAdTlGrantDisabled = true,
    this.maxViewsPerDay = 0,
    this.maxViewsPerHour = 0,
    this.cooldownSeconds = 0,
    this.fraudHashRetentionDays = 0,
  });

  factory AdminRewardConfig.fromJson(Map<String, dynamic> json) {
    return AdminRewardConfig(
      testMode: json['test_mode'] as bool? ?? false,
      admobAppIdAndroid: json['admob_app_id_android'] as String?,
      admobAppIdIos: json['admob_app_id_ios'] as String?,
      admobRewardedUnitIdAndroid:
          json['admob_rewarded_unit_id_android'] as String?,
      admobRewardedUnitIdIos: json['admob_rewarded_unit_id_ios'] as String?,
      rewardMinPoints: _int(json['reward_min_points']),
      rewardMaxPoints: _int(json['reward_max_points']),
      maxDailyRewardPoints: _int(json['max_daily_reward_points']),
      pointsPerTry: _int(json['points_per_try']),
      rewardPolicyVersion: _int(json['reward_policy_version']),
      rewardFeatureMode: RewardFeatureMode.fromJson(json['reward_feature_mode']),
      rewardPointsSchemaReady:
          json['reward_points_schema_ready'] as bool? ?? false,
      rewardPointsEarnEnabled:
          json['reward_points_earn_enabled'] as bool? ?? false,
      rewardPointsSsvRequired:
          json['reward_points_ssv_required'] as bool? ?? true,
      rewardPointsSsvEnabled:
          json['reward_points_ssv_enabled'] as bool? ?? false,
      rewardPointsSpendEnabled:
          json['reward_points_spend_enabled'] as bool? ?? false,
      rewardPointsEligibleProductsEnabled:
          json['reward_points_eligible_products_enabled'] as bool? ?? false,
      rewardPointsAdminReportingEnabled:
          json['reward_points_admin_reporting_enabled'] as bool? ?? false,
      legacyAdTlGrantDisabled:
          json['legacy_ad_tl_grant_disabled'] as bool? ?? true,
      maxViewsPerDay: _int(json['max_views_per_day']),
      maxViewsPerHour: _int(json['max_views_per_hour']),
      cooldownSeconds: _int(json['cooldown_seconds']),
      fraudHashRetentionDays: _int(json['fraud_hash_retention_days']),
    );
  }
}

class AdminRewardToday {
  final int grantedPoints;
  final int grantCount;
  final int distinctUsers;
  final int maxDailyRewardPoints;
  final int remainingPoints;

  const AdminRewardToday({
    this.grantedPoints = 0,
    this.grantCount = 0,
    this.distinctUsers = 0,
    this.maxDailyRewardPoints = 0,
    this.remainingPoints = 0,
  });

  factory AdminRewardToday.fromJson(Map<String, dynamic> json) {
    return AdminRewardToday(
      grantedPoints: _int(json['granted_points']),
      grantCount: _int(json['grant_count']),
      distinctUsers: _int(json['distinct_users']),
      maxDailyRewardPoints: _int(json['max_daily_reward_points']),
      remainingPoints: _int(json['remaining_points']),
    );
  }

  /// Bütçe yüzdesi 0..1; maksimum tanımsızsa 0.
  double get budgetUsedFraction => maxDailyRewardPoints <= 0
      ? 0
      : (grantedPoints / maxDailyRewardPoints).clamp(0.0, 1.0);
}

class AdminRewardRecentSession {
  final String sessionId;
  final String userId;
  final String? fullName;
  final String? email;
  final int? creditedPoints;
  final String status;
  final DateTime? creditedAt;

  const AdminRewardRecentSession({
    required this.sessionId,
    required this.userId,
    this.fullName,
    this.email,
    this.creditedPoints,
    required this.status,
    this.creditedAt,
  });

  factory AdminRewardRecentSession.fromJson(Map<String, dynamic> json) {
    return AdminRewardRecentSession(
      sessionId: json['session_id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String?,
      email: json['email'] as String?,
      creditedPoints: (json['credited_points'] as num?)?.toInt(),
      status: json['status'] as String? ?? '',
      creditedAt: json['credited_at'] == null
          ? null
          : DateTime.parse(json['credited_at'] as String).toLocal(),
    );
  }
}

class AdminRewardTopEarner {
  final String userId;
  final String? fullName;
  final String? email;
  final int totalPoints;
  final int sessionCount;

  const AdminRewardTopEarner({
    required this.userId,
    this.fullName,
    this.email,
    this.totalPoints = 0,
    this.sessionCount = 0,
  });

  factory AdminRewardTopEarner.fromJson(Map<String, dynamic> json) {
    return AdminRewardTopEarner(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String?,
      email: json['email'] as String?,
      totalPoints: _int(json['total_points']),
      sessionCount: _int(json['session_count']),
    );
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;