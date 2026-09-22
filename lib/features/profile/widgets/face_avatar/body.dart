part of '../face_avatar_painter.dart';

// ------------------------------------------------------------------ arka plan
void _paintBackground(Canvas canvas, _Rig r) {
  const rect = Rect.fromLTWH(0, 0, 200, 200);
  final spec = r.cfg.backgroundSpec;
  final top = r.background ?? spec.top;
  final bottom = r.background ?? spec.bottom;

  canvas.drawRect(
    rect,
    Paint()..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(0, 200), [top, bottom]),
  );
  if (!r.detailed) return;

  // Kafanın arkasında yumuşak ışık (stüdyo portresi hissi).
  canvas.drawCircle(
    const Offset(100, 82),
    92,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(94, 70),
        100,
        [Colors.white.withValues(alpha: 0.42), Colors.white.withValues(alpha: 0.0)],
      ),
  );
  // Hafif bokeh daireleri: derinlik verir, yüzle yarışmaz.
  final rng = r.rngFor(4242 + r.cfg.background);
  for (var i = 0; i < 7; i++) {
    final x = rng.nextDouble() * 200;
    final y = 12 + rng.nextDouble() * 120;
    final rad = 6 + rng.nextDouble() * 14;
    canvas.drawCircle(
      Offset(x, y),
      rad,
      r.soft(Colors.white.withValues(alpha: 0.10 + rng.nextDouble() * 0.10), 1.6),
    );
  }
  // Kenarlarda hafif vinyet.
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(100, 100),
        150,
        [Colors.black.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.16)],
        const [0.55, 1.0],
      ),
  );
}

// ---------------------------------------------------------------- omuz/boyun
Path _torsoPath(_Rig r) {
  final nh = r.neckHalf;
  return Path()
    ..moveTo(_cx - nh, 100)
    ..lineTo(_cx - nh - 0.4, 136)
    ..cubicTo(_cx - nh - 1, 148, _cx - nh - 9, 154, _cx - 42, 159)
    ..cubicTo(_cx - 68, 163, _cx - 92, 176, _cx - 104, 216)
    ..lineTo(_cx + 104, 216)
    ..cubicTo(_cx + 92, 176, _cx + 68, 163, _cx + 42, 159)
    ..cubicTo(_cx + nh + 9, 154, _cx + nh + 1, 148, _cx + nh + 0.4, 136)
    ..lineTo(_cx + nh, 100)
    ..close();
}

/// Omuz/kıyafet, çene ile arasında görünür bir boyun kalsın diye aşağı kaydırılır.
const double _bodyDrop = 7;

void _paintTorso(Canvas canvas, _Rig r) {
  canvas.save();
  canvas.translate(0, _bodyDrop);
  _paintTorsoInner(canvas, r);
  canvas.restore();
}

void _paintTorsoInner(Canvas canvas, _Rig r) {
  final torso = _torsoPath(r);
  final base = _mix(r.skin, r.skinShadow, 0.30);
  canvas.drawPath(torso, r.fill(base));
  if (!r.detailed) return;

  canvas.save();
  canvas.clipPath(torso);

  // Boyunun yan tarafları: sternokleidomastoid kasının yumuşak hattı.
  final nh = r.neckHalf;
  r.mirrored(canvas, (c, mir) {
    final path = Path()
      ..moveTo(_cx - nh + 1.5, 118)
      ..cubicTo(_cx - nh + 3, 132, _cx - nh + 6, 146, _cx - 10, 158)
      ..lineTo(_cx - 5, 158)
      ..cubicTo(_cx - nh + 6, 144, _cx - nh + 5, 130, _cx - nh + 5, 118)
      ..close();
    c.drawPath(path, r.soft(_alpha(r.skinDeep, mir ? 0.30 : 0.16), 2.4));
  });
  // Sağ (gölge) taraf biraz daha koyu.
  canvas.drawRect(
    Rect.fromLTWH(_cx, 100, 60, 110),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(_cx, 0),
        const Offset(_cx + 46, 0),
        [_alpha(r.skinDeep, 0.0), _alpha(r.skinDeep, 0.22)],
      ),
  );
  // Çenenin boyuna düşen gölgesi.
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx, r.chinY - _bodyDrop + 5), width: r.jawHalf * 2.2, height: 30),
    r.soft(_alpha(r.skinDeep, 0.72), 7),
  );
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx, r.chinY - _bodyDrop + 12), width: r.jawHalf * 1.7, height: 22),
    r.soft(_alpha(r.skinDeep, 0.35), 5),
  );
  // Köprücük kemikleri (açık yakalarda görünür).
  final clavicle = r.stroke(_alpha(r.skinLight, 0.55), 2.0, blur: 1.3);
  final clavShadow = r.stroke(_alpha(r.skinDeep, 0.30), 1.4, blur: 1.2);
  r.mirrored(canvas, (c, mir) {
    final p = Path()
      ..moveTo(_cx - 6, 163)
      ..quadraticBezierTo(_cx - 20, 160, _cx - 40, 165);
    c.drawPath(p.shift(const Offset(0, 1.6)), clavShadow);
    c.drawPath(p, clavicle);
  });
  canvas.restore();
}

