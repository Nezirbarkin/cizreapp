// Selfie'den kişiye benzeyen Bitmoji tarzı avatar üretir.
//
// 1) ML Kit yüzü, konturları (yüz ovali, kaş, göz, burun, dudak) ve gülümseme
//    olasılığını bulur.
// 2) Fotoğrafın pikselleri çözülür; EXIF dönüşü farklı uygulanmışsa doğru
//    eşleme (0/90/180/270°) göz-yanak karşıtlığından otomatik seçilir.
// 3) Her şey yüz hizalı koordinatlara çevrilir (bkz. face_likeness.dart):
//    baş eğikliği, kameraya uzaklık ve çözünürlük sonucu etkilemez.
// 4) ÖLÇÜLEN: yüz şekli ve oranları, göz/kaş/burun/dudak biçimi, ten, saç,
//    göz ve kıyafet rengi, saçın uzunluğu/hacmi/genişliği/kâkülü/dokusu
//    (90 stil puanlanır), sakal/bıyık, gözlük, başörtüsü, ruj.
//
// Sonuç, avatarla birlikte ekranda gösterilecek tespitleri, alternatif saç
// önerilerini ve tarama animasyonu için kontur noktalarını taşır.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, Offset, Rect;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_avatar_config.dart';
import 'face_likeness.dart';

/// Sonuç ekranında gösterilen tek bir tespit ("Saç: Uzun Dalgalı").
class FaceTrait {
  final String label;
  final String value;
  final Color? swatch;
  const FaceTrait(this.label, this.value, {this.swatch});
}

class FaceAnalysis {
  final FaceAvatarConfig config;
  final bool faceFound;
  final List<FaceTrait> traits;

  /// Ölçüme en yakın saç stilleri (ilki seçilen).
  final List<int> hairCandidates;

  /// Fotoğrafta bulunan konturlar (0..1 normalize, fotoğrafın görünen yönünde).
  final List<List<Offset>> overlay;

  /// Yüz kutusu (0..1 normalize).
  final Rect? faceBox;

  /// Kullanıcıya ipucu (ör. "Kameraya düz bak").
  final String? hint;

  /// Fotoğraftan ölçülen ten/saç rengi (editörde "fotoğraftan" rengi olarak).
  final Color? photoSkin;
  final Color? photoHair;

  const FaceAnalysis({
    required this.config,
    this.faceFound = true,
    this.traits = const [],
    this.hairCandidates = const [],
    this.overlay = const [],
    this.faceBox,
    this.hint,
    this.photoSkin,
    this.photoHair,
  });

  static FaceAnalysis notFound(String hint) => FaceAnalysis(
        config: FaceAvatarConfig.defaultConfig.copyWith(isSuggested: true),
        faceFound: false,
        hint: hint,
      );
}

const List<String> _eyeColorNames = [
  'Çok koyu kahve',
  'Koyu kahve',
  'Kahve',
  'Ela',
  'Kehribar',
  'Yeşil-ela',
  'Yeşil',
  'Mavi-yeşil',
  'Mavi',
  'Açık mavi',
  'Gri-mavi',
  'Gri',
];

class FaceAvatarAnalyzer {
  static Future<FaceAnalysis> analyze({required String imagePath, required Uint8List photoBytes}) async {
    FaceDetector? detector;
    try {
      detector = FaceDetector(
        options: FaceDetectorOptions(
          enableLandmarks: true,
          enableContours: true,
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.15,
        ),
      );

      final faces = await detector.processImage(InputImage.fromFilePath(imagePath));
      if (faces.isEmpty) {
        debugPrint('ℹ️ Yüz avatarı: fotoğrafta yüz bulunamadı');
        return FaceAnalysis.notFound('Yüz bulunamadı. Işıklı bir yerde, yüzün kadrajı dolduracak şekilde tekrar dene.');
      }
      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
      final face = faces.first;

      // ------------------------------------------------------------ pikseller
      final codec = await ui.instantiateImageCodec(photoBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width, h = image.height;
      image.dispose();
      if (byteData == null) return FaceAnalysis.notFound('Fotoğraf okunamadı, tekrar dene.');
      final px = RgbaPixels(byteData.buffer.asUint8List(), w, h);

      return _Measure(face, px).run();
    } catch (e, st) {
      debugPrint('❌ Yüz analizi başarısız, varsayılan öneriyle devam ediliyor: $e\n$st');
      return FaceAnalysis.notFound('Yüz ölçülemedi, varsayılan avatar gösteriliyor. Yeniden çekebilirsin.');
    } finally {
      await detector?.close();
    }
  }
}

/// Ölçüm ana isolate'te yapılır: ML Kit nesneleri isolate'e taşınamaz ve
/// örnek sayısı birkaç binle sınırlı olduğu için hızlıdır.
class _Measure {
  final Face face;
  final RgbaPixels px;
  _Measure(this.face, this.px);

