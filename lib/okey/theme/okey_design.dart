import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'okey_rack_style.dart';
import 'okey_table_theme.dart';

/// 101 OKEY TASARIM SİSTEMİ v6 — "tasarım paketleri" (kullanıcı isteği,
/// 2026-10-05: "okey 101 UI/UX anasayfa, oyun içi yeniden tümünü tasarla ve
/// admin yeni UX/UI seçeneği de ekle, 5'ten fazla tasarım ekle").
///
/// ## Masa temasından farkı
///
/// [OkeyTableTheme] yalnızca MASANIN malzemesidir (zemin, HUD camı, taş
/// fildişi) ve oyuncunun kişisel tercihidir. Bir [OkeyDesign] ise modülün
/// TAMAMINI giydirir:
///
///   * lobi, masa kur, bekleme odası, puan, sonuç ekranları ve tüm alt
///     sayfaların renkleri ([OkeyUI] token'ları artık buradan okunur),
///   * şekil dili (kart köşesi, düğme biçimi: yuvarlak / hap / keskin),
///   * yazı dili (başlık yazı tipi, BÜYÜK HARF ya da cümle düzeni),
///   * lobinin arka plan dekoru ve DÜZENİ (UX: Salon / Arena / Kompakt),
///   * eşleşen masa teması ve ıstaka (oyun içi görünüm).
///
/// Hangi tasarımın aktif olduğuna YÖNETİCİ karar verir (Admin › 101 Okey ›
/// Tasarım, `app_settings.okey_design`); yönetici izin verirse oyuncu kendi
/// cihazında başka bir tasarım seçebilir (bkz. [OkeyDesignPrefs]).
///
/// ## Neden her alan açık bir renk, "tohumdan türetilmiş" palet değil
///
/// İki tasarım (İznik Çini, Ege Gündüz) AÇIK zeminlidir. Türetilmiş bir
/// palette "metin" rengi zemin açıldıkça kendiliğinden kararmaz; elle
/// yazılan her değer kontrastı test edilebilir kılar (bkz.
/// test/okey/okey_design_test.dart — metin/kart oranı ≥ 4.5).
enum OkeyLobbyLayout {
  /// Dikey akış: kimlik → büyük "Hemen oyna" kartı → masa listesi.
  salon('Salon', 'Büyük "Hemen oyna" kartı, altında masa listesi'),

  /// Vitrin: istatistikli afiş, hızlı eylem kutuları, canlı masalar şeridi,
  /// açık masalar iki sütunlu ızgarada.
  arena('Arena', 'İstatistikli afiş, canlı masa şeridi, masa ızgarası'),

  /// Hız: sekmeli sıkı liste, "Hemen oyna" ekranın altında hep sabit.
  kompakt('Kompakt', 'Sekmeli sıkı liste, altta sabit "Hemen oyna"');

  final String label;
  final String description;
  const OkeyLobbyLayout(this.label, this.description);

  static OkeyLobbyLayout? byKey(String? key) {
    for (final l in values) {
      if (l.name == key) return l;
    }
    return null;
  }
}

/// Lobi zemininin üstüne çizilen dekor (bkz. okey_design_decor.dart).
enum OkeyDesignDecor {
  none,

  /// Kulüp spotları — iki yumuşak ışık havuzu.
  spotlight,

  /// Kadife kapitone — baklava dikiş çizgileri ve düğmeler.
  quilt,

  /// Gece neonu — ufukta parlayan perspektif ızgara.
  neonGrid,

  /// İznik çinisi — sekiz köşeli yıldız örgüsü.
  cini,

  /// Saray — iç içe geçen kemer (ogee) kafes.
  arabesque,

  /// Ege — kıyıya vuran dalga kavisleri ve güneş.
  waves,
}

/// Düğmelerin biçimi.
enum OkeyButtonShape {
  /// Tasarımın kart köşesiyle aynı yarıçap.
  rounded,

  /// Tam yuvarlak uçlu hap.
  pill,

  /// Neredeyse köşeli, teknik görünüm.
  sharp,
}

@immutable
class OkeyDesign {
  /// Sunucuda (`app_settings.okey_design`) ve cihazda saklanan anahtar.
  /// Ad değişse bile SABİT kalır.
  final String key;
  final String label;

  /// Seçim kartındaki tek satırlık tanım.
  final String tagline;

  final Brightness brightness;
  final OkeyLobbyLayout layout;
  final OkeyDesignDecor decor;

  // --- Zemin ---------------------------------------------------------------
  final List<Color> screenGradient;
  final List<double> screenStops;

  /// Dekor çizgilerinin rengi (alfa dekor tarafından ayrıca düşürülür).
  final Color decorColor;

  // --- Kartlar ---------------------------------------------------------------
  final Color cardFill;
  final Color cardFillRaised;
  final Color cardBorder;
  final Color shadow;

