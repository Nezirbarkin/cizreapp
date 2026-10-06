part of '../face_avatar_painter.dart';

// ============================================================================
// GÖZLÜK / BAŞLIK / TAKI (Bitmoji tarzı: düz renk + cel gölge + kontur)
// ============================================================================

/// Düz yüzey: dolgu → sağ altta cel gölge → üstte parlama → kontur.
void _solid(Canvas canvas, _Rig r, Path path, Color color, {double gloss = 0.16, Offset light = const Offset(-6, -5)}) {
  canvas.drawPath(path, r.fill(color));
  r.celShade(canvas, path, _alpha(_tone(color, -0.30), 0.95), base: color, offset: light, blur: r.detailed ? 1.0 : 0);
  if (gloss > 0 && r.detailed) {
    final b = path.getBounds();
    canvas.save();
    canvas.clipPath(path);
    canvas.drawOval(
      Rect.fromLTWH(b.left + b.width * 0.12, b.top + b.height * 0.10, b.width * 0.42, b.height * 0.32),
      r.soft(_alpha(Colors.white, gloss), 2.5),
    );
    canvas.restore();
  }
  canvas.drawPath(path, r.stroke(_tone(color, -0.55), r.lineW));
}

/// Şapkanın alnına düşürdüğü gölge.
void _castHatShadow(Canvas canvas, _Rig r, Path shape, {double dy = 3.5}) {
  canvas.save();
  canvas.clipPath(r.head);
  canvas.drawPath(shape.shift(Offset(1, dy)), r.soft(_alpha(r.skinShadow, 0.95), r.detailed ? 1.4 : 0));
  canvas.restore();
}

Path _dome(double cx, double topY, double baseY, double hw, {double curve = 3}) {
  return Path()
    ..moveTo(cx - hw, baseY)
    ..cubicTo(cx - hw * 1.02, topY + (baseY - topY) * 0.25, cx - hw * 0.62, topY, cx, topY)
    ..cubicTo(cx + hw * 0.62, topY, cx + hw * 1.02, topY + (baseY - topY) * 0.25, cx + hw, baseY)
    ..quadraticBezierTo(cx, baseY + curve, cx - hw, baseY)
    ..close();
}

// ============================================================ BAŞLIK (ARKA)
void _paintHeadwearBack(Canvas canvas, _Rig r) {
  // Kapüşonun başın arkasında kalan iç kısmı.
  if (r.headwear.kind == Headwear.hood) {
    final cw = r.cheekHalf;
    final inner = _symmetric([
      const Offset(0, 14),
      Offset(cw + 12, 60),
      Offset(cw + 16, 130),
      Offset(cw + 20, 172),
      const Offset(0, 176),
    ]);
    canvas.drawPath(inner, r.fill(_tone(r.headwear.color, -0.45)));
  }
}

