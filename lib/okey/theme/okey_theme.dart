import 'package:flutter/material.dart';

import '../engine/okey_tile.dart';

/// 101 Okey modülünün TEK renk kaynağı.
///
/// Önceden her widget kendi rengini elle yazıyordu (aynı fildişi taş
/// gradyanı, aynı lacivert zemin, aynı taş renkleri 4-6 dosyada birebir
/// tekrarlanmıştı) — bir tonu değiştirmek her seferinde tüm dosyaları
/// taramayı gerektiriyordu. Artık her yer buradan okur.
abstract final class OkeyColors {
  // --- Zeminler --------------------------------------------------------
  /// Oyun masası ekranının Scaffold arka planı.
  static const tableBackground = Color(0xFF10495F);

  /// Lobi/oda/puan/sonuç gibi diğer okey ekranlarının Scaffold arka planı.
  static const screenBackground = Color(0xFF0E3A4F);

  /// AppBar / footer / diyalog gibi daha koyu vurgu yüzeyleri.
  static const surfaceDark = Color(0xFF0A2C3C);

  /// Tahta (per/grup alanı) keçe rengi.
  static const felt = Color(0xFF0E3A4F);

  // --- Taş gövdesi -------------------------------------------------------
  static const tileIvoryLight = Color(0xFFFFFDF7);
  static const tileIvoryDark = Color(0xFFF2ECDD);
  static const tileGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tileIvoryLight, tileIvoryDark],
  );

  // --- Taş renkleri (suit) -----------------------------------------------
  static const tileRed = Color(0xFFE53935);
  static const tileYellow = Color(0xFFF9A825);
  static const tileBlack = Color(0xFF212121);
  static const tileBlue = Color(0xFF1E88E5);
  static const falseJoker = Colors.deepPurple;

  static Color tileColorFor(OkeyColor c) {
    switch (c) {
      case OkeyColor.red:
        return tileRed;
      case OkeyColor.yellow:
        return tileYellow;
      case OkeyColor.black:
        return tileBlack;
      case OkeyColor.blue:
        return tileBlue;
    }
  }

  // --- Vurgu / durum renkleri ---------------------------------------------
  /// Otomatik sayılan tamamlanmış per/grup/çift kenarlığı (altın).
  static const completeMeldGold = Color(0xFFFFB300);

  /// Yardımlı modda "işlenebilir" ipucu (yeşil).
  /// İŞLEK TAŞ VURGUSU — masadaki açık bir pere işlenebilen elimdeki taş.
  ///
  /// 0xFF2E7D32 (koyu yeşil) idi ve fildişi taşın üstünde ince bir çizgi
  /// olarak neredeyse görünmüyordu (kullanıcı isteği, 2026-09-06: "işlek
  /// taşlar daha belirgin olsun"). Parlak yeşile çekildi: taşın kendi rengi
  /// (kırmızı/sarı/siyah/mavi) ile karışmayan, masadaki tek "elektrik"
  /// tonu — yani vurgu bir renk değil, bir SİNYAL.
  static const hintProcessable = Color(0xFF76FF03);

  /// Vurgunun taşın çevresine yaydığı ışık.
  static const hintProcessableGlow = Color(0xCC64DD17);

  /// Yardımlı modda "per/grup/çift olabilir" ipucu (mavi alt çizgi).
  static const hintMeldable = tileBlue;

  /// RİSKLİ ("işlek") TAŞ — atılırsa +101 ceza yazılır (RULES.md §7).
  ///
  /// Fırsat ipuçlarından (yeşil/mavi) ayrı bir renk: bu işaret "şunu yap"
  /// demiyor, "şunu ATMA" diyor. Cezanın kendisi 2026-09-07'de eli kapalı
  /// oyuncuya da işlemeye başladı; uyarı olmasaydı oyuncu bedelini ancak
  /// ödedikten sonra öğrenirdi.
  static const hintRisky = Color(0xFFFF5252);

  static const accentGold = Colors.amber;

  // --- Ahşap ıstaka --------------------------------------------------------
  static const woodLight = Color(0xFFD9A441);
  static const woodDark = Color(0xFFB5822B);
  static const woodBorder = Color(0xFF8A5F1A);
  static const woodGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [woodLight, woodDark],
  );

  // --- Oda arka planı (skeuomorfik masa çevresi) ---------------------------
  // NEDEN: kullanıcı gerçek bir oda/masa ortamındaymış hissi istedi ama
  // fotoğraf/görsel varlık üretecek bir aracımız yok — bu tonlar Flutter
  // gradyanlarıyla o hissi VEKTÖREL yaklaştırır (bkz. plan: warm-moseying-nautilus).
  static const roomWallDark = Color(0xFF2A1B12);
  static const roomWallWarm = Color(0xFF4E3420);
  static const roomGlow = Color(0xFFFFD59A);

  // --- Masa rayı + keçe (trapez CustomPainter) -----------------------------
  // Istakanın woodLight/woodDark'ından BİLİNÇLİ olarak ayrı: masa rayı daha
  // doygun/turuncu, ıstaka daha sarı kalsın diye ikisi karışmaz.
  static const tableRailLight = Color(0xFFC98A3B);
  static const tableRailDark = Color(0xFF7A4A17);
  // Turkuaz keçe ailesi (bkz. feltCenter'daki gerekçe).
  static const tableFeltDeep = Color(0xFF104E5A);
  static const tableFeltEdge = Color(0xFF166571);

  // --- Köşe avatarı + isim hapı ---------------------------------------------
  static const avatarRing = Color(0xFF2FBFA8);
  static const nameTagBg = Color(0xFF1A1410);

  // --- Modern "tablo" (panel/kart) görünümü ---------------------------------
  // KULLANICI İSTEĞİ: SERİ/ÇİFT panelleri ve bilgi şeridi, masaya oturan
  // yarı-saydam "cam" kartlar gibi görünsün — düz/opak eski kutudan farklı,
  // ince bir kenarlık ve yumuşak gölgeyle modern bir his verir.
  static const panelGlassFill = Color(0x3D000000); // ~%24 siyah
  static const panelGlassFillTop = Color(0x52000000); // panel üstü biraz koyu
  static const panelBorder = Color(0x26FFFFFF); // ~%15 beyaz
  static const panelHeaderBg = Color(0x40FFD54F); // altın başlık şeridi zemini

  // --- Aksiyon butonları ---------------------------------------------------
  static const buttonDisabled = [Color(0xFF6E7B85), Color(0xFF55606A)];
  static const buttonHighlighted = [Color(0xFFFFD54F), Color(0xFFF9A825)];
  static const buttonNormal = [Color(0xFFFFFDF7), Color(0xFFEFE3C8)];
  static const dizActive = [Color(0xFF4FC3F7), Color(0xFF0288D1)];
  static const dizInactive = [Color(0xFFF5F5F5), Color(0xFFD5D5D5)];
  // DİZ butonları için YENİ altın gradyan — mevcut dizActive silinmedi/
  // değiştirilmedi, sadece OkeyDizButton artık bunu okuyor (bkz. plan).
  static const dizGoldActive = [Color(0xFFFFD54F), Color(0xFFC9861A)];
  // OkeyModeBadge rozetlerini sıcak zemine karşı harmanlamak için taban tonu.
  static const surfaceWarm = Color(0xFF241A12);

  // --- Durum renkleri (seat/turn) ------------------------------------------
  static const turnActive = Colors.amber;
  static const drawSource = Colors.lightGreenAccent;
  static const discardTarget = Colors.lightBlueAccent;
  static const idle = Colors.white24;

  // ==========================================================================
  // MERKEZİ MASA TASARIMI (2026-09) — "gerçekçi masa + modern HUD"
  // ==========================================================================
  // Eski düzen masayı dikey sütunlara bölüyordu (köşe sütunu | sol tahta |
  // bilgi şeridi | sağ tahta | aksiyon sütunu). Yeni düzende masa TEK PARÇA
  // keçedir ve 4 oyuncu gerçek kenarlarında oturur. Aşağıdaki tonlar o
  // yüzeyleri tanımlar; yukarıdaki eski tokenlar SİLİNMEDİ çünkü ıstaka,
  // taşlar ve admin ekranları hâlâ onları okuyor.

  /// Masa rayının (ahşap çerçeve) dikey gradyanı — üstte cilalı parlaklık,
  /// altta derin gölge. [tableRailLight]/[tableRailDark] ikilisinden daha
  /// zengin: gerçek bir ahşap kenarın ışığı böyle kırılır.
  static const railGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFE0A653),
      Color(0xFFC98A3B),
      Color(0xFF8B5620),
      Color(0xFF5F3A12),
    ],
    stops: [0.0, 0.22, 0.68, 1.0],
  );

  /// Keçenin merkezden dışa açılan tonu — masanın üst-ortasına düşen ışık.
  ///
  /// [feltHighlight] lambanın tam düştüğü en açık nokta: vinyetin merkezine
  /// eklenen bu beşinci durak, keçeye tek bir düz rengin veremeyeceği
  /// yuvarlaklık hissini verir.
  ///
  /// RENK AİLESİ TURKUAZ (2026-09): kullanıcının referans görselindeki masa
  /// mavi-yeşil bir keçe; buradaki eski tonlar koyu ORMAN YEŞİLİYDİ. Turkuaz
  /// aynı zamanda taşların kırmızı/sarı/siyah/mavi dördünü de daha yüksek
  /// kontrastla taşır — koyu yeşilde siyah taşlar zeminle kaynaşıyordu.
  static const feltHighlight = Color(0xFF2A93A2);
  static const feltCenter = Color(0xFF1E7F8C);
  static const feltMid = Color(0xFF166571);
  static const feltRim = Color(0xFF0A3A45);

  // --- Modern HUD (masanın üstüne binen düz katman) -------------------------
  /// Oyuncu kartı / kontrol düğmesi zemini.
  ///
  /// Turkuaz keçede eski (yeşile çalan, %66 opak) ton yeterince ayrışmıyordu;
  /// kartlar keçenin bir gölgesi gibi duruyordu. Daha opak ve daha soğuk bir
  /// gece mavisi, kartı zeminden net ayırır.
  static const hudFill = Color(0xD4041F26);

  /// Mod rozeti zemini.
  static const hudBadgeFill = Color(0xC2031A20);

  /// HUD kenarlığı.
  static const hudBorder = Color(0x33FFFFFF);

  /// Sıra BENDEYKEN oyuncu kartının sıcak zemini + altın kenarı.
  static const podTurnFill = Color(0xB3261C08);
  static const podTurnBorder = Color(0x73FFC107);

  // --- Modern aksiyon butonları --------------------------------------------
  /// Etkin ama vurgusuz buton (koyu, ince kenarlı).
  ///
  /// KONTRAST NOTU (2026-09): keçe koyu YEŞİLDEN turkuaza geçince bu tonlar
  /// zeminle kaynaşıp butonlar "yok gibi" göründü — kullanıcı tam olarak
  /// bunu bildirdi ("tüm butonlar görülecek"). Dolgu neredeyse opak bir
  /// gece mavisine, kenarlık iki katına çıkarıldı: buton artık keçenin
  /// ÜSTÜNDE duran ayrı bir cisim.
  static const actionFill = Color(0xE6062A33);
  static const actionBorder = Color(0x5CFFFFFF);

  /// Kapalı buton — dolgu ve kenar birlikte soluklaşır, ama YİNE DE görünür
  /// kalır: "yapılamaz" ile "yok" farklı şeylerdir.
  static const actionDisabledFill = Color(0x8A042028);
  static const actionDisabledBorder = Color(0x24FFFFFF);
  static const actionDisabledText = Color(0x70FFFFFF);

  /// "Yapılabilir" aksiyon (SERİ AÇ hazır) — altın gradyan, koyu metin.
  static const actionReady = [Color(0xFFFFD54F), Color(0xFFF0A415)];

  /// Bitirme hamlesi — daha parlak altın + dışa vuran parıltı.
  static const actionWinning = [Color(0xFFFFE082), Color(0xFFFFB300)];

  /// Altın butonların üzerindeki metin/ikon rengi.
  static const onGold = Color(0xFF241A12);

  /// HUD metinleri.
  static const hudText = Color(0xFFF3EDE2);
  static const hudTextDim = Color(0x9EFFFFFF);
  static const hudTextFaint = Color(0x6BFFFFFF);

  /// Keçeye "kazınmış" başlık (SERİLER & GRUPLAR / ÇİFTLER).
  static const engraved = Color(0x6B000000);
  static const engravedHighlight = Color(0x12FFFFFF);
}