  List<Offset> _pts(FaceContourType t) =>
      face.contours[t]?.points.map((p) => Offset(p.x.toDouble(), p.y.toDouble())).toList() ?? const [];

  Offset? _lm(FaceLandmarkType t) {
    final p = face.landmarks[t]?.position;
    return p == null ? null : Offset(p.x.toDouble(), p.y.toDouble());
  }

  static Offset? _center(List<Offset> pts) {
    if (pts.isEmpty) return null;
    var s = Offset.zero;
    for (final p in pts) {
      s += p;
    }
    return s / pts.length.toDouble();
  }

  FaceAnalysis run() {
    final eyeL = _center(_pts(FaceContourType.leftEye)) ?? _lm(FaceLandmarkType.leftEye);
    final eyeR = _center(_pts(FaceContourType.rightEye)) ?? _lm(FaceLandmarkType.rightEye);
    final below = _lm(FaceLandmarkType.noseBase) ?? _lm(FaceLandmarkType.bottomMouth) ?? face.boundingBox.bottomCenter;
    if (eyeL == null || eyeR == null) {
      return FaceAnalysis.notFound('Gözler net görünmüyor; gözlük/şapka varsa çıkarıp tekrar dene.');
    }

    // -------------------------------------------- algılama → piksel eşlemesi
    final maps = candidateMappings(px.width, px.height);
    var map = maps.first;
    var bestScore = -1e9;
    for (var i = 0; i < maps.length; i++) {
      final m = maps[i];
      final f = FaceFrame.fromEyes(m(eyeL), m(eyeR), m(below));
      final s = FaceSampler(px, f);
      final eyes = [s.at(const Offset(-0.5, 0), radius: 0.06), s.at(const Offset(0.5, 0), radius: 0.06)];
      final cheeks = [s.at(const Offset(-0.62, 0.55), radius: 0.08), s.at(const Offset(0.62, 0.55), radius: 0.08)];
      if (eyes.contains(null) || cheeks.contains(null)) continue;
      // Gözler yanaklardan koyudur; kimlik eşlemesi küçük bir avantajla seçilir.
      final score = (cheeks[0]!.l + cheeks[1]!.l) / 2 - (eyes[0]!.l + eyes[1]!.l) / 2 + (i == 0 ? 4 : 0);
      if (score > bestScore) {
        bestScore = score;
        map = m;
      }
    }

    final frame = FaceFrame.fromEyes(map(eyeL), map(eyeR), map(below));
    List<Offset> toFace(FaceContourType t) => _pts(t).map((p) => frame.toFace(map(p))).toList();

    final geo = FaceGeometry(
      contour: toFace(FaceContourType.face),
      browTop: [...toFace(FaceContourType.leftEyebrowTop), ...toFace(FaceContourType.rightEyebrowTop)],
      browBottom: [...toFace(FaceContourType.leftEyebrowBottom), ...toFace(FaceContourType.rightEyebrowBottom)],
      eyeA: toFace(FaceContourType.leftEye),
      eyeB: toFace(FaceContourType.rightEye),
      upperLipTop: toFace(FaceContourType.upperLipTop),
      lowerLipBottom: toFace(FaceContourType.lowerLipBottom),
      noseBottom: toFace(FaceContourType.noseBottom),
    );
    final sampler = FaceSampler(px, frame);
    final probe = LikenessProbe(sampler, geo);

    // ------------------------------------------------------------- oranlar
    final pitch = ((face.headEulerAngleX ?? 0).clamp(-25.0, 25.0)) * math.pi / 180;
    final vfix = 1 / math.cos(pitch);
    final faceW = geo.widthAt(0);
    final jawW = geo.widthAt(1.05 * vfix);
    final foreheadW = geo.widthAt(-0.55 * vfix);
    final chinLen = geo.chinY * vfix;
    final browThick = (geo.browBottomY - geo.browTopY).abs() * vfix;
    final browGap = (0 - geo.browTopY) * vfix;
    final lipH = (geo.mouthBottom - geo.mouthTop) * vfix;
    final noseLen = geo.noseBottomY * vfix;

    final metrics = FaceMetrics(
      faceWidth: metricRatio(faceW, 2.05, spread: 0.14),
      jawWidth: metricRatio(jawW, 1.72, spread: 0.18),
      chinLength: metricRatio(chinLen, 1.52, spread: 0.14),
      eyeSize: metricRatio(geo.eyeWidth, 0.42, spread: 0.18),
      eyeSpacing: metricRatio(1 / math.max(faceW, 0.5), 0.49, spread: 0.12),
      browHeight: metricRatio(browGap, 0.36, spread: 0.18),
      browThickness: metricRatio(browThick, 0.115, spread: 0.30),
      noseWidth: metricRatio(geo.noseWidth, 0.62, spread: 0.20),
      lipFullness: metricRatio(lipH, 0.47, spread: 0.26),
      mouthWidth: metricRatio(geo.mouthHalf * 2, 0.95, spread: 0.18),
      noseLength: metricRatio(noseLen, 0.80, spread: 0.15),
      smile: 0.2 + 0.8 * (face.smilingProbability ?? 0.2).clamp(0.0, 1.0),
    );

    // ------------------------------------------------------- biçim seçimleri
    final faceShape = pickFaceShape(
      jawOverFace: faceW > 0 ? jawW / faceW : 0,
      foreheadOverFace: faceW > 0 ? foreheadW / faceW : 0,
      lengthOverHalfWidth: faceW > 0 ? chinLen / (faceW / 2) : 0,
    );

    double tiltOf(List<Offset> eye) {
      if (eye.length < 4) return 0;
      final sorted = [...eye]..sort((a, b) => a.dx.abs().compareTo(b.dx.abs()));
      final inner = sorted.first, outer = sorted.last;
      final width = (outer.dx - inner.dx).abs();
      return width <= 0 ? 0 : (inner.dy - outer.dy) / width;
    }

    final eyeIndex = pickEyeStyle(
      aspect: geo.eyeWidth > 0 ? geo.eyeHeight / geo.eyeWidth : 0,
      size: geo.eyeWidth,
      tilt: (tiltOf(geo.eyeA) + tiltOf(geo.eyeB)) / 2,
    );

    double archOf(List<Offset> top) {
      if (top.length < 3) return 0;
      final sorted = [...top]..sort((a, b) => a.dx.compareTo(b.dx));
      final ends = (sorted.first.dy + sorted.last.dy) / 2;
      return (ends - sorted.map((p) => p.dy).reduce(math.min)).abs();
    }

    final browIndex = pickBrowStyle(
      thickness: browThick,
      arch: archOf(toFace(FaceContourType.leftEyebrowTop)),
    );

    final noseLabels = kNoseStyles.map((e) => e.label).toList();
    var noseIndex = 0;
    if (metrics.noseWidth > 1.10) {
      noseIndex = noseLabels.indexOf('Geniş');
    } else if (metrics.noseWidth < 0.90) {
      noseIndex = noseLabels.indexOf('İnce');
    } else if (metrics.noseLength > 1.09) {
      noseIndex = noseLabels.indexOf('Uzun');
    } else if (metrics.noseLength < 0.91) {
      noseIndex = noseLabels.indexOf('Küçük');
    }
    final lipLabels = kLipStyles.map((e) => e.label).toList();
    var lipIndex = 0;
    if ((face.smilingProbability ?? 0) > 0.75) {
      lipIndex = lipLabels.indexOf('Gülümseyen');
    } else if (metrics.lipFullness > 1.14) {
      lipIndex = lipLabels.indexOf('Dolgun');
    } else if (metrics.lipFullness < 0.86) {
      lipIndex = lipLabels.indexOf('İnce');
    } else if (metrics.mouthWidth > 1.10) {
      lipIndex = lipLabels.indexOf('Geniş');
    } else if (metrics.mouthWidth < 0.90) {
      lipIndex = lipLabels.indexOf('Küçük');
    }

    // ---------------------------------------------------- renk ve saç/sakal
    final skinLab = probe.skin;
    final skinTone = skinLab == null ? FaceAvatarConfig.defaultConfig.skinTone : stylizeSkin(skinLab);
    final hairObs = probe.hair;
    final hairRank = rankHairStyles(hairObs);
    final hairIndex = hairRank.first;
    final hairLab = probe.hairColor;
    var hairColor = hairLab == null ? kHairColors[2] : stylizeHair(hairLab);
    final eyeLab = probe.eyeColor;
    final eyeColorIndex = eyeLab == null ? 2 : nearestIndex(eyeLab, kEyeColors);

    final feminine = hairObs.covered || hairObs.length >= 5 || kHairStyles[hairIndex].length == HairLength.pulled;
    final beardLabel = feminine && hairObs.covered ? 'Yok' : pickBeardLabel(probe.beard, strict: feminine);
    final beardIndex = math.max(0, kBeardStyles.indexWhere((b) => b.label == beardLabel));
    final masculine = beardIndex > 0 || (!feminine && hairObs.length <= 3);

    final glassesLabel = probe.glasses;
    final glassesIndex = math.max(0, kGlassesStyles.indexWhere((g) => g.label == glassesLabel));

    // Ruj: dudak tenden belirgin kırmızı/doygunsa.
    var lipColor = 0;
    final lipLab = probe.lipColor;
    if (!masculine && lipLab != null && skinLab != null && lipLab.a - skinLab.a > 16 && lipLab.chroma > skinLab.chroma + 8) {
      lipColor = 1 + nearestIndex(lipLab, kLipColors.sublist(1));
    }

    // Kıyafet / başörtüsü rengi.
    var clothingColor = kClothingColors.first;
    final cover = probe.coverColor;
    final cloth = cover ?? probe.clothing;
    if (cloth != null) clothingColor = kClothingColors[nearestIndex(cloth, kClothingColors)];

    // Gri/gümüş saç: hafif olgun görünüm.
    var age = 0;
    final hairIdx = kHairColors.indexOf(hairColor);
    if (hairIdx == 13 || hairIdx == 14) {
      age = 1;
      hairColor = kHairColors[hairIdx];
    }

    final config = FaceAvatarConfig(
      faceShape: faceShape,
      skinTone: skinTone,
      hair: hairIndex,
      hairColor: hairColor,
      brow: browIndex,
      eye: eyeIndex,
      eyeColor: kEyeColors[eyeColorIndex],
      lash: masculine ? 0 : 1,
      nose: math.max(0, noseIndex),
      lips: math.max(0, lipIndex),
      lipColor: lipColor,
      beard: beardIndex,
      glasses: glassesIndex,
      age: age,
      clothingColor: clothingColor,
      metrics: metrics,
      isSuggested: true,
    );

    // ----------------------------------------------------- ekran için veriler
    final overlay = <List<Offset>>[];
    for (final t in const [
      FaceContourType.face,
      FaceContourType.leftEyebrowTop,
      FaceContourType.rightEyebrowTop,
      FaceContourType.leftEye,
      FaceContourType.rightEye,
      FaceContourType.noseBridge,
      FaceContourType.noseBottom,
      FaceContourType.upperLipTop,
      FaceContourType.lowerLipBottom,
    ]) {
      final pts = _pts(t).map(map).map((p) => Offset(p.dx / px.width, p.dy / px.height)).toList();
      if (pts.isNotEmpty) overlay.add(pts);
    }
    Rect? faceBox;
    if (overlay.isNotEmpty) {
      var r = Rect.fromPoints(overlay.first.first, overlay.first.first);
      for (final p in overlay.first) {
        r = r.expandToInclude(Rect.fromPoints(p, p));
      }
      faceBox = r;
    }

    String? hint;
    final yaw = (face.headEulerAngleY ?? 0).abs();
    if (yaw > 18) {
      hint = 'Başın yana dönük; daha benzer sonuç için kameraya düz bakarak yeniden çek.';
    } else if (skinLab != null && skinLab.l < 28) {
      hint = 'Ortam karanlık; renkler tam ölçülemedi. Işıklı bir yerde yeniden çekebilirsin.';
    } else if (frame.unit < 36) {
      hint = 'Yüzün küçük görünüyor; telefonu biraz yaklaştırırsan ölçüm iyileşir.';
    }

    final hairSpec = kHairStyles[hairIndex];
    final traits = <FaceTrait>[
      FaceTrait('Yüz', kFaceShapes[faceShape].label),
      FaceTrait('Ten', 'Fotoğraftan', swatch: skinTone),
      FaceTrait(hairSpec.covered ? 'Örtü' : 'Saç', hairSpec.label, swatch: hairSpec.covered ? clothingColor : hairColor),
      FaceTrait('Göz', '${kEyeStyles[eyeIndex].label}, ${_eyeColorNames[eyeColorIndex.clamp(0, _eyeColorNames.length - 1)].toLowerCase()}',
          swatch: kEyeColors[eyeColorIndex]),
      FaceTrait('Kaş', kBrowStyles[browIndex].label),
      if (beardIndex > 0) FaceTrait('Sakal', kBeardStyles[beardIndex].label),
      if (glassesIndex > 0) FaceTrait('Gözlük', kGlassesStyles[glassesIndex].label),
      if ((face.smilingProbability ?? 0) > 0.6) const FaceTrait('İfade', 'Gülümseyen'),
    ];

    debugPrint('✅ Yüz analizi: $hairObs ${probe.beard} gözlük=$glassesLabel '
        'şekil=${kFaceShapes[faceShape].label} saç=${hairSpec.label} sakal=$beardLabel ten=$skinLab saçRengi=$hairLab');

    return FaceAnalysis(
      config: config,
      traits: traits,
      hairCandidates: hairRank.take(8).toList(),
      overlay: overlay,
      faceBox: faceBox,
      hint: hint,
      photoSkin: skinTone,
      photoHair: hairColor,
    );
  }
}