// =============================================================== BAŞLIK (ÖN)
void _paintHeadwearFront(Canvas canvas, _Rig r) {
  final spec = r.headwear;
  if (spec.kind == Headwear.none) return;
  final col = spec.color;
  final fh = r.foreheadHalf;
  final g = _HairGeo(r);
  final band = fh + 9.5;
  final bandY = g.hl + 5;

  switch (spec.kind) {
    case Headwear.none:
      return;

    case Headwear.cap:
    case Headwear.capBack:
      final forward = spec.kind == Headwear.cap;
      final dome = _dome(_cx, _Rig.skullTop - 13, bandY, band, curve: 3);
      _castHatShadow(canvas, r, dome);
      _solid(canvas, r, dome, col);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        final seam = r.stroke(_alpha(_tone(col, -0.5), 0.6), 0.8);
        canvas.drawPath(Path()..moveTo(_cx, _Rig.skullTop - 13)..quadraticBezierTo(_cx - 1, 34, _cx, bandY), seam);
        canvas.drawPath(Path()..moveTo(_cx - band * 0.4, _Rig.skullTop - 9)..quadraticBezierTo(_cx - band * 0.85, 36, _cx - band * 0.8, bandY), seam);
        canvas.drawPath(Path()..moveTo(_cx + band * 0.4, _Rig.skullTop - 9)..quadraticBezierTo(_cx + band * 0.85, 36, _cx + band * 0.8, bandY), seam);
        canvas.restore();
      }
      canvas.drawCircle(Offset(_cx, _Rig.skullTop - 12.5), 2.4, r.fill(_tone(col, -0.2)));
      if (forward) {
        final bill = Path()
          ..moveTo(_cx - band + 2, bandY - 1)
          ..cubicTo(_cx - band * 0.8, bandY + 16, _cx + band * 0.8, bandY + 16, _cx + band - 2, bandY - 1)
          ..quadraticBezierTo(_cx, bandY + 4, _cx - band + 2, bandY - 1)
          ..close();
        _castHatShadow(canvas, r, bill, dy: 4);
        _solid(canvas, r, bill, _tone(col, -0.12), gloss: 0.2);
      } else {
        // Ters şapka: alında ayar kayışı boşluğu.
        final strap = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(_cx, bandY - 4), width: 18, height: 7), const Radius.circular(3));
        canvas.drawRRect(strap, r.fill(r.hairColor));
        canvas.drawRRect(strap, r.stroke(_tone(col, -0.55), r.lineW));
        canvas.drawLine(Offset(_cx - 9, bandY - 1), Offset(_cx + 9, bandY - 1), r.stroke(_tone(col, -0.3), 2));
      }
      return;

    case Headwear.beanie:
    case Headwear.beaniePom:
      final dome = _dome(_cx, _Rig.skullTop - 12, bandY + 2, band - 1, curve: 1);
      _solid(canvas, r, dome, col, gloss: 0.1);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        for (var i = -7; i <= 7; i++) {
          final x = _cx + i * (band * 0.14);
          canvas.drawPath(
            Path()
              ..moveTo(_cx + (x - _cx) * 0.25, _Rig.skullTop - 10)
              ..quadraticBezierTo(x + (x - _cx) * 0.1, 34, x, bandY),
            r.stroke(_alpha(_tone(col, -0.3), 0.6), 0.9),
          );
        }
        canvas.restore();
      }
      final cuff = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTRB(_cx - band - 1.5, bandY - 9, _cx + band + 1.5, bandY + 6), const Radius.circular(5)));
      _castHatShadow(canvas, r, cuff, dy: 3);
      _solid(canvas, r, cuff, _tone(col, -0.06), gloss: 0.08);
      canvas.save();
      canvas.clipPath(cuff);
      for (var i = -14; i <= 14; i++) {
        canvas.drawLine(Offset(_cx + i * 3.6, bandY - 9), Offset(_cx + i * 3.6, bandY + 6), r.stroke(_alpha(_tone(col, -0.35), 0.7), 1.0));
      }
      canvas.restore();
      if (spec.kind == Headwear.beaniePom) {
        final pom = Path()..addOval(Rect.fromCircle(center: Offset(_cx, _Rig.skullTop - 15), radius: 9));
        _solid(canvas, r, _scallop(pom, 1.0, 4, seed: 701), _tone(col, 0.08));
      }
      return;

    case Headwear.fedora:
      final crown = Path()
        ..moveTo(_cx - fh - 2, bandY - 2)
        ..cubicTo(_cx - fh - 4, 28, _cx - fh * 0.7, 12, _cx - 7, 12)
        ..quadraticBezierTo(_cx, 18, _cx + 7, 12)
        ..cubicTo(_cx + fh * 0.7, 12, _cx + fh + 4, 28, _cx + fh + 2, bandY - 2)
        ..close();
      final brim = Path()..addOval(Rect.fromCenter(center: Offset(_cx, bandY), width: (fh + 30) * 2, height: 20));
      _castHatShadow(canvas, r, brim, dy: 5);
      _solid(canvas, r, brim, _tone(col, -0.06), gloss: 0.12);
      _solid(canvas, r, crown, col);
      final ribbon = Path()
        ..moveTo(_cx - fh - 2.6, bandY - 12)
        ..quadraticBezierTo(_cx, bandY - 8, _cx + fh + 2.6, bandY - 12)
        ..lineTo(_cx + fh + 2.2, bandY - 3)
        ..quadraticBezierTo(_cx, bandY + 1, _cx - fh - 2.2, bandY - 3)
        ..close();
      _solid(canvas, r, ribbon, _tone(col, -0.45), gloss: 0.06);
      return;

    case Headwear.flatCap:
      final dome = Path()
        ..moveTo(_cx - band, bandY)
        ..cubicTo(_cx - band - 4, 28, _cx - fh * 0.5, 14, _cx + fh * 0.2, 18)
        ..cubicTo(_cx + band, 20, _cx + band + 5, 36, _cx + band, bandY)
        ..quadraticBezierTo(_cx, bandY + 5, _cx - band, bandY)
        ..close();
      _castHatShadow(canvas, r, dome);
      _solid(canvas, r, dome, col, gloss: 0.08);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        final rng = r.rngFor(702);
        for (var i = 0; i < 70; i++) {
          final p = Offset(_cx - band + rng.nextDouble() * band * 2, 16 + rng.nextDouble() * 44);
          canvas.drawLine(p, p.translate(2.2, 1.0), r.stroke(_alpha(rng.nextBool() ? Colors.white : Colors.black, 0.14), 0.7));
        }
        canvas.restore();
      }
      final bill = Path()
        ..moveTo(_cx - band + 3, bandY)
        ..quadraticBezierTo(_cx, bandY + 14, _cx + band - 3, bandY)
        ..quadraticBezierTo(_cx, bandY + 4, _cx - band + 3, bandY)
        ..close();
      _solid(canvas, r, bill, _tone(col, -0.16), gloss: 0.1);
      return;

    case Headwear.sunHat:
      final crown = _dome(_cx, _Rig.skullTop - 14, bandY - 2, fh + 5, curve: 0);
      final brim = Path()..addOval(Rect.fromCenter(center: Offset(_cx, bandY + 1), width: (fh + 50) * 2, height: 30));
      _castHatShadow(canvas, r, brim, dy: 5);
      _solid(canvas, r, brim, _tone(col, 0.02), gloss: 0.14);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(brim);
        for (var i = 1; i < 7; i++) {
          canvas.drawOval(
            Rect.fromCenter(center: Offset(_cx, bandY + 1), width: (fh + 50) * 2 * (i / 7), height: 30 * (i / 7)),
            r.stroke(_alpha(_tone(col, -0.3), 0.5), 0.7),
          );
        }
        canvas.restore();
      }
      _solid(canvas, r, crown, col, gloss: 0.14);
      final ribbon = Path()
        ..moveTo(_cx - fh - 5, bandY - 12)
        ..quadraticBezierTo(_cx, bandY - 7, _cx + fh + 5, bandY - 12)
        ..lineTo(_cx + fh + 5, bandY - 4)
        ..quadraticBezierTo(_cx, bandY + 1, _cx - fh - 5, bandY - 4)
        ..close();
      _solid(canvas, r, ribbon, const Color(0xFFB5443A), gloss: 0.08);
      return;

    case Headwear.headband:
      final pts = <Offset>[];
      for (var i = 0; i <= 18; i++) {
        final a = math.pi * (1 - i / 18);
        pts.add(Offset(_cx + math.cos(a) * (fh + 4), g.hl + 14 - math.sin(a) * (g.hl + 14 - g.topY - 6)));
      }
      _solid(canvas, r, _taperPath(pts, 6.5, 6.5, wMid: 7.4), col, gloss: 0.15);
      return;

    case Headwear.bandana:
      _paintBandana(canvas, r, col);
      return;

    case Headwear.headphones:
      final hw = r.cheekHalf + 9;
      final cy = (r.earTop + r.earBottom) / 2;
      final arcPts = <Offset>[];
      for (var i = 0; i <= 20; i++) {
        final a = math.pi * (1 - i / 20);
        arcPts.add(Offset(_cx + math.cos(a) * hw, cy - math.sin(a) * (cy - g.topY + 6)));
      }
      _solid(canvas, r, _taperPath(arcPts, 5, 5, wMid: 5.6), _tone(col, -0.05), gloss: 0.2);
      r.mirrored(canvas, (c, mir) {
        final cup = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(_cx - hw + 0.5, cy), width: 15, height: 27), const Radius.circular(7)));
        _solid(c, r, cup, _tone(col, mir ? -0.1 : 0.0), gloss: 0.2);
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(_cx - hw + 4.5, cy), width: 6, height: 20), const Radius.circular(3)),
            r.fill(_tone(col, -0.3)));
      });
      return;

    case Headwear.flowerCrown:
      final rng = r.rngFor(703);
      final colors = <Color>[col, const Color(0xFFF6E7A8), const Color(0xFFFFFFFF), const Color(0xFFD9578A), const Color(0xFFB08AD8)];
      final ry = g.hl + 10 - (g.topY + 8);
      Offset at(double t) {
        final a = math.pi * (1 - t);
        return Offset(_cx + math.cos(a) * (fh + 5), g.hl + 10 - math.sin(a) * ry);
      }
      for (var i = 0; i <= 16; i++) {
        final p = at(i / 16);
        final leaf = Path()..addOval(Rect.fromCenter(center: p, width: 9, height: 4.5));
        canvas.drawPath(leaf, r.fill(const Color(0xFF5E9A5E)));
        canvas.drawPath(leaf, r.stroke(const Color(0xFF2F5A33), r.lineW * 0.7));
      }
      for (var i = 0; i < 8; i++) {
        final p = at((i + 0.5) / 8);
        final fc = colors[i % colors.length];
        final rad = 4.6 + rng.nextDouble() * 1.4;
        final flower = Path();
        for (var k = 0; k < 5; k++) {
          final pa = k * math.pi * 2 / 5;
          flower.addOval(Rect.fromCircle(center: p + Offset(math.cos(pa), math.sin(pa)) * rad * 0.6, radius: rad * 0.55));
        }
        canvas.drawPath(flower, r.fill(fc));
        canvas.drawPath(flower, r.stroke(_tone(fc, -0.45), r.lineW * 0.7));
        canvas.drawCircle(p, rad * 0.34, r.fill(const Color(0xFFE8B23C)));
      }
      return;

    case Headwear.tiara:
      final ry = g.hl + 6 - (g.topY + 10);
      final pts = <Offset>[];
      for (var i = 0; i <= 18; i++) {
        final a = math.pi * (1 - i / 18);
        pts.add(Offset(_cx + math.cos(a) * (fh + 2), g.hl + 6 - math.sin(a) * ry));
      }
      _solid(canvas, r, _taperPath(pts, 2.6, 2.6, wMid: 2.8), col, gloss: 0.3);
      final peakY = g.hl + 6 - ry;
      final peak = Path()
        ..moveTo(_cx - 10, peakY + 2)
        ..lineTo(_cx - 4, peakY - 11)
        ..lineTo(_cx, peakY - 4)
        ..lineTo(_cx + 4, peakY - 11)
        ..lineTo(_cx + 10, peakY + 2)
        ..close();
      _solid(canvas, r, peak, col, gloss: 0.3);
      canvas.drawCircle(Offset(_cx, peakY - 1), 2.3, r.fill(const Color(0xFF6FB8E8)));
      canvas.drawCircle(Offset(_cx, peakY - 1), 2.3, r.stroke(const Color(0xFF2F5F88), r.lineW * 0.7));
      return;

    case Headwear.bow:
      final c0 = Offset(_cx + g.fh * 0.62, g.topY + 12);
      for (final s in [-1.0, 1.0]) {
        final loop = Path()
          ..moveTo(c0.dx, c0.dy)
          ..cubicTo(c0.dx + s * 8, c0.dy - 13, c0.dx + s * 21, c0.dy - 10, c0.dx + s * 19, c0.dy + 1)
          ..cubicTo(c0.dx + s * 21, c0.dy + 11, c0.dx + s * 8, c0.dy + 13, c0.dx, c0.dy)
          ..close();
        _solid(canvas, r, loop, col, gloss: 0.2);
      }
      _solid(canvas, r, Path()..addOval(Rect.fromCenter(center: c0, width: 8.5, height: 10.5)), _tone(col, -0.12), gloss: 0.2);
      return;

    case Headwear.clips:
      for (var i = 0; i < 3; i++) {
        final p = Offset(_cx - g.fh * 0.78 + i * 2.2, g.hl + 2 + i * 7.5);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(-0.55);
        final clip = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 12, height: 3.6), const Radius.circular(1.8)));
        _solid(canvas, r, clip, col, gloss: 0.3);
        canvas.restore();
      }
      return;

    case Headwear.visor:
      final strap = Path()
        ..moveTo(_cx - band + 1, bandY - 4)
        ..quadraticBezierTo(_cx, bandY + 1, _cx + band - 1, bandY - 4)
        ..lineTo(_cx + band - 1, bandY + 2)
        ..quadraticBezierTo(_cx, bandY + 7, _cx - band + 1, bandY + 2)
        ..close();
      _solid(canvas, r, strap, _tone(col, -0.08));
      final bill = Path()
        ..moveTo(_cx - band + 2, bandY + 1)
        ..cubicTo(_cx - band * 0.8, bandY + 17, _cx + band * 0.8, bandY + 17, _cx + band - 2, bandY + 1)
        ..quadraticBezierTo(_cx, bandY + 6, _cx - band + 2, bandY + 1)
        ..close();
      _castHatShadow(canvas, r, bill, dy: 4);
      _solid(canvas, r, bill, col, gloss: 0.2);
      return;

    case Headwear.turbanWrap:
      _paintTurban(canvas, r, col);
      return;

    case Headwear.hood:
      final cw = r.cheekHalf;
      final outer = _symmetric([
        const Offset(0, 8),
        Offset(fh * 0.65, 11),
        Offset(fh + 14, 36),
        Offset(cw + 15, 80),
        Offset(cw + 16, 124),
        Offset(cw + 19, 160),
        Offset(cw + 26, 186),
        const Offset(0, 192),
      ]);
      final opening = _faceOpening(r, top: g.hl - 2, side: 1.08, chinExtra: 6);
      final fabric = Path.combine(PathOperation.difference, outer, opening);
      canvas.save();
      canvas.clipPath(opening);
      canvas.drawPath(opening, r.stroke(_alpha(r.skinShadow, 0.95), 6, blur: r.detailed ? 1.4 : 0));
      canvas.restore();
      _solid(canvas, r, fabric, col, gloss: 0.08);
      canvas.drawPath(opening, r.stroke(_tone(col, 0.2), 2.4));
      canvas.drawPath(opening, r.stroke(_tone(col, -0.55), r.lineW));
      return;
  }
}

