// Avatar kataloğu ve tarifi.
//
// Her parça (yüz şekli, saç, kaş, göz, burun, dudak, sakal, gözlük, başlık…)
// tek tek elle çizilmiş bir path değil, PARAMETRİK BİR TARİF (spec). Çizim
// motoru bu tariflere göre üretir; katalog büyütmek yeni bir satır eklemek
// demektir.
//
// Katalog (yaklaşık): 12 yüz şekli × 14 ten × 90 saç × 22 saç rengi × 22 kaş
// × 18 göz × 12 göz rengi × 14 makyaj × 10 burun × 10 dudak × 42 sakal
// × 18 gözlük × 16 başlık × 10 takı × 14 detay × 12 kıyafet × 14 arka plan.
//
// Bunların bir kısmı fotoğraftan ÖLÇÜLEREK seçilir (yüz şekli, göz şekli, kaş
// kalınlığı, saç uzunluğu, sakal yoğunluğu, ten/saç/göz rengi), kalanı
// kullanıcının tercihidir.
import 'dart:math' as math;

import 'package:flutter/material.dart';

enum FaceAvatarCategory {
  faceShape,
  skin,
  hair,
  brow,
  eye,
  lash,
  nose,
  lips,
  beard,
  glasses,
  headwear,
  jewelry,
  detail,
  clothing,
  background,
}

// ---------------------------------------------------------------- paletler

const List<Color> kSkinTones = [
  Color(0xFFFFE4D2),
  Color(0xFFFBD8C0),
  Color(0xFFF4C9A8),
  Color(0xFFEBB68F),
  Color(0xFFE2A578),
  Color(0xFFD5956A),
  Color(0xFFC58559),
  Color(0xFFB27448),
  Color(0xFF9E6238),
  Color(0xFF8A5030),
  Color(0xFF744027),
  Color(0xFF5F3220),
  Color(0xFF4A2618),
  Color(0xFF3A1D12),
];

/// İlk [kNaturalHairColorCount] renk doğal; gerisi boyalı (fantezi) renkler.
/// Fotoğraf analizi yalnızca doğal renkler arasından seçer.
const int kNaturalHairColorCount = 15;

const List<Color> kHairColors = [
  Color(0xFF15100D), // simsiyah
  Color(0xFF241810), // siyah-kahve
  Color(0xFF382519), // koyu kahve
  Color(0xFF52341F), // kahve
  Color(0xFF6B4226), // kestane
  Color(0xFF85552F), // açık kahve
  Color(0xFFA47842), // bal kahve
  Color(0xFFBB8C4E), // koyu sarı
  Color(0xFFD3B071), // sarı
  Color(0xFFE6CD95), // açık sarı
  Color(0xFFE9DFC6), // platin
  Color(0xFFA9481F), // kızıl
  Color(0xFF7A2C1B), // kızıl kahve
  Color(0xFF979CA3), // gri
  Color(0xFFD9DCE0), // gümüş
  // ---- fantezi renkler
  Color(0xFFE78FB4), // pastel pembe
  Color(0xFF3B6BD0), // mavi
  Color(0xFF7A4CC0), // mor
  Color(0xFF2FA58E), // turkuaz
  Color(0xFFC62D4B), // şarap kırmızısı
  Color(0xFFF09A3E), // turuncu
  Color(0xFF6E1F3E), // bordo
];

const List<Color> kEyeColors = [
  Color(0xFF2E1B10), // çok koyu kahve
  Color(0xFF4A2E1C), // koyu kahve
  Color(0xFF6B4423), // kahve
  Color(0xFF8C6B3F), // ela
  Color(0xFFA57A2F), // kehribar
  Color(0xFF6E7A3C), // yeşilimsi ela
  Color(0xFF4F7A52), // yeşil
  Color(0xFF3C7A80), // mavi-yeşil
  Color(0xFF3F6E96), // mavi
  Color(0xFF6E9CC2), // açık mavi
  Color(0xFF6E8A9B), // gri mavi
  Color(0xFF8A9096), // gri
];

const List<Color> kClothingColors = [
  Color(0xFF2F3A4A),
  Color(0xFF3F5E8C),
  Color(0xFF7A3B52),
  Color(0xFF2E6B5B),
  Color(0xFF8A5A2B),
  Color(0xFF4A4A52),
  Color(0xFF1F2430),
  Color(0xFFB5443A),
  Color(0xFFD9A441),
  Color(0xFF5B4B8A),
  Color(0xFFE8E4DA),
  Color(0xFF6FA8A0),
  Color(0xFF3B7A3F),
  Color(0xFFD97B9A),
  Color(0xFF9CA3AF),
  Color(0xFF14181F),
];

const List<Color> kLipColors = [
  Color(0x00000000), // doğal (ten tonundan türetilir)
  Color(0xFFC9727A), // gül
  Color(0xFFD9826E), // mercan
  Color(0xFFB8323F), // kırmızı
  Color(0xFF8E1F33), // koyu kırmızı
  Color(0xFF9C4A63), // böğürtlen
  Color(0xFFA9707A), // mor-pembe
  Color(0xFFCB9A8A), // nude
  Color(0xFF6D2B47), // erik
  Color(0xFFE08AA4), // pembe
];

// -------------------------------------------------------------- arka plan

@immutable
class BackgroundSpec {
  final String label;
  final Color top;
  final Color bottom;
  const BackgroundSpec(this.label, this.top, this.bottom);
}

const List<BackgroundSpec> kBackgrounds = [
  BackgroundSpec('Stüdyo', Color(0xFFF1F3F7), Color(0xFFD9DEE8)),
  BackgroundSpec('Gün Batımı', Color(0xFFFFC7A0), Color(0xFFE5758B)),
  BackgroundSpec('Okyanus', Color(0xFF9FD8F0), Color(0xFF3F7FC4)),
  BackgroundSpec('Orman', Color(0xFFB7DDB0), Color(0xFF3F8A62)),
  BackgroundSpec('Lavanta', Color(0xFFD9C8F4), Color(0xFF8A6FD1)),
  BackgroundSpec('Kum', Color(0xFFF2E2C6), Color(0xFFC9A26E)),
  BackgroundSpec('Gece', Color(0xFF4A5A86), Color(0xFF1A2038)),
  BackgroundSpec('Şeftali', Color(0xFFFFE0D2), Color(0xFFF3A48E)),
  BackgroundSpec('Nane', Color(0xFFCFF2E4), Color(0xFF66BFA4)),
  BackgroundSpec('Altın', Color(0xFFFBE7A6), Color(0xFFD9A233)),
  BackgroundSpec('Gül', Color(0xFFFAD2E0), Color(0xFFD8709A)),
  BackgroundSpec('Antrasit', Color(0xFF7C8494), Color(0xFF2B303B)),
  BackgroundSpec('Gökyüzü', Color(0xFFCDE7FB), Color(0xFF7DB2E8)),
  BackgroundSpec('Şarap', Color(0xFFC97A8A), Color(0xFF5A1F35)),
];

// ------------------------------------------------------------- yüz şekli

@immutable
class FaceShapeSpec {
  final String label;

  /// Alın / elmacık / çene genişliği çarpanları, çene uzunluğu ve çene
  /// köşesinin keskinliği (0 = yuvarlak, 1 = kare).
  final double forehead;
  final double cheek;
  final double jaw;
  final double chin;
  final double corner;

  /// Çene ucunun genişliği (küçük = sivri, büyük = geniş/kare çene).
  final double chinWidth;

  const FaceShapeSpec(
    this.label, {
    required this.forehead,
    required this.cheek,
    required this.jaw,
    required this.chin,
    required this.corner,
    this.chinWidth = 1.0,
  });
}

/// Çizim motorunun taban ölçüleri (yarım genişlikler, 200 birimlik tuvalde).
/// Fotoğraf analizi de yüz şeklini seçerken bunlara bakar.
const double kFaceBaseForeheadHalf = 35.0;
const double kFaceBaseCheekHalf = 39.0;
const double kFaceBaseJawHalf = 31.0;
const double kFaceBaseChinLength = 54.0; // göz hattı → çene

