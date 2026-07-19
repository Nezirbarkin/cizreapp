import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/models/ad_settings_model.dart';

void main() {
  group('AdSettings.fromJson', () {
    test('tüm alanları doğru şekilde parse eder', () {
      final json = {
        'is_enabled': true,
        'test_mode': false,
        'admob_app_id_android': 'ca-app-pub-111~222',
        'admob_app_id_ios': 'ca-app-pub-111~333',
        'admob_rewarded_unit_id_android': 'ca-app-pub-111/444',
        'admob_rewarded_unit_id_ios': 'ca-app-pub-111/555',
        'reward_min_try': 0.5,
        'reward_max_try': 10.0,
        'max_views_per_day': 10,
        'max_views_per_hour': 3,
        'min_watch_seconds': 15,
        'cooldown_seconds': 60,
        'max_daily_payout_try': 5000.0,
      };

      final settings = AdSettings.fromJson(json);

      expect(settings.isEnabled, true);
      expect(settings.testMode, false);
      expect(settings.admobRewardedUnitIdAndroid, 'ca-app-pub-111/444');
      expect(settings.rewardMinTry, 0.5);
      expect(settings.rewardMaxTry, 10.0);
      expect(settings.maxViewsPerDay, 10);
      expect(settings.maxViewsPerHour, 3);
      expect(settings.minWatchSeconds, 15);
      expect(settings.cooldownSeconds, 60);
      expect(settings.maxDailyPayoutTry, 5000.0);
    });

    test('eksik/null alanlar için güvenli varsayılanlar kullanır', () {
      final settings = AdSettings.fromJson({});

      expect(settings.isEnabled, false);
      expect(settings.testMode, true);
      expect(settings.admobAppIdAndroid, isNull);
      expect(settings.rewardMinTry, 0);
      expect(settings.rewardMaxTry, 0);
      expect(settings.maxViewsPerDay, 0);
    });

    test('int değerleri num olarak gelse de doğru parse edilir', () {
      final settings = AdSettings.fromJson({
        'reward_min_try': 1,
        'max_views_per_day': 5.0,
      });

      expect(settings.rewardMinTry, 1.0);
      expect(settings.maxViewsPerDay, 5);
    });
  });

  group('AdSettings.toJson', () {
    test('toJson -> fromJson round-trip aynı değerleri korur', () {
      final original = AdSettings(
        isEnabled: true,
        testMode: false,
        admobAppIdAndroid: 'app-android',
        admobAppIdIos: 'app-ios',
        admobRewardedUnitIdAndroid: 'unit-android',
        admobRewardedUnitIdIos: 'unit-ios',
        rewardMinTry: 0.5,
        rewardMaxTry: 1.25,
        maxViewsPerDay: 8,
        maxViewsPerHour: 2,
        minWatchSeconds: 20,
        cooldownSeconds: 90,
        maxDailyPayoutTry: 3000,
      );

      final restored = AdSettings.fromJson(original.toJson());

      expect(restored.isEnabled, original.isEnabled);
      expect(restored.admobRewardedUnitIdAndroid, original.admobRewardedUnitIdAndroid);
      expect(restored.rewardMinTry, original.rewardMinTry);
      expect(restored.rewardMaxTry, original.rewardMaxTry);
      expect(restored.maxViewsPerDay, original.maxViewsPerDay);
    });
  });

  group('AdSettings.copyWith', () {
    test('sadece belirtilen alanları değiştirir', () {
      final original = AdSettings(
        isEnabled: false,
        testMode: true,
        rewardMinTry: 0.5,
        rewardMaxTry: 10,
        maxViewsPerDay: 10,
        maxViewsPerHour: 3,
        minWatchSeconds: 15,
        cooldownSeconds: 60,
        maxDailyPayoutTry: 5000,
      );

      final updated = original.copyWith(isEnabled: true, rewardMaxTry: 20.0);

      expect(updated.isEnabled, true);
      expect(updated.rewardMaxTry, 20.0);
      // Değiştirilmeyen alanlar aynı kalmalı
      expect(updated.rewardMinTry, original.rewardMinTry);
      expect(updated.testMode, original.testMode);
      expect(updated.maxViewsPerDay, original.maxViewsPerDay);
    });
  });

  group('Test reklam birim ID sabitleri', () {
    test('Google resmi test ID formatına uygun', () {
      expect(AdSettings.testRewardedUnitIdAndroid, startsWith('ca-app-pub-3940256099942544/'));
      expect(AdSettings.testRewardedUnitIdIos, startsWith('ca-app-pub-3940256099942544/'));
    });
  });
}
