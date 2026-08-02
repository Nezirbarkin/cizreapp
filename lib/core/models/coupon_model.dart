/// Müşteri tarafında sepete uygulanan kuponun client-side state modeli.
///
/// `validate_coupon` RPC'sinin döndüğü satır şu kolonları içerir:
///   id, discount_type, discount_value, maximum_discount_amount,
///   minimum_order_amount
///
/// Biz bunlara ek olarak kuponun `code`'unu ve `shopId`'sini de saklarız;
/// checkout ekranında rozet/iptal için gerekir, `use_coupon` RPC'si
/// yalnızca `couponId` istediği için `code` zorunlu değildir ama UI için
/// kullanışlıdır.
class AppliedCoupon {
  /// shop_coupons.id — use_coupon RPC'sine p_coupon_id olarak geçilecek.
  final String id;
  final String shopId;
  final String code;
  final String? title;
  final String discountType; // 'fixed_amount' | 'percentage'
  final double discountValue;
  final double? maximumDiscountAmount;
  final double minimumOrderAmount;

  const AppliedCoupon({
    required this.id,
    required this.shopId,
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.maximumDiscountAmount,
    this.minimumOrderAmount = 0,
    this.title,
  });

  /// `validate_coupon` RPC'sinden dönen satır haritasından inşa eder.
  /// Kolon isimleri migration 20260722000003_fix_coupon_validation.sql ile
  /// birebir aynıdır (snake_case).
  factory AppliedCoupon.fromRpcRow(Map<String, dynamic> row, {
    required String shopId,
    required String code,
  }) {
    return AppliedCoupon(
      id: row['id'].toString(),
      shopId: shopId,
      code: code,
      title: row['title'] as String?,
      discountType: (row['discount_type'] as String?) ?? 'fixed_amount',
      discountValue: (row['discount_value'] as num?)?.toDouble() ?? 0,
      maximumDiscountAmount:
          (row['maximum_discount_amount'] as num?)?.toDouble(),
      minimumOrderAmount:
          (row['minimum_order_amount'] as num?)?.toDouble() ?? 0,
    );
  }

  /// Dükkan-bazlı ara toplama (ürünlerin `effectivePrice` toplamı)
  /// göre uygulanan indirim tutarını hesaplar.
  ///
  /// - `fixed_amount`: doğrudan `discountValue`, ama subtotal'i aşamaz
  ///   ve `minimumOrderAmount` zaten validate_coupon'da kontrol edildi.
  /// - `percentage`: `subtotal * discountValue / 100`,
  ///   `maximumDiscountAmount` ile sınırlanır.
  double discountFor(double shopSubtotal) {
    if (shopSubtotal <= 0) return 0;
    double d;
    if (discountType == 'percentage') {
      d = shopSubtotal * (discountValue / 100.0);
      if (maximumDiscountAmount != null && d > maximumDiscountAmount!) {
        d = maximumDiscountAmount!;
      }
    } else {
      d = discountValue;
    }
    if (d > shopSubtotal) d = shopSubtotal;
    if (d < 0) d = 0;
    return d;
  }

  /// UI rozeti için: "%10 indirim" veya "₺25 indirim"
  String get label {
    if (discountType == 'percentage') {
      return '%${discountValue.toStringAsFixed(0)} indirim';
    }
    return '₺${discountValue.toStringAsFixed(0)} indirim';
  }
}