const List<FaceShapeSpec> kFaceShapes = [
  FaceShapeSpec('Oval', forehead: 1.00, cheek: 1.00, jaw: 0.95, chin: 1.00, corner: 0.15),
  FaceShapeSpec('Yuvarlak', forehead: 1.02, cheek: 1.14, jaw: 1.04, chin: 0.85, corner: 0.05, chinWidth: 1.15),
  FaceShapeSpec('Kare', forehead: 1.05, cheek: 1.04, jaw: 1.11, chin: 0.94, corner: 0.72, chinWidth: 1.22),
  FaceShapeSpec('Kalp', forehead: 1.10, cheek: 1.03, jaw: 0.82, chin: 1.0, corner: 0.20, chinWidth: 0.92),
  FaceShapeSpec('Uzun', forehead: 0.94, cheek: 0.90, jaw: 0.88, chin: 1.26, corner: 0.25),
  FaceShapeSpec('Elmas', forehead: 0.86, cheek: 1.12, jaw: 0.84, chin: 1.06, corner: 0.18, chinWidth: 0.88),
  FaceShapeSpec('Üçgen', forehead: 0.84, cheek: 0.96, jaw: 1.18, chin: 0.96, corner: 0.60, chinWidth: 1.12),
  FaceShapeSpec('Armut', forehead: 0.87, cheek: 1.02, jaw: 1.15, chin: 1.00, corner: 0.35),
  FaceShapeSpec('Dikdörtgen', forehead: 1.02, cheek: 1.00, jaw: 1.06, chin: 1.20, corner: 0.60, chinWidth: 1.15),
  FaceShapeSpec('İnce Oval', forehead: 0.93, cheek: 0.91, jaw: 0.86, chin: 1.08, corner: 0.10, chinWidth: 0.92),
  FaceShapeSpec('Yumuşak Kare', forehead: 1.04, cheek: 1.05, jaw: 1.08, chin: 0.96, corner: 0.50, chinWidth: 1.18),
  FaceShapeSpec('Tombul', forehead: 1.04, cheek: 1.20, jaw: 1.10, chin: 0.80, corner: 0.02, chinWidth: 1.20),
];

// ------------------------------------------------------------------- saç

enum HairGroup { short, medium, long, curly, updo, braided, covered }

const Map<HairGroup, String> kHairGroupLabels = {
  HairGroup.short: 'Kısa',
  HairGroup.medium: 'Orta',
  HairGroup.long: 'Uzun',
  HairGroup.curly: 'Kıvırcık',
  HairGroup.updo: 'Toplu',
  HairGroup.braided: 'Örgü',
  HairGroup.covered: 'Kapalı',
};

enum HairTexture { smooth, wavy, curly, coily }

/// Saç çizgisinin (alın hattı) biçimi.
enum Hairline { round, high, low, widow, mShape, receding, straight }

/// Alına düşen / tepeyi biçimlendiren bölüm.
enum HairFringe {
  none,
  sweep, // yana taranmış
  sweepLong, // uzun yan kâkül
  blunt, // düz kâkül
  curtain, // perde
  wispy, // ince, seyrek kâkül
  micro, // kısa, öne taralı
  quiff, // yukarı kabarık
  pomp, // pompadur
  slick, // arkaya taralı
  spiky, // dikenli
  messy, // dağınık
  comb, // sert ayrım, yana tarak
  wave, // Hollywood dalgası
  crop, // dağınık kısa dokulu
}

/// Yan ve arka uzunluk.
enum HairLength { bald, buzz, crop, short, ear, jaw, shoulder, long, xlong, pulled }

/// Fade (yanlar tıraşlı) derinliği.
enum HairFade { none, low, mid, high, skin }

/// Toplama / örgü / özel biçimler.
enum HairTie {
  none,
  bunLow,
  bunHigh,
  bunTop,
  bunMessy,
  bunBallet,
  ponyHigh,
  ponyLow,
  ponySide,
  pigtails,
  spaceBuns,
  halfUp,
  halfBun,
  braid,
  braidSide,
  braidsTwo,
  crownBraid,
  fishtail,
  boxBraids,
  cornrows,
  dreads,
  afroPuffs,
  mohawk,
  twists,
  flatTop,
}

enum HairCover { none, hijab, hijabWrap, turban, babushka, shawl, bandana }

@immutable
class HairSpec {
  final String label;
  final HairGroup group;

  /// Tepe yüksekliği (0 = yapışık, 1 = dolgun, 1.6+ = afro).
  final double volume;

  /// Yanlara taşma (0 = kafatasına yapışık, 1.6 = afro).
  final double width;

  final Hairline hairline;
  final HairTexture texture;

  /// Kıvrım şiddeti (dalga/bukle genliği), 0..1.
  final double curl;

  /// Ayrım: -1 sol, 0 yok/orta, 1 sağ.
  final int part;

  final HairFringe fringe;
  final HairLength length;
  final HairFade fade;
  final HairTie tie;
  final HairCover cover;

  /// Katmanlı (uçlar farklı boyda) uzun saç.
  final bool layered;

  const HairSpec(
    this.label,
    this.group, {
    this.volume = 0.4,
    this.width = 0.3,
    this.hairline = Hairline.round,
    this.texture = HairTexture.smooth,
    this.curl = 0.0,
    this.part = 1,
    this.fringe = HairFringe.none,
    this.length = HairLength.short,
    this.fade = HairFade.none,
    this.tie = HairTie.none,
    this.cover = HairCover.none,
    this.layered = false,
  });

  bool get bald => length == HairLength.bald && cover == HairCover.none;
  bool get covered => cover != HairCover.none;
}

