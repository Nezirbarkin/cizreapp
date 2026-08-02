import 'package:cizreapp/core/models/reward_points_model.dart';
import 'package:cizreapp/core/models/reward_session_model.dart';
import 'package:cizreapp/core/services/reward_points_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements RewardPointsGateway {
  final List<Object?> answers;
  var index = 0;

  _FakeGateway(this.answers);

  @override
  Future<RewardSession?> getRewardSession(String rewardSessionId) async {
    final answer =
        answers[index < answers.length ? index++ : answers.length - 1];
    if (answer is Exception) throw answer;
    return answer as RewardSession?;
  }

  @override
  Future<RewardSession> createRewardSession({required String idempotencyKey}) =>
      throw UnimplementedError();

  @override
  Future<UserPointAccount?> getMyAccount() => throw UnimplementedError();

  @override
  Future<List<PointLedgerEntry>> getMyLedger({int limit = 50}) =>
      throw UnimplementedError();
}

RewardSession _session(RewardSessionStatus status, {int? points}) =>
    RewardSession(
      id: 'session-1',
      status: status,
      creditedPoints: points,
      expiresAt: DateTime.utc(2026, 7, 30),
      policyVersion: 1,
    );

void main() {
  test('pending durumdan credited durumuna polling yapar', () async {
    final gateway = _FakeGateway([
      _session(RewardSessionStatus.pendingSsv),
      _session(RewardSessionStatus.credited, points: 25),
    ]);
    final poller = RewardVerificationPoller(
      gateway: gateway,
      delay: (_) async {},
    );

    final result = await poller.waitForTerminal(
      rewardSessionId: 'session-1',
      maxAttempts: 2,
    );

    expect(result.state, RewardVerificationState.credited);
    expect(result.creditedPoints, 25);
  });

  test('ağ hatası ve timeout ekonomik başarı sayılmaz', () async {
    final gateway = _FakeGateway([Exception('network')]);
    final poller = RewardVerificationPoller(
      gateway: gateway,
      delay: (_) async {},
    );

    final result = await poller.waitForTerminal(
      rewardSessionId: 'session-1',
      maxAttempts: 2,
    );

    expect(result.state, RewardVerificationState.pending);
    expect(result.creditedPoints, isNull);
  });

  test('duplicate ayrı terminal durumudur', () async {
    final poller = RewardVerificationPoller(
      gateway: _FakeGateway([_session(RewardSessionStatus.duplicate)]),
      delay: (_) async {},
    );

    final result = await poller.waitForTerminal(
      rewardSessionId: 'session-1',
      maxAttempts: 1,
    );

    expect(result.state, RewardVerificationState.duplicate);
  });
}
