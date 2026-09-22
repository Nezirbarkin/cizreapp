// Avatar çizim motoru: FaceAvatarConfig'teki parametrik tarifleri (spec)
// yarı-gerçekçi bir portreye çevirir.
//
// Görsel varlık (PNG/SVG) yoktur; her şey Canvas'ta gradyan, yumuşak gölge,
// bezier eğrileri ve tek tek çizilen kıl/tel katmanlarıyla üretilir. Bu yüzden
// katalog büyütmek (yeni saç/kaş/göz stili) dosya eklemek değil, tek satır
// spec eklemek demektir.
//
// Parçalar (`part`) tek kitaplığı paylaşır, böylece ortak geometri/renk
// (`_Rig`) ve yardımcılar her yerden kullanılabilir:
//   face_avatar/rig.dart       geometri, renk paleti, çizim yardımcıları
//   face_avatar/body.dart      arka plan, boyun/omuz, kıyafetler
//   face_avatar/skin.dart      kafa, kulak, cilt gölgeleri, çil/ben, yaş çizgileri
//   face_avatar/features.dart  kaş, göz, burun, dudak
//   face_avatar/hair.dart      saç (arka + ön), kapalı saç/başörtüsü
//   face_avatar/beard.dart     sakal, bıyık, favori
//   face_avatar/wear.dart      gözlük, başlık, takı
//
// Kalite: `detailed: false` küçük önizlemeler içindir (bulanıklık, tel tel
// saç/kıl ve doku katmanları atlanır).
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/face_avatar_config.dart';

part 'face_avatar/rig.dart';
part 'face_avatar/body.dart';
part 'face_avatar/skin.dart';
part 'face_avatar/features.dart';
part 'face_avatar/hair.dart';
part 'face_avatar/hair_ties.dart';
part 'face_avatar/beard.dart';
part 'face_avatar/wear.dart';

class FaceAvatarPainter extends CustomPainter {
  final FaceAvatarConfig config;
  final Color? background;

  /// Küçük önizlemelerde bulanıklık/tel katmanları atlanır.
  final bool detailed;

  /// Arka planı hiç çizme (şeffaf PNG / üst üste bindirme için).
  final bool transparent;

  /// Küçük önizlemede belirli bir bölgeye yakınlaşmak için (örn. gözler).
  /// [focus] 200x200 tuval koordinatındadır.
  final Offset? focus;
  final double zoom;

  /// Hareketli avatar kareleri için: göz kırpma (0 açık, 1 kapalı), hafif
  /// sallanma (radyan) ve nefes alma (y kayması, birim).
  final double blink;
  final double sway;
  final double bob;

  FaceAvatarPainter(
    this.config, {
    this.background,
    this.detailed = true,
    this.transparent = false,
    this.focus,
    this.zoom = 1.0,
    this.blink = 0.0,
    this.sway = 0.0,
    this.bob = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 200, 200));

    final rig = _Rig(config, detailed: detailed, background: background, blink: blink);

    if (!transparent) _paintBackground(canvas, rig);

    // Yakınlaştırma: arka plan tüm kareyi kaplar, geri kalanı odağa büyütülür.
    if (focus != null && zoom != 1.0) {
      canvas.translate(100, 100);
      canvas.scale(zoom);
      canvas.translate(-focus!.dx, -focus!.dy);
    }

    // Hafif sallanma + nefes: arka plan sabit kalır, portre boyundan kıpırdar.
    if (sway != 0.0 || bob != 0.0) {
      canvas.translate(100, 170);
      canvas.rotate(sway);
      canvas.translate(-100, -170 + bob);
    }

    _paintHeadwearBack(canvas, rig);
    _paintHairBack(canvas, rig);
    _paintTorso(canvas, rig);
    _paintClothing(canvas, rig);
    _paintEars(canvas, rig);
    _paintHead(canvas, rig);
    _paintFaceShading(canvas, rig);
    _paintBrows(canvas, rig);
    _paintEyes(canvas, rig);
    _paintNose(canvas, rig);
    _paintMouth(canvas, rig);
    _paintFaceDetails(canvas, rig);
    _paintBeard(canvas, rig);
    _paintJewelry(canvas, rig);
    _paintHairFront(canvas, rig);
    _paintHeadwearFront(canvas, rig);
    _paintGlasses(canvas, rig);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FaceAvatarPainter oldDelegate) =>
      oldDelegate.config != config ||
      oldDelegate.background != background ||
      oldDelegate.detailed != detailed ||
      oldDelegate.transparent != transparent ||
      oldDelegate.focus != focus ||
      oldDelegate.zoom != zoom ||
      oldDelegate.blink != blink ||
      oldDelegate.sway != sway ||
      oldDelegate.bob != bob;
}

/// Canlı önizleme: yuvarlak çerçeve içinde avatar.
class FaceAvatarPreview extends StatelessWidget {
  final FaceAvatarConfig config;
  final double size;
  final bool detailed;
  final Color? background;

  const FaceAvatarPreview({
    super.key,
    required this.config,
    this.size = 170,
    this.detailed = true,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: size * 0.18,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: ClipOval(
        child: CustomPaint(
          painter: FaceAvatarPainter(config, detailed: detailed, background: background),
          size: Size(size, size),
        ),
      ),
    );
  }
}

/// Avatarı [size]x[size] PNG baytlarına çizer (yükleme için).
Future<Uint8List> renderFaceAvatarToPng(FaceAvatarConfig config, {int size = 768}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  FaceAvatarPainter(config).paint(canvas, Size(size.toDouble(), size.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    throw Exception('Avatar PNG olarak kodlanamadı');
  }
  return byteData.buffer.asUint8List();
}
