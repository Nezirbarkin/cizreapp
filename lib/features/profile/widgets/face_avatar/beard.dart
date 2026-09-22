part of '../face_avatar_painter.dart';

// ============================================================================
// SAKAL / BIYIK / FAVORİ
//
// Sakal, yüz silüetinin çene hattını izleyen bir kütledir; iç sınırı yanaktan
// ağız köşelerine inip alt dudağın altından geçer, böylece dudaklar açık kalır.
// Kısa (üç günlük) sakal yumuşak dolgu + tek tek noktalar, uzun sakal ise tel
// tel saç motoru ile çizilir.
// ============================================================================

Offset _mirX(Offset p) => Offset(_cx - (p.dx - _cx), p.dy);

/// Alt dudağın alt kenarı (sakal iç sınırı bunun altından geçer).
double _lipBottomY(_Rig r) => r.mouthY + 6.4 * r.lip.lower * r.m.lipFullness + 0.6;

/// Çene hattını saran U biçimli sakal kütlesi.
Path _beardMass(
  _Rig r, {
  required double sideTopY,
  double flare = 0,
  double drop = 0,
  double tip = 0,
  double cheekIn = 0,
  double cheekLift = 0,
  double mouthGap = 0,
}) {
  final chinY = r.chinY;
  final lipB = _lipBottomY(r);
  final mh = r.mouthHalf;

  // Dış kenar: yüz silüeti + taşma; sağ yarı, yukarıdan çeneye.
  final right = <Offset>[];
  for (var y = sideTopY; y < chinY - 6; y += 7) {
    final ease = ((y - sideTopY) / (chinY - sideTopY)).clamp(0.0, 1.0);
    right.add(Offset(_cx + r.headX(y) + flare * (0.35 + 0.65 * ease), y));
  }
  right.add(Offset(_cx + r.headX(chinY - 3) + flare * 0.8, chinY - 3 + drop * 0.25));
  right.add(Offset(_cx + r.chinHalf * (0.95 - tip) + flare * 0.5, chinY + drop * 0.7));
  right.add(Offset(_cx, chinY + drop));

  // İç kenar (sağ yarı): merkezden (alt dudak altı) yanağa.
  final inner = <Offset>[
    Offset(_cx, lipB + 2.4 + mouthGap),
    Offset(_cx + mh * 0.55, lipB + 1.8 + mouthGap),
    Offset(_cx + mh * 1.05, r.mouthY + 6.0),
    Offset(_cx + mh * 1.34, r.mouthY - 3.0),
    Offset(_cx + mh * 1.3 + cheekIn * 0.4, r.mouthY - 12 - cheekLift),
    Offset(_cx + _lerpD(r.headX(sideTopY + 4) - 2.6, mh * 1.6, cheekIn * 0.5), sideTopY + 4 - cheekLift * 0.6),
  ];

  // Sağ dış (yukarıdan çeneye) → sol dış (çeneden yukarı) → sol iç (yukarıdan
  // merkeze) → sağ iç (merkezden yukarı).
  final innerLeftDown = inner.reversed.map(_mirX).toList()..removeLast();
  final pts = <Offset>[
    ...right,
    ...right.reversed.skip(1).map(_mirX),
    ...innerLeftDown,
    ...inner,
  ];
  return _spline(pts, closed: true, tension: 0.9);
}

/// Yalnızca çene çevresi ince bant (çene hattı / şerit).
Path _jawBand(_Rig r, {required double thick, double topY = 96}) {
  final outer = <Offset>[];
  final inner = <Offset>[];
  for (var y = topY; y < r.chinY - 4; y += 6) {
    final x = r.headX(y);
    outer.add(Offset(_cx + x + 0.3, y));
    inner.add(Offset(_cx + x - thick, y));
  }
  outer.add(Offset(_cx + r.chinHalf + 0.5, r.chinY - 2));
  inner.add(Offset(_cx + r.chinHalf - thick * 0.6, r.chinY - 2 - thick * 0.5));
  outer.add(Offset(_cx, r.chinY + 0.8));
  inner.add(Offset(_cx, r.chinY - thick * 0.9));
  // Sağ dış (yukarıdan çeneye) → sol dış (çeneden yukarı) → sol iç (yukarıdan
  // çeneye) → sağ iç (çeneden yukarı).
  final pts = <Offset>[
    ...outer,
    ...outer.reversed.skip(1).map(_mirX),
    ...inner.map(_mirX),
    ...inner.reversed.skip(1),
  ];
  return _spline(pts, closed: true, tension: 0.9);
}

