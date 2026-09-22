part of '../face_avatar_painter.dart';

// ============================================================================
// GÖZLÜK / BAŞLIK / TAKI
// ============================================================================

/// Kumaş/şapka yüzeyini boyar: ışık soldan, gölge sağdan.
void _shadeSolid(Canvas canvas, _Rig r, Path path, Color color, {double gloss = 0.14}) {
  canvas.drawPath(path, r.fill(color));
  final b = path.getBounds();
  canvas.save();
  canvas.clipPath(path);
  canvas.drawRect(
    b,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(b.left, b.top),
        Offset(b.right, b.bottom),
        [_alpha(Colors.white, gloss + 0.06), _alpha(Colors.black, 0.0), _alpha(Colors.black, 0.24)],
        const [0.0, 0.5, 1.0],
      ),
  );
  if (r.detailed) {
    canvas.drawPath(path, r.stroke(_alpha(Colors.black, 0.32), 4, blur: 2.2));
  }
  canvas.restore();
}

/// Şapkanın alnına düşürdüğü gölge (kenarın hemen altında).
void _castHatShadow(Canvas canvas, _Rig r, Path edge, {double strength = 0.42}) {
  if (!r.detailed) return;
  canvas.save();
  canvas.clipPath(r.head);
  canvas.drawPath(edge.shift(const Offset(0, 3.2)), r.stroke(_alpha(r.skinDeep, strength), 6, blur: 3.4));
  canvas.restore();
}

Path _dome(double cx, double topY, double baseY, double hw, {double curve = 3}) {
  return Path()
    ..moveTo(cx - hw, baseY)
    ..cubicTo(cx - hw * 1.02, topY + (baseY - topY) * 0.30, cx - hw * 0.62, topY, cx, topY)
    ..cubicTo(cx + hw * 0.62, topY, cx + hw * 1.02, topY + (baseY - topY) * 0.30, cx + hw, baseY)
    ..quadraticBezierTo(cx, baseY + curve, cx - hw, baseY)
    ..close();
}

// ============================================================ BAŞLIK (ARKA)
void _paintHeadwearBack(Canvas canvas, _Rig r) {
  // Başlıkların tamamı ön katmanda çizilir.
}

