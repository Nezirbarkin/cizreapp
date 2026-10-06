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
  if (r.background != null) return;

  // Kafanın arkasında geniş, yumuşak bir ışık dairesi (Bitmoji sahnesi).
  canvas.drawCircle(
    const Offset(100, 92),
    96,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(100, 84),
        96,
        [_alpha(_mix(top, Colors.white, 0.55), 0.55), _alpha(top, 0.0)],
      ),
  );
}

// ---------------------------------------------------------------- omuz/boyun
/// Boynun omuzlarla birleştiği y. Uzun çenede biraz aşağı iner.
double _neckBaseY(_Rig r) => math.max(160.0, r.chinY + 11);

Path _torsoPath(_Rig r) {
  final nh = r.neckHalf;
  final by = _neckBaseY(r);
  final right = <Offset>[
    Offset(nh, r.chinY - 26),
    Offset(nh + 0.4, by - 6),
    Offset(nh + 6, by + 2.5),
    Offset(nh + 26, by + 6.5),
    Offset(66, by + 13),
    Offset(84, by + 22),
    Offset(94, 214),
  ];
  final path = Path()..moveTo(_cx - right.first.dx, right.first.dy);
  final left = right.map((p) => Offset(_cx - p.dx, p.dy)).toList();
  path.extendWithPath(_spline(left), Offset.zero);
  path.lineTo(_cx + 94, 214);
  path.extendWithPath(_spline(right.reversed.map((p) => Offset(_cx + p.dx, p.dy)).toList()), Offset.zero);
  path.close();
  return path;
}

void _paintTorso(Canvas canvas, _Rig r) {
  final torso = _torsoPath(r);
  canvas.drawPath(torso, r.fill(_mix(r.skin, r.skinShadow, 0.35)));

  canvas.save();
  canvas.clipPath(torso);
  // Çenenin boyuna düşürdüğü gölge: çene hattının aşağı kaydırılmış kopyası.
  final jawShadow = Path.combine(PathOperation.difference, r.head.shift(const Offset(0, 9)), r.head);
  canvas.drawPath(jawShadow, r.soft(_alpha(r.skinDeep, 0.40), 1.6));
  // Sağ (gölge) taraf.
  canvas.drawRect(
    Rect.fromLTWH(_cx + r.neckHalf * 0.35, r.chinY - 30, 80, 100),
    r.soft(_alpha(r.skinShadow, 0.55), 2.0),
  );
  if (r.detailed) {
    // Köprücük çizgileri (açık yakalarda görünür).
    final by = _neckBaseY(r);
    r.mirrored(canvas, (c, mir) {
      c.drawPath(
        Path()
          ..moveTo(_cx - 6, by + 6)
          ..quadraticBezierTo(_cx - 20, by + 3.5, _cx - 38, by + 8),
        r.stroke(_alpha(r.skinShadow, mir ? 0.75 : 0.55), 1.1),
      );
    });
  }
  canvas.restore();
  canvas.drawPath(torso, r.stroke(r.skinLine, r.lineW));
}

// ------------------------------------------------------------------ kıyafet
/// Yaka boşluğu (cildin göründüğü bölge). Kıyafet bu boşluğu bırakarak çizilir.
class _Neckline {
  final Path hole;
  const _Neckline(this.hole);
}

_Neckline _neckline(_Rig r, ClothingKind kind) {
  final nh = r.neckHalf;
  final by = _neckBaseY(r);
  Path crew(double l, double depth) => Path()
    ..moveTo(_cx - l, by - 20)
    ..lineTo(_cx - l, by - 2)
    ..cubicTo(_cx - l, by - 2 + depth * 0.7, _cx - l * 0.5, by - 2 + depth, _cx, by - 2 + depth)
    ..cubicTo(_cx + l * 0.5, by - 2 + depth, _cx + l, by - 2 + depth * 0.7, _cx + l, by - 2)
    ..lineTo(_cx + l, by - 20)
    ..close();

  Path vee(double l, double depth) => Path()
    ..moveTo(_cx - l, by - 20)
    ..lineTo(_cx - l, by - 2)
    ..quadraticBezierTo(_cx - l * 0.35, by + depth * 0.45, _cx, by + depth)
    ..quadraticBezierTo(_cx + l * 0.35, by + depth * 0.45, _cx + l, by - 2)
    ..lineTo(_cx + l, by - 20)
    ..close();

  switch (kind) {
    case ClothingKind.crew:
      return _Neckline(crew(nh + 3, 9));
    case ClothingKind.vneck:
      return _Neckline(vee(nh + 3, 22));
    case ClothingKind.scoop:
      return _Neckline(crew(nh + 13, 19));
    case ClothingKind.tank:
      return _Neckline(crew(nh + 18, 24));
    case ClothingKind.polo:
    case ClothingKind.henley:
      return _Neckline(crew(nh + 3, 8));
    case ClothingKind.hoodie:
      return _Neckline(crew(nh + 4, 8));
    case ClothingKind.sweater:
      return _Neckline(crew(nh + 3.5, 8));
    case ClothingKind.turtleneck:
      return _Neckline(crew(nh + 0.5, 2));
    case ClothingKind.blazer:
      return _Neckline(vee(nh + 2, 30));
    case ClothingKind.shirtTie:
      return _Neckline(vee(nh + 2.5, 12));
    case ClothingKind.bomber:
      return _Neckline(crew(nh + 3.5, 7));
  }
}