// ================================================================== GÖZLÜK
/// Sol göz (ekranda solda) için mercek yolu; iç taraf +x.
Path _lensPath(GlassesShape shape, Offset c, double a, double b) {
  switch (shape) {
    case GlassesShape.none:
      return Path();
    case GlassesShape.rect:
      return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: a * 2, height: b * 2 * 0.84), const Radius.circular(4.2)));
    case GlassesShape.square:
      return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: a * 2 * 0.96, height: b * 2 * 1.0), const Radius.circular(3.0)));
    case GlassesShape.round:
      return Path()..addOval(Rect.fromCenter(center: c, width: b * 2.25, height: b * 2.25));
    case GlassesShape.oval:
      return Path()..addOval(Rect.fromCenter(center: c, width: a * 2, height: b * 2 * 0.84));
    case GlassesShape.cat:
      return _spline([
        Offset(c.dx - a * 1.10, c.dy - b * 1.02),
        Offset(c.dx - a * 0.2, c.dy - b * 0.74),
        Offset(c.dx + a * 0.78, c.dy - b * 0.56),
        Offset(c.dx + a * 0.74, c.dy + b * 0.55),
        Offset(c.dx - a * 0.1, c.dy + b * 0.90),
        Offset(c.dx - a * 0.94, c.dy + b * 0.30),
      ], closed: true);
    case GlassesShape.aviator:
      return _spline([
        Offset(c.dx - a * 0.98, c.dy - b * 0.80),
        Offset(c.dx, c.dy - b * 0.88),
        Offset(c.dx + a * 0.98, c.dy - b * 0.76),
        Offset(c.dx + a * 0.86, c.dy + b * 0.32),
        Offset(c.dx + a * 0.15, c.dy + b * 1.08),
        Offset(c.dx - a * 0.7, c.dy + b * 0.85),
        Offset(c.dx - a * 1.0, c.dy + b * 0.05),
      ], closed: true);
    case GlassesShape.wayfarer:
      return _spline([
        Offset(c.dx - a * 1.06, c.dy - b * 0.88),
        Offset(c.dx, c.dy - b * 0.94),
        Offset(c.dx + a * 1.0, c.dy - b * 0.94),
        Offset(c.dx + a * 0.86, c.dy + b * 0.52),
        Offset(c.dx + a * 0.1, c.dy + b * 0.84),
        Offset(c.dx - a * 0.88, c.dy + b * 0.64),
      ], closed: true, tension: 0.7);
    case GlassesShape.browline:
      return Path()
        ..addRRect(RRect.fromLTRBAndCorners(c.dx - a, c.dy - b * 0.8, c.dx + a, c.dy + b * 0.85,
            topLeft: const Radius.circular(1.6),
            topRight: const Radius.circular(1.6),
            bottomLeft: Radius.circular(b * 0.9),
            bottomRight: Radius.circular(b * 0.9)));
    case GlassesShape.hexagon:
      final pts = <Offset>[];
      for (var i = 0; i < 6; i++) {
        final ang = math.pi / 6 + i * math.pi / 3 - math.pi / 2;
        pts.add(Offset(c.dx + math.cos(ang) * a * 0.98, c.dy + math.sin(ang) * b * 1.05));
      }
      return Path()..addPolygon(pts, true);
    case GlassesShape.wrap:
      return _spline([
        Offset(c.dx - a * 1.14, c.dy - b * 0.55),
        Offset(c.dx, c.dy - b * 0.92),
        Offset(c.dx + a * 1.02, c.dy - b * 0.7),
        Offset(c.dx + a * 0.95, c.dy + b * 0.5),
        Offset(c.dx, c.dy + b * 0.8),
        Offset(c.dx - a * 1.1, c.dy + b * 0.3),
      ], closed: true);
    case GlassesShape.halfMoon:
      return Path()
        ..moveTo(c.dx - a * 0.95, c.dy - b * 0.25)
        ..lineTo(c.dx + a * 0.95, c.dy - b * 0.25)
        ..quadraticBezierTo(c.dx + a * 0.9, c.dy + b * 1.0, c.dx, c.dy + b * 0.95)
        ..quadraticBezierTo(c.dx - a * 0.9, c.dy + b * 1.0, c.dx - a * 0.95, c.dy - b * 0.25)
        ..close();
  }
}

