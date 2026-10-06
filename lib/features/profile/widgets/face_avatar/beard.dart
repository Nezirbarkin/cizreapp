part of '../face_avatar_painter.dart';

// ============================================================================
// SAKAL / BIYIK / FAVORİ (Bitmoji tarzı)
//
// Dolgun sakallar tek parça kütle: dolgu + cel gölge + aşağı akan kısa çizgiler
// + kontur. Üç günlük sakal ise konturu olmayan yarı saydam gölge ve nokta
// dokusudur. Ağız her zaman açıkta kalır (dudak bölgesi kütleden çıkarılır).
// ============================================================================

Color _beardColor(_Rig r) => _mix(r.hairColor, r.browColor, 0.30);

/// Alt dudağın alt kenarı (yaklaşık).
double _lipBottomY(_Rig r) {
  final open = math.max(0.0, r.m.smile - 0.60) * 13.0 + (r.lip.corner > 1.2 ? 2.2 : 0);
  return r.mouthY + 4.2 * r.lip.lower * r.m.lipFullness + open + 0.8;
}

/// Ağız deliği: dudaklar ve hemen çevresi.
Path _mouthHole(_Rig r, {double pad = 0.8}) {
  final top = r.mouthY - 2.6 * r.lip.upper * r.m.lipFullness - 0.6 - 3.0 * r.m.smile - 1.7 * r.lip.corner;
  final bottom = _lipBottomY(r) + pad;
  final w = r.mouthHalf + pad;
  return Path()
    ..addRRect(RRect.fromLTRBR(_cx - w, top, _cx + w, bottom, Radius.circular(math.min(w, (bottom - top) / 2))));
}

/// Çene hattının sağ yarısı: [top]'tan çene ucuna (aşağı doğru) noktalar.
List<Offset> _jawRight(_Rig r, double top, {int n = 16}) {
  final pts = r.headEdge(top, r.chinY - 0.6, n: n);
  pts.add(Offset(_cx, r.chinY));
  return pts;
}

/// Dolgun sakal bölgesi.
/// [top]: favori/yanak üst sınırı; [len]: çenede uzama; [lenSide]: yanlarda;
/// [inset]: yanak çizgisinin içe girmesi; [point]: çenede sivri uç ekleme.
Path _beardMass(_Rig r, {required double top, required double len, required double lenSide, double inset = 0, double point = 0, double round = 0}) {
  final jaw = _jawRight(r, top);
  final outer = <Offset>[];
  for (var i = 0; i < jaw.length; i++) {
    final prev = jaw[math.max(0, i - 1)];
    final next = jaw[math.min(jaw.length - 1, i + 1)];
    final d = _norm(next - prev);
    final out = Offset(d.dy, -d.dx);
    final t = i / (jaw.length - 1);
    var l = lenSide + (len - lenSide) * math.pow(t, 2.2);
    l += point * math.exp(-math.pow((1 - t) * 6, 2));
    l += round * math.sin(t * math.pi) * 0.6;
    outer.add(jaw[i] + out * l + Offset(0, l * 0.25 * t));
  }
  outer.last = Offset(_cx, outer.last.dy);

  final lipB = _lipBottomY(r);
  // Yanak çizgisi: favoriden önce dar bir şerit halinde iner, sonra ağız
  // köşesine doğru çapraz kesilir (Bitmoji sakal hattı).
  final sideW = 5.5 + 2 * inset.abs() / 3;
  final innerRight = _sampleSpline([
    Offset(_cx + r.headX(top) - 0.8, top),
    Offset(_cx + r.headX(top + 7) - sideW, top + 7),
    Offset(_cx + _lerpD(r.headX(r.noseBaseY) - sideW - 2, r.mouthHalf + 6 + inset, 0.45), r.noseBaseY),
    Offset(_cx + r.mouthHalf + 5 + inset, r.noseBaseY + 4.5),
    Offset(_cx + r.mouthHalf + 1.2, r.mouthY + 0.5),
    Offset(_cx + r.mouthHalf * 0.55, lipB + 0.8),
    Offset(_cx, lipB + 1.2),
  ], 18);

  final path = Path();
  final leftOuter = outer.map(_mirX).toList();
  path.moveTo(leftOuter.first.dx, leftOuter.first.dy);
  for (final p in leftOuter.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in outer.reversed.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in innerRight) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in innerRight.reversed.skip(1)) {
    final q = _mirX(p);
    path.lineTo(q.dx, q.dy);
  }
  path.close();
  return path;
}