  // --- Vurgu (birincil eylem) -------------------------------------------------
  final List<Color> accentGradient;
  final Color onAccent;

  /// Tek vurgu rengi: seçili çip, vurgulu kart kenarı, rozet.
  final Color accent;

  /// Birincil düğmenin altındaki "basılabilir kalınlık".
  final Color accentEdge;

  /// Kart/hap üstündeki vurgulu sayılar (çip bakiyesi, masa bedeli).
  final Color accentText;

  final Color sectionLabel;

  // --- İkincil yüzeyler ---------------------------------------------------------
  final Color secondaryFill;
  final Color secondaryBorder;
  final Color ghostBorder;
  final Color dangerFill;
  final Color dangerText;
  final Color dangerBorder;
  final Color navFill;
  final Color pillFill;
  final Color pillBorder;
  final Color errorText;

  // --- "Hemen oyna" afişi ------------------------------------------------------
  final List<Color> heroGradient;
  final Color onHero;
  final Color onHeroDim;

  // --- Kuş bakışı masa (OkeySeatMini) ------------------------------------------
  final Color miniFelt;
  final Color miniRim;
  final Color seatEmpty;

  // --- Avatar yer tutucusu ----------------------------------------------------
  final Color avatarFill;
  final Color avatarIcon;

  // --- Kazanç kartlarının anlam renkleri -------------------------------------
  final Color giftColor;
  final Color adColor;

  // --- Metin ------------------------------------------------------------------
  final Color text;
  final Color textDim;
  final Color textFaint;

  // --- Şekil ve yazı ------------------------------------------------------------
  final double radius;
  final double radiusSm;
  final double radiusLg;
  final double heroRadius;
  final OkeyButtonShape buttonShape;

  /// `true` → düğme etiketleri ve bölüm başlıkları BÜYÜK HARF; `false` →
  /// cümle düzeni ("Masa kur"). Türkçe İ/ı kurallarıyla çevrilir.
  final bool uppercase;

  /// Başlık yazı tipi; `null` → sistem yazı tipi (Roboto / SF).
  final String? displayFont;
  final FontWeight displayWeight;
  final double displayLetterSpacing;

  /// Vurgulu kartlar ve birincil düğme kalınlık yerine IŞIK yayar (neon).
  final bool glow;

  // --- Oyun içi eşleşme --------------------------------------------------------
  /// Bu tasarımla gelen masa teması (bkz. [OkeyTableTheme.byKey]).
  final String tableThemeKey;

  /// Bu tasarımla gelen ıstaka (bkz. [OkeyRackStyle.byKey]).
  final String rackStyleKey;

  const OkeyDesign({
    required this.key,
    required this.label,
    required this.tagline,
    required this.brightness,
    required this.layout,
    required this.decor,
    required this.screenGradient,
    required this.screenStops,
    required this.decorColor,
    required this.cardFill,
    required this.cardFillRaised,
    required this.cardBorder,
    required this.shadow,
    required this.accentGradient,
    required this.onAccent,
    required this.accent,
    required this.accentEdge,
    required this.accentText,
    required this.sectionLabel,
    required this.secondaryFill,
    required this.secondaryBorder,
    required this.ghostBorder,
    required this.dangerFill,
    required this.dangerText,
    required this.dangerBorder,
    required this.navFill,
    required this.pillFill,
    required this.pillBorder,
    required this.errorText,
    required this.heroGradient,
    required this.onHero,
    required this.onHeroDim,
    required this.miniFelt,
    required this.miniRim,
    required this.seatEmpty,
    required this.avatarFill,
    required this.avatarIcon,
    required this.giftColor,
    required this.adColor,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.radius,
    required this.radiusSm,
    required this.radiusLg,
    required this.heroRadius,
    required this.buttonShape,
    required this.uppercase,
    required this.displayFont,
    required this.displayWeight,
    required this.displayLetterSpacing,
    required this.glow,
    required this.tableThemeKey,
    required this.rackStyleKey,
  });

  bool get isLight => brightness == Brightness.light;

  /// Düğme köşe yarıçapı ([buttonShape]'e göre).
  double get buttonRadius => switch (buttonShape) {
    OkeyButtonShape.rounded => radius,
    OkeyButtonShape.pill => 999,
    OkeyButtonShape.sharp => 6,
  };

  OkeyTableTheme get tableTheme => OkeyTableTheme.byKey(tableThemeKey);
  OkeyRackStyle get rackStyle => OkeyRackStyle.byKey(rackStyleKey);

  // ===========================================================================
  // HAZIR TASARIMLAR
  // ===========================================================================

