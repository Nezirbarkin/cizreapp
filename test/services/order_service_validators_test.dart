// =============================================================================
// Order Service Validators Test - Sipariş validasyon kuralları
// CizreApp - 0 TL limit, toplam hesaplama, indirim kontrolü
// =============================================================================
// Kullanım:
//   flutter test test/services/order_service_validators_test.dart
// =============================================================================

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

/// Sipariş validasyon kuralları - OrderService'ten bağımsız, saf fonksiyonlar.
/// Bu kurallar hem Flutter client'ta hem Supabase RLS'de uygulanmalı.
class OrderValidators {
  /// Ücretsiz sipariş sayısı kullanıcı başına
  static const int freeOrderLimitPerUser = 1;

  /// Kullanıcının yeni ücretsiz sipariş verip veremeyeceğini kontrol et
  /// Returns: error mesajı veya null (sorun yok)
  static String? validateFreeOrderLimit({
    required int existingFreeOrderCount,
    required int maxFreeOrders,
  }) {
    if (existingFreeOrderCount >= maxFreeOrders) {
      return 'Ücretsiz sipariş hakkınızı kullandınız. '
          'Bu üründen sadece $maxFreeOrders kez ücretsiz sipariş verebilirsiniz.';
    }
    return null;
  }

  /// Sipariş tutarı validasyonu
  /// Negatif tutar reddedilmeli
  static String? validateOrderAmount({
    required double subtotal,
    required double deliveryFee,
    required double discount,
    required double total,
  }) {
    // Bileşenleri önce kontrol et (hata mesajları daha spesifik)
    if (subtotal < 0) return 'Ara toplam negatif olamaz';
    if (deliveryFee < 0) return 'Teslimat ücreti negatif olamaz';
    if (discount < 0) return 'İndirim negatif olamaz';
    if (total < 0) return 'Sipariş tutarı negatif olamaz';

    // Toplam doğru hesaplanmış mı?
    final expectedTotal = subtotal + deliveryFee - discount;
    if ((expectedTotal - total).abs() > 0.01) {
      return 'Toplam tutar hatalı (beklenen: $expectedTotal, gelen: $total)';
    }

    return null;
  }

  /// Teslimat adresi validasyonu
  static String? validateDeliveryAddress(String? address) {
    if (address == null || address.trim().isEmpty) {
      return 'Teslimat adresi boş olamaz';
    }
    if (address.trim().length < 10) {
      return 'Teslimat adresi en az 10 karakter olmalı';
    }
    if (address.length > 500) {
      return 'Teslimat adresi en fazla 500 karakter olabilir';
    }
    return null;
  }

  /// Sipariş öğeleri validasyonu
  static String? validateOrderItems(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return 'Sipariş en az 1 ürün içermelidir';

    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item['product_id'] == null || (item['product_id'] as String).isEmpty) {
        return 'Ürün #${i + 1}: product_id eksik';
      }
      final qty = item['quantity'] as int? ?? 0;
      if (qty <= 0) return 'Ürün #${i + 1}: miktar 0\'dan büyük olmalı';
      if (qty > 999) return 'Ürün #${i + 1}: miktar 999\'dan büyük olamaz';

      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      if (price < 0) return 'Ürün #${i + 1}: fiyat negatif olamaz';
    }
    return null;
  }

  /// Ödeme yöntemi validasyonu
  static String? validatePaymentMethod(String method) {
    const valid = ['cash', 'cardOnDelivery', 'online', 'balance'];
    if (!valid.contains(method)) {
      return 'Geçersiz ödeme yöntemi: $method. '
          'Geçerli: ${valid.join(', ')}';
    }
    return null;
  }

  /// Ücretsiz sipariş mi? (toplam 0 veya negatif ise evet)
  static bool isFreeOrder(double total) {
    return total <= 0;
  }

  /// İndirim oranı hesapla (yüzde)
  static double calculateDiscountPercentage({
    required double originalPrice,
    required double discountedPrice,
  }) {
    if (originalPrice <= 0) return 0;
    if (discountedPrice >= originalPrice) return 0;

    return ((originalPrice - discountedPrice) / originalPrice) * 100;
  }
}