Path _garmentPath(_Rig r, ClothingKind kind) {
  final by = _neckBaseY(r);
  if (kind == ClothingKind.tank) {
    // Askılı: omuzlar açık.
    return Path()
      ..moveTo(_cx - 62, 214)
      ..cubicTo(_cx - 62, by + 26, _cx - 50, by + 14, _cx - 42, by + 6)
      ..lineTo(_cx - 34, by - 6)
      ..lineTo(_cx + 34, by - 6)
      ..lineTo(_cx + 42, by + 6)
      ..cubicTo(_cx + 50, by + 14, _cx + 62, by + 26, _cx + 62, 214)
      ..close();
  }
  final nh = r.neckHalf;
  final right = <Offset>[
    Offset(nh + 2, by - 9),
    Offset(nh + 8, by + 1.5),
    Offset(nh + 26, by + 5.5),
    Offset(66, by + 12),
    Offset(85, by + 21),
    Offset(96, 214),
  ];
  final path = Path()..moveTo(_cx - right.first.dx, right.first.dy);
  path.extendWithPath(_spline(right.map((p) => Offset(_cx - p.dx, p.dy)).toList()), Offset.zero);
  path.lineTo(_cx + 96, 214);
  path.extendWithPath(_spline(right.reversed.map((p) => Offset(_cx + p.dx, p.dy)).toList()), Offset.zero);
  path.close();
  return path;
}

void _paintClothing(Canvas canvas, _Rig r) {
  final kind = r.clothing.kind;
  final cloth = r.cfg.clothingColor;
  final by = _neckBaseY(r);
  final nl = _neckline(r, kind);
  final shape = _garmentPath(r, kind);
  final garment = Path.combine(PathOperation.difference, shape, nl.hole);
  final dark = _tone(cloth, -0.24);
  final line = _tone(cloth, -0.52);

  if (kind == ClothingKind.hoodie) {
    // Kapüşon: boynun arkasında omuzlara yatan yumuşak halka.
    final nh = r.neckHalf;
    final hood = Path()
      ..moveTo(_cx - nh - 22, by + 8)
      ..cubicTo(_cx - nh - 25, by - 12, _cx - nh - 10, by - 20, _cx, by - 20)
      ..cubicTo(_cx + nh + 10, by - 20, _cx + nh + 25, by - 12, _cx + nh + 22, by + 8)
      ..close();
    canvas.drawPath(hood, r.fill(_tone(cloth, -0.16)));
    canvas.drawPath(hood, r.stroke(line, r.lineW));
  }

  canvas.drawPath(garment, r.fill(cloth));

  canvas.save();
  canvas.clipPath(garment);
  // Cel gölge: sağ omuz ve kol altı.
  r.celShade(canvas, shape, _alpha(dark, 0.85), base: cloth, offset: const Offset(-9, -5), blur: 1.8);
  // Boynun kumaşa düşürdüğü gölge.
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx + 2, by + 3), width: r.neckHalf * 3.4, height: 13),
    r.soft(_alpha(dark, 0.75), 2.4),
  );
  // Kol kıvrımları.
  r.mirrored(canvas, (c, mir) {
    c.drawPath(
      Path()
        ..moveTo(_cx - 76, by + 18)
        ..quadraticBezierTo(_cx - 66, by + 28, _cx - 70, 202),
      r.stroke(_alpha(dark, mir ? 0.9 : 0.6), 1.3),
    );
  });
  if (r.detailed) {
    // Sol omuzda ışık.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - 52, by + 10), width: 34, height: 10),
      r.soft(_alpha(_tone(cloth, 0.22), 0.55), 4),
    );
  }
  canvas.restore();

  _paintClothingDetails(canvas, r, kind, cloth, nl, by);
  canvas.drawPath(garment, r.stroke(line, r.lineW));
}

