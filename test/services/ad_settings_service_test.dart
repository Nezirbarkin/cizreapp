import 'package:cizreapp/core/models/ad_settings_model.dart';
import 'package:cizreapp/core/services/ad_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

RewardPointsConfigUpdate buildUpdate({
  bool testMode = false,
  RewardFeatureMode mode = RewardFeatureMode.enabled,
  String? appAndroid = 'ca-app-pub-1234567890123456~1234567890',
  String? appIos = 'ca-app-pub-1234567890123456~0987654321',
  String? unitAndroid = 'ca-app-pub-1234567890123456/1234567890',
  String? unitIos = 'ca-app-pub-1234567890123456/0987654321',
}) {
  return RewardPointsConfigUpdate(
    rewardMinPoints: 10,
    rewardMaxPoints: 10,
    maxDailyRewardPoints: 500000,
    pointsPerTry: 100,
    testMode: testMode,
    admobAppIdAndroid: appAndroid,
    admobAppIdIos: appIos,
    admobRewardedUnitIdAndroid: unitAndroid,
    admobRewardedUnitIdIos: unitIos,
    featureMode: mode,
    earnEnabled: false,
    ssvEnabled: true,
    spendEnabled: true,
    eligibleProductsEnabled: true,
    adminReportingEnabled: true,
    maxViewsPerDay: 10,
    maxViewsPerHour: 3,
    cooldownSeconds: 60,
    reason: 'AdMob ayarları güncellendi',
  );
}

void main() {
  test('AdMob alanlarını RPC parametrelerine normalize eder', () {
    final params = buildUpdate().toRpcParams();

    expect(params['p_admob_app_id_android'], contains('~'));
    expect(params['p_admob_rewarded_unit_id_android'], contains('/'));
    expect(params['p_points_per_try'], 100);
  });

  test('gerçek enabled modda iki rewarded unit zorunludur', () {
    final update = buildUpdate(unitIos: '');

    expect(update.validate(), contains('Android ve iOS Rewarded Unit ID'));
  });

  test('test modunda boş gerçek reklam birimleri kabul edilir', () {
    final update = buildUpdate(testMode: true, unitAndroid: '', unitIos: '');

    expect(update.validate(), isNull);
    expect(update.toRpcParams()['p_admob_rewarded_unit_id_android'], isNull);
  });

  test('hatalı AdMob kimlik biçimini reddeder', () {
    final update = buildUpdate(appAndroid: 'yanlis-app-id');

    expect(update.validate(), contains('App ID biçimi geçersiz'));
  });
}
