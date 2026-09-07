import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../engine/okey_rack_layout.dart';
import 'okey_rack_chrome.dart';

/// 101 Okey masasının ÖLÇÜ SÖZLEŞMESİ — ekranın tamamından türetilir.
///
/// ## Düzen v4 (2026-09) — referans masa yerleşimi
///
/// ```
///  ┌──────────────────────── üst şerit ───────────────────────────────┐
///  │ [🪙 4.500][BONUS AL]     ● KARŞIDAKİ ●      [SATIN AL][💬][⌄]   │
///  ├───┬──────────────────────────────┬──────┬──────┬───┬────────────┤
///  │ ▭ │                              │ Tek  │      │ ▭ │  ← ıskarta │
///  │ ▐ │      A Ç I L A N   P E R     │Yardım│ ek   │ ▐ │  ← levha   │
///  │ S │        (geniş bölme)         │Katla.│bölme │ S │            │
///  │ O │                              │ 1 El │      │ A │            │
///  │ L │                              │ ▭ ▭  │      │ Ğ │            │
///  │ ▭ │                              │  16  │      │ ▭ │  ← ıskarta │
///  ├───┴──────────────────────────────┴──────┴──────┴───┴────────────┤
///  │ [SERİ AÇ][ÇİFT AÇ][İŞLE][AT]     ● BEN ●  (0)                   │
///  ├──────────────────────────── süre ───────────────────────────────┤
///  │      [ÇİFT│███████ I S T A K A M ███████│SERİ]                 │
///  │       DİZ]│                             │DİZ]                    │
///  └──────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## v3'ten farkı ve NEDENİ
///
/// v3'te masa ahşap raylı bir keçeydi ve dört oyuncu kartı keçenin dört
/// kenarına dağılmıştı; ıskartalar kartların yanında duruyordu. Referans
/// masada ise ıskartalar KÖŞELERDEDİR ve bu tesadüf değil, oyunun yönüdür:
/// her ıskarta, onu ATAN ile onu ALAN oyuncunun ARASINDAKİ köşede durur.
/// Sol alt köşe = solumdakinin attığı (ben alırım), sağ alt köşe = benim
/// attığım (sağımdaki alır). Yerleşim böylece kuralı tarif eder.
///
/// Dizme araçları (SERİ DİZ / ÇİFT DİZ) da konsoldan ISTAKANIN İKİ UCUNA
/// taşındı: ıstakayı dizen düğme, ıstakanın kendisine bitişik durmalı.
///
/// ## Taşma garantisi
///
/// Dikey bütçe tanım gereği kapalıdır:
/// `masa + süre çizgisi + ıstaka = ekran yüksekliği`
/// ve masanın içi de öyle: `üst şerit + orta + konsol = masa yüksekliği`.
/// Her bölge Positioned/SizedBox ile AÇIK ölçü alır; kutunun içi sığmazsa
/// FittedBox küçültür. Row/Column taşma sınıfı yapısal olarak kalkar.
///
/// ## Taş oranı
///
/// Zincir her zaman "önce satır yüksekliği, sonra ondan türeyen genişlik"
/// yönünde kurulur. Tersi (genişlikten yüksekliğe) taşları yatık
/// dikdörtgenlere çeviren eski hataydı.
@immutable
class OkeyTableMetrics {
  /// Masa alanının (ekranın) ölçüleri.
  final double width;
  final double height;

  /// Alttaki ahşap ıstakanın yüksekliği (iç süsleme dahil).
  final double rackHeight;

  /// Istakadaki BİR taş satırının yüksekliği.
  final double rackRowHeight;

  /// Istakanın İKİ UCUNDAKİ dizme düğmesinin genişliği.
  final double rackCapWidth;

  /// Masanın ALT kenarındaki kontrol şeridinin yüksekliği.
  final double consoleHeight;

  /// Masanın ÜST kenarındaki bilgi şeridinin yüksekliği.
  final double topStripHeight;

  /// Sol/sağ kenar sütununun genişliği (ıskarta + dikey oyuncu levhası).
  final double sidePodWidth;

  /// Per alanının sağındaki bilgi sütununun genişliği (mod rozetleri,
  /// gösterge, deste).
  final double infoColumnWidth;

  /// Bilgi sütununun sağındaki EK per bölmesinin genişliği.
  final double miniBayWidth;

