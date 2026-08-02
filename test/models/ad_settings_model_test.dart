import 'package:cizreapp/core/models/ad_settings_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdSettings.fromJson', () {
    test('integer puan ve feature flag sözleşmesini parse eder', () {
      final settings = AdSettings.fromJson({
        'reward_min_points': 10,
        'reward_max_points': 10,
        'max_daily_reward_points': 50000,
        'points_per_try': 100,
        'reward_policy_version': 3,
        'reward_feature_mode': 'enabled',
        'reward_points_schema_ready': true,
        'reward_points_earn_enabled': true,
        'reward_points_ssv_required': true,
        'reward_points_ssv_enabled': true,
        'reward_points_spend_enabled': true,
        'reward_points_eligible_products_enabled': true,
        'legacy_ad_tl_grant_disabled': true,
        'admob_rewarded_unit_id_android':
            'ca-app-pub-1234567890123456/1234567890',
        'admob_rewarded_unit_id_ios': 'ca-app-pub-1234567890123456/0987654321',
      });

      expect(settings.rewardMinPoints, 10);
      expect(settings.rewardMaxPoints, 10);
      expect(settings.maxDailyRewardPoints, 50000);
      expect(settings.pointsPerTry, 100);
      expect(settings.rewardPolicyVersion, 3);
      expect(
        settings.admobRewardedUnitIdAndroid,
        'ca-app-pub-1234567890123456/1234567890',
      );
      expect(settings.rewardFeatureMode, RewardFeatureMode.enabled);
      expect(settings.canRequestRewardSession, true);
    });

    test('eski TL ödül alanlarını puana kopyalamaz', () {
      final settings = AdSettings.fromJson({
        'is_enabled': true,
        'reward_min_try': 10,
        'reward_max_try': 99,
        'max_daily_payout_try': 5000,
      });

      expect(settings.rewardMinPoints, 0);
      expect(settings.rewardMaxPoints, 0);
      expect(settings.maxDailyRewardPoints, isNull);
      expect(settings.canRequestRewardSession, false);
    });

    test('num değerlerini integer puan olarak parse eder', () {
      final settings = AdSettings.fromJson({
        'reward_min_points': 10.0,
        'reward_max_points': 50.0,
        'points_per_try': 100.0,
      });

      expect(settings.rewardMinPoints, 10);
      expect(settings.rewardMaxPoints, 50);
      expect(settings.pointsPerTry, 100);
    });
  });

  test('toJson deprecated TL reward alanlarını üretmez', () {
    const settings = AdSettings(
      rewardMinPoints: 10,
      rewardMaxPoints: 10,
      maxDailyRewardPoints: 10000,
      pointsPerTry: 100,
      rewardPolicyVersion: 2,
      rewardFeatureMode: RewardFeatureMode.enabled,
      rewardPointsSchemaReady: true,
      rewardPointsEarnEnabled: true,
      rewardPointsSsvEnabled: true,
    );

    final json = settings.toJson();
    expect(json['reward_min_points'], 10);
    expect(json['reward_max_points'], 10);
    expect(json, isNot(contains('reward_min_try')));
    expect(json, isNot(contains('reward_max_try')));
    expect(json, isNot(contains('max_daily_payout_try')));
  });

  test('copyWith puan alanlarını günceller', () {
    const settings = AdSettings(
      rewardMinPoints: 10,
      rewardMaxPoints: 50,
      pointsPerTry: 100,
    );
    final updated = settings.copyWith(
      rewardMaxPoints: 80,
      rewardFeatureMode: RewardFeatureMode.cohort,
    );

    expect(updated.rewardMinPoints, 10);
    expect(updated.rewardMaxPoints, 80);
    expect(updated.rewardFeatureMode, RewardFeatureMode.cohort);
  });

  test('Google resmi rewarded test ID sabitleri geçerlidir', () {
    expect(
      AdSettings.testRewardedUnitIdAndroid,
      startsWith('ca-app-pub-3940256099942544/'),
    );
    expect(
      AdSettings.testRewardedUnitIdIos,
      startsWith('ca-app-pub-3940256099942544/'),
    );
  });

  test('test modu reklam provası açar, cohort ekonomik oturum açmaz', () {
    const testMode = AdSettings(
      testMode: true,
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
    final cohort = testMode.copyWith(
      testMode: false,
      rewardFeatureMode: RewardFeatureMode.cohort,
    );

    expect(testMode.canRequestRewardSession, true);
    expect(cohort.canRequestRewardSession, false);
  });

  test('test modu puan kazanımı kapalıyken güvenli reklam provası açar', () {
    const settings = AdSettings(
      testMode: true,
      rewardFeatureMode: RewardFeatureMode.enabled,
      rewardPointsSchemaReady: true,
      rewardPointsEarnEnabled: false,
      rewardPointsSsvEnabled: false,
      legacyAdTlGrantDisabled: true,
    );

    expect(settings.canRequestRewardSession, true);
  });
}