// ------------------------------------------------------------------ kıyafet
/// Yaka boşluğu (cildin göründüğü bölge). Kıyafet bu boşluğu bırakarak çizilir.
class _Neckline {
  final Path hole;
  final double halfTop;
  const _Neckline(this.hole, this.halfTop);
}

_Neckline _neckline(_Rig r, ClothingKind kind) {
  final nh = r.neckHalf;
  Path crew(double l, double depth) => Path()
    ..moveTo(_cx - l, 138)
    ..lineTo(_cx - l, 148)
    ..cubicTo(_cx - l, 148 + depth * 0.6, _cx - l * 0.55, 148 + depth, _cx, 148 + depth)
    ..cubicTo(_cx + l * 0.55, 148 + depth, _cx + l, 148 + depth * 0.6, _cx + l, 148)
    ..lineTo(_cx + l, 138)
    ..close();

  switch (kind) {
    case ClothingKind.crew:
      return _Neckline(crew(nh + 3.5, 14), nh + 3.5);
    case ClothingKind.vneck:
      final p = Path()
        ..moveTo(_cx - nh - 3, 138)
        ..lineTo(_cx - nh - 3, 148)
        ..quadraticBezierTo(_cx - 6, 165, _cx, 186)
        ..quadraticBezierTo(_cx + 6, 165, _cx + nh + 3, 148)
        ..lineTo(_cx + nh + 3, 138)
        ..close();
      return _Neckline(p, nh + 3);
    case ClothingKind.scoop:
      return _Neckline(crew(nh + 16, 28), nh + 16);
    case ClothingKind.tank:
      return _Neckline(crew(nh + 24, 36), nh + 24);
    case ClothingKind.polo:
    case ClothingKind.henley:
      return _Neckline(crew(nh + 3.5, 13), nh + 3.5);
    case ClothingKind.hoodie:
      return _Neckline(crew(nh + 5, 12), nh + 5);
    case ClothingKind.sweater:
      return _Neckline(crew(nh + 4, 12), nh + 4);
    case ClothingKind.turtleneck:
      return _Neckline(crew(nh + 1, 6), nh + 1);
    case ClothingKind.blazer:
      final p = Path()
        ..moveTo(_cx - nh - 2, 138)
        ..lineTo(_cx - nh - 2, 148)
        ..lineTo(_cx, 188)
        ..lineTo(_cx + nh + 2, 148)
        ..lineTo(_cx + nh + 2, 138)
        ..close();
      return _Neckline(p, nh + 2);
    case ClothingKind.shirtTie:
      final p = Path()
        ..moveTo(_cx - nh - 2.5, 138)
        ..lineTo(_cx - nh - 2.5, 148)
        ..lineTo(_cx, 168)
        ..lineTo(_cx + nh + 2.5, 148)
        ..lineTo(_cx + nh + 2.5, 138)
        ..close();
      return _Neckline(p, nh + 2.5);
    case ClothingKind.bomber:
      return _Neckline(crew(nh + 4, 10), nh + 4);
  }
}

Path _garmentPath(ClothingKind kind) {
  if (kind == ClothingKind.tank) {
    // Askılı: omuzlar açık.
    return Path()
      ..moveTo(_cx - 66, 202)
      ..cubicTo(_cx - 66, 190, _cx - 54, 178, _cx - 46, 166)
      ..lineTo(_cx - 38, 152)
      ..lineTo(_cx + 38, 152)
      ..lineTo(_cx + 46, 166)
      ..cubicTo(_cx + 54, 178, _cx + 66, 190, _cx + 66, 202)
      ..close();
  }
  return Path()
    ..moveTo(_cx - 105, 216)
    ..cubicTo(_cx - 99, 176, _cx - 74, 164, _cx - 44, 159)
    ..cubicTo(_cx - 30, 156.5, _cx - 20, 152, _cx - 16, 146)
    ..lineTo(_cx + 16, 146)
    ..cubicTo(_cx + 20, 152, _cx + 30, 156.5, _cx + 44, 159)
    ..cubicTo(_cx + 74, 164, _cx + 99, 176, _cx + 105, 216)
    ..close();
}