// =============================================================== BAŞLIK (ÖN)
void _paintHeadwearFront(Canvas canvas, _Rig r) {
  final spec = r.headwear;
  if (spec.kind == Headwear.none) return;
  final col = spec.color;
  final fh = r.foreheadHalf;

  switch (spec.kind) {
    case Headwear.none:
      return;

    case Headwear.cap:
    case Headwear.capBack:
      final forward = spec.kind == Headwear.cap;
      final dome = _dome(_cx, 17, 62, fh + 8.5, curve: forward ? 3 : 1.5);
      _castHatShadow(canvas, r, Path()..moveTo(_cx - fh - 6, 64)..quadraticBezierTo(_cx, 70, _cx + fh + 6, 64), strength: 0.34);
      _shadeSolid(canvas, r, dome, col);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        // Panel dikişleri.
        final seam = r.stroke(_alpha(Colors.black, 0.28), 0.8);
        canvas.drawPath(Path()..moveTo(_cx, 17)..quadraticBezierTo(_cx - 1, 40, _cx, 62), seam);
        canvas.drawPath(Path()..moveTo(_cx - fh * 0.5, 22)..quadraticBezierTo(_cx - fh * 0.9, 44, _cx - fh * 0.8, 62), seam);
        canvas.drawPath(Path()..moveTo(_cx + fh * 0.5, 22)..quadraticBezierTo(_cx + fh * 0.9, 44, _cx + fh * 0.8, 62), seam);
        canvas.restore();
        canvas.drawCircle(const Offset(_cx, 18), 2.2, r.fill(_tone(col, -0.2)));
      }
      // Alt bant (ter bandı).
      final band = Path()
        ..moveTo(_cx - fh - 8.5, 58)
        ..quadraticBezierTo(_cx, 64, _cx + fh + 8.5, 58)
        ..lineTo(_cx + fh + 8.5, 63)
        ..quadraticBezierTo(_cx, 69, _cx - fh - 8.5, 63)
        ..close();
      _shadeSolid(canvas, r, band, _tone(col, -0.10));
      if (forward) {
        // Siperlik: yüze doğru uzanan elips.
        final bill = Path()
          ..moveTo(_cx - fh - 6, 61)
          ..cubicTo(_cx - fh * 0.8, 78, _cx + fh * 0.8, 78, _cx + fh + 6, 61)
          ..quadraticBezierTo(_cx, 66, _cx - fh - 6, 61)
          ..close();
        _castHatShadow(canvas, r, Path()..moveTo(_cx - fh, 74)..quadraticBezierTo(_cx, 80, _cx + fh, 74), strength: 0.5);
        _shadeSolid(canvas, r, bill, _tone(col, -0.14));
        if (r.detailed) {
          canvas.drawPath(bill, r.stroke(_alpha(Colors.black, 0.35), 0.8));
          canvas.drawOval(Rect.fromCenter(center: const Offset(_cx - 8, 68), width: 14, height: 2.6), r.soft(_alpha(Colors.white, 0.28), 1.4));
        }
      } else {
        // Ters şapka: alında arka ayar kayışı.
        canvas.drawRect(Rect.fromCenter(center: const Offset(_cx, 61), width: 16, height: 5.4), r.fill(_tone(col, -0.22)));
        for (var i = -2; i <= 2; i++) {
          canvas.drawCircle(Offset(_cx + i * 3, 61), 0.6, r.fill(_alpha(Colors.black, 0.5)));
        }
      }
      return;

    case Headwear.beanie:
    case Headwear.beaniePom:
      final dome = _dome(_cx, 15, 56, fh + 7.5, curve: 1);
      _castHatShadow(canvas, r, Path()..moveTo(_cx - fh - 4, 64)..quadraticBezierTo(_cx, 66, _cx + fh + 4, 64), strength: 0.36);
      _shadeSolid(canvas, r, dome, col);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        for (var i = -8; i <= 8; i++) {
          final x = _cx + i * (fh * 0.13);
          canvas.drawPath(
            Path()
              ..moveTo(_cx + (x - _cx) * 0.2, 16)
              ..quadraticBezierTo(x + (x - _cx) * 0.1, 38, x * 1.0 + (x - _cx) * 0.06, 58),
            r.stroke(_alpha(Colors.black, 0.13), 0.9),
          );
        }
        canvas.restore();
      }
      // Kıvrık manşet.
      final cuff = RRect.fromRectAndRadius(Rect.fromLTRB(_cx - fh - 9, 50, _cx + fh + 9, 65), const Radius.circular(4.5));
      _shadeSolid(canvas, r, Path()..addRRect(cuff), _tone(col, -0.06), gloss: 0.10);
      if (r.detailed) {
        canvas.save();
        canvas.clipRRect(cuff);
        for (var i = -12; i <= 12; i++) {
          canvas.drawLine(Offset(_cx + i * 3.5, 50), Offset(_cx + i * 3.5, 65), r.stroke(_alpha(Colors.black, 0.20), 1.0));
        }
        canvas.restore();
      }
      if (spec.kind == Headwear.beaniePom) {
        final pom = Offset(_cx, 12);
        canvas.drawCircle(pom, 8.5, r.fill(_tone(col, 0.06)));
        if (r.detailed) {
          final rng = r.rngFor(701);
          for (var i = 0; i < 40; i++) {
            final a = rng.nextDouble() * math.pi * 2;
            final d = 4 + rng.nextDouble() * 5;
            canvas.drawCircle(pom + Offset(math.cos(a), math.sin(a)) * d, 1.6, r.fill(_alpha(i.isEven ? Colors.white : Colors.black, 0.10)));
          }
          canvas.drawCircle(pom.translate(-2.4, -2.4), 3.6, r.soft(_alpha(Colors.white, 0.35), 2));
        }
      }
      return;

    case Headwear.fedora:
      final crown = Path()
        ..moveTo(_cx - fh - 3, 56)
        ..cubicTo(_cx - fh - 4, 34, _cx - fh * 0.7, 22, _cx - 6, 21)
        ..quadraticBezierTo(_cx, 26, _cx + 6, 21)
        ..cubicTo(_cx + fh * 0.7, 22, _cx + fh + 4, 34, _cx + fh + 3, 56)
        ..close();
      _shadeSolid(canvas, r, crown, col);
      // Kurdele.
      final ribbon = Path()
        ..moveTo(_cx - fh - 3.6, 44)
        ..quadraticBezierTo(_cx, 48, _cx + fh + 3.6, 44)
        ..lineTo(_cx + fh + 3.2, 54)
        ..quadraticBezierTo(_cx, 58, _cx - fh - 3.2, 54)
        ..close();
      _shadeSolid(canvas, r, ribbon, _tone(col, -0.42), gloss: 0.08);
      _castHatShadow(canvas, r, Path()..moveTo(_cx - fh - 10, 66)..quadraticBezierTo(_cx, 72, _cx + fh + 10, 66), strength: 0.5);
      final brim = Path()
        ..addOval(Rect.fromCenter(center: const Offset(_cx, 58), width: (fh + 27) * 2, height: 22));
      _shadeSolid(canvas, r, brim, _tone(col, -0.04), gloss: 0.10);
      if (r.detailed) {
        canvas.drawPath(brim, r.stroke(_alpha(Colors.black, 0.32), 0.9));
        canvas.drawOval(Rect.fromCenter(center: const Offset(_cx - 10, 62), width: 40, height: 5), r.soft(_alpha(Colors.white, 0.22), 2.2));
      }
      return;

    case Headwear.flatCap:
      final dome = Path()
        ..moveTo(_cx - fh - 9, 62)
        ..cubicTo(_cx - fh - 13, 40, _cx - fh * 0.5, 26, _cx + fh * 0.2, 30)
        ..cubicTo(_cx + fh + 8, 32, _cx + fh + 14, 46, _cx + fh + 9, 62)
        ..quadraticBezierTo(_cx, 68, _cx - fh - 9, 62)
        ..close();
      _castHatShadow(canvas, r, Path()..moveTo(_cx - fh - 4, 66)..quadraticBezierTo(_cx, 72, _cx + fh + 4, 66), strength: 0.36);
      _shadeSolid(canvas, r, dome, col);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        final rng = r.rngFor(702);
        for (var i = 0; i < 90; i++) {
          final p = Offset(_cx - fh - 12 + rng.nextDouble() * (fh * 2 + 24), 28 + rng.nextDouble() * 40);
          canvas.drawLine(p, p.translate(2.2, 1.0), r.stroke(_alpha(rng.nextBool() ? Colors.white : Colors.black, 0.12), 0.6));
        }
        canvas.restore();
      }
      final bill = Path()
        ..moveTo(_cx - fh - 6, 62)
        ..quadraticBezierTo(_cx, 76, _cx + fh + 6, 62)
        ..quadraticBezierTo(_cx, 66, _cx - fh - 6, 62)
        ..close();
      _shadeSolid(canvas, r, bill, _tone(col, -0.18));
      canvas.drawCircle(Offset(_cx, 30), 2, r.fill(_tone(col, -0.2)));
      return;

    case Headwear.sunHat:
      final crown = _dome(_cx, 14, 54, fh + 4, curve: 0);
      _shadeSolid(canvas, r, crown, col, gloss: 0.16);
      final ribbon = Path()
        ..moveTo(_cx - fh - 4, 44)
        ..quadraticBezierTo(_cx, 50, _cx + fh + 4, 44)
        ..lineTo(_cx + fh + 4, 52)
        ..quadraticBezierTo(_cx, 58, _cx - fh - 4, 52)
        ..close();
      _shadeSolid(canvas, r, ribbon, const Color(0xFFB5443A), gloss: 0.10);
      _castHatShadow(canvas, r, Path()..moveTo(_cx - fh - 14, 68)..quadraticBezierTo(_cx, 76, _cx + fh + 14, 68), strength: 0.5);
      final brim = Path()..addOval(Rect.fromCenter(center: const Offset(_cx, 60), width: (fh + 46) * 2, height: 32));
      _shadeSolid(canvas, r, brim, _tone(col, 0.02), gloss: 0.16);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(brim);
        for (var i = 1; i < 8; i++) {
          canvas.drawOval(
            Rect.fromCenter(center: const Offset(_cx, 60), width: (fh + 46) * 2 * (i / 8), height: 32 * (i / 8)),
            r.stroke(_alpha(Colors.black, 0.14), 0.7),
          );
        }
        canvas.restore();
        canvas.drawPath(brim, r.stroke(_alpha(Colors.black, 0.28), 0.9));
        // Ön kenarın koyu gölgesi (elips önden bakışta üst yarım kenar).
        canvas.drawOval(Rect.fromCenter(center: const Offset(_cx, 56), width: (fh + 40) * 2, height: 18), r.soft(_alpha(Colors.black, 0.12), 3));
      }
      return;

    case Headwear.headband:
      final pts = <Offset>[];
      for (var i = 0; i <= 18; i++) {
        final a = math.pi * (1 - i / 18);
        pts.add(Offset(_cx + math.cos(a) * (fh + 3.5), 66 - math.sin(a) * 27));
      }
      final band = _ribbon(pts, 6.8, 7.4, 6.8);
      _shadeSolid(canvas, r, band, col, gloss: 0.12);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(band);
        for (var i = 0; i < 18; i++) {
          final p = pts[i];
          canvas.drawLine(p.translate(-1.5, 3), p.translate(1.5, -3), r.stroke(_alpha(Colors.white, 0.18), 0.6));
        }
        canvas.restore();
      }
      return;

    case Headwear.bandana:
      _paintBandanaBand(canvas, r, col);
      return;

    case Headwear.headphones:
      final arcPts = <Offset>[];
      final hw = r.cheekHalf + 8;
      for (var i = 0; i <= 20; i++) {
        final a = math.pi * (1 - i / 20);
        arcPts.add(Offset(_cx + math.cos(a) * hw, 92 - math.sin(a) * 66));
      }
      final band = _ribbon(arcPts, 4.6, 4.2, 4.6);
      _shadeSolid(canvas, r, band, _tone(col, -0.05), gloss: 0.16);
      r.mirrored(canvas, (c, mir) {
        final cup = Rect.fromCenter(center: Offset(_cx - hw + 0.5, 92), width: 13, height: 24);
        c.drawRRect(RRect.fromRectAndRadius(cup, const Radius.circular(6)), r.fill(_tone(col, mir ? -0.18 : -0.04)));
        c.drawRRect(RRect.fromRectAndRadius(cup.deflate(2.2), const Radius.circular(4)), r.fill(_tone(col, mir ? -0.28 : -0.14)));
        if (r.detailed) {
          c.drawOval(Rect.fromCenter(center: Offset(_cx - hw - 1.2, 84), width: 3.4, height: 9), r.soft(_alpha(Colors.white, mir ? 0.12 : 0.30), 1.2));
          c.drawRRect(RRect.fromRectAndRadius(cup, const Radius.circular(6)), r.stroke(_alpha(Colors.black, 0.4), 0.8));
        }
      });
      return;

    case Headwear.flowerCrown:
      final rng = r.rngFor(703);
      final colors = <Color>[col, const Color(0xFFF6E7A8), const Color(0xFFFFFFFF), const Color(0xFFD9578A), const Color(0xFFB08AD8)];
      // Yapraklar
      for (var i = 0; i < 18; i++) {
        final a = math.pi * (1 - i / 17);
        final p = Offset(_cx + math.cos(a) * (fh + 4), 64 - math.sin(a) * 30);
        canvas.drawOval(Rect.fromCenter(center: p, width: 9, height: 4), r.fill(const Color(0xFF4F8A55)));
      }
      for (var i = 0; i < 9; i++) {
        final a = math.pi * (1 - (i + 0.5) / 9);
        final p = Offset(_cx + math.cos(a) * (fh + 4), 64 - math.sin(a) * 30);
        final fc = colors[i % colors.length];
        final rad = 4.6 + rng.nextDouble() * 1.6;
        for (var k = 0; k < 5; k++) {
          final pa = k * math.pi * 2 / 5 + rng.nextDouble() * 0.3;
          canvas.drawCircle(p + Offset(math.cos(pa), math.sin(pa)) * rad * 0.62, rad * 0.55, r.fill(fc));
          if (r.detailed) canvas.drawCircle(p + Offset(math.cos(pa), math.sin(pa)) * rad * 0.62, rad * 0.55, r.stroke(_alpha(Colors.black, 0.14), 0.4));
        }
        canvas.drawCircle(p, rad * 0.36, r.fill(const Color(0xFFE8B23C)));
      }
      return;

    case Headwear.tiara:
      final pts = <Offset>[];
      for (var i = 0; i <= 18; i++) {
        final a = math.pi * (1 - i / 18);
        pts.add(Offset(_cx + math.cos(a) * (fh + 2), 60 - math.sin(a) * 28));
      }
      final band = _ribbon(pts, 2.4, 2.4, 2.4);
      _shadeSolid(canvas, r, band, col, gloss: 0.3);
      // Ortada sivri parça ve taşlar.
      final peak = Path()
        ..moveTo(_cx - 9, 34)
        ..lineTo(_cx - 3, 22)
        ..lineTo(_cx, 30)
        ..lineTo(_cx + 3, 22)
        ..lineTo(_cx + 9, 34)
        ..close();
      _shadeSolid(canvas, r, peak, col, gloss: 0.3);
      canvas.drawCircle(const Offset(_cx, 31), 2.2, r.fill(const Color(0xFF6FB8E8)));
      canvas.drawCircle(const Offset(_cx - 3, 25), 1.2, r.fill(const Color(0xFFFFFFFF)));
      canvas.drawCircle(const Offset(_cx + 3, 25), 1.2, r.fill(const Color(0xFFFFFFFF)));
      return;

    case Headwear.bow:
      final c0 = Offset(_cx + 24, 32);
      for (final s in [-1.0, 1.0]) {
        final loop = Path()
          ..moveTo(c0.dx, c0.dy)
          ..cubicTo(c0.dx + s * 8, c0.dy - 12, c0.dx + s * 20, c0.dy - 9, c0.dx + s * 18, c0.dy + 1)
          ..cubicTo(c0.dx + s * 20, c0.dy + 10, c0.dx + s * 8, c0.dy + 13, c0.dx, c0.dy)
          ..close();
        _shadeSolid(canvas, r, loop, col, gloss: 0.18);
        if (r.detailed) canvas.drawPath(loop, r.stroke(_alpha(Colors.black, 0.24), 0.7));
      }
      canvas.drawOval(Rect.fromCenter(center: c0, width: 8, height: 10), r.fill(_tone(col, -0.14)));
      if (r.detailed) canvas.drawOval(Rect.fromCenter(center: c0.translate(-1, -1.4), width: 3, height: 3.6), r.soft(_alpha(Colors.white, 0.4), 0.8));
      return;

    case Headwear.clips:
      r.mirrored(canvas, (c, mir) {
        if (mir) return;
        for (var i = 0; i < 3; i++) {
          final p = Offset(_cx - 30 + i * 2, 56 + i * 7.5);
          c.save();
          c.translate(p.dx, p.dy);
          c.rotate(-0.5);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: 11, height: 3.2), const Radius.circular(1.6)), r.fill(col));
          if (r.detailed) c.drawLine(const Offset(-4, -0.4), const Offset(3, -0.4), r.stroke(_alpha(Colors.white, 0.5), 0.6));
          c.restore();
        }
      });
      return;

    case Headwear.visor:
      final band = Path()
        ..moveTo(_cx - fh - 6, 60)
        ..quadraticBezierTo(_cx, 66, _cx + fh + 6, 60)
        ..lineTo(_cx + fh + 6, 65)
        ..quadraticBezierTo(_cx, 71, _cx - fh - 6, 65)
        ..close();
      _shadeSolid(canvas, r, band, _tone(col, -0.08));
      final bill = Path()
        ..moveTo(_cx - fh - 5, 63)
        ..cubicTo(_cx - fh * 0.8, 80, _cx + fh * 0.8, 80, _cx + fh + 5, 63)
        ..quadraticBezierTo(_cx, 68, _cx - fh - 5, 63)
        ..close();
      _castHatShadow(canvas, r, Path()..moveTo(_cx - fh, 76)..quadraticBezierTo(_cx, 82, _cx + fh, 76), strength: 0.45);
      _shadeSolid(canvas, r, bill, col);
      return;

    case Headwear.turbanWrap:
      _paintTurban(canvas, r, col);
      return;

    case Headwear.hood:
      final cw = r.cheekHalf;
      final outer = _spline([
        Offset(_cx, 18),
        Offset(_cx + fh * 0.62, 21),
        Offset(_cx + fh + 12, 44),
        Offset(_cx + cw + 14, 80),
        Offset(_cx + cw + 15, 112),
        Offset(_cx + cw + 17, 140),
        Offset(_cx + cw + 20, 160),
        Offset(_cx, 170),
        Offset(_cx - cw - 20, 160),
        Offset(_cx - cw - 17, 140),
        Offset(_cx - cw - 15, 112),
        Offset(_cx - cw - 14, 80),
        Offset(_cx - fh - 12, 44),
        Offset(_cx - fh * 0.62, 21),
      ], closed: true);
      final opening = _faceOpening(r, top: 55, side: 1.05, chinExtra: 4);
      final fabric = Path.combine(PathOperation.difference, outer, opening);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(r.head);
        canvas.drawPath(opening, r.stroke(_alpha(r.skinDeep, 0.6), 6, blur: 3.4));
        canvas.restore();
      }
      _shadeSolid(canvas, r, fabric, col);
      // İç astar: açıklık kenarında açık şerit.
      canvas.drawPath(opening, r.stroke(_tone(col, 0.22), 3.0));
      canvas.drawPath(opening, r.stroke(_alpha(Colors.black, 0.30), 0.9));
      return;
  }
}