const List<HairSpec> kHairStyles = [
  // ---------------------------------------------------------- kısa (erkek)
  HairSpec('Kel', HairGroup.short, length: HairLength.bald, volume: 0, width: 0),
  HairSpec('Sıfır Tıraş', HairGroup.short, length: HairLength.buzz, volume: 0.02, width: 0.05, hairline: Hairline.high),
  HairSpec('Asker', HairGroup.short, length: HairLength.crop, volume: 0.10, width: 0.08, fringe: HairFringe.micro, hairline: Hairline.straight),
  HairSpec('Çok Kısa', HairGroup.short, length: HairLength.crop, volume: 0.18, width: 0.12, fringe: HairFringe.micro),
  HairSpec('Kısa', HairGroup.short, length: HairLength.short, volume: 0.42, width: 0.22, fringe: HairFringe.micro),
  HairSpec('Kısa Dalgalı', HairGroup.short, length: HairLength.short, volume: 0.55, width: 0.28, texture: HairTexture.wavy, curl: 0.5, fringe: HairFringe.messy),
  HairSpec('Yana Ayrık', HairGroup.short, length: HairLength.short, volume: 0.50, width: 0.22, fringe: HairFringe.comb, part: 1),
  HairSpec('Yana Ayrık Sol', HairGroup.short, length: HairLength.short, volume: 0.50, width: 0.22, fringe: HairFringe.comb, part: -1),
  HairSpec('Öne Taralı', HairGroup.short, length: HairLength.short, volume: 0.36, width: 0.20, fringe: HairFringe.micro, hairline: Hairline.low),
  HairSpec('Kirpi', HairGroup.short, length: HairLength.short, volume: 0.72, width: 0.16, fringe: HairFringe.spiky),
  HairSpec('Fade Kısa', HairGroup.short, length: HairLength.crop, fade: HairFade.mid, volume: 0.40, width: 0.10, fringe: HairFringe.micro),
  HairSpec('Yüksek Fade', HairGroup.short, length: HairLength.crop, fade: HairFade.high, volume: 0.55, width: 0.10, fringe: HairFringe.crop),
  HairSpec('Skin Fade Tepe', HairGroup.short, length: HairLength.crop, fade: HairFade.skin, volume: 0.60, width: 0.10, fringe: HairFringe.quiff),
  HairSpec('Undercut', HairGroup.short, length: HairLength.crop, fade: HairFade.high, volume: 0.66, width: 0.10, fringe: HairFringe.sweep, part: 1),
  HairSpec('Undercut Uzun Tepe', HairGroup.short, length: HairLength.crop, fade: HairFade.high, volume: 0.78, width: 0.12, fringe: HairFringe.slick),
  HairSpec('Pompadur', HairGroup.short, length: HairLength.crop, fade: HairFade.mid, volume: 1.10, width: 0.14, fringe: HairFringe.pomp),
  HairSpec('Quiff', HairGroup.short, length: HairLength.short, fade: HairFade.low, volume: 0.95, width: 0.16, fringe: HairFringe.quiff),
  HairSpec('Arkaya Taralı', HairGroup.short, length: HairLength.short, volume: 0.55, width: 0.16, fringe: HairFringe.slick, hairline: Hairline.receding),
  HairSpec('Yandan Taraklı', HairGroup.short, length: HairLength.short, fade: HairFade.low, volume: 0.62, width: 0.14, fringe: HairFringe.comb, part: 1),
  HairSpec('Dağınık Kısa', HairGroup.short, length: HairLength.short, volume: 0.70, width: 0.24, fringe: HairFringe.messy, texture: HairTexture.wavy, curl: 0.35),
  HairSpec('Geri Çekilmiş', HairGroup.short, length: HairLength.crop, volume: 0.22, width: 0.10, hairline: Hairline.receding, fringe: HairFringe.micro),
  HairSpec('Yüksek Saç Çizgisi', HairGroup.short, length: HairLength.crop, volume: 0.30, width: 0.10, hairline: Hairline.mShape, fringe: HairFringe.micro),
  HairSpec('Mohawk', HairGroup.short, length: HairLength.buzz, tie: HairTie.mohawk, volume: 1.0, width: 0.05, fade: HairFade.skin),
  HairSpec('Faux Hawk', HairGroup.short, length: HairLength.crop, fade: HairFade.high, volume: 0.9, width: 0.08, fringe: HairFringe.spiky),

  // ------------------------------------------------------- kıvırcık / afro
  HairSpec('Kısa Kıvırcık', HairGroup.curly, length: HairLength.short, volume: 0.62, width: 0.42, texture: HairTexture.curly, curl: 0.7),
  HairSpec('Kıvırcık Fade', HairGroup.curly, length: HairLength.crop, fade: HairFade.mid, volume: 0.70, width: 0.22, texture: HairTexture.curly, curl: 0.7),
  HairSpec('Afro', HairGroup.curly, length: HairLength.short, volume: 1.30, width: 1.30, texture: HairTexture.coily, curl: 1.0),
  HairSpec('Küçük Afro', HairGroup.curly, length: HairLength.short, volume: 0.85, width: 0.70, texture: HairTexture.coily, curl: 0.9),
  HairSpec('Sıkı Bukle', HairGroup.curly, length: HairLength.crop, volume: 0.62, width: 0.34, texture: HairTexture.coily, curl: 0.9),
  HairSpec('Bukle Fade', HairGroup.curly, length: HairLength.crop, fade: HairFade.high, volume: 0.66, width: 0.18, texture: HairTexture.coily, curl: 0.8),
  HairSpec('Yüksek Tepe', HairGroup.curly, length: HairLength.crop, fade: HairFade.high, tie: HairTie.flatTop, volume: 1.0, width: 0.20, texture: HairTexture.coily, curl: 0.6),
  HairSpec('Bükümlü Tepe', HairGroup.curly, length: HairLength.crop, fade: HairFade.mid, tie: HairTie.twists, volume: 0.80, width: 0.22, texture: HairTexture.coily, curl: 0.9),
  HairSpec('Kıvırcık Orta', HairGroup.curly, length: HairLength.ear, volume: 0.80, width: 0.70, texture: HairTexture.curly, curl: 0.8),
  HairSpec('Kıvırcık Uzun', HairGroup.curly, length: HairLength.shoulder, volume: 0.85, width: 0.75, texture: HairTexture.curly, curl: 0.9, fringe: HairFringe.curtain),
  HairSpec('Uzun Bukle', HairGroup.curly, length: HairLength.long, volume: 0.9, width: 0.85, texture: HairTexture.curly, curl: 1.0, fringe: HairFringe.sweepLong),
  HairSpec('Afro Kabarık', HairGroup.curly, length: HairLength.shoulder, volume: 1.5, width: 1.60, texture: HairTexture.coily, curl: 1.0),
  HairSpec('Sıkı Bukle Uzun', HairGroup.curly, length: HairLength.shoulder, volume: 0.9, width: 0.95, texture: HairTexture.coily, curl: 1.0, fringe: HairFringe.curtain),

  // ------------------------------------------------------------------ orta
  HairSpec('Orta Düz', HairGroup.medium, length: HairLength.ear, volume: 0.48, width: 0.32, fringe: HairFringe.sweep),
  HairSpec('Orta Dalgalı', HairGroup.medium, length: HairLength.ear, volume: 0.62, width: 0.42, texture: HairTexture.wavy, curl: 0.6, fringe: HairFringe.sweep),
  HairSpec('Dağınık Orta', HairGroup.medium, length: HairLength.ear, volume: 0.72, width: 0.46, texture: HairTexture.wavy, curl: 0.5, fringe: HairFringe.messy),
  HairSpec('Perde Saç', HairGroup.medium, length: HairLength.ear, volume: 0.50, width: 0.36, fringe: HairFringe.curtain, part: 0),
  HairSpec('Mullet', HairGroup.medium, length: HairLength.shoulder, fade: HairFade.low, volume: 0.62, width: 0.30, fringe: HairFringe.messy, layered: true, texture: HairTexture.wavy, curl: 0.4),
  HairSpec('Çene Boyu', HairGroup.medium, length: HairLength.jaw, volume: 0.50, width: 0.40, fringe: HairFringe.sweep),
  HairSpec('Kısa Bob', HairGroup.medium, length: HairLength.jaw, volume: 0.42, width: 0.38, fringe: HairFringe.blunt, part: 0),
  HairSpec('Bob', HairGroup.medium, length: HairLength.jaw, volume: 0.50, width: 0.44, fringe: HairFringe.sweep, part: 1),
  HairSpec('Uzun Bob', HairGroup.medium, length: HairLength.shoulder, volume: 0.50, width: 0.42, fringe: HairFringe.sweep, part: 1),
  HairSpec('A Bob', HairGroup.medium, length: HairLength.jaw, volume: 0.46, width: 0.44, fringe: HairFringe.sweepLong, part: 1, layered: true),
  HairSpec('Pixie', HairGroup.medium, length: HairLength.crop, volume: 0.58, width: 0.18, fringe: HairFringe.wispy, part: 1),
  HairSpec('Pixie Kâküllü', HairGroup.medium, length: HairLength.short, volume: 0.50, width: 0.22, fringe: HairFringe.blunt),
  HairSpec('Omuz Katlı', HairGroup.medium, length: HairLength.shoulder, volume: 0.56, width: 0.44, layered: true, fringe: HairFringe.curtain, part: 0),
  HairSpec('Shag', HairGroup.medium, length: HairLength.shoulder, volume: 0.80, width: 0.56, layered: true, fringe: HairFringe.wispy, texture: HairTexture.wavy, curl: 0.5),
  HairSpec('Wolf Cut', HairGroup.medium, length: HairLength.shoulder, volume: 0.86, width: 0.60, layered: true, fringe: HairFringe.curtain, texture: HairTexture.wavy, curl: 0.4, part: 0),

  // ------------------------------------------------------------------ uzun
  HairSpec('Uzun Düz', HairGroup.long, length: HairLength.long, volume: 0.46, width: 0.34, fringe: HairFringe.sweepLong, part: 0),
  HairSpec('Uzun Dalgalı', HairGroup.long, length: HairLength.long, volume: 0.60, width: 0.48, texture: HairTexture.wavy, curl: 0.7, fringe: HairFringe.sweepLong, part: 0),
  HairSpec('Çok Uzun Düz', HairGroup.long, length: HairLength.xlong, volume: 0.46, width: 0.30, fringe: HairFringe.sweepLong, part: 0),
  HairSpec('Plaj Dalgası', HairGroup.long, length: HairLength.xlong, volume: 0.70, width: 0.58, texture: HairTexture.wavy, curl: 0.9, fringe: HairFringe.sweepLong, part: 0, layered: true),
  HairSpec('Kâkül Uzun', HairGroup.long, length: HairLength.long, volume: 0.50, width: 0.34, fringe: HairFringe.blunt),
  HairSpec('Perde Kâkül', HairGroup.long, length: HairLength.long, volume: 0.54, width: 0.38, fringe: HairFringe.curtain, part: 0),
  HairSpec('Yan Ayrım Uzun', HairGroup.long, length: HairLength.long, volume: 0.64, width: 0.42, fringe: HairFringe.sweepLong, part: 1),
  HairSpec('Katlı Uzun', HairGroup.long, length: HairLength.long, volume: 0.66, width: 0.50, layered: true, fringe: HairFringe.curtain, part: 0),
  HairSpec('Hollywood Dalga', HairGroup.long, length: HairLength.long, volume: 0.70, width: 0.46, texture: HairTexture.wavy, curl: 0.8, fringe: HairFringe.wave, part: 1),
  HairSpec('Uzun Rüzgârlı', HairGroup.long, length: HairLength.long, volume: 0.80, width: 0.60, texture: HairTexture.wavy, curl: 0.5, fringe: HairFringe.messy, layered: true),
  HairSpec('Uzun Kâküllü Dalga', HairGroup.long, length: HairLength.long, volume: 0.62, width: 0.46, texture: HairTexture.wavy, curl: 0.55, fringe: HairFringe.blunt),
  HairSpec('Uzun Erkek', HairGroup.long, length: HairLength.shoulder, volume: 0.50, width: 0.36, fringe: HairFringe.sweepLong, part: 0),
  HairSpec('Uzun Dağınık Erkek', HairGroup.long, length: HairLength.shoulder, volume: 0.72, width: 0.50, texture: HairTexture.wavy, curl: 0.5, fringe: HairFringe.messy, layered: true),

  // ----------------------------------------------------------------- toplu
  HairSpec('Topuz', HairGroup.updo, length: HairLength.pulled, tie: HairTie.bunLow, volume: 0.32, width: 0.10, fringe: HairFringe.none),
  HairSpec('Yüksek Topuz', HairGroup.updo, length: HairLength.pulled, tie: HairTie.bunHigh, volume: 0.30, width: 0.10),
  HairSpec('Dağınık Topuz', HairGroup.updo, length: HairLength.pulled, tie: HairTie.bunMessy, volume: 0.45, width: 0.22, fringe: HairFringe.wispy, texture: HairTexture.wavy, curl: 0.4),
  HairSpec('Balerin Topuz', HairGroup.updo, length: HairLength.pulled, tie: HairTie.bunBallet, volume: 0.24, width: 0.08, hairline: Hairline.high),
  HairSpec('Erkek Topuz', HairGroup.updo, length: HairLength.pulled, tie: HairTie.bunTop, fade: HairFade.mid, volume: 0.36, width: 0.08),
  HairSpec('Yarım Topuz', HairGroup.updo, length: HairLength.long, tie: HairTie.halfBun, volume: 0.62, width: 0.34, fringe: HairFringe.curtain, part: 0),
  HairSpec('Yarım Kuyruk', HairGroup.updo, length: HairLength.long, tie: HairTie.halfUp, volume: 0.58, width: 0.34, fringe: HairFringe.sweep, part: 1),
  HairSpec('At Kuyruğu', HairGroup.updo, length: HairLength.pulled, tie: HairTie.ponyHigh, volume: 0.36, width: 0.10, fringe: HairFringe.none),
  HairSpec('Kâküllü Kuyruk', HairGroup.updo, length: HairLength.pulled, tie: HairTie.ponyHigh, volume: 0.42, width: 0.14, fringe: HairFringe.blunt),
  HairSpec('Alçak Kuyruk', HairGroup.updo, length: HairLength.pulled, tie: HairTie.ponyLow, volume: 0.36, width: 0.10, fringe: HairFringe.sweep),
  HairSpec('Yan Kuyruk', HairGroup.updo, length: HairLength.pulled, tie: HairTie.ponySide, volume: 0.44, width: 0.16, fringe: HairFringe.sweep, texture: HairTexture.wavy, curl: 0.5),
  HairSpec('İki Kuyruk', HairGroup.updo, length: HairLength.pulled, tie: HairTie.pigtails, volume: 0.34, width: 0.10, part: 0),
  HairSpec('Uzay Topuzları', HairGroup.updo, length: HairLength.pulled, tie: HairTie.spaceBuns, volume: 0.30, width: 0.10, part: 0),
  HairSpec('Afro Topuzlar', HairGroup.updo, length: HairLength.pulled, tie: HairTie.afroPuffs, volume: 0.40, width: 0.12, texture: HairTexture.coily, curl: 1.0, part: 0),

  // ------------------------------------------------------------------ örgü
  HairSpec('Örgü', HairGroup.braided, length: HairLength.pulled, tie: HairTie.braid, volume: 0.36, width: 0.10),
  HairSpec('Yan Örgü', HairGroup.braided, length: HairLength.long, tie: HairTie.braidSide, volume: 0.56, width: 0.34, fringe: HairFringe.sweep),
  HairSpec('İki Örgü', HairGroup.braided, length: HairLength.pulled, tie: HairTie.braidsTwo, volume: 0.34, width: 0.10, part: 0),
  HairSpec('Taç Örgü', HairGroup.braided, length: HairLength.pulled, tie: HairTie.crownBraid, volume: 0.40, width: 0.14, part: 0),
  HairSpec('Balık Kılçığı', HairGroup.braided, length: HairLength.pulled, tie: HairTie.fishtail, volume: 0.40, width: 0.14, fringe: HairFringe.wispy),
  HairSpec('Kutu Örgü', HairGroup.braided, length: HairLength.shoulder, tie: HairTie.boxBraids, volume: 0.64, width: 0.36, part: 0),
  HairSpec('Kaba Örgü', HairGroup.braided, length: HairLength.crop, tie: HairTie.cornrows, volume: 0.10, width: 0.08),
  HairSpec('Rasta', HairGroup.braided, length: HairLength.shoulder, tie: HairTie.dreads, volume: 0.70, width: 0.55, texture: HairTexture.coily, curl: 0.4, part: 0),

  // ----------------------------------------------------------------- kapalı
  HairSpec('Başörtüsü', HairGroup.covered, cover: HairCover.hijab, length: HairLength.pulled, volume: 0, width: 0),
  HairSpec('Sarma Başörtü', HairGroup.covered, cover: HairCover.hijabWrap, length: HairLength.pulled, volume: 0, width: 0),
  HairSpec('Türban', HairGroup.covered, cover: HairCover.turban, length: HairLength.pulled, volume: 0, width: 0),
  HairSpec('Fularlı', HairGroup.covered, cover: HairCover.babushka, length: HairLength.pulled, volume: 0, width: 0),
  HairSpec('Şal', HairGroup.covered, cover: HairCover.shawl, length: HairLength.pulled, volume: 0, width: 0),
  HairSpec('Bandana', HairGroup.covered, cover: HairCover.bandana, length: HairLength.short, volume: 0.30, width: 0.14),
];

