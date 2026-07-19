import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ad_settings_model.dart';
import 'ad_settings_service.dart';

/// Ödüllü (rewarded) reklam yükleme/gösterme ve ödül talep etme servisi.
///
/// Ödül bakiyeye SADECE `grant-ad-reward` Edge Function'ı (service_role)
/// tarafından yazılır; bu servis client tarafında yalnızca reklamı gösterir
/// ve kullanıcı ödülü tamamen izlediğinde ödül talebini backend'e iletir.
class RewardedAdService {
  static const _deviceIdKey = 'ad_reward_device_id';

  final AdSettingsService _settingsService = AdSettingsService();
  RewardedAd? _rewardedAd;
  AdSettings? _settings;

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      final random = DateTime.now().microsecondsSinceEpoch;
      id = 'dev-$random-${identityHashCode(prefs)}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  String? _unitIdFor(AdSettings settings) {
    if (settings.testMode) {
      return Platform.isIOS
          ? AdSettings.testRewardedUnitIdIos
          : AdSettings.testRewardedUnitIdAndroid;
    }
    return Platform.isIOS
        ? settings.admobRewardedUnitIdIos
        : settings.admobRewardedUnitIdAndroid;
  }

  /// Ayarları getirir; reklam kapalıysa veya birim ID tanımsızsa null döner.
  Future<AdSettings?> loadSettings() async {
    _settings = await _settingsService.getSettings();
    if (_settings == null || !_settings!.isEnabled) return null;
    return _settings;
  }

  /// Reklamı önceden yükler (ekran açılırken çağırmak gecikmeyi azaltır).
  Future<bool> preload() async {
    final settings = _settings ?? await loadSettings();
    if (settings == null) return false;
    final unitId = _unitIdFor(settings);
    if (unitId == null || unitId.isEmpty) return false;

    final completer = Completer<bool>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          debugPrint('❌ Rewarded ad yüklenemedi: $error');
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future;
  }

  bool get isReady => _rewardedAd != null;

  /// Reklamı gösterir; kullanıcı ödülü tam izlerse backend'e ödül talebini
  /// gönderir ve sonucu (yeni bakiye) döner.
  Future<AdRewardResult> showAndClaim() async {
    final ad = _rewardedAd;
    if (ad == null) {
      return AdRewardResult.failure('Reklam hazır değil, lütfen tekrar deneyin');
    }
    _rewardedAd = null;

    final dismissedCompleter = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissedCompleter.isCompleted) dismissedCompleter.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissedCompleter.isCompleted) dismissedCompleter.complete();
      },
    );

    var earned = false;
    await ad.show(onUserEarnedReward: (adWithoutView, reward) {
      earned = true;
    });
    await dismissedCompleter.future;

    if (!earned) {
      return AdRewardResult.failure('Reklam sonuna kadar izlenmedi, ödül verilmedi');
    }

    return _claimReward();
  }

  Future<AdRewardResult> _claimReward() async {
    final deviceId = await _getOrCreateDeviceId();
    final minSeconds = _settings?.minWatchSeconds ?? 0;

    Map<String, dynamic>? body;
    int? statusCode;
    Object? caughtError;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'grant-ad-reward',
        body: {
          'device_id': deviceId,
          'watched_seconds': minSeconds,
        },
      );
      statusCode = response.status;
      final data = response.data;
      if (data is Map) body = Map<String, dynamic>.from(data);
    } on FunctionException catch (e) {
      // Supabase Functions istemcisi 4xx/5xx'te FunctionException atar.
      // Gövdeyi (limit_type, retry_after_seconds, error) yakalayıp özel
      // mesaj gösterebilelim.
      statusCode = e.status;
      final details = e.details;
      if (details is Map) {
        body = Map<String, dynamic>.from(details);
      } else if (e.toString().contains('{')) {
        // Güvenlik ağı: bazı sürümlerde details null olabiliyor
        body = null;
      }
    } catch (e) {
      caughtError = e;
    }

    // ---- 1) Body'den limit türünü çıkar ----
    final limitType = body?['limit_type'] as String?;
    final retryAfter = (body?['retry_after_seconds'] as num?)?.toInt();
    final rawError = body?['error'] as String?;

    if (limitType == 'cooldown' && retryAfter != null) {
      return AdRewardResult.cooldown(retryAfter);
    }
    if (limitType == 'hourly' && retryAfter != null) {
      return AdRewardResult.hourly(retryAfter, message: rawError);
    }
    if (limitType == 'daily' && retryAfter != null) {
      return AdRewardResult.daily(retryAfter, message: rawError);
    }

    // ---- 2) Body'de limit bilgisi yoksa status kodu yorumla ----
    if (statusCode != null && statusCode != 200) {
      final msg = (rawError != null && rawError.isNotEmpty)
          ? rawError
          : 'Ödül alınamadı (sunucu $statusCode), lütfen tekrar dene';
      return AdRewardResult.failure(msg);
    }

    // ---- 3) Network/auth hatası (catch'e düştüyse) ----
    if (caughtError != null) {
      debugPrint('❌ Reklam ödülü talep hatası: $caughtError');
      final msg = caughtError.toString().toLowerCase();
      final isAuthIssue =
          msg.contains('jwt') || msg.contains('unauthorized') || msg.contains('401');
      return AdRewardResult.failure(
        isAuthIssue
            ? 'Oturumun dolmuş, lütfen yeniden giriş yap'
            : 'Bağlantı kurulamadı, internetini kontrol edip tekrar dene',
      );
    }

    // ---- 4) Beklenen başarı gövdesi ----
    if (body != null && body['reward_amount'] != null && body['new_balance'] != null) {
      return AdRewardResult.success(
        rewardAmount: (body['reward_amount'] as num).toDouble(),
        newBalance: (body['new_balance'] as num).toDouble(),
      );
    }

    return AdRewardResult.failure('Beklenmeyen yanıt, lütfen tekrar dene');
  }

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}

class AdRewardResult {
  final bool isSuccess;
  final String? errorMessage;
  final double? rewardAmount;
  final double? newBalance;

  /// 'cooldown' | 'hourly' | 'daily' | null
  final String? limitType;

  /// Cooldown/limit için kalan saniye (sunucudan geldiyse)
  final int? retryAfterSeconds;

  const AdRewardResult._(
    this.isSuccess,
    this.errorMessage,
    this.rewardAmount,
    this.newBalance, {
    this.limitType,
    this.retryAfterSeconds,
  });

  factory AdRewardResult.success({
    required double rewardAmount,
    required double newBalance,
  }) =>
      AdRewardResult._(true, null, rewardAmount, newBalance);

  factory AdRewardResult.failure(String message) =>
      AdRewardResult._(false, message, null, null);

  factory AdRewardResult.cooldown(int seconds) =>
      AdRewardResult._(
        false,
        'Reklamlar arası bekleme süresi',
        null,
        null,
        limitType: 'cooldown',
        retryAfterSeconds: seconds,
      );

  factory AdRewardResult.hourly(int seconds, {String? message}) =>
      AdRewardResult._(
        false,
        message ?? 'Saatlik reklam izleme limitine ulaştın',
        null,
        null,
        limitType: 'hourly',
        retryAfterSeconds: seconds,
      );

  factory AdRewardResult.daily(int seconds, {String? message}) =>
      AdRewardResult._(
        false,
        message ?? 'Bugünkü reklam hakkın bitti',
        null,
        null,
        limitType: 'daily',
        retryAfterSeconds: seconds,
      );
}
