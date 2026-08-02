// Güvenlik smoke testleri — production'da risk oluşturan kod kalıplarının
// kaldırıldığını/sarıldığını doğrular.
//
// Kapsam:
// - SMS doğrulama kodu artık production'da ekranda gösterilmiyor
//   (sadece kDebugMode). 2026-07-29 FIX.

// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

void main() {
  group('SMS doğrulama kodu — production güvenliği', () {
    test('market/checkout_screen.dart: displayedCode kDebugMode koşulunda', () {
      final source = File('lib/features/market/screens/checkout_screen.dart').readAsStringSync();
      // Düzeltilmiş kalıp: `kDebugMode && displayedCode != null && ...`
      // Önceki tehlikeli kalıp: `displayedCode != null && displayedCode!.isNotEmpty`
      final hasGuarded = RegExp(
        r'kDebugMode\s*&&\s*displayedCode\s*!=\s*null\s*&&\s*displayedCode!\.isNotEmpty',
      ).hasMatch(source);
      expect(hasGuarded, isTrue,
          reason: 'displayedCode kDebugMode korumalı olmalı');
    });

    test('multi_shop_checkout_screen.dart: displayedCode kDebugMode koşulunda', () {
      final source = File('lib/features/market/screens/multi_shop_checkout_screen.dart').readAsStringSync();
      final hasGuarded = RegExp(
        r'kDebugMode\s*&&\s*displayedCode\s*!=\s*null\s*&&\s*displayedCode!\.isNotEmpty',
      ).hasMatch(source);
      expect(hasGuarded, isTrue,
          reason: 'displayedCode kDebugMode korumalı olmalı (multi-shop)');
    });

    test('shop/checkout_screen.dart: displayedCode kDebugMode koşulunda', () {
      final source = File('lib/features/shop/screens/checkout_screen.dart').readAsStringSync();
      final hasGuarded = RegExp(
        r'kDebugMode\s*&&\s*displayedCode\s*!=\s*null\s*&&\s*displayedCode!\.isNotEmpty',
      ).hasMatch(source);
      expect(hasGuarded, isTrue,
          reason: 'displayedCode kDebugMode korumalı olmalı (shop checkout)');
    });

    test('Tüm 3 dosyada kDebugMode import edildi', () {
      for (final path in [
        'lib/features/market/screens/checkout_screen.dart',
        'lib/features/market/screens/multi_shop_checkout_screen.dart',
        'lib/features/shop/screens/checkout_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains("import 'package:flutter/foundation.dart' show kDebugMode"),
          isTrue,
          reason: '$path kDebugMode import etmeli',
        );
      }
    });
  });

  group('Sepet join yapısı — discount_price entegrasyonu', () {
    test('CartService.getCart join\'inde discount_price var', () {
      final source = File('lib/features/market/services/cart_service.dart').readAsStringSync();
      // getCart içindeki ürün join'inde discount_price alanı çekilmeli
      final getCartStart = source.indexOf('Future<List<CartItem>> getCart(');
      expect(getCartStart, greaterThan(-1));

      // getCart gövdesinin başlangıcını bul
      final firstBrace = source.indexOf('{', getCartStart);
      final firstTripleQuote = source.indexOf("'''", firstBrace);
      final secondTripleQuote = source.indexOf("'''", firstTripleQuote + 3);

      final joinBlock = source.substring(firstTripleQuote, secondTripleQuote + 3);
      expect(joinBlock.contains('discount_price'),
          isTrue,
          reason: 'Sepet join\'inde discount_price alanı çekilmeli');
    });

    test('CartService._mapToCartItem productDiscountPrice parse ediyor', () {
      final source = File('lib/features/market/services/cart_service.dart').readAsStringSync();
      // _mapToCartItem içinde productDiscountPrice alanı okunmalı
      final startIdx = source.indexOf('CartItem _mapToCartItem(');
      expect(startIdx, greaterThan(-1));

      final endIdx = source.indexOf('}', source.indexOf('variantData: item', startIdx));
      final helperBody = source.substring(startIdx, endIdx + 1);
      expect(helperBody.contains('productDiscountPrice'),
          isTrue,
          reason: '_mapToCartItem productDiscountPrice alanını parse etmeli');
    });
  });

  group('Product model — effectivePrice sözleşmesi', () {
    test('Product.effectivePrice discount_price < price kuralını uygular', () {
      final source = File('lib/core/models/product_model.dart').readAsStringSync();
      // effectivePrice getter\'ı discount_price\'ı price\'a göre önceliklendirir
      expect(
        RegExp(
          r'if\s*\(\s*discountPrice\s*!=\s*null\s*&&\s*discountPrice!\s*>\s*0\s*&&\s*discountPrice!\s*<\s*price\s*\)\s*\{\s*return\s+discountPrice!',
        ).hasMatch(source),
        isTrue,
        reason: 'Product.effectivePrice discount_price öncelikli mantığı içermeli',
      );
    });
  });
}