/// Kısa yüz kılları (üç günlük) için yumuşak dolgu + noktalar.
void _stubbleFill(Canvas canvas, _Rig r, Path region, double density, int seed) {
  canvas.save();
  canvas.clipPath(r.head);
  canvas.drawPath(region, r.soft(_alpha(r.hairColor, 0.18 + 0.36 * density), 2.6));
  if (r.detailed) {
    final b = region.getBounds();
    final rng = r.rngFor(seed);
    final dots = <Offset>[];
    final n = (b.width * b.height * (0.18 + 0.30 * density)).round();
    for (var i = 0; i < n; i++) {
      final p = Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height);
      if (region.contains(p)) dots.add(p);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      dots,
      Paint()
        ..strokeWidth = 0.65
        ..strokeCap = StrokeCap.round
        ..color = _alpha(r.hairDark, 0.30 + 0.35 * density),
    );
  }
  canvas.restore();
}

/// Sakal akışı: yanaktan çeneye, aşağı ve hafif içe.
_Flow _beardFlow(_Rig r) {
  return (p) {
    final dx = (p.dx - _cx) / 40.0;
    return _norm(Offset(-dx * 0.35, 1.0));
  };
}

/// Gerçek sakal: tel tel + dolgu; yanak çizgisinde yumuşak, dışarıda net.
void _beardHair(Canvas canvas, _Rig r, Path region, {required double density, required int seed, double sheen = 0.16, double len = 6, bool fade = false}) {
  final g = _HairGeo(r);
  canvas.save();
  // Sakal, yüzün dışına (çene altı) taşabilir; yalnız kafa + alt bölge.
  final clip = Path.combine(
    PathOperation.union,
    r.head,
    Path()..addOval(Rect.fromCenter(center: Offset(_cx, r.chinY), width: r.jawHalf * 3.2, height: 90)),
  );
  canvas.clipPath(clip);
  final base = _mix(r.hairColor, r.hairDark, 0.14);
  final path = region;
  // Yanak/şakak tarafında sakal yukarı doğru yumuşakça sönsün (maske gibi durmasın).
  if (fade && r.detailed) {
    canvas.saveLayer(path.getBounds().inflate(8), Paint());
  }
  canvas.drawPath(path, r.fill(_alpha(base, density)));
  if (r.detailed) {
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(
      path.getBounds().inflate(2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(path.getBounds().left, path.getBounds().top),
          Offset(path.getBounds().right, path.getBounds().bottom),
          [_alpha(r.hairLight, 0.26), _alpha(r.hairDark, 0.0), _alpha(r.hairDark, 0.36)],
          const [0.0, 0.5, 1.0],
        ),
    );
    _strands(canvas, r, g, path, flow: _beardFlow(r), count: 520, len: len, width: 0.8, curl: r.hair.texture == HairTexture.smooth ? 0.5 : 1.3, wavelength: 6, seed: seed);
    // Alt/kenar koyulaşması: çene altı gölgeli.
    canvas.drawPath(path, r.stroke(_alpha(r.hairDark, 0.4), 4.5, blur: 2.4));
    canvas.drawOval(
      Rect.fromLTWH(_cx - 30, r.chinY - 16, 42, 14),
      r.soft(_alpha(r.hairShine, sheen), 4),
    );
    canvas.restore();
  }
  if (fade && r.detailed) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 60, 200, 100),
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          const Offset(0, 88),
          const Offset(0, 116),
          [const Color(0x00000000), const Color(0xFF000000)],
        ),
    );
    canvas.restore();
  }
  canvas.restore();
}

