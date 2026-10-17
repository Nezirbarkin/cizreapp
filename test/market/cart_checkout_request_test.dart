import 'package:cizreapp/core/models/cart_model.dart';
import 'package:cizreapp/core/models/coupon_model.dart';
import 'package:cizreapp/core/models/invoice_info_model.dart';
import 'package:cizreapp/core/models/order_model.dart';
import 'package:cizreapp/features/market/services/cart_checkout_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ana sepet → sunucu ödeme oturumu isteği. İstek hiçbir tutar taşımamalı;
/// fiyatı, teslimatı, kuponu ve Gel Al'ı `prepare_checkout_session` hesaplar.
void main() {
  CartItem item({
    required String id,
    required String productId,
    required String shopId,
    int quantity = 1,
    String? flashSaleId,
    double? flashPrice,
  }) {
    return CartItem(
      id: id,
      userId: 'user-1',
      productId: productId,
      quantity: quantity,
      createdAt: DateTime(2026, 10, 17),
      updatedAt: DateTime(2026, 10, 17),
      shopId: shopId,
      productPrice: 100,
      flashSaleId: flashSaleId,
      flashPrice: flashPrice,
    );
  }

  AppliedCoupon coupon(String id, String shopId) => AppliedCoupon(
        id: id,
        shopId: shopId,
        code: 'KOD',
        discountType: 'fixed_amount',
        discountValue: 10,
      );

  test('kalemler yalnız urun, adet ve flas firsati tasir; tutar alani yok', () {
    final request = buildCartCheckoutRequest(
      items: [
        item(id: 'c1', productId: 'p1', shopId: 's1', quantity: 2),
        item(
          id: 'c2',
          productId: 'p2',
          shopId: 's1',
          flashSaleId: 'sale-1',
          flashPrice: 80,
        ),
      ],
      addressId: 'addr-1',
      paymentMethod: PaymentMethod.cash,
      idempotencyKey: 'key-123456',
    );

    expect(request.items.map((e) => e.toJson()).toList(), [
      {'product_id': 'p1', 'quantity': 2},
      {'product_id': 'p2', 'quantity': 1, 'flash_sale_id': 'sale-1'},
    ]);
    final json = request.toJson().toString();
    for (final forbidden in [
      'price',
      'total',
      'subtotal',
      'delivery_fee',
      'discount',
      'amount',
    ]) {
      expect(json.contains(forbidden), isFalse, reason: '$forbidden gönderilmemeli');
    }
  });

  test('odeme yontemleri sunucu oturum degerlerine cevrilir', () {
    String methodFor(PaymentMethod m) => buildCartCheckoutRequest(
          items: [item(id: 'c1', productId: 'p1', shopId: 's1')],
          addressId: 'a',
          paymentMethod: m,
          idempotencyKey: 'key-123456',
        ).paymentMethod;

    expect(methodFor(PaymentMethod.cash), 'cash');
    expect(methodFor(PaymentMethod.cardOnDelivery), 'card_on_delivery');
    expect(methodFor(PaymentMethod.balance), 'balance');
    expect(methodFor(PaymentMethod.online), 'online');
  });

  test('sepette olmayan magazanin kuponu ve Gel Al secimi gonderilmez', () {
    final request = buildCartCheckoutRequest(
      items: [
        item(id: 'c1', productId: 'p1', shopId: 's1'),
        item(id: 'c2', productId: 'p2', shopId: 's2'),
      ],
      addressId: 'addr-1',
      paymentMethod: PaymentMethod.balance,
      idempotencyKey: 'key-123456',
      coupons: [coupon('k1', 's1'), coupon('k-eski', 's9')],
      pickupShopIds: ['s2', 's2', 's9'],
    );

    expect(request.couponIds, ['k1']);
    expect(request.pickupShopIds, ['s2']);
  });

  test('bos not ve adetsiz satirlar atlanir, fatura anlik goruntusu gider', () {
    final request = buildCartCheckoutRequest(
      items: [
        item(id: 'c1', productId: 'p1', shopId: 's1', quantity: 3),
        item(id: 'c2', productId: 'p2', shopId: 's1', quantity: 0),
      ],
      addressId: 'addr-1',
      paymentMethod: PaymentMethod.cash,
      idempotencyKey: 'key-123456',
      notes: '   ',
      invoiceInfo: const InvoiceInfo(
        type: InvoiceType.individual,
        fullName: 'Test Musteri',
      ),
    );

    expect(request.items, hasLength(1));
    expect(request.notes, isNull);
    expect(request.invoiceData?['invoice_full_name'], 'Test Musteri');

    final withNote = buildCartCheckoutRequest(
      items: [item(id: 'c1', productId: 'p1', shopId: 's1')],
      addressId: 'addr-1',
      paymentMethod: PaymentMethod.cash,
      idempotencyKey: 'key-123456',
      notes: '  Kapı kodu 12  ',
    );
    expect(withNote.notes, 'Kapı kodu 12');
  });
}