/// Ortak metin stilleri — tahta ve panellerde tekrar eden font ayarları.
abstract final class OkeyTextStyles {
  static const panelTitle = TextStyle(
    color: Colors.white38,
    fontSize: 10,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.2,
  );

  static const badge = TextStyle(
    color: Colors.white70,
    fontSize: 9,
    fontWeight: FontWeight.bold,
  );
}

/// MASA TASARIMI v3 (2026-09) — "sakin keçe, net kontroller".
///
/// ## Neden yeni bir katman
///
/// Önceki tasarımda masanın üstündeki her öğe kendi malzemesini seçiyordu:
/// aksiyon butonları neredeyse görünmez koyu kutulardı, DİZ düğmeleri parlak
/// turuncu ahşap bloklardı, oyuncu kartları siyah şeritlerdi, ıstaka ise
/// bambaşka bir sarıydı. Aynı ekranda dört ayrı görsel dil vardı.
///
/// v3'te kural tek cümle: **masa gerçekçi, kontroller düz.** Keçe ve ahşap
/// ray dokulu kalır; ÜZERİNE BİNEN her kontrol aynı koyu cam yüzeyden,
/// aynı köşe yarıçapından ve aynı kenar çizgisinden yapılır. Renk yalnızca
/// ANLAM taşır:
///
///   * altın  → şu an yapılabilen, değerli hamle (AÇ / BİTİR)
///   * turkuaz→ ıstaka aracı (SERİ DİZ / ÇİFT DİZ)
///   * yeşil  → taş çekilecek yer
///   * mavi   → taş atılacak yer
///
/// Renk anlam taşımadığı her yerde yüzey nötr kalır. Böylece oyuncu ekrana
/// baktığında "ne yapabilirim"i renkten okur, kutuları tek tek gezmez.
abstract final class OkeyV3 {
  // --- Yüzeyler ------------------------------------------------------------
  /// Masanın üstüne binen her kontrolün taban dolgusu.
  static const Color surface = Color(0xF00A2028);