  /// SALON — 2026-09-20 Salon turunun dili: espresso zemin, ceviz kartlar,
  /// pirinç vurgu, turkuaz kahvehane masası. Varsayılan: mevcut oyuncu hiçbir
  /// şeyin değişmediğini görür.
  static const salon = OkeyDesign(
    key: 'salon',
    label: 'Salon',
    tagline: 'Espresso ve pirinç — klasik kahvehane salonu',
    brightness: Brightness.dark,
    layout: OkeyLobbyLayout.salon,
    decor: OkeyDesignDecor.none,
    screenGradient: [Color(0xFF14322E), Color(0xFF120C09), Color(0xFF0D0806)],
    screenStops: [0, 0.38, 1],
    decorColor: Color(0xFFF5EBD8),
    cardFill: Color(0xFF1F1811),
    cardFillRaised: Color(0xFF2B2018),
    cardBorder: Color(0x24FFF0D2),
    shadow: Color(0x4D000000),
    accentGradient: [Color(0xFFF5CB6A), Color(0xFFD9972A)],
    onAccent: Color(0xFF2A1A05),
    accent: Color(0xFFE4B04C),
    accentEdge: Color(0xFF9A6A17),
    accentText: Color(0xFFFFE7A8),
    sectionLabel: Color(0xFFF0C462),
    secondaryFill: Color(0xFF2B2018),
    secondaryBorder: Color(0x3DFFF0D2),
    ghostBorder: Color(0x59FFF0D2),
    dangerFill: Color(0xFF7A2733),
    dangerText: Color(0xFFFFD9DE),
    dangerBorder: Color(0x4DFF8A9B),
    navFill: Color(0xFF0D0806),
    pillFill: Color(0x99120C09),
    pillBorder: Color(0x80E4B04C),
    errorText: Color(0xFFFF9AA6),
    heroGradient: [Color(0xFF1B7562), Color(0xFF0F4A45), Color(0xFF0A3532)],
    onHero: Color(0xFFF5EBD8),
    onHeroDim: Color(0xD9F5EBD8),
    miniFelt: Color(0xFF17705F),
    miniRim: Color(0xFF5B3A22),
    seatEmpty: Color(0x73F5EBD8),
    avatarFill: Color(0xFF2B2018),
    avatarIcon: Color(0xFFC9B88F),
    giftColor: Color(0xFF9CCC65),
    adColor: Color(0xFF80D8FF),
    text: Color(0xFFF5EBD8),
    textDim: Color(0xC7F5EBD8),
    textFaint: Color(0x94F5EBD8),
    radius: 14,
    radiusSm: 10,
    radiusLg: 20,
    heroRadius: 24,
    buttonShape: OkeyButtonShape.rounded,
    uppercase: true,
    displayFont: 'Fraunces',
    displayWeight: FontWeight.w800,
    displayLetterSpacing: 0,
    glow: false,
    tableThemeKey: 'kahvehane',
    rackStyleKey: 'ceviz',
  );

  /// ZÜMRÜT KULÜP — yeşil çuhalı özel kulüp: zümrüt cam, altın, spot ışığı.
  /// ARENA düzeniyle gelir (vitrin + masa ızgarası).
  static const zumrut = OkeyDesign(
    key: 'zumrut',
    label: 'Zümrüt Kulüp',
    tagline: 'Zümrüt cam, altın, spot ışığı — özel kulüp',
    brightness: Brightness.dark,
    layout: OkeyLobbyLayout.arena,
    decor: OkeyDesignDecor.spotlight,
    screenGradient: [Color(0xFF0F4A3A), Color(0xFF082A21), Color(0xFF041712)],
    screenStops: [0, 0.45, 1],
    decorColor: Color(0xFFFFE3A0),
    cardFill: Color(0xFF0D2C23),
    cardFillRaised: Color(0xFF143A2E),
    cardBorder: Color(0x2E9FF2CF),
    shadow: Color(0x59000000),
    accentGradient: [Color(0xFFF8DB7E), Color(0xFFCF9B2E)],
    onAccent: Color(0xFF1F1503),
    accent: Color(0xFFE5BC4F),
    accentEdge: Color(0xFF8C6414),
    accentText: Color(0xFFFFEDB3),
    sectionLabel: Color(0xFF7FE3BF),
    secondaryFill: Color(0xFF143A2E),
    secondaryBorder: Color(0x3D9FF2CF),
    ghostBorder: Color(0x599FF2CF),
    dangerFill: Color(0xFF7A2733),
    dangerText: Color(0xFFFFD9DE),
    dangerBorder: Color(0x4DFF8A9B),
    navFill: Color(0xFF03130F),
    pillFill: Color(0x99031510),
    pillBorder: Color(0x80E5BC4F),
    errorText: Color(0xFFFF9AA6),
    heroGradient: [Color(0xFF177A57), Color(0xFF0F5A43), Color(0xFF093A2C)],
    onHero: Color(0xFFF4FFF9),
    onHeroDim: Color(0xD9F4FFF9),
    miniFelt: Color(0xFF1F7A4C),
    miniRim: Color(0xFF6B4A1B),
    seatEmpty: Color(0x73EAF6EF),
    avatarFill: Color(0xFF143A2E),
    avatarIcon: Color(0xFFA9D8C2),
    giftColor: Color(0xFFB2E07A),
    adColor: Color(0xFF7FD6FF),
    text: Color(0xFFEAF6EF),
    textDim: Color(0xC2EAF6EF),
    textFaint: Color(0x8CEAF6EF),
    radius: 18,
    radiusSm: 12,
    radiusLg: 24,
    heroRadius: 28,
    buttonShape: OkeyButtonShape.pill,
    uppercase: true,
    displayFont: 'Fraunces',
    displayWeight: FontWeight.w800,
    displayLetterSpacing: 0,
    glow: false,
    tableThemeKey: 'yesil_cuha',
    rackStyleKey: 'mese',
  );