/// Alından geçen bandana bandı + yandan düğüm (başlık olarak).
void _paintBandanaBand(Canvas canvas, _Rig r, Color cloth) {
  final fh = r.foreheadHalf;
  final band = Path()
    ..moveTo(_cx - fh - 4, 68)
    ..quadraticBezierTo(_cx, 38, _cx + fh + 4, 68)
    ..lineTo(_cx + fh + 3, 59)
    ..quadraticBezierTo(_cx, 26, _cx - fh - 3, 59)
    ..close();
  _shadeSolid(canvas, r, band, cloth);
  if (r.detailed) {
    canvas.save();
    canvas.clipPath(band);
    final rng = r.rngFor(704);
    for (var i = 0; i < 26; i++) {
      canvas.drawCircle(
        Offset(_cx - fh + rng.nextDouble() * fh * 2, 34 + rng.nextDouble() * 34),
        0.9,
        r.fill(_alpha(Colors.white, 0.6)),
      );
    }
    canvas.restore();
  }
  final knot = Offset(_cx + fh + 2, 63);
  canvas.drawCircle(knot, 4.6, r.fill(_tone(cloth, -0.08)));
  final tail = Path()
    ..moveTo(knot.dx, knot.dy)
    ..quadraticBezierTo(knot.dx + 10, knot.dy + 4, knot.dx + 14, knot.dy + 16)
    ..lineTo(knot.dx + 6, knot.dy + 12)
    ..quadraticBezierTo(knot.dx + 4, knot.dy + 6, knot.dx - 1, knot.dy + 3)
    ..close();
  canvas.drawPath(tail, r.fill(_tone(cloth, -0.14)));
}

