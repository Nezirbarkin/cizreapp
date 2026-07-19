// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/features/shop/services/order_service.dart';

void main() {
  group('OrderService - Ücretsiz (0 TL) sipariş limiti', () {
    test('freeOrderLimitPerUser kullanıcı başına 1 olmalı', () {
      expect(OrderService.freeOrderLimitPerUser, equals(1));
    });

    test('limit pozitif bir değer olmalı (0 veya negatif limit tüm siparişleri engeller)', () {
      expect(OrderService.freeOrderLimitPerUser, greaterThan(0));
    });
  });
}