// ------------------------------------------------------------------- kaş

@immutable
class BrowSpec {
  final String label;
  final double thickness;
  final double arch;
  final double tilt;
  final double length;
  final double taper;

  /// Kaşın yüzdeki yüksekliği (+ yukarı).
  final double lift;

  /// Kaşın seyrekliği (0 = dolgun, 1 = çok seyrek/kesik).
  final double sparse;

  /// Gövde açısı: iç uç ile arch tepesi arasındaki kayma.
  final double peak;

  const BrowSpec(
    this.label, {
    this.thickness = 1.0,
    this.arch = 1.0,
    this.tilt = 0.0,
    this.length = 1.0,
    this.taper = 1.0,
    this.lift = 0.0,
    this.sparse = 0.0,
    this.peak = 0.55,
  });
}

const List<BrowSpec> kBrowStyles = [
  BrowSpec('İnce', thickness: 0.62, arch: 1.15),
  BrowSpec('Doğal', thickness: 1.0, arch: 1.0),
  BrowSpec('Kalın', thickness: 1.45, arch: 0.85),
  BrowSpec('Çok Kalın', thickness: 1.85, arch: 0.7, taper: 0.6),
  BrowSpec('Çatık', thickness: 1.15, arch: 0.30, tilt: 2.8),
  BrowSpec('Yay', thickness: 0.95, arch: 1.7),
  BrowSpec('Düz', thickness: 1.1, arch: 0.1),
  BrowSpec('Kavisli', thickness: 0.85, arch: 1.45, taper: 1.3),
  BrowSpec('Kısa', thickness: 1.05, arch: 1.0, length: 0.78),
  BrowSpec('Uzun', thickness: 0.8, arch: 1.2, length: 1.2, taper: 1.2),
  BrowSpec('Sert Açılı', thickness: 1.0, arch: 1.9, peak: 0.66, taper: 1.2),
  BrowSpec('Yumuşak Yay', thickness: 1.1, arch: 1.2, peak: 0.45),
  BrowSpec('Tüylü', thickness: 1.35, arch: 0.95, sparse: 0.25),
  BrowSpec('Yüksek', thickness: 1.0, arch: 1.25, lift: 2.6),
  BrowSpec('Alçak', thickness: 1.2, arch: 0.6, lift: -1.8),
  BrowSpec('Seyrek', thickness: 0.8, arch: 1.0, sparse: 0.6),
  BrowSpec('Düşük Uç', thickness: 1.05, arch: 0.8, tilt: -2.2),
  BrowSpec('Yükselen Uç', thickness: 1.0, arch: 0.9, tilt: 1.6, taper: 1.2),
  BrowSpec('Kalın Düz', thickness: 1.7, arch: 0.15, taper: 0.7),
  BrowSpec('İnce Yay', thickness: 0.5, arch: 1.6, taper: 1.4),
  BrowSpec('Geniş Aralık', thickness: 1.1, arch: 1.0, length: 0.86, lift: 1.0),
  BrowSpec('Kirpi Kaş', thickness: 1.25, arch: 0.8, taper: 0.5, sparse: 0.12),
];

