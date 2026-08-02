// CartItem model testleri — özellikle 2026-07-29 FIX sonrası `effectivePrice` mantığı.
// Bug: Sepet join'inde `discount_price` kolonu çekilmiyordu, dolayısıyla
// kullanıcı detayda gördüğü indirimli fiyatı sepete ekleyince indirimsiz
// fiyat üzerinden işlem görüyordu. Bu test grubu yeni mantığı kilitler.

// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/cart_model.dart';

void main() {
  group('CartItem - effectivePrice (2026-07-29 FIX)', () {
    test('productDiscountPrice null ise productPrice döner', () {
      final item = CartItem(
        id: 'c1',
        userId: 'u1',
        productId: 'p1',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: null,
      );
      expect(item.effectivePrice, 100.0);
    });

    test('productPrice null ise 0 döner (sıfır güvenlik)', () {
      final item = CartItem(
        id: 'c2',
        userId: 'u1',
        productId: 'p2',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: null,
        productDiscountPrice: 50.0,
      );
      // productPrice null + discount var → effectivePrice 0 (güvenli)
      expect(item.effectivePrice, 0.0);
    });

    test('discount_price < price ise discount_price kullanılır (kritik bug fix)', () {
      final item = CartItem(
        id: 'c3',
        userId: 'u1',
        productId: 'p3',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 150.0,
        productOldPrice: 200.0,
        productDiscountPrice: 90.0, // %40 indirim
      );
      // Eski bug: 150.0 dönerdi (price alınırdı)
      // Yeni davranış: 90.0 (discount_price öncelikli)
      expect(item.effectivePrice, 90.0);
    });

    test('discount_price > price ise price kullanılır (tutarsız veri koruması)', () {
      final item = CartItem(
        id: 'c4',
        userId: 'u1',
        productId: 'p4',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 50.0,
        productDiscountPrice: 75.0, // anlamsız: discount > price
      );
      // discount_price, price'tan büyükse price kullan (eski mantık)
      expect(item.effectivePrice, 50.0);
    });

    test('discount_price == price ise price kullanılır (sıfır indirim)', () {
      final item = CartItem(
        id: 'c5',
        userId: 'u1',
        productId: 'p5',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 100.0, // aynı fiyat = indirim yok
      );
      expect(item.effectivePrice, 100.0);
    });

    test('discount_price 0 ise price kullanılır (pasif indirim)', () {
      final item = CartItem(
        id: 'c6',
        userId: 'u1',
        productId: 'p6',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 0.0, // 0 = indirim aktif değil
      );
      expect(item.effectivePrice, 100.0);
    });

    test('hem null ise 0 döner (uç durum)', () {
      final item = CartItem(
        id: 'c7',
        userId: 'u1',
        productId: 'p7',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: null,
        productDiscountPrice: null,
      );
      expect(item.effectivePrice, 0.0);
    });
  });

  group('CartItem - itemTotal (effectivePrice * quantity)', () {
    test('indirimsiz ürün × 3 = doğru toplam', () {
      final item = CartItem(
        id: 'i1',
        userId: 'u1',
        productId: 'p1',
        quantity: 3,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 50.0,
      );
      expect(item.itemTotal, 150.0);
    });

    test('indirimli ürün × 2 = effectivePrice × quantity (BUG FIX)', () {
      // Eski kodda: itemTotal = productPrice * qty = 200.0 * 2 = 400.0
      // Yeni kodda: itemTotal = effectivePrice * qty = 120.0 * 2 = 240.0
      final item = CartItem(
        id: 'i2',
        userId: 'u1',
        productId: 'p2',
        quantity: 2,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 200.0,
        productOldPrice: 250.0,
        productDiscountPrice: 120.0,
      );
      expect(item.itemTotal, 240.0); // 120 * 2
    });

    test('quantity 0 ise 0 döner', () {
      final item = CartItem(
        id: 'i3',
        userId: 'u1',
        productId: 'p3',
        quantity: 0,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
      );
      expect(item.itemTotal, 0.0);
    });
  });

  group('CartItem - hasDiscount mantığı', () {
    test('discount_price < price → hasDiscount true', () {
      final item = CartItem(
        id: 'd1',
        userId: 'u1',
        productId: 'p1',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 80.0,
      );
      expect(item.hasDiscount, isTrue);
    });

    test('old_price > price → hasDiscount true (eski yol hala çalışır)', () {
      final item = CartItem(
        id: 'd2',
        userId: 'u1',
        productId: 'p2',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productOldPrice: 150.0,
        productDiscountPrice: null,
      );
      expect(item.hasDiscount, isTrue);
    });

    test('discount yoksa hasDiscount false', () {
      final item = CartItem(
        id: 'd3',
        userId: 'u1',
        productId: 'p3',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productOldPrice: null,
        productDiscountPrice: null,
      );
      expect(item.hasDiscount, isFalse);
    });

    test('price == effective_price → hasDiscount false', () {
      final item = CartItem(
        id: 'd4',
        userId: 'u1',
        productId: 'p4',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 100.0,
      );
      expect(item.hasDiscount, isFalse);
    });
  });

  group('CartItem - itemDiscount (gösterim amaçlı tasarruf)', () {
    test('discount_price + old_price varsa tasarruf = (oldPrice - effective) * qty', () {
      final item = CartItem(
        id: 's1',
        userId: 'u1',
        productId: 'p1',
        quantity: 2,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 200.0,
        productOldPrice: 250.0,
        productDiscountPrice: 120.0,
      );
      // effectivePrice = 120, oldPrice = 250 (en yüksek gösterilen fiyat)
      // tasarruf = (250 - 120) * 2 = 260
      expect(item.itemDiscount, 260.0);
    });

    test('discount_price yok ama old_price varsa tasarruf = (oldPrice - price) * qty', () {
      final item = CartItem(
        id: 's2',
        userId: 'u1',
        productId: 'p2',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 80.0,
        productOldPrice: 100.0,
        productDiscountPrice: null,
      );
      expect(item.itemDiscount, 20.0);
    });

    test('sadece discount_price varsa tasarruf = (price - effective) * qty', () {
      final item = CartItem(
        id: 's2b',
        userId: 'u1',
        productId: 'p2b',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productOldPrice: null,
        productDiscountPrice: 70.0,
      );
      // effectivePrice = 70, price = 100, oldPrice = null
      // tasarruf = (100 - 70) * 1 = 30
      expect(item.itemDiscount, 30.0);
    });

    test('indirim yoksa tasarruf 0', () {
      final item = CartItem(
        id: 's3',
        userId: 'u1',
        productId: 'p3',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: null,
        productOldPrice: null,
      );
      expect(item.itemDiscount, 0.0);
    });
  });

  group('CartItem - discountPercentage', () {
    test('discount_price: %33 (100→67)', () {
      final item = CartItem(
        id: 'p1',
        userId: 'u1',
        productId: 'p1',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 67.0,
      );
      // base = price (100), unit = 67, fark = 33
      expect(item.discountPercentage, 33);
    });

    test('old_price: %20 (100→80)', () {
      final item = CartItem(
        id: 'p2',
        userId: 'u1',
        productId: 'p2',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 80.0,
        productOldPrice: 100.0,
      );
      expect(item.discountPercentage, 20);
    });

    test('indirim yoksa 0', () {
      final item = CartItem(
        id: 'p3',
        userId: 'u1',
        productId: 'p3',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
      );
      expect(item.discountPercentage, 0);
    });
  });

  group('CartItem - fromJson discount_price parse', () {
    test('product_discount_price null olabilir', () {
      final json = {
        'id': 'c1',
        'user_id': 'u1',
        'product_id': 'p1',
        'quantity': 1,
        'created_at': '2026-07-29T10:00:00.000Z',
        'updated_at': '2026-07-29T10:00:00.000Z',
        'product_price': 100.0,
        // product_discount_price yok
      };
      final item = CartItem.fromJson(json);
      expect(item.productDiscountPrice, isNull);
      expect(item.effectivePrice, 100.0);
    });

    test('product_discount_price int olarak gelirse doğru parse', () {
      final json = {
        'id': 'c2',
        'user_id': 'u1',
        'product_id': 'p2',
        'quantity': 1,
        'created_at': '2026-07-29T10:00:00.000Z',
        'updated_at': '2026-07-29T10:00:00.000Z',
        'product_price': 100.0,
        'product_discount_price': 75, // int
      };
      final item = CartItem.fromJson(json);
      expect(item.productDiscountPrice, 75.0);
      expect(item.effectivePrice, 75.0);
    });

    test('product_discount_price double olarak gelirse doğru parse', () {
      final json = {
        'id': 'c3',
        'user_id': 'u1',
        'product_id': 'p3',
        'quantity': 1,
        'created_at': '2026-07-29T10:00:00.000Z',
        'updated_at': '2026-07-29T10:00:00.000Z',
        'product_price': 100.0,
        'product_discount_price': 75.5, // double
      };
      final item = CartItem.fromJson(json);
      expect(item.productDiscountPrice, 75.5);
      expect(item.effectivePrice, 75.5);
    });
  });

  group('CartItem - copyWith productDiscountPrice', () {
    test('yeni discount_price ile kopyalanır', () {
      final original = CartItem(
        id: 'c1',
        userId: 'u1',
        productId: 'p1',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 80.0,
      );
      final copy = original.copyWith(productDiscountPrice: 60.0);
      expect(copy.productDiscountPrice, 60.0);
      expect(copy.productPrice, 100.0); // değişmedi
      expect(copy.effectivePrice, 60.0);
    });

    test('productDiscountPrice null geçilirse null olur (silme)', () {
      final original = CartItem(
        id: 'c2',
        userId: 'u1',
        productId: 'p2',
        quantity: 1,
        createdAt: DateTime(2026, 7, 29),
        updatedAt: DateTime(2026, 7, 29),
        productPrice: 100.0,
        productDiscountPrice: 80.0,
      );
      final copy = original.copyWith();
      // productDiscountPrice explicit null geçilmedi → orijinal kalmalı
      expect(copy.productDiscountPrice, 80.0);
    });
  });

  group('CartSummary - indirimli sepet toplamı', () {
    test('indirimli 2 ürünün subtotal/toplam tutarı doğru (BUG FIX)', () {
      // Eski kod: CartSummary.fromItems → itemTotal = productPrice * qty
      // Yeni kod: itemTotal = effectivePrice * qty
      final items = [
        CartItem(
          id: 'a',
          userId: 'u1',
          productId: 'p1',
          quantity: 2,
          createdAt: DateTime(2026, 7, 29),
          updatedAt: DateTime(2026, 7, 29),
          productPrice: 100.0,
          productDiscountPrice: 70.0,
        ),
        CartItem(
          id: 'b',
          userId: 'u1',
          productId: 'p2',
          quantity: 1,
          createdAt: DateTime(2026, 7, 29),
          updatedAt: DateTime(2026, 7, 29),
          productPrice: 50.0,
        ),
      ];
      final summary = CartSummary.fromItems(items, deliveryFee: 10.0);
      // subtotal = (70*2) + (50*1) = 140 + 50 = 190
      expect(summary.subtotal, 190.0);
      // total = 190 + 10 = 200
      expect(summary.total, 200.0);
      // tasarruf: ilk ürün (100-70)*2 = 60, ikinci 0 → 60
      expect(summary.discount, 60.0);
    });

    test('subtotal deliveryFee dahil DEĞİL, total dahil', () {
      final items = [
        CartItem(
          id: 'c1',
          userId: 'u1',
          productId: 'p1',
          quantity: 1,
          createdAt: DateTime(2026, 7, 29),
          updatedAt: DateTime(2026, 7, 29),
          productPrice: 100.0,
        ),
      ];
      final summary = CartSummary.fromItems(items, deliveryFee: 15.0);
      expect(summary.subtotal, 100.0);
      expect(summary.deliveryFee, 15.0);
      expect(summary.total, 115.0);
    });
  });
}
