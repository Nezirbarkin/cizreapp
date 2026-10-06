import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'okey_rack_style.dart';

/// MASA TEMASI — 101 Okey masasının TÜM malzeme paletini taşıyan tek nesne
/// (kullanıcı isteği, 2026-09-14: "okey oyunu yeni bir tasarım yap, oyuncu
/// tema seçebilsin ayardan").
///
/// ## Neden yepyeni bir sınıf, `OkeyColors`in içine gömülü dört palet değil
///
/// Masanın rengini taşıyan `OkeyColors`/`OkeyV3` `static const` alanlardı —
/// yani DERLEME ZAMANINDA sabitti, kullanıcı tercihine göre değişemezdi. Bu
/// dosya değeri taşımaz, YALNIZCA dört (ileride daha fazla) hazır PALETİ
/// tanımlar; `OkeyColors`/`OkeyV3` bu paletlerden HANGİSİNİN aktif olduğunu
/// [OkeyTableThemePrefs] üzerinden okur (bkz. okey_theme.dart). Böylece
/// masayı çizen ~30 dosyanın HİÇBİRİ değişmedi: hepsi hâlâ `OkeyColors.xxx`
/// yazıyor, sadece o ifadenin ARKASINDAKİ değer artık canlı.
///
/// ## Neden dördü de GERÇEK bir fiziksel masaya karşılık geliyor
///
/// Kullanıcı isteği net: "tamamen gerçekçi, sanki gerçek oyundaymış gibi".
/// Rastgele dört renk paleti değil, Türkiye'de gerçekten var olan dört okey
/// masası:
///   * **Kahvehane** — bugünkü varsayılan: ceviz ıstaka + turkuaz çuha.
///   * **Yeşil Çuha** — klasik salon/kahvehane masası, çoğu fiziksel okey
///     seti bu renkte satılır.
///   * **Kırmızı Kadife** — kulüp/salon masası, koyu maun + kadife kırmızı.
///   * **Gece Modu** — ahşap değil FIRÇALANMIŞ ÇELİK ray + soğuk grafit çuha;
///     dijital/modern bir masa, genç oyuncu kitlesi için.
///
/// Oyunun SİNYAL renkleri (işlek taş yeşili, riskli taş kırmızısı, sıra
/// ambar rengi, taş rengleri kırmızı/sarı/siyah/mavi) HİÇBİR temada
/// DEĞİŞMEZ — bunlar `OkeyColors`te sabit kalır. Neden: gerçek okey
/// taşlarının mürekkep renkleri evrenseldir ve oyuncunun "yeşil = işlenebilir"
/// gibi öğrendiği anlam, masa hangi renkte olursa olsun aynı kalmalı.
/// ZEMİNİN "kabartma" DESENİ — kullanıcı isteği, 2026-09-15: "arka plandaki
/// solukları kaldır ve yeni arka plan özellikleri ekle".
///
/// Eskiden HER temada aynı soluk kıvrım/yaprak (scroll) motifi tekrarlanırdı
/// — sadece rengi değişiyordu, kendisi hiçbir masaya özgü değildi. Artık her
/// desen GERÇEK bir yüzeyi taklit eder: keçe dokuması, kadife düğmelemesi,
/// modern nokta ızgarası... Kahvehane BİLEREK desensiz kalır (bkz.
/// [OkeyTableTheme.kahvehane]) — "solukları kaldır" isteği en çok orada
/// hissediliyordu, o yüzden varsayılan tema artık yalnızca temiz bir ışık
/// havuzu, hiçbir soluk desen taşımıyor.
enum OkeyBackdropPattern {
  /// Desen yok — yalnızca ışık havuzu + vinyet.
  plain,

  /// Çapraz keçe dokuması — köşegen iki yönde ince çizgiler, baklava deseni.
  weave,

  /// Kadife düğmelemesi (chesterfield) — düzenli aralıklı yumuşak düğmeler
  /// + aralarındaki kırışık çizgiler.
  tufted,

  /// Modern nokta ızgarası — ince, soğuk tonlu düzenli noktalar.
  grid,

  /// İznik çinisi — sekiz köşeli yıldız ve aralarındaki haç (İznik Çini).
  star,

  /// Saray kemeri — iç içe geçen ogee kafes (Osmanlı Saray).
  ogee,

  /// Petek — neon çizgili altıgen ızgara (Gece Neon).
  hex,

  /// Ege dalgası — kıyıya vuran üst üste dalga kavisleri (Ege Gündüz).
  waves,
}

@immutable
class OkeyTableTheme {
  /// Tercih olarak saklanan sabit anahtar.
  final String key;

  /// Ayarlar ekranında görünen ad.
  final String label;

  /// Seçim kartında görünen kısa açıklama — "hangi gerçek masa" olduğunu
  /// anlatır, salt renk adı değil.
  final String description;

  // --- Zeminler ------------------------------------------------------------
  final Color tableBackground;
  final Color screenBackground;
  final Color surfaceDark;
  final Color surfaceWarm;

  // --- Taş gövdesi -----------------------------------------------------------
  final Color tileIvoryLight;
  final Color tileIvoryDark;

  // --- Vurgu -----------------------------------------------------------------
  final Color accentGold;
  final Color completeMeldGold;
  final Color avatarRing;

  // --- Masa rayı (ahşap/metal çerçeve) ----------------------------------------
  final List<Color> railGradient;
  final List<double> railGradientStops;
  final Color railGrainLight;
  final Color railGrainDark;

  /// Ray dokusunun şiddet çarpanı. Ahşap temalarda 1.0; Gece Modu'nda
  /// neredeyse sıfır — orada ray fırçalanmış çelik olduğu için DAMAR değil,
  /// ince paralel FIRÇA çizikleri ister, ahşap lifi orada yanlış okunur.
  final double railGrainOpacity;

