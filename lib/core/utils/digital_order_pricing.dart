/// Dijital (SMM) sipariş fiyatı — sunucunun `create_digital_order_with_points`
/// hesabının BİREBİR istemci karşılığı (Görev 3.6).
///
/// Sunucu (20261016000011):
///   toplam = round(price_per_1000 × adet / 1000, 2)
///   birim  = round(price_per_1000 / 1000, 6)  (yalnız kayıt; toplamı etkilemez)
///   puan   ≤ floor(toplam_kuruş × max_points_coverage_percent / 100) kuruş
///
/// Eskiden birim önce 4 haneye yuvarlanıp adetle çarpılıyordu; ucuz serviste
/// (0,24 TL / 1000 adet) birim 0,0002'ye kırpılıp 1000 adet 0,20 TL çıkıyordu.
///
/// `price_per_1000` sütunu numeric(12,2) olduğundan hesap kuruş/milyonda-bir
/// tamsayılarıyla yapılır; kayan nokta yuvarlama farkı oluşmaz. PostgreSQL
/// `round()` sıfırdan uzağa yuvarlar — pozitif değerlerde (x + yarım) ~/ birim.
class DigitalOrderQuote {
  /// 1000 adetlik fiyat, kuruş.
  final int pricePer1000Cents;

  /// Adet başı fiyat, 1/1000000 TL (sunucudaki 6 haneli `unit_price`).
  final int unitPriceE6;
  final int quantity;

  /// Sunucudaki `gross_total_try`, kuruş.
  final int totalCents;

  /// Ürün puana uygunsa puanla ödenebilecek en fazla kısım (bakiye yeterliyse), kuruş.
  final int maxPointsCents;

  const DigitalOrderQuote({
    required this.pricePer1000Cents,
    required this.unitPriceE6,
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
    // birim (6 hane) = ppk / 1000 → milyonda-bir TL = kuruş × 10 (kesirsiz)
    final unitE6 = ppkCents * 10;
    // toplam (2 hane) = ppk × adet / 1000 → kuruş = ppk_kuruş × adet / 1000
    final totalCents = (ppkCents * quantity + 500) ~/ 1000;
    final coverage = maxPointsCoveragePercent.clamp(0, 100);
    final maxPoints = pointsEligible ? (totalCents * coverage) ~/ 100 : 0;
    return DigitalOrderQuote(
      pricePer1000Cents: ppkCents,
      unitPriceE6: unitE6,
      quantity: quantity,
      totalCents: totalCents,
      maxPointsCents: maxPoints,
    );
  }

  /// Paket (sabit fiyat) siparişi: sunucu `brüt = round(price, 2)`, adet 1.
  /// Fiyat bilinmiyorsa ya da 0 / negatifse null.
  static DigitalOrderQuote? quotePackage({
    required double? price,
    bool pointsEligible = false,
    int maxPointsCoveragePercent = 100,
  }) {
    if (price == null || price <= 0) return null;
    final totalCents = (price * 100).round();
    final coverage = maxPointsCoveragePercent.clamp(0, 100);
    final maxPoints = pointsEligible ? (totalCents * coverage) ~/ 100 : 0;
    return DigitalOrderQuote(
      pricePer1000Cents: 0,
      unitPriceE6: totalCents * 10000,
      quantity: 1,
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
