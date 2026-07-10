// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/order_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('Order Model Tests', () {
    group('OrderStatus', () {
      test('should have correct label for all statuses', () {
        expect(OrderStatus.pending.label, equals('Beklemede'));
        expect(OrderStatus.confirmed.label, equals('Onaylandı'));
        expect(OrderStatus.preparing.label, equals('Hazırlanıyor'));
        expect(OrderStatus.ready.label, equals('Hazır'));
        expect(OrderStatus.onTheWay.label, equals('Yolda'));
        expect(OrderStatus.delivered.label, equals('Teslim Edildi'));
        expect(OrderStatus.cancelled.label, equals('İptal Edildi'));
      });

      test('should have correct dbValue for all statuses', () {
        expect(OrderStatus.pending.dbValue, equals('pending'));
        expect(OrderStatus.confirmed.dbValue, equals('confirmed'));
        expect(OrderStatus.preparing.dbValue, equals('preparing'));
        expect(OrderStatus.ready.dbValue, equals('ready'));
        expect(OrderStatus.onTheWay.dbValue, equals('on_the_way'));
        expect(OrderStatus.delivered.dbValue, equals('delivered'));
        expect(OrderStatus.cancelled.dbValue, equals('cancelled'));
      });

      test('should parse fromString correctly', () {
        expect(OrderStatus.fromString('pending'), equals(OrderStatus.pending));
        expect(OrderStatus.fromString('confirmed'), equals(OrderStatus.confirmed));
        expect(OrderStatus.fromString('on_the_way'), equals(OrderStatus.onTheWay));
        expect(OrderStatus.fromString('delivered'), equals(OrderStatus.delivered));
      });

      test('should default to pending for invalid status', () {
        expect(OrderStatus.fromString('invalid'), equals(OrderStatus.pending));
        expect(OrderStatus.fromString(''), equals(OrderStatus.pending));
      });
    });

    group('PaymentMethod', () {
      test('should have correct label for all methods', () {
        expect(PaymentMethod.cash.label, equals('Kapıda Nakit'));
        expect(PaymentMethod.cardOnDelivery.label, equals('Kapıda Kart'));
        expect(PaymentMethod.online.label, equals('Online Ödeme'));
        expect(PaymentMethod.balance.label, equals('Bakiye ile Ödeme'));
      });

      test('should parse fromString correctly', () {
        expect(PaymentMethod.fromString('cash'), equals(PaymentMethod.cash));
        expect(PaymentMethod.fromString('cardOnDelivery'), equals(PaymentMethod.cardOnDelivery));
        expect(PaymentMethod.fromString('online'), equals(PaymentMethod.online));
        expect(PaymentMethod.fromString('balance'), equals(PaymentMethod.balance));
      });

      test('should default to cash for invalid method', () {
        expect(PaymentMethod.fromString('invalid'), equals(PaymentMethod.cash));
      });
    });

    group('CommissionStatus', () {
      test('should have correct label for all statuses', () {
        expect(CommissionStatus.pending.label, equals('Beklemede'));
        expect(CommissionStatus.collected.label, equals('Tahsil Edildi'));
        expect(CommissionStatus.debt.label, equals('Borç'));
        expect(CommissionStatus.waived.label, equals('Affedildi'));
      });

      test('should parse fromString correctly', () {
        expect(CommissionStatus.fromString('pending'), equals(CommissionStatus.pending));
        expect(CommissionStatus.fromString('collected'), equals(CommissionStatus.collected));
        expect(CommissionStatus.fromString('debt'), equals(CommissionStatus.debt));
        expect(CommissionStatus.fromString('waived'), equals(CommissionStatus.waived));
      });
    });

    group('OrderItem', () {
      test('should create OrderItem from JSON correctly', () {
        final json = TestHelpers.createMockOrderItemJson(
          id: 'item-123',
          productId: 'product-123',
          productName: 'Test Product',
          price: 25.0,
          quantity: 3,
        );

        final item = OrderItem.fromJson(json);

        expect(item.id, equals('item-123'));
        expect(item.productId, equals('product-123'));
        expect(item.productName, equals('Test Product'));
        expect(item.price, equals(25.0));
        expect(item.quantity, equals(3));
      });

      test('should calculate subtotal correctly', () {
        final item = OrderItem.fromJson(TestHelpers.createMockOrderItemJson(
          price: 25.0,
          quantity: 4,
        ));

        expect(item.subtotal, equals(100.0));
      });

      test('should use default values for missing fields', () {
        final json = {
          'created_at': '2024-01-01T00:00:00.000Z',
        };

        final item = OrderItem.fromJson(json);

        expect(item.id, equals(''));
        expect(item.price, equals(0.0));
        expect(item.quantity, equals(0));
      });
    });

    group('Order.fromJson', () {
      test('should create Order from valid JSON', () {
        final json = TestHelpers.createMockOrderJson(
          id: 'order-123',
          userId: 'user-123',
          shopId: 'shop-123',
          subtotal: 100.0,
          deliveryFee: 15.0,
          totalAmount: 115.0,
        );

        final order = Order.fromJson(json);

        expect(order.id, equals('order-123'));
        expect(order.userId, equals('user-123'));
        expect(order.shopId, equals('shop-123'));
        expect(order.subtotal, equals(100.0));
        expect(order.deliveryFee, equals(15.0));
        expect(order.totalAmount, equals(115.0));
        expect(order.status, equals(OrderStatus.pending));
        expect(order.paymentMethod, equals(PaymentMethod.cash));
      });

      test('should parse order items correctly', () {
        final json = TestHelpers.createMockOrderJson(
          items: [
            TestHelpers.createMockOrderItemJson(price: 25.0, quantity: 2),
            TestHelpers.createMockOrderItemJson(price: 50.0, quantity: 1),
          ],
        );

        final order = Order.fromJson(json);

        expect(order.items.length, equals(2));
        expect(order.items[0].price, equals(25.0));
        expect(order.items[1].price, equals(50.0));
      });

      test('should parse all order statuses correctly', () {
        for (final status in OrderStatus.values) {
          final json = TestHelpers.createMockOrderJson(status: status.name);
          final order = Order.fromJson(json);
          expect(order.status, equals(status), reason: 'Status: ${status.name}');
        }
      });

      test('should support both subtotal and total field names', () {
        final jsonWithTotal = {
          'id': 'order-123',
          'user_id': 'user-123',
          'shop_id': 'shop-123',
          'total': 100.0,
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        };

        final order = Order.fromJson(jsonWithTotal);
        expect(order.totalAmount, equals(100.0));
      });
    });

    group('Order.toJson', () {
      test('should convert Order to JSON correctly', () {
        final order = TestHelpers.createMockOrder(
          id: 'order-123',
          status: OrderStatus.confirmed,
          paymentMethod: PaymentMethod.online,
        );

        final json = order.toJson();

        expect(json['id'], equals('order-123'));
        expect(json['status'], equals('confirmed'));
        expect(json['payment_method'], equals('online'));
      });

      test('should use correct dbValue for on_the_way status', () {
        final order = TestHelpers.createMockOrder(
          status: OrderStatus.onTheWay,
        );

        final json = order.toJson();

        expect(json['status'], equals('on_the_way'));
      });
    });

    group('Order helper properties', () {
      test('isCompleted should return true for delivered orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.delivered);
        expect(order.isCompleted, isTrue);
      });

      test('isCompleted should return false for non-delivered orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.pending);
        expect(order.isCompleted, isFalse);
      });

      test('isCancelled should return true for cancelled orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.cancelled);
        expect(order.isCancelled, isTrue);
      });

      test('isActive should return true for pending orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.pending);
        expect(order.isActive, isTrue);
      });

      test('isActive should return false for completed orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.delivered);
        expect(order.isActive, isFalse);
      });

      test('isActive should return false for cancelled orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.cancelled);
        expect(order.isActive, isFalse);
      });

      test('isPaid should return true for balance payment', () {
        final order = TestHelpers.createMockOrder(paymentMethod: PaymentMethod.balance);
        expect(order.isPaid, isTrue);
      });

      test('isPaid should return true for online payment', () {
        final order = TestHelpers.createMockOrder(paymentMethod: PaymentMethod.online);
        expect(order.isPaid, isTrue);
      });

      test('isPaid should return false for cash payment without completion', () {
        final order = TestHelpers.createMockOrder(paymentMethod: PaymentMethod.cash);
        expect(order.isPaid, isFalse);
      });

      test('canCancel should return true for pending orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.pending);
        expect(order.canCancel, isTrue);
      });

      test('canCancel should return true for confirmed orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.confirmed);
        expect(order.canCancel, isTrue);
      });

      test('canCancel should return false for preparing orders', () {
        final order = TestHelpers.createMockOrder(status: OrderStatus.preparing);
        expect(order.canCancel, isFalse);
      });

      test('hasDebt should return true when commissionDebt > 0', () {
        final order = Order.fromJson({
          ...TestHelpers.createMockOrderJson(),
          'commission_debt': 50.0,
        });
        expect(order.hasDebt, isTrue);
      });

      test('hasDebt should return false when commissionDebt is null', () {
        final order = TestHelpers.createMockOrder();
        expect(order.hasDebt, isFalse);
      });

      test('totalAdminEarnings should calculate correctly', () {
        final order = Order.fromJson({
          ...TestHelpers.createMockOrderJson(),
          'admin_commission': 10.0,
          'admin_delivery_fee': 5.0,
        });
        expect(order.totalAdminEarnings, equals(15.0));
      });

      test('formattedDate should return correct format', () {
        final order = TestHelpers.createMockOrder();
        // Model format: d.M.yyyy HH:mm (örn: 1.1.2024 00:00)
        expect(order.formattedDate, matches(RegExp(r'\d{1,2}\.\d{1,2}\.\d{4} \d{2}:\d{2}')));
      });
    });
  });
}