  // --- Keçe (felt) — kullanılmayan eski trapez painter için, bkz. dosya sonu -
  final Color feltHighlight;
  final Color feltCenter;
  final Color feltMid;
  final Color feltDeep;
  final Color feltRim;

  // --- MASANIN GERÇEKTE ÇİZİLEN ZEMİNİ — damask ("işlemeli kumaş") arka
  // plan (bkz. OkeyDamaskBackground) ve perlerin oturduğu oyuk tabla
  // (bkz. OkeyMeldBay). v4 düzeninde ahşap ray/keçe kalktı, oyuncunun
  // GERÇEKTEN gördüğü zemin budur — tema burada görünür olmalı.
  final Color damaskDeep;
  final Color damaskMid;
  final Color damaskLight;
  final Color damaskGrainShadow;
  final Color damaskGrainLight;
  final Color damaskVignette;
  final Color meldBayTop;
  final Color meldBayBottom;

  /// Zeminin kabartma deseni — bkz. [OkeyBackdropPattern].
  final OkeyBackdropPattern backdropPattern;

  // --- Rakip ıstakası (3B ahşap/metal kutu, bkz. paintOkeyRackBox) -----------
  final Color rackBoxBack;
  final Color rackBoxCap;
  final List<Color> rackBoxTop;
  final List<Color> rackBoxFront;
  final Color rackBoxGroove;
  final Color rackBoxEdgeBright;
  final Color rackBoxEdgeDim;

  // --- HUD (masanın üstüne binen düz katman) ----------------------------------
  final Color hudFill;
  final Color hudBadgeFill;
  final Color hudBorder;
  final Color hudText;
  final Color hudTextDim;
  final Color hudTextFaint;

  // --- Aksiyon butonları -------------------------------------------------------
  final Color actionFill;
  final Color actionBorder;
  final Color actionDisabledFill;
  final Color actionDisabledBorder;
  final Color actionDisabledText;
  final List<Color> actionReady;
  final List<Color> actionWinning;
  final Color onGold;

  // --- v3 cam paneller (OkeyGlassPanel, aksiyon çipleri) ------------------------
  final Color v3Surface;
  final Color v3SurfaceRaised;
  final Color v3Border;
  final Color v3BorderStrong;
  final Color v3SurfaceDisabled;
  final Color v3BorderDisabled;
  final Color v3Text;
  final Color v3TextDim;
  final Color v3TextFaint;
  final Color v3TextDisabled;
  final List<Color> v3Gold;
  final Color v3OnGold;
  final Color v3GoldGlow;
  final List<Color> v3GoldBright;

  /// Tema seçilince BİRLİKTE önerilen ıstaka ahşabı (bkz. OkeyRackStyle).
  /// Kullanıcı isterse ayrı ayardan yine değiştirebilir; bu yalnızca
  /// "bu masaya en çok yakışan takoz" ön seçimidir.
  final String pairedRackStyleKey;

  const OkeyTableTheme({
    required this.key,
    required this.label,
    required this.description,
    required this.tableBackground,
    required this.screenBackground,
    required this.surfaceDark,
    required this.surfaceWarm,
    required this.tileIvoryLight,
    required this.tileIvoryDark,
    required this.accentGold,
    required this.completeMeldGold,
    required this.avatarRing,
    required this.railGradient,
    required this.railGradientStops,
    required this.railGrainLight,
    required this.railGrainDark,
    required this.railGrainOpacity,
    required this.feltHighlight,
    required this.feltCenter,
    required this.feltMid,
    required this.feltDeep,
    required this.feltRim,
    required this.damaskDeep,
    required this.damaskMid,
    required this.damaskLight,
    required this.damaskGrainShadow,
    required this.damaskGrainLight,
    required this.damaskVignette,
    required this.meldBayTop,
    required this.meldBayBottom,
    required this.backdropPattern,
    required this.rackBoxBack,
    required this.rackBoxCap,
    required this.rackBoxTop,
    required this.rackBoxFront,
    required this.rackBoxGroove,
    required this.rackBoxEdgeBright,
    required this.rackBoxEdgeDim,
    required this.hudFill,
    required this.hudBadgeFill,
    required this.hudBorder,
    required this.hudText,
    required this.hudTextDim,
    required this.hudTextFaint,
    required this.actionFill,
    required this.actionBorder,
    required this.actionDisabledFill,
    required this.actionDisabledBorder,
    required this.actionDisabledText,
    required this.actionReady,
    required this.actionWinning,
    required this.onGold,
    required this.v3Surface,
    required this.v3SurfaceRaised,
    required this.v3Border,
    required this.v3BorderStrong,
    required this.v3SurfaceDisabled,
    required this.v3BorderDisabled,
    required this.v3Text,
    required this.v3TextDim,
    required this.v3TextFaint,
    required this.v3TextDisabled,
    required this.v3Gold,
    required this.v3OnGold,
    required this.v3GoldGlow,
    required this.v3GoldBright,
    required this.pairedRackStyleKey,
  });

