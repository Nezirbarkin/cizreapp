import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Görev 3.6 — dijital sipariş ekranında anlık toplam: ekran kartı durumdaki
/// miktarla çizer, üst sınıra çekilen miktar da durumu günceller (eskiden
/// setState'siz atanıyordu), fiyat formülü sunucudakiyle aynı kalır.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');

  test('ürün detayı kartı durumdaki miktarla çizer; düğmede toplam', () {
    final screen = read('lib/features/market/screens/product_detail_screen.dart');
    expect(screen, contains('DigitalOrderTotalCard('));
    expect(screen, contains('quantity: _digitalQuantity,'));
    expect(screen, contains('setState(() => _digitalQuantity = maxQ);'));
    expect(screen, contains('FilteringTextInputFormatter.digitsOnly'));
    expect(screen, contains('_digitalBuyLabel(product)'));
  });

  test('istemci formülü sunucunun create_digital_order_with_points hesabını izler', () {
    final pricing = read('lib/core/utils/digital_order_pricing.dart');
    expect(pricing, contains('final unitE4 = (ppkCents + 5) ~/ 10;'));
    expect(pricing, contains('final totalCents = (unitE4 * quantity + 50) ~/ 100;'));
    expect(pricing, contains('(totalCents * coverage) ~/ 100'));
  });
}
