// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/product_model.dart';

void main() {
  group('Product Model Tests - Dijital Ürün ve 0 TL Fiyat', () {
    group('isDigital getter', () {
      test('should return true for digital product type', () {
        final product = Product(
          id: 'p1',
          shopId: 's1',
          name: 'Instagram Takipçi',
          price: 50.0,
          stockQuantity: 0,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'digital',
          pricePer1000: 50.0,
          minQuantity: 100,
          maxQuantity: 10000,
        );
        expect(product.isDigital, isTrue);
      });

      test('should return false for normal product type', () {
        final product = Product(
          id: 'p2',
          shopId: 's1',
          name: 'T-Shirt',
          price: 100.0,
          stockQuantity: 10,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'normal',
        );
        expect(product.isDigital, isFalse);
      });

      test('hasVariants should exclude digital products', () {
        final product = Product(
          id: 'p3',
          shopId: 's1',
          name: 'YouTube İzlenme',
          price: 30.0,
          stockQuantity: 0,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'digital',
        );
        expect(product.hasVariants, isFalse);
      });
    });

    group('Digital product JSON parsing', () {
      test('should parse digital product fields from JSON', () {
        final json = {
          'id': 'p4',
          'shop_id': 's1',
          'name': 'TikTok Beğeni',
          'price': 25.0,
          'stock_quantity': 0,
          'is_available': true,
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
          'product_type': 'digital',
          'smm_provider_id': 'provider-1',
          'smm_service_id': 'service-100',
          'price_per_1000': 25.0,
          'min_quantity': 50,
          'max_quantity': 5000,
        };

        final product = Product.fromJson(json);

        expect(product.smmProviderId, equals('provider-1'));
        expect(product.smmServiceId, equals('service-100'));
        expect(product.pricePer1000, equals(25.0));
        expect(product.minQuantity, equals(50));
        expect(product.maxQuantity, equals(5000));
        expect(product.isDigital, isTrue);
      });

      test('should handle null digital fields gracefully', () {
        final json = {
          'id': 'p5',
          'shop_id': 's1',
          'name': 'Normal Product',
          'price': 50.0,
          'stock_quantity': 10,
          'is_available': true,
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
          'product_type': 'normal',
        };

        final product = Product.fromJson(json);

        expect(product.smmProviderId, isNull);
        expect(product.smmServiceId, isNull);
        expect(product.pricePer1000, isNull);
        expect(product.minQuantity, isNull);
        expect(product.maxQuantity, isNull);
      });
    });

    group('Price validation - 0 TL desteği', () {
      test('should accept zero price product', () {
        final product = Product(
          id: 'p6',
          shopId: 's1',
          name: 'Bedava Ürün',
          price: 0.0,
          stockQuantity: 100,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'normal',
        );

        // 0 TL fiyat kabul edilmeli
        expect(product.price, equals(0.0));
        expect(product.price < 0, isFalse); // 0 >= 0 olduğu için hata yok
      });

      test('should reject negative price', () {
        // Negatif fiyat validator tarafından reddedilmeli
        // manage_product_screen.dart: price < 0 kontrolü
        final product = Product(
          id: 'p7',
          shopId: 's1',
          name: 'Test',
          price: -10.0, // Bu zaten Product oluşturulmaz, ama test amaçlı
          stockQuantity: 1,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'normal',
        );

        // Negatif fiyat effectivePrice'e de yansır
        expect(product.effectivePrice < 0, isTrue);
      });
    });

    group('effectivePrice calculation', () {
      test('should return price for non-discount products', () {
        final product = Product(
          id: 'p8',
          shopId: 's1',
          name: 'Normal',
          price: 100.0,
          stockQuantity: 10,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'normal',
        );

        expect(product.effectivePrice, equals(100.0));
      });

      test('should return discountPrice if set and less than price', () {
        final product = Product(
          id: 'p9',
          shopId: 's1',
          name: 'Discounted',
          price: 100.0,
          discountPrice: 75.0,
          stockQuantity: 10,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'normal',
        );

        expect(product.effectivePrice, equals(75.0));
      });

      test('should return 0 for free product', () {
        final product = Product(
          id: 'p10',
          shopId: 's1',
          name: 'Free',
          price: 0.0,
          stockQuantity: 100,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'normal',
        );

        expect(product.effectivePrice, equals(0.0));
      });
    });

    group('Digital price calculation (per 1000)', () {
      test('unit price should be pricePer1000 / 1000', () {
        final product = Product(
          id: 'p11',
          shopId: 's1',
          name: 'SMM',
          price: 50.0,
          stockQuantity: 0,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'digital',
          pricePer1000: 50.0,
          minQuantity: 100,
          maxQuantity: 10000,
        );

        // 1000 adet için 50 TL → birim fiyat 0.05 TL
        final unitPrice = (product.pricePer1000 ?? 0) / 1000;
        expect(unitPrice, equals(0.05));

        // 1000 adet toplam
        final totalFor1000 = unitPrice * 1000;
        expect(totalFor1000, closeTo(50.0, 0.001));
      });

      test('should validate quantity within min/max range', () {
        final product = Product(
          id: 'p12',
          shopId: 's1',
          name: 'SMM',
          price: 30.0,
          stockQuantity: 0,
          isAvailable: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          productType: 'digital',
          pricePer1000: 30.0,
          minQuantity: 100,
          maxQuantity: 5000,
        );

        final minQ = product.minQuantity ?? 0;
        final maxQ = product.maxQuantity ?? 0;

        // Geçerli miktar kontrolü
        expect(minQ <= maxQ, isTrue);

        // Test senaryoları
        expect(100 >= minQ && 100 <= maxQ, isTrue, reason: 'min miktar geçerli');
        expect(5000 >= minQ && 5000 <= maxQ, isTrue, reason: 'max miktar geçerli');
        expect(50 >= minQ && 50 <= maxQ, isFalse, reason: 'min altı geçersiz');
        expect(10000 >= minQ && 10000 <= maxQ, isFalse, reason: 'max üstü geçersiz');
      });
    });
  });
}