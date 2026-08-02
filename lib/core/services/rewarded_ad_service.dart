import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:uuid/uuid.dart';

import '../models/ad_settings_model.dart';
import '../models/reward_session_model.dart';
import 'ad_settings_service.dart';
import 'reward_points_service.dart';

abstract interface class RewardedAdHandle {
  Future<void> setServerSideCustomData(String customData);
  Future<RewardedAdPresentation> show();
  void dispose();
}

class RewardedAdPresentation {
  final bool sdkRewardCallbackReceived;
  final String? errorMessage;

  const RewardedAdPresentation({
    required this.sdkRewardCallbackReceived,
    this.errorMessage,
  });
}

abstract interface class RewardedAdLoader {
  Future<RewardedAdHandle?> load(String adUnitId);
}

class GoogleRewardedAdLoader implements RewardedAdLoader {
  const GoogleRewardedAdLoader();

  @override
  Future<RewardedAdHandle?> load(String adUnitId) {
    final completer = Completer<RewardedAdHandle?>();
    RewardedAd.load(
      adUnitId: adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(_GoogleRewardedAdHandle(ad)),
        onAdFailedToLoad: (error) {
          debugPrint('Rewarded ad yüklenemedi: $error');
          completer.complete(null);
        },
      ),
    );
    return completer.future;
  }
}

class _GoogleRewardedAdHandle implements RewardedAdHandle {
  final RewardedAd _ad;

  _GoogleRewardedAdHandle(this._ad);

  @override
  Future<void> setServerSideCustomData(String customData) {
    // google_mobile_ads 5.3.1 API'si: custom data yüklü reklam nesnesine show
    // çağrısından önce setServerSideOptions ile bağlanır.
    return _ad.setServerSideOptions(
      ServerSideVerificationOptions(customData: customData),
    );
  }

  @override
  Future<RewardedAdPresentation> show() async {
    final dismissed = Completer<RewardedAdPresentation>();
    var sdkCallbackReceived = false;
    String? showError;

    _ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) {
          dismissed.complete(
            RewardedAdPresentation(
              sdkRewardCallbackReceived: sdkCallbackReceived,
              errorMessage: showError,
            ),
          );
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        showError = error.message;
        ad.dispose();
        if (!dismissed.isCompleted) {
          dismissed.complete(
            RewardedAdPresentation(
              sdkRewardCallbackReceived: false,
              errorMessage: showError,
            ),
          );
        }
      },
    );

    try {
      await _ad.show(
        onUserEarnedReward: (_, __) {
          // Bu callback ekonomik kredi kanıtı değildir; yalnız UI'nın SSV
          // doğrulaması bekleme aşamasına geçmesine izin verir.
          sdkCallbackReceived = true;
        },
      );
    } catch (error) {
      _ad.dispose();
      return RewardedAdPresentation(
        sdkRewardCallbackReceived: false,
        errorMessage: error.toString(),
      );
    }
    return dismissed.future;
  }

  @override
  void dispose() => _ad.dispose();
}

enum AdRewardResultState {
  credited,
  testCompleted,
  duplicate,
  verificationPending,
  rejected,
  failed,
}

class AdRewardResult {
  final AdRewardResultState state;
  final String rewardSessionId;
  final int? rewardPoints;
  final String? errorMessage;

  const AdRewardResult._({
    required this.state,
    required this.rewardSessionId,
    this.rewardPoints,
    this.errorMessage,
  });

  bool get isSuccess => state == AdRewardResultState.credited;
  bool get isPending => state == AdRewardResultState.verificationPending;

  factory AdRewardResult.credited({
    required String sessionId,
    required int points,
  }) => AdRewardResult._(
    state: AdRewardResultState.credited,
    rewardSessionId: sessionId,
    rewardPoints: points,
  );

  factory AdRewardResult.testCompleted({required String sessionId}) =>
      AdRewardResult._(
        state: AdRewardResultState.testCompleted,
        rewardSessionId: sessionId,
        rewardPoints: 0,
        errorMessage: 'Test reklamı tamamlandı; gerçek puan eklenmedi.',
      );

  factory AdRewardResult.duplicate({required String sessionId, int? points}) =>
      AdRewardResult._(
        state: AdRewardResultState.duplicate,
        rewardSessionId: sessionId,
        rewardPoints: points,
        errorMessage: 'Bu reklam doğrulaması daha önce işlendi.',
      );

  factory AdRewardResult.pending(String sessionId) => AdRewardResult._(
    state: AdRewardResultState.verificationPending,
    rewardSessionId: sessionId,
    errorMessage:
        'Puanın sunucuda doğrulanıyor. Doğrulanmadan bakiyene eklenmez.',
  );

  factory AdRewardResult.rejected(String sessionId, String message) =>
      AdRewardResult._(
        state: AdRewardResultState.rejected,
        rewardSessionId: sessionId,
        errorMessage: message,
      );

  factory AdRewardResult.failed(String message, {String sessionId = ''}) =>
      AdRewardResult._(
        state: AdRewardResultState.failed,
        rewardSessionId: sessionId,
        errorMessage: message,
      );
}

