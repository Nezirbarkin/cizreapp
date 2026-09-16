// Avatar kataloğu ve tarifi.
//
// Her parça (yüz şekli, saç, kaş, göz, kirpik, sakal, gözlük) tek tek elle
// çizilmiş bir path değil, PARAMETRİK BİR TARİF (spec). Çizim motoru bu
// tariflere göre üretir; katalog büyütmek yeni bir satır eklemek demek.
//
// Katalog: 8 yüz şekli × 24 saç × 8 saç rengi × 10 kaş × 10 göz × 6 göz rengi
// × 6 kirpik × 12 sakal × 4 gözlük × 8 ten tonu → pratikte sınırsız kombinasyon.
//
// Bunların bir kısmı fotoğraftan ÖLÇÜLEREK seçilir (yüz şekli, göz şekli, kaş
// kalınlığı, saç uzunluğu, sakal yoğunluğu, ten/saç/göz rengi), kalanı
// kullanıcının tercihidir.
import 'package:flutter/material.dart';

enum FaceAvatarCategory { faceShape, skin, hair, brow, eye, lash, beard, glasses }

// ---------------------------------------------------------------- paletler

const List<Color> kSkinTones = [
  Color(0xFFFFE0C4),
  Color(0xFFF7CDA8),
  Color(0xFFE9B489),
  Color(0xFFD29A6D),
  Color(0xFFB27A4F),
  Color(0xFF8D5C39),
  Color(0xFF6B422A),
  Color(0xFF4A2D1D),
];

const List<Color> kHairColors = [
  Color(0xFF15100C),
  Color(0xFF3B2A1E),
  Color(0xFF5C3A22),
  Color(0xFF8A5A32),
  Color(0xFFB98A4E),
  Color(0xFFE0C08A),
  Color(0xFF8E3B22),
  Color(0xFF9AA0A6),
];

const List<Color> kEyeColors = [
  Color(0xFF4A2E1C),
  Color(0xFF6B4423),
  Color(0xFF8C6B3F),
  Color(0xFF4F7A52),
  Color(0xFF3F6E96),
  Color(0xFF6E8A9B),
];

const List<Color> kClothingColors = [
  Color(0xFF2F3A4A),
  Color(0xFF3F5E8C),
  Color(0xFF7A3B52),
  Color(0xFF2E6B5B),
  Color(0xFF8A5A2B),
  Color(0xFF4A4A52),
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

  const FaceShapeSpec(this.label, {
    required this.forehead,
    required this.cheek,
    required this.jaw,
    required this.chin,
    required this.corner,
  });
}

const List<FaceShapeSpec> kFaceShapes = [
  FaceShapeSpec('Oval', forehead: 1.00, cheek: 1.00, jaw: 0.95, chin: 1.00, corner: 0.15),
  FaceShapeSpec('Yuvarlak', forehead: 1.02, cheek: 1.14, jaw: 1.02, chin: 0.84, corner: 0.05),
  FaceShapeSpec('Kare', forehead: 1.08, cheek: 1.06, jaw: 1.21, chin: 0.88, corner: 0.90),
  FaceShapeSpec('Kalp', forehead: 1.13, cheek: 1.03, jaw: 0.75, chin: 1.05, corner: 0.20),
  FaceShapeSpec('Uzun', forehead: 0.93, cheek: 0.89, jaw: 0.86, chin: 1.26, corner: 0.25),
  FaceShapeSpec('Elmas', forehead: 0.84, cheek: 1.13, jaw: 0.80, chin: 1.10, corner: 0.18),
  FaceShapeSpec('Üçgen', forehead: 0.82, cheek: 0.95, jaw: 1.20, chin: 0.96, corner: 0.60),
  FaceShapeSpec('Armut', forehead: 0.86, cheek: 1.02, jaw: 1.16, chin: 1.00, corner: 0.35),
];

// ------------------------------------------------------------------- saç

enum HairTexture { smooth, wavy, curly, coily }

enum HairFringe { none, side, blunt, curtain, spiky }

enum HairSides { none, sideburn, short, long, tucked }

enum HairBack { none, medium, long, bun, highBun, ponytail, lowPonytail, braid, pigtails }

@immutable
class HairSpec {
  final String label;

  /// Kepin kafatası üstündeki hacmi (0 = yapışık, 1 = dolgun).
  final double volume;

  /// Saç çizgisinin yüksekliği (küçük = daha açık alın).
  final double hairlineY;

  final HairTexture texture;
  final HairFringe fringe;
  final HairSides sides;
  final HairBack back;

  /// Saçsız (kel) ya da özel başörtüsü katmanı.
  final bool bald;
  final bool headscarf;

  const HairSpec(
    this.label, {
    this.volume = 0.4,
    this.hairlineY = 54,
    this.texture = HairTexture.smooth,
    this.fringe = HairFringe.none,
    this.sides = HairSides.sideburn,
    this.back = HairBack.none,
    this.bald = false,
    this.headscarf = false,
  });
}