void _paintGlasses(Canvas canvas, _Rig r) {
  final spec = r.glasses;
  if (spec.shape == GlassesShape.none) return;

  final a = math.max(r.eyeW * 1.48, 12.5); // yarı genişlik
  final b = math.max(r.eyeH * 1.75, 9.8); // yarı yükseklik
  final centerDx = r.eyeDx;
  final cy = _Rig.eyeY + 0.8;
  final frameW = (1.5 * spec.thickness + (spec.rimless ? -0.6 : 0)).clamp(0.7, 3.4);
  final frame = spec.frame;
  final frameLine = _tone(frame, -0.5);

  // Camın yüze düşürdüğü gölge.
  canvas.save();
  canvas.clipPath(r.head);
  r.mirrored(canvas, (c, mir) {
    final lens = _lensPath(spec.shape, Offset(_cx - centerDx, cy), a, b);
    c.drawPath(lens.shift(const Offset(1, 3)), r.stroke(_alpha(r.skinShadow, 0.9), frameW, blur: r.detailed ? 1.0 : 0));
  });
  canvas.restore();

  r.mirrored(canvas, (c, mir) {
    final center = Offset(_cx - centerDx, cy);
    final lens = _lensPath(spec.shape, center, a, b);
    final bounds = lens.getBounds();

    // Mercek.
    if (spec.sun) {
      c.drawPath(
        lens,
        Paint()
          ..shader = ui.Gradient.linear(bounds.topCenter, bounds.bottomCenter, [const Color(0xF2141A22), const Color(0xD9303A48)]),
      );
    } else {
      c.drawPath(lens, r.fill(spec.tint));
    }
    // Çapraz yansıma şeridi (ışık soldan: aynada sağa kayar).
    c.save();
    c.clipPath(lens);
    final x0 = bounds.left + bounds.width * (mir ? 0.50 : 0.16);
    final glare = Path()
      ..moveTo(x0, bounds.bottom)
      ..lineTo(x0 + bounds.width * 0.14, bounds.bottom)
      ..lineTo(x0 + bounds.width * 0.42, bounds.top)
      ..lineTo(x0 + bounds.width * 0.28, bounds.top)
      ..close();
    c.drawPath(glare, r.fill(_alpha(Colors.white, spec.sun ? 0.28 : 0.30)));
    c.restore();

    // Çerçeve.
    if (spec.shape == GlassesShape.browline) {
      final top = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTRB(bounds.left - 0.5, bounds.top - 0.5, bounds.right + 0.5, bounds.top + 3.8 * spec.thickness),
          const Radius.circular(1.6),
        ));
      c.drawPath(lens, r.stroke(_alpha(frame, 0.9), 0.8));
      c.drawPath(top, r.fill(frame));
      c.drawPath(top, r.stroke(frameLine, r.lineW * 0.8));
    } else if (spec.rimless) {
      c.drawPath(lens, r.stroke(_alpha(frame, 0.65), 0.7));
    } else {
      c.drawPath(lens, r.stroke(frameLine, frameW + 1.0));
      c.drawPath(lens, r.stroke(frame, frameW));
      if (r.detailed) {
        c.save();
        c.clipRect(Rect.fromLTRB(bounds.left - 4, bounds.top - 4, bounds.right + 4, bounds.center.dy));
        c.drawPath(lens.shift(const Offset(0, -0.3)), r.stroke(_alpha(Colors.white, 0.28), frameW * 0.35));
        c.restore();
      }
    }

    // Sap (kulağa giden çubuk).
    final templeY = bounds.top + bounds.height * 0.24;
    final temple = Path()
      ..moveTo(bounds.left + 0.6, templeY)
      ..lineTo(_cx - r.headX(templeY + 2) - 0.5, templeY + 2.5);
    c.drawPath(temple, r.stroke(spec.rimless ? _alpha(frame, 0.7) : frame, math.max(1.1, frameW * 0.85)));
  });

  // Köprü.
  final bridge = Path()
    ..moveTo(_cx - centerDx + a * 0.96, cy - b * 0.18)
    ..quadraticBezierTo(_cx, cy - b * 0.48, _cx + centerDx - a * 0.96, cy - b * 0.18);
  if (!spec.rimless) canvas.drawPath(bridge, r.stroke(frameLine, math.max(1.0, frameW) + 1.0));
  canvas.drawPath(bridge, r.stroke(spec.rimless ? _alpha(frame, 0.8) : frame, math.max(1.0, frameW)));
}