// ------------------------------------------------------------------- göz

@immutable
class EyeSpec {
  final String label;
  final double width;
  final double height;

  /// Dış köşenin yukarı (+) / aşağı (−) kayması.
  final double tilt;
  final bool hooded;
  final bool closed;

  /// Tek katlı göz kapağı (belirgin kıvrım yok).
  final bool monolid;

  /// Göz çukuru derinliği (üst kapakta gölge).
  final double deepSet;

  /// Üst kapak eğrisi: 0 = yassı, 1 = dolgun.
  final double lidCurve;

  const EyeSpec(
    this.label, {
    this.width = 1.0,
    this.height = 1.0,
    this.tilt = 0.0,
    this.hooded = false,
    this.closed = false,
    this.monolid = false,
    this.deepSet = 0.0,
    this.lidCurve = 0.5,
  });
}

const List<EyeSpec> kEyeStyles = [
  EyeSpec('Normal'),
  EyeSpec('Badem', width: 1.10, height: 0.80, lidCurve: 0.45),
  EyeSpec('İri', width: 1.08, height: 1.24, lidCurve: 0.7),
  EyeSpec('Küçük', width: 0.86, height: 0.84),
  EyeSpec('Yuvarlak', width: 0.96, height: 1.18, lidCurve: 0.8),
  EyeSpec('Çekik', width: 1.08, height: 0.86, tilt: 2.2),
  EyeSpec('Düşük', width: 1.05, height: 0.92, tilt: -2.0),
  EyeSpec('Kapaklı', width: 1.04, height: 0.90, hooded: true),
  EyeSpec('Uykulu', width: 1.0, height: 0.64, lidCurve: 0.3),
  EyeSpec('Gülen', closed: true),
  EyeSpec('Derin Çukur', width: 1.02, height: 0.92, deepSet: 1.0, hooded: true),
  EyeSpec('Tek Kat', width: 1.06, height: 0.78, monolid: true, tilt: 1.2),
  EyeSpec('Çekik Badem', width: 1.12, height: 0.82, monolid: true, tilt: 2.4),
  EyeSpec('Kedi', width: 1.14, height: 0.86, tilt: 3.0, lidCurve: 0.4),
  EyeSpec('Geniş', width: 1.16, height: 1.0),
  EyeSpec('Hüzünlü', width: 1.02, height: 0.96, tilt: -2.8, lidCurve: 0.4),
  EyeSpec('Ela Bakış', width: 1.0, height: 1.05, lidCurve: 0.65),
  EyeSpec('Yorgun', width: 1.02, height: 0.7, hooded: true, deepSet: 0.5, tilt: -0.8),
];

// ---------------------------------------------------------------- kirpik

@immutable
class LashSpec {
  final String label;
  final double length;
  final double thickness;
  final bool winged;
  final bool lower;

  /// Eyeliner kalınlığı (0 = yok).
  final double liner;

  /// Far (göz kapağı rengi); şeffaf = far yok.
  final Color shadow;
  final double shadowStrength;

  const LashSpec(
    this.label, {
    this.length = 0,
    this.thickness = 1.0,
    this.winged = false,
    this.lower = false,
    this.liner = 0,
    this.shadow = const Color(0x00000000),
    this.shadowStrength = 0,
  });
}

const List<LashSpec> kLashStyles = [
  LashSpec('Yok'),
  LashSpec('Doğal', length: 0.42, thickness: 0.85),
  LashSpec('Uzun', length: 1.15),
  LashSpec('Kalın', length: 0.85, thickness: 1.6),
  LashSpec('Kedi Gözü', length: 1.25, thickness: 1.35, winged: true, liner: 1.0),
  LashSpec('Alt + Üst', length: 0.9, thickness: 1.15, lower: true),
  LashSpec('Dramatik', length: 1.6, thickness: 1.5, lower: true, liner: 0.8),
  LashSpec('İnce Eyeliner', length: 0.7, thickness: 1.0, liner: 0.7),
  LashSpec('Kanatlı Eyeliner', length: 0.9, thickness: 1.1, winged: true, liner: 1.2),
  LashSpec('Smoky', length: 1.1, thickness: 1.3, liner: 1.0, lower: true, shadow: Color(0xFF3A2E36), shadowStrength: 0.62),
  LashSpec('Pembe Far', length: 1.0, thickness: 1.1, shadow: Color(0xFFE596AE), shadowStrength: 0.55),
  LashSpec('Altın Far', length: 1.05, thickness: 1.1, shadow: Color(0xFFD9A441), shadowStrength: 0.55),
  LashSpec('Mavi Far', length: 1.0, thickness: 1.1, shadow: Color(0xFF5F8FD6), shadowStrength: 0.5),
  LashSpec('Mor Far', length: 1.0, thickness: 1.1, shadow: Color(0xFF8A5FC4), shadowStrength: 0.5),
  LashSpec('Bronz Far', length: 0.95, thickness: 1.0, shadow: Color(0xFFB07044), shadowStrength: 0.5),
];

// ------------------------------------------------------------------ burun

@immutable
class NoseSpec {
  final String label;

  /// Burun sırtı genişliği.
  final double bridge;

  /// Burun ucu/kanat genişliği.
  final double width;

  /// Uzunluk (göz hattından ucuna).
  final double length;

  /// Ucun yukarı dönüklüğü (0 = düz, 1 = kalkık).
  final double upturn;

  /// Sırtın kemer çıkıntısı.
  final double bump;

  /// Burun ucu dolgunluğu.
  final double tip;

  const NoseSpec(
    this.label, {
    this.bridge = 1.0,
    this.width = 1.0,
    this.length = 1.0,
    this.upturn = 0.0,
    this.bump = 0.0,
    this.tip = 1.0,
  });
}

const List<NoseSpec> kNoseStyles = [
  NoseSpec('Düz'),
  NoseSpec('Kemerli', bump: 0.9, length: 1.06, bridge: 1.05),
  NoseSpec('Kalkık', upturn: 0.8, length: 0.92, tip: 0.9),
  NoseSpec('Geniş', width: 1.28, bridge: 1.2, tip: 1.15),
  NoseSpec('İnce', width: 0.80, bridge: 0.78, tip: 0.85),
  NoseSpec('Yuvarlak Uçlu', tip: 1.3, width: 1.06),
  NoseSpec('Keskin', bridge: 0.86, tip: 0.72, length: 1.08),
  NoseSpec('Küçük', width: 0.84, length: 0.84, upturn: 0.4, tip: 0.85),
  NoseSpec('Uzun', length: 1.16, bridge: 0.94),
  NoseSpec('Dolgun', width: 1.16, bridge: 1.1, tip: 1.28, upturn: 0.2),
];

// ------------------------------------------------------------------ dudak

@immutable
class LipSpec {
  final String label;

  /// Üst/alt dudak dolgunluğu çarpanı.
  final double upper;
  final double lower;
  final double width;

  /// Üst dudak "cupid's bow" belirginliği.
  final double bow;

  /// Ağız köşelerinin yukarı (+) / aşağı (−) eğimi (gülümseme eklenir).
  final double corner;

  const LipSpec(
    this.label, {
    this.upper = 1.0,
    this.lower = 1.0,
    this.width = 1.0,
    this.bow = 1.0,
    this.corner = 0.0,
  });
}

const List<LipSpec> kLipStyles = [
  LipSpec('Doğal'),
  LipSpec('İnce', upper: 0.62, lower: 0.62),
  LipSpec('Dolgun', upper: 1.35, lower: 1.4),
  LipSpec('Kalp Dudak', upper: 1.15, lower: 1.1, bow: 1.7),
  LipSpec('Geniş', width: 1.18, upper: 1.0, lower: 1.1),
  LipSpec('Küçük', width: 0.82),
  LipSpec('Alt Dolgun', upper: 0.8, lower: 1.5),
  LipSpec('Üst Dolgun', upper: 1.4, lower: 0.9),
  LipSpec('Gülümseyen', corner: 1.6, width: 1.08),
  LipSpec('Ciddi', corner: -0.5, upper: 0.85, lower: 0.85),
];

