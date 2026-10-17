import '../../../core/models/cart_model.dart';
import '../../../core/models/coupon_model.dart';
import '../../../core/models/invoice_info_model.dart';
import '../../../core/models/order_model.dart';
import '../../../models/checkout_session_model.dart';
import '../../../services/checkout_service.dart';

/// Ana sepetin satırlarından sunucu ödeme oturumu isteğini kurar.
///
/// İstek yalnız ürün kimliği, adet ve sepet satırının geldiği flaş fırsatını
/// taşır; fiyat, teslimat, indirim ve toplamı sunucu
/// (`prepare_checkout_session`) hesaplar. Sepette olmayan mağazaların
/// kupon/Gel Al seçimleri gönderilmez (sunucu onları reddederdi).
CheckoutSessionRequest buildCartCheckoutRequest({
  required List<CartItem> items,
  required String addressId,
  required PaymentMethod paymentMethod,
  required String idempotencyKey,
  Iterable<AppliedCoupon> coupons = const [],
  Iterable<String> pickupShopIds = const [],
  String? notes,
  InvoiceInfo? invoiceInfo,
}) {
  final lines = items
      .where((item) => item.productId.isNotEmpty && item.quantity > 0)
      .toList();
  final shopIds = {
    for (final item in lines)
      if (item.shopId != null) item.shopId!,
  };

  final trimmedNotes = notes?.trim();
  final invoice = invoiceInfo?.toOrderSnapshot();

  return CheckoutSessionRequest(
    items: [
      for (final item in lines)
        CheckoutItemRequest(
          productId: item.productId,
          quantity: item.quantity,
          flashSaleId: item.flashSaleId,
        ),
    ],
    addressId: addressId,
    paymentMethod: CheckoutService.paymentMethodValue(paymentMethod),
    idempotencyKey: idempotencyKey,
    couponIds: [
      for (final coupon in coupons)
        if (shopIds.contains(coupon.shopId)) coupon.id,
    ],
    pickupShopIds: [
      for (final shopId in pickupShopIds.toSet())
        if (shopIds.contains(shopId)) shopId,
    ],
    notes: (trimmedNotes == null || trimmedNotes.isEmpty) ? null : trimmedNotes,
    invoiceData: (invoice == null || invoice.isEmpty) ? null : invoice,
  );
}
