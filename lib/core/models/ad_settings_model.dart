class AdSettings {
  final bool isEnabled;
  final bool testMode;
  final String? admobAppIdAndroid;
  final String? admobAppIdIos;
  final String? admobRewardedUnitIdAndroid;
  final String? admobRewardedUnitIdIos;
  final double rewardMinTry;
  final double rewardMaxTry;
  final int maxViewsPerDay;
  final int maxViewsPerHour;
  final int minWatchSeconds;
  final int cooldownSeconds;
  final double maxDailyPayoutTry;
  final String? cardDescription;

  AdSettings({
    required this.isEnabled,
    required this.testMode,
    this.admobAppIdAndroid,
    this.admobAppIdIos,
    this.admobRewardedUnitIdAndroid,
    this.admobRewardedUnitIdIos,
    required this.rewardMinTry,
    required this.rewardMaxTry,
    required this.maxViewsPerDay,
    required this.maxViewsPerHour,
    required this.minWatchSeconds,
    required this.cooldownSeconds,
    required this.maxDailyPayoutTry,
    this.cardDescription,
  });

  factory AdSettings.fromJson(Map<String, dynamic> json) {
    return AdSettings(
      isEnabled: json['is_enabled'] as bool? ?? false,
      testMode: json['test_mode'] as bool? ?? true,
      admobAppIdAndroid: json['admob_app_id_android'] as String?,
      admobAppIdIos: json['admob_app_id_ios'] as String?,
      admobRewardedUnitIdAndroid: json['admob_rewarded_unit_id_android'] as String?,
      admobRewardedUnitIdIos: json['admob_rewarded_unit_id_ios'] as String?,
      rewardMinTry: (json['reward_min_try'] as num?)?.toDouble() ?? 0,
      rewardMaxTry: (json['reward_max_try'] as num?)?.toDouble() ?? 0,
      maxViewsPerDay: (json['max_views_per_day'] as num?)?.toInt() ?? 0,
      maxViewsPerHour: (json['max_views_per_hour'] as num?)?.toInt() ?? 0,
      minWatchSeconds: (json['min_watch_seconds'] as num?)?.toInt() ?? 0,
      cooldownSeconds: (json['cooldown_seconds'] as num?)?.toInt() ?? 0,
      maxDailyPayoutTry: (json['max_daily_payout_try'] as num?)?.toDouble() ?? 0,
      cardDescription: json['card_description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_enabled': isEnabled,
        'test_mode': testMode,
        'admob_app_id_android': admobAppIdAndroid,
        'admob_app_id_ios': admobAppIdIos,
        'admob_rewarded_unit_id_android': admobRewardedUnitIdAndroid,
        'admob_rewarded_unit_id_ios': admobRewardedUnitIdIos,
        'reward_min_try': rewardMinTry,
        'reward_max_try': rewardMaxTry,
        'max_views_per_day': maxViewsPerDay,
        'max_views_per_hour': maxViewsPerHour,
        'min_watch_seconds': minWatchSeconds,
        'cooldown_seconds': cooldownSeconds,
        'max_daily_payout_try': maxDailyPayoutTry,
        'card_description': cardDescription,
      };

  /// Test için Google'ın resmi test reklam birim ID'leri
  static const String testRewardedUnitIdAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const String testRewardedUnitIdIos = 'ca-app-pub-3940256099942544/1712485313';

  AdSettings copyWith({
    bool? isEnabled,
    bool? testMode,
    String? admobAppIdAndroid,
    String? admobAppIdIos,
    String? admobRewardedUnitIdAndroid,
    String? admobRewardedUnitIdIos,
    double? rewardMinTry,
    double? rewardMaxTry,
    int? maxViewsPerDay,
    int? maxViewsPerHour,
    int? minWatchSeconds,
    int? cooldownSeconds,
    double? maxDailyPayoutTry,
    String? cardDescription,
  }) {
    return AdSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      testMode: testMode ?? this.testMode,
      admobAppIdAndroid: admobAppIdAndroid ?? this.admobAppIdAndroid,
      admobAppIdIos: admobAppIdIos ?? this.admobAppIdIos,
      admobRewardedUnitIdAndroid: admobRewardedUnitIdAndroid ?? this.admobRewardedUnitIdAndroid,
      admobRewardedUnitIdIos: admobRewardedUnitIdIos ?? this.admobRewardedUnitIdIos,
      rewardMinTry: rewardMinTry ?? this.rewardMinTry,
      rewardMaxTry: rewardMaxTry ?? this.rewardMaxTry,
      maxViewsPerDay: maxViewsPerDay ?? this.maxViewsPerDay,
      maxViewsPerHour: maxViewsPerHour ?? this.maxViewsPerHour,
      minWatchSeconds: minWatchSeconds ?? this.minWatchSeconds,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      maxDailyPayoutTry: maxDailyPayoutTry ?? this.maxDailyPayoutTry,
      cardDescription: cardDescription ?? this.cardDescription,
    );
  }
}