  /// BORDO KADİFE — kapitone kadife koltuklu salon, şampanya altını.
  static const bordo = OkeyDesign(
    key: 'bordo',
    label: 'Bordo Kadife',
    tagline: 'Kapitone kadife, şampanya altını — lüks salon',
    brightness: Brightness.dark,
    layout: OkeyLobbyLayout.salon,
    decor: OkeyDesignDecor.quilt,
    screenGradient: [Color(0xFF4A1020), Color(0xFF2A0812), Color(0xFF16040A)],
    screenStops: [0, 0.42, 1],
    decorColor: Color(0xFFF3D9A8),
    cardFill: Color(0xFF2F0C16),
    cardFillRaised: Color(0xFF3E1320),
    cardBorder: Color(0x33F3D9A8),
    shadow: Color(0x59000000),
    accentGradient: [Color(0xFFF6E2B0), Color(0xFFC99A58)],
    onAccent: Color(0xFF2A1408),
    accent: Color(0xFFE9C68A),
    accentEdge: Color(0xFF8C6232),
    accentText: Color(0xFFFFEBC4),
    sectionLabel: Color(0xFFF0C98C),
    secondaryFill: Color(0xFF3E1320),
    secondaryBorder: Color(0x40F3D9A8),
    ghostBorder: Color(0x66F3D9A8),
    dangerFill: Color(0xFF8E1F2F),
    dangerText: Color(0xFFFFE3E6),
    dangerBorder: Color(0x80FF9AA6),
    navFill: Color(0xFF12030A),
    pillFill: Color(0x99140409),
    pillBorder: Color(0x80E9C68A),
    errorText: Color(0xFFFFB3BC),
    heroGradient: [Color(0xFF8C2238), Color(0xFF5E1426), Color(0xFF3A0B17)],
    onHero: Color(0xFFFFF4EE),
    onHeroDim: Color(0xD9FFF4EE),
    miniFelt: Color(0xFF7A1F30),
    miniRim: Color(0xFF4A2410),
    seatEmpty: Color(0x73FBEFEA),
    avatarFill: Color(0xFF3E1320),
    avatarIcon: Color(0xFFE6C0B0),
    giftColor: Color(0xFFB5DA80),
    adColor: Color(0xFF9AD7FF),
    text: Color(0xFFFBEFEA),
    textDim: Color(0xC4FBEFEA),
    textFaint: Color(0x8FFBEFEA),
    radius: 12,
    radiusSm: 8,
    radiusLg: 18,
    heroRadius: 20,
    buttonShape: OkeyButtonShape.rounded,
    uppercase: true,
    displayFont: 'Fraunces',
    displayWeight: FontWeight.w800,
    displayLetterSpacing: 0.2,
    glow: false,
    tableThemeKey: 'kirmizi_kadife',
    rackStyleKey: 'maun',
  );

