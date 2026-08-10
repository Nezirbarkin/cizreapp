import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ad_settings_model.dart';
import '../models/admin_reward_overview_model.dart';

class RewardPointsConfigUpdate {
  final int rewardMinPoints;
  final int rewardMaxPoints;
  final int maxDailyRewardPoints;
  final int pointsPerTry;
  final bool testMode;
  final String? admobAppIdAndroid;
  final String? admobAppIdIos;
  final String? admobRewardedUnitIdAndroid;
  final String? admobRewardedUnitIdIos;
  final RewardFeatureMode featureMode;
  final bool earnEnabled;
  final bool ssvEnabled;
  final bool spendEnabled;
  final bool eligibleProductsEnabled;
  final bool adminReportingEnabled;
  final int maxViewsPerDay;
  final int maxViewsPerHour;
  final int cooldownSeconds;
  final String reason;

  const RewardPointsConfigUpdate({
    required this.rewardMinPoints,
    required this.rewardMaxPoints,
    required this.maxDailyRewardPoints,
    required this.pointsPerTry,
    required this.testMode,
    this.admobAppIdAndroid,
    this.admobAppIdIos,
    this.admobRewardedUnitIdAndroid,
    this.admobRewardedUnitIdIos,
    required this.featureMode,
    required this.earnEnabled,
    required this.ssvEnabled,
    required this.spendEnabled,
    required this.eligibleProductsEnabled,
    required this.adminReportingEnabled,
    required this.maxViewsPerDay,
    required this.maxViewsPerHour,
    required this.cooldownSeconds,
    required this.reason,
  });

  static final RegExp _appIdPattern = RegExp(
    r'^ca-app-pub-[0-9]{16}~[0-9]{10}$',
  );
  static final RegExp _unitIdPattern = RegExp(
    r'^ca-app-pub-[0-9]{16}/[0-9]{10}$',
  );

  String? get normalizedAppIdAndroid => _emptyToNull(admobAppIdAndroid);
  String? get normalizedAppIdIos => _emptyToNull(admobAppIdIos);
  String? get normalizedRewardedUnitIdAndroid =>
      _emptyToNull(admobRewardedUnitIdAndroid);
  String? get normalizedRewardedUnitIdIos =>
      _emptyToNull(admobRewardedUnitIdIos);

  String? validate() {
    if (rewardMinPoints <= 0 || rewardMaxPoints != rewardMinPoints) {
      return 'Reklam ödülü pozitif ve sabit bir puan değeri olmalı.';
    }
    if (maxDailyRewardPoints < 0 ||
        pointsPerTry <= 0 ||
        pointsPerTry % 100 != 0) {
      return 'Günlük bütçe negatif olamaz; 1 TL karşılığı puan 100’ün katı olmalı.';
    }
    if ((normalizedAppIdAndroid != null &&
            !_appIdPattern.hasMatch(normalizedAppIdAndroid!)) ||
        (normalizedAppIdIos != null &&
            !_appIdPattern.hasMatch(normalizedAppIdIos!))) {
      return 'AdMob App ID biçimi geçersiz. Örnek: ca-app-pub-1234567890123456~1234567890';
    }
    if ((normalizedRewardedUnitIdAndroid != null &&
            !_unitIdPattern.hasMatch(normalizedRewardedUnitIdAndroid!)) ||
        (normalizedRewardedUnitIdIos != null &&
            !_unitIdPattern.hasMatch(normalizedRewardedUnitIdIos!))) {
      return 'Rewarded Unit ID biçimi geçersiz. Örnek: ca-app-pub-1234567890123456/1234567890';
    }
    if (!testMode &&
        featureMode == RewardFeatureMode.enabled &&
        (normalizedRewardedUnitIdAndroid == null ||
            normalizedRewardedUnitIdIos == null)) {
      return 'Gerçek reklamı açmak için Android ve iOS Rewarded Unit ID alanlarını doldurun.';
    }
    // 0 "block-all" anlamına gelir (grant_verified_ad_points: count >= 0 her zaman
    // true), bu yüzden günlük/saatlik izleme limiti en az 1 olmalıdır.
    if (maxViewsPerDay < 1 || maxViewsPerHour < 1) {
      return 'Günlük ve saatlik maksimum izleme limiti en az 1 olmalı.';
    }
    if (cooldownSeconds < 0) {
      return 'İzlemeler arası bekleme süresi negatif olamaz.';
    }
    if (reason.trim().length < 8 || reason.trim().length > 1000) {
      return 'Değişiklik gerekçesi 8-1000 karakter olmalı.';
    }
    if (earnEnabled && testMode) {
      return 'Test modunda ekonomik puan kazanımı açılamaz.';
    }
    if (earnEnabled &&
        (!ssvEnabled || featureMode != RewardFeatureMode.enabled)) {
      return 'Puan kazanımı için SSV etkin ve özellik modu enabled olmalı.';
    }
    return null;
  }