// ------------------------------------------------------------------ sakal

/// Sakalın çene/yanak bölgesi.
enum BeardRegion {
  none,
  stubbleLight,
  stubbleMedium,
  stubbleHeavy,
  jawline, // ince çene hattı
  chinStrap,
  short, // kısa, düzenli
  boxed, // kutu sakal
  full, // tam
  fullLong, // uzun
  garibaldi, // geniş yuvarlak
  balbo, // bıyıklı çene, yanak temiz
  goatee, // keçi
  vanDyke, // sivri keçi + bıyık
  anchor, // çapa
  circle, // daire
  soulPatch, // dudak altı
  chinPuff, // çene ucu
  ducktail, // ördek kuyruğu
  lumberjack, // odun kesici
  viking, // uzun, kabarık
  mutton, // favori + bıyık
  neckOnly, // sadece boyun altı
}

enum MustacheKind {
  none,
  natural,
  thin,
  thick,
  walrus,
  handlebar,
  fuManchu,
  toothbrush,
  chevron,
  horseshoe,
  imperial,
}

@immutable
class BeardSpec {
  final String label;
  final BeardRegion region;
  final MustacheKind mustache;

  /// 0..1: dolgunluk/opaklık (üç günlük için düşük).
  final double density;
  final double sideburn;

  const BeardSpec(
    this.label, {
    this.region = BeardRegion.none,
    this.mustache = MustacheKind.none,
    this.density = 1.0,
    this.sideburn = 0.0,
  });

  bool get isNone => region == BeardRegion.none && mustache == MustacheKind.none && sideburn <= 0;
}

const List<BeardSpec> kBeardStyles = [
  BeardSpec('Yok'),
  BeardSpec('Hafif', region: BeardRegion.stubbleLight, density: 0.32),
  BeardSpec('Üç Günlük', region: BeardRegion.stubbleMedium, mustache: MustacheKind.natural, density: 0.55),
  BeardSpec('Yoğun Üç Günlük', region: BeardRegion.stubbleHeavy, mustache: MustacheKind.natural, density: 0.78),
  BeardSpec('Bıyık', mustache: MustacheKind.natural),
  BeardSpec('İnce Bıyık', mustache: MustacheKind.thin),
  BeardSpec('Kalın Bıyık', mustache: MustacheKind.thick),
  BeardSpec('Fırça Bıyık', mustache: MustacheKind.toothbrush),
  BeardSpec('Kıvrık Bıyık', mustache: MustacheKind.handlebar),
  BeardSpec('Mors Bıyık', mustache: MustacheKind.walrus),
  BeardSpec('Fu Manchu', mustache: MustacheKind.fuManchu),
  BeardSpec('Sakal Ucu', region: BeardRegion.soulPatch),
  BeardSpec('Keçi', region: BeardRegion.goatee, mustache: MustacheKind.natural),
  BeardSpec('Van Dyke', region: BeardRegion.vanDyke, mustache: MustacheKind.thin),
  BeardSpec('Çene Ucu', region: BeardRegion.chinPuff),
  BeardSpec('Çapa Sakal', region: BeardRegion.anchor, mustache: MustacheKind.thin),
  BeardSpec('Daire Sakal', region: BeardRegion.circle, mustache: MustacheKind.natural),
  BeardSpec('Çene Şeridi', region: BeardRegion.chinStrap),
  BeardSpec('Çene Hattı', region: BeardRegion.jawline),
  BeardSpec('Şeritli Sakal', region: BeardRegion.chinStrap, mustache: MustacheKind.natural),
  BeardSpec('Kısa Sakal', region: BeardRegion.short, mustache: MustacheKind.natural, density: 0.94),
  BeardSpec('Kutu Sakal', region: BeardRegion.boxed, mustache: MustacheKind.natural),
  BeardSpec('Tam Sakal', region: BeardRegion.full, mustache: MustacheKind.natural),
  BeardSpec('Uzun Sakal', region: BeardRegion.fullLong, mustache: MustacheKind.natural),
  BeardSpec('Garibaldi', region: BeardRegion.garibaldi, mustache: MustacheKind.natural),
  BeardSpec('Balbo', region: BeardRegion.balbo, mustache: MustacheKind.natural),
  BeardSpec('Ördek Kuyruğu', region: BeardRegion.ducktail, mustache: MustacheKind.natural),
  BeardSpec('Odun Kesici', region: BeardRegion.lumberjack, mustache: MustacheKind.natural),
  BeardSpec('Viking', region: BeardRegion.viking, mustache: MustacheKind.walrus),
  BeardSpec('Favori', sideburn: 1.0),
  BeardSpec('Uzun Favori', sideburn: 1.7, mustache: MustacheKind.natural),
  BeardSpec('Koyun Favorisi', region: BeardRegion.mutton, mustache: MustacheKind.thick, sideburn: 1.4),
  BeardSpec('Bıyıklı Çene', region: BeardRegion.chinStrap, mustache: MustacheKind.handlebar),
  BeardSpec('Kalın Bıyık Sakal', region: BeardRegion.full, mustache: MustacheKind.thick),
  BeardSpec('İmparator', region: BeardRegion.goatee, mustache: MustacheKind.imperial),
  BeardSpec('Ay Bıyıklı', region: BeardRegion.stubbleLight, mustache: MustacheKind.horseshoe, density: 0.6),
  BeardSpec('Chevron Bıyık', mustache: MustacheKind.chevron),
  BeardSpec('Uzun Kutu', region: BeardRegion.boxed, mustache: MustacheKind.thick, density: 0.96),
  BeardSpec('Yumuşak Sakal', region: BeardRegion.short, mustache: MustacheKind.thin, density: 0.7),
  BeardSpec('Ağır Sakal', region: BeardRegion.fullLong, mustache: MustacheKind.walrus, density: 1.0),
  BeardSpec('Boyun Sakalı', region: BeardRegion.neckOnly, mustache: MustacheKind.natural, density: 0.6),
  BeardSpec('Çene Bıyık', region: BeardRegion.jawline, mustache: MustacheKind.thin),
];

// ----------------------------------------------------------------- gözlük

enum GlassesShape {
  none,
  rect,
  round,
  square,
  oval,
  cat,
  aviator,
  wayfarer,
  browline,
  hexagon,
  wrap,
  halfMoon,
}

@immutable
class GlassesSpec {
  final String label;
  final GlassesShape shape;
  final bool sun;
  final double thickness;
  final Color frame;
  final Color tint;

  /// Çerçeve olmadan (rimless) çizim.
  final bool rimless;

  const GlassesSpec(
    this.label, {
    this.shape = GlassesShape.none,
    this.sun = false,
    this.thickness = 1.0,
    this.frame = const Color(0xFF2B2F36),
    this.tint = const Color(0x22B8D8F0),
    this.rimless = false,
  });

  /// Eski kodun beklediği alan: 0 = gözlük yok.
  double get width => shape == GlassesShape.none ? 0 : 1;
}

const List<GlassesSpec> kGlassesStyles = [
  GlassesSpec('Yok'),
  GlassesSpec('İnce Çerçeve', shape: GlassesShape.rect, thickness: 0.7, frame: Color(0xFF4A4F58)),
  GlassesSpec('Yuvarlak', shape: GlassesShape.round, thickness: 0.8, frame: Color(0xFF3A3F47)),
  GlassesSpec('Kalın Çerçeve', shape: GlassesShape.rect, thickness: 1.9, frame: Color(0xFF1F2227)),
  GlassesSpec('Harry', shape: GlassesShape.round, thickness: 1.5, frame: Color(0xFF3A2A1E)),
  GlassesSpec('Kare', shape: GlassesShape.square, thickness: 1.5, frame: Color(0xFF232830)),
  GlassesSpec('Oval', shape: GlassesShape.oval, thickness: 0.9, frame: Color(0xFF6A4A32)),
  GlassesSpec('Kedi Gözü', shape: GlassesShape.cat, thickness: 1.3, frame: Color(0xFFB03A55)),
  GlassesSpec('Havacı', shape: GlassesShape.aviator, thickness: 0.6, frame: Color(0xFFC8A552), tint: Color(0x26FFE7A8)),
  GlassesSpec('Wayfarer', shape: GlassesShape.wayfarer, thickness: 1.8, frame: Color(0xFF15181C)),
  GlassesSpec('Yarım Çerçeve', shape: GlassesShape.browline, thickness: 1.2, frame: Color(0xFF3A3F47)),
  GlassesSpec('Altıgen', shape: GlassesShape.hexagon, thickness: 0.8, frame: Color(0xFFBFA36A)),
  GlassesSpec('Çerçevesiz', shape: GlassesShape.rect, thickness: 0.5, rimless: true, frame: Color(0xFFB9C3CC)),
  GlassesSpec('Okuma', shape: GlassesShape.halfMoon, thickness: 0.9, frame: Color(0xFF8A3D3D)),
  GlassesSpec('Güneş', shape: GlassesShape.wayfarer, sun: true, thickness: 1.6, frame: Color(0xFF15181C)),
  GlassesSpec('Havacı Güneş', shape: GlassesShape.aviator, sun: true, thickness: 0.7, frame: Color(0xFFC8A552)),
  GlassesSpec('Yuvarlak Güneş', shape: GlassesShape.round, sun: true, thickness: 1.0, frame: Color(0xFF2A2018)),
  GlassesSpec('Spor Güneş', shape: GlassesShape.wrap, sun: true, thickness: 1.2, frame: Color(0xFF1B1F27)),
];