  /// KAHVEHANE — bugüne kadarki TEK masa. Varsayılan: mevcut oyuncular
  /// masaya girdiğinde HİÇBİR ŞEY değişmemiş görünür.
  static const kahvehane = OkeyTableTheme(
    key: 'kahvehane',
    label: 'Kahvehane',
    description: 'Ceviz ıstaka, turkuaz çuha — klasik masa',
    tableBackground: Color(0xFF10495F),
    screenBackground: Color(0xFF0E3A4F),
    surfaceDark: Color(0xFF0A2C3C),
    surfaceWarm: Color(0xFF241A12),
    tileIvoryLight: Color(0xFFFFFDF7),
    tileIvoryDark: Color(0xFFF2ECDD),
    accentGold: Color(0xFFFFC107),
    completeMeldGold: Color(0xFFFFB300),
    avatarRing: Color(0xFF2FBFA8),
    railGradient: [
      Color(0xFFE0A653),
      Color(0xFFC98A3B),
      Color(0xFF8B5620),
      Color(0xFF5F3A12),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x33FFD9A0),
    railGrainDark: Color(0x40402008),
    railGrainOpacity: 1.0,
    feltHighlight: Color(0xFF2A93A2),
    feltCenter: Color(0xFF1E7F8C),
    feltMid: Color(0xFF166571),
    feltDeep: Color(0xFF104E5A),
    feltRim: Color(0xFF0A3A45),
    damaskDeep: Color(0xFF0C3F57),
    damaskMid: Color(0xFF17607D),
    damaskLight: Color(0xFF2380A0),
    damaskGrainShadow: Color(0xFF04222F),
    damaskGrainLight: Color(0xFF7FD0E4),
    damaskVignette: Color(0xFF001A26),
    meldBayTop: Color(0xD105202C),
    meldBayBottom: Color(0xC4093344),
    backdropPattern: OkeyBackdropPattern.plain,
    rackBoxBack: Color(0xFF6B4113),
    rackBoxCap: Color(0xFF8A5A20),
    rackBoxTop: [Color(0xFFF2CB84), Color(0xFFCE9748)],
    rackBoxFront: [Color(0xFFE6B871), Color(0xFF9A6526)],
    rackBoxGroove: Color(0x8A2E1808),
    rackBoxEdgeBright: Color(0x8AFFE6BE),
    rackBoxEdgeDim: Color(0x4DFFE6BE),
    hudFill: Color(0xD4041F26),
    hudBadgeFill: Color(0xC2031A20),
    hudBorder: Color(0x33FFFFFF),
    hudText: Color(0xFFF3EDE2),
    hudTextDim: Color(0x9EFFFFFF),
    hudTextFaint: Color(0x6BFFFFFF),
    actionFill: Color(0xE6062A33),
    actionBorder: Color(0x5CFFFFFF),
    actionDisabledFill: Color(0x8A042028),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFFFD54F), Color(0xFFF0A415)],
    actionWinning: [Color(0xFFFFE082), Color(0xFFFFB300)],
    onGold: Color(0xFF241A12),
    v3Surface: Color(0xF00A2028),
    v3SurfaceRaised: Color(0xFF123845),
    v3Border: Color(0x40FFFFFF),
    v3BorderStrong: Color(0x66FFFFFF),
    v3SurfaceDisabled: Color(0x9E07202A),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFF1F7F9),
    v3TextDim: Color(0xB8FFFFFF),
    v3TextFaint: Color(0x73FFFFFF),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFFFD264), Color(0xFFE79417)],
    v3OnGold: Color(0xFF2A1B03),
    v3GoldGlow: Color(0x59FFB300),
    v3GoldBright: [Color(0xFFFFE9A6), Color(0xFFFFB01F)],
    pairedRackStyleKey: 'ceviz',
  );

  /// YEŞİL ÇUHA — Türkiye'deki en yaygın fiziksel okey masası rengi.
  static const yesilCuha = OkeyTableTheme(
    key: 'yesil_cuha',
    label: 'Yeşil Çuha',
    description: 'Meşe ıstaka, klasik salon çuhası',
    tableBackground: Color(0xFF123320),
    screenBackground: Color(0xFF0F2A1B),
    surfaceDark: Color(0xFF0A1F13),
    surfaceWarm: Color(0xFF231708),
    tileIvoryLight: Color(0xFFFFFCF2),
    tileIvoryDark: Color(0xFFEFE6CE),
    accentGold: Color(0xFFE0A72A),
    completeMeldGold: Color(0xFFE8AE1F),
    avatarRing: Color(0xFFD8B24A),
    railGradient: [
      Color(0xFFB98A4A),
      Color(0xFF8F6530),
      Color(0xFF5E4118),
      Color(0xFF3A280E),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x33EFD9A0),
    railGrainDark: Color(0x40301C08),
    railGrainOpacity: 1.0,
    feltHighlight: Color(0xFF3F8F55),
    feltCenter: Color(0xFF2E7A45),
    feltMid: Color(0xFF1F5E34),
    feltDeep: Color(0xFF163F24),
    feltRim: Color(0xFF0C2716),
    damaskDeep: Color(0xFF0A2E1B),
    damaskMid: Color(0xFF15542F),
    damaskLight: Color(0xFF247A41),
    damaskGrainShadow: Color(0xFF041F0F),
    damaskGrainLight: Color(0xFF9FE0AE),
    damaskVignette: Color(0xFF00170B),
    meldBayTop: Color(0xD1051F10),
    meldBayBottom: Color(0xC40C3D1E),
    backdropPattern: OkeyBackdropPattern.weave,
    rackBoxBack: Color(0xFF4A3312),
    rackBoxCap: Color(0xFF6B4A1B),
    rackBoxTop: [Color(0xFFE0C078), Color(0xFFAE7E37)],
    rackBoxFront: [Color(0xFFCDA361), Color(0xFF7A501E)],
    rackBoxGroove: Color(0x8A26170A),
    rackBoxEdgeBright: Color(0x8AF2E0B0),
    rackBoxEdgeDim: Color(0x4DF2E0B0),
    hudFill: Color(0xD4051F0F),
    hudBadgeFill: Color(0xC2041A0C),
    hudBorder: Color(0x33FFF6DC),
    hudText: Color(0xFFF2EFDD),
    hudTextDim: Color(0x9EFFF6E0),
    hudTextFaint: Color(0x6BFFF6E0),
    actionFill: Color(0xE60A2B16),
    actionBorder: Color(0x5CE8D9A8),
    actionDisabledFill: Color(0x8A072010),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFF2D06B), Color(0xFFCB8D1E)],
    actionWinning: [Color(0xFFFFE9A0), Color(0xFFE8A100)],
    onGold: Color(0xFF231708),
    v3Surface: Color(0xF0071F10),
    v3SurfaceRaised: Color(0xFF0F3320),
    v3Border: Color(0x40F2E7C2),
    v3BorderStrong: Color(0x66F2E7C2),
    v3SurfaceDisabled: Color(0x9E051A0D),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFF3F7EF),
    v3TextDim: Color(0xB8FFFFFF),
    v3TextFaint: Color(0x73FFFFFF),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFF0D274), Color(0xFFCB8D1E)],
    v3OnGold: Color(0xFF241A03),
    v3GoldGlow: Color(0x59E8A100),
    v3GoldBright: [Color(0xFFFFEBAE), Color(0xFFE8A100)],
    pairedRackStyleKey: 'mese',
  );

  /// KIRMIZI KADİFE — kulüp/salon masası, koyu maun + kadife kırmızı.
  static const kirmiziKadife = OkeyTableTheme(
    key: 'kirmizi_kadife',
    label: 'Kırmızı Kadife',
    description: 'Maun ıstaka, kulüp masası',
    tableBackground: Color(0xFF3A0E14),
    screenBackground: Color(0xFF2C0A10),
    surfaceDark: Color(0xFF1E070B),
    surfaceWarm: Color(0xFF2A0F08),
    tileIvoryLight: Color(0xFFFFFBF3),
    tileIvoryDark: Color(0xFFF3E4D6),
    accentGold: Color(0xFFFFC947),
    completeMeldGold: Color(0xFFFFC233),
    avatarRing: Color(0xFFFFC947),
    railGradient: [
      Color(0xFFD4A24E),
      Color(0xFFB07B2E),
      Color(0xFF6E4213),
      Color(0xFF3E220A),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x33FFD9A0),
    railGrainDark: Color(0x40301608),
    railGrainOpacity: 1.0,
    feltHighlight: Color(0xFF7A2430),
    feltCenter: Color(0xFF611B26),
    feltMid: Color(0xFF43121A),
    feltDeep: Color(0xFF2E0B10),
    feltRim: Color(0xFF190509),
    damaskDeep: Color(0xFF330A10),
    damaskMid: Color(0xFF5C1420),
    damaskLight: Color(0xFF832030),
    damaskGrainShadow: Color(0xFF230609),
    damaskGrainLight: Color(0xFFF0A8B0),
    damaskVignette: Color(0xFF1A0508),
    meldBayTop: Color(0xD1230609),
    meldBayBottom: Color(0xC4400D14),
    backdropPattern: OkeyBackdropPattern.tufted,
    rackBoxBack: Color(0xFF5A2A12),
    rackBoxCap: Color(0xFF7A3B18),
    rackBoxTop: [Color(0xFFEFC583), Color(0xFFC48A3C)],
    rackBoxFront: [Color(0xFFDDA766), Color(0xFF8F5622)],
    rackBoxGroove: Color(0x8A2E140A),
    rackBoxEdgeBright: Color(0x8AFFDFAE),
    rackBoxEdgeDim: Color(0x4DFFDFAE),
    hudFill: Color(0xD4230609),
    hudBadgeFill: Color(0xC21E0507),
    hudBorder: Color(0x33FFD9A8),
    hudText: Color(0xFFF7ECE4),
    hudTextDim: Color(0x9EFFE9DE),
    hudTextFaint: Color(0x6BFFE9DE),
    actionFill: Color(0xE6300A10),
    actionBorder: Color(0x5CFFCB80),
    actionDisabledFill: Color(0x8A230709),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFFFD87A), Color(0xFFE79417)],
    actionWinning: [Color(0xFFFFEFB0), Color(0xFFFFB300)],
    onGold: Color(0xFF2A0F08),
    v3Surface: Color(0xF0230609),
    v3SurfaceRaised: Color(0xFF3A0E14),
    v3Border: Color(0x40FFD9A8),
    v3BorderStrong: Color(0x66FFD9A8),
    v3SurfaceDisabled: Color(0x9E1E0507),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFFAF1EC),
    v3TextDim: Color(0xB8FFFFFF),
    v3TextFaint: Color(0x73FFFFFF),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFFFD87A), Color(0xFFE79417)],
    v3OnGold: Color(0xFF2A1503),
    v3GoldGlow: Color(0x59FFB300),
    v3GoldBright: [Color(0xFFFFEFB0), Color(0xFFFFB300)],
    pairedRackStyleKey: 'maun',
  );

  /// GECE MODU — ahşap yok, fırçalanmış çelik ray + soğuk grafit çuha.
  static const geceModu = OkeyTableTheme(
    key: 'gece_modu',
    label: 'Gece Modu',
    description: 'Grafit ıstaka, çelik ray — modern masa',
    tableBackground: Color(0xFF0B1420),
    screenBackground: Color(0xFF0A121C),
    surfaceDark: Color(0xFF060B12),
    surfaceWarm: Color(0xFF141B24),
    tileIvoryLight: Color(0xFFF7FAFC),
    tileIvoryDark: Color(0xFFE3E9EE),
    accentGold: Color(0xFFE8C069),
    completeMeldGold: Color(0xFFFFC233),
    avatarRing: Color(0xFF4FC3D8),
    railGradient: [
      Color(0xFF56636E),
      Color(0xFF3A4750),
      Color(0xFF232B33),
      Color(0xFF11161C),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x30D8E8EF),
    railGrainDark: Color(0x40080B0E),
    railGrainOpacity: 0.35,
    feltHighlight: Color(0xFF1F4A5C),
    feltCenter: Color(0xFF163847),
    feltMid: Color(0xFF0F2530),
    feltDeep: Color(0xFF0A1820),
    feltRim: Color(0xFF050D12),
    damaskDeep: Color(0xFF060B12),
    damaskMid: Color(0xFF0F1D2A),
    damaskLight: Color(0xFF1B3446),
    damaskGrainShadow: Color(0xFF03070C),
    damaskGrainLight: Color(0xFF8FD4E8),
    damaskVignette: Color(0xFF000406),
    meldBayTop: Color(0xD1050B12),
    meldBayBottom: Color(0xC40D1E2C),
    backdropPattern: OkeyBackdropPattern.grid,
    rackBoxBack: Color(0xFF232B33),
    rackBoxCap: Color(0xFF2E3841),
    rackBoxTop: [Color(0xFF6B7986), Color(0xFF3F4B54)],
    rackBoxFront: [Color(0xFF56636E), Color(0xFF2A333B)],
    rackBoxGroove: Color(0x8A0A0F14),
    rackBoxEdgeBright: Color(0x8AAFC3CE),
    rackBoxEdgeDim: Color(0x4DAFC3CE),
    hudFill: Color(0xD404121C),
    hudBadgeFill: Color(0xC2030E16),
    hudBorder: Color(0x33BFE3F0),
    hudText: Color(0xFFEAF3F7),
    hudTextDim: Color(0x9ED9ECF2),
    hudTextFaint: Color(0x6BD9ECF2),
    actionFill: Color(0xE60A222E),
    actionBorder: Color(0x5C7FD9E8),
    actionDisabledFill: Color(0x8A071923),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFFFD87A), Color(0xFFCB9A2E)],
    actionWinning: [Color(0xFFFFEFB0), Color(0xFFFFB300)],
    onGold: Color(0xFF17222A),
    v3Surface: Color(0xF0071923),
    v3SurfaceRaised: Color(0xFF0F2530),
    v3Border: Color(0x40BFE3F0),
    v3BorderStrong: Color(0x667FD9E8),
    v3SurfaceDisabled: Color(0x9E051019),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFEDF6F9),
    v3TextDim: Color(0xB8D9ECF2),
    v3TextFaint: Color(0x73D9ECF2),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFFFD87A), Color(0xFFCB9A2E)],
    v3OnGold: Color(0xFF17222A),
    v3GoldGlow: Color(0x59FFB300),
    v3GoldBright: [Color(0xFFFFEFB0), Color(0xFFFFB300)],
    pairedRackStyleKey: 'grafit',
  );

  // ===========================================================================
  // TASARIM PAKETLERİYLE GELEN MASALAR (2026-10-05, bkz. OkeyDesign)
  // ===========================================================================

  /// İZNİK ÇİNİ — kobalt sırlı masa, porselen beyazı taşlar, sekiz köşeli
  /// yıldız örgüsü. Taşlar bilerek SOĞUK beyaz: fildişi kobaltın üstünde
  /// kirli sarı okunuyordu.
  static const cini = OkeyTableTheme(
    key: 'cini',
    label: 'İznik Çini',
    description: 'Kobalt sır, porselen taş',
    tableBackground: Color(0xFF0F2C66),
    screenBackground: Color(0xFF0C2456),
    surfaceDark: Color(0xFF081A40),
    surfaceWarm: Color(0xFF141C33),
    tileIvoryLight: Color(0xFFFFFFFF),
    tileIvoryDark: Color(0xFFEAF0F8),
    accentGold: Color(0xFFF2C94C),
    completeMeldGold: Color(0xFFFFC233),
    avatarRing: Color(0xFF3FC1C9),
    railGradient: [
      Color(0xFFE9EEF7),
      Color(0xFFC9D3E6),
      Color(0xFF8E9DBD),
      Color(0xFF5B6A8E),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x30FFFFFF),
    railGrainDark: Color(0x401A2A4A),
    railGrainOpacity: 0.3,
    feltHighlight: Color(0xFF2F64C4),
    feltCenter: Color(0xFF2556AD),
    feltMid: Color(0xFF1C4389),
    feltDeep: Color(0xFF143267),
    feltRim: Color(0xFF0B2148),
    damaskDeep: Color(0xFF0D2558),
    damaskMid: Color(0xFF1A438F),
    damaskLight: Color(0xFF2A5FBF),
    damaskGrainShadow: Color(0xFF061535),
    damaskGrainLight: Color(0xFFBFD8FF),
    damaskVignette: Color(0xFF030C22),
    meldBayTop: Color(0xD1061535),
    meldBayBottom: Color(0xC40E2A5E),
    backdropPattern: OkeyBackdropPattern.star,
    rackBoxBack: Color(0xFF8E9DBD),
    rackBoxCap: Color(0xFFAFBCD6),
    rackBoxTop: [Color(0xFFF4F7FC), Color(0xFFCAD5E8)],
    rackBoxFront: [Color(0xFFE3EAF5), Color(0xFF9AA9C7)],
    rackBoxGroove: Color(0x8A1A2A4A),
    rackBoxEdgeBright: Color(0x8AFFFFFF),
    rackBoxEdgeDim: Color(0x4DFFFFFF),
    hudFill: Color(0xD4071A3F),
    hudBadgeFill: Color(0xC2061636),
    hudBorder: Color(0x33D6E6FF),
    hudText: Color(0xFFEFF5FF),
    hudTextDim: Color(0x9EE3EEFF),
    hudTextFaint: Color(0x6BE3EEFF),
    actionFill: Color(0xE6082050),
    actionBorder: Color(0x5CBFD8FF),
    actionDisabledFill: Color(0x8A06183D),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFFFDB6E), Color(0xFFE8A92A)],
    actionWinning: [Color(0xFFFFEBA6), Color(0xFFFFB300)],
    onGold: Color(0xFF1A1A2E),
    v3Surface: Color(0xF0071A3F),
    v3SurfaceRaised: Color(0xFF123272),
    v3Border: Color(0x40D6E6FF),
    v3BorderStrong: Color(0x66D6E6FF),
    v3SurfaceDisabled: Color(0x9E06163A),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFF1F6FF),
    v3TextDim: Color(0xB8E3EEFF),
    v3TextFaint: Color(0x73E3EEFF),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFFFDB6E), Color(0xFFE8A92A)],
    v3OnGold: Color(0xFF1A1A2E),
    v3GoldGlow: Color(0x59FFC233),
    v3GoldBright: [Color(0xFFFFEBA6), Color(0xFFFFB300)],
    pairedRackStyleKey: 'kobalt',
  );

  /// OSMANLI SARAY — patlıcan moru kadife, abanoz ıstaka, varak altın kemer
  /// kafes. Zeminin "açık damarı" bilerek ALTIN: desen süsleme gibi okunsun.
  static const saray = OkeyTableTheme(
    key: 'saray',
    label: 'Saray',
    description: 'Mor kadife, abanoz ve altın',
    tableBackground: Color(0xFF2A1238),
    screenBackground: Color(0xFF22102E),
    surfaceDark: Color(0xFF160A1F),
    surfaceWarm: Color(0xFF2A1A0E),
    tileIvoryLight: Color(0xFFFFFBF0),
    tileIvoryDark: Color(0xFFF1E6D0),
    accentGold: Color(0xFFF1C75B),
    completeMeldGold: Color(0xFFFFC233),
    avatarRing: Color(0xFFE9C25B),
    railGradient: [
      Color(0xFF5A4232),
      Color(0xFF3A2A20),
      Color(0xFF22170F),
      Color(0xFF120B07),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x30F3D27A),
    railGrainDark: Color(0x40050302),
    railGrainOpacity: 0.8,
    feltHighlight: Color(0xFF6A3590),
    feltCenter: Color(0xFF57287A),
    feltMid: Color(0xFF431D5F),
    feltDeep: Color(0xFF321548),
    feltRim: Color(0xFF1E0B2D),
    damaskDeep: Color(0xFF261033),
    damaskMid: Color(0xFF431D5C),
    damaskLight: Color(0xFF5E2C80),
    damaskGrainShadow: Color(0xFF14071C),
    damaskGrainLight: Color(0xFFF3D27A),
    damaskVignette: Color(0xFF0C0412),
    meldBayTop: Color(0xD114071C),
    meldBayBottom: Color(0xC42C123D),
    backdropPattern: OkeyBackdropPattern.ogee,
    rackBoxBack: Color(0xFF1E1410),
    rackBoxCap: Color(0xFF2C1E16),
    rackBoxTop: [Color(0xFF5A4232), Color(0xFF2E2018)],
    rackBoxFront: [Color(0xFF4A3628), Color(0xFF1E140E)],
    rackBoxGroove: Color(0x8A0A0604),
    rackBoxEdgeBright: Color(0x8AF3D27A),
    rackBoxEdgeDim: Color(0x4DF3D27A),
    hudFill: Color(0xD4180A22),
    hudBadgeFill: Color(0xC2140820),
    hudBorder: Color(0x33F3D27A),
    hudText: Color(0xFFFFF4E4),
    hudTextDim: Color(0x9EFFEBD0),
    hudTextFaint: Color(0x6BFFEBD0),
    actionFill: Color(0xE61E0D2A),
    actionBorder: Color(0x5CF3D27A),
    actionDisabledFill: Color(0x8A160A20),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFFFE08A), Color(0xFFDDA332)],
    actionWinning: [Color(0xFFFFF0B8), Color(0xFFFFB300)],
    onGold: Color(0xFF2A1A05),
    v3Surface: Color(0xF0180A22),
    v3SurfaceRaised: Color(0xFF34184A),
    v3Border: Color(0x40F3D27A),
    v3BorderStrong: Color(0x66F3D27A),
    v3SurfaceDisabled: Color(0x9E14081E),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFFFF6EA),
    v3TextDim: Color(0xB8FFEBD0),
    v3TextFaint: Color(0x73FFEBD0),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFFFE08A), Color(0xFFDDA332)],
    v3OnGold: Color(0xFF2A1A05),
    v3GoldGlow: Color(0x59FFB300),
    v3GoldBright: [Color(0xFFFFF0B8), Color(0xFFFFB300)],
    pairedRackStyleKey: 'abanoz',
  );

  /// GECE NEON — mürdüm gece, camgöbeği petek ızgara, akrilik ıstaka.
  /// "Yapılabilir hamle" rengi burada altın değil camgöbeği→eflatun: temanın
  /// tek parlak tonu neon olmalı, aksi halde altın düğme ekranda yabancı kalır.
  static const neon = OkeyTableTheme(
    key: 'neon',
    label: 'Neon',
    description: 'Petek ızgara, camgöbeği ışık',
    tableBackground: Color(0xFF0B0820),
    screenBackground: Color(0xFF0A071C),
    surfaceDark: Color(0xFF050311),
    surfaceWarm: Color(0xFF120E26),
    tileIvoryLight: Color(0xFFF8F7FF),
    tileIvoryDark: Color(0xFFE6E3F5),
    accentGold: Color(0xFF35E8FF),
    completeMeldGold: Color(0xFFFFD25A),
    avatarRing: Color(0xFFFF5ED8),
    railGradient: [
      Color(0xFF3A3560),
      Color(0xFF26214A),
      Color(0xFF171333),
      Color(0xFF0B0920),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x30B9A8FF),
    railGrainDark: Color(0x40050311),
    railGrainOpacity: 0.2,
    feltHighlight: Color(0xFF2B2370),
    feltCenter: Color(0xFF221B5C),
    feltMid: Color(0xFF191447),
    feltDeep: Color(0xFF120E33),
    feltRim: Color(0xFF0A081F),
    damaskDeep: Color(0xFF07051A),
    damaskMid: Color(0xFF140F3A),
    damaskLight: Color(0xFF241A5E),
    damaskGrainShadow: Color(0xFF02010A),
    damaskGrainLight: Color(0xFF35E8FF),
    damaskVignette: Color(0xFF000000),
    meldBayTop: Color(0xD103020F),
    meldBayBottom: Color(0xC40F0B2E),
    backdropPattern: OkeyBackdropPattern.hex,
    rackBoxBack: Color(0xFF120E26),
    rackBoxCap: Color(0xFF1A1536),
    rackBoxTop: [Color(0xFF2E2858), Color(0xFF16122E)],
    rackBoxFront: [Color(0xFF241F48), Color(0xFF0E0B20)],
    rackBoxGroove: Color(0x8A000000),
    rackBoxEdgeBright: Color(0x8A35E8FF),
    rackBoxEdgeDim: Color(0x4D35E8FF),
    hudFill: Color(0xD40A0720),
    hudBadgeFill: Color(0xC208061A),
    hudBorder: Color(0x4D7C5CFF),
    hudText: Color(0xFFF2EEFF),
    hudTextDim: Color(0x9EE2DCFF),
    hudTextFaint: Color(0x6BE2DCFF),
    actionFill: Color(0xE60E0A2A),
    actionBorder: Color(0x8035E8FF),
    actionDisabledFill: Color(0x8A0A0720),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFF5CF6FF), Color(0xFF8F7BFF)],
    actionWinning: [Color(0xFFB8FBFF), Color(0xFFFF7BE0)],
    onGold: Color(0xFF07051C),
    v3Surface: Color(0xF00A0720),
    v3SurfaceRaised: Color(0xFF1D1747),
    v3Border: Color(0x4D7C5CFF),
    v3BorderStrong: Color(0x8035E8FF),
    v3SurfaceDisabled: Color(0x9E08061A),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFF2EEFF),
    v3TextDim: Color(0xB8E2DCFF),
    v3TextFaint: Color(0x73E2DCFF),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFF5CF6FF), Color(0xFF8F7BFF)],
    v3OnGold: Color(0xFF07051C),
    v3GoldGlow: Color(0x5935E8FF),
    v3GoldBright: [Color(0xFFB8FBFF), Color(0xFFFF7BE0)],
    pairedRackStyleKey: 'neon',
  );

  /// EGE — derin deniz camı, zeytin ıstaka, dalga kavisleri; vurgu gün
  /// batımı şeftalisi.
  static const ege = OkeyTableTheme(
    key: 'ege',
    label: 'Ege',
    description: 'Deniz camı, zeytin ıstaka',
    tableBackground: Color(0xFF0B4A55),
    screenBackground: Color(0xFF093F49),
    surfaceDark: Color(0xFF062C33),
    surfaceWarm: Color(0xFF2A2214),
    tileIvoryLight: Color(0xFFFFFDF7),
    tileIvoryDark: Color(0xFFF3ECDD),
    accentGold: Color(0xFFFFB86B),
    completeMeldGold: Color(0xFFFFC233),
    avatarRing: Color(0xFFF2D4A0),
    railGradient: [
      Color(0xFFC9B27A),
      Color(0xFFA48C55),
      Color(0xFF6E5C33),
      Color(0xFF473B1F),
    ],
    railGradientStops: [0.0, 0.22, 0.68, 1.0],
    railGrainLight: Color(0x33FFF0C8),
    railGrainDark: Color(0x402E2410),
    railGrainOpacity: 1.0,
    feltHighlight: Color(0xFF1E8C99),
    feltCenter: Color(0xFF187A86),
    feltMid: Color(0xFF12636E),
    feltDeep: Color(0xFF0D4B54),
    feltRim: Color(0xFF07343B),
    damaskDeep: Color(0xFF073C46),
    damaskMid: Color(0xFF0F6170),
    damaskLight: Color(0xFF1A8494),
    damaskGrainShadow: Color(0xFF032830),
    damaskGrainLight: Color(0xFFBDF2F4),
    damaskVignette: Color(0xFF021A20),
    meldBayTop: Color(0xD1032830),
    meldBayBottom: Color(0xC40A4A56),
    backdropPattern: OkeyBackdropPattern.waves,
    rackBoxBack: Color(0xFF5A4A26),
    rackBoxCap: Color(0xFF7A6634),
    rackBoxTop: [Color(0xFFE8D5A0), Color(0xFFB89E5E)],
    rackBoxFront: [Color(0xFFD6BF85), Color(0xFF8A733F)],
    rackBoxGroove: Color(0x8A2E2410),
    rackBoxEdgeBright: Color(0x8AFFF0C8),
    rackBoxEdgeDim: Color(0x4DFFF0C8),
    hudFill: Color(0xD4042A31),
    hudBadgeFill: Color(0xC2032229),
    hudBorder: Color(0x33E6FFFB),
    hudText: Color(0xFFF1FBFA),
    hudTextDim: Color(0x9EE0F7F5),
    hudTextFaint: Color(0x6BE0F7F5),
    actionFill: Color(0xE6053640),
    actionBorder: Color(0x5CBDF2F4),
    actionDisabledFill: Color(0x8A042830),
    actionDisabledBorder: Color(0x24FFFFFF),
    actionDisabledText: Color(0x70FFFFFF),
    actionReady: [Color(0xFFFFD08A), Color(0xFFF08A4B)],
    actionWinning: [Color(0xFFFFE6B8), Color(0xFFFFA33A)],
    onGold: Color(0xFF2B1206),
    v3Surface: Color(0xF0042A31),
    v3SurfaceRaised: Color(0xFF0F5562),
    v3Border: Color(0x40E6FFFB),
    v3BorderStrong: Color(0x66E6FFFB),
    v3SurfaceDisabled: Color(0x9E03242A),
    v3BorderDisabled: Color(0x1FFFFFFF),
    v3Text: Color(0xFFF1FBFA),
    v3TextDim: Color(0xB8E0F7F5),
    v3TextFaint: Color(0x73E0F7F5),
    v3TextDisabled: Color(0x5CFFFFFF),
    v3Gold: [Color(0xFFFFD08A), Color(0xFFF08A4B)],
    v3OnGold: Color(0xFF2B1206),
    v3GoldGlow: Color(0x59FFA33A),
    v3GoldBright: [Color(0xFFFFE6B8), Color(0xFFFFA33A)],
    pairedRackStyleKey: 'zeytin',
  );

  /// Ayarlar ekranında GÖSTERİLDİKLERİ sıra.
  static const List<OkeyTableTheme> all = [
    kahvehane,
    yesilCuha,
    kirmiziKadife,
    geceModu,
    cini,
    saray,
    neon,
    ege,
  ];

  static bool isKnown(String? key) => all.any((t) => t.key == key);

  static OkeyTableTheme byKey(String? key) {
    for (final t in all) {
      if (t.key == key) return t;
    }
    return kahvehane;
  }
}