void main() {
  // ===========================================================================
  // 1. ÜCRETSİZ SİPARİŞ LİMİTİ
  // ===========================================================================
  group('🎁 Ücretsiz Sipariş Limiti', () {
    test('Limit 1 olmalı (proje kuralı)', () {
      expect(OrderValidators.freeOrderLimitPerUser, equals(1));
    });

    test('Hiç ücretsiz sipariş yoksa yeni sipariş verilebilir', () {
      final error = OrderValidators.validateFreeOrderLimit(
        existingFreeOrderCount: 0,
        maxFreeOrders: 1,
      );
      expect(error, isNull);
    });

    test('Limit aşıldıysa hata mesajı dönmeli', () {
      final error = OrderValidators.validateFreeOrderLimit(
        existingFreeOrderCount: 1,
        maxFreeOrders: 1,
      );
      expect(error, isNotNull);
      expect(error, contains('hakkınızı kullandınız'));
      expect(error, contains('1'));
    });

    test('Limit 0 ise tüm ücretsiz siparişler reddedilmeli', () {
      final error = OrderValidators.validateFreeOrderLimit(
        existingFreeOrderCount: 0,
        maxFreeOrders: 0,
      );
      expect(error, isNotNull);
    });
  });

  // ===========================================================================
  // 2. SİPARİŞ TUTARI VALİDASYONU
  // ===========================================================================
  group('💰 Sipariş Tutarı Validasyonu', () {
    test('Geçerli tutar kabul edilmeli', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: 100.0,
        deliveryFee: 15.0,
        discount: 10.0,
        total: 105.0, // 100 + 15 - 10
      );
      expect(error, isNull);
    });

    test('Negatif tutar reddedilmeli', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: 100.0,
        deliveryFee: 15.0,
        discount: 0.0,
        total: -10.0,
      );
      expect(error, isNotNull);
      expect(error, contains('negatif'));
    });

    test('Negatif ara toplam reddedilmeli', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: -10.0,
        deliveryFee: 0.0,
        discount: 0.0,
        total: -10.0,
      );
      expect(error, isNotNull);
      expect(error, contains('Ara toplam'));
    });

    test('Negatif teslimat ücreti reddedilmeli', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: 100.0,
        deliveryFee: -5.0,
        discount: 0.0,
        total: 95.0,
      );
      expect(error, isNotNull);
    });

    test('Hesaplama hatası (tutar yanlış) reddedilmeli', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: 100.0,
        deliveryFee: 15.0,
        discount: 10.0,
        total: 200.0, // Yanlış! Olması gereken 105
      );
      expect(error, isNotNull);
      expect(error, contains('Toplam tutar hatalı'));
    });

    test('0 TL sipariş kabul edilmeli (ücretsiz)', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: 0.0,
        deliveryFee: 0.0,
        discount: 0.0,
        total: 0.0,
      );
      expect(error, isNull);
    });

    test('Küçük yuvarlama farkı kabul edilmeli (±0.01)', () {
      final error = OrderValidators.validateOrderAmount(
        subtotal: 100.0,
        deliveryFee: 15.0,
        discount: 10.0,
        total: 105.005, // 0.005 fark - kabul edilir
      );
      expect(error, isNull);
    });
  });

  // ===========================================================================
  // 3. TESLİMAT ADRESİ
  // ===========================================================================
  group('📍 Teslimat Adresi', () {
    test('Geçerli adres kabul edilmeli', () {
      final error = OrderValidators.validateDeliveryAddress(
        'Cizre, Şırnak, Atatürk Mahallesi, No: 123',
      );
      expect(error, isNull);
    });

    test('Boş adres reddedilmeli', () {
      expect(OrderValidators.validateDeliveryAddress(''), isNotNull);
      expect(OrderValidators.validateDeliveryAddress(null), isNotNull);
      expect(OrderValidators.validateDeliveryAddress('   '), isNotNull);
    });

    test('Çok kısa adres reddedilmeli (< 10 karakter)', () {
      final error = OrderValidators.validateDeliveryAddress('Cizre');
      expect(error, isNotNull);
      expect(error, contains('10 karakter'));
    });

    test('Çok uzun adres reddedilmeli (> 500 karakter)', () {
      final error = OrderValidators.validateDeliveryAddress('a' * 501);
      expect(error, isNotNull);
      expect(error, contains('500'));
    });
  });

  // ===========================================================================
  // 4. SİPARİŞ ÖĞELERİ
  // ===========================================================================
  group('🛒 Sipariş Öğeleri', () {
    test('Geçerli öğeler kabul edilmeli', () {
      final error = OrderValidators.validateOrderItems([
        {'product_id': 'p1', 'quantity': 2, 'price': 50.0},
        {'product_id': 'p2', 'quantity': 1, 'price': 25.0},
      ]);
      expect(error, isNull);
    });

    test('Boş liste reddedilmeli', () {
      final error = OrderValidators.validateOrderItems([]);
      expect(error, isNotNull);
      expect(error, contains('en az 1'));
    });

    test('Eksik product_id reddedilmeli', () {
      final error = OrderValidators.validateOrderItems([
        {'product_id': '', 'quantity': 1, 'price': 50.0},
      ]);
      expect(error, contains('product_id'));
    });

    test('Geçersiz miktar (0 veya negatif) reddedilmeli', () {
      final error = OrderValidators.validateOrderItems([
        {'product_id': 'p1', 'quantity': 0, 'price': 50.0},
      ]);
      expect(error, contains('0'));
    });

    test('Çok yüksek miktar (1000+) reddedilmeli', () {
      final error = OrderValidators.validateOrderItems([
        {'product_id': 'p1', 'quantity': 1000, 'price': 50.0},
      ]);
      expect(error, contains('999'));
    });

    test('Negatif fiyat reddedilmeli', () {
      final error = OrderValidators.validateOrderItems([
        {'product_id': 'p1', 'quantity': 1, 'price': -10.0},
      ]);
      expect(error, contains('fiyat'));
    });

    test('Birden fazla hata varsa ilk hatayı dönmeli', () {
      final error = OrderValidators.validateOrderItems([
        {'product_id': '', 'quantity': 0, 'price': -10.0},
      ]);
      expect(error, isNotNull);
    });
  });

  // ===========================================================================
  // 5. ÖDEME YÖNTEMİ
  // ===========================================================================
  group('💳 Ödeme Yöntemi', () {
    test('Geçerli yöntemler kabul edilmeli', () {
      expect(OrderValidators.validatePaymentMethod('cash'), isNull);
      expect(OrderValidators.validatePaymentMethod('cardOnDelivery'), isNull);
      expect(OrderValidators.validatePaymentMethod('online'), isNull);
      expect(OrderValidators.validatePaymentMethod('balance'), isNull);
    });

    test('Geçersiz yöntem reddedilmeli', () {
      final error = OrderValidators.validatePaymentMethod('bitcoin');
      expect(error, isNotNull);
      expect(error, contains('Geçersiz'));
    });
  });

  // ===========================================================================
  // 6. ÜCRETSİZ SİPARİŞ TESPİTİ
  // ===========================================================================
  group('🆓 Ücretsiz Sipariş Tespiti', () {
    test('Toplam 0 ise ücretsiz sipariş', () {
      expect(OrderValidators.isFreeOrder(0.0), isTrue);
    });

    test('Toplam negatif ise ücretsiz sipariş (kupon/indirim)', () {
      expect(OrderValidators.isFreeOrder(-5.0), isTrue);
    });

    test('Toplam pozitif ise ücretli sipariş', () {
      expect(OrderValidators.isFreeOrder(15.0), isFalse);
      expect(OrderValidators.isFreeOrder(0.01), isFalse);
    });
  });

  // ===========================================================================
  // 7. İNDİRİM YÜZDESİ HESAPLAMA
  // ===========================================================================
  group('📊 İndirim Yüzdesi', () {
    test('%20 indirim doğru hesaplanmalı', () {
      final pct = OrderValidators.calculateDiscountPercentage(
        originalPrice: 100.0,
        discountedPrice: 80.0,
      );
      expect(pct, equals(20.0));
    });

    test('İndirim yoksa 0%', () {
      final pct = OrderValidators.calculateDiscountPercentage(
        originalPrice: 100.0,
        discountedPrice: 100.0,
      );
      expect(pct, equals(0.0));
    });

    test('İndirimli fiyat > orijinal ise 0% (koruma)', () {
      final pct = OrderValidators.calculateDiscountPercentage(
        originalPrice: 100.0,
        discountedPrice: 150.0,
      );
      expect(pct, equals(0.0));
    });

    test('Orijinal fiyat 0 ise 0% (division by zero koruması)', () {
      final pct = OrderValidators.calculateDiscountPercentage(
        originalPrice: 0.0,
        discountedPrice: 50.0,
      );
      expect(pct, equals(0.0));
    });
  });

  // ===========================================================================
  // 8. SONUÇ RAPORU
  // ===========================================================================
  tearDownAll(() {
    print('\n${'=' * 60}');
    print('🛒 ORDER SERVICE VALIDATORS TEST SONUÇ RAPORU');
    print('=' * 60);
    print('✅ Sipariş validasyon kuralları test edildi');
    print('💡 Kapsam:');
    print('   - Ücretsiz sipariş limiti kontrolü');
    print('   - Tutar hesaplama doğrulaması');
    print('   - Teslimat adresi validasyonu');
    print('   - Sipariş öğeleri kontrolü');
    print('   - Ödeme yöntemi kontrolü');
    print('   - İndirim yüzdesi hesaplama');
    print('=' * 60);
  });
}