void _paintClothing(Canvas canvas, _Rig r) {
  canvas.save();
  canvas.translate(0, _bodyDrop);
  _paintClothingInner(canvas, r);
  canvas.restore();
}

void _paintClothingInner(Canvas canvas, _Rig r) {
  final kind = r.clothing.kind;
  final cloth = r.cfg.clothingColor;
  final nl = _neckline(r, kind);
  final garment = Path.combine(PathOperation.difference, _garmentPath(kind), nl.hole);

  if (kind == ClothingKind.hoodie) {
    // Kapüşon: boynun arkasında, omuzlara yatan yumuşak halka.
    final hood = Path()
      ..moveTo(_cx - r.neckHalf - 20, 156)
      ..cubicTo(_cx - r.neckHalf - 22, 138, _cx - r.neckHalf - 10, 130, _cx, 130)
      ..cubicTo(_cx + r.neckHalf + 10, 130, _cx + r.neckHalf + 22, 138, _cx + r.neckHalf + 20, 156)
      ..close();
    canvas.drawPath(hood, r.fill(_tone(cloth, -0.14)));
    if (r.detailed) {
      canvas.save();
      canvas.clipPath(hood);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, 138), width: 50, height: 22),
        r.soft(_alpha(Colors.black, 0.42), 5),
      );
      canvas.restore();
    }
  }

  canvas.drawPath(garment, r.fill(cloth));

  // Kumaş hacmi: omuzda açık, kolda/altta koyu.
  canvas.save();
  canvas.clipPath(garment);
  canvas.drawRect(
    const Rect.fromLTWH(0, 145, 200, 60),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 150),
        const Offset(0, 202),
        [_alpha(Colors.white, 0.14), _alpha(Colors.black, 0.18)],
      ),
  );
  // Işık soldan gelir: sol omuz açık, sağ koyu.
  canvas.drawRect(
    const Rect.fromLTWH(0, 145, 200, 60),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(200, 0),
        [_alpha(Colors.white, 0.10), _alpha(Colors.black, 0.0), _alpha(Colors.black, 0.20)],
        const [0.0, 0.45, 1.0],
      ),
  );
  if (r.detailed) {
    // Boyun ve çene altının kumaşa düşürdüğü gölge.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(_cx, 156), width: 64, height: 26),
      r.soft(_alpha(Colors.black, 0.32), 6),
    );
    // Kol altı kıvrımları.
    r.mirrored(canvas, (c, mir) {
      c.drawPath(
        Path()
          ..moveTo(_cx - 84, 172)
          ..quadraticBezierTo(_cx - 70, 190, _cx - 76, 204),
        r.stroke(_alpha(Colors.black, 0.20), 3.0, blur: 2.2),
      );
      c.drawPath(
        Path()
          ..moveTo(_cx - 34, 176)
          ..quadraticBezierTo(_cx - 28, 190, _cx - 36, 204),
        r.stroke(_alpha(Colors.black, 0.10), 2.4, blur: 2.4),
      );
    });
  }
  canvas.restore();

  // Yaka kenarı vurgusu (yalnız garmanın kestiği alt kenar).
  canvas.save();
  canvas.clipRect(const Rect.fromLTWH(0, 147.5, 200, 60));
  canvas.drawPath(nl.hole, r.stroke(_alpha(Colors.black, 0.28), 1.0, blur: r.detailed ? 0.6 : 0));
  canvas.restore();

  _paintClothingDetails(canvas, r, kind, cloth, nl);
}

