// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/balance_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('UserBalance Model Tests', () {
    group('UserBalance.fromJson', () {
      test('should create UserBalance from valid JSON', () {
        final json = TestHelpers.createMockBalanceJson(
          id: 'balance-123',
          userId: 'user-123',
          balance: 100.0,
          lockedBalance: 10.0,
          totalEarned: 200.0,
          totalSpent: 80.0,
          totalRefunds: 10.0,
          totalWithdrawn: 20.0,
        );

        final balance = UserBalance.fromJson(json);

        expect(balance.id, equals('balance-123'));
        expect(balance.userId, equals('user-123'));
        expect(balance.balance, equals(100.0));
        expect(balance.lockedBalance, equals(10.0));
        expect(balance.totalEarned, equals(200.0));
        expect(balance.totalSpent, equals(80.0));
        expect(balance.totalRefunds, equals(10.0));
        expect(balance.totalWithdrawn, equals(20.0));
      });

      test('should use default values for missing fields', () {
        final json = {
          'id': 'balance-123',
          'user_id': 'user-123',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        };

        final balance = UserBalance.fromJson(json);

        expect(balance.balance, equals(0));
        expect(balance.lockedBalance, equals(0));
        expect(balance.totalEarned, equals(0));
        expect(balance.totalSpent, equals(0));
        expect(balance.totalRefunds, equals(0));
        expect(balance.totalWithdrawn, equals(0));
      });

      test('should handle null values in JSON', () {
        // Model default değerleri kullanır, null olan alanlar 0 olur
        final json = {
          'id': 'balance-123',
          'user_id': 'user-123',
          'balance': null,
          'locked_balance': null,
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        };

        final balance = UserBalance.fromJson(json);

        expect(balance.balance, equals(0));
        expect(balance.lockedBalance, equals(0));
      });

      test('should convert integer to double', () {
        final json = TestHelpers.createMockBalanceJson(
          balance: 100,
          totalEarned: 200,
        );

        final balance = UserBalance.fromJson(json);

        expect(balance.balance, equals(100.0));
        expect(balance.totalEarned, equals(200.0));
        expect(balance.balance, isA<double>());
      });
    });

    group('UserBalance.toJson', () {
      test('should convert UserBalance to JSON correctly', () {
        final balance = TestHelpers.createMockBalance(
          id: 'balance-123',
          userId: 'user-123',
          balance: 100.0,
        );

        final json = balance.toJson();

        expect(json['id'], equals('balance-123'));
        expect(json['user_id'], equals('user-123'));
        expect(json['balance'], equals(100.0));
        expect(json['locked_balance'], equals(10.0));
        expect(json['total_earned'], equals(200.0));
      });
    });

    group('UserBalance.availableBalance', () {
      test('should calculate available balance correctly', () {
        final balance = TestHelpers.createMockBalance(
          balance: 100.0,
          lockedBalance: 25.0,
        );

        expect(balance.availableBalance, equals(75.0));
      });

      test('should return full balance when nothing locked', () {
        final balance = TestHelpers.createMockBalance(
          balance: 100.0,
          lockedBalance: 0.0,
        );

        expect(balance.availableBalance, equals(100.0));
      });

      test('should handle negative locked balance', () {
        final balance = TestHelpers.createMockBalance(
          balance: 100.0,
          lockedBalance: -10.0,
        );

        // Negatif kilitli bakiye toplam + |-negatif| olur
        expect(balance.availableBalance, equals(110.0));
      });
    });

    group('UserBalance.isConsistent', () {
      test('should return true for consistent balance', () {
        // bakiye = yüklenen - harcanan + iade - çekilen
        // 100 = 200 - 80 + 10 - 30
        final balance = TestHelpers.createMockBalance(
          balance: 100.0,
          totalEarned: 200.0,
          totalSpent: 80.0,
          totalRefunds: 10.0,
          totalWithdrawn: 30.0,
        );

        expect(balance.isConsistent, isTrue);
      });

      test('should return true for consistent balance with small floating point error', () {
        // Küçük yuvarlama hataları tolere edilmeli (< 0.01 tolerans)
        final balance = TestHelpers.createMockBalance(
          balance: 100.005,
          totalEarned: 200.0,
          totalSpent: 80.0,
          totalRefunds: 10.0,
          totalWithdrawn: 30.0,
        );

        // 100.005 - (200 - 80 + 10 - 30) = 100.005 - 100 = 0.005 < 0.01
        expect(balance.isConsistent, isTrue);
      });

      test('should return false for inconsistent balance', () {
        // 50 != 200 - 80 + 10 - 30 = 100
        final balance = TestHelpers.createMockBalance(
          balance: 50.0,
          totalEarned: 200.0,
          totalSpent: 80.0,
          totalRefunds: 10.0,
          totalWithdrawn: 30.0,
        );

        expect(balance.isConsistent, isFalse);
      });
    });

    group('UserBalance.copyWith', () {
      test('should create copy with modified fields', () {
        final balance = TestHelpers.createMockBalance(
          balance: 100.0,
        );

        final modified = balance.copyWith(
          balance: 200.0,
          lockedBalance: 50.0,
        );

        expect(modified.balance, equals(200.0));
        expect(modified.lockedBalance, equals(50.0));
        expect(modified.id, equals(balance.id));
        expect(modified.userId, equals(balance.userId));
      });
    });
  });

  group('SellerEarningsSummary Model Tests', () {
    group('SellerEarningsSummary.fromJson', () {
      test('should create SellerEarningsSummary from valid JSON', () {
        final json = {
          'total_orders': 10,
          'total_gross': 1000.0,
          'total_commission': 100.0,
          'total_net': 900.0,
          'pending_amount': 50.0,
          'available_amount': 850.0,
          'withdrawn_amount': 0.0,
          'min_withdrawal': 50.0,
          'withdrawal_fee_percent': 2.0,
        };

        final summary = SellerEarningsSummary.fromJson(json);

        expect(summary.totalOrders, equals(10));
        expect(summary.totalGross, equals(1000.0));
        expect(summary.totalCommission, equals(100.0));
        expect(summary.totalNet, equals(900.0));
        expect(summary.pendingAmount, equals(50.0));
        expect(summary.availableAmount, equals(850.0));
        expect(summary.withdrawnAmount, equals(0.0));
        expect(summary.minWithdrawal, equals(50.0));
        expect(summary.withdrawalFeePercent, equals(2.0));
      });

      test('should use default values for missing fields', () {
        final json = <String, dynamic>{};

        final summary = SellerEarningsSummary.fromJson(json);

        expect(summary.totalOrders, equals(0));
        expect(summary.totalGross, equals(0));
        expect(summary.minWithdrawal, equals(50));
        expect(summary.withdrawalFeePercent, equals(2));
      });
    });

    group('SellerEarningsSummary.calculateFee', () {
      test('should calculate fee correctly', () {
        final summary = SellerEarningsSummary(
          totalOrders: 0,
          totalGross: 0,
          totalCommission: 0,
          totalNet: 0,
          pendingAmount: 0,
          availableAmount: 0,
          withdrawnAmount: 0,
          minWithdrawal: 50,
          withdrawalFeePercent: 2,
        );

        expect(summary.calculateFee(100.0), equals(2.0));
        expect(summary.calculateFee(50.0), equals(1.0));
        expect(summary.calculateFee(0.0), equals(0.0));
      });
    });

    group('SellerEarningsSummary.netWithdrawable', () {
      test('should calculate net withdrawable amount correctly', () {
        final summary = SellerEarningsSummary(
          totalOrders: 0,
          totalGross: 0,
          totalCommission: 0,
          totalNet: 0,
          pendingAmount: 0,
          availableAmount: 0,
          withdrawnAmount: 0,
          minWithdrawal: 50,
          withdrawalFeePercent: 2,
        );

        // 100 - (100 * 2 / 100 * 100) = 100 - 2 = 98
        expect(summary.netWithdrawable(100.0), equals(98.0));
      });
    });
  });
}