// ================================================================== GÖZLÜK
/// Sol göz (ekranda solda) için mercek yolu; iç taraf +x.
Path _lensPath(GlassesShape shape, Offset c, double a, double b) {
  switch (shape) {
    case GlassesShape.none:
      return Path();
    case GlassesShape.rect:
      return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: a * 2, height: b * 2 * 0.86), const Radius.circular(3.4)));
    case GlassesShape.square:
      return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: a * 2 * 0.95, height: b * 2 * 1.02), const Radius.circular(2.6)));
    case GlassesShape.round:
      return Path()..addOval(Rect.fromCenter(center: c, width: b * 2.4, height: b * 2.4));
    case GlassesShape.oval:
      return Path()..addOval(Rect.fromCenter(center: c, width: a * 2, height: b * 2 * 0.86));
    case GlassesShape.cat:
      return _spline([
        Offset(c.dx - a * 1.08, c.dy - b * 1.02),
        Offset(c.dx - a * 0.2, c.dy - b * 0.72),
        Offset(c.dx + a * 0.75, c.dy - b * 0.5),
        Offset(c.dx + a * 0.72, c.dy + b * 0.55),
        Offset(c.dx - a * 0.1, c.dy + b * 0.92),
        Offset(c.dx - a * 0.92, c.dy + b * 0.28),
      ], closed: true);
    case GlassesShape.aviator:
      return _spline([
        Offset(c.dx - a * 0.98, c.dy - b * 0.82),
        Offset(c.dx, c.dy - b * 0.9),
        Offset(c.dx + a * 0.98, c.dy - b * 0.78),
        Offset(c.dx + a * 0.86, c.dy + b * 0.32),
        Offset(c.dx + a * 0.15, c.dy + b * 1.1),
        Offset(c.dx - a * 0.7, c.dy + b * 0.85),
        Offset(c.dx - a * 1.0, c.dy + b * 0.05),
      ], closed: true);
    case GlassesShape.wayfarer:
      return _spline([
        Offset(c.dx - a * 1.04, c.dy - b * 0.86),
        Offset(c.dx, c.dy - b * 0.94),
        Offset(c.dx + a * 1.0, c.dy - b * 0.96),
        Offset(c.dx + a * 0.86, c.dy + b * 0.5),
        Offset(c.dx + a * 0.1, c.dy + b * 0.86),
        Offset(c.dx - a * 0.86, c.dy + b * 0.66),
      ], closed: true, tension: 0.7);
    case GlassesShape.browline:
      return Path()..addRRect(RRect.fromLTRBAndCorners(c.dx - a, c.dy - b * 0.8, c.dx + a, c.dy + b * 0.85, topLeft: const Radius.circular(1.6), topRight: const Radius.circular(1.6), bottomLeft: Radius.circular(b * 0.9), bottomRight: Radius.circular(b * 0.9)));
    case GlassesShape.hexagon:
      final pts = <Offset>[];
      for (var i = 0; i < 6; i++) {
        final ang = math.pi / 6 + i * math.pi / 3 - math.pi / 2;
        pts.add(Offset(c.dx + math.cos(ang) * a * 0.98, c.dy + math.sin(ang) * b * 1.05));
      }
      return Path()..addPolygon(pts, true);
    case GlassesShape.wrap:
      return _spline([
        Offset(c.dx - a * 1.12, c.dy - b * 0.55),
        Offset(c.dx, c.dy - b * 0.92),
        Offset(c.dx + a * 1.02, c.dy - b * 0.7),
        Offset(c.dx + a * 0.95, c.dy + b * 0.5),
        Offset(c.dx, c.dy + b * 0.82),
        Offset(c.dx - a * 1.1, c.dy + b * 0.3),
      ], closed: true);
    case GlassesShape.halfMoon:
      return Path()
        ..moveTo(c.dx - a * 0.95, c.dy - b * 0.35)
        ..lineTo(c.dx + a * 0.95, c.dy - b * 0.35)
        ..quadraticBezierTo(c.dx + a * 0.9, c.dy + b * 1.0, c.dx, c.dy + b * 0.95)
        ..quadraticBezierTo(c.dx - a * 0.9, c.dy + b * 1.0, c.dx - a * 0.95, c.dy - b * 0.35)
        ..close();
  }
}

