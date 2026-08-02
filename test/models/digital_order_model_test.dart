// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/digital_order_model.dart';

void main() {
  group('DigitalOrder Model Tests', () {
    group('DigitalOrderStatus', () {
      test('should have correct label for all statuses', () {
        expect(DigitalOrderStatus.pending.label, equals('Bekliyor'));
        expect(DigitalOrderStatus.inProgress.label, equals('İşlemde'));
        expect(DigitalOrderStatus.completed.label, equals('Tamamlandı'));
        expect(DigitalOrderStatus.partial.label, equals('Kısmi Tamamlandı'));
        expect(DigitalOrderStatus.canceled.label, equals('İptal Edildi'));
        expect(DigitalOrderStatus.refunded.label, equals('İade Edildi'));
        expect(DigitalOrderStatus.failed.label, equals('Başarısız'));
      });

      test('should have correct dbValue for all statuses', () {
        expect(DigitalOrderStatus.pending.dbValue, equals('pending'));
        expect(DigitalOrderStatus.inProgress.dbValue, equals('in_progress'));
        expect(DigitalOrderStatus.completed.dbValue, equals('completed'));
        expect(DigitalOrderStatus.partial.dbValue, equals('partial'));
        expect(DigitalOrderStatus.canceled.dbValue, equals('canceled'));
        expect(DigitalOrderStatus.refunded.dbValue, equals('refunded'));
        expect(DigitalOrderStatus.failed.dbValue, equals('failed'));
      });

      test('should parse fromDbValue correctly', () {
        expect(
          DigitalOrderStatus.fromDbValue('pending'),
          equals(DigitalOrderStatus.pending),
        );
        expect(
          DigitalOrderStatus.fromDbValue('in_progress'),
          equals(DigitalOrderStatus.inProgress),
        );
        expect(
          DigitalOrderStatus.fromDbValue('completed'),
          equals(DigitalOrderStatus.completed),
        );
        expect(
          DigitalOrderStatus.fromDbValue('partial'),
          equals(DigitalOrderStatus.partial),
        );
        expect(
          DigitalOrderStatus.fromDbValue('canceled'),
          equals(DigitalOrderStatus.canceled),
        );
        expect(
          DigitalOrderStatus.fromDbValue('refunded'),
          equals(DigitalOrderStatus.refunded),
        );
        expect(
          DigitalOrderStatus.fromDbValue('failed'),
          equals(DigitalOrderStatus.failed),
        );
      });

      test('should default to pending for invalid status', () {
        expect(
          DigitalOrderStatus.fromDbValue('invalid'),
          equals(DigitalOrderStatus.pending),
        );
        expect(
          DigitalOrderStatus.fromDbValue(''),
          equals(DigitalOrderStatus.pending),
        );
      });

      test('dbValue and fromDbValue should round-trip for every status', () {
        for (final status in DigitalOrderStatus.values) {
          expect(
            DigitalOrderStatus.fromDbValue(status.dbValue),
            equals(status),
          );
        }
      });
    });

    group('DigitalOrder.fromJson', () {
      final baseJson = {
        'id': 'order-1',
        'user_id': 'user-1',
        'product_id': 'product-1',
        'provider_id': 'provider-1',
        'target_url': 'https://instagram.com/p/abc',
        'quantity': 1000,
        'unit_price': 0.05,
        'total_price': 50.0,
        'status': 'in_progress',
        'created_at': '2026-07-10T12:00:00.000Z',
      };

      test('should parse required fields correctly', () {
        final order = DigitalOrder.fromJson(baseJson);
        expect(order.id, equals('order-1'));
        expect(order.userId, equals('user-1'));
        expect(order.productId, equals('product-1'));
        expect(order.providerId, equals('provider-1'));
        expect(order.targetUrl, equals('https://instagram.com/p/abc'));
        expect(order.quantity, equals(1000));
        expect(order.unitPrice, equals(0.05));
        expect(order.totalPrice, equals(50.0));
        expect(order.status, equals(DigitalOrderStatus.inProgress));
        expect(order.externalOrderId, isNull);
        expect(order.startCount, isNull);
        expect(order.remains, isNull);
        expect(order.lastCheckedAt, isNull);
        expect(order.productName, isNull);
      });

      test('should parse optional fields when present', () {
        final json = {
          ...baseJson,
          'external_order_id': 'ext-123',
          'start_count': 100,
          'remains': 50,
          'last_checked_at': '2026-07-10T12:05:00.000Z',
          'error_message': 'bir hata',
          'products': {'name': 'Instagram Takipçi'},
        };
        final order = DigitalOrder.fromJson(json);
        expect(order.externalOrderId, equals('ext-123'));
        expect(order.startCount, equals(100));
        expect(order.remains, equals(50));
        expect(
          order.lastCheckedAt,
          equals(DateTime.parse('2026-07-10T12:05:00.000Z')),
        );
        expect(order.errorMessage, equals('bir hata'));
        expect(order.productName, equals('Instagram Takipçi'));
      });
    });
  });
}