/// Yanak çizgisine dağılmış tüyler: sakalın iç kenarını yumuşatır.
void _beardFeather(Canvas canvas, _Rig r, List<Offset> line, {required int seed, double density = 1.0}) {
  if (!r.detailed) return;
  final rng = r.rngFor(seed);
  canvas.save();
  canvas.clipPath(r.head);
  for (final p0 in line) {
    for (var k = 0; k < (3 * density).round(); k++) {
      final p = p0 + Offset((rng.nextDouble() - 0.5) * 3.2, (rng.nextDouble() - 0.5) * 3.2);
      final dir = _norm(Offset((rng.nextDouble() - 0.5) * 0.6, -0.4 + rng.nextDouble() * 0.6));
      _taper(canvas, [p, p + dir * 1.4, p + dir * (2.4 + rng.nextDouble() * 1.8)], 0.5, 0.08, r.fill(_alpha(r.hairColor, 0.5)));
    }
  }
  canvas.restore();
}

// ------------------------------------------------------------------ bıyık
Path _mustachePath(_Rig r, MustacheKind kind) {
  final mh = r.mouthHalf;
  final y0 = r.mouthY - 7.6;
  double w;
  double th;
  double droop;
  switch (kind) {
    case MustacheKind.thin:
      w = mh * 1.02;
      th = 2.6;
      droop = 1.0;
      break;
    case MustacheKind.thick:
      w = mh * 1.24;
      th = 7.0;
      droop = 2.0;
      break;
    case MustacheKind.toothbrush:
      w = mh * 0.62;
      th = 6.0;
      droop = 0.2;
      break;
    case MustacheKind.chevron:
      w = mh * 1.1;
      th = 6.6;
      droop = 1.4;
      break;
    case MustacheKind.walrus:
      w = mh * 1.52;
      th = 8.0;
      droop = 6.0;
      break;
    case MustacheKind.horseshoe:
      w = mh * 1.16;
      th = 6.2;
      droop = 1.6;
      break;
    case MustacheKind.handlebar:
      w = mh * 1.14;
      th = 3.4;
      droop = -0.6;
      break;
    case MustacheKind.fuManchu:
      w = mh * 1.08;
      th = 3.2;
      droop = 1.4;
      break;
    case MustacheKind.imperial:
      w = mh * 1.12;
      th = 3.0;
      droop = -1.2;
      break;
    case MustacheKind.natural:
    case MustacheKind.none:
      w = mh * 1.12;
      th = 5.0;
      droop = 1.6;
      break;
  }

  final top = y0 - th * 0.5;
  final pts = <Offset>[
    Offset(_cx, top + 0.6),
    Offset(_cx + w * 0.34, top - 0.2),
    Offset(_cx + w * 0.72, top + 0.7 + droop * 0.4),
    Offset(_cx + w, y0 + droop + th * 0.15),
    Offset(_cx + w * 0.86, y0 + droop + th * 0.75),
    Offset(_cx + w * 0.46, y0 + th * 0.55),
    Offset(_cx + w * 0.16, y0 + th * 0.62 + 0.4),
    Offset(_cx, y0 + th * 0.36),
  ];
  final full = <Offset>[
    ...pts,
    ...pts.reversed.skip(1).map(_mirX),
  ];
  final path = _spline(full, closed: true, tension: 0.85);

  final extra = Path();
  if (kind == MustacheKind.handlebar || kind == MustacheKind.imperial) {
    final up = kind == MustacheKind.imperial ? 9.0 : 6.4;
    r.mirroredPaths((sgn) {
      extra.addPath(
        _spline([
          Offset(_cx + sgn * (w * 0.92), y0 + 0.4),
          Offset(_cx + sgn * (w * 1.10), y0 - 0.8),
          Offset(_cx + sgn * (w * 1.26), y0 - up),
          Offset(_cx + sgn * (w * 1.20), y0 - up + 1.6),
          Offset(_cx + sgn * (w * 1.06), y0 + 1.4),
          Offset(_cx + sgn * (w * 0.90), y0 + 2.6),
        ], closed: true),
        Offset.zero,
      );
    });
  }
  if (kind == MustacheKind.horseshoe) {
    r.mirroredPaths((sgn) {
      extra.addPath(
        _spline([
          Offset(_cx + sgn * (w * 0.98), y0 + 1),
          Offset(_cx + sgn * (w * 1.02 + 0.8), r.mouthY + 2),
          Offset(_cx + sgn * (w * 1.0), r.mouthY + 12),
          Offset(_cx + sgn * (w * 0.8), r.mouthY + 12.5),
          Offset(_cx + sgn * (w * 0.8), r.mouthY + 2),
          Offset(_cx + sgn * (w * 0.78), y0 + 2.6),
        ], closed: true),
        Offset.zero,
      );
    });
  }
  if (kind == MustacheKind.fuManchu) {
    r.mirroredPaths((sgn) {
      extra.addPath(
        _spline([
          Offset(_cx + sgn * (w * 0.94), y0 + 1),
          Offset(_cx + sgn * (w * 1.06), r.mouthY + 4),
          Offset(_cx + sgn * (w * 1.04), r.mouthY + 22),
          Offset(_cx + sgn * (w * 0.90), r.mouthY + 23),
          Offset(_cx + sgn * (w * 0.86), r.mouthY + 6),
          Offset(_cx + sgn * (w * 0.78), y0 + 3),
        ], closed: true),
        Offset.zero,
      );
    });
  }
  if (kind == MustacheKind.walrus) {
    r.mirroredPaths((sgn) {
      extra.addPath(
        _spline([
          Offset(_cx + sgn * (w * 0.86), y0 + 2),
          Offset(_cx + sgn * (w * 1.06), r.mouthY + 4),
          Offset(_cx + sgn * (w * 1.0), r.mouthY + 10),
          Offset(_cx + sgn * (w * 0.84), r.mouthY + 8),
          Offset(_cx + sgn * (w * 0.7), y0 + 4.5),
        ], closed: true),
        Offset.zero,
      );
    });
  }
  return Path.combine(PathOperation.union, path, extra);
}

