/// Dijital (SMM) sipariş fiyatı — sunucunun `create_digital_order_with_points`
/// hesabının BİREBİR istemci karşılığı (Görev 3.6).
///
/// Sunucu:
///   birim  = round(price_per_1000 / 1000, 4)
///   toplam = round(birim × adet, 2)
///   puan   ≤ floor(toplam_kuruş × max_points_coverage_percent / 100) kuruş
///
/// `price_per_1000` sütunu numeric(12,2) olduğundan hesap kuruş/on-binde-bir
/// tamsayılarıyla yapılır; kayan nokta yuvarlama farkı oluşmaz. PostgreSQL
/// `round()` sıfırdan uzağa yuvarlar — pozitif değerlerde (x + yarım) ~/ birim.
class DigitalOrderQuote {
  /// 1000 adetlik fiyat, kuruş.
  final int pricePer1000Cents;

  /// Adet başı fiyat, 1/10000 TL (sunucudaki 4 haneli `unit_price`).
  final int unitPriceE4;
  final int quantity;

  /// Sunucudaki `gross_total_try`, kuruş.
  final int totalCents;

  /// Ürün puana uygunsa puanla ödenebilecek en fazla kısım (bakiye yeterliyse), kuruş.
  final int maxPointsCents;

  const DigitalOrderQuote({
    required this.pricePer1000Cents,
    required this.unitPriceE4,
    required this.quantity,
    required this.totalCents,
    this.maxPointsCents = 0,
  });

  double get total => totalCents / 100;
  double get pricePer1000 => pricePer1000Cents / 100;
  double get maxPoints => maxPointsCents / 100;
}

class DigitalOrderPricing {
  DigitalOrderPricing._();

  /// Geçerli adet için fiyat; fiyat bilinmiyorsa ya da adet ≤ 0 ise null.
  static DigitalOrderQuote? quote({
    required double? pricePer1000,
    required int quantity,
    bool pointsEligible = false,
    int maxPointsCoveragePercent = 100,
  }) {
    if (pricePer1000 == null || pricePer1000 < 0 || quantity <= 0) return null;
    final ppkCents = (pricePer1000 * 100).round();
    // birim (4 hane) = ppk / 1000 → on-binde-bir TL = ppk × 10 = kuruş / 10
    final unitE4 = (ppkCents + 5) ~/ 10;
    // toplam (2 hane): on-binde-bir × adet → kuruş = / 100
    final totalCents = (unitE4 * quantity + 50) ~/ 100;
    final coverage = maxPointsCoveragePercent.clamp(0, 100);
    final maxPoints = pointsEligible ? (totalCents * coverage) ~/ 100 : 0;
    return DigitalOrderQuote(
      pricePer1000Cents: ppkCents,
      unitPriceE4: unitE4,
      quantity: quantity,
      totalCents: totalCents,
      maxPointsCents: maxPoints,
    );
  }

  /// "₺1.234,50" / "₺0,04" — küçük tutarlar kaybolmasın diye her zaman 2 hane.
  static String formatTry(int cents) {
    final negative = cents < 0;
    final abs = cents.abs();
    final lira = abs ~/ 100;
    final kurus = (abs % 100).toString().padLeft(2, '0');
    final digits = lira.toString();
    final grouped = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
      grouped.write(digits[i]);
    }
    return '${negative ? '-' : ''}₺$grouped,$kurus';
  }
}