void _paintClothingDetails(Canvas canvas, _Rig r, ClothingKind kind, Color cloth, _Neckline nl) {
  final nh = r.neckHalf;
  final dark = _tone(cloth, -0.30);
  final light = _tone(cloth, 0.18);
  final lum = cloth.computeLuminance();
  final lineC = _alpha(lum > 0.5 ? Colors.black : Colors.white, lum > 0.5 ? 0.22 : 0.18);

  switch (kind) {
    case ClothingKind.crew:
    case ClothingKind.vneck:
    case ClothingKind.scoop:
    case ClothingKind.tank:
      break;

    case ClothingKind.polo:
      // Yaka kanatları + kapama.
      r.mirrored(canvas, (c, mir) {
        c.drawPath(
          Path()
            ..moveTo(_cx - nh - 2, 145)
            ..lineTo(_cx - 3, 151)
            ..lineTo(_cx - 3, 172)
            ..lineTo(_cx - nh - 8, 158)
            ..close(),
          r.fill(mir ? _tone(cloth, -0.10) : _tone(cloth, 0.06)),
        );
        c.drawPath(
          Path()
            ..moveTo(_cx - nh - 2, 145)
            ..lineTo(_cx - 3, 151)
            ..lineTo(_cx - 3, 172),
          r.stroke(lineC, 0.9),
        );
      });
      canvas.drawLine(const Offset(_cx, 152), const Offset(_cx, 176), r.stroke(lineC, 0.9));
      canvas.drawCircle(const Offset(_cx + 0.2, 160), 1.3, r.fill(_tone(cloth, 0.30)));
      canvas.drawCircle(const Offset(_cx + 0.2, 169), 1.3, r.fill(_tone(cloth, 0.30)));
      break;

    case ClothingKind.henley:
      canvas.drawLine(const Offset(_cx, 160), const Offset(_cx, 184), r.stroke(lineC, 1.0));
      for (final y in [166.0, 174.0, 182.0]) {
        canvas.drawCircle(Offset(_cx, y), 1.4, r.fill(_tone(cloth, 0.32)));
      }
      _strokeHoleEdge(canvas, nl, r.stroke(_tone(cloth, -0.14), 2.2));
      break;

    case ClothingKind.hoodie:
      _strokeHoleEdge(canvas, nl, r.stroke(_tone(cloth, -0.18), 2.6));
      // İp ve kanguru cep hattı.
      r.mirrored(canvas, (c, mir) {
        c.drawLine(
          Offset(_cx - 8, 160),
          Offset(_cx - 9.5, 182),
          r.stroke(_tone(cloth, 0.55), 1.4),
        );
        c.drawCircle(Offset(_cx - 9.5, 183.5), 1.6, r.fill(_tone(cloth, 0.55)));
      });
      break;

    case ClothingKind.turtleneck:
      final band = Path()
        ..moveTo(_cx - nh - 2.4, 122)
        ..cubicTo(_cx - nh - 3, 138, _cx - nh - 3, 148, _cx - nh - 5, 156)
        ..quadraticBezierTo(_cx, 165, _cx + nh + 5, 156)
        ..cubicTo(_cx + nh + 3, 148, _cx + nh + 3, 138, _cx + nh + 2.4, 122)
        ..quadraticBezierTo(_cx, 128, _cx - nh - 2.4, 122)
        ..close();
      canvas.drawPath(band, r.fill(_tone(cloth, -0.04)));
      canvas.save();
      canvas.clipPath(band);
      for (var i = -5; i <= 5; i++) {
        canvas.drawLine(
          Offset(_cx + i * 3.0, 120),
          Offset(_cx + i * 3.4, 166),
          r.stroke(_alpha(Colors.black, 0.13), 0.8),
        );
      }
      canvas.drawRect(
        Rect.fromLTWH(_cx - 30, 118, 60, 60),
        Paint()
          ..shader = ui.Gradient.linear(
            const Offset(_cx - 20, 0),
            const Offset(_cx + 22, 0),
            [_alpha(Colors.white, 0.16), _alpha(Colors.black, 0.0), _alpha(Colors.black, 0.20)],
            const [0.0, 0.5, 1.0],
          ),
      );
      // Çenenin boğaz yakasına düşen gölgesi.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, r.chinY - _bodyDrop + 4), width: 40, height: 14),
        r.soft(_alpha(Colors.black, 0.35), 3.5),
      );
      canvas.restore();
      canvas.drawPath(
        Path()
          ..moveTo(_cx - nh - 5, 156)
          ..quadraticBezierTo(_cx, 165, _cx + nh + 5, 156),
        r.stroke(_alpha(Colors.black, 0.28), 1.1),
      );
      break;

    case ClothingKind.blazer:
      // İç gömlek + yaka klapaları.
      final shirt = const Color(0xFFF1EEE8);
      canvas.drawPath(nl.hole, r.fill(shirt));
      canvas.save();
      canvas.clipPath(nl.hole);
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, 152), width: 40, height: 22),
        r.soft(_alpha(Colors.black, 0.28), 4),
      );
      canvas.restore();
      // Gömlek yakası.
      r.mirrored(canvas, (c, mir) {
        c.drawPath(
          Path()
            ..moveTo(_cx - nh - 1, 146)
            ..lineTo(_cx - 1, 168)
            ..lineTo(_cx - nh - 9, 160)
            ..close(),
          r.fill(mir ? const Color(0xFFDAD6CE) : const Color(0xFFFAF8F4)),
        );
      });
      // Klapalar.
      r.mirrored(canvas, (c, mir) {
        final lapel = Path()
          ..moveTo(_cx - nh - 3, 148)
          ..lineTo(_cx - 1, 189)
          ..lineTo(_cx - 15, 199)
          ..lineTo(_cx - 34, 168)
          ..lineTo(_cx - 25, 160)
          ..close();
        c.drawPath(lapel, r.fill(_tone(cloth, mir ? -0.10 : 0.05)));
        c.drawPath(lapel, r.stroke(_alpha(Colors.black, 0.30), 0.9));
      });
      canvas.drawLine(const Offset(_cx, 189), const Offset(_cx, 204), r.stroke(_alpha(Colors.black, 0.30), 1.0));
      canvas.drawCircle(const Offset(_cx + 4, 196), 1.6, r.fill(dark));
      break;

    case ClothingKind.shirtTie:
      // Kravat.
      final tie = _mix(const Color(0xFF8A2F3B), cloth, 0.12);
      r.mirrored(canvas, (c, mir) {
        c.drawPath(
          Path()
            ..moveTo(_cx - nh - 2.5, 146)
            ..lineTo(_cx - 1, 168)
            ..lineTo(_cx - nh - 11, 160)
            ..close(),
          r.fill(mir ? _tone(cloth, -0.12) : _tone(cloth, 0.10)),
        );
        c.drawPath(
          Path()
            ..moveTo(_cx - nh - 2.5, 146)
            ..lineTo(_cx - 1, 168)
            ..lineTo(_cx - nh - 11, 160),
          r.stroke(_alpha(Colors.black, 0.22), 0.9),
        );
      });
      canvas.drawPath(
        Path()
          ..moveTo(_cx - 4, 158)
          ..lineTo(_cx + 4, 158)
          ..lineTo(_cx + 3, 165)
          ..lineTo(_cx - 3, 165)
          ..close(),
        r.fill(_tone(tie, -0.10)),
      );
      canvas.drawPath(
        Path()
          ..moveTo(_cx - 3, 165)
          ..lineTo(_cx + 3, 165)
          ..lineTo(_cx + 6.5, 196)
          ..lineTo(_cx, 203)
          ..lineTo(_cx - 6.5, 196)
          ..close(),
        r.fill(tie),
      );
      canvas.drawLine(
        const Offset(_cx - 1.2, 167),
        const Offset(_cx - 3.4, 195),
        r.stroke(_alpha(Colors.white, 0.24), 1.2, blur: r.detailed ? 0.5 : 0),
      );
      // Düğme sırası.
      for (final y in [178.0, 190.0]) {
        canvas.drawCircle(Offset(_cx + 14, y), 1.1, r.fill(_tone(cloth, 0.35)));
      }
      break;

    case ClothingKind.sweater:
      // Kalın yaka ribi + örgü çizgileri.
      _strokeHoleEdge(canvas, nl, r.stroke(_tone(cloth, -0.10), 3.6));
      canvas.save();
      canvas.clipPath(_garmentPath(kind));
      for (var i = -12; i <= 12; i++) {
        final x = _cx + i * 8.0;
        canvas.drawPath(
          Path()
            ..moveTo(x, 168)
            ..cubicTo(x + 3, 178, x - 3, 188, x, 204),
          r.stroke(_alpha(Colors.black, 0.10), 1.6),
        );
        canvas.drawPath(
          Path()
            ..moveTo(x + 2.2, 168)
            ..cubicTo(x + 5, 178, x - 1, 188, x + 2.2, 204),
          r.stroke(_alpha(Colors.white, 0.08), 1.0),
        );
      }
      canvas.restore();
      break;

    case ClothingKind.bomber:
      _strokeHoleEdge(canvas, nl, r.stroke(_tone(cloth, -0.16), 3.8));
      canvas.drawLine(const Offset(_cx, 158), const Offset(_cx, 204), r.stroke(_alpha(Colors.black, 0.34), 1.3));
      canvas.drawLine(const Offset(_cx + 1.3, 158), const Offset(_cx + 1.3, 204), r.stroke(_alpha(Colors.white, 0.14), 0.8));
      canvas.drawRect(Rect.fromCenter(center: const Offset(_cx, 160), width: 3.4, height: 5), r.fill(light));
      r.mirrored(canvas, (c, mir) {
        c.drawLine(Offset(_cx - 62, 178), Offset(_cx - 46, 176), r.stroke(_alpha(Colors.black, 0.24), 1.0));
      });
      break;
  }
}

void _strokeHoleEdge(Canvas canvas, _Neckline nl, Paint paint) {
  canvas.save();
  canvas.clipRect(const Rect.fromLTWH(0, 147.5, 200, 60));
  canvas.drawPath(nl.hole, paint);
  canvas.restore();
}