void _paintMustache(Canvas canvas, _Rig r, MustacheKind kind, double density) {
  if (kind == MustacheKind.none) return;
  final path = _mustachePath(r, kind);
  final g = _HairGeo(r);
  // Bıyık, üst dudağın üstünde; dudağı örtmez ama burun altına biner.
  Offset flow(Offset p) {
    final dx = p.dx - _cx;
    return _norm(Offset(dx.sign * 0.9, 0.7 + (kind == MustacheKind.handlebar ? -0.6 : 0)));
  }

  canvas.save();
  canvas.clipPath(Path.combine(PathOperation.union, r.head, Path()..addRect(Rect.fromLTWH(0, r.mouthY, 200, 60))));
  canvas.drawPath(path, r.fill(_alpha(_mix(r.hairColor, r.hairDark, 0.16), density.clamp(0.5, 1.0))));
  if (r.detailed) {
    canvas.save();
    canvas.clipPath(path);
    _strands(canvas, r, g, path, flow: flow, count: 130, len: 4.6, width: 0.7, curl: 0.4, wavelength: 5, seed: 610 + kind.index);
    canvas.drawPath(path, r.stroke(_alpha(r.hairDark, 0.4), 2.4, blur: 1.4));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - 5, r.mouthY - 9.4), width: 10, height: 2.4),
      r.soft(_alpha(r.hairShine, 0.22), 1.2),
    );
    canvas.restore();
    // Bıyığın dudağa düşürdüğü ince gölge.
    canvas.drawPath(
      Path()
        ..moveTo(_cx - r.mouthHalf * 0.8, r.mouthY - 4)
        ..quadraticBezierTo(_cx, r.mouthY - 2.6, _cx + r.mouthHalf * 0.8, r.mouthY - 4),
      r.stroke(_alpha(r.skinDeep, 0.22), 1.6, blur: 1.2),
    );
  }
  canvas.restore();
}