  /// Biraz daha açık yüzey — kontrolün İÇİNDEKİ ikinci kademe (rozet, sayaç).
  static const Color surfaceRaised = Color(0xFF123845);

  /// Kontrol kenarı. Tek bir değer: her kutu aynı kalınlıkta çizilir.
  static const Color border = Color(0x40FFFFFF);

  /// Vurgulanmamış ama etkin bir kontrolün kenarı biraz daha belirgin.
  static const Color borderStrong = Color(0x66FFFFFF);

  /// Kapalı kontrol — GÖRÜNÜR kalır, sadece söner. "Yapılamaz" ile "yok"
  /// farklı şeylerdir; kaybolan bir buton oyuncuya hiçbir şey öğretmez.
  static const Color surfaceDisabled = Color(0x9E07202A);
  static const Color borderDisabled = Color(0x1FFFFFFF);

  // --- Metin ---------------------------------------------------------------
  static const Color text = Color(0xFFF1F7F9);
  static const Color textDim = Color(0xB8FFFFFF);
  static const Color textFaint = Color(0x73FFFFFF);
  static const Color textDisabled = Color(0x5CFFFFFF);

  // --- Anlam renkleri ------------------------------------------------------
  /// ALTIN — yapılabilir, yüksek değerli hamle.
  static const List<Color> gold = [Color(0xFFFFD264), Color(0xFFE79417)];
  static const Color onGold = Color(0xFF2A1B03);
  static const Color goldGlow = Color(0x59FFB300);