  /// GECE NEON — e-spor salonu: mürdüm gece, camgöbeği/eflatun neon, keskin
  /// köşeler, sistem yazı tipi. ARENA düzeniyle gelir.
  static const neon = OkeyDesign(
    key: 'neon',
    label: 'Gece Neon',
    tagline: 'Camgöbeği neon, keskin hatlar — e-spor salonu',
    brightness: Brightness.dark,
    layout: OkeyLobbyLayout.arena,
    decor: OkeyDesignDecor.neonGrid,
    screenGradient: [Color(0xFF1A0F3D), Color(0xFF0C0822), Color(0xFF050411)],
    screenStops: [0, 0.45, 1],
    decorColor: Color(0xFF35E8FF),
    cardFill: Color(0xFF140F33),
    cardFillRaised: Color(0xFF1D1747),
    cardBorder: Color(0x4D7C5CFF),
    shadow: Color(0x66000000),
    accentGradient: [Color(0xFF3DF5FF), Color(0xFF8F7BFF)],
    onAccent: Color(0xFF07051C),
    accent: Color(0xFF35E8FF),
    accentEdge: Color(0xFF5B3FD6),
    accentText: Color(0xFFA6F7FF),
    sectionLabel: Color(0xFFFF6BDC),
    secondaryFill: Color(0xFF1D1747),
    secondaryBorder: Color(0x667C5CFF),
    ghostBorder: Color(0x8035E8FF),
    dangerFill: Color(0xFF6A1340),
    dangerText: Color(0xFFFFD6EC),
    dangerBorder: Color(0x80FF5ED8),
    navFill: Color(0xFF07051A),
    pillFill: Color(0x9907051A),
    pillBorder: Color(0x9935E8FF),
    errorText: Color(0xFFFF9ACD),
    heroGradient: [Color(0xFF3A1E8C), Color(0xFF1F1259), Color(0xFF120B36)],
    onHero: Color(0xFFFFFFFF),
    onHeroDim: Color(0xD9E8E2FF),
    miniFelt: Color(0xFF20175C),
    miniRim: Color(0xFF35E8FF),
    seatEmpty: Color(0x73F2EEFF),
    avatarFill: Color(0xFF1D1747),
    avatarIcon: Color(0xFFB9A8FF),
    giftColor: Color(0xFF7CFFB2),
    adColor: Color(0xFF35E8FF),
    text: Color(0xFFF2EEFF),
    textDim: Color(0xC2F2EEFF),
    textFaint: Color(0x8CF2EEFF),
    radius: 8,
    radiusSm: 6,
    radiusLg: 12,
    heroRadius: 14,
    buttonShape: OkeyButtonShape.sharp,
    uppercase: true,
    displayFont: null,
    displayWeight: FontWeight.w900,
    displayLetterSpacing: 0.8,
    glow: true,
    tableThemeKey: 'neon',
    rackStyleKey: 'neon',
  );

  /// İZNİK ÇİNİ — AÇIK zemin: porselen krem, kobalt mavi, mercan kırmızısı;
  /// sekiz köşeli yıldız örgüsü. KOMPAKT düzenle gelir.
  static const cini = OkeyDesign(
    key: 'cini',
    label: 'İznik Çini',
    tagline: 'Porselen beyazı, kobalt ve mercan — gündüz salonu',
    brightness: Brightness.light,
    layout: OkeyLobbyLayout.kompakt,
    decor: OkeyDesignDecor.cini,
    screenGradient: [Color(0xFFFBF7EF), Color(0xFFF3ECDF), Color(0xFFEDE3D1)],
    screenStops: [0, 0.5, 1],
    decorColor: Color(0xFF1F58C2),
    cardFill: Color(0xFFFFFFFF),
    cardFillRaised: Color(0xFFF4EFE5),
    cardBorder: Color(0x2E1E4FA3),
    shadow: Color(0x1F1B2A4A),
    accentGradient: [Color(0xFF3A78E0), Color(0xFF1D46A0)],
    onAccent: Color(0xFFFFFFFF),
    accent: Color(0xFF1F58C2),
    accentEdge: Color(0xFF14306E),
    accentText: Color(0xFF1D46A0),
    sectionLabel: Color(0xFFB8321F),
    secondaryFill: Color(0xFFEFF3FB),
    secondaryBorder: Color(0x401F58C2),
    ghostBorder: Color(0x661F58C2),
    dangerFill: Color(0xFFFCE8E6),
    dangerText: Color(0xFFB3261E),
    dangerBorder: Color(0x66B3261E),
    navFill: Color(0xFFFFFFFF),
    pillFill: Color(0xFFFFFFFF),
    pillBorder: Color(0x661F58C2),
    errorText: Color(0xFFB3261E),
    heroGradient: [Color(0xFF2D63C8), Color(0xFF1C428F), Color(0xFF12306B)],
    onHero: Color(0xFFFFFFFF),
    onHeroDim: Color(0xE6FFFFFF),
    // Turkuaz çuha + kobalt kenar: dolu koltuklar (kobalt vurgu) çuhadan
    // ayrışsın — mavi çuhada mavi koltuk görünmüyordu.
    miniFelt: Color(0xFF138A8F),
    miniRim: Color(0xFF1C428F),
    seatEmpty: Color(0x8018213D),
    avatarFill: Color(0xFFE9EEF8),
    avatarIcon: Color(0xFF5C6A8C),
    giftColor: Color(0xFF2E7D4F),
    adColor: Color(0xFF0B6E75),
    text: Color(0xFF18213D),
    textDim: Color(0xFF46506B),
    textFaint: Color(0xFF6E7590),
    radius: 16,
    radiusSm: 10,
    radiusLg: 22,
    heroRadius: 24,
    buttonShape: OkeyButtonShape.rounded,
    uppercase: false,
    displayFont: 'Fraunces',
    displayWeight: FontWeight.w800,
    displayLetterSpacing: 0,
    glow: false,
    tableThemeKey: 'cini',
    rackStyleKey: 'kobalt',
  );

