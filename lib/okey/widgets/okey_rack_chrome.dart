/// Ahşap ıstakanın İÇ SÜSLEMESİNİN toplam dikey yüksekliği.
///
/// TEK KAYNAK: Hem ıstakanın kendi padding/kenarlık değerleri hem de masa
/// ölçülerinin (OkeyTableMetrics) satır yüksekliği hesabı bu sabiti kullanır.
///
/// NEDEN AYRI BİR DOSYA: Bu sayı önce iki yerde ayrı ayrı yazılıydı. Istakanın
/// padding'leri küçültülürken sabit güncellenmeyi unutunca ıstaka kendi içinde
/// 1 piksel taştı. Tek kaynağa bağlanınca o hata sınıfı ortadan kalktı.
///
/// ## Sayılar NEYE karşılık geliyor (2026-09-07: "gerçek görünümlü ıstaka")
///
/// Gerçek bir ıstaka iki KADEMELİ bir takozdur; oyuncu onu önden-üstten görür
/// ve taşların ARASINDA kalan üç şerit dışında hiçbir yerini görmez:
///
/// ```
///   ┌──────────────────────────┐ ← arka tahtanın üst pahı (topBorder)
///   │▓▓▓▓ ARKA SIRA TAŞLARI ▓▓▓│
///   ├──────────────────────────┤ ← ARA RAF: arka kademenin ön çıtası (rowGap)
///   │▓▓▓▓ ÖN SIRA TAŞLARI  ▓▓▓▓│
///   ├──────────────────────────┤ ← ÖN ÇITA: taşların dayandığı dudak (ledge)
///   └──────────────────────────┘   + öne düşen ön yüz
/// ```
///
/// Üç şerit de ANLAMLI kalınlıkta olmalı: 2 piksellik bir ara boşluğa ne pah,
/// ne gölge sığar — takoz o yüzden "düz bir tahta" gibi okunuyordu. Kalınlık
/// bedava değil (ıstakanın dikey bütçesinden çıkar), bu yüzden
/// OkeyTableMetrics'in ıstakaya ayırdığı pay da aynı ölçüde artırıldı; taş
/// boyu değişmedi.
library;

/// Arka tahtanın taşların üstünde kalan pahı.
const double okeyRackTopBorder = 4;

const double okeyRackVerticalPadding = 3;

/// İKİ SIRA ARASINDAKİ ARA RAF — arka kademenin ön çıtası.
///
/// Bir "boşluk" değil, ıstakanın kendi parçasıdır: üstünde ışık alan bir pah,
/// altında ön sıraya düşen gölge vardır (bkz. OkeyRackBodyPainter).
const double okeyRackRowGap = 6;

/// Taşların dibinin oturduğu ÖN ÇITANIN yüksekliği.
///
/// Bu şerit ıstakaya DERİNLİK veren parçadır (bkz. OkeyRackPanel): taşlar
/// artık düz bir tahtanın üstünde yüzmüyor, bir rafın üzerinde duruyor.
/// Yüksekliği chrome hesabına DAHİL — dahil olmasaydı ıstaka kendi içinde
/// tam bu kadar taşardı.
const double okeyRackLedgeHeight = 9;

const double okeyRackChromeHeight =
    okeyRackTopBorder +
    (okeyRackVerticalPadding * 2) +
    okeyRackRowGap +
    okeyRackLedgeHeight;
