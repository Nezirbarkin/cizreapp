// Selfie'den avatar üretir.
//
// ÖLÇÜLEN (gerçekten fotoğraftan gelir):
//   • yüz ovali konturundan  → yüz şekli (oval/kare/kalp/uzun...), yüz ve çene
//     genişliği, çene uzunluğu
//   • göz konturundan        → göz şekli (badem/iri/çekik/düşük/küçük), göz
//     büyüklüğü ve aralığı
//   • kaş konturundan        → kaş kalınlığı ve kavisi (ince/kalın/düz/yay)
//   • burun ve dudak konturundan → burun genişliği, dudak dolgunluğu, ağız eni
//   • sınıflandırıcıdan      → gülümseme
//   • piksel örneklemesinden → ten tonu, göz rengi, saç rengi, saç uzunluğu
//     (kulak hizasında saç var mı), kellik (tepe ten rengiyle aynı mı),
//     sakal yoğunluğu (çene bölgesi ten tonundan ne kadar koyu)
//
// SEÇİLEMEYEN (kullanıcıya bırakılır): saç modeli detayı, kirpik, gözlük.
//
// Tüm oranlar göz arası mesafeye (IOD) bölünür; böylece kameraya uzaklıktan
// ve fotoğraf çözünürlüğünden bağımsız çalışır.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/face_avatar_config.dart';

class FaceAvatarAnalyzer {
  static Future<FaceAvatarConfig> analyze({
    required String imagePath,
    required Uint8List photoBytes,
  }) async {
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
        return FaceAvatarConfig.defaultConfig.copyWith(isSuggested: true);
      }

      faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
          .compareTo(a.boundingBox.width * a.boundingBox.height));
      final face = faces.first;
      final box = face.boundingBox;

      // ---------------------------------------------------------- piksel
      final codec = await ui.instantiateImageCodec(photoBytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = byteData?.buffer.asUint8List();
      final imgW = image.width;
      final imgH = image.height;
      final coordsMatch = pixels != null &&
          box.left >= -8 &&
          box.top >= -8 &&
          box.right <= imgW + 8 &&
          box.bottom <= imgH + 8;

      Color sampleAt(double x, double y, {int radius = 4}) {
        if (pixels == null) return kSkinTones[2];
        int rSum = 0, gSum = 0, bSum = 0, count = 0;
        final cx = x.round();
        final cy = y.round();
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final px = cx + dx;
            final py = cy + dy;
            if (px < 0 || py < 0 || px >= imgW || py >= imgH) continue;
            final i = (py * imgW + px) * 4;
            rSum += pixels[i];
            gSum += pixels[i + 1];
            bSum += pixels[i + 2];
            count++;
          }
        }
        if (count == 0) return kSkinTones[2];
        return Color.fromARGB(255, rSum ~/ count, gSum ~/ count, bSum ~/ count);
      }

      double colorDist(Color a, Color b) {
        final dr = a.r - b.r;
        final dg = a.g - b.g;
        final db = a.b - b.b;
        return math.sqrt(dr * dr + dg * dg + db * db);
      }

      Color nearest(Color sample, List<Color> palette) {
        var best = palette.first;
        var bestDist = double.infinity;
        for (final c in palette) {
          final d = colorDist(c, sample);
          if (d < bestDist) {
            bestDist = d;
            best = c;
          }
        }
        return best;
      }

      // ---------------------------------------------------------- kontur
      List<math.Point<int>>? contour(FaceContourType type) => face.contours[type]?.points;

      double spanX(List<math.Point<int>>? pts) {
        if (pts == null || pts.isEmpty) return 0;
        var minX = pts.first.x.toDouble(), maxX = minX;
        for (final p in pts) {
          minX = math.min(minX, p.x.toDouble());
          maxX = math.max(maxX, p.x.toDouble());
        }
        return maxX - minX;
      }

      double spanY(List<math.Point<int>>? pts) {
        if (pts == null || pts.isEmpty) return 0;
        var minY = pts.first.y.toDouble(), maxY = minY;
        for (final p in pts) {
          minY = math.min(minY, p.y.toDouble());
          maxY = math.max(maxY, p.y.toDouble());
        }
        return maxY - minY;
      }

      ui.Offset? centerOf(List<math.Point<int>>? pts) {
        if (pts == null || pts.isEmpty) return null;
        var sx = 0.0, sy = 0.0;
        for (final p in pts) {
          sx += p.x;
          sy += p.y;
        }
        return ui.Offset(sx / pts.length, sy / pts.length);
      }

      final leftEyePts = contour(FaceContourType.leftEye);
      final rightEyePts = contour(FaceContourType.rightEye);
      final leftEyeC = centerOf(leftEyePts) ??
          _fromLandmark(face.landmarks[FaceLandmarkType.leftEye]);
      final rightEyeC = centerOf(rightEyePts) ??
          _fromLandmark(face.landmarks[FaceLandmarkType.rightEye]);

      double iod = 0;
      if (leftEyeC != null && rightEyeC != null) {
        iod = math.sqrt(math.pow(leftEyeC.dx - rightEyeC.dx, 2) +
            math.pow(leftEyeC.dy - rightEyeC.dy, 2));
      }
      if (iod < 8) iod = box.width * 0.42;

      final facePts = contour(FaceContourType.face);
      final eyeLineY =
          leftEyeC != null && rightEyeC != null ? (leftEyeC.dy + rightEyeC.dy) / 2 : box.center.dy;

      double widthAt(double y, double band) {
        if (facePts == null || facePts.isEmpty) return 0;
        double? minX, maxX;
        for (final p in facePts) {
          if ((p.y - y).abs() > band) continue;
          final x = p.x.toDouble();
          minX = minX == null ? x : math.min(minX, x);
          maxX = maxX == null ? x : math.max(maxX, x);
        }
        if (minX == null || maxX == null) return 0;
        return maxX - minX;
      }

      final faceW = widthAt(eyeLineY, iod * 0.35);
      final jawW = widthAt(eyeLineY + iod * 1.05, iod * 0.35);
      final foreheadW = widthAt(eyeLineY - iod * 0.55, iod * 0.30);

      double chinY = 0;
      if (facePts != null && facePts.isNotEmpty) {
        chinY = facePts.map((p) => p.y.toDouble()).reduce(math.max);
      }
      final chinLen = chinY > 0 ? chinY - eyeLineY : 0.0;

      final browTopPts = contour(FaceContourType.leftEyebrowTop);
      final browBottomPts = contour(FaceContourType.leftEyebrowBottom);
      double browThick = 0, browGap = 0, browArch = 0;
      if (browTopPts != null && browTopPts.isNotEmpty && browBottomPts != null && browBottomPts.isNotEmpty) {
        final topY = browTopPts.map((p) => p.y.toDouble()).reduce((a, b) => a + b) / browTopPts.length;
        final botY =
            browBottomPts.map((p) => p.y.toDouble()).reduce((a, b) => a + b) / browBottomPts.length;
        browThick = (botY - topY).abs();
        if (leftEyeC != null) browGap = (leftEyeC.dy - topY).abs();

        // kavis: uçların ortalaması ile tepe noktası arasındaki fark
        final sorted = [...browTopPts]..sort((a, b) => a.x.compareTo(b.x));
        final endsY = (sorted.first.y + sorted.last.y) / 2;
        final peakY = sorted.map((p) => p.y).reduce(math.min).toDouble();
        browArch = (endsY - peakY).abs();
      }

      final noseW = spanX(contour(FaceContourType.noseBottom));
      final upperLip = contour(FaceContourType.upperLipTop);
      final lowerLip = contour(FaceContourType.lowerLipBottom);
      double lipHeight = 0;
      if (upperLip != null && upperLip.isNotEmpty && lowerLip != null && lowerLip.isNotEmpty) {
        final topY = upperLip.map((p) => p.y.toDouble()).reduce(math.min);
        final botY = lowerLip.map((p) => p.y.toDouble()).reduce(math.max);
        lipHeight = botY - topY;
      }
      final mouthW = math.max(spanX(upperLip), spanX(lowerLip));
      final eyeW = math.max(spanX(leftEyePts), spanX(rightEyePts));
      final eyeH = math.max(spanY(leftEyePts), spanY(rightEyePts));

      double ratio(double measured, double expected, {double spread = 0.22}) {
        if (measured <= 0 || expected <= 0) return 1.0;
        final r = measured / expected;
        return (1 + (r - 1) * 0.85).clamp(1 - spread, 1 + spread);
      }

      final metrics = FaceMetrics(
        faceWidth: ratio(faceW / iod, 2.05, spread: 0.14),
        jawWidth: ratio(jawW / iod, 1.72, spread: 0.18),
        chinLength: ratio(chinLen / iod, 1.52, spread: 0.14),
        eyeSize: ratio(eyeW / iod, 0.42, spread: 0.20),
        eyeSpacing: ratio(iod / math.max(faceW, 1), 0.49, spread: 0.12),
        browHeight: ratio(browGap / iod, 0.36, spread: 0.18),
        browThickness: ratio(browThick / iod, 0.115, spread: 0.30),
        noseWidth: ratio(noseW / iod, 0.62, spread: 0.20),
        lipFullness: ratio(lipHeight / iod, 0.47, spread: 0.26),
        mouthWidth: ratio(mouthW / iod, 0.95, spread: 0.18),
        smile: (face.smilingProbability ?? 0.35).clamp(0.0, 1.0),
      );

      // ------------------------------------------------------- yüz şekli
      final faceShape = _pickFaceShape(
        jawOverFace: faceW > 0 ? jawW / faceW : 0,
        foreheadOverFace: faceW > 0 ? foreheadW / faceW : 0,
        lengthOverHalfWidth: faceW > 0 ? chinLen / (faceW / 2) : 0,
      );

      // ---------------------------------------------------------- gözler
      final eyeIndex = _pickEyeStyle(
        eyeW: eyeW,
        eyeH: eyeH,
        iod: iod,
        outerHigherBy: _eyeTilt(leftEyePts, isLeftOfFace: true),
      );

      // ------------------------------------------------------------ kaş
      final browIndex = _pickBrowStyle(
        thicknessRatio: iod > 0 ? browThick / iod : 0,
        archRatio: iod > 0 ? browArch / iod : 0,
      );

      // --------------------------------------------------------- renkler
      var skinTone = FaceAvatarConfig.defaultConfig.skinTone;
      var eyeColor = kEyeColors[1];
      var hairColor = kHairColors[1];
      var beardIndex = 0;
      var hairIndex = _indexOfHair('Kısa');

      if (coordsMatch) {
        final leftCheek = face.landmarks[FaceLandmarkType.leftCheek]?.position;
        final rightCheek = face.landmarks[FaceLandmarkType.rightCheek]?.position;
        final Color skinSample;
        if (leftCheek != null && rightCheek != null) {
          final c1 = sampleAt(leftCheek.x.toDouble(), leftCheek.y.toDouble(), radius: 5);
          final c2 = sampleAt(rightCheek.x.toDouble(), rightCheek.y.toDouble(), radius: 5);
          skinSample = Color.lerp(c1, c2, 0.5)!;
        } else {
          skinSample = sampleAt(box.center.dx, box.center.dy + box.height * 0.1, radius: 6);
        }
        skinTone = nearest(skinSample, kSkinTones);

        if (leftEyeC != null) {
          eyeColor = nearest(sampleAt(leftEyeC.dx, leftEyeC.dy, radius: 2), kEyeColors);
        }

        // Tepe: saç mı, ten mi? (kellik tespiti)
        final topY = box.top - box.height * 0.08;
        final topSample = topY > 4
            ? sampleAt(box.center.dx, topY, radius: 6)
            : sampleAt(box.center.dx, box.top + 4, radius: 5);
        final topIsSkin = colorDist(topSample, skinSample) < 0.16;

        if (!topIsSkin) {
          final samples = [
            topSample,
            sampleAt(box.center.dx - box.width * 0.26, topY + box.height * 0.05, radius: 5),
            sampleAt(box.center.dx + box.width * 0.26, topY + box.height * 0.05, radius: 5),
          ];
          samples.sort((a, b) => a.computeLuminance().compareTo(b.computeLuminance()));
          hairColor = nearest(samples.first, kHairColors);
        }

        // Kulak hizasının dışında saç var mı? (uzunluk tespiti)
        var sideHits = 0;
        final sidePoints = <ui.Offset>[
          ui.Offset(box.left - box.width * 0.12, box.center.dy + box.height * 0.18),
          ui.Offset(box.right + box.width * 0.12, box.center.dy + box.height * 0.18),
          ui.Offset(box.left - box.width * 0.10, box.bottom - box.height * 0.02),
          ui.Offset(box.right + box.width * 0.10, box.bottom - box.height * 0.02),
        ];
        for (final p in sidePoints) {
          if (p.dx < 3 || p.dx > imgW - 3 || p.dy < 3 || p.dy > imgH - 3) continue;
          final s = sampleAt(p.dx, p.dy, radius: 5);
          if (colorDist(s, topSample) < 0.18 && colorDist(s, skinSample) > 0.12) {
            sideHits++;
          }
        }

        if (topIsSkin) {
          hairIndex = _indexOfHair('Kel');
        } else if (sideHits >= 3) {
          hairIndex = _indexOfHair('Uzun Düz');
        } else if (sideHits == 2) {
          hairIndex = _indexOfHair('Orta Düz');
        } else {
          hairIndex = _indexOfHair('Kısa');
        }

        // Sakal yoğunluğu
        final noseBase = face.landmarks[FaceLandmarkType.noseBase]?.position;
        if (noseBase != null) {
          final chinSample =
              sampleAt(noseBase.x.toDouble(), noseBase.y + box.height * 0.26, radius: 6);
          final delta = skinSample.computeLuminance() - chinSample.computeLuminance();
          if (delta > 0.24) {
            beardIndex = _indexOfBeard('Tam Sakal');
          } else if (delta > 0.16) {
            beardIndex = _indexOfBeard('Kısa Sakal');
          } else if (delta > 0.11) {
            beardIndex = _indexOfBeard('Üç Günlük');
          } else if (delta > 0.07) {
            beardIndex = _indexOfBeard('Hafif');
          }
        }
      }

      debugPrint(
        '✅ Yüz analizi: şekil=${kFaceShapes[faceShape].label} '
        'göz=${kEyeStyles[eyeIndex].label} kaş=${kBrowStyles[browIndex].label} '
        'saç=${kHairStyles[hairIndex].label} sakal=${kBeardStyles[beardIndex].label} '
        'gülümseme=${metrics.smile.toStringAsFixed(2)}',
      );

      return FaceAvatarConfig(
        faceShape: faceShape,
        skinTone: skinTone,
        hair: hairIndex,
        hairColor: hairColor,
        brow: browIndex,
        eye: eyeIndex,
        eyeColor: eyeColor,
        lash: 1,
        beard: beardIndex,
        glasses: 0,
        clothingColor: kClothingColors.first,
        metrics: metrics,
        isSuggested: true,
      );
    } catch (e) {
      debugPrint('❌ Yüz analizi başarısız, varsayılan öneriyle devam ediliyor: $e');
      return FaceAvatarConfig.defaultConfig.copyWith(isSuggested: true);
    } finally {
      await detector?.close();
    }
  }

  // ------------------------------------------------------------- seçiciler

  /// Ölçülen oranları katalogdaki 8 yüz şeklinin oranlarıyla karşılaştırıp
  /// en yakınını seçer. Karşılaştırma, her iki tarafı da kendi "oval"
  /// referansına bölerek yapılır; böylece fotoğraf ile çizim arasındaki
  /// ölçüm farkı sonucu bozmaz.
  static int _pickFaceShape({
    required double jawOverFace,
    required double foreheadOverFace,
    required double lengthOverHalfWidth,
  }) {
    if (jawOverFace <= 0 || foreheadOverFace <= 0 || lengthOverHalfWidth <= 0) return 0;

    // Fotoğraflardaki ortalama değerler (referans).
    const avgJaw = 0.84;
    const avgForehead = 0.93;
    const avgLength = 1.50;

    double specJaw(FaceShapeSpec s) => (37 * s.jaw) / (45 * s.cheek);
    double specForehead(FaceShapeSpec s) => (41.5 * s.forehead) / (45 * s.cheek);
    double specLength(FaceShapeSpec s) => (50 * s.chin - 1) / (45 * s.cheek);

    final oval = kFaceShapes.first;
    final refJaw = specJaw(oval);
    final refForehead = specForehead(oval);
    final refLength = specLength(oval);

    final mJaw = jawOverFace / avgJaw;
    final mForehead = foreheadOverFace / avgForehead;
    final mLength = lengthOverHalfWidth / avgLength;

    var best = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < kFaceShapes.length; i++) {
      final s = kFaceShapes[i];
      final dJaw = (specJaw(s) / refJaw) - mJaw;
      final dFore = (specForehead(s) / refForehead) - mForehead;
      final dLen = (specLength(s) / refLength) - mLength;
      final score = dJaw * dJaw * 1.6 + dFore * dFore * 1.2 + dLen * dLen;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  /// Göz konturunun dış köşesi iç köşesine göre ne kadar yukarıda
  /// (pozitif = çekik, negatif = düşük). Göz genişliğine oranlanır.
  static double _eyeTilt(List<math.Point<int>>? pts, {required bool isLeftOfFace}) {
    if (pts == null || pts.length < 4) return 0;
    final sorted = [...pts]..sort((a, b) => a.x.compareTo(b.x));
    final leftMost = sorted.first;
    final rightMost = sorted.last;
    final width = (rightMost.x - leftMost.x).toDouble();
    if (width <= 0) return 0;
    // ML Kit'in "leftEye"ı görüntünün solundadır → dış köşe soldadır.
    final outer = isLeftOfFace ? leftMost : rightMost;
    final inner = isLeftOfFace ? rightMost : leftMost;
    return (inner.y - outer.y) / width;
  }

  static int _pickEyeStyle({
    required double eyeW,
    required double eyeH,
    required double iod,
    required double outerHigherBy,
  }) {
    if (eyeW <= 0 || eyeH <= 0 || iod <= 0) return 0;

    if (outerHigherBy > 0.10) return _indexOfEye('Çekik');
    if (outerHigherBy < -0.10) return _indexOfEye('Düşük');

    final aspect = eyeH / eyeW;
    final size = eyeW / iod;

    if (aspect < 0.30) return _indexOfEye('Uykulu');
    if (aspect < 0.36) return _indexOfEye('Badem');
    if (aspect > 0.52) return _indexOfEye(size > 0.44 ? 'İri' : 'Yuvarlak');
    if (size < 0.37) return _indexOfEye('Küçük');
    return _indexOfEye('Normal');
  }

  static int _pickBrowStyle({required double thicknessRatio, required double archRatio}) {
    if (thicknessRatio <= 0) return _indexOfBrow('Doğal');
    if (thicknessRatio > 0.185) return _indexOfBrow('Çok Kalın');
    if (thicknessRatio > 0.150) return _indexOfBrow('Kalın');
    if (thicknessRatio < 0.085) return _indexOfBrow('İnce');
    if (archRatio > 0.10) return _indexOfBrow('Yay');
    if (archRatio < 0.03) return _indexOfBrow('Düz');
    return _indexOfBrow('Doğal');
  }

  static int _indexOfHair(String label) {
    final i = kHairStyles.indexWhere((s) => s.label == label);
    return i < 0 ? 3 : i;
  }

  static int _indexOfBrow(String label) {
    final i = kBrowStyles.indexWhere((s) => s.label == label);
    return i < 0 ? 1 : i;
  }

  static int _indexOfEye(String label) {
    final i = kEyeStyles.indexWhere((s) => s.label == label);
    return i < 0 ? 0 : i;
  }

  static int _indexOfBeard(String label) {
    final i = kBeardStyles.indexWhere((s) => s.label == label);
    return i < 0 ? 0 : i;
  }

  static ui.Offset? _fromLandmark(FaceLandmark? landmark) {
    if (landmark == null) return null;
    return ui.Offset(landmark.position.x.toDouble(), landmark.position.y.toDouble());
  }
}