// ===================================================================== TAKI
void _paintJewelry(Canvas canvas, _Rig r) {
  final spec = r.jewelry;
  if (spec.kind == Jewelry.none) return;
  final col = spec.color;
  final metalLine = _tone(col, -0.5);

  final lobeY = r.earBottom - 1.5;
  final lobe = Offset(_cx - r.headX(lobeY) - 2.5, lobeY);

  void stud(Canvas c, Offset p, double rad, Color color) {
    c.drawCircle(p, rad, r.fill(color));
    c.drawCircle(p, rad, r.stroke(_tone(color, -0.5), r.lineW * 0.7));
    c.drawCircle(p.translate(-rad * 0.3, -rad * 0.3), rad * 0.35, r.fill(_alpha(Colors.white, 0.85)));
  }

  void gem(Canvas c, Offset p, double rad, Color color) {
    final path = Path()
      ..moveTo(p.dx, p.dy - rad * 1.1)
      ..lineTo(p.dx + rad, p.dy - rad * 0.1)
      ..lineTo(p.dx, p.dy + rad * 1.2)
      ..lineTo(p.dx - rad, p.dy - rad * 0.1)
      ..close();
    c.drawPath(path, r.fill(color));
    c.drawLine(p.translate(-rad, -rad * 0.1), p.translate(rad, -rad * 0.1), r.stroke(_alpha(Colors.white, 0.6), 0.5));
    c.drawPath(path, r.stroke(_tone(color, -0.5), r.lineW * 0.7));
  }

  void ring(Canvas c, Offset center, double rad, double w) {
    c.drawCircle(center, rad, r.stroke(metalLine, w + 1.0));
    c.drawCircle(center, rad, r.stroke(col, w));
    c.drawArc(Rect.fromCircle(center: center, radius: rad), math.pi * 1.0, math.pi * 0.45, false, r.stroke(_alpha(Colors.white, 0.7), w * 0.4));
  }

  if (spec.kind != Jewelry.noseStud && spec.kind != Jewelry.cuffs) {
    r.mirrored(canvas, (c, mir) {
      final p = lobe;
      switch (spec.kind) {
        case Jewelry.studs:
        case Jewelry.studsChain:
          stud(c, p, 1.9, col);
          break;
        case Jewelry.pearls:
          stud(c, p.translate(0, 0.8), 2.5, col);
          break;
        case Jewelry.hoops:
        case Jewelry.hoopsChain:
          ring(c, p.translate(-0.4, 5.4), 5.4, 1.3);
          break;
        case Jewelry.bigHoops:
          ring(c, p.translate(-1.2, 9.6), 9.4, 1.5);
          break;
        case Jewelry.drops:
          stud(c, p, 1.5, col);
          c.drawLine(p.translate(0, 1.5), p.translate(-0.2, 6.6), r.stroke(col, 0.8));
          final drop = Path()
            ..moveTo(p.dx - 0.2, p.dy + 6.2)
            ..quadraticBezierTo(p.dx + 3.6, p.dy + 10.4, p.dx - 0.2, p.dy + 14.4)
            ..quadraticBezierTo(p.dx - 4.0, p.dy + 10.4, p.dx - 0.2, p.dy + 6.2)
            ..close();
          c.drawPath(drop, r.fill(col));
          c.drawPath(drop, r.stroke(metalLine, r.lineW * 0.7));
          c.drawCircle(p.translate(-1.2, 10.4), 0.9, r.fill(_alpha(Colors.white, 0.8)));
          break;
        case Jewelry.gems:
          gem(c, p.translate(0, 1.6), 2.8, col);
          break;
        default:
          break;
      }
    });
  }

  if (spec.kind == Jewelry.cuffs) {
    r.mirrored(canvas, (c, mir) {
      final x = _cx - r.headX(r.earTop + 6) - 7.5;
      c.drawArc(Rect.fromCenter(center: Offset(x, r.earTop + 7), width: 7, height: 11), math.pi * 0.6, math.pi * 1.4, false, r.stroke(metalLine, 2.4));
      c.drawArc(Rect.fromCenter(center: Offset(x, r.earTop + 7), width: 7, height: 11), math.pi * 0.6, math.pi * 1.4, false, r.stroke(col, 1.4));
    });
  }

  if (spec.kind == Jewelry.noseStud) {
    stud(canvas, Offset(_cx + r.noseHalf * 0.95, r.noseBaseY - 2.4), 1.1, col);
  }

  if (spec.kind == Jewelry.studsChain || spec.kind == Jewelry.hoopsChain) {
    // İnce zincir kolye ve küçük kolye ucu.
    final by = _neckBaseY(r);
    final chain = Path()
      ..moveTo(_cx - r.neckHalf - 1, by - 4)
      ..quadraticBezierTo(_cx, by + 22, _cx + r.neckHalf + 1, by - 4);
    canvas.drawPath(chain, r.stroke(metalLine, 2.0));
    canvas.drawPath(chain, r.stroke(col, 1.1));
    gem(canvas, Offset(_cx, by + 11.5), 2.6, spec.kind == Jewelry.studsChain ? const Color(0xFFE8455F) : const Color(0xFFF6E9C5));
  }
}
