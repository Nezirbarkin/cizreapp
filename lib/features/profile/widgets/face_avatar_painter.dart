// Avatar çizim motoru: FaceAvatarConfig'teki parametrik tarifleri (spec)
// hacimli bir portreye çevirir.
//
// Görsel varlık (PNG/SVG) yoktur; her şey Canvas'ta gradyan, yumuşak gölge ve
// bezier eğrileriyle üretilir. Bu yüzden katalog büyütmek (yeni saç/kaş/göz
// stili) dosya eklemek değil, tek satır spec eklemek demektir.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/face_avatar_config.dart';

class FaceAvatarPainter extends CustomPainter {
  final FaceAvatarConfig config;
  final Color? background;

  /// Küçük önizlemelerde bulanıklık/gradyan katmanları atlanır.
  final bool detailed;

  FaceAvatarPainter(this.config, {this.background, this.detailed = true});

  FaceMetrics get _m => config.metrics;
  FaceShapeSpec get _shape => config.faceShapeSpec;
  HairSpec get _hairSpec => config.hairSpec;
  BrowSpec get _browSpec => config.browSpec;
  EyeSpec get _eyeSpec => config.eyeSpec;
  LashSpec get _lashSpec => config.lashSpec;
  BeardSpec get _beardSpec => config.beardSpec;
  GlassesSpec get _glassesSpec => config.glassesSpec;

  // ---------------------------------------------------------------- renkler
  Color get _skin => config.skinTone;
  Color get _skinShadow => Color.lerp(_skin, const Color(0xFF7A3F22), 0.36)!;
  Color get _skinDeep => Color.lerp(_skin, const Color(0xFF4A2412), 0.55)!;
  Color get _skinLight => Color.lerp(_skin, Colors.white, 0.30)!;
  Color get _blush => Color.lerp(_skin, const Color(0xFFD9584F), 0.55)!;
  Color get _hair => config.hairColor;
  Color get _hairLight => Color.lerp(_hair, Colors.white, 0.30)!;
  Color get _hairDark => Color.lerp(_hair, Colors.black, 0.40)!;
  Color get _lip => Color.lerp(_skin, const Color(0xFFB04E4C), 0.52)!;
  Color get _lipDark => Color.lerp(_lip, Colors.black, 0.32)!;
  Color get _lipLight => Color.lerp(_lip, Colors.white, 0.35)!;
  Color get _lashColor => Color.lerp(_hairDark, const Color(0xFF1A120E), 0.55)!;

  /// Çok açık saç renklerinde kaş kaybolmasın diye koyulaştırılır.
  Color get _browColor =>
      Color.lerp(_hair, const Color(0xFF3A2A20), 0.12 + 0.45 * _hair.computeLuminance())!;

  // --------------------------------------------------------------- ölçüler
  static const double _cx = 100;
  static const double _headTop = 40;
  static const double _eyeY = 97;
  static const double _noseTipY = 114;

  double get _foreheadHalf => 41.5 * _shape.forehead * _m.faceWidth;
  double get _cheekHalf => 45.0 * _shape.cheek * _m.faceWidth;
  double get _jawHalf => 37.0 * _shape.jaw * _m.jawWidth;
  double get _chinY => 96 + 50 * _shape.chin * _m.chinLength;
  double get _eyeDx => 19.5 * _m.eyeSpacing;
  double get _browY => 79 - (_m.browHeight - 1) * 10;
  double get _noseHalf => 6.4 * _m.noseWidth;
  double get _mouthY => 130;
  double get _mouthHalf => 18.5 * _m.mouthWidth;
  double get _eyeW => 11.6 * _m.eyeSize * _eyeSpec.width;
  double get _eyeH => 7.4 * _m.eyeSize * _eyeSpec.height;

  // -------------------------------------------------------------- yardımcı
  Paint _soft(Color color, double sigma) {
    final p = Paint()..color = color;
    if (detailed && sigma > 0) {
      p.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    }
    return p;
  }

  void _mirrored(Canvas canvas, void Function(Canvas canvas) drawLeft) {
    drawLeft(canvas);
    canvas.save();
    canvas.translate(200, 0);
    canvas.scale(-1, 1);
    drawLeft(canvas);
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 200, size.height / 200);
    canvas.clipRect(const Rect.fromLTWH(0, 0, 200, 200));

    _paintBackground(canvas);
    _paintHairBack(canvas);
    _paintNeck(canvas);
    _paintBody(canvas);
    _paintEars(canvas);
    _paintHead(canvas);
    _paintBrows(canvas);
    _paintEyes(canvas);
    _paintNose(canvas);
    _paintMouth(canvas);
    _paintBeard(canvas);
    _paintHairFront(canvas);
    _paintGlasses(canvas);