const List<HairSpec> kHairStyles = [
  HairSpec('Kel', bald: true, sides: HairSides.none),
  HairSpec('Asker', volume: 0.05, hairlineY: 49, sides: HairSides.sideburn),
  HairSpec('Çok Kısa', volume: 0.18, hairlineY: 51),
  HairSpec('Kısa', volume: 0.40, hairlineY: 53),
  HairSpec('Kısa Dalgalı', volume: 0.50, hairlineY: 53, texture: HairTexture.wavy),
  HairSpec('Yana Ayrık', volume: 0.45, hairlineY: 55, fringe: HairFringe.side),
  HairSpec('Öne Taralı', volume: 0.38, hairlineY: 57, fringe: HairFringe.blunt),
  HairSpec('Kirpi', volume: 0.72, hairlineY: 52, fringe: HairFringe.spiky),
  HairSpec('Kısa Kıvırcık', volume: 0.55, hairlineY: 54, texture: HairTexture.curly),
  HairSpec('Afro', volume: 1.0, hairlineY: 55, texture: HairTexture.coily),
  HairSpec('Sıkı Bukle', volume: 0.75, hairlineY: 55, texture: HairTexture.coily, sides: HairSides.short),
  HairSpec('Orta Düz', volume: 0.45, hairlineY: 54, sides: HairSides.short, back: HairBack.medium),
  HairSpec('Orta Dalgalı', volume: 0.55, hairlineY: 54, texture: HairTexture.wavy, sides: HairSides.short, back: HairBack.medium),
  HairSpec('Uzun Düz', volume: 0.45, hairlineY: 54, sides: HairSides.long, back: HairBack.long),
  HairSpec('Uzun Dalgalı', volume: 0.58, hairlineY: 54, texture: HairTexture.wavy, sides: HairSides.long, back: HairBack.long),
  HairSpec('Uzun Kıvırcık', volume: 0.70, hairlineY: 55, texture: HairTexture.curly, sides: HairSides.long, back: HairBack.long),
  HairSpec('Kâkül', volume: 0.50, hairlineY: 58, fringe: HairFringe.blunt, sides: HairSides.long, back: HairBack.long),
  HairSpec('Perde Kâkül', volume: 0.52, hairlineY: 56, fringe: HairFringe.curtain, sides: HairSides.long, back: HairBack.medium),
  HairSpec('Topuz', volume: 0.30, hairlineY: 53, sides: HairSides.tucked, back: HairBack.bun),
  HairSpec('Yüksek Topuz', volume: 0.28, hairlineY: 52, sides: HairSides.tucked, back: HairBack.highBun),
  HairSpec('At Kuyruğu', volume: 0.35, hairlineY: 54, sides: HairSides.tucked, back: HairBack.ponytail),
  HairSpec('Alçak Kuyruk', volume: 0.35, hairlineY: 54, sides: HairSides.short, back: HairBack.lowPonytail),
  HairSpec('Örgü', volume: 0.35, hairlineY: 54, sides: HairSides.tucked, back: HairBack.braid),
  HairSpec('İki Örgü', volume: 0.35, hairlineY: 54, sides: HairSides.short, back: HairBack.pigtails),
  HairSpec('Başörtüsü', headscarf: true, sides: HairSides.none),
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

  const BrowSpec(
    this.label, {
    this.thickness = 1.0,
    this.arch = 1.0,
    this.tilt = 0.0,
    this.length = 1.0,
    this.taper = 1.0,
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

  const EyeSpec(
    this.label, {
    this.width = 1.0,
    this.height = 1.0,
    this.tilt = 0.0,
    this.hooded = false,
    this.closed = false,
  });
}

const List<EyeSpec> kEyeStyles = [
  EyeSpec('Normal'),
  EyeSpec('Badem', width: 1.10, height: 0.80),
  EyeSpec('İri', width: 1.08, height: 1.24),
  EyeSpec('Küçük', width: 0.86, height: 0.84),
  EyeSpec('Yuvarlak', width: 0.96, height: 1.18),
  EyeSpec('Çekik', width: 1.08, height: 0.86, tilt: 2.2),
  EyeSpec('Düşük', width: 1.05, height: 0.92, tilt: -2.0),
  EyeSpec('Kapaklı', width: 1.04, height: 0.90, hooded: true),
  EyeSpec('Uykulu', width: 1.0, height: 0.64),
  EyeSpec('Gülen', closed: true),
];

// ---------------------------------------------------------------- kirpik

@immutable
class LashSpec {
  final String label;
  final double length;
  final double thickness;
  final bool winged;
  final bool lower;

  const LashSpec(
    this.label, {
    this.length = 0,
    this.thickness = 1.0,
    this.winged = false,
    this.lower = false,
  });
}

const List<LashSpec> kLashStyles = [
  LashSpec('Yok'),
  LashSpec('Doğal', length: 0.42, thickness: 0.85),
  LashSpec('Uzun', length: 1.15),
  LashSpec('Kalın', length: 0.85, thickness: 1.6),
  LashSpec('Kedi Gözü', length: 1.25, thickness: 1.35, winged: true),
  LashSpec('Alt + Üst', length: 0.9, thickness: 1.15, lower: true),
];

// ------------------------------------------------------------------ sakal

@immutable
class BeardSpec {
  final String label;

  /// 0 = yok, 1 = çeneyi saran, 1.3 = uzun.
  final double coverage;
  final bool mustache;
  final double mustacheWidth;
  final double mustacheThickness;
  final bool chinOnly;
  final bool soulPatch;
  final bool chinStrap;

  /// Yumuşak/şeffaf (tıraşlı izlenimi).
  final double opacity;

  const BeardSpec(
    this.label, {
    this.coverage = 0,
    this.mustache = false,
    this.mustacheWidth = 1.0,
    this.mustacheThickness = 1.0,
    this.chinOnly = false,
    this.soulPatch = false,
    this.chinStrap = false,
    this.opacity = 1.0,
  });
}

const List<BeardSpec> kBeardStyles = [
  BeardSpec('Yok'),
  BeardSpec('Hafif', coverage: 0.55, opacity: 0.30),
  BeardSpec('Üç Günlük', coverage: 0.70, mustache: true, mustacheThickness: 0.7, opacity: 0.55),
  BeardSpec('Bıyık', mustache: true),
  BeardSpec('İnce Bıyık', mustache: true, mustacheWidth: 0.85, mustacheThickness: 0.6),
  BeardSpec('Kalın Bıyık', mustache: true, mustacheWidth: 1.2, mustacheThickness: 1.5),
  BeardSpec('Sakal Ucu', soulPatch: true),
  BeardSpec('Keçi', mustache: true, chinOnly: true),
  BeardSpec('Çene Şeridi', coverage: 0.85, chinStrap: true),
  BeardSpec('Kısa Sakal', coverage: 0.72, mustache: true, opacity: 0.94),
  BeardSpec('Tam Sakal', coverage: 1.0, mustache: true),
  BeardSpec('Uzun Sakal', coverage: 1.32, mustache: true, mustacheWidth: 1.1),
];

// ----------------------------------------------------------------- gözlük

@immutable
class GlassesSpec {
  final String label;
  final bool round;
  final bool sun;
  final double width;
  final double height;

  const GlassesSpec(
    this.label, {
    this.round = false,
    this.sun = false,
    this.width = 1.0,
    this.height = 1.0,
  });
}

const List<GlassesSpec> kGlassesStyles = [
  GlassesSpec('Yok', width: 0),
  GlassesSpec('İnce'),
  GlassesSpec('Yuvarlak', round: true),
  GlassesSpec('Kalın', width: 1.08, height: 1.12),
  GlassesSpec('Güneş', sun: true, width: 1.05),
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
  final int beard;
  final int glasses;
  final Color clothingColor;
  final FaceMetrics metrics;
  final bool isSuggested;

  const FaceAvatarConfig({
    this.faceShape = 0,
    this.skinTone = const Color(0xFFF7CDA8),
    this.hair = 3,
    this.hairColor = const Color(0xFF3B2A1E),
    this.brow = 1,
    this.eye = 0,
    this.eyeColor = const Color(0xFF6B4423),
    this.lash = 1,
    this.beard = 0,
    this.glasses = 0,
    this.clothingColor = const Color(0xFF2F3A4A),
    this.metrics = FaceMetrics.average,
    this.isSuggested = false,
  });

  static const FaceAvatarConfig defaultConfig = FaceAvatarConfig();

  FaceShapeSpec get faceShapeSpec => kFaceShapes[faceShape.clamp(0, kFaceShapes.length - 1)];
  HairSpec get hairSpec => kHairStyles[hair.clamp(0, kHairStyles.length - 1)];
  BrowSpec get browSpec => kBrowStyles[brow.clamp(0, kBrowStyles.length - 1)];
  EyeSpec get eyeSpec => kEyeStyles[eye.clamp(0, kEyeStyles.length - 1)];
  LashSpec get lashSpec => kLashStyles[lash.clamp(0, kLashStyles.length - 1)];
  BeardSpec get beardSpec => kBeardStyles[beard.clamp(0, kBeardStyles.length - 1)];
  GlassesSpec get glassesSpec => kGlassesStyles[glasses.clamp(0, kGlassesStyles.length - 1)];

  FaceAvatarConfig copyWith({
    int? faceShape,
    Color? skinTone,
    int? hair,
    Color? hairColor,
    int? brow,
    int? eye,
    Color? eyeColor,
    int? lash,
    int? beard,
    int? glasses,
    Color? clothingColor,
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
      beard: beard ?? this.beard,
      glasses: glasses ?? this.glasses,
      clothingColor: clothingColor ?? this.clothingColor,
      metrics: metrics ?? this.metrics,
      isSuggested: isSuggested ?? this.isSuggested,
    );
  }
}
