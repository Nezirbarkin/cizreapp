enum RewardFeatureMode {
  disabled,
  observe,
  cohort,
  enabled;

  static RewardFeatureMode fromJson(Object? value) {
    return RewardFeatureMode.values.firstWhere(
      (mode) => mode.name == value,
      orElse: () => RewardFeatureMode.disabled,
    );
  }
}

/// Reklam puanı özelliğinin istemci tarafından görülebilen yapılandırması.
///
/// Parasal eski reklam alanları bilerek bu modele alınmaz. Böylece geçmişte TL
/// olarak verilmiş reklam ödülleri puana dönüştürülmez veya puan toplamlarına
/// karışmaz. Eski backend ile geçiş uyumluluğu yalnız kimlik/limit alanlarının
/// güvenli okunmasıyla sınırlıdır.
class AdSettings {
  final bool testMode;
  final String? admobAppIdAndroid;
  final String? admobAppIdIos;
  final String? admobRewardedUnitIdAndroid;
  final String? admobRewardedUnitIdIos;
  final int rewardMinPoints;
  final int rewardMaxPoints;
  final int? maxDailyRewardPoints;
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

  const AdSettings({
    this.testMode = false,
    this.admobAppIdAndroid,
    this.admobAppIdIos,
    this.admobRewardedUnitIdAndroid,
    this.admobRewardedUnitIdIos,
    this.rewardMinPoints = 0,
    this.rewardMaxPoints = 0,
    this.maxDailyRewardPoints,
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
  });

  factory AdSettings.fromJson(Map<String, dynamic> json) {
    final hasPointContract =
        json.containsKey('reward_min_points') &&
        json.containsKey('reward_max_points') &&
        json.containsKey('points_per_try');
    return AdSettings(
      testMode: json['test_mode'] as bool? ?? false,
      admobAppIdAndroid: json['admob_app_id_android'] as String?,
      admobAppIdIos: json['admob_app_id_ios'] as String?,
      admobRewardedUnitIdAndroid:
          json['admob_rewarded_unit_id_android'] as String?,
      admobRewardedUnitIdIos: json['admob_rewarded_unit_id_ios'] as String?,
      rewardMinPoints: _int(json['reward_min_points']),
      rewardMaxPoints: _int(json['reward_max_points']),
      maxDailyRewardPoints: json['max_daily_reward_points'] == null
          ? null
          : _int(json['max_daily_reward_points']),
      pointsPerTry: _int(json['points_per_try']),
      rewardPolicyVersion: _int(json['reward_policy_version']),
      rewardFeatureMode: RewardFeatureMode.fromJson(
        json['reward_feature_mode'],
      ),
      rewardPointsSchemaReady:
          json['reward_points_schema_ready'] as bool? ?? hasPointContract,
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
    );
  }

  /// Yalnız yeni puan sözleşmesini üretir; deprecated TL alanlarını asla yazmaz.
  Map<String, dynamic> toJson() => {
    'reward_min_points': rewardMinPoints,
    'reward_max_points': rewardMaxPoints,
    'max_daily_reward_points': maxDailyRewardPoints,
    'points_per_try': pointsPerTry,
    'reward_policy_version': rewardPolicyVersion,
    'reward_feature_mode': rewardFeatureMode.name,
    'reward_points_schema_ready': rewardPointsSchemaReady,
    'reward_points_earn_enabled': rewardPointsEarnEnabled,
    'reward_points_ssv_required': rewardPointsSsvRequired,
    'reward_points_ssv_enabled': rewardPointsSsvEnabled,
    'reward_points_spend_enabled': rewardPointsSpendEnabled,
    'reward_points_eligible_products_enabled':
        rewardPointsEligibleProductsEnabled,
    'reward_points_admin_reporting_enabled': rewardPointsAdminReportingEnabled,
    'legacy_ad_tl_grant_disabled': legacyAdTlGrantDisabled,
  };

  /// İstemci görünürlüğü içindir. Nihai açma/güvenlik kararını session endpoint'i
  /// ve SSV kredi RPC'si verir.
  bool get canRequestRewardSession => testMode
      ? rewardPointsSchemaReady &&
            legacyAdTlGrantDisabled &&
            rewardFeatureMode == RewardFeatureMode.enabled
      : rewardPointsSchemaReady &&
            rewardPointsEarnEnabled &&
            rewardPointsSsvRequired &&
            rewardPointsSsvEnabled &&
            legacyAdTlGrantDisabled &&
            rewardFeatureMode == RewardFeatureMode.enabled;