  /// OSMANLI SARAY — patlıcan moru kadife, varak altın, kemer kafes dekoru.
  static const saray = OkeyDesign(
    key: 'saray',
    label: 'Osmanlı Saray',
    tagline: 'Mor kadife, varak altın, kemer kafes — saray odası',
    brightness: Brightness.dark,
    layout: OkeyLobbyLayout.salon,
    decor: OkeyDesignDecor.arabesque,
    screenGradient: [Color(0xFF3A1A4F), Color(0xFF1E0D2B), Color(0xFF110719)],
    screenStops: [0, 0.42, 1],
    decorColor: Color(0xFFE9C25B),
    cardFill: Color(0xFF24112F),
    cardFillRaised: Color(0xFF31183F),
    cardBorder: Color(0x40E9C25B),
    shadow: Color(0x59000000),
    accentGradient: [Color(0xFFFFE6A3), Color(0xFFD4A437)],
    onAccent: Color(0xFF2A1A05),
    accent: Color(0xFFE9C25B),
    accentEdge: Color(0xFF8F6A16),
    accentText: Color(0xFFFFEDB8),
    sectionLabel: Color(0xFFE9C25B),
    secondaryFill: Color(0xFF31183F),
    secondaryBorder: Color(0x4DE9C25B),
    ghostBorder: Color(0x80E9C25B),
    dangerFill: Color(0xFF7A2733),
    dangerText: Color(0xFFFFD9DE),
    dangerBorder: Color(0x4DFF8A9B),
    navFill: Color(0xFF0F0616),
    pillFill: Color(0x990F0616),
    pillBorder: Color(0x99E9C25B),
    errorText: Color(0xFFFF9AA6),
    heroGradient: [Color(0xFF5B2A7A), Color(0xFF3A1A52), Color(0xFF241033)],
    onHero: Color(0xFFFFF5E6),
    onHeroDim: Color(0xD9FFF5E6),
    miniFelt: Color(0xFF4E2370),
    miniRim: Color(0xFFB8892B),
    seatEmpty: Color(0x73FFF5E6),
    avatarFill: Color(0xFF31183F),
    avatarIcon: Color(0xFFE0C9A6),
    giftColor: Color(0xFFB7E08A),
    adColor: Color(0xFF9FD8FF),
    text: Color(0xFFFFF5E6),
    textDim: Color(0xC4FFF5E6),
    textFaint: Color(0x8FFFF5E6),
    radius: 20,
    radiusSm: 12,
    radiusLg: 26,
    heroRadius: 30,
    buttonShape: OkeyButtonShape.rounded,
    uppercase: true,
    displayFont: 'Fraunces',
    displayWeight: FontWeight.w800,
    displayLetterSpacing: 0.3,
    glow: false,
    tableThemeKey: 'saray',
    rackStyleKey: 'abanoz',
  );

  /// EGE GÜNDÜZ — AÇIK zemin: deniz köpüğü, kum, kiremit; hap düğmeler,
  /// sistem yazı tipi, cümle düzeni. KOMPAKT düzenle gelir.
  static const ege = OkeyDesign(
    key: 'ege',
    label: 'Ege Gündüz',
    tagline: 'Deniz köpüğü, kum ve kiremit — sahil kahvesi',
    brightness: Brightness.light,
    layout: OkeyLobbyLayout.kompakt,
    decor: OkeyDesignDecor.waves,
    screenGradient: [Color(0xFFE3F3F2), Color(0xFFF2F1E9), Color(0xFFF8F3EA)],
    screenStops: [0, 0.5, 1],
    decorColor: Color(0xFF0E7C86),
    cardFill: Color(0xFFFFFFFF),
    cardFillRaised: Color(0xFFF0F6F5),
    cardBorder: Color(0x2E0E7C86),
    shadow: Color(0x1F0B3A40),
    accentGradient: [Color(0xFFF6A576), Color(0xFFE57A4C)],
    onAccent: Color(0xFF2B1206),
    accent: Color(0xFFE07A4A),
    accentEdge: Color(0xFFB4512A),
    accentText: Color(0xFFAA4A23),
    sectionLabel: Color(0xFF0B6F78),
    secondaryFill: Color(0xFFEAF5F4),
    secondaryBorder: Color(0x400E7C86),
    ghostBorder: Color(0x660E7C86),
    dangerFill: Color(0xFFFCE8E6),
    dangerText: Color(0xFFB3261E),
    dangerBorder: Color(0x66B3261E),
    navFill: Color(0xFFFFFFFF),
    pillFill: Color(0xFFFFFFFF),
    pillBorder: Color(0x66E07A4A),
    errorText: Color(0xFFB3261E),
    heroGradient: [Color(0xFF14808C), Color(0xFF0F6670), Color(0xFF0A4A52)],
    onHero: Color(0xFFFFFFFF),
    onHeroDim: Color(0xE6FFFFFF),
    miniFelt: Color(0xFF1F9AA6),
    miniRim: Color(0xFFD9B98A),
    seatEmpty: Color(0x8012353A),
    avatarFill: Color(0xFFE6F2F1),
    avatarIcon: Color(0xFF5D8086),
    giftColor: Color(0xFF2F7D3D),
    adColor: Color(0xFF15708F),
    text: Color(0xFF12353A),
    textDim: Color(0xFF41646A),
    textFaint: Color(0xFF6A878B),
    radius: 22,
    radiusSm: 14,
    radiusLg: 28,
    heroRadius: 28,
    buttonShape: OkeyButtonShape.pill,
    uppercase: false,
    displayFont: null,
    displayWeight: FontWeight.w800,
    displayLetterSpacing: -0.2,
    glow: false,
    tableThemeKey: 'ege',
    rackStyleKey: 'zeytin',
  );