void _paintClothingDetails(Canvas canvas, _Rig r, ClothingKind kind, Color cloth, _Neckline nl, double by) {
  final nh = r.neckHalf;
  final dark = _tone(cloth, -0.24);
  final line = _tone(cloth, -0.52);
  final light = _tone(cloth, 0.20);
  final w = r.lineW;

  void rib(double width) {
    // Yakanın kesildiği kenarda kalın ribana.
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, by - 4, 200, 60));
    canvas.drawPath(nl.hole, r.stroke(_tone(cloth, -0.10), width));
    canvas.drawPath(nl.hole.shift(Offset(0, width * 0.45)), r.stroke(_alpha(line, 0.6), w * 0.8));
    canvas.restore();
  }

  switch (kind) {
    case ClothingKind.crew:
      rib(3.0);
      break;
    case ClothingKind.vneck:
      rib(2.6);
      break;
    case ClothingKind.scoop:
    case ClothingKind.tank:
      rib(2.0);
      break;

    case ClothingKind.polo:
      // Yaka kanatları + düğme şeridi.
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTRB(_cx - 3.4, by + 4, _cx + 3.4, by + 26), const Radius.circular(1.5)),
        r.fill(_tone(cloth, -0.08)),
      );
      canvas.drawCircle(Offset(_cx, by + 11), 1.3, r.fill(light));
      canvas.drawCircle(Offset(_cx, by + 19), 1.3, r.fill(light));
      r.mirrored(canvas, (c, mir) {
        final flap = Path()
          ..moveTo(_cx - nh - 3, by - 7)
          ..lineTo(_cx - 2, by + 5)
          ..lineTo(_cx - nh - 9, by + 11)
          ..quadraticBezierTo(_cx - nh - 9, by + 2, _cx - nh - 3, by - 7)
          ..close();
        c.drawPath(flap, r.fill(mir ? _tone(cloth, -0.14) : _tone(cloth, 0.08)));
        c.drawPath(flap, r.stroke(line, w));
      });
      break;

    case ClothingKind.henley:
      rib(2.6);
      canvas.drawLine(Offset(_cx, by + 7), Offset(_cx, by + 28), r.stroke(line, w));
      for (final y in [by + 12, by + 19, by + 26]) {
        canvas.drawCircle(Offset(_cx + 2.2, y), 1.3, r.fill(light));
      }
      break;

    case ClothingKind.hoodie:
      rib(3.4);
      r.mirrored(canvas, (c, mir) {
        c.drawPath(
          Path()
            ..moveTo(_cx - 7, by + 5)
            ..quadraticBezierTo(_cx - 9, by + 16, _cx - 8, by + 26),
          r.stroke(_tone(cloth, 0.55), 1.6),
        );
        c.drawCircle(Offset(_cx - 8, by + 27.5), 1.7, r.fill(_tone(cloth, 0.55)));
      });
      break;

    case ClothingKind.turtleneck:
      final band = Path()
        ..moveTo(_cx - nh - 1.5, r.chinY - 6)
        ..cubicTo(_cx - nh - 2.5, by - 12, _cx - nh - 3, by - 4, _cx - nh - 6, by + 4)
        ..quadraticBezierTo(_cx, by + 11, _cx + nh + 6, by + 4)
        ..cubicTo(_cx + nh + 3, by - 4, _cx + nh + 2.5, by - 12, _cx + nh + 1.5, r.chinY - 6)
        ..quadraticBezierTo(_cx, r.chinY - 1, _cx - nh - 1.5, r.chinY - 6)
        ..close();
      canvas.drawPath(band, r.fill(_tone(cloth, -0.04)));
      canvas.save();
      canvas.clipPath(band);
      r.celShade(canvas, band, _alpha(dark, 0.8), base: _tone(cloth, -0.04), offset: const Offset(-6, -2));
      for (var i = -4; i <= 4; i++) {
        canvas.drawLine(Offset(_cx + i * 4.0, r.chinY - 8), Offset(_cx + i * 4.4, by + 12), r.stroke(_alpha(dark, 0.55), 0.9));
      }
      // Çenenin boğaz yakasına düşen gölgesi.
      canvas.drawPath(
        Path.combine(PathOperation.difference, r.head.shift(const Offset(0, 5)), r.head),
        r.soft(_alpha(dark, 0.8), 1.2),
      );
      canvas.restore();
      canvas.drawPath(band, r.stroke(line, w));
      break;

    case ClothingKind.blazer:
      // İç gömlek + yaka klapaları.
      const shirt = Color(0xFFF4F1EC);
      canvas.drawPath(nl.hole, r.fill(shirt));
      canvas.save();
      canvas.clipPath(nl.hole);
      canvas.drawRect(Rect.fromLTWH(_cx - 30, r.chinY - 30, 60, 40), r.fill(_mix(r.skin, r.skinShadow, 0.35)));
      final open = Path()
        ..moveTo(_cx - nh + 1, by - 20)
        ..lineTo(_cx - nh + 1, by - 1)
        ..quadraticBezierTo(_cx - 3, by + 6, _cx, by + 10)
        ..quadraticBezierTo(_cx + 3, by + 6, _cx + nh - 1, by - 1)
        ..lineTo(_cx + nh - 1, by - 20)
        ..close();
      canvas.restore();
      canvas.save();
      canvas.clipPath(Path.combine(PathOperation.difference, nl.hole, open));
      canvas.drawRect(Rect.fromLTWH(0, by - 20, 200, 80), r.fill(shirt));
      canvas.drawRect(Rect.fromLTWH(_cx, by - 20, 30, 80), r.fill(const Color(0xFFDCD8D0)));
      canvas.restore();
      r.mirrored(canvas, (c, mir) {
        final collar = Path()
          ..moveTo(_cx - nh - 1, by - 9)
          ..lineTo(_cx - 1.5, by + 9)
          ..lineTo(_cx - nh - 7, by + 5)
          ..close();
        c.drawPath(collar, r.fill(mir ? const Color(0xFFDCD8D0) : const Color(0xFFFFFFFF)));
        c.drawPath(collar, r.stroke(const Color(0xFF8C8880), w * 0.8));
      });
      r.mirrored(canvas, (c, mir) {
        final lapel = Path()
          ..moveTo(_cx - nh - 3, by - 6)
          ..lineTo(_cx - 1.5, by + 30)
          ..lineTo(_cx - 12, by + 36)
          ..lineTo(_cx - 32, by + 8)
          ..lineTo(_cx - 24, by + 2)
          ..close();
        c.drawPath(lapel, r.fill(_tone(cloth, mir ? -0.14 : 0.06)));
        c.drawPath(lapel, r.stroke(line, w));
      });
      canvas.drawCircle(Offset(_cx + 3.5, by + 38), 1.6, r.fill(_tone(cloth, -0.4)));
      break;

    case ClothingKind.shirtTie:
      final tie = _mix(const Color(0xFF8A2F3B), cloth, 0.12);
      r.mirrored(canvas, (c, mir) {
        final collar = Path()
          ..moveTo(_cx - nh - 2.5, by - 8)
          ..lineTo(_cx - 1, by + 9)
          ..lineTo(_cx - nh - 10, by + 4)
          ..close();
        c.drawPath(collar, r.fill(mir ? _tone(cloth, -0.12) : _tone(cloth, 0.12)));
        c.drawPath(collar, r.stroke(line, w));
      });
      final knot = Path()
        ..moveTo(_cx - 4, by + 1)
        ..lineTo(_cx + 4, by + 1)
        ..lineTo(_cx + 2.8, by + 8)
        ..lineTo(_cx - 2.8, by + 8)
        ..close();
      final blade = Path()
        ..moveTo(_cx - 2.8, by + 8)
        ..lineTo(_cx + 2.8, by + 8)
        ..lineTo(_cx + 6.2, by + 34)
        ..lineTo(_cx, by + 41)
        ..lineTo(_cx - 6.2, by + 34)
        ..close();
      canvas.drawPath(blade, r.fill(tie));
      canvas.drawPath(knot, r.fill(_tone(tie, -0.12)));
      canvas.drawLine(Offset(_cx + 1.4, by + 10), Offset(_cx + 3.8, by + 33), r.stroke(_alpha(_tone(tie, -0.3), 0.8), 1.4));
      canvas.drawPath(blade, r.stroke(_tone(tie, -0.5), w));
      canvas.drawPath(knot, r.stroke(_tone(tie, -0.5), w));
      for (final y in [by + 20, by + 32]) {
        canvas.drawCircle(Offset(_cx + 13, y), 1.1, r.fill(light));
      }
      break;

    case ClothingKind.sweater:
      rib(4.2);
      canvas.save();
      canvas.clipPath(_garmentPath(r, kind));
      for (var i = -12; i <= 12; i++) {
        final x = _cx + i * 8.0;
        canvas.drawPath(
          Path()
            ..moveTo(x, by + 12)
            ..cubicTo(x + 2.5, by + 20, x - 2.5, by + 28, x, by + 40),
          r.stroke(_alpha(dark, 0.45), 1.3),
        );
      }
      canvas.restore();
      break;

    case ClothingKind.bomber:
      rib(4.4);
      canvas.drawLine(Offset(_cx, by + 4), Offset(_cx, 204), r.stroke(line, w * 1.2));
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(_cx, by + 7), width: 3.6, height: 6), const Radius.circular(1)),
        r.fill(const Color(0xFFCFD4DA)),
      );
      r.mirrored(canvas, (c, mir) {
        c.drawLine(Offset(_cx - 58, by + 24), Offset(_cx - 42, by + 22), r.stroke(line, w));
      });
      break;
  }
}