    canvas.restore();
  }

  // ------------------------------------------------------------------ arka
  void _paintBackground(Canvas canvas) {
    const rect = Rect.fromLTWH(0, 0, 200, 200);
    if (background != null) {
      canvas.drawRect(rect, Paint()..color = background!);
    } else {
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(0, 0),
            const Offset(0, 200),
            const [Color(0xFFF4F6F9), Color(0xFFE4E8EF)],
          ),
      );
    }
    if (detailed) {
      canvas.drawCircle(
        const Offset(100, 78),
        84,
        Paint()
          ..shader = ui.Gradient.radial(
            const Offset(92, 62),
            96,
            [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0.0)],
          ),
      );
    }
  }

  // ------------------------------------------------------------ boyun/omuz
  void _paintNeck(Canvas canvas) {
    final neck = Path()
      ..moveTo(_cx - 14, 118)
      ..cubicTo(_cx - 15, 140, _cx - 17, 152, _cx - 20, 166)
      ..lineTo(_cx + 20, 166)
      ..cubicTo(_cx + 17, 152, _cx + 15, 140, _cx + 14, 118)
      ..close();
    canvas.drawPath(neck, Paint()..color = Color.lerp(_skin, _skinShadow, 0.35)!);

    if (detailed) {
      canvas.save();
      canvas.clipPath(neck);
      canvas.drawCircle(Offset(_cx, _chinY - 4), 26, _soft(_skinDeep.withValues(alpha: 0.55), 8));
      canvas.restore();
    }
  }

  void _paintBody(Canvas canvas) {
    final cloth = config.clothingColor;
    final body = Path()
      ..moveTo(10, 200)
      ..cubicTo(12, 180, 34, 168, 62, 162)
      ..cubicTo(78, 158, 86, 157, 100, 157)
      ..cubicTo(114, 157, 122, 158, 138, 162)
      ..cubicTo(166, 168, 188, 180, 190, 200)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 155),
          const Offset(0, 200),
          [Color.lerp(cloth, Colors.white, 0.10)!, cloth],
        ),
    );

    final collar = Path()
      ..moveTo(_cx - 21, 160)
      ..quadraticBezierTo(_cx, 182, _cx + 21, 160)
      ..quadraticBezierTo(_cx, 172, _cx - 21, 160)
      ..close();
    canvas.drawPath(collar, Paint()..color = Color.lerp(cloth, Colors.black, 0.28)!);

    if (detailed) {
      canvas.save();
      canvas.clipPath(body);
      canvas.drawCircle(Offset(_cx, 164), 30, _soft(Colors.black.withValues(alpha: 0.22), 10));
      canvas.restore();
    }
  }

  // ------------------------------------------------------------------ kulak
  void _paintEars(Canvas canvas) {
    _mirrored(canvas, (c) {
      final center = Offset(_cx - _cheekHalf + 1, _eyeY + 6);
      c.drawOval(
        Rect.fromCenter(center: center, width: 13, height: 20),
        Paint()..color = Color.lerp(_skin, _skinShadow, 0.18)!,
      );
      c.drawOval(
        Rect.fromCenter(center: center.translate(1.5, 0), width: 6, height: 11),
        Paint()..color = _skinShadow.withValues(alpha: 0.55),
      );
    });
  }

  // -------------------------------------------------------------------- yüz
  Path _headPath() {
    final chinY = _chinY;
    final fw = _foreheadHalf;
    final cw = _cheekHalf;
    final jw = _jawHalf;
    final k = _shape.corner; // 0 yuvarlak → 1 kare

    return Path()
      ..moveTo(_cx, _headTop)
      ..cubicTo(_cx + fw * 0.62, _headTop + 0.5, _cx + fw, 56, _cx + cw, 85)
      ..cubicTo(
        _cx + cw + 1.5,
        104 - 4 * k,
        _cx + jw + 3.5 * (1 - k) + 5 * k,
        114 - 3 * k,
        _cx + jw * (0.78 + 0.15 * k),
        131 - 5 * k,
      )
      ..cubicTo(
        _cx + jw * (0.52 + 0.22 * k),
        chinY - 8 + 3 * k,
        _cx + 13 * (1 - 0.35 * k),
        chinY,
        _cx,
        chinY,
      )
      ..cubicTo(
        _cx - 13 * (1 - 0.35 * k),
        chinY,
        _cx - jw * (0.52 + 0.22 * k),
        chinY - 8 + 3 * k,
        _cx - jw * (0.78 + 0.15 * k),
        131 - 5 * k,
      )
      ..cubicTo(
        _cx - jw - 3.5 * (1 - k) - 5 * k,
        114 - 3 * k,
        _cx - cw - 1.5,
        104 - 4 * k,
        _cx - cw,
        85,
      )
      ..cubicTo(_cx - fw, 56, _cx - fw * 0.62, _headTop + 0.5, _cx, _headTop)
      ..close();
  }

  void _paintHead(Canvas canvas) {
    final head = _headPath();
    canvas.drawPath(head, Paint()..color = _skin);
    if (!detailed) return;

    canvas.save();
    canvas.clipPath(head);
    final bounds = head.getBounds().inflate(6);

    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(_cx - 20, 62),
          82,
          [_skinLight.withValues(alpha: 0.85), _skinLight.withValues(alpha: 0.0)],
        ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(_cx + 40, _chinY - 6),
          74,
          [_skinShadow.withValues(alpha: 0.50), _skinShadow.withValues(alpha: 0.0)],
        ),
    );
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(_cx - _cheekHalf, 0),
          Offset(_cx + _cheekHalf, 0),
          [
            _skinShadow.withValues(alpha: 0.38),
            _skinShadow.withValues(alpha: 0.0),
            _skinShadow.withValues(alpha: 0.0),
            _skinShadow.withValues(alpha: 0.30),
          ],
          const [0.0, 0.22, 0.78, 1.0],
        ),
    );

    _mirrored(canvas, (c) {
      c.drawCircle(
        Offset(_cx - _cheekHalf * 0.60, _eyeY + 16),
        14,
        _soft(_blush.withValues(alpha: 0.22), 9),
      );
    });

    canvas.drawCircle(Offset(_cx - 6, 60), 20, _soft(_skinLight.withValues(alpha: 0.35), 10));
    canvas.drawCircle(Offset(_cx, _chinY + 2), 18, _soft(_skinShadow.withValues(alpha: 0.40), 9));

    canvas.restore();
  }

  // ------------------------------------------------------------------ kaşlar
  void _paintBrows(Canvas canvas) {
    final spec = _browSpec;
    final th = _m.browThickness * spec.thickness;
    final arch = spec.arch;

    _mirrored(canvas, (c) {
      final innerX = _cx - (_eyeDx - 9) * spec.length;
      final outerX = _cx - (_eyeDx + 13.5) * spec.length;
      final y = _browY;
      final lift = 5.0 * arch;
      final tilt = spec.tilt;
      final tip = 0.9 * th / spec.taper;

      final brow = Path()
        ..moveTo(outerX, y + 3.2 + tilt)
        ..cubicTo(outerX + 5, y - lift * 0.45 + tilt, innerX - 9, y - lift, innerX, y - lift * 0.35 - tilt)
        ..lineTo(innerX, y - lift * 0.35 - tilt + 3.0 * th)
        ..cubicTo(
          innerX - 9,
          y - lift + 3.4 * th,
          outerX + 5,
          y - lift * 0.45 + tilt + 2.6 * th,
          outerX,
          y + 3.2 + tilt + tip,
        )
        ..close();

      c.drawPath(brow, Paint()..color = _browColor);
      if (detailed) {
        c.drawPath(brow, _soft(_browColor.withValues(alpha: 0.35), 1.6));
      }
    });
  }

  // ------------------------------------------------------------------ gözler
  Path _eyeShape(Offset c, double w, double h) => Path()
    ..moveTo(c.dx - w, c.dy + 0.5)
    ..quadraticBezierTo(c.dx - w * 0.48, c.dy - h * 1.08, c.dx + w * 0.06, c.dy - h * 0.96)
    ..quadraticBezierTo(c.dx + w * 0.62, c.dy - h * 0.82, c.dx + w, c.dy - h * 0.02)
    ..quadraticBezierTo(c.dx + w * 0.55, c.dy + h * 0.88, c.dx - w * 0.02, c.dy + h * 0.98)
    ..quadraticBezierTo(c.dx - w * 0.58, c.dy + h * 0.94, c.dx - w, c.dy + 0.5)
    ..close();

  void _paintEyes(Canvas canvas) {
    _mirrored(canvas, (c) {
      final center = Offset(_cx - _eyeDx, _eyeY);
      final tilt = _eyeSpec.tilt;
      if (tilt != 0) {
        c.save();
        c.translate(center.dx, center.dy);
        c.rotate(tilt * 0.035);
        c.translate(-center.dx, -center.dy);
      }
      _drawEye(c, center);
      if (tilt != 0) c.restore();
    });
  }

  void _drawEye(Canvas canvas, Offset center) {
    final w = _eyeW;
    final h = _eyeH;

    if (_eyeSpec.closed) {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - w, center.dy + h * 0.5)
          ..quadraticBezierTo(center.dx, center.dy - h * 1.5, center.dx + w, center.dy + h * 0.4),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF241813),
      );
      _drawLashes(canvas, center, w, h);
      return;
    }

    final shape = _eyeShape(center, w, h);

    if (detailed) {
      canvas.drawPath(
        _eyeShape(center.translate(0, -1.8), w * 1.2, h * 1.5),
        _soft(_skinShadow.withValues(alpha: 0.30), 3.5),
      );
    }

    canvas.drawPath(shape, Paint()..color = const Color(0xFFF8F6F4));

    canvas.save();
    canvas.clipPath(shape);

    if (detailed) {
      canvas.drawRect(
        Rect.fromCenter(center: center, width: w * 3, height: h * 3),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(center.dx, center.dy - h),
            Offset(center.dx, center.dy + h),
            const [Color(0x45000000), Color(0x00000000), Color(0x18000000)],
            const [0.0, 0.48, 1.0],
          ),
      );
    }

    final irisR = h * 1.18;
    final irisC = Offset(center.dx + 0.6, center.dy + 0.4);
    canvas.drawCircle(
      irisC,
      irisR,
      Paint()
        ..shader = ui.Gradient.radial(
          irisC.translate(-irisR * 0.28, -irisR * 0.32),
          irisR * 1.35,
          [
            Color.lerp(config.eyeColor, Colors.white, 0.42)!,
            config.eyeColor,
            Color.lerp(config.eyeColor, Colors.black, 0.45)!,
          ],
          const [0.0, 0.58, 1.0],
        ),
    );
    canvas.drawCircle(
      irisC,
      irisR - 0.4,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.lerp(config.eyeColor, Colors.black, 0.62)!.withValues(alpha: 0.85),
    );
    canvas.drawCircle(irisC, irisR * 0.44, Paint()..color = const Color(0xFF130F0D));
    canvas.drawCircle(
      irisC.translate(-irisR * 0.36, -irisR * 0.40),
      irisR * 0.27,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    canvas.drawCircle(
      irisC.translate(irisR * 0.34, irisR * 0.34),
      irisR * 0.13,
      Paint()..color = Colors.white.withValues(alpha: 0.50),
    );

    if (_eyeSpec.hooded) {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - w - 1, center.dy - h * 1.2)
          ..quadraticBezierTo(center.dx, center.dy - h * 0.10, center.dx + w + 1, center.dy - h * 0.95)
          ..lineTo(center.dx + w + 1, center.dy - h * 2.2)
          ..lineTo(center.dx - w - 1, center.dy - h * 2.2)
          ..close(),
        Paint()..color = Color.lerp(_skin, _skinShadow, 0.35)!,
      );
    }

    canvas.restore();

    canvas.drawPath(
      Path()
        ..moveTo(center.dx - w, center.dy + 0.5)
        ..quadraticBezierTo(center.dx - w * 0.48, center.dy - h * 1.16, center.dx + w * 0.06, center.dy - h * 1.02)
        ..quadraticBezierTo(center.dx + w * 0.62, center.dy - h * 0.88, center.dx + w, center.dy - h * 0.02),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF231713),
    );

    canvas.drawPath(
      Path()
        ..moveTo(center.dx - w * 0.82, center.dy + h * 0.92)
        ..quadraticBezierTo(center.dx, center.dy + h * 1.35, center.dx + w * 0.86, center.dy + h * 0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeCap = StrokeCap.round
        ..color = _skinShadow.withValues(alpha: 0.55),
    );

    _drawLashes(canvas, center, w, h);
  }

  /// Kirpikler: üst kapağın dışına doğru incelen kısa çizgiler.
  void _drawLashes(Canvas canvas, Offset center, double w, double h) {
    final spec = _lashSpec;
    if (spec.length <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = _lashColor;

    const count = 4;
    for (var i = 0; i < count; i++) {
      final t = 0.12 + i * 0.24;
      final x = center.dx - w + (w * 2) * t;
      final y = center.dy - h * (0.95 + 0.12 * math.sin(t * math.pi));
      final len = (1.7 + 2.0 * spec.length) * (1.25 - t * 0.6);
      final lean = -1.8 + t * 1.0;
      paint.strokeWidth = 1.15 * spec.thickness * (1.15 - t * 0.35);
      canvas.drawLine(Offset(x, y), Offset(x + lean, y - len), paint);
    }

    if (spec.winged) {
      canvas.drawPath(
        Path()
          ..moveTo(center.dx - w * 0.75, center.dy - h * 0.55)
          ..quadraticBezierTo(
            center.dx - w * 1.05,
            center.dy - h * 1.0,
            center.dx - w * 1.5,
            center.dy - h * 1.9,
          ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.0 * spec.thickness
          ..color = _lashColor,
      );
    }

    if (spec.lower) {
      paint.strokeWidth = 0.8 * spec.thickness;
      for (var i = 0; i < 3; i++) {
        final t = 0.28 + i * 0.22;
        final x = center.dx - w + (w * 2) * t;
        final y = center.dy + h * (0.95 + 0.1 * math.sin(t * math.pi));
        canvas.drawLine(Offset(x, y), Offset(x - 0.4, y + 1.4 + spec.length * 0.8), paint);
      }
    }
  }

  // ------------------------------------------------------------- burun/ağız
  void _paintNose(Canvas canvas) {
    final w = _noseHalf;

    if (detailed) {
      canvas.drawPath(
        Path()
          ..moveTo(_cx - 2.5, _eyeY + 6)
          ..quadraticBezierTo(_cx - w * 0.9, _noseTipY - 8, _cx - w * 0.95, _noseTipY)
          ..quadraticBezierTo(_cx - w * 0.5, _noseTipY + 4, _cx - 1, _noseTipY + 2)
          ..close(),
        _soft(_skinShadow.withValues(alpha: 0.42), 3),
      );
      canvas.drawCircle(
        Offset(_cx + 1, _noseTipY - 3),
        5.5,
        _soft(_skinLight.withValues(alpha: 0.60), 4),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, _noseTipY + 4.5), width: w * 2.5, height: 5),
        _soft(_skinShadow.withValues(alpha: 0.45), 3),
      );
    }

    _mirrored(canvas, (c) {
      c.save();
      c.translate(_cx - w * 0.62, _noseTipY + 1.6);
      c.rotate(-0.35);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 4.4, height: 2.8),
        Paint()..color = _skinDeep.withValues(alpha: 0.80),
      );
      c.restore();
    });
  }

  void _paintMouth(Canvas canvas) {
    final w = _mouthHalf;
    final y = _mouthY;
    final lift = 5.0 * _m.smile;
    final lower = 6.6 * _m.lipFullness;
    final upper = 3.6 * _m.lipFullness;

    final upperLip = Path()
      ..moveTo(_cx - w, y - lift * 0.5)
      ..quadraticBezierTo(_cx - w * 0.55, y - upper - 1.2, _cx - w * 0.18, y - upper * 0.55)
      ..quadraticBezierTo(_cx, y - upper * 0.15, _cx + w * 0.18, y - upper * 0.55)
      ..quadraticBezierTo(_cx + w * 0.55, y - upper - 1.2, _cx + w, y - lift * 0.5)
      ..quadraticBezierTo(_cx, y + 1.2, _cx - w, y - lift * 0.5)
      ..close();

    final lowerLip = Path()
      ..moveTo(_cx - w, y - lift * 0.5)
      ..quadraticBezierTo(_cx, y + 1.0, _cx + w, y - lift * 0.5)
      ..quadraticBezierTo(_cx + w * 0.55, y + lower + lift * 0.4, _cx, y + lower + 1 + lift * 0.5)
      ..quadraticBezierTo(_cx - w * 0.55, y + lower + lift * 0.4, _cx - w, y - lift * 0.5)
      ..close();

    canvas.drawPath(lowerLip, Paint()..color = _lip);
    canvas.drawPath(upperLip, Paint()..color = _lipDark);

    if (detailed) {
      canvas.save();
      canvas.clipPath(lowerLip);
      canvas.drawRect(
        Rect.fromLTWH(_cx - w - 4, y - 4, w * 2 + 8, lower + 12),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(_cx, y),
            Offset(_cx, y + lower + 2),
            [_lipDark.withValues(alpha: 0.55), _lip.withValues(alpha: 0.0)],
          ),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx - 1, y + lower * 0.55), width: w * 0.9, height: 3.4),
        _soft(_lipLight.withValues(alpha: 0.75), 2.5),
      );
      canvas.restore();

      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, y + lower + 5), width: w * 1.5, height: 4),
        _soft(_skinShadow.withValues(alpha: 0.35), 3),
      );
    }

    canvas.drawPath(
      Path()
        ..moveTo(_cx - w, y - lift * 0.5)
        ..quadraticBezierTo(_cx, y + 1.4, _cx + w, y - lift * 0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(_lipDark, Colors.black, 0.35)!.withValues(alpha: 0.75),
    );
  }

  // ------------------------------------------------------------------ sakal
  Path _mustachePath(BeardSpec spec) {
    final w = _mouthHalf * spec.mustacheWidth;
    final y = _mouthY - 6.5;
    final t = spec.mustacheThickness;
    return Path()
      ..moveTo(_cx - w * 1.08, y - 1.5 * t)
      ..quadraticBezierTo(_cx - w * 0.48, y - 5.2 * t, _cx, y - 2.4 * t)
      ..quadraticBezierTo(_cx + w * 0.48, y - 5.2 * t, _cx + w * 1.08, y - 1.5 * t)
      ..quadraticBezierTo(_cx + w * 0.58, y + 3.4 * t, _cx, y + 1.2 * t)
      ..quadraticBezierTo(_cx - w * 0.58, y + 3.4 * t, _cx - w * 1.08, y - 1.5 * t)
      ..close();
  }

  /// Çene hattını saran bant; üst kenarı ortada ağzın altına iner.
  Path _beardPath(double coverage) {
    final jw = _jawHalf;
    final chinY = _chinY;
    final c = coverage.clamp(0.0, 1.0);
    final sideTop = _eyeY + 24 - 16 * c;
    final midY = _mouthY + 7 - 3 * c;
    final drop = coverage > 1 ? (coverage - 1) * 26 : 0.0;
    return Path()
      ..moveTo(_cx - jw - 6, sideTop)
      ..cubicTo(_cx - jw - 6, chinY - 16 + drop, _cx - jw * 0.62, chinY + 5 + drop, _cx, chinY + 5 + drop)
      ..cubicTo(_cx + jw * 0.62, chinY + 5 + drop, _cx + jw + 6, chinY - 16 + drop, _cx + jw + 6, sideTop)
      ..cubicTo(_cx + jw * 0.85, sideTop + 15, _cx + jw * 0.48, midY, _cx, midY)
      ..cubicTo(_cx - jw * 0.48, midY, _cx - jw * 0.85, sideTop + 15, _cx - jw - 6, sideTop)
      ..close();
  }

  void _paintBeard(Canvas canvas) {
    final spec = _beardSpec;
    if (spec.coverage <= 0 && !spec.mustache && !spec.soulPatch && !spec.chinOnly) {
      return;
    }

    canvas.save();
    // Uzun sakal yüzün altına taşabilsin diye kırpma alanı çeneyi aşar.
    final clip = Path.from(_headPath())
      ..addOval(Rect.fromCenter(center: Offset(_cx, _chinY - 4), width: _jawHalf * 2.3, height: 72));
    canvas.clipPath(clip);

    final beardPaint = Paint()..color = _hair.withValues(alpha: spec.opacity);

    if (spec.coverage > 0 && !spec.chinStrap) {
      final path = _beardPath(spec.coverage);
      canvas.drawPath(path, beardPaint);
      if (detailed) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5
            ..color = _hair.withValues(alpha: spec.opacity * 0.55)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
        );
      }
    }

    if (spec.chinStrap) {
      // Dolu bandı çiz, sonra içini ten rengiyle oyarak ince şerit bırak.
      canvas.drawPath(_beardPath(spec.coverage), beardPaint);
      canvas.save();
      canvas.translate(_cx, _chinY);
      canvas.scale(0.86, 0.86);
      canvas.translate(-_cx, -_chinY);
      canvas.drawPath(_beardPath(spec.coverage), Paint()..color = _skin);
      canvas.restore();
    }

    if (spec.chinOnly) {
      canvas.drawPath(
        Path()
          ..moveTo(_cx - 11, _mouthY + 10)
          ..quadraticBezierTo(_cx, _mouthY + 6, _cx + 11, _mouthY + 10)
          ..quadraticBezierTo(_cx + 8, _chinY + 3, _cx, _chinY + 5)
          ..quadraticBezierTo(_cx - 8, _chinY + 3, _cx - 11, _mouthY + 10)
          ..close(),
        beardPaint,
      );
    }

    if (spec.soulPatch) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, _mouthY + 10), width: 11, height: 5.5),
        beardPaint,
      );
    }

    if (spec.mustache) {
      canvas.drawPath(_mustachePath(spec), Paint()..color = _hair);
    }

    canvas.restore();
  }

  // -------------------------------------------------------------------- saç
  Path _capPath({double extra = 0, double? hairlineOverride}) {
    final spec = _hairSpec;
    final cw = _cheekHalf + 1.5 + extra;
    final lift = spec.volume * 11;
    final top = 26 - lift;
    final hy = hairlineOverride ?? spec.hairlineY;
    return Path()
      ..moveTo(_cx - cw - 1.5, 90)
      ..cubicTo(_cx - cw - 7, 54 - lift * 0.5, _cx - 33, top, _cx, top)
      ..cubicTo(_cx + 33, top, _cx + cw + 7, 54 - lift * 0.5, _cx + cw + 1.5, 90)
      ..cubicTo(_cx + cw - 4, 76, _cx + cw - 10, hy + 7, _cx + 24, hy + 3)
      ..cubicTo(_cx + 12, hy - 2, _cx - 12, hy - 2, _cx - 24, hy + 3)
      ..cubicTo(_cx - cw + 10, hy + 7, _cx - cw + 4, 76, _cx - cw - 1.5, 90)
      ..close();
  }

  void _paintHairBack(Canvas canvas) {
    final spec = _hairSpec;

    if (spec.headscarf) {
      canvas.drawPath(
        Path()
          ..moveTo(_cx - 60, 200)
          ..cubicTo(_cx - 66, 120, _cx - 60, 44, _cx, 26)
          ..cubicTo(_cx + 60, 44, _cx + 66, 120, _cx + 60, 200)
          ..close(),
        Paint()..color = Color.lerp(config.clothingColor, Colors.black, 0.18)!,
      );
      return;
    }
    if (spec.bald) return;

    final dark = Paint()..color = _hairDark;

    switch (spec.back) {
      case HairBack.none:
        break;
      case HairBack.medium:
        canvas.drawPath(
          Path()
            ..moveTo(_cx - 56, 150)
            ..cubicTo(_cx - 62, 110, _cx - 58, 56, _cx, 30)
            ..cubicTo(_cx + 58, 56, _cx + 62, 110, _cx + 56, 150)
            ..cubicTo(_cx + 30, 160, _cx - 30, 160, _cx - 56, 150)
            ..close(),
          dark,
        );
        break;
      case HairBack.long:
        final back = Path()
          ..moveTo(_cx - 64, 200)
          ..cubicTo(_cx - 70, 130, _cx - 62, 58, _cx, 30)
          ..cubicTo(_cx + 62, 58, _cx + 70, 130, _cx + 64, 200)
          ..close();
        canvas.drawPath(back, dark);
        if (detailed) {
          canvas.drawPath(
            back,
            Paint()
              ..shader = ui.Gradient.linear(
                const Offset(0, 40),
                const Offset(0, 200),
                [_hair.withValues(alpha: 0.9), _hairDark.withValues(alpha: 0.2)],
              ),
          );
        }
        break;
      case HairBack.bun:
        canvas.drawCircle(Offset(_cx, 32), 17, dark);
        canvas.drawCircle(Offset(_cx - 4, 28), 11, Paint()..color = _hair.withValues(alpha: 0.7));
        break;
      case HairBack.highBun:
        canvas.drawRect(Rect.fromCenter(center: Offset(_cx, 32), width: 13, height: 12), dark);
        canvas.drawCircle(Offset(_cx, 19), 15, dark);
        canvas.drawCircle(Offset(_cx - 4, 15), 9, Paint()..color = _hair.withValues(alpha: 0.65));
        break;
      case HairBack.ponytail:
        canvas.drawPath(
          Path()
            ..moveTo(_cx + 40, 52)
            ..cubicTo(_cx + 76, 70, _cx + 80, 128, _cx + 60, 168)
            ..cubicTo(_cx + 52, 140, _cx + 44, 96, _cx + 36, 74)
            ..close(),
          dark,
        );
        break;
      case HairBack.lowPonytail:
        canvas.drawPath(
          Path()
            ..moveTo(_cx + 34, 92)
            ..cubicTo(_cx + 66, 110, _cx + 68, 160, _cx + 52, 192)
            ..cubicTo(_cx + 46, 158, _cx + 38, 120, _cx + 30, 100)
            ..close(),
          dark,
        );
        break;
      case HairBack.braid:
        for (var i = 0; i < 5; i++) {
          final y = 96.0 + i * 20;
          final w = 16.0 - i * 1.6;
          canvas.drawOval(
            Rect.fromCenter(center: Offset(_cx + 41 + i * 1.2, y), width: w, height: 21),
            dark,
          );
        }
        break;
      case HairBack.pigtails:
        _mirrored(canvas, (c) {
          c.drawPath(
            Path()
              ..moveTo(_cx - 46, 74)
              ..cubicTo(_cx - 66, 88, _cx - 70, 128, _cx - 58, 160)
              ..cubicTo(_cx - 52, 132, _cx - 46, 102, _cx - 42, 82)
              ..close(),
            dark,
          );
          c.drawOval(
            Rect.fromCenter(center: Offset(_cx - 46, 76), width: 13, height: 12),
            Paint()..color = _hair,
          );
        });
        break;
    }
  }

  void _paintHairFront(Canvas canvas) {
    final spec = _hairSpec;

    if (spec.headscarf) {
      _paintHeadscarf(canvas);
      return;
    }
    if (spec.bald) return;

    final basePaint = Paint()..color = _hair;

    _paintHairTexture(canvas, basePaint);
    canvas.drawPath(_capPath(), basePaint);
    _paintFringe(canvas);
    _paintHairSides(canvas);

    if (!detailed) return;

    canvas.save();
    canvas.clipPath(_capPath(extra: 6, hairlineOverride: spec.hairlineY + 4));
    final gloss = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.2
      ..color = _hairLight.withValues(alpha: 0.42);
    canvas.drawPath(
      Path()
        ..moveTo(_cx - 30, 52)
        ..quadraticBezierTo(_cx - 12, 36, _cx + 14, 38),
      gloss,
    );
    gloss
      ..strokeWidth = 2.2
      ..color = _hairLight.withValues(alpha: 0.28);
    canvas.drawPath(
      Path()
        ..moveTo(_cx - 36, 64)
        ..quadraticBezierTo(_cx - 18, 46, _cx + 8, 46),
      gloss,
    );
    canvas.restore();

    canvas.save();
    canvas.clipPath(_headPath());
    canvas.drawPath(_capPath(), _soft(Colors.black.withValues(alpha: 0.20), 4));
    canvas.restore();
  }

  void _paintHairTexture(Canvas canvas, Paint paint) {
    final spec = _hairSpec;
    if (spec.texture == HairTexture.smooth) return;

    final count = switch (spec.texture) {
      HairTexture.wavy => 11,
      HairTexture.curly => 15,
      HairTexture.coily => 21,
      HairTexture.smooth => 0,
    };
    final radius = switch (spec.texture) {
      HairTexture.wavy => 9.0,
      HairTexture.curly => 11.0,
      HairTexture.coily => 10.0,
      HairTexture.smooth => 0.0,
    };
    // Yay, kepin kendi silüetine oturur: halkalar taç gibi tepede durmaz,
    // saçın hacmini oluşturur.
    const baseY = 74.0;
    final capTop = 26 - spec.volume * 11;
    final rx = _cheekHalf + (spec.texture == HairTexture.coily ? 8 : 2);
    final ry = (baseY - capTop) - radius * 0.35 + (spec.texture == HairTexture.coily ? 6 : 0);

    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final ang = math.pi * t;
      final x = _cx - rx * math.cos(ang);
      final y = baseY - ry * math.sin(ang);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }

    if (!detailed) return;
    for (var i = 0; i < count; i += 2) {
      final t = i / (count - 1);
      final ang = math.pi * t;
      final x = _cx - rx * math.cos(ang);
      final y = baseY - ry * math.sin(ang);
      canvas.drawCircle(
        Offset(x - radius * 0.28, y - radius * 0.3),
        radius * 0.38,
        Paint()..color = _hairLight.withValues(alpha: 0.20),
      );
    }
  }

  void _paintFringe(Canvas canvas) {
    final spec = _hairSpec;
    if (spec.fringe == HairFringe.none) return;

    final cw = _cheekHalf;
    final hy = spec.hairlineY;

    if (spec.fringe == HairFringe.spiky) {
      // Dikenler kepin dış hattı boyunca yukarı taşar.
      for (var i = 0; i < 10; i++) {
        // Yalnızca tepe yayı (0.18–0.82): yanlarda taç gibi durmasın.
        final t = 0.18 + (i / 9) * 0.64;
        final ang = math.pi * t;
        final rx = cw + 1;
        final ry = (74 - (26 - spec.volume * 11)) - 4;
        final x = _cx - rx * math.cos(ang);
        final y = 74 - ry * math.sin(ang);
        canvas.drawPath(
          Path()
            ..moveTo(x - 9, y + 9)
            ..lineTo(x - math.cos(ang) * 4, y - 11)
            ..lineTo(x + 9, y + 9)
            ..close(),
          Paint()..color = _hair,
        );
      }
      return;
    }

    canvas.save();
    canvas.clipPath(_capPath(extra: 2, hairlineOverride: hy + 14));
    final dark = Paint()..color = _hairDark;

    switch (spec.fringe) {
      case HairFringe.none:
      case HairFringe.spiky:
        break;
      case HairFringe.side:
        canvas.drawPath(
          Path()
            ..moveTo(_cx - cw - 4, hy + 7)
            ..cubicTo(_cx - 26, hy - 23, _cx + 14, hy - 23, _cx + cw + 2, hy - 7)
            ..cubicTo(_cx + 14, hy - 13, _cx - 14, hy - 7, _cx - cw - 4, hy + 13)
            ..close(),
          dark,
        );
        break;
      case HairFringe.blunt:
        canvas.drawPath(
          Path()
            ..moveTo(_cx - cw - 2, hy - 18)
            ..lineTo(_cx + cw + 2, hy - 18)
            ..lineTo(_cx + cw - 2, hy + 8)
            ..quadraticBezierTo(_cx, hy + 14, _cx - cw + 2, hy + 8)
            ..close(),
          dark,
        );
        break;
      case HairFringe.curtain:
        _mirrored(canvas, (c) {
          c.drawPath(
            Path()
              ..moveTo(_cx - 2, hy - 20)
              ..cubicTo(_cx - 18, hy - 12, _cx - cw + 4, hy - 2, _cx - cw - 2, hy + 16)
              ..cubicTo(_cx - cw + 6, hy - 6, _cx - 16, hy - 18, _cx - 2, hy - 26)
              ..close(),
            dark,
          );
        });
        break;
    }
    canvas.restore();
  }

  void _paintHairSides(Canvas canvas) {
    final spec = _hairSpec;
    final cw = _cheekHalf;
    final paint = Paint()..color = _hair;

    switch (spec.sides) {
      case HairSides.none:
        break;
      case HairSides.sideburn:
        _mirrored(canvas, (c) {
          c.drawPath(
            Path()
              ..moveTo(_cx - cw + 3, 82)
              ..lineTo(_cx - cw + 7, 82)
              ..quadraticBezierTo(_cx - cw + 6.5, 92, _cx - cw + 5.5, 96)
              ..quadraticBezierTo(_cx - cw + 4.5, 90, _cx - cw + 3, 82)
              ..close(),
            paint,
          );
        });
        break;
      case HairSides.short:
        _mirrored(canvas, (c) {
          c.drawPath(
            Path()
              ..moveTo(_cx - cw - 3, 72)
              ..cubicTo(_cx - cw - 8, 92, _cx - cw - 7, 106, _cx - cw - 2, 118)
              ..lineTo(_cx - cw + 8, 114)
              ..cubicTo(_cx - cw + 4, 100, _cx - cw + 3, 86, _cx - cw + 5, 74)
              ..close(),
            paint,
          );
        });
        break;
      case HairSides.long:
        _mirrored(canvas, (c) {
          c.drawPath(
            Path()
              ..moveTo(_cx - cw - 3, 70)
              ..cubicTo(_cx - cw - 13, 110, _cx - cw - 11, 148, _cx - cw - 5, 180)
              ..lineTo(_cx - cw + 9, 178)
              ..cubicTo(_cx - cw + 3, 142, _cx - cw + 2, 106, _cx - cw + 5, 74)
              ..close(),
            paint,
          );
        });
        break;
      case HairSides.tucked:
        _mirrored(canvas, (c) {
          c.drawPath(
            Path()
              ..moveTo(_cx - cw - 2, 74)
              ..cubicTo(_cx - cw - 5, 84, _cx - cw - 4, 92, _cx - cw - 1, 98)
              ..lineTo(_cx - cw + 5, 96)
              ..cubicTo(_cx - cw + 3, 88, _cx - cw + 3, 80, _cx - cw + 4, 74)
              ..close(),
            paint,
          );
        });
        break;
    }
  }

  void _paintHeadscarf(Canvas canvas) {
    final cw = _cheekHalf;
    final scarf = Path()
      ..moveTo(_cx - cw - 7, 108)
      ..cubicTo(_cx - cw - 10, 56, _cx - 34, 24, _cx, 24)
      ..cubicTo(_cx + 34, 24, _cx + cw + 10, 56, _cx + cw + 7, 108)
      ..cubicTo(_cx + cw + 2, 84, _cx + 30, 52, _cx, 52)
      ..cubicTo(_cx - 30, 52, _cx - cw - 2, 84, _cx - cw - 7, 108)
      ..close();
    canvas.drawPath(scarf, Paint()..color = config.clothingColor);
    if (detailed) {
      canvas.drawPath(
        scarf,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(_cx - cw, 24),
            Offset(_cx + cw, 108),
            [Colors.white.withValues(alpha: 0.18), Colors.black.withValues(alpha: 0.10)],
          ),
      );
    }
    _mirrored(canvas, (c) {
      c.drawPath(
        Path()
          ..moveTo(_cx - cw - 7, 104)
          ..cubicTo(_cx - cw - 14, 130, _cx - cw - 12, 150, _cx - cw - 6, 168)
          ..lineTo(_cx - cw + 6, 166)
          ..cubicTo(_cx - cw + 2, 144, _cx - cw + 1, 124, _cx - cw + 2, 104)
          ..close(),
        Paint()..color = Color.lerp(config.clothingColor, Colors.black, 0.12)!,
      );
    });
  }

  // ----------------------------------------------------------------- gözlük
  void _paintGlasses(Canvas canvas) {
    final spec = _glassesSpec;
    if (spec.width <= 0) return;

    final frameColor = spec.sun ? const Color(0xFF23262B) : const Color(0xFF3A3F47);
    final lensW = _eyeW * 1.26 * spec.width;
    final lensH = spec.round ? lensW : _eyeH * 1.58 * spec.height;
    final strokeW = spec.height > 1.05 ? 3.4 : 2.2;

    void drawLens(Canvas c, double dx) {
      final rect = Rect.fromCenter(
        center: Offset(_cx + dx, _eyeY),
        width: lensW * 2,
        height: spec.round ? lensW * 2 : lensH * 2,
      );
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(spec.round ? lensW : 5));
      c.drawRRect(
        rrect,
        Paint()
          ..color = spec.sun
              ? const Color(0xFF1C1F24).withValues(alpha: 0.88)
              : Colors.white.withValues(alpha: 0.16),
      );
      if (detailed) {
        c.drawRRect(
          rrect,
          Paint()
            ..shader = ui.Gradient.linear(
              rect.topLeft,
              rect.bottomRight,
              [
                Colors.white.withValues(alpha: spec.sun ? 0.22 : 0.40),
                Colors.white.withValues(alpha: 0.0),
              ],
            ),
        );
      }
      c.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..color = frameColor,
      );
    }

    drawLens(canvas, -_eyeDx);
    drawLens(canvas, _eyeDx);
    canvas.drawLine(
      Offset(_cx - _eyeDx + lensW, _eyeY - 2),
      Offset(_cx + _eyeDx - lensW, _eyeY - 2),
      Paint()
        ..strokeWidth = strokeW
        ..strokeCap = StrokeCap.round
        ..color = frameColor,
    );
    _mirrored(canvas, (c) {
      c.drawLine(
        Offset(_cx - _eyeDx - lensW, _eyeY - 2),
        Offset(_cx - _cheekHalf + 3, _eyeY - 6),
        Paint()
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = frameColor,
      );
    });
  }

  @override
  bool shouldRepaint(covariant FaceAvatarPainter oldDelegate) => true;
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