  /// Seçim ekranlarında GÖSTERİLDİKLERİ sıra.
  static const List<OkeyDesign> all = [
    salon,
    zumrut,
    bordo,
    neon,
    cini,
    saray,
    ege,
  ];

  static const OkeyDesign fallback = salon;

  /// Bilinmeyen/boş anahtar → [fallback]. Sunucuda yeni bir tasarım
  /// anahtarı yazılıp eski bir istemci açıldığında modül çökmesin.
  static OkeyDesign byKey(String? key) {
    for (final d in all) {
      if (d.key == key) return d;
    }
    return fallback;
  }

  static bool isKnown(String? key) => all.any((d) => d.key == key);
}

/// Yöneticinin sunucuda belirlediği tasarım ayarı
/// (`public.okey_design_config()`).
@immutable
class OkeyDesignConfig {
  /// Herkesin gördüğü tasarım.
  final String designKey;

  /// Lobi düzeni geçersiz kılması; `null` → tasarımın kendi düzeni.
  final OkeyLobbyLayout? layout;

  /// Oyuncu kendi cihazında başka tasarım/masa/ıstaka seçebilir mi.
  final bool userChoice;

  const OkeyDesignConfig({
    required this.designKey,
    this.layout,
    this.userChoice = true,
  });

  static const defaults = OkeyDesignConfig(designKey: 'salon');

  /// RPC yanıtını çözer; bozuk/eksik alanlar varsayılana düşer.
  factory OkeyDesignConfig.fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    final design = raw['design'];
    final layout = raw['layout'];
    final choice = raw['user_choice'];
    return OkeyDesignConfig(
      designKey: design is String && design.isNotEmpty ? design : 'salon',
      layout: layout is String ? OkeyLobbyLayout.byKey(layout) : null,
      userChoice: choice is bool
          ? choice
          : choice is String
          ? choice.toLowerCase() != 'false'
          : true,
    );
  }

  Map<String, Object?> toJson() => {
    'design': designKey,
    'layout': layout?.name ?? 'auto',
    'user_choice': userChoice,
  };

  @override
  bool operator ==(Object other) =>
      other is OkeyDesignConfig &&
      other.designKey == designKey &&
      other.layout == layout &&
      other.userChoice == userChoice;

  @override
  int get hashCode => Object.hash(designKey, layout, userChoice);
}

/// AKTİF tasarımı tutan tek nokta.
///
/// Etkin tasarım = (yönetici izin veriyorsa VE oyuncu cihazında bir seçim
/// yaptıysa) oyuncunun seçimi, aksi halde yöneticinin tasarımı. Her
/// hesaplamada eşleşen masa teması ve ıstaka da güncellenir (bkz.
/// [OkeyTableThemePrefs.applyDesignDefault]) — oyuncu masayı ayrıca elle
/// değiştirmediyse masa da tasarımla birlikte gelir.
///
/// Yöneticinin son ayarı cihazda önbelleğe alınır: bir sonraki açılışta lobi
/// ağ yanıtını beklemeden doğru tasarımla çizilir (aksi halde ilk karede
/// varsayılan tasarım görünüp hemen değişirdi).
class OkeyDesignPrefs {
  static const _adminCacheKey = 'okey_design_admin_cache';
  static const _userKey = 'okey_design_user';

  static final OkeyDesignPrefs instance = OkeyDesignPrefs._();

  OkeyDesignPrefs._();

  /// Etkin tasarım — [OkeyUI] token'ları buradan okur.
  final ValueNotifier<OkeyDesign> current = ValueNotifier<OkeyDesign>(
    OkeyDesign.fallback,
  );

  /// Etkin lobi düzeni (yönetici geçersiz kılması > tasarımın düzeni).
  final ValueNotifier<OkeyLobbyLayout> layout = ValueNotifier<OkeyLobbyLayout>(
    OkeyDesign.fallback.layout,
  );

