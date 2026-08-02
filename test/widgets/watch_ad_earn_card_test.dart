import 'package:cizreapp/core/models/ad_settings_model.dart';
import 'package:cizreapp/core/models/reward_points_model.dart';
import 'package:cizreapp/core/models/reward_session_model.dart';
import 'package:cizreapp/core/services/ad_settings_service.dart';
import 'package:cizreapp/core/services/reward_points_service.dart';
import 'package:cizreapp/core/services/rewarded_ad_service.dart';
import 'package:cizreapp/features/wallet/widgets/watch_ad_earn_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoopGateway implements RewardPointsGateway {
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

class _NoopLoader implements RewardedAdLoader {
  @override
  Future<RewardedAdHandle?> load(String adUnitId) async => null;
}

class _StaticSettingsService extends AdSettingsService {
  _StaticSettingsService();

  @override
  Future<AdSettings?> getSettings() async => const AdSettings(
    testMode: false,
    rewardMinPoints: 10,
    rewardMaxPoints: 10,
    pointsPerTry: 100,
    rewardFeatureMode: RewardFeatureMode.enabled,
    rewardPointsSchemaReady: true,
    rewardPointsEarnEnabled: true,
    rewardPointsSsvRequired: true,
    rewardPointsSsvEnabled: true,
    rewardPointsSpendEnabled: true,
    legacyAdTlGrantDisabled: true,
  );
}

void main() {
  testWidgets('puanı para simgesi olmadan ve sınır metniyle gösterir', (
    tester,
  ) async {
    final gateway = _NoopGateway();
    final service = RewardedAdService(
      settingsService: _StaticSettingsService(),
      pointsGateway: gateway,
      adLoader: _NoopLoader(),
      verificationPoller: RewardVerificationPoller(
        gateway: gateway,
        delay: (_) async {},
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WatchAdEarnCard(adService: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Reklam İzle, Puan Kazan'), findsOneWidget);
    expect(
      find.text('10 puan kazan; uygun dijital ürünlerde kullan'),
      findsOneWidget,
    );
    expect(find.textContaining('IBAN'), findsOneWidget);
    expect(find.textContaining('₺'), findsNothing);
  });
}
