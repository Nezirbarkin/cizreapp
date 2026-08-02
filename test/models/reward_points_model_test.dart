import 'package:cizreapp/core/models/reward_points_model.dart';
import 'package:cizreapp/core/models/reward_session_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('puan hesabı integer değerlerle parse edilir', () {
    final account = UserPointAccount.fromJson({
      'user_id': 'user-1',
      'balance_points': 125,
      'lifetime_earned_points': 200,
      'lifetime_spent_points': 100,
      'lifetime_refunded_points': 25,
      'version': 4,
      'created_at': '2026-07-30T00:00:00Z',
      'updated_at': '2026-07-30T01:00:00Z',
    });

    expect(account.balancePoints, 125);
    expect(account.lifetimeRefundedPoints, 25);
  });

  test('ledger işareti TL sembolü içermeden puan gösterir', () {
    final entry = PointLedgerEntry.fromJson({
      'id': 'entry-1',
      'user_id': 'user-1',
      'entry_type': 'digital_order_refund',
      'direction': 'credit',
      'points': 30,
      'balance_before_points': 10,
      'balance_after_points': 40,
      'reference_type': 'digital_order',
      'reference_id': 'order-1',
      'created_at': '2026-07-30T00:00:00Z',
    });

    expect(entry.signedPointsLabel, '+30 puan');
    expect(entry.signedPointsLabel, isNot(contains('₺')));
    expect(entry.entryType, PointLedgerEntryType.digitalOrderRefund);
  });

  test('reward session custom data ve terminal durumunu parse eder', () {
    final session = RewardSession.fromJson({
      'reward_session_id': 'session-1',
      'custom_data': 'opaque-token',
      'status': 'credited',
      'credited_points': 42,
      'expires_at': '2026-07-30T00:10:00Z',
      'policy_version': 2,
      'environment': 'production',
    });

    expect(session.status, RewardSessionStatus.credited);
    expect(session.status.isTerminal, true);
    expect(session.creditedPoints, 42);
    expect(session.customData, 'opaque-token');
  });
}