/// Seçili masa temasını tutan ve cihazda saklayan tek nokta.
///
/// [OkeyRackStylePrefs] ile AYNI desen (bkz. okey_rack_style.dart): maçın
/// değil KULLANICININ tercihi, sunucuya gitmez, tüm okey ekranlarında
/// geçerlidir. `OkeyColors`/`OkeyV3` bu tek örneği okuyarak "canlı sabit"
/// davranışı sağlar.
///
/// ## İki katman: tasarımın masası + oyuncunun seçimi (2026-10-05)
///
/// Etkin tema = oyuncu elle bir masa seçtiyse VE yönetici oyuncu seçimine
/// izin veriyorsa o masa; aksi halde aktif TASARIMIN masası (bkz.
/// `OkeyDesign.tableThemeKey`, [applyDesignDefault]). Oyuncunun seçimi
/// yönetici kilidi açıkken SİLİNMEZ — kilit kalkınca geri gelir.
class OkeyTableThemePrefs {
  static const _prefsKey = 'okey_table_theme';

  static final OkeyTableThemePrefs instance = OkeyTableThemePrefs._();

  OkeyTableThemePrefs._();

  final ValueNotifier<OkeyTableTheme> current = ValueNotifier<OkeyTableTheme>(
    OkeyTableTheme.kahvehane,
  );

