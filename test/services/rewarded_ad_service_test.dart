import 'package:cizreapp/core/models/ad_settings_model.dart';
import 'package:cizreapp/core/models/reward_points_model.dart';
import 'package:cizreapp/core/models/reward_session_model.dart';
import 'package:cizreapp/core/services/ad_settings_service.dart';
import 'package:cizreapp/core/services/reward_points_service.dart';
import 'package:cizreapp/core/services/rewarded_ad_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _StaticSettingsService extends AdSettingsService {
  final AdSettings? settings;

  _StaticSettingsService(this.settings);

  @override
  Future<AdSettings?> getSettings() async => settings;
}

class _Gateway implements RewardPointsGateway {
  @override
  Future<RewardSession> createRewardSession({required String idempotencyKey}) =>
      throw UnimplementedError();

  @override
  Future<UserPointAccount?> getMyAccount() async => null;

  @override
  Future<List<PointLedgerEntry>> getMyLedger({int limit = 50}) async =>
      const [];

  @override
  Future<RewardSession?> getRewardSession(String rewardSessionId) async => null;
}

class _RecordingLoader implements RewardedAdLoader {
  final List<String> requestedUnitIds = [];

  @override
  Future<RewardedAdHandle?> load(String adUnitId) async {
    requestedUnitIds.add(adUnitId);
    return null;
  }
}

RewardedAdService _buildService({
  required AdSettings settings,
  required _RecordingLoader loader,
}) {
  final gateway = _Gateway();
  return RewardedAdService(
    settingsService: _StaticSettingsService(settings),
    pointsGateway: gateway,
    adLoader: loader,
    verificationPoller: RewardVerificationPoller(
      gateway: gateway,
      delay: (_) async {},
    ),
  );
}

const productionSettings = AdSettings(
  testMode: false,
  admobRewardedUnitIdAndroid: 'ca-app-pub-1234567890123456/1234567890',
  admobRewardedUnitIdIos: 'ca-app-pub-1234567890123456/0987654321',
  rewardMinPoints: 10,
  rewardMaxPoints: 10,
  pointsPerTry: 100,
  rewardFeatureMode: RewardFeatureMode.enabled,
  rewardPointsSchemaReady: true,
  rewardPointsEarnEnabled: true,
  rewardPointsSsvRequired: true,
  rewardPointsSsvEnabled: true,
  legacyAdTlGrantDisabled: true,
);

void main() {
  test('üretimde mevcut platformun public config unit ID değerini seçer', () {
    final loader = _RecordingLoader();
    final service = _buildService(settings: productionSettings, loader: loader);

    final unitId = service.resolveUnitId(productionSettings);

    expect(
      unitId,
      anyOf(
        productionSettings.admobRewardedUnitIdAndroid,
        productionSettings.admobRewardedUnitIdIos,
      ),
    );
  });

  test('test modunda gerçek birimleri yok sayıp resmi test birimini seçer', () {
    final loader = _RecordingLoader();
    final service = _buildService(
      settings: productionSettings.copyWith(testMode: true),
      loader: loader,
    );

    final unitId = service.resolveUnitId(
      productionSettings.copyWith(testMode: true),
    );

    expect(
      unitId,
      anyOf(
        AdSettings.testRewardedUnitIdAndroid,
        AdSettings.testRewardedUnitIdIos,
      ),
    );
  });

  test('public config unit ID varsa preload bunu loadera aktarır', () async {
    final loader = _RecordingLoader();
    final service = _buildService(settings: productionSettings, loader: loader);

    expect(await service.loadSettings(), isNotNull);
    expect(await service.preload(), isFalse);
    expect(loader.requestedUnitIds, hasLength(1));
    expect(
      loader.requestedUnitIds.single,
      anyOf(
        productionSettings.admobRewardedUnitIdAndroid,
        productionSettings.admobRewardedUnitIdIos,
      ),
    );
  });

  test('ekonomik feature kapalıyken loader çağrılmaz', () async {
    final loader = _RecordingLoader();
    final service = _buildService(
      settings: productionSettings.copyWith(
        rewardFeatureMode: RewardFeatureMode.disabled,
      ),
      loader: loader,
    );

    expect(await service.loadSettings(), isNull);
    expect(await service.preload(), isFalse);
    expect(loader.requestedUnitIds, isEmpty);
  });

  group('yükleme hatası kaydı', () {
    const unit = 'ca-app-pub-1234567890123456/1234567890';
    late List<Map<String, dynamic>> written;
    late Future<void> Function(Map<String, dynamic>) originalWriter;

    setUp(() {
      written = [];
      originalWriter = RewardedAdLoadFailureLog.writer;
      RewardedAdLoadFailureLog.resetForTest();
      RewardedAdLoadFailureLog.writer = (metadata) async {
        written.add(metadata);
      };
    });

    tearDown(() {
      RewardedAdLoadFailureLog.writer = originalWriter;
      RewardedAdLoadFailureLog.resetForTest();
    });

    void record({
      int code = 3,
      String message = 'Account not approved yet.',
      String? responseId,
    }) {
      RewardedAdLoadFailureLog.record(
        platform: 'android',
        adUnitId: unit,
        code: code,
        domain: 'com.google.android.gms.ads',
        message: message,
        responseId: responseId,
      );
    }

    test('kodu, mesajı ve birimi admin kartlarının okuduğu biçimde yazar', () {
      record(responseId: 'abc123');

      expect(written, hasLength(1));
      final metadata = written.single;
      expect(metadata['type'], RewardedAdLoadFailureLog.errorType);
      expect(metadata['details'], contains('kod 3'));
      expect(metadata['details'], contains('Account not approved yet.'));
      expect(metadata['details'], contains(unit));
      expect(metadata['origin'], isNotEmpty);
      expect(metadata['ad_error_code'], 3);
      expect(metadata['ad_error_domain'], 'com.google.android.gms.ads');
      expect(metadata['ad_unit_id'], unit);
      expect(metadata['ad_response_id'], 'abc123');
    });

    test('response id yoksa o anahtar hiç eklenmez', () {
      record();

      expect(written.single.containsKey('ad_response_id'), isFalse);
    });

    test('aynı hata aynı çalışmada bir kez yazılır, farklı hata yazılır', () {
      record();
      record();
      expect(written, hasLength(1));

      record(code: 2, message: 'Network error');
      expect(written, hasLength(2));
    });

    test('çok uzun mesaj kesilir', () {
      record(message: 'x' * 1000);

      expect(written.single['ad_error_message'], hasLength(300));
    });

    test('yazım patlasa da reklam akışına istisna sızmaz', () async {
      RewardedAdLoadFailureLog.writer = (_) => throw StateError('eşzamanlı');
      expect(record, returnsNormally);

      RewardedAdLoadFailureLog.resetForTest();
      RewardedAdLoadFailureLog.writer = (_) async => throw StateError('async');
      expect(record, returnsNormally);

      // Yutulmayan bir async hata test bölgesini düşürürdü.
      await Future<void>.delayed(Duration.zero);
    });
  });
}