  /// Üretim rewarded unit ID'leri backend public view'ında yer almıyor. Mobil
  /// build sırasında dart-define ile sağlanabilir; boşsa servis fail-closed olur.
  static const String productionRewardedUnitIdAndroid = String.fromEnvironment(
    'ADMOB_REWARDED_UNIT_ID_ANDROID',
  );
  static const String productionRewardedUnitIdIos = String.fromEnvironment(
    'ADMOB_REWARDED_UNIT_ID_IOS',
  );

  static const String testRewardedUnitIdAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const String testRewardedUnitIdIos =
      'ca-app-pub-3940256099942544/1712485313';

  AdSettings copyWith({
    bool? testMode,
    String? admobAppIdAndroid,
    String? admobAppIdIos,
    String? admobRewardedUnitIdAndroid,
    String? admobRewardedUnitIdIos,
    int? rewardMinPoints,
    int? rewardMaxPoints,
    int? maxDailyRewardPoints,
    int? pointsPerTry,
    int? rewardPolicyVersion,
    RewardFeatureMode? rewardFeatureMode,
    bool? rewardPointsSchemaReady,
    bool? rewardPointsEarnEnabled,
    bool? rewardPointsSsvRequired,
    bool? rewardPointsSsvEnabled,
    bool? rewardPointsSpendEnabled,
    bool? rewardPointsEligibleProductsEnabled,
    bool? rewardPointsAdminReportingEnabled,
    bool? legacyAdTlGrantDisabled,
    int? maxViewsPerDay,
    int? maxViewsPerHour,
    int? cooldownSeconds,
  }) {
    return AdSettings(
      testMode: testMode ?? this.testMode,
      admobAppIdAndroid: admobAppIdAndroid ?? this.admobAppIdAndroid,
      admobAppIdIos: admobAppIdIos ?? this.admobAppIdIos,
      admobRewardedUnitIdAndroid:
          admobRewardedUnitIdAndroid ?? this.admobRewardedUnitIdAndroid,
      admobRewardedUnitIdIos:
          admobRewardedUnitIdIos ?? this.admobRewardedUnitIdIos,
      rewardMinPoints: rewardMinPoints ?? this.rewardMinPoints,
      rewardMaxPoints: rewardMaxPoints ?? this.rewardMaxPoints,
      maxDailyRewardPoints: maxDailyRewardPoints ?? this.maxDailyRewardPoints,
      pointsPerTry: pointsPerTry ?? this.pointsPerTry,
      rewardPolicyVersion: rewardPolicyVersion ?? this.rewardPolicyVersion,
      rewardFeatureMode: rewardFeatureMode ?? this.rewardFeatureMode,
      rewardPointsSchemaReady:
          rewardPointsSchemaReady ?? this.rewardPointsSchemaReady,
      rewardPointsEarnEnabled:
          rewardPointsEarnEnabled ?? this.rewardPointsEarnEnabled,
      rewardPointsSsvRequired:
          rewardPointsSsvRequired ?? this.rewardPointsSsvRequired,
      rewardPointsSsvEnabled:
          rewardPointsSsvEnabled ?? this.rewardPointsSsvEnabled,
      rewardPointsSpendEnabled:
          rewardPointsSpendEnabled ?? this.rewardPointsSpendEnabled,
      rewardPointsEligibleProductsEnabled:
          rewardPointsEligibleProductsEnabled ??
          this.rewardPointsEligibleProductsEnabled,
      rewardPointsAdminReportingEnabled:
          rewardPointsAdminReportingEnabled ??
          this.rewardPointsAdminReportingEnabled,
      legacyAdTlGrantDisabled:
          legacyAdTlGrantDisabled ?? this.legacyAdTlGrantDisabled,
      maxViewsPerDay: maxViewsPerDay ?? this.maxViewsPerDay,
      maxViewsPerHour: maxViewsPerHour ?? this.maxViewsPerHour,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
    );
  }
}

int _int(Object? value) => value is num ? value.toInt() : 0;
