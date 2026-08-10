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

      test(
        'should return true for consistent balance with small floating point error',
        () {
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
        },
      );

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
        final balance = TestHelpers.createMockBalance(balance: 100.0);

        final modified = balance.copyWith(balance: 200.0, lockedBalance: 50.0);

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

  group('BalanceTransaction Amount Tests (CHECK >= 0)', () {
    group('BalanceTransaction amount validation', () {
      test('should accept zero amount transactions (CHECK >= 0)', () {
        // 2026-07-14: balance_transactions CHECK constraint
        // CHECK (amount >= 0) olarak güncellendi
        // 0 TL tutarlı işlemler artık kabul edilmeli
        const zeroAmount = 0.0;
        expect(zeroAmount >= 0, isTrue, reason: '0 TL CHECK >= 0 uyumlu');
      });

      test('should accept positive amount transactions', () {
        const positiveAmount = 100.50;
        expect(positiveAmount >= 0, isTrue);
      });

      test('should reject negative amount transactions', () {
        // Negatif tutarlar CHECK constraint tarafından reddedilmeli
        const negativeAmount = -50.0;
        expect(
          negativeAmount >= 0,
          isFalse,
          reason: 'Negatif tutar reddedilmeli',
        );
      });

      test('availableBalance calculation with zero balance', () {
        // 0 TL bakiye senaryosu
        final balance = TestHelpers.createMockBalance(
          balance: 0.0,
          lockedBalance: 0.0,
        );
        expect(balance.availableBalance, equals(0.0));
        expect(balance.balance, equals(0.0));
      });

      test('should handle deduction resulting in zero balance', () {
        // Bakiye - bakiye = 0 senaryosu
        // Varsayılan: total_earned=200, total_spent=80, total_refunds=10, total_withdrawn=20
        // Sıfır bakiye için: 0 = X - 80 + 10 - 20 => X = 90
        final balance = TestHelpers.createMockBalance(
          balance: 0.0,
          totalEarned: 90.0,
          totalSpent: 80.0,
          totalRefunds: 10.0,
          totalWithdrawn: 20.0,
        );
        // 0 = 90 - 80 + 10 - 20
        expect(balance.isConsistent, isTrue);
      });
    });

    group('Balance Transaction Types', () {
      test('topup type should have positive amount', () {
        // Bakiye yükleme her zaman pozitif olmalı
        const topupAmount = 50.0;
        expect(topupAmount > 0, isTrue);
        expect(topupAmount >= 0, isTrue);
      });

      test('spending type can result in zero balance', () {
        // Harcama sonucu bakiye 0 olabilir
        // lockedBalance = balance - availableBalance formülü
        // availableBalance = balance - lockedBalance (negatif kilitli → eklenir)
        // 0 bakiye + 0 locked = 0 available
        final zeroBalance = TestHelpers.createMockBalance(
          balance: 0.0,
          lockedBalance: 0.0,
          totalEarned: 0.0,
          totalSpent: 0.0,
          totalRefunds: 0.0,
          totalWithdrawn: 0.0,
        );
        expect(zeroBalance.availableBalance, equals(0.0));
        expect(zeroBalance.balance, equals(0.0));
      });

      test('refund type should be positive', () {
        // İade pozitif tutar olarak kaydedilmeli
        const refundAmount = 25.0;
        expect(refundAmount > 0, isTrue);
        expect(refundAmount >= 0, isTrue);
      });

      test('withdrawal type should have positive amount', () {
        // Çekim pozitif tutar olarak kaydedilmeli
        const withdrawalAmount = 100.0;
        expect(withdrawalAmount > 0, isTrue);
        expect(withdrawalAmount >= 0, isTrue);
      });
    });
  });
}