// ------------------------------------------------------------------- ana
void _paintBeard(Canvas canvas, _Rig r) {
  final spec = r.beard;
  if (spec.isNone) return;
  final d = spec.density;
  final lipB = _lipBottomY(r);
  final mh = r.mouthHalf;

  Path? mass;
  var stubble = false;
  var feather = <Offset>[];

  switch (spec.region) {
    case BeardRegion.none:
    case BeardRegion.neckOnly:
      break;

    case BeardRegion.stubbleLight:
    case BeardRegion.stubbleMedium:
    case BeardRegion.stubbleHeavy:
      mass = _beardMass(r, sideTopY: 84, flare: 0.2, drop: 0, cheekLift: 3);
      stubble = true;
      break;

    case BeardRegion.short:
      mass = _beardMass(r, sideTopY: 88, flare: 0.5, drop: 1, cheekLift: 2);
      break;
    case BeardRegion.boxed:
      mass = _beardMass(r, sideTopY: 86, flare: 1.6, drop: 3, cheekLift: 3);
      break;
    case BeardRegion.full:
      mass = _beardMass(r, sideTopY: 84, flare: 1.3, drop: 7, cheekLift: 4);
      break;
    case BeardRegion.fullLong:
      mass = _beardMass(r, sideTopY: 84, flare: 2.4, drop: 20, tip: 0.1, cheekLift: 4);
      break;
    case BeardRegion.garibaldi:
      mass = _beardMass(r, sideTopY: 84, flare: 3.8, drop: 15, cheekLift: 4);
      break;
    case BeardRegion.lumberjack:
      mass = _beardMass(r, sideTopY: 82, flare: 2.8, drop: 12, cheekLift: 6);
      break;
    case BeardRegion.viking:
      mass = _beardMass(r, sideTopY: 82, flare: 4.2, drop: 32, tip: 0.22, cheekLift: 6);
      break;
    case BeardRegion.ducktail:
      mass = _beardMass(r, sideTopY: 86, flare: 1.4, drop: 16, tip: 0.5, cheekLift: 4);
      break;

    case BeardRegion.jawline:
      mass = _jawBand(r, thick: 3.6);
      break;
    case BeardRegion.chinStrap:
      mass = _jawBand(r, thick: 2.8, topY: 100);
      break;

    case BeardRegion.mutton:
      mass = _spline([
        Offset(_cx + r.headX(70) + 0.5, 70),
        Offset(_cx + r.headX(96) + 2.8, 96),
        Offset(_cx + r.headX(116) + 2.0, 116),
        Offset(_cx + r.headX(118) - 7, 118),
        Offset(_cx + r.headX(96) - 8.4, 96),
        Offset(_cx + r.headX(76) - 4.0, 74),
      ], closed: true);
      break;

    case BeardRegion.goatee:
    case BeardRegion.circle:
      mass = _spline([
        Offset(_cx - mh * 0.95, r.mouthY + 3),
        Offset(_cx - mh * 0.55, lipB + 1.4),
        Offset(_cx, lipB + 2.4),
        Offset(_cx + mh * 0.55, lipB + 1.4),
        Offset(_cx + mh * 0.95, r.mouthY + 3),
        Offset(_cx + mh * 0.82, r.chinY - 3),
        Offset(_cx + 2, r.chinY + 4),
        Offset(_cx - 2, r.chinY + 4),
        Offset(_cx - mh * 0.82, r.chinY - 3),
      ], closed: true);
      break;

    case BeardRegion.vanDyke:
    case BeardRegion.anchor:
      mass = _spline([
        Offset(_cx - mh * 0.62, lipB + 0.6),
        Offset(_cx, lipB + 2.2),
        Offset(_cx + mh * 0.62, lipB + 0.6),
        Offset(_cx + mh * 0.5, r.chinY - 5),
        Offset(_cx + 1.4, r.chinY + 10),
        Offset(_cx - 1.4, r.chinY + 10),
        Offset(_cx - mh * 0.5, r.chinY - 5),
      ], closed: true);
      break;

    case BeardRegion.soulPatch:
      mass = Path()..addOval(Rect.fromCenter(center: Offset(_cx, lipB + 3.6), width: 6.6, height: 5.2));
      break;

    case BeardRegion.chinPuff:
      mass = Path()..addOval(Rect.fromCenter(center: Offset(_cx, r.chinY - 6.5), width: 15, height: 9));
      break;

    case BeardRegion.balbo:
      mass = _spline([
        Offset(_cx - mh * 1.1, r.mouthY + 2),
        Offset(_cx - mh * 0.6, lipB + 1.4),
        Offset(_cx, lipB + 2.2),
        Offset(_cx + mh * 0.6, lipB + 1.4),
        Offset(_cx + mh * 1.1, r.mouthY + 2),
        Offset(_cx + r.chinHalf * 1.0, r.chinY - 1),
        Offset(_cx, r.chinY + 9),
        Offset(_cx - r.chinHalf * 1.0, r.chinY - 1),
      ], closed: true);
      break;
  }

  if (spec.region == BeardRegion.neckOnly) {
    canvas.save();
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx, r.chinY + 9), width: r.jawHalf * 1.5, height: 15),
      r.soft(_alpha(r.hairColor, 0.55), 2.4),
    );
    if (r.detailed) {
      final rng = r.rngFor(620);
      final dots = <Offset>[];
      for (var i = 0; i < 260; i++) {
        final p = Offset(_cx + (rng.nextDouble() * 2 - 1) * r.jawHalf * 0.72, r.chinY + 2 + rng.nextDouble() * 15);
        if (((p.dx - _cx) / (r.jawHalf * 0.72)).abs() + ((p.dy - r.chinY - 9) / 8).abs() < 1.2) dots.add(p);
      }
      canvas.drawPoints(ui.PointMode.points, dots, Paint()..strokeWidth = 0.65..strokeCap = StrokeCap.round..color = _alpha(r.hairDark, 0.5));
    }
    canvas.restore();
  }

  if (mass != null) {
    if (stubble) {
      _stubbleFill(canvas, r, mass, d, 600 + spec.region.index);
    } else if (spec.region == BeardRegion.jawline || spec.region == BeardRegion.chinStrap) {
      _beardHair(canvas, r, mass, density: 0.94, seed: 601, len: 4);
    } else {
      final thick = spec.region == BeardRegion.fullLong ||
          spec.region == BeardRegion.viking ||
          spec.region == BeardRegion.garibaldi ||
          spec.region == BeardRegion.lumberjack;
      _beardHair(canvas, r, mass, density: d.clamp(0.6, 1.0), seed: 602 + spec.region.index, len: thick ? 9 : 6, fade: true);
      // Yanak çizgisinde yumuşak kenar.
      feather = [
        Offset(_cx - r.headX(90) + 3.4, 90),
        Offset(_cx - r.headX(100) + 4.6, 101),
        Offset(_cx - mh * 1.34, r.mouthY - 4),
        Offset(_cx + r.headX(90) - 3.4, 90),
        Offset(_cx + r.headX(100) - 4.6, 101),
        Offset(_cx + mh * 1.34, r.mouthY - 4),
      ];
      _beardFeather(canvas, r, feather, seed: 640);
    }
  }

  // Sideburn (favori)
  if (spec.sideburn > 0 && spec.region != BeardRegion.mutton) {
    final sb = spec.sideburn;
    r.mirroredPaths((sgn) {
      final len = 14.0 + 16 * sb;
      final path = _spline([
        Offset(_cx + sgn * (r.headX(72) + 0.4), 70),
        Offset(_cx + sgn * (r.headX(72 + len) + 1.2), 72 + len),
        Offset(_cx + sgn * (r.headX(72 + len) - (2.6 + 1.6 * sb)), 72 + len),
        Offset(_cx + sgn * (r.headX(84) - (3.0 + 1.4 * sb)), 82),
      ], closed: true);
      _beardHair(canvas, r, path, density: 0.95, seed: 650 + (sgn > 0 ? 1 : 0), len: 5);
    });
  }

  _paintMustache(canvas, r, spec.mustache, d);
}