// --------------------------------------------------------------- başlık

enum Headwear {
  none,
  cap,
  capBack,
  beanie,
  beaniePom,
  fedora,
  flatCap,
  sunHat,
  headband,
  bandana,
  headphones,
  flowerCrown,
  tiara,
  bow,
  clips,
  visor,
  turbanWrap,
  hood,
}

@immutable
class HeadwearSpec {
  final String label;
  final Headwear kind;
  final Color color;
  const HeadwearSpec(this.label, this.kind, [this.color = const Color(0xFF3F5E8C)]);
}

const List<HeadwearSpec> kHeadwearStyles = [
  HeadwearSpec('Yok', Headwear.none),
  HeadwearSpec('Kep', Headwear.cap, Color(0xFFB5443A)),
  HeadwearSpec('Mavi Kep', Headwear.cap, Color(0xFF2F5FA8)),
  HeadwearSpec('Ters Kep', Headwear.capBack, Color(0xFF232830)),
  HeadwearSpec('Bere', Headwear.beanie, Color(0xFF3B4A5C)),
  HeadwearSpec('Kırmızı Bere', Headwear.beanie, Color(0xFFC0392B)),
  HeadwearSpec('Ponponlu Bere', Headwear.beaniePom, Color(0xFFE8DED0)),
  HeadwearSpec('Fötr Şapka', Headwear.fedora, Color(0xFF4A3A2E)),
  HeadwearSpec('Kasket', Headwear.flatCap, Color(0xFF6B6F76)),
  HeadwearSpec('Hasır Şapka', Headwear.sunHat, Color(0xFFD9BE86)),
  HeadwearSpec('Saç Bandı', Headwear.headband, Color(0xFFD9578A)),
  HeadwearSpec('Bandana', Headwear.bandana, Color(0xFFB03A2E)),
  HeadwearSpec('Kulaklık', Headwear.headphones, Color(0xFF1F2430)),
  HeadwearSpec('Çiçek Tacı', Headwear.flowerCrown, Color(0xFFE88AA8)),
  HeadwearSpec('Taç', Headwear.tiara, Color(0xFFD9B44A)),
  HeadwearSpec('Fiyonk', Headwear.bow, Color(0xFFE05A86)),
  HeadwearSpec('Tokalar', Headwear.clips, Color(0xFFD9B44A)),
  HeadwearSpec('Vizör', Headwear.visor, Color(0xFF2F5FA8)),
  HeadwearSpec('Kapüşon', Headwear.hood, Color(0xFF3B4A5C)),
];

// --------------------------------------------------------------------- takı

enum Jewelry {
  none,
  studs,
  pearls,
  hoops,
  bigHoops,
  drops,
  gems,
  studsChain,
  hoopsChain,
  noseStud,
  cuffs,
}

@immutable
class JewelrySpec {
  final String label;
  final Jewelry kind;
  final Color color;
  const JewelrySpec(this.label, this.kind, [this.color = const Color(0xFFD9B44A)]);
}

const List<JewelrySpec> kJewelryStyles = [
  JewelrySpec('Yok', Jewelry.none),
  JewelrySpec('Altın Küpe', Jewelry.studs),
  JewelrySpec('Gümüş Küpe', Jewelry.studs, Color(0xFFCDD3DA)),
  JewelrySpec('İnci Küpe', Jewelry.pearls, Color(0xFFF2EBDD)),
  JewelrySpec('Halka Küpe', Jewelry.hoops),
  JewelrySpec('Büyük Halka', Jewelry.bigHoops),
  JewelrySpec('Gümüş Halka', Jewelry.hoops, Color(0xFFCDD3DA)),
  JewelrySpec('Sarkık Küpe', Jewelry.drops),
  JewelrySpec('Mavi Taş', Jewelry.gems, Color(0xFF4F86D9)),
  JewelrySpec('Küpe + Kolye', Jewelry.studsChain),
  JewelrySpec('Halka + Kolye', Jewelry.hoopsChain),
  JewelrySpec('Burun Piercing', Jewelry.noseStud),
];

// -------------------------------------------------------------- yüz detayı

@immutable
class DetailSpec {
  final String label;
  final double freckles;
  final double blush;
  final int moles; // bit maskesi: 1 yanak, 2 dudak üstü, 4 çene, 8 şakak
  final bool dimples;
  final double eyebags;
  final double sunkissed;
  const DetailSpec(
    this.label, {
    this.freckles = 0,
    this.blush = 0,
    this.moles = 0,
    this.dimples = false,
    this.eyebags = 0,
    this.sunkissed = 0,
  });
}

const List<DetailSpec> kDetailStyles = [
  DetailSpec('Yok'),
  DetailSpec('Az Çil', freckles: 0.45),
  DetailSpec('Çok Çil', freckles: 1.0),
  DetailSpec('Çil + Allık', freckles: 0.8, blush: 0.6),
  DetailSpec('Allık', blush: 0.7),
  DetailSpec('Yumuşak Allık', blush: 0.35),
  DetailSpec('Yanak Beni', moles: 1),
  DetailSpec('Dudak Üstü Ben', moles: 2),
  DetailSpec('Çene Beni', moles: 4),
  DetailSpec('Şakak Beni', moles: 8),
  DetailSpec('Gamze', dimples: true, blush: 0.2),
  DetailSpec('Göz Altı Torbası', eyebags: 0.8),
  DetailSpec('Güneş Yanığı', sunkissed: 1.0, freckles: 0.4),
  DetailSpec('Çil + Ben', freckles: 0.5, moles: 1),
];

// -------------------------------------------------------------- kıyafet

enum ClothingKind {
  crew,
  vneck,
  polo,
  henley,
  hoodie,
  turtleneck,
  blazer,
  shirtTie,
  tank,
  scoop,
  sweater,
  bomber,
}

@immutable
class ClothingSpec {
  final String label;
  final ClothingKind kind;
  const ClothingSpec(this.label, this.kind);
}

const List<ClothingSpec> kClothingStyles = [
  ClothingSpec('Tişört', ClothingKind.crew),
  ClothingSpec('V Yaka', ClothingKind.vneck),
  ClothingSpec('Polo', ClothingKind.polo),
  ClothingSpec('Düğmeli', ClothingKind.henley),
  ClothingSpec('Kapüşonlu', ClothingKind.hoodie),
  ClothingSpec('Boğazlı', ClothingKind.turtleneck),
  ClothingSpec('Ceket', ClothingKind.blazer),
  ClothingSpec('Gömlek Kravat', ClothingKind.shirtTie),
  ClothingSpec('Askılı', ClothingKind.tank),
  ClothingSpec('Geniş Yaka', ClothingKind.scoop),
  ClothingSpec('Kazak', ClothingKind.sweater),
  ClothingSpec('Bomber', ClothingKind.bomber),
];

// ----------------------------------------------------------------- ölçüler

/// Fotoğraftaki yüzden ölçülen oranlar. 1.0 = ortalama yüz.
@immutable
class FaceMetrics {
  final double faceWidth;
  final double jawWidth;
  final double chinLength;
  final double eyeSize;
  final double eyeSpacing;
  final double browHeight;
  final double browThickness;
  final double noseWidth;
  final double lipFullness;
  final double mouthWidth;
  final double smile;

  const FaceMetrics({
    this.faceWidth = 1.0,
    this.jawWidth = 1.0,
    this.chinLength = 1.0,
    this.eyeSize = 1.0,
    this.eyeSpacing = 1.0,
    this.browHeight = 1.0,
    this.browThickness = 1.0,
    this.noseWidth = 1.0,
    this.lipFullness = 1.0,
    this.mouthWidth = 1.0,
    this.smile = 0.35,
  });