  /// Bir ıskarta taşının genişliği (yüksekliği [tileAspect]'ten türer).
  final double discardTileWidth;

  /// Masaya AÇILAN perlerdeki taşın ÜST SINIR genişliği.
  final double meldTileWidth;

  /// Gösterge/okey/deste sütunundaki taşın genişliği.
  final double islandTileWidth;

  /// Oyuncu avatarının çapı.
  final double avatarSize;

  /// Dar/kısa ekran: yazılar ve boşluklar küçülür.
  final bool compact;

  const OkeyTableMetrics._({
    required this.width,
    required this.height,
    required this.rackHeight,
    required this.rackRowHeight,
    required this.rackCapWidth,
    required this.consoleHeight,
    required this.topStripHeight,
    required this.sidePodWidth,
    required this.infoColumnWidth,
    required this.miniBayWidth,
    required this.discardTileWidth,
    required this.meldTileWidth,
    required this.islandTileWidth,
    required this.avatarSize,
    required this.compact,
  });

  /// Gerçek bir okey taşının genişlik/yükseklik oranı.
  ///
  /// TEK KAYNAK: ıstaka taşı, ıskarta taşı, ada taşı ve masaya açılan per
  /// taşı — hepsi bunu kullanır, böylece aynı oyunda üç farklı biçimde taş
  /// görünmez.
  static const double tileAspect = 0.74;

  /// Istakanın iç süslemesinin toplam yüksekliği.
  static const double rackChrome = okeyRackChromeHeight;

  /// Istakanın hemen üstündeki süre çizgisinin yüksekliği.
  static const double timerBarHeight = 4;

  /// Istakanın yatay iç dolgusu (iki kenar toplamı).
  static const double _rackHorizontalPadding = 12;

  /// Masadaki bölgeler arasındaki standart boşluk.
  static const double gap = 6;

  /// Dizme düğmesi ile ıstakanın ARASINDAKİ boşluk (kullanıcı isteği,
  /// 2026-09-07: "seri diz, çift diz takoza biraz daha yakınlaştır").
  ///
  /// Masanın genel boşluğundan ([gap]) küçüktür ve olması gereken de budur:
  /// düğme ıstakanın bir PARÇASI gibi okunmalı, yanındaki ayrı bir kutu gibi
  /// değil. Sıfır yapılmadı — bitişik dururlarsa düğmenin kendi kenarlığı
  /// ıstakanın kenarıyla birleşip tek bir bulanık şeride dönüşüyor.
  static const double rackCapGap = 3;

  /// En küçük desteklenen ıstaka satır yüksekliği.
  static const double _minRowHeight = 18;

  /// En büyük ıstaka satır yüksekliği — EKRANLA BİRLİKTE BÜYÜR.
  ///
  /// Sabit bir tavan tablette ıstakayı 1280px'lik bir masanın ortasında
  /// 790px'lik bir çubuğa indiriyordu: taşlar telefonla aynı boyda kalıyor,
  /// kazanılan yer boşa gidiyordu.
  static double _maxRowHeightFor(double h) => math.max(66, h * 0.145);

  /// Istaka ekran yüksekliğinin en fazla bu kadarını alır.
  ///
  /// 2026-09-07: 0,32 → 0,34. Gerçekçi takoz için ıstakanın iç süslemesi
  /// 17px'ten 25px'e çıktı (ara raf ve ön çıta artık gerçek birer kademe,
  /// bkz. okey_rack_chrome.dart). Oran sabit kalsaydı bu 8 piksel doğrudan
  /// TAŞLARDAN kısılırdı — süslemeyi taş boyuyla ödemek, kazanılan
  /// gerçekçiliği anlamsız kılardı. Pay ise masanın en bol olduğu yerden,
  /// per tablasının boyundan gelir.
  static const double _rackHeightRatio = 0.34;

  /// Konsoldaki kontrollerin arasındaki standart boşluk.
  static const double consoleGap = 7;

  /// Aksiyon butonları ile ıskarta kutusu arasındaki GÜVENLİK boşluğu.
  ///
  /// Kozmetik değil, HATA ÖNLEME: ıskarta bir bırakma hedefidir; taşı oraya
  /// sürüklerken parmak son anda kayarsa bitişikteki "ÇİFT AÇ"a basmak eli
  /// açmak gibi GERİ ALINAMAZ bir hamleyi tetikler. Regresyon testi bu
  /// mesafenin 24px'ten büyük kalmasını şart koşuyor.
  static const double discardSafeGap = 34;

  factory OkeyTableMetrics.from(BoxConstraints c) {
    final w = (c.hasBoundedWidth && c.maxWidth > 0) ? c.maxWidth : 900.0;
    final h = (c.hasBoundedHeight && c.maxHeight > 0) ? c.maxHeight : 420.0;

    // ---- ISTAKA -----------------------------------------------------------
    // Alt şerit ıstakanın ve iki ucundaki dizme düğmesinindir. Satır
    // yüksekliği ya kalan genişlikten (16 slot yan yana) ya da yükseklik
    // bütçesinden gelir — hangisi küçükse.
    final capW = (w * 0.062).clamp(44.0, 112.0).toDouble();
    final rackTrack = math.max(w - capW * 2 - rackCapGap * 2, 80.0);

    final byWidth =
        ((rackTrack - _rackHorizontalPadding) / OkeyRackLayout.slotsPerRow) /
        tileAspect;
    final byHeight = (h * _rackHeightRatio - rackChrome) / 2;

    var rowH = math
        .min(byWidth, byHeight)
        .clamp(_minRowHeight, _maxRowHeightFor(h))
        .toDouble();

    // Son güvenlik ağı: ıstaka hiçbir koşulda ekranın yarısını geçmez.
    final maxRack = h * 0.5;
    if (rowH * 2 + rackChrome > maxRack) {
      rowH = math.max((maxRack - rackChrome) / 2, 0);
    }

    final rackH = rowH * 2 + rackChrome;

    // ---- MASA (ıstakanın üstünde kalan her şey) ---------------------------
    final boardH = math.max(h - rackH - timerBarHeight, 0.0);
    final short = math.min(w, boardH);

    // Üst şerit: altın sayacı + bonus, karşıdaki oyuncu, mağaza + ikonlar.
    final topStrip = (h * 0.095).clamp(28.0, 50.0).toDouble();

    // Konsol: hamle düğmeleri + kendi kartım + skor balonu. Dokunulabilir
    // kalmalı (>=34px) ama masayı yutmamalı.
    final console = (h * 0.095).clamp(32.0, 50.0).toDouble();

    final avatar = (short * 0.115).clamp(22.0, 44.0).toDouble();

    // ISKARTA TAŞI: hem genişlikten hem yükseklikten sınırlanır. Yalnızca
    // ikisinin küçüğüne bağlanınca, ıstaka masanın yüksekliğini kısınca
    // ıskartalar da gereksiz yere küçülüyordu.
    final discardW = math
        .min(w * 0.040, boardH * 0.20)
        .clamp(20.0, 44.0)
        .toDouble();

    // Kenar sütunu: içine ıskarta taşı + dikey oyuncu levhası girer.
    final side = math
        .max((w * 0.078).clamp(46.0, 96.0).toDouble(), discardW + 10)
        .toDouble();

    final infoW = (w * 0.088).clamp(52.0, 118.0).toDouble();
    final miniW = (w * 0.075).clamp(40.0, 100.0).toDouble();

    // Bilgi sütunundaki taş HEM sütunun genişliğinden HEM de sütunun
    // yüksekliğinden kısılır: iki taş yan yana durur ve altlarında deste
    // taşı için de yer kalmalıdır.
    final infoBodyH = math.max(boardH - topStrip - console - 8, 40.0);
    final islandW = math
        .min(infoW * 0.44, infoBodyH * 0.20 * tileAspect)
        .clamp(13.0, 46.0)
        .toDouble();

    return OkeyTableMetrics._(
      width: w,
      height: h,
      rackHeight: rackH,
      rackRowHeight: rowH,
      rackCapWidth: capW,
      consoleHeight: console,
      topStripHeight: topStrip,
      sidePodWidth: side,
      infoColumnWidth: infoW,
      miniBayWidth: miniW,
      discardTileWidth: discardW,
      // Masadaki taş ELİMDEKİ taştan büyük olamaz: uzaktaki masa yakındaki
      // elden büyük görünürse derinlik hissi tersine döner.
      //
      // 2026-09-05 (1): katsayı 0,92 → 0,68, tavan 48 → 34.
      // 2026-09-05 (2): 0,68 → 0,50, tavan 34 → 26 — kullanıcı aynı isteği
      // TEKRAR bildirdi ("masadaki perlerin taşları küçült"). İlk indirim
      // yetmemişti çünkü tipik bir telefonda ıstaka satırı ~66px'dir ve
      // 66 × 0,74 × 0,68 ≈ 33px zaten tavana dayanıyordu: masada iki-üç per
      // varken taşlar hâlâ ıstaka taşının üçte ikisi kadar duruyordu.
      //
      // Bu bir ÜST SINIRDIR; asıl ölçüyü OkeyBoardLayout alana göre çözer.
      // Sınırı indirmek, masada az per varken taşların gereksizce şişmesini
      // engeller — dolu masada zaten motor küçültüyordu, yani per sayısı
      // arttıkça taş boyu ZIPLIYORDU.
      meldTileWidth: (rowH * tileAspect * 0.50).clamp(12.0, 26.0).toDouble(),
      islandTileWidth: islandW,
      avatarSize: avatar,
      compact: boardH < 230 || w < 700,
    );
  }