  /// Bitiren hamle — altının daha parlak ve daha çok parlayan hali.
  static const List<Color> goldBright = [Color(0xFFFFE9A6), Color(0xFFFFB01F)];

  /// TURKUAZ — ıstaka aracı (dizme). Hamle değil, düzenleme.
  static const List<Color> tool = [Color(0xFF44D3D8), Color(0xFF12808E)];
  static const Color onTool = Color(0xFF04252B);

  /// Taş ÇEKİLECEK yer (soldaki oyuncunun ıskartası, deste).
  static const Color draw = Color(0xFF8CE071);

  /// Taş ATILACAK yer (kendi ıskartam).
  static const Color discard = Color(0xFF5CB8FF);

  /// Sıra o oyuncuda.
  static const Color turn = Color(0xFFFFC845);

  // --- Ölçüler -------------------------------------------------------------
  /// TEK köşe yarıçapı ailesi — kontroller birbirine benzesin diye.
  static const double radius = 11;
  static const double radiusSm = 7;
  static const double radiusPill = 999;

  /// Masadaki kontrollerin ortak gölgesi: yüzeyden ayrılsınlar diye dar ve
  /// koyu. Bulanık geniş gölge, koyu keçede kirli bir leke bırakıyordu.
  static const List<BoxShadow> lift = [
    BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2)),
  ];
}
