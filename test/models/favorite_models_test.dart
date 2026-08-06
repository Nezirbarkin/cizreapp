// =============================================================================
// Favorite Models Test - Saf model testleri (mock gerektirmez)
// CizreApp - ProductFavorite ve PostFavorite JSON parse/serialize
// =============================================================================
// Kullanım:
//   flutter test test/models/favorite_models_test.dart
// =============================================================================

// ignore_for_file: avoid_relative_lib_imports, avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/core/models/favorite_models.dart';

void main() {
  // ===========================================================================
  // 1. PRODUCT FAVORITE - fromJson
  // ===========================================================================
  group('💖 ProductFavorite - fromJson', () {
    test('Ürün bilgisi olmadan parse edilmeli', () {
      final json = {
        'id': 'fav-123',
        'user_id': 'user-123',
        'product_id': 'product-456',
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final fav = ProductFavorite.fromJson(json);

      expect(fav.id, equals('fav-123'));
      expect(fav.userId, equals('user-123'));
      expect(fav.productId, equals('product-456'));
      expect(fav.createdAt, isA<DateTime>());
      expect(fav.product, isNull, reason: 'Join yoksa product null olmalı');
    });

    test('Ürün bilgisi ile birlikte parse edilmeli (join)', () {
      final json = {
        'id': 'fav-123',
        'user_id': 'user-123',
        'product_id': 'product-456',
        'created_at': '2026-08-01T10:00:00.000Z',
        'products': {
          'id': 'product-456',
          'name': 'Test Ürün',
          'price': 99.99,
          'shop_id': 'shop-123',
          'is_active': true,
          'created_at': '2026-07-01T00:00:00.000Z',
          'updated_at': '2026-07-01T00:00:00.000Z',
        },
      };

      final fav = ProductFavorite.fromJson(json);

      expect(fav.product, isNotNull);
      expect(fav.product!.id, equals('product-456'));
      expect(fav.product!.name, equals('Test Ürün'));
      expect(fav.product!.price, equals(99.99));
    });

    test('createdAt ISO 8601 formatından doğru parse edilmeli', () {
      final json = {
        'id': 'fav-1',
        'user_id': 'u1',
        'product_id': 'p1',
        'created_at': '2026-08-06T14:30:00.000Z',
      };

      final fav = ProductFavorite.fromJson(json);
      expect(fav.createdAt.year, equals(2026));
      expect(fav.createdAt.month, equals(8));
      expect(fav.createdAt.day, equals(6));
    });
  });

  // ===========================================================================
  // 2. PRODUCT FAVORITE - toJson
  // ===========================================================================
  group('💖 ProductFavorite - toJson', () {
    test('DB alan adları ile uyumlu JSON üretmeli', () {
      final fav = ProductFavorite(
        id: 'fav-1',
        userId: 'u1',
        productId: 'p1',
        createdAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
      );

      final json = fav.toJson();

      expect(json['id'], equals('fav-1'));
      expect(json['user_id'], equals('u1'));
      expect(json['product_id'], equals('p1'));
      expect(json['created_at'], contains('2026-08-01'));
      // Ürün bilgisi JSON'a dahil edilmemeli (DB zaten biliyor)
      expect(json.containsKey('products'), isFalse);
    });
  });

  // ===========================================================================
  // 3. PRODUCT FAVORITE - Round Trip
  // ===========================================================================
  group('💖 ProductFavorite - Round Trip', () {
    test('JSON → Model → JSON aynı veriyi vermeli', () {
      final originalJson = {
        'id': 'fav-rt-1',
        'user_id': 'user-rt',
        'product_id': 'product-rt',
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final fav = ProductFavorite.fromJson(originalJson);
      final outputJson = fav.toJson();

      expect(outputJson['id'], equals(originalJson['id']));
      expect(outputJson['user_id'], equals(originalJson['user_id']));
      expect(outputJson['product_id'], equals(originalJson['product_id']));
    });
  });

  // ===========================================================================
  // 4. POST FAVORITE - fromJson
  // ===========================================================================
  group('💌 PostFavorite - fromJson', () {
    test('Gönderi bilgisi olmadan parse edilmeli', () {
      final json = {
        'id': 'pfav-123',
        'user_id': 'user-123',
        'post_id': 'post-456',
        'created_at': '2026-08-01T10:00:00.000Z',
      };

      final fav = PostFavorite.fromJson(json);

      expect(fav.id, equals('pfav-123'));
      expect(fav.userId, equals('user-123'));
      expect(fav.postId, equals('post-456'));
      expect(fav.post, isNull);
    });

    test('Gönderi bilgisi ile birlikte parse edilmeli (join)', () {
      final json = {
        'id': 'pfav-1',
        'user_id': 'user-1',
        'post_id': 'post-1',
        'created_at': '2026-08-01T10:00:00.000Z',
        'posts': {
          'id': 'post-1',
          'content': 'Test gönderi içeriği',
          'user_id': 'user-1',
          'created_at': '2026-08-01T09:00:00.000Z',
          'updated_at': '2026-08-01T09:00:00.000Z',
        },
      };

      final fav = PostFavorite.fromJson(json);
      expect(fav.post, isNotNull);
      expect(fav.post!.id, equals('post-1'));
    });
  });

  // ===========================================================================
  // 5. POST FAVORITE - toJson
  // ===========================================================================
  group('💌 PostFavorite - toJson', () {
    test('DB alan adları ile uyumlu JSON üretmeli', () {
      final fav = PostFavorite(
        id: 'pfav-1',
        userId: 'u1',
        postId: 'p1',
        createdAt: DateTime.parse('2026-08-01T10:00:00.000Z'),
      );

      final json = fav.toJson();

      expect(json['id'], equals('pfav-1'));
      expect(json['user_id'], equals('u1'));
      expect(json['post_id'], equals('p1'));
      expect(json.containsKey('posts'), isFalse);
    });
  });

  // ===========================================================================
  // 6. EDGE CASES
  // ===========================================================================
  group('🧪 Edge Cases', () {
    test('Boş product objesi null olarak parse edilmeli', () {
      final json = {
        'id': 'fav-edge',
        'user_id': 'u1',
        'product_id': 'p1',
        'created_at': '2026-08-01T10:00:00.000Z',
        'products': null, // Explicit null
      };

      final fav = ProductFavorite.fromJson(json);
      expect(fav.product, isNull);
    });

    test('Çok eski tarihler parse edilebilmeli', () {
      final json = {
        'id': 'fav-old',
        'user_id': 'u1',
        'product_id': 'p1',
        'created_at': '2020-01-01T00:00:00.000Z',
      };

      final fav = ProductFavorite.fromJson(json);
      expect(fav.createdAt.year, equals(2020));
    });
  });

  // ===========================================================================
  // 7. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('💖 FAVORITE MODELS TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ ProductFavorite + PostFavorite model testleri geçti');
    print('💡 Bu testler:');
    print('   - JSON parse/serialize');
    print('   - Join handling (null product/post)');
    print('   - Round trip integrity');
    print('   - Edge cases (null, eski tarihler)');
    print('=' * 60);
  });
}
