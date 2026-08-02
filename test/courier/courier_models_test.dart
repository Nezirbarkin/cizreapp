// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/courier_request_model.dart';
import '../../lib/core/models/courier_assignment_model.dart';

void main() {
  // ===========================================================================
  // CourierRequestStatus
  // ===========================================================================
  group('CourierRequestStatus', () {
    test('label değerleri doğru', () {
      expect(CourierRequestStatus.pending.label, equals('Beklemede'));
      expect(CourierRequestStatus.approved.label, equals('Onaylandı'));
      expect(CourierRequestStatus.rejected.label, equals('Reddedildi'));
    });

    test('dbValue enum adıyla aynı', () {
      for (final s in CourierRequestStatus.values) {
        expect(s.dbValue, equals(s.name));
      }
    });

    test('fromString geçerli değerleri eşler', () {
      expect(CourierRequestStatus.fromString('pending'),
          equals(CourierRequestStatus.pending));
      expect(CourierRequestStatus.fromString('approved'),
          equals(CourierRequestStatus.approved));
      expect(CourierRequestStatus.fromString('rejected'),
          equals(CourierRequestStatus.rejected));
    });

    test('fromString geçersiz/null değerlerde pending döner ( güvenli default )', () {
      expect(CourierRequestStatus.fromString('invalid'),
          equals(CourierRequestStatus.pending));
      expect(CourierRequestStatus.fromString(''),
          equals(CourierRequestStatus.pending));
    });
  });

  // ===========================================================================
  // CourierAssignmentStatus
  // ===========================================================================
  group('CourierAssignmentStatus', () {
    test('label değerleri doğru', () {
      expect(CourierAssignmentStatus.assigned.label, equals('Atandı'));
      expect(CourierAssignmentStatus.pickedUp.label, equals('Alındı'));
      expect(CourierAssignmentStatus.delivered.label, equals('Teslim Edildi'));
      expect(CourierAssignmentStatus.cancelled.label, equals('İptal Edildi'));
    });

    test('dbValue enum adıyla aynı', () {
      for (final s in CourierAssignmentStatus.values) {
        expect(s.dbValue, equals(s.name));
      }
    });

    test('fromString geçerli değerleri eşler', () {
      expect(CourierAssignmentStatus.fromString('assigned'),
          equals(CourierAssignmentStatus.assigned));
      expect(CourierAssignmentStatus.fromString('pickedUp'),
          equals(CourierAssignmentStatus.pickedUp));
      expect(CourierAssignmentStatus.fromString('delivered'),
          equals(CourierAssignmentStatus.delivered));
      expect(CourierAssignmentStatus.fromString('cancelled'),
          equals(CourierAssignmentStatus.cancelled));
    });

    test('fromString geçersiz değerde assigned döner ( güvenli default )', () {
      expect(CourierAssignmentStatus.fromString('invalid'),
          equals(CourierAssignmentStatus.assigned));
      expect(CourierAssignmentStatus.fromString(''),
          equals(CourierAssignmentStatus.assigned));
    });
  });

  // ===========================================================================
  // CourierRequest
  // ===========================================================================
  group('CourierRequest', () {
    test('nested shops/profiles ile fromJson doğru eşler', () {
      final req = CourierRequest.fromJson({
        'id': 'req-1',
        'shop_id': 'shop-1',
        'seller_id': 'seller-1',
        'status': 'approved',
        'message': 'lütfen',
        'admin_notes': 'ok',
        'created_at': '2026-01-02T03:04:05.000Z',
        'updated_at': '2026-01-02T03:05:00.000Z',
        'reviewed_at': '2026-01-02T04:00:00.000Z',
        'reviewed_by': 'admin-1',
        'shops': {'name': 'Marketim'},
        'profiles': {
          'full_name': 'Ahmet',
          'username': 'ahmet',
          'email': 'ahmet@x.com',
        },
      });

      expect(req.id, equals('req-1'));
      expect(req.shopId, equals('shop-1'));
      expect(req.sellerId, equals('seller-1'));
      expect(req.status, equals(CourierRequestStatus.approved));
      expect(req.message, equals('lütfen'));
      expect(req.adminNotes, equals('ok'));
      expect(req.reviewedBy, equals('admin-1'));
      expect(req.reviewedAt, isNotNull);
      expect(req.shopName, equals('Marketim'));
      expect(req.sellerName, equals('Ahmet'));
      expect(req.sellerEmail, equals('ahmet@x.com'));
    });

    test('profiles full_name yoksa username, o da yoksa flat seller_name düşer', () {
      final req = CourierRequest.fromJson({
        'id': 'r',
        'shop_id': 's',
        'seller_id': 'u',
        'status': 'pending',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'profiles': {'username': 'veli'},
        'seller_name': 'flat-name',
      });
      expect(req.sellerName, equals('veli'));
    });

    test('shops yoksa flat shop_name kullanılır', () {
      final req = CourierRequest.fromJson({
        'id': 'r',
        'shop_id': 's',
        'seller_id': 'u',
        'status': 'pending',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'shop_name': 'FlatShop',
      });
      expect(req.shopName, equals('FlatShop'));
    });

    test('eksik tarih alanlarında crash etmez ( now fallback )', () {
      final req = CourierRequest.fromJson({
        'id': 'r',
        'shop_id': 's',
        'seller_id': 'u',
        'status': 'pending',
      });
      expect(req.createdAt, isNotNull);
      expect(req.updatedAt, isNotNull);
      expect(req.reviewedAt, isNull);
    });

    test('eksik id/shop_id/seller_id boş stringe düşer ( crash değil )', () {
      final req = CourierRequest.fromJson({'status': 'pending'});
      expect(req.id, equals(''));
      expect(req.shopId, equals(''));
      expect(req.sellerId, equals(''));
    });

    test('toJson anahtarları db ile uyumlu ve status dbValue verir', () {
      final req = CourierRequest(
        id: 'r',
        shopId: 's',
        sellerId: 'u',
        status: CourierRequestStatus.rejected,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );
      final json = req.toJson();
      expect(json['id'], equals('r'));
      expect(json['shop_id'], equals('s'));
      expect(json['seller_id'], equals('u'));
      expect(json['status'], equals('rejected'));
      expect(json['created_at'], equals('2026-01-01T00:00:00.000'));
    });

    test('copyWith yalnızca verilen alanları değiştirir', () {
      final req = CourierRequest(
        id: 'r',
        shopId: 's',
        sellerId: 'u',
        status: CourierRequestStatus.pending,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final updated = req.copyWith(status: CourierRequestStatus.approved, adminNotes: 'n');
      expect(updated.status, equals(CourierRequestStatus.approved));
      expect(updated.adminNotes, equals('n'));
      expect(updated.id, equals('r'));
      expect(updated.shopId, equals('s'));
    });
  });

  // ===========================================================================
  // CourierAssignment
  // ===========================================================================
  group('CourierAssignment', () {
    Map<String, dynamic> fullJson() => {
          'id': 'a1',
          'order_id': 'o1',
          'courier_id': 'c1',
          'status': 'assigned',
          'fee_amount': 15.5,
          'assigned_at': '2026-01-01T00:00:00.000Z',
          'picked_up_at': '2026-01-01T01:00:00.000Z',
          'delivered_at': null,
          'cancelled_at': null,
          'cancellation_reason': null,
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
          'orders': {'id': 'o1', 'total_amount': 60},
          'courier_name': 'Kurye1',
          'courier_phone': '+90555',
        };

    test('fromJson tüm alanları doğru eşler', () {
      final a = CourierAssignment.fromJson(fullJson());
      expect(a.id, equals('a1'));
      expect(a.orderId, equals('o1'));
      expect(a.courierId, equals('c1'));
      expect(a.status, equals(CourierAssignmentStatus.assigned));
      expect(a.feeAmount, equals(15.5));
      expect(a.pickedUpAt, isNotNull);
      expect(a.deliveredAt, isNull);
      expect(a.order, isNotNull);
      expect(a.order!['id'], equals('o1'));
      expect(a.courierName, equals('Kurye1'));
      expect(a.courierPhone, equals('+90555'));
    });

    test('fee_amount int gelirse double çevrilir ( num güvenli cast )', () {
      final a = CourierAssignment.fromJson({
        'id': 'a',
        'order_id': 'o',
        'courier_id': 'c',
        'status': 'assigned',
        'fee_amount': 20,
        'assigned_at': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(a.feeAmount, equals(20.0));
    });

    test('orders bir List ( to-many join ) gelirse order null olur ( güvenli cast )', () {
      // Eski kod `as Map<String, dynamic>?` cast'i ile TypeError fırlatırdı.
      final a = CourierAssignment.fromJson({
        'id': 'a',
        'order_id': 'o',
        'courier_id': 'c',
        'status': 'assigned',
        'fee_amount': 0,
        'assigned_at': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
        'orders': [{'id': 'o1'}],
      });
      expect(a.order, isNull);
    });

    test('eksik id/order_id/courier_id boş stringe düşer ( crash değil )', () {
      final a = CourierAssignment.fromJson({
        'status': 'assigned',
        'fee_amount': 0,
        'assigned_at': '2026-01-01T00:00:00.000Z',
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(a.id, equals(''));
      expect(a.orderId, equals(''));
      expect(a.courierId, equals(''));
      expect(a.feeAmount, equals(0.0));
    });

    test('eksik assigned_at tarihinde now fallback ( crash değil )', () {
      final a = CourierAssignment.fromJson({
        'id': 'a',
        'order_id': 'o',
        'courier_id': 'c',
        'status': 'assigned',
        'fee_amount': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
        'updated_at': '2026-01-01T00:00:00.000Z',
      });
      expect(a.assignedAt, isNotNull);
      expect(a.createdAt, isNotNull);
      expect(a.updatedAt, isNotNull);
    });

    test('toJson db alan adları ile uyumlu', () {
      final a = CourierAssignment(
        id: 'a1',
        orderId: 'o1',
        courierId: 'c1',
        status: CourierAssignmentStatus.delivered,
        feeAmount: 25.0,
        assignedAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 2),
      );
      final json = a.toJson();
      expect(json['id'], equals('a1'));
      expect(json['order_id'], equals('o1'));
      expect(json['courier_id'], equals('c1'));
      expect(json['status'], equals('delivered'));
      expect(json['fee_amount'], equals(25.0));
      expect(json['picked_up_at'], isNull);
    });
  });

  // ===========================================================================
  // CourierOrder + CourierOrderItem
  // ===========================================================================
  group('CourierOrder', () {
    test('order_items ile fromJson doğru eşler', () {
      final o = CourierOrder.fromJson({
        'id': 'o-9',
        'order_number': '#100',
        'total_amount': 120.0,
        'status': 'on_the_way',
        'payment_method': 'card_on_delivery',
        'customer_name': 'Müşteri',
        'customer_phone': '+90500',
        'address_display': 'Cadde Sokak',
        'shop_name': 'Marketim',
        'order_items': [
          {'product_name': 'Ekmek', 'quantity': 2, 'product_image_url': 'http://x/a.jpg'},
          {'product_name': 'Süt', 'quantity': 1},
        ],
        'created_at': '2026-01-01T00:00:00.000Z',
      });

      expect(o.id, equals('o-9'));
      expect(o.orderNumber, equals('#100'));
      expect(o.totalAmount, equals(120.0));
      expect(o.status, equals('on_the_way'));
      expect(o.paymentMethod, equals('card_on_delivery'));
      expect(o.deliveryAddress, equals('Cadde Sokak'));
      expect(o.shopName, equals('Marketim'));
      expect(o.items.length, equals(2));
      expect(o.items[0].productName, equals('Ekmek'));
      expect(o.items[0].quantity, equals(2));
      expect(o.items[0].productImageUrl, equals('http://x/a.jpg'));
      expect(o.items[1].quantity, equals(1));
      expect(o.items[1].productImageUrl, isNull);
    });

    test('order_number yoksa id prefix fallback crash etmez', () {
      final o = CourierOrder.fromJson({
        'id': 'abcdef1234567890',
        'status': 'pending',
        'payment_method': 'cash',
        'total_amount': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      // id 16 karakter; substring(0,8) güvenli çalışır.
      expect(o.orderNumber, equals('#abcdef12'));
    });

    test('order_number yoksa ve id 8 karakterden KISA ise RangeError fırlatmaz ( regression )', () {
      // Eski kod `id.toString().substring(0, 8)` ile RangeError veriyordu.
      final o = CourierOrder.fromJson({
        'id': 'o',
        'status': 'pending',
        'payment_method': 'cash',
        'total_amount': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.orderNumber, equals('#o'));

      // id tamamen yoksa '#' döner (crash değil).
      final o2 = CourierOrder.fromJson({
        'status': 'pending',
        'payment_method': 'cash',
        'total_amount': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o2.orderNumber, equals('#'));
    });

    test('order_items eksikse boş liste döner ( crash değil )', () {
      final o = CourierOrder.fromJson({
        'id': 'o',
        'status': 'pending',
        'payment_method': 'cash',
        'total_amount': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.items, isEmpty);
    });

    test('address_display yoksa delivery_address_text fallback', () {
      final o = CourierOrder.fromJson({
        'id': 'o',
        'status': 'pending',
        'payment_method': 'cash',
        'total_amount': 0,
        'delivery_address_text': 'Metin adres',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.deliveryAddress, equals('Metin adres'));
    });

    test('shop_name yoksa nested shops.name fallback ( Map güvenli )', () {
      final o = CourierOrder.fromJson({
        'id': 'o',
        'status': 'pending',
        'payment_method': 'cash',
        'total_amount': 0,
        'shops': {'name': 'NestedShop'},
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.shopName, equals('NestedShop'));
    });

    test('CourierOrderItem null/eksik alanlarda güvenli default', () {
      final item = CourierOrderItem.fromJson({});
      expect(item.productName, equals('Ürün'));
      expect(item.quantity, equals(1));
      expect(item.productImageUrl, isNull);
    });
  });
}