/// Çene hattı boyunca şerit (çene şeridi, ince hat, boyun sakalı).
Path _jawBand(_Rig r, {required double top, required double outer, required double inner}) {
  final jaw = _jawRight(r, top, n: 18);
  final out = <Offset>[];
  final inn = <Offset>[];
  for (var i = 0; i < jaw.length; i++) {
    final prev = jaw[math.max(0, i - 1)];
    final next = jaw[math.min(jaw.length - 1, i + 1)];
    final d = _norm(next - prev);
    final n = Offset(d.dy, -d.dx);
    out.add(jaw[i] + n * outer);
    inn.add(jaw[i] - n * inner);
  }
  out.last = Offset(_cx, out.last.dy);
  inn.last = Offset(_cx, inn.last.dy);
  final path = Path();
  final all = <Offset>[
    ...out.map(_mirX),
    ...out.reversed.skip(1),
    ...inn,
    ...inn.reversed.skip(1).map(_mirX),
  ];
  path.addPolygon(all, true);
  return path;
}

/// Dudak altından çene ucuna küçük bölge (keçi, çene ucu).
Path _chinPatch(_Rig r, {required double halfW, required double len, double point = 0, double top = 0}) {
  final lipB = _lipBottomY(r) + 1.2 + top;
  final bottom = r.chinY + len;
  return Path()
    ..moveTo(_cx - halfW, lipB + 1)
    ..quadraticBezierTo(_cx, lipB - 1.2, _cx + halfW, lipB + 1)
    ..cubicTo(_cx + halfW * 1.15, _lerpD(lipB, bottom, 0.55), _cx + halfW * 0.6, bottom - point * 0.3, _cx, bottom + point)
    ..cubicTo(_cx - halfW * 0.6, bottom - point * 0.3, _cx - halfW * 1.15, _lerpD(lipB, bottom, 0.55), _cx - halfW, lipB + 1)
    ..close();
}

/// Dolgun sakalı boyar.
void _paintBeardMass(Canvas canvas, _Rig r, Path region, {required int seed, double density = 1.0}) {
  final col = _beardColor(r);
  final hole = _mouthHole(r);
  var shaped = Path.combine(PathOperation.difference, region, hole);
  if (r.detailed) shaped = _wobble(shaped, 0.6, seed, step: 2.0);
  final base = Color.alphaBlend(_alpha(col, density.clamp(0.0, 1.0)), r.skin);
  canvas.drawPath(shaped, r.fill(base));
  r.celShade(canvas, shaped, _alpha(_mix(col, r.hairShadow, 0.6), 0.9), base: base, offset: const Offset(-6, -4), blur: r.detailed ? 1.0 : 0);

  // Aşağı akan kısa tutam çizgileri + sol yanakta parlama.
  final b = shaped.getBounds();
  final rng = r.rngFor(seed);
  Offset flow(Offset p) => _norm(Offset((p.dx - _cx) / 60, 1));
  final seeds = _seedsIn(shaped, b, r.detailed ? (8 + b.width * b.height / 220).round().clamp(8, 26) : 5, rng);
  canvas.save();
  canvas.clipPath(shaped);
  for (final s in seeds) {
    final d = flow(s);
    final l = 3.5 + rng.nextDouble() * 3.5;
    canvas.drawPath(_taperPath([s, s + d * (l * 0.5) + const Offset(0.4, 0), s + d * l], 0.3, 0.1, wMid: 1.1),
        r.fill(_alpha(r.hairShadow, 0.8)));
  }
  canvas.drawOval(
    Rect.fromLTWH(b.left + b.width * 0.12, b.top + b.height * 0.35, b.width * 0.3, b.height * 0.4),
    r.soft(_alpha(r.hairLight, 0.30), r.detailed ? 4 : 0),
  );
  if (r.detailed) {
    for (final s in _seedsIn(shaped, Rect.fromLTWH(b.left, b.top + b.height * 0.25, b.width * 0.35, b.height * 0.5), 4, rng)) {
      canvas.drawPath(_taperPath([s, s + const Offset(0.5, 3), s + const Offset(0.6, 6)], 0.4, 0.1, wMid: 1.5),
          r.fill(_alpha(r.hairLight, 0.7)));
    }
  }
  canvas.restore();
  canvas.drawPath(shaped, r.stroke(_alpha(r.hairLine, 0.9), r.lineW * 0.9));
}

/// Üç günlük sakal: konturu olmayan gölge + nokta dokusu.
void _paintStubble(Canvas canvas, _Rig r, Path region, double density, int seed) {
  final col = _beardColor(r);
  final shaped = Path.combine(PathOperation.difference, region, _mouthHole(r, pad: 0.8));
  canvas.save();
  canvas.clipPath(r.head);
  canvas.drawPath(shaped, r.soft(_alpha(_mix(col, r.skin, 0.25), 0.22 + 0.36 * density), r.detailed ? 1.6 : 0));
  if (r.detailed) {
    canvas.clipPath(shaped);
    final rng = r.rngFor(seed);
    final b = shaped.getBounds();
    final n = (b.width * b.height * 0.22 * density).round();
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      pts.add(Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height));
    }
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..strokeWidth = 0.6
        ..strokeCap = StrokeCap.round
        ..color = _alpha(_mix(col, Colors.black, 0.2), 0.35 + 0.3 * density),
    );
  }
  canvas.restore();
}

// ------------------------------------------------------------------- bıyık
Path _mustachePath(_Rig r, MustacheKind kind) {
  final w = r.mouthHalf;
  final lift = 3.0 * r.m.smile + 1.7 * r.lip.corner;
  final top = r.noseBaseY + 1.6;
  final lipTop = r.mouthY - 2.6 * r.lip.upper * r.m.lipFullness - 0.8;
  final cornerY = r.mouthY - lift + 0.5;

  // Sağ yarı tarif (merkezden köşeye), sonra aynalanır.
  Path sym(List<Offset> topEdge, List<Offset> bottomEdge) {
    // topEdge: merkezden dışa (x merkezden uzaklık); bottomEdge: dıştan merkeze.
    final right = <Offset>[...topEdge, ...bottomEdge];
    final path = Path();
    final pts = <Offset>[
      ...right.map((p) => Offset(_cx + p.dx, p.dy)),
      ...right.reversed.map((p) => Offset(_cx - p.dx, p.dy)),
    ];
    path.addPolygon(_sampleSpline(pts, 48), true);
    return path;
  }

  switch (kind) {
    case MustacheKind.none:
      return Path();
    case MustacheKind.thin:
      return sym(
        [Offset(0, lipTop - 2.2), Offset(w * 0.5, lipTop - 2.0), Offset(w * 0.95, cornerY - 1.0)],
        [Offset(w * 1.0, cornerY + 0.2), Offset(w * 0.5, lipTop - 0.4), Offset(0.01, lipTop - 0.2)],
      );
    case MustacheKind.toothbrush:
      return Path()
        ..addRRect(RRect.fromLTRBR(_cx - r.noseHalf * 0.9, top + 0.5, _cx + r.noseHalf * 0.9, lipTop + 0.4, const Radius.circular(1.5)));
    case MustacheKind.thick:
    case MustacheKind.chevron:
      final drop = kind == MustacheKind.chevron ? 3.2 : 1.6;
      return sym(
        [Offset(0, top + 0.4), Offset(w * 0.45, top + 0.8), Offset(w * 0.95, cornerY - 3)],
        [Offset(w * 1.12, cornerY + drop), Offset(w * 0.55, lipTop + 1.2), Offset(0.01, lipTop + 0.6)],
      );
    case MustacheKind.walrus:
      return sym(
        [Offset(0, top), Offset(w * 0.5, top + 0.4), Offset(w * 1.05, cornerY - 2)],
        [Offset(w * 1.18, cornerY + 5.5), Offset(w * 0.6, r.mouthY + 3.4), Offset(0.01, r.mouthY + 2.4)],
      );
    case MustacheKind.handlebar:
      return sym(
        [Offset(0, top + 1.6), Offset(w * 0.5, lipTop - 1.8), Offset(w * 1.15, cornerY - 2.4), Offset(w * 1.45, cornerY - 7.5)],
        [Offset(w * 1.36, cornerY - 4.2), Offset(w * 0.9, cornerY + 0.4), Offset(w * 0.4, lipTop + 0.2), Offset(0.01, lipTop + 0.2)],
      );
    case MustacheKind.fuManchu:
      return sym(
        [Offset(0, lipTop - 2.4), Offset(w * 0.6, lipTop - 2.0), Offset(w * 1.05, cornerY), Offset(w * 1.15, r.chinY + 6)],
        [Offset(w * 0.98, r.chinY + 8), Offset(w * 0.92, cornerY + 2), Offset(w * 0.5, lipTop), Offset(0.01, lipTop)],
      );
    case MustacheKind.horseshoe:
      return sym(
        [Offset(0, top + 0.8), Offset(w * 0.6, top + 1.2), Offset(w * 1.12, cornerY - 1), Offset(w * 1.2, r.chinY - 3)],
        [Offset(w * 0.92, r.chinY - 3), Offset(w * 0.92, cornerY + 2), Offset(w * 0.5, lipTop + 0.6), Offset(0.01, lipTop + 0.6)],
      );
    case MustacheKind.imperial:
      return sym(
        [Offset(0, top + 0.6), Offset(w * 0.6, top + 0.6), Offset(w * 1.1, cornerY - 4), Offset(w * 1.35, cornerY - 8)],
        [Offset(w * 1.25, cornerY - 3.5), Offset(w * 0.6, lipTop + 1.0), Offset(0.01, lipTop + 0.6)],
      );
    case MustacheKind.natural:
      return sym(
        [Offset(0, top + 1.0), Offset(w * 0.5, top + 1.6), Offset(w * 1.0, cornerY - 1.6)],
        [Offset(w * 1.08, cornerY + 1.0), Offset(w * 0.5, lipTop + 0.5), Offset(0.01, lipTop + 0.1)],
      );
  }
}

void _paintMustache(Canvas canvas, _Rig r, MustacheKind kind, double density) {
  if (kind == MustacheKind.none) return;
  final path = _mustachePath(r, kind);
  final col = _beardColor(r);
  if (density < 0.6) {
    canvas.drawPath(path, r.soft(_alpha(col, 0.25 + 0.5 * density), r.detailed ? 1.0 : 0));
    return;
  }
  canvas.drawPath(path, r.fill(col));
  r.celShade(canvas, path, _alpha(_mix(col, r.hairShadow, 0.6), 0.9), base: col, offset: const Offset(-4, -2.5), blur: 0);
  canvas.save();
  canvas.clipPath(path);
  final b = path.getBounds();
  final rng = r.rngFor(410 + kind.index);
  for (var i = 0; i < (r.detailed ? 10 : 4); i++) {
    final x = b.left + rng.nextDouble() * b.width;
    final y = b.top + rng.nextDouble() * b.height * 0.6;
    final dx = (x - _cx) / 12;
    canvas.drawLine(Offset(x, y), Offset(x + dx * 1.6, y + 2.6), r.stroke(_alpha(r.hairShadow, 0.85), 0.8));
  }
  canvas.restore();
  canvas.drawPath(path, r.stroke(_alpha(r.hairLine, 0.9), r.lineW * 0.85));
}

