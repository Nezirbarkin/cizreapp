// OrderService smoke testleri — 2026-07-29 FIX'lerinin koda uygulandığını
// doğrulayan testler. Gerçek Supabase entegrasyonu mock'lanmadan test edilemediği
// için statik imzalar ve kaynak-kod tabanlı doğrulamalar kullanılır.
//
// Kapsam:
// - createOrder'da Dart email çağrıları kaldırıldı (çift email fix)
// - createMultiShopOrder'da Dart email çağrıları kaldırıldı
// - createMultiShopOrder'da discountByShop parametresi var
// - createOrder'ın temel imzası korundu

// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import '../../lib/features/market/services/cart_service.dart';
import '../../lib/features/market/services/multi_shop_checkout_mapper.dart';

void main() {
  group('OrderService - çift email fix smoke testi', () {
    final orderServiceSource = File(
      'lib/features/shop/services/order_service.dart',
    ).readAsStringSync();

    test('createOrder içinde sendNewOrderEmailToSeller çağrısı YOK', () {
      // Çift email gönderimini engellemek için Dart tarafındaki email
      // çağrıları 2026-07-29'da kaldırıldı. DB trigger'ı (notify_new_order_email)
      // zaten Edge Function ile email gönderiyor.
      final createOrderStart = orderServiceSource.indexOf(
        'Future<Order?> createOrder',
      );
      expect(
        createOrderStart,
        greaterThan(-1),
        reason: 'createOrder bulunamadı',
      );

      // createOrder ile createMultiShopOrder arasındaki kısmi inceleme
      final createMultiShopStart = orderServiceSource.indexOf(
        'Future<MultiShopOrderResult> createMultiShopOrder',
      );
      expect(
        createMultiShopStart,
        greaterThan(-1),
        reason: 'createMultiShopOrder bulunamadı',
      );
      expect(
        createMultiShopStart,
        greaterThan(createOrderStart),
        reason: 'createOrder, createMultiShopOrder\'dan önce tanımlı olmalı',
      );

      final createOrderBody = orderServiceSource.substring(
        createOrderStart,
        createMultiShopStart,
      );

      expect(
        createOrderBody.contains('sendNewOrderEmailToSeller('),
        isFalse,
        reason: 'createOrder Dart\'tan email göndermemeli (DB trigger yapıyor)',
      );
      expect(
        createOrderBody.contains('sendNewOrderEmailToAdmin('),
        isFalse,
        reason:
            'createOrder Dart\'tan admin email göndermemeli (DB trigger yapıyor)',
      );
    });

    test('createMultiShopOrder içinde email çağrıları YOK', () {
      final createMultiShopStart = orderServiceSource.indexOf(
        'Future<MultiShopOrderResult> createMultiShopOrder',
      );
      final fileEnd = orderServiceSource.length;
      final createMultiShopBody = orderServiceSource.substring(
        createMultiShopStart,
        fileEnd,
      );

      expect(
        createMultiShopBody.contains('sendNewOrderEmailToSeller('),
        isFalse,
        reason: 'createMultiShopOrder Dart\'tan satıcıya email göndermemeli',
      );
      expect(
        createMultiShopBody.contains('sendNewOrderEmailToAdmin('),
        isFalse,
        reason: 'createMultiShopOrder Dart\'tan admin\'e email göndermemeli',
      );
    });

    test('push notification hâlâ çağrılıyor (Dart tarafı)', () {
      // Email kaldırıldı ama push notification kaldı çünkü DB'de push kanalı yok.
      final createOrderStart = orderServiceSource.indexOf(
        'Future<Order?> createOrder',
      );
      final createMultiShopStart = orderServiceSource.indexOf(
        'Future<MultiShopOrderResult> createMultiShopOrder',
      );
      final createOrderBody = orderServiceSource.substring(
        createOrderStart,
        createMultiShopStart,
      );
      expect(
        createOrderBody.contains("createNotification("),
        isTrue,
        reason: 'createOrder push notification göndermeli',
      );

      final createMultiShopBody = orderServiceSource.substring(
        createMultiShopStart,
      );
      expect(
        createMultiShopBody.contains("createNotification("),
        isTrue,
        reason: 'createMultiShopOrder push notification göndermeli',
      );
    });
  });

  group('OrderService - createMultiShopOrder discountByShop', () {
    final orderServiceSource = File(
      'lib/features/shop/services/order_service.dart',
    ).readAsStringSync();

    test('createMultiShopOrder imzasında discountByShop parametresi var', () {
      expect(
        orderServiceSource.contains(
          'Map<String, double>? discountByShop, // shopId -> indirim tutarı (kupon vb.)',
        ),
        isTrue,
        reason: 'createMultiShopOrder discountByShop parametresi kabul etmeli',
      );
    });

    test('discount ByShop kullanımı: discountByShop?[shopId] ?? 0.0', () {
      // DB\'ye 0 yazılmasını engelleyen koruma — önceki bug buradaydı.
      expect(
        orderServiceSource.contains('discountByShop?[shopId] ?? 0.0'),
        isTrue,
        reason: 'discountByShop parametresi uygulanmalı',
      );
    });
  });

  group('OrderService - createOrder temel imzası', () {
    test('OrderService sınıfı var ve createOrder public', () {
      final source = File(
        'lib/features/shop/services/order_service.dart',
      ).readAsStringSync();
      expect(source.contains('class OrderService'), isTrue);
      expect(source.contains('Future<Order?> createOrder({'), isTrue);
    });

    test('freeOrderLimitPerUser sabit olarak 1', () {
      // Bu sabit Sipariş Oluşturma analizinde (4.1) belirtildiği gibi
      // kullanıcı başına ücretsiz sipariş limiti.
      final source = File(
        'lib/features/shop/services/order_service.dart',
      ).readAsStringSync();
      expect(
        source.contains('static const int freeOrderLimitPerUser = 1'),
        isTrue,
      );
    });
  });

  group('MultiShopCheckoutScreen - discountByShop aktarımı', () {
    test(
      'her mağazanın doğrulanmış indirimi kendi shopId anahtarına aktarılır',
      () {
        final summaries = {
          'shop-a': ShopCartSummary(
            shopId: 'shop-a',
            shopName: 'A Mağazası',
            items: const [],
            subtotal: 100,
            deliveryFee: 10,
            discount: 20,
            total: 90,
          ),
          'shop-b': ShopCartSummary(
            shopId: 'shop-b',
            shopName: 'B Mağazası',
            items: const [],
            subtotal: 50,
            deliveryFee: 0,
            discount: 7.5,
            total: 42.5,
          ),
        };

        expect(
          buildDiscountByShop(summaries),
          equals({'shop-a': 20.0, 'shop-b': 7.5}),
        );
      },
    );

    test('özet yoksa boş indirim sözleşmesi döner', () {
      expect(buildDiscountByShop(const {}), isEmpty);
    });
  });
}