  bool _loaded = false;

  /// Oyuncunun elle seçtiği masa (yoksa null).
  String? _userKey;

  /// Aktif tasarımın masası.
  String _designKey = OkeyTableTheme.kahvehane.key;

  bool _userChoiceAllowed = true;

  /// Oyuncu bu cihazda masayı elle seçti mi.
  bool get hasUserChoice => _userKey != null;

  /// Yönetici oyuncunun masa seçmesine izin veriyor mu.
  bool get userChoiceAllowed => _userChoiceAllowed;

  /// Aktif tasarımın önerdiği masa.
  OkeyTableTheme get designDefault => OkeyTableTheme.byKey(_designKey);

  /// Kayıtlı tercihi okur. ASLA hata fırlatmaz — okunamazsa varsayılan kalır.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      _userKey = OkeyTableTheme.isKnown(stored) ? stored : null;
    } catch (_) {
      // tercih okunamadıysa varsayılan tema kullanılır
    }
    _recompute();
  }

  /// Aktif tasarım değişti (bkz. OkeyDesignPrefs).
  void applyDesignDefault(String key, {required bool userChoiceAllowed}) {
    _designKey = key;
    _userChoiceAllowed = userChoiceAllowed;
    _recompute();
  }

  void _recompute() {
    final userKey = _userKey;
    current.value = _userChoiceAllowed && userKey != null
        ? OkeyTableTheme.byKey(userKey)
        : OkeyTableTheme.byKey(_designKey);
  }

  /// Tema seçilir VE eşleşen ıstaka ahşabı da önerilir.
  ///
  /// [alsoPairRackStyle] false verilirse yalnızca masa teması değişir —
  /// kullanıcı ıstakasını zaten elle özelleştirmişse onu ezmemek için
  /// (bkz. OkeyTableThemePicker: kullanıcı daha önce takozunu değiştirdiyse
  /// sorulmadan üzerine yazılmaz).
  ///
  /// Yönetici oyuncu seçimini kapattıysa hiçbir şey yapmaz (seçiciler o
  /// durumda zaten kilitli çizilir).
  Future<void> select(
    OkeyTableTheme theme, {
    bool alsoPairRackStyle = true,
  }) async {
    if (!_userChoiceAllowed) return;
    if (_userKey != theme.key) {
      _userKey = theme.key;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, theme.key);
      } catch (_) {
        // kaydedilemezse seçim bu oturum boyunca geçerli kalır
      }
    }
    _recompute();
    if (alsoPairRackStyle) {
      await OkeyRackStylePrefs.instance.select(
        OkeyRackStyle.byKey(theme.pairedRackStyleKey),
      );
    }
  }

  /// Oyuncunun masa seçimini kaldırır → tasarımın masasına döner.
  Future<void> clearUserChoice() async {
    _userKey = null;
    _recompute();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // yoksayılır
    }
  }
}
