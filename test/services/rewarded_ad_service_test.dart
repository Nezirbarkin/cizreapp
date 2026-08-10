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
  final RewardedAdHandle? result;

  _RecordingLoader({this.result});

  @override
  Future<RewardedAdHandle?> load(String adUnitId) async {
    requestedUnitIds.add(adUnitId);
    return result;
  }
}

RewardedAdService buildService({
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
    final service = buildService(settings: productionSettings, loader: loader);

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
    final service = buildService(
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
    final service = buildService(settings: productionSettings, loader: loader);

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
    final service = buildService(
      settings: productionSettings.copyWith(
        rewardFeatureMode: RewardFeatureMode.disabled,
      ),
      loader: loader,
    );

    expect(await service.loadSettings(), isNull);
    expect(await service.preload(), isFalse);
    expect(loader.requestedUnitIds, isEmpty);
  });
}