  OkeyDesignConfig _admin = OkeyDesignConfig.defaults;
  String? _user;
  bool _loaded = false;

  OkeyDesignConfig get adminConfig => _admin;

  /// Oyuncunun cihazındaki seçimi (yoksa null).
  String? get userDesignKey => _user;

  /// Oyuncu tasarım/masa/ıstaka seçebilir mi (yönetici anahtarı).
  bool get userChoiceAllowed => _admin.userChoice;

  /// Ekranların tek dinleyicisi: tasarım ya da düzen değişince yeniden çiz.
  Listenable get listenable => Listenable.merge([current, layout]);

  /// Cihazdaki önbelleği ve oyuncu seçimini okur. ASLA hata fırlatmaz.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_adminCacheKey);
      if (cached != null) _admin = _decodeCache(cached);
      _user = prefs.getString(_userKey);
    } catch (_) {
      // okunamazsa varsayılan tasarım kalır
    }
    await Future.wait([
      OkeyTableThemePrefs.instance.load(),
      OkeyRackStylePrefs.instance.load(),
    ]);
    _recompute();
  }

  /// Sunucudan gelen yönetici ayarını uygular ve önbelleğe yazar.
  Future<void> applyAdminConfig(OkeyDesignConfig config) async {
    final changed = config != _admin;
    _admin = config;
    _recompute();
    if (!changed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = config.toJson();
      await prefs.setString(
        _adminCacheKey,
        '${c['design']}|${c['layout']}|${c['user_choice']}',
      );
    } catch (_) {
      // önbellek yazılamazsa yalnızca bir sonraki açılış ağ yanıtını bekler
    }
  }

  /// Oyuncunun kendi cihazındaki tasarım seçimi.
  ///
  /// Tasarım değişince oyuncunun ELLE seçtiği masa/ıstaka sıfırlanır: yeni
  /// tasarım "tam paket" olarak görünsün (oyuncu sonra yine değiştirebilir).
  Future<void> selectByUser(OkeyDesign design) async {
    if (!userChoiceAllowed) return;
    _user = design.key;
    await OkeyTableThemePrefs.instance.clearUserChoice();
    await OkeyRackStylePrefs.instance.clearUserChoice();
    _recompute();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, design.key);
    } catch (_) {
      // kaydedilemezse seçim bu oturum boyunca geçerli kalır
    }
  }

  /// Oyuncu seçimini kaldırır → yöneticinin tasarımına döner.
  Future<void> clearUserChoice() async {
    _user = null;
    await OkeyTableThemePrefs.instance.clearUserChoice();
    await OkeyRackStylePrefs.instance.clearUserChoice();
    _recompute();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userKey);
    } catch (_) {
      // yoksayılır
    }
  }

  void _recompute() {
    final userKey = _user;
    final design = userChoiceAllowed && OkeyDesign.isKnown(userKey)
        ? OkeyDesign.byKey(userKey)
        : OkeyDesign.byKey(_admin.designKey);
    current.value = design;
    layout.value = _admin.layout ?? design.layout;
    OkeyTableThemePrefs.instance.applyDesignDefault(
      design.tableThemeKey,
      userChoiceAllowed: userChoiceAllowed,
    );
    OkeyRackStylePrefs.instance.applyDesignDefault(
      design.rackStyleKey,
      userChoiceAllowed: userChoiceAllowed,
    );
  }

  static OkeyDesignConfig _decodeCache(String raw) {
    final parts = raw.split('|');
    if (parts.length != 3) return OkeyDesignConfig.defaults;
    return OkeyDesignConfig(
      designKey: parts[0].isEmpty ? 'salon' : parts[0],
      layout: OkeyLobbyLayout.byKey(parts[1]),
      userChoice: parts[2] != 'false',
    );
  }

  /// Testler için: belleği sıfırlar (SharedPreferences'a dokunmaz).
  @visibleForTesting
  void debugReset({
    OkeyDesignConfig admin = OkeyDesignConfig.defaults,
    String? user,
  }) {
    _admin = admin;
    _user = user;
    _loaded = true;
    _recompute();
  }
}

// =============================================================================
// TÜRKÇE BÜYÜK/KÜÇÜK HARF
// =============================================================================

/// Türkçe büyük harf: `i → İ`, `ı → I`. Dart'ın `toUpperCase()`'i "i"yi
/// noktasız "I" yapıyordu ("Seni davet edenler" → "SENI DAVET EDENLER").
String okeyUpperTr(String s) =>
    s.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Türkçe küçük harf: `I → ı`, `İ → i`.
String okeyLowerTr(String s) =>
    s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// "MASA KUR" → "Masa kur". Yalnızca baş harf büyük kalır.
String okeySentenceTr(String s) {
  final lower = okeyLowerTr(s.trim());
  if (lower.isEmpty) return lower;
  return okeyUpperTr(lower.substring(0, 1)) + lower.substring(1);
}