void _paintGlasses(Canvas canvas, _Rig r) {
  final spec = r.glasses;
  if (spec.shape == GlassesShape.none) return;

  final a = r.eyeW * 1.5; // yarı genişlik
  final b = r.eyeH * 2.15; // yarı yükseklik
  final centerDx = r.eyeDx * 1.0;
  final cy = _Rig.eyeY + 0.6;
  final frameW = 1.15 * spec.thickness + (spec.rimless ? -0.4 : 0);

  // Camın yüze düşürdüğü ince gölge.
  if (r.detailed) {
    r.mirrored(canvas, (c, mir) {
      final lens = _lensPath(spec.shape, Offset(_cx - centerDx, cy), a, b);
      c.drawPath(lens.shift(const Offset(0.8, 2.4)), r.soft(_alpha(r.skinDeep, 0.26), 1.7));
    });
  }

  r.mirrored(canvas, (c, mir) {
    final center = Offset(_cx - centerDx, cy);
    final lens = _lensPath(spec.shape, center, a, b);
    final bounds = lens.getBounds();

    // Mercek.
    if (spec.sun) {
      c.drawPath(
        lens,
        Paint()
          ..shader = ui.Gradient.linear(
            bounds.topCenter,
            bounds.bottomCenter,
            [const Color(0xF0101418), const Color(0xC81E242C)],
          ),
      );
    } else {
      c.drawPath(lens, r.fill(spec.tint));
    }
    if (r.detailed) {
      c.save();
      c.clipPath(lens);
      // Çapraz yansıma parlaması (ışık soldan: aynada sağa kayar).
      final glare = Path()
        ..moveTo(bounds.left + bounds.width * (mir ? 0.42 : 0.18), bounds.bottom)
        ..lineTo(bounds.left + bounds.width * (mir ? 0.58 : 0.34), bounds.bottom)
        ..lineTo(bounds.left + bounds.width * (mir ? 0.86 : 0.62), bounds.top)
        ..lineTo(bounds.left + bounds.width * (mir ? 0.72 : 0.48), bounds.top)
        ..close();
      c.drawPath(glare, r.fill(_alpha(Colors.white, spec.sun ? 0.18 : 0.13)));
      c.drawRect(
        bounds,
        Paint()
          ..shader = ui.Gradient.linear(
            bounds.topLeft,
            bounds.bottomRight,
            [_alpha(Colors.white, spec.sun ? 0.14 : 0.08), _alpha(Colors.white, 0.0)],
          ),
      );
      c.restore();
    }

    // Çerçeve.
    if (spec.shape == GlassesShape.browline) {
      // Üst kalın çubuk + alt ince tel.
      final top = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTRB(bounds.left - 0.4, bounds.top, bounds.right + 0.4, bounds.top + 3.6 * spec.thickness),
          const Radius.circular(1.4),
        ));
      c.drawPath(top, r.fill(spec.frame));
      c.drawPath(lens, r.stroke(_alpha(spec.frame, 0.85), 0.7));
    } else if (spec.rimless) {
      c.drawPath(lens, r.stroke(_alpha(spec.frame, 0.55), 0.6));
    } else {
      c.drawPath(lens, r.stroke(spec.frame, frameW, cap: StrokeCap.round));
      if (r.detailed && spec.thickness > 1.3) {
        c.drawPath(lens, r.stroke(_alpha(Colors.white, 0.20), 0.5));
      }
    }

    // Sap (kulağa giden çubuk).
    final temple = Path()
      ..moveTo(bounds.left + 0.5, bounds.top + bounds.height * 0.28)
      ..lineTo(_cx - r.cheekHalf - 0.4, _Rig.eyeY - 2.6);
    c.drawPath(temple, r.stroke(spec.rimless ? _alpha(spec.frame, 0.6) : spec.frame, math.max(0.9, frameW * 0.8)));
  });

  // Köprü.
  final bridge = Path()
    ..moveTo(_cx - centerDx + a * 0.98, cy - b * 0.2)
    ..quadraticBezierTo(_cx, cy - b * 0.5, _cx + centerDx - a * 0.98, cy - b * 0.2);
  canvas.drawPath(bridge, r.stroke(spec.rimless ? _alpha(spec.frame, 0.7) : spec.frame, math.max(1.0, frameW)));
  // Burun pedleri.
  r.mirrored(canvas, (c, mir) {
    c.drawCircle(Offset(_cx - 4.4, cy + b * 0.42), 0.9, r.fill(_alpha(Colors.white, 0.5)));
  });
}