  Map<String, dynamic> toRpcParams() => {
    'p_reward_min_points': rewardMinPoints,
    'p_reward_max_points': rewardMaxPoints,
    'p_max_daily_reward_points': maxDailyRewardPoints,
    'p_points_per_try': pointsPerTry,
    'p_test_mode': testMode,
    'p_admob_app_id_android': normalizedAppIdAndroid,
    'p_admob_app_id_ios': normalizedAppIdIos,
    'p_admob_rewarded_unit_id_android': normalizedRewardedUnitIdAndroid,
    'p_admob_rewarded_unit_id_ios': normalizedRewardedUnitIdIos,
    'p_reward_feature_mode': featureMode.name,
    'p_earn_enabled': earnEnabled,
    'p_ssv_enabled': ssvEnabled,
    'p_spend_enabled': spendEnabled,
    'p_eligible_products_enabled': eligibleProductsEnabled,
    'p_reason': reason.trim(),
    'p_max_views_per_day': maxViewsPerDay,
    'p_max_views_per_hour': maxViewsPerHour,
    'p_cooldown_seconds': cooldownSeconds,
    'p_admin_reporting_enabled': adminReportingEnabled,
  };
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// Yeni sistemde okuma güvenli public view'dan, admin mutasyonu ise yalnız
/// doğrulamalı/audit'li RPC'den yapılır. `ad_settings` tablosuna doğrudan yazmaz.
class AdSettingsService {
  final SupabaseClient? _client;

  AdSettingsService({SupabaseClient? client}) : _client = client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<AdSettings?> getSettings() async {
    try {
      final row = await _supabase
          .from('reward_points_public_config')
          .select()
          .eq('id', 1)
          .maybeSingle();
      if (row == null) {
        debugPrint(
          '[AdSettings] public_config_empty view=reward_points_public_config id=1',
        );
        return null;
      }
      final settings = AdSettings.fromJson(row);
      debugPrint(
        '[AdSettings] public_config_loaded '
        'testMode=${settings.testMode} mode=${settings.rewardFeatureMode.name} '
        'schemaReady=${settings.rewardPointsSchemaReady} '
        'earnEnabled=${settings.rewardPointsEarnEnabled} '
        'ssvRequired=${settings.rewardPointsSsvRequired} '
        'ssvEnabled=${settings.rewardPointsSsvEnabled} '
        'androidUnitPresent=${settings.admobRewardedUnitIdAndroid?.trim().isNotEmpty == true} '
        'iosUnitPresent=${settings.admobRewardedUnitIdIos?.trim().isNotEmpty == true}',
      );
      return settings;
    } catch (error) {
      debugPrint(
        '[AdSettings] public_config_failed '
        'errorType=${error.runtimeType} error=$error',
      );
      return null;
    }
  }

  Future<AdSettings> updateRewardPointsConfig(
    RewardPointsConfigUpdate update,
  ) async {
    final validationError = update.validate();
    if (validationError != null) {
      throw ArgumentError(validationError);
    }
    final params = update.toRpcParams();
    debugPrint(
      '[AdSettings] update_rpc_start '
      'rpc=admin_update_reward_points_config testMode=${update.testMode} '
      'mode=${update.featureMode.name} earnEnabled=${update.earnEnabled} '
      'ssvEnabled=${update.ssvEnabled} '
      'androidAppPresent=${update.normalizedAppIdAndroid != null} '
      'iosAppPresent=${update.normalizedAppIdIos != null} '
      'androidUnitPresent=${update.normalizedRewardedUnitIdAndroid != null} '
      'iosUnitPresent=${update.normalizedRewardedUnitIdIos != null} '
      'paramCount=${params.length}',
    );
    dynamic data;
    try {
      data = await _supabase.rpc(
        'admin_update_reward_points_config',
        params: params,
      );
    } catch (error) {
      debugPrint(
        '[AdSettings] update_rpc_failed '
        'errorType=${error.runtimeType} error=$error',
      );
      rethrow;
    }
    if (data is! Map) {
      throw StateError('Admin config RPC beklenmeyen yanıt döndürdü.');
    }
    final settings = AdSettings.fromJson(Map<String, dynamic>.from(data));
    debugPrint(
      '[AdSettings] update_rpc_succeeded '
      'policyVersion=${settings.rewardPolicyVersion} '
      'mode=${settings.rewardFeatureMode.name}',
    );
    return settings;
  }

  /// Yalnız adminler çağırabilir; RPC iç kontrolle admin olmayanları reddeder.
  /// AdMob/SSV bağlantı durumu, bugünkü kazanımlar, son puan olayları ve en çok
  /// kazananlar tek yanıtta döner.
  Future<AdminRewardOverview> getAdminOverview() async {
    dynamic data;
    try {
      data = await _supabase.rpc('admin_reward_points_overview');
    } catch (error) {
      debugPrint(
        '[AdSettings] overview_rpc_failed '
        'errorType=${error.runtimeType} error=$error',
      );
      rethrow;
    }
    if (data is! Map) {
      throw StateError('Admin overview RPC beklenmeyen yanıt döndürdü.');
    }
    final overview = AdminRewardOverview.fromJson(
      Map<String, dynamic>.from(data),
    );
    debugPrint(
      '[AdSettings] overview_rpc_succeeded '
      'androidAppPresent=${overview.config.admobAppIdAndroid?.trim().isNotEmpty == true} '
      'iosAppPresent=${overview.config.admobAppIdIos?.trim().isNotEmpty == true} '
      'androidUnitPresent=${overview.config.admobRewardedUnitIdAndroid?.trim().isNotEmpty == true} '
      'iosUnitPresent=${overview.config.admobRewardedUnitIdIos?.trim().isNotEmpty == true}',
    );
    return overview;
  }
}
