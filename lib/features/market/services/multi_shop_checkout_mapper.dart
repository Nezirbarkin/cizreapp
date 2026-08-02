import 'cart_service.dart';

/// Çok mağazalı checkout özetlerindeki doğrulanmış indirimleri sipariş
/// servisinin beklediği `shopId -> discount` sözleşmesine dönüştürür.
///
/// Bu saf fonksiyon ekran durumundan ve Supabase'den bağımsızdır; böylece
/// indirim aktarımı kaynak kod metni aranmadan davranış testiyle doğrulanabilir.
Map<String, double> buildDiscountByShop(
  Map<String, ShopCartSummary> summaries,
) {
  return {
    for (final entry in summaries.entries) entry.key: entry.value.discount,
  };
}