// ===================================================================== TAKI
void _paintJewelry(Canvas canvas, _Rig r) {
  final spec = r.jewelry;
  if (spec.kind == Jewelry.none) return;
  final col = spec.color;
  final cw = r.cheekHalf;
  final metal = _tone(col, 0.0);

  Offset lobe(bool left) => Offset(_cx + (left ? -1 : 1) * (cw - 0.9), 109.0);

  void stud(Canvas c, Offset p, double rad, Color color) {
    c.drawCircle(p, rad, r.fill(color));
    if (r.detailed) {
      c.drawCircle(p.translate(-rad * 0.3, -rad * 0.3), rad * 0.45, r.fill(_alpha(Colors.white, 0.75)));
      c.drawCircle(p, rad, r.stroke(_alpha(Colors.black, 0.25), 0.4));
    }
  }

  void gem(Canvas c, Offset p, double rad, Color color) {
    final path = Path()
      ..moveTo(p.dx, p.dy - rad * 1.1)
      ..lineTo(p.dx + rad, p.dy - rad * 0.1)
      ..lineTo(p.dx, p.dy + rad * 1.2)
      ..lineTo(p.dx - rad, p.dy - rad * 0.1)
      ..close();
    c.drawPath(path, r.fill(color));
    if (r.detailed) {
      c.drawLine(p.translate(-rad, -rad * 0.1), p.translate(rad, -rad * 0.1), r.stroke(_alpha(Colors.white, 0.6), 0.4));
      c.drawLine(p.translate(0, -rad * 1.1), p.translate(0, rad * 1.2), r.stroke(_alpha(Colors.white, 0.35), 0.4));
      c.drawPath(path, r.stroke(_alpha(Colors.black, 0.3), 0.4));
    }
  }

  if (spec.kind != Jewelry.noseStud && spec.kind != Jewelry.cuffs) {
    r.mirrored(canvas, (c, mir) {
      final p = lobe(true);
      switch (spec.kind) {
        case Jewelry.studs:
        case Jewelry.studsChain:
          stud(c, p, 1.7, metal);
          break;
        case Jewelry.pearls:
          c.drawCircle(p.translate(0, 0.6), 2.3, r.fill(col));
          if (r.detailed) {
            c.drawCircle(p.translate(-0.7, -0.2), 0.9, r.fill(_alpha(Colors.white, 0.85)));
            c.drawCircle(p.translate(0, 0.6), 2.3, r.stroke(_alpha(Colors.black, 0.18), 0.4));
          }
          break;
        case Jewelry.hoops:
        case Jewelry.hoopsChain:
          c.drawCircle(p.translate(-0.4, 5.2), 5.6, r.stroke(metal, 1.3));
          if (r.detailed) c.drawArc(Rect.fromCircle(center: p.translate(-0.4, 5.2), radius: 5.6), math.pi * 1.05, math.pi * 0.5, false, r.stroke(_alpha(Colors.white, 0.6), 0.6));
          break;
        case Jewelry.bigHoops:
          c.drawCircle(p.translate(-1.2, 9.4), 9.6, r.stroke(metal, 1.5));
          if (r.detailed) c.drawArc(Rect.fromCircle(center: p.translate(-1.2, 9.4), radius: 9.6), math.pi * 1.0, math.pi * 0.5, false, r.stroke(_alpha(Colors.white, 0.6), 0.7));
          break;
        case Jewelry.drops:
          stud(c, p, 1.4, metal);
          c.drawLine(p.translate(0, 1.4), p.translate(-0.2, 7), r.stroke(metal, 0.6));
          final drop = Path()
            ..moveTo(p.dx - 0.2, p.dy + 6.4)
            ..quadraticBezierTo(p.dx + 3.4, p.dy + 10.4, p.dx - 0.2, p.dy + 14.4)
            ..quadraticBezierTo(p.dx - 3.8, p.dy + 10.4, p.dx - 0.2, p.dy + 6.4)
            ..close();
          c.drawPath(drop, r.fill(metal));
          if (r.detailed) c.drawCircle(p.translate(-1.2, 10.6), 0.9, r.fill(_alpha(Colors.white, 0.7)));
          break;
        case Jewelry.gems:
          gem(c, p.translate(0, 1.4), 2.6, col);
          break;
        default:
          break;
      }
    });
  }

  if (spec.kind == Jewelry.cuffs) {
    r.mirrored(canvas, (c, mir) {
      c.drawArc(Rect.fromCenter(center: Offset(_cx - cw - 1.6, 92), width: 7, height: 12), math.pi * 0.7, math.pi * 1.5, false, r.stroke(metal, 1.4));
    });
  }

  if (spec.kind == Jewelry.noseStud) {
    final p = Offset(_cx + r.noseHalf * 1.02, r.noseBaseY - 2.6);
    stud(canvas, p, 1.0, col);
    if (r.detailed) canvas.drawCircle(p, 2.6, r.soft(_alpha(Colors.white, 0.25), 1.2));
  }

  if (spec.kind == Jewelry.studsChain || spec.kind == Jewelry.hoopsChain) {
    // İnce zincir kolye ve küçük kolye ucu.
    final chain = Path()
      ..moveTo(_cx - 15, 146 + _bodyDrop)
      ..quadraticBezierTo(_cx, 176 + _bodyDrop, _cx + 15, 146 + _bodyDrop);
    canvas.drawPath(chain, r.stroke(metal, 1.0));
    if (r.detailed) canvas.drawPath(chain.shift(const Offset(0, -0.6)), r.stroke(_alpha(Colors.white, 0.4), 0.4));
    gem(canvas, Offset(_cx, 164 + _bodyDrop), 2.4, spec.kind == Jewelry.studsChain ? const Color(0xFFE8455F) : const Color(0xFFF6E9C5));
  }
}
