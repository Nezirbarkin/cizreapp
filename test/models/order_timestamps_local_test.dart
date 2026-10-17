// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';

import '../../lib/core/models/order_model.dart';
import '../../lib/core/models/shop_review_model.dart';
import '../helpers/test_helpers.dart';

/// Ekranlar sipariş/yorum saatini `createdAt.hour` gibi alanlardan okuyor.
/// Model UTC bırakırsa sunucunun yazdığı saat (now()) Türkiye'de 3 saat geri
/// görünüyordu; ayrıştırırken yerel saate çevrilir (an değişmez).
void main() {
  test('Order zaman damgaları yerel saatte, an aynı', () {
    final json = TestHelpers.createMockOrderJson()
      ..['created_at'] = '2026-10-17T09:30:00+00:00'
      ..['delivered_at'] = '2026-10-17T10:00:00+00:00';
    final order = Order.fromJson(json);

    final utc = DateTime.utc(2026, 10, 17, 9, 30);
    expect(order.createdAt.isUtc, isFalse);
    expect(order.createdAt.isAtSameMomentAs(utc), isTrue);
    expect(order.createdAt.hour, utc.toLocal().hour);
    expect(order.deliveredAt!.isUtc, isFalse);
  });

  test('ShopReview zaman damgaları yerel saatte', () {
    final review = ShopReview.fromJson({
      'id': 'r1',
      'shop_id': 's1',
      'user_id': 'u1',
      'rating': 5,
      'comment': 'iyi',
      'created_at': '2026-10-17T21:30:00+00:00',
      'updated_at': '2026-10-17T21:30:00+00:00',
      'seller_reply': 'teşekkürler',
      'seller_replied_at': '2026-10-17T22:00:00+00:00',
    });
    expect(review.createdAt.isUtc, isFalse);
    expect(
      review.createdAt.isAtSameMomentAs(DateTime.utc(2026, 10, 17, 21, 30)),
      isTrue,
    );
    expect(review.sellerRepliedAt!.isUtc, isFalse);
  });
}