  // ---------------------------------------------------------------------
  // ISTAKA
  // ---------------------------------------------------------------------

  /// Istakadaki BİR taşın ölçüsü.
  double get rackTileHeight => rackRowHeight;
  double get rackTileWidth => rackRowHeight * tileAspect;

  /// Istakanın GERÇEKTE kapladığı genişlik.
  double get rackWidth =>
      (rackTileWidth * OkeyRackLayout.slotsPerRow) + _rackHorizontalPadding;

  /// Istakanın EN FAZLA genişliği — iki dizme düğmesi dışarıda kalır.
  double get rackMaxWidth =>
      math.max(width - rackCapWidth * 2 - rackCapGap * 2, 80.0);

  // ---------------------------------------------------------------------
  // MASA BÖLGELERİ
  // ---------------------------------------------------------------------

  /// Masanın (ıstaka ve süre çizgisi hariç) yüksekliği.
  double get boardAreaHeight =>
      math.max(height - rackHeight - timerBarHeight, 0);

  /// Açılan perlere kalan yükseklik: masa − üst şerit − konsol.
  double get meldAreaHeight =>
      math.max(boardAreaHeight - topStripHeight - consoleHeight - 8, 0);

  /// Açılan perlere kalan genişlik: masa − kenar sütunları − bilgi sütunu −
  /// ek bölme − aradaki boşluklar.
  double get meldAreaWidth => math.max(
    width - sidePodWidth * 2 - infoColumnWidth - miniBayWidth - gap * 6,
    80,
  );

  /// Iskarta taşının yüksekliği.
  double get discardTileHeight => discardTileWidth / tileAspect;

  /// Masaya açılan per taşının yüksekliği.
  double get meldTileHeight => meldTileWidth / tileAspect;

  /// Bilgi sütunundaki taşın yüksekliği.
  double get islandTileHeight => islandTileWidth / tileAspect;

  /// Sağdaki bilgi sütununun azami genişliği (geriye dönük ad).
  double get islandMaxWidth => infoColumnWidth;

  /// Üst şeridin sol ucundaki altın + bonus grubunun genişliği.
  double get hudColumnWidth => (width * 0.28).clamp(120.0, 300.0).toDouble();

  // ---------------------------------------------------------------------
  // KONSOL (masanın alt kenarı)
  // ---------------------------------------------------------------------

  /// Konsoldaki bir butonun yüksekliği.
  double get actionButtonHeight => (consoleHeight - 6).clamp(28.0, 46.0);

  /// SERİ DİZ / ÇİFT DİZ düğmelerinin yüksekliği — artık ıstakanın kendi
  /// yüksekliğinden türer, çünkü ıstakanın iki ucunda dururlar.
  double get sortButtonHeight => rackHeight;

  /// Konsoldaki kimlik kartımın genişliği.
  double get myPodWidth => (width * 0.20).clamp(96.0, 260.0).toDouble();

  /// KENDİ ıskarta taşım — diğer üç ıskartayla AYNI ölçüdedir.
  ///
  /// v3'te konsolun içinde durduğu için küçültülüyordu; artık sağ kenar
  /// sütununun dibinde, tam da sağımdaki oyuncuyla aramdaki köşede durur.
  double get myDiscardTileWidth => discardTileWidth;

  /// Kendi ıskarta kutumun genişliği.
  double get myDiscardWidth => myDiscardTileWidth + 8;
}