/// İstemci yalnız JWT'li reward session açar, opaque custom data'yı SDK'ya
/// bağlar ve server-side SSV sonucunu sorgular. Eski `grant-ad-reward` yolu ve
/// istemci tarafı ekonomik kredi varsayımı bulunmaz.
class RewardedAdService {
  final AdSettingsService settingsService;
  final RewardPointsGateway pointsGateway;
  final RewardedAdLoader adLoader;
  late final RewardVerificationPoller verificationPoller;

  RewardedAdHandle? _rewardedAd;
  AdSettings? _settings;

  RewardedAdService({
    AdSettingsService? settingsService,
    RewardPointsGateway? pointsGateway,
    RewardedAdLoader? adLoader,
    RewardVerificationPoller? verificationPoller,
  }) : settingsService = settingsService ?? AdSettingsService(),
       pointsGateway = pointsGateway ?? RewardPointsService(),
       adLoader = adLoader ?? const GoogleRewardedAdLoader() {
    this.verificationPoller =
        verificationPoller ??
        RewardVerificationPoller(gateway: this.pointsGateway);
  }

  String? _unitIdFor(AdSettings settings) {
    if (settings.testMode) {
      return Platform.isIOS
          ? AdSettings.testRewardedUnitIdIos
          : AdSettings.testRewardedUnitIdAndroid;
    }
    final configured = Platform.isIOS
        ? settings.admobRewardedUnitIdIos
        : settings.admobRewardedUnitIdAndroid;
    if (configured != null && configured.trim().isNotEmpty) return configured;
    final buildValue = Platform.isIOS
        ? AdSettings.productionRewardedUnitIdIos
        : AdSettings.productionRewardedUnitIdAndroid;
    return buildValue.isEmpty ? null : buildValue;
  }

  Future<AdSettings?> loadSettings() async {
    _settings = await settingsService.getSettings();
    if (_settings?.canRequestRewardSession != true) return null;
    return _settings;
  }

  Future<bool> preload() async {
    final settings = _settings ?? await loadSettings();
    if (settings == null) return false;
    final unitId = _unitIdFor(settings);
    if (unitId == null || unitId.isEmpty) return false;
    _rewardedAd?.dispose();
    _rewardedAd = await adLoader.load(unitId);
    return _rewardedAd != null;
  }

  bool get isReady => _rewardedAd != null;

  Future<AdRewardResult> showAndVerify() async {
    final ad = _rewardedAd;
    if (ad == null) {
      return AdRewardResult.failed(
        'Reklam hazır değil. Yeni bir reklam yüklenmesini bekleyin.',
      );
    }
    _rewardedAd = null;

    final settings = _settings;
    if (settings == null) {
      ad.dispose();
      return AdRewardResult.failed('Reklam ayarları yüklenemedi.');
    }

    if (settings.testMode) {
      final presentation = await ad.show();
      if (!presentation.sdkRewardCallbackReceived) {
        return AdRewardResult.failed(
          presentation.errorMessage ?? 'Test reklamı tamamlanmadı.',
        );
      }
      return AdRewardResult.testCompleted(sessionId: 'test');
    }

    RewardSession session;
    try {
      session = await pointsGateway.createRewardSession(
        idempotencyKey: 'mobile:${const Uuid().v4()}',
      );
      await ad.setServerSideCustomData(session.customData!);
    } catch (error) {
      ad.dispose();
      debugPrint('Reward session/SSV options hatası: $error');
      return AdRewardResult.failed(
        'Güvenli doğrulama oturumu açılamadı; reklam gösterilmedi.',
      );
    }

    final presentation = await ad.show();
    if (!presentation.sdkRewardCallbackReceived) {
      return AdRewardResult.failed(
        presentation.errorMessage ?? 'Reklam tamamlanmadı; puan verilmedi.',
        sessionId: session.id,
      );
    }

    final outcome = await verificationPoller.waitForTerminal(
      rewardSessionId: session.id,
    );
    return switch (outcome.state) {
      RewardVerificationState.credited when outcome.creditedPoints != null =>
        AdRewardResult.credited(
          sessionId: session.id,
          points: outcome.creditedPoints!,
        ),
      RewardVerificationState.duplicate => AdRewardResult.duplicate(
        sessionId: session.id,
        points: outcome.creditedPoints,
      ),
      RewardVerificationState.rejected => AdRewardResult.rejected(
        session.id,
        'Reklam sunucu doğrulamasından geçmedi; puan verilmedi.',
      ),
      RewardVerificationState.expired => AdRewardResult.rejected(
        session.id,
        'Doğrulama oturumunun süresi doldu; puan verilmedi.',
      ),
      _ => AdRewardResult.pending(session.id),
    };
  }

  /// Geçici uyumluluk adı; davranış artık claim değil SSV doğrulamasıdır.
  Future<AdRewardResult> showAndClaim() => showAndVerify();

  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
  }
}