  static const FaceMetrics average = FaceMetrics();

  @override
  bool operator ==(Object other) =>
      other is FaceMetrics &&
      other.faceWidth == faceWidth &&
      other.jawWidth == jawWidth &&
      other.chinLength == chinLength &&
      other.eyeSize == eyeSize &&
      other.eyeSpacing == eyeSpacing &&
      other.browHeight == browHeight &&
      other.browThickness == browThickness &&
      other.noseWidth == noseWidth &&
      other.lipFullness == lipFullness &&
      other.mouthWidth == mouthWidth &&
      other.smile == smile;

  @override
  int get hashCode => Object.hash(faceWidth, jawWidth, chinLength, eyeSize, eyeSpacing,
      browHeight, browThickness, noseWidth, lipFullness, mouthWidth, smile);
}

// ------------------------------------------------------------------ tarif

@immutable
class FaceAvatarConfig {
  final int faceShape;
  final Color skinTone;
  final int hair;
  final Color hairColor;
  final int brow;
  final int eye;
  final Color eyeColor;
  final int lash;
  final int nose;
  final int lips;
  final int lipColor;
  final int beard;
  final int glasses;
  final int headwear;
  final int jewelry;
  final int detail;

  /// 0 genç, 1 orta yaş, 2 olgun, 3 yaşlı — yüz çizgileri ve saç grileşmesi.
  final int age;
  final int clothing;
  final Color clothingColor;
  final int background;
  final FaceMetrics metrics;
  final bool isSuggested;

  const FaceAvatarConfig({
    this.faceShape = 0,
    this.skinTone = const Color(0xFFF4C9A8),
    this.hair = 4,
    this.hairColor = const Color(0xFF382519),
    this.brow = 1,
    this.eye = 0,
    this.eyeColor = const Color(0xFF6B4423),
    this.lash = 1,
    this.nose = 0,
    this.lips = 0,
    this.lipColor = 0,
    this.beard = 0,
    this.glasses = 0,
    this.headwear = 0,
    this.jewelry = 0,
    this.detail = 0,
    this.age = 0,
    this.clothing = 0,
    this.clothingColor = const Color(0xFF2F3A4A),
    this.background = 0,
    this.metrics = FaceMetrics.average,
    this.isSuggested = false,
  });

  static const FaceAvatarConfig defaultConfig = FaceAvatarConfig();

  FaceShapeSpec get faceShapeSpec => kFaceShapes[faceShape.clamp(0, kFaceShapes.length - 1)];
  HairSpec get hairSpec => kHairStyles[hair.clamp(0, kHairStyles.length - 1)];
  BrowSpec get browSpec => kBrowStyles[brow.clamp(0, kBrowStyles.length - 1)];
  EyeSpec get eyeSpec => kEyeStyles[eye.clamp(0, kEyeStyles.length - 1)];
  LashSpec get lashSpec => kLashStyles[lash.clamp(0, kLashStyles.length - 1)];
  NoseSpec get noseSpec => kNoseStyles[nose.clamp(0, kNoseStyles.length - 1)];
  LipSpec get lipSpec => kLipStyles[lips.clamp(0, kLipStyles.length - 1)];
  BeardSpec get beardSpec => kBeardStyles[beard.clamp(0, kBeardStyles.length - 1)];
  GlassesSpec get glassesSpec => kGlassesStyles[glasses.clamp(0, kGlassesStyles.length - 1)];
  HeadwearSpec get headwearSpec => kHeadwearStyles[headwear.clamp(0, kHeadwearStyles.length - 1)];
  JewelrySpec get jewelrySpec => kJewelryStyles[jewelry.clamp(0, kJewelryStyles.length - 1)];
  DetailSpec get detailSpec => kDetailStyles[detail.clamp(0, kDetailStyles.length - 1)];
  ClothingSpec get clothingSpec => kClothingStyles[clothing.clamp(0, kClothingStyles.length - 1)];
  BackgroundSpec get backgroundSpec => kBackgrounds[background.clamp(0, kBackgrounds.length - 1)];

  FaceAvatarConfig copyWith({
    int? faceShape,
    Color? skinTone,
    int? hair,
    Color? hairColor,
    int? brow,
    int? eye,
    Color? eyeColor,
    int? lash,
    int? nose,
    int? lips,
    int? lipColor,
    int? beard,
    int? glasses,
    int? headwear,
    int? jewelry,
    int? detail,
    int? age,
    int? clothing,
    Color? clothingColor,
    int? background,
    FaceMetrics? metrics,
    bool? isSuggested,
  }) {
    return FaceAvatarConfig(
      faceShape: faceShape ?? this.faceShape,
      skinTone: skinTone ?? this.skinTone,
      hair: hair ?? this.hair,
      hairColor: hairColor ?? this.hairColor,
      brow: brow ?? this.brow,
      eye: eye ?? this.eye,
      eyeColor: eyeColor ?? this.eyeColor,
      lash: lash ?? this.lash,
      nose: nose ?? this.nose,
      lips: lips ?? this.lips,
      lipColor: lipColor ?? this.lipColor,
      beard: beard ?? this.beard,
      glasses: glasses ?? this.glasses,
      headwear: headwear ?? this.headwear,
      jewelry: jewelry ?? this.jewelry,
      detail: detail ?? this.detail,
      age: age ?? this.age,
      clothing: clothing ?? this.clothing,
      clothingColor: clothingColor ?? this.clothingColor,
      background: background ?? this.background,
      metrics: metrics ?? this.metrics,
      isSuggested: isSuggested ?? this.isSuggested,
    );
  }

  /// Ölçülen yüz oranlarını ve fotoğraftan gelen renkleri koruyarak stilleri
  /// rastgele değiştirir; birbirine yakışmayan kombinasyonlardan kaçınır
  /// (kepin altına afro, kapalı saça sakal, gözlük+güneş gözlüğü çakışması).
  FaceAvatarConfig shuffled(math.Random r) {
    final hairIdx = r.nextInt(kHairStyles.length);
    final spec = kHairStyles[hairIdx];
    final covered = spec.covered;
    final headwearIdx = (covered || r.nextInt(4) != 0) ? 0 : r.nextInt(kHeadwearStyles.length);
    return copyWith(
      hair: hairIdx,
      hairColor: kHairColors[r.nextInt(r.nextInt(5) == 0 ? kHairColors.length : kNaturalHairColorCount)],
      brow: r.nextInt(kBrowStyles.length),
      eye: r.nextInt(kEyeStyles.length),
      lash: r.nextInt(kLashStyles.length),
      nose: r.nextInt(kNoseStyles.length),
      lips: r.nextInt(kLipStyles.length),
      lipColor: r.nextInt(3) == 0 ? r.nextInt(kLipColors.length) : 0,
      beard: r.nextInt(3) == 0 ? r.nextInt(kBeardStyles.length) : 0,
      glasses: r.nextInt(3) == 0 ? r.nextInt(kGlassesStyles.length) : 0,
      headwear: headwearIdx,
      jewelry: r.nextInt(3) == 0 ? r.nextInt(kJewelryStyles.length) : 0,
      detail: r.nextInt(3) == 0 ? r.nextInt(kDetailStyles.length) : 0,
      clothing: r.nextInt(kClothingStyles.length),
      clothingColor: kClothingColors[r.nextInt(kClothingColors.length)],
      background: r.nextInt(kBackgrounds.length),
      isSuggested: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FaceAvatarConfig &&
      other.faceShape == faceShape &&
      other.skinTone == skinTone &&
      other.hair == hair &&
      other.hairColor == hairColor &&
      other.brow == brow &&
      other.eye == eye &&
      other.eyeColor == eyeColor &&
      other.lash == lash &&
      other.nose == nose &&
      other.lips == lips &&
      other.lipColor == lipColor &&
      other.beard == beard &&
      other.glasses == glasses &&
      other.headwear == headwear &&
      other.jewelry == jewelry &&
      other.detail == detail &&
      other.age == age &&
      other.clothing == clothing &&
      other.clothingColor == clothingColor &&
      other.background == background &&
      other.metrics == metrics;

  @override
  int get hashCode => Object.hashAll([
        faceShape,
        skinTone,
        hair,
        hairColor,
        brow,
        eye,
        eyeColor,
        lash,
        nose,
        lips,
        lipColor,
        beard,
        glasses,
        headwear,
        jewelry,
        detail,
        age,
        clothing,
        clothingColor,
        background,
        metrics,
      ]);
}