// -------------------------------------------------------------------- ana
void _paintBeard(Canvas canvas, _Rig r) {
  final spec = r.beard;
  if (spec.isNone) return;
  final density = spec.density;
  // Dolgun sakal favoriye bağlanır ama göz hizasına çıkmaz.
  final earMid = (r.earTop + r.earBottom) / 2;
  final sideEnd = r.hair.bald || r.hair.covered ? earMid : _HairGeo(r).sideEndY;
  final topFull = sideEnd.clamp(r.earTop + 8, earMid + 2).toDouble();

  // ---- favori
  if (spec.sideburn > 0) {
    final g = _HairGeo(r);
    final y0 = math.min(g.sideEndY, r.earTop + 2) - 2;
    final y1 = y0 + 12 + 10 * spec.sideburn;
    r.mirrored(canvas, (c, mir) {
      final edge = r.headEdge(y0, y1, n: 6);
      final p = Path()..moveTo(_cx - (edge.first.dx - _cx) + 0.5, edge.first.dy);
      for (final q in edge.skip(1)) {
        p.lineTo(_cx - (q.dx - _cx) + 0.5, q.dy);
      }
      p.lineTo(_cx - (edge.last.dx - _cx) + 6.5, y1 - 2);
      for (final q in edge.reversed.skip(1)) {
        p.lineTo(_cx - (q.dx - _cx) + 6.0, q.dy);
      }
      p.close();
      c.drawPath(p, r.fill(_beardColor(r)));
      c.drawPath(p, r.stroke(_alpha(r.hairLine, 0.85), r.lineW * 0.85));
    });
  }

  // Bıyıkla birleşen sakallarda ağız çevresinde ten boşluğu kalmasın.
  final hug = spec.mustache == MustacheKind.none ? 0.0 : -4.0;

  switch (spec.region) {
    case BeardRegion.none:
      break;
    case BeardRegion.stubbleLight:
    case BeardRegion.stubbleMedium:
    case BeardRegion.stubbleHeavy:
      _paintStubble(canvas, r, _beardMass(r, top: topFull + 2, len: 1.5, lenSide: 0.5, inset: -2), density, 400);
      break;
    case BeardRegion.jawline:
      _paintBeardMass(canvas, r, _jawBand(r, top: topFull + 4, outer: 2.2, inner: 1.6), seed: 401, density: density);
      break;
    case BeardRegion.chinStrap:
      _paintBeardMass(canvas, r, _jawBand(r, top: topFull, outer: 3.2, inner: 3.4), seed: 402, density: density);
      break;
    case BeardRegion.neckOnly:
      _paintStubble(canvas, r, _jawBand(r, top: topFull + 6, outer: 6, inner: -0.5), 0.9, 403);
      break;
    case BeardRegion.short:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull + 3, len: 4.5, lenSide: 2.2, inset: hug), seed: 404, density: density);
      break;
    case BeardRegion.boxed:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull + 2, len: 6.5, lenSide: 3.2, inset: -3 + hug), seed: 405, density: density);
      break;
    case BeardRegion.full:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull, len: 9.5, lenSide: 4.4, inset: -1 + hug), seed: 406, density: density);
      break;
    case BeardRegion.fullLong:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull, len: 22, lenSide: 5.5, inset: -1 + hug, point: 5), seed: 407, density: density);
      break;
    case BeardRegion.garibaldi:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull, len: 17, lenSide: 7, inset: -1 + hug, round: 8), seed: 408, density: density);
      break;
    case BeardRegion.ducktail:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull + 1, len: 12, lenSide: 4, inset: hug, point: 9), seed: 409, density: density);
      break;
    case BeardRegion.lumberjack:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull - 2, len: 15, lenSide: 7.5, inset: -3 + hug, round: 4), seed: 410, density: density);
      break;
    case BeardRegion.viking:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull - 2, len: 34, lenSide: 9, inset: -3 + hug, point: 8, round: 6), seed: 411, density: density);
      break;
    case BeardRegion.balbo:
      final chin = _chinPatch(r, halfW: r.mouthHalf + 4, len: 4.5);
      _paintBeardMass(canvas, r, chin, seed: 412, density: density);
      break;
    case BeardRegion.goatee:
      _paintBeardMass(canvas, r, _chinPatch(r, halfW: r.mouthHalf * 0.72, len: 4.0), seed: 413, density: density);
      break;
    case BeardRegion.vanDyke:
      _paintBeardMass(canvas, r, _chinPatch(r, halfW: r.mouthHalf * 0.55, len: 5.5, point: 5), seed: 414, density: density);
      break;
    case BeardRegion.chinPuff:
      _paintBeardMass(canvas, r, _chinPatch(r, halfW: r.mouthHalf * 0.5, len: 3.0, top: (r.chinY - _lipBottomY(r)) * 0.45), seed: 415, density: density);
      break;
    case BeardRegion.soulPatch:
      final lipB = _lipBottomY(r);
      final p = Path()
        ..moveTo(_cx - 3.2, lipB + 1.2)
        ..quadraticBezierTo(_cx, lipB + 0.4, _cx + 3.2, lipB + 1.2)
        ..lineTo(_cx, lipB + 8.5)
        ..close();
      _paintBeardMass(canvas, r, p, seed: 416, density: density);
      break;
    case BeardRegion.anchor:
      final chin = _chinPatch(r, halfW: r.mouthHalf * 0.6, len: 4.5, point: 2);
      final strap = _jawBand(r, top: r.mouthY - 2, outer: 2.6, inner: 2.6);
      _paintBeardMass(canvas, r, Path.combine(PathOperation.union, chin, strap), seed: 417, density: density);
      break;
    case BeardRegion.circle:
      final lipB = _lipBottomY(r);
      final ring = Path()
        ..addOval(Rect.fromLTRB(_cx - r.mouthHalf - 4.5, r.noseBaseY + 1.5, _cx + r.mouthHalf + 4.5, math.max(lipB + 10, r.chinY + 3)));
      _paintBeardMass(canvas, r, ring, seed: 418, density: density);
      break;
    case BeardRegion.mutton:
      final mass = _beardMass(r, top: topFull, len: 6, lenSide: 3.5, inset: -2 + hug);
      final chinClear = Path()..addOval(Rect.fromCenter(center: Offset(_cx, r.chinY - 3), width: r.mouthHalf * 2.1, height: (r.chinY - r.mouthY) * 2.0 + 8));
      _paintBeardMass(canvas, r, Path.combine(PathOperation.difference, mass, chinClear), seed: 419, density: density);
      break;
  }

  _paintMustache(canvas, r, spec.mustache, density);
}
