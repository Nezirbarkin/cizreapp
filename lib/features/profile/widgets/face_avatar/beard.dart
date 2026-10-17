part of '../face_avatar_painter.dart';

// ============================================================================
// SAKAL / BIYIK / FAVORİ (yarı gerçekçi)
//
// Dolgun sakal kontursuz bir kütledir: altındaki deri koyulaşır, kütle yanağa
// doğru seyrelerek deriye karışır, içi ve kenarı yüzlerce kısa, kıvrık telden
// oluşur (siluet tel tel taşar). Üç günlük sakal serin bir gölge ve yoğun kıl
// noktalarıdır. Ağız her zaman açıkta kalır (dudak bölgesi kütleden çıkarılır).
// ============================================================================

Color _beardColor(_Rig r) => _mix(r.hairColor, r.browColor, 0.30);

/// Alt dudağın alt kenarı (yaklaşık; `_paintMouth` ile aynı ölçüler).
double _lipBottomY(_Rig r) {
  final open = math.max(0.0, r.m.smile - 0.60) * 13.0 + (r.lip.corner > 1.2 ? 2.2 : 0);
  return r.mouthY + 4.4 * r.lip.lower * r.m.lipFullness + open + 0.8;
}

/// Ağız deliği: dudaklar ve hemen çevresi.
Path _mouthHole(_Rig r, {double pad = 0.8}) {
  final top = r.mouthY - 3.0 * r.lip.upper * r.m.lipFullness - 0.6 - 2.6 * r.m.smile - 1.5 * r.lip.corner;
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

/// Sakal/bıyık telleri: [region] içinde tohumlanır, [flow] yönünde kısa ve
/// hafif kıvrık; [avoid] (ağız) dışında kalacak biçimde kırpılır ama bölge
/// kenarından biraz taşabilir (tel tel siluet).
void _beardHairs(Canvas canvas, _Rig r, Path region, Offset Function(Offset p) flow,
    {required int seed, required double perArea, double len = 3.2, double width = 0.5, double light = 0.45, Path? avoid}) {
  final col = _beardColor(r);
  final b = region.getBounds();
  final rng = r.rngFor(seed + 300);
  final n = (b.width * b.height / perArea).round().clamp(6, r.detailed ? 1300 : 90);
  final dark = _alpha(r.hairShadow, 0.55);
  final base = _alpha(col, 0.65);
  final lit = _mix(col, r.hairLight, 0.6);
  canvas.save();
  if (avoid != null) {
    canvas.clipPath(Path.combine(PathOperation.difference, Path()..addRect(const Rect.fromLTWH(-20, -20, 240, 260)), avoid));
  }
  for (var i = 0, tries = 0; i < n && tries < n * 6; tries++) {
    final p = Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height);
    if (!region.contains(p)) continue;
    i++;
    final ang = (rng.nextDouble() - 0.5) * 0.8;
    final f = flow(p);
    final d = Offset(f.dx * math.cos(ang) - f.dy * math.sin(ang), f.dx * math.sin(ang) + f.dy * math.cos(ang));
    final l = len * (0.6 + 0.8 * rng.nextDouble());
    final bend = Offset(-d.dy, d.dx) * ((rng.nextDouble() - 0.5) * 1.2);
    final pts = [p, p + d * (l * 0.5) + bend * 0.5, p + d * l + bend];
    final k = rng.nextDouble();
    final litSide = (1 - (p.dx - b.left) / math.max(1.0, b.width)) * 0.7;
    final Color c = k < 0.45 ? dark : (k < 0.45 + light * litSide ? _alpha(lit, 0.55) : base);
    canvas.drawPath(_taperPath(pts, width, width * 0.15, wMid: width * 0.9), r.fill(c));
  }
  canvas.restore();
}

/// Sakal kılının yüzdeki akışı: yanaklarda aşağı ve biraz çeneye doğru.
Offset _beardFlow(Offset p) => _norm(Offset((_cx - p.dx) / 85, 1));

/// Dolgun sakalı boyar.
void _paintBeardMass(Canvas canvas, _Rig r, Path region, {required int seed, double density = 1.0, double hairLen = 3.4}) {
  final col = _beardColor(r);
  final hole = _mouthHole(r);
  var shaped = Path.combine(PathOperation.difference, region, hole);
  if (r.detailed) shaped = _wobble(shaped, 0.6, seed, step: 2.0);
  final dens = density.clamp(0.0, 1.0);
  final b = shaped.getBounds();

  // Altındaki deri: serin gölge (kıl dipleri), kenarı geniş ve yumuşak.
  canvas.drawPath(shaped, r.soft(_alpha(_mix(col, r.skinCool, 0.35), 0.45 * dens), r.detailed ? 2.4 : 0));
  // Gövde: yanak tarafında (üstte) seyrek, çenede yoğun.
  canvas.drawPath(
    shaped,
    Paint()
      ..maskFilter = r.detailed ? const MaskFilter.blur(BlurStyle.normal, 0.9) : null
      ..shader = ui.Gradient.linear(
        Offset(0, b.top),
        Offset(0, b.bottom),
        [_alpha(col, 0.18 * dens), _alpha(col, 0.86 * dens), _alpha(_mix(col, r.hairShadow, 0.30), 0.95 * dens)],
        [0.0, math.min(0.5, 16 / math.max(1.0, b.height)), 1.0],
      ),
  );
  canvas.save();
  canvas.clipPath(shaped);
  r.celShade(canvas, shaped, _alpha(r.hairShadow, 0.55 * dens), offset: const Offset(-6, -4), blur: 1.4);
  // Sol yanakta ışık.
  r.glow(canvas, Offset(b.left + b.width * 0.27, b.top + b.height * 0.55), b.width * 0.28, b.height * 0.45, _alpha(r.hairLight, 0.22 * dens), 4);
  canvas.restore();

  // Teller (içte yoğun, kenardan taşan).
  _beardHairs(canvas, r, shaped, _beardFlow, seed: seed, perArea: 2.4 / dens, len: hairLen * (0.75 + 0.35 * dens), avoid: hole);
}

/// Üç günlük sakal: serin gölge + yoğun kıl noktaları + birkaç kısa kıl.
void _paintStubble(Canvas canvas, _Rig r, Path region, double density, int seed) {
  final col = _beardColor(r);
  final shaped = Path.combine(PathOperation.difference, region, _mouthHole(r, pad: 0.8));
  canvas.save();
  canvas.clipPath(r.head);
  canvas.drawPath(shaped, r.soft(_alpha(_mix(col, r.skinCool, 0.45), 0.16 + 0.34 * density), r.detailed ? 2.6 : 0));
  if (r.detailed) {
    canvas.clipPath(shaped);
    final rng = r.rngFor(seed);
    final b = shaped.getBounds();
    final n = (b.width * b.height * 0.55 * density).round();
    final pts = <Offset>[];
    for (var i = 0; i < n; i++) {
      pts.add(Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height));
    }
    canvas.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..strokeWidth = 0.45
        ..strokeCap = StrokeCap.round
        ..color = _alpha(_mix(col, Colors.black, 0.25), 0.28 + 0.30 * density),
    );
    if (density > 0.5) {
      _beardHairs(canvas, r, shaped, _beardFlow, seed: seed + 1, perArea: 22 / density, len: 1.1, width: 0.35, light: 0.2);
    }
  }
  canvas.restore();
}

// ------------------------------------------------------------------- bıyık
Path _mustachePath(_Rig r, MustacheKind kind) {
  final w = r.mouthHalf;
  final lift = 2.6 * r.m.smile + 1.5 * r.lip.corner;
  final top = r.noseBaseY + 1.6;
  final lipTop = r.mouthY - 3.0 * r.lip.upper * r.m.lipFullness - 0.8;
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
  // Bıyık kılı ortadan iki yana, aşağı doğru taranır.
  Offset flow(Offset p) => _norm(Offset((p.dx - _cx) / 9, 1.1));
  if (density < 0.6) {
    canvas.drawPath(path, r.soft(_alpha(_mix(col, r.skinCool, 0.3), 0.20 + 0.45 * density), r.detailed ? 1.6 : 0));
    if (r.detailed) _beardHairs(canvas, r, path, flow, seed: 420 + kind.index, perArea: 6 / density, len: 1.6, width: 0.4, light: 0.2, avoid: _mouthHole(r, pad: 0));
    return;
  }
  final b = path.getBounds();
  canvas.drawPath(path, r.soft(_alpha(_mix(col, r.skinCool, 0.3), 0.5), r.detailed ? 1.6 : 0));
  canvas.drawPath(
    path,
    Paint()
      ..maskFilter = r.detailed ? const MaskFilter.blur(BlurStyle.normal, 0.7) : null
      ..shader = ui.Gradient.linear(Offset(0, b.top), Offset(0, b.bottom), [_alpha(col, 0.55), _alpha(col, 0.92), _alpha(_mix(col, r.hairShadow, 0.35), 0.95)], const [0.0, 0.4, 1.0]),
  );
  r.celShade(canvas, path, _alpha(r.hairShadow, 0.5), offset: const Offset(-4, -2.5), blur: 1.0);
  _beardHairs(canvas, r, path, flow, seed: 410 + kind.index, perArea: 1.8, len: 3.0, width: 0.5, avoid: _mouthHole(r, pad: -0.4));
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
      c.drawPath(p, r.soft(_alpha(_beardColor(r), 0.85), r.detailed ? 0.8 : 0));
      _beardHairs(c, r, p, (q) => const Offset(0.08, 1), seed: 430, perArea: 2.0, len: 2.6, width: 0.45);
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
      _paintBeardMass(canvas, r, _jawBand(r, top: topFull + 4, outer: 2.2, inner: 1.6), seed: 401, density: density, hairLen: 1.8);
      break;
    case BeardRegion.chinStrap:
      _paintBeardMass(canvas, r, _jawBand(r, top: topFull, outer: 3.2, inner: 3.4), seed: 402, density: density, hairLen: 2.2);
      break;
    case BeardRegion.neckOnly:
      _paintStubble(canvas, r, _jawBand(r, top: topFull + 6, outer: 6, inner: -0.5), 0.9, 403);
      break;
    case BeardRegion.short:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull + 3, len: 4.5, lenSide: 2.2, inset: hug), seed: 404, density: density, hairLen: 2.3);
      break;
    case BeardRegion.boxed:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull + 2, len: 6.5, lenSide: 3.2, inset: -3 + hug), seed: 405, density: density, hairLen: 2.8);
      break;
    case BeardRegion.full:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull, len: 9.5, lenSide: 4.4, inset: -1 + hug), seed: 406, density: density, hairLen: 3.4);
      break;
    case BeardRegion.fullLong:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull, len: 22, lenSide: 5.5, inset: -1 + hug, point: 5), seed: 407, density: density, hairLen: 4.6);
      break;
    case BeardRegion.garibaldi:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull, len: 17, lenSide: 7, inset: -1 + hug, round: 8), seed: 408, density: density, hairLen: 4.2);
      break;
    case BeardRegion.ducktail:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull + 1, len: 12, lenSide: 4, inset: hug, point: 9), seed: 409, density: density, hairLen: 3.8);
      break;
    case BeardRegion.lumberjack:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull - 2, len: 15, lenSide: 7.5, inset: -3 + hug, round: 4), seed: 410, density: density, hairLen: 4.2);
      break;
    case BeardRegion.viking:
      _paintBeardMass(canvas, r, _beardMass(r, top: topFull - 2, len: 34, lenSide: 9, inset: -3 + hug, point: 8, round: 6), seed: 411, density: density, hairLen: 5.0);
      break;
    case BeardRegion.balbo:
      final chin = _chinPatch(r, halfW: r.mouthHalf + 4, len: 4.5);
      _paintBeardMass(canvas, r, chin, seed: 412, density: density, hairLen: 2.6);
      break;
    case BeardRegion.goatee:
      _paintBeardMass(canvas, r, _chinPatch(r, halfW: r.mouthHalf * 0.72, len: 4.0), seed: 413, density: density, hairLen: 2.6);
      break;
    case BeardRegion.vanDyke:
      _paintBeardMass(canvas, r, _chinPatch(r, halfW: r.mouthHalf * 0.55, len: 5.5, point: 5), seed: 414, density: density, hairLen: 2.6);
      break;
    case BeardRegion.chinPuff:
      _paintBeardMass(canvas, r, _chinPatch(r, halfW: r.mouthHalf * 0.5, len: 3.0, top: (r.chinY - _lipBottomY(r)) * 0.45), seed: 415, density: density, hairLen: 2.4);
      break;
    case BeardRegion.soulPatch:
      final lipB = _lipBottomY(r);
      final p = Path()
        ..moveTo(_cx - 3.2, lipB + 1.2)
        ..quadraticBezierTo(_cx, lipB + 0.4, _cx + 3.2, lipB + 1.2)
        ..lineTo(_cx, lipB + 8.5)
        ..close();
      _paintBeardMass(canvas, r, p, seed: 416, density: density, hairLen: 2.2);
      break;
    case BeardRegion.anchor:
      final chin = _chinPatch(r, halfW: r.mouthHalf * 0.6, len: 4.5, point: 2);
      final strap = _jawBand(r, top: r.mouthY - 2, outer: 2.6, inner: 2.6);
      _paintBeardMass(canvas, r, Path.combine(PathOperation.union, chin, strap), seed: 417, density: density, hairLen: 2.6);
      break;
    case BeardRegion.circle:
      final lipB = _lipBottomY(r);
      final ring = Path()
        ..addOval(Rect.fromLTRB(_cx - r.mouthHalf - 4.5, r.noseBaseY + 1.5, _cx + r.mouthHalf + 4.5, math.max(lipB + 10, r.chinY + 3)));
      _paintBeardMass(canvas, r, ring, seed: 418, density: density, hairLen: 2.8);
      break;
    case BeardRegion.mutton:
      final mass = _beardMass(r, top: topFull, len: 6, lenSide: 3.5, inset: -2 + hug);
      final chinClear = Path()..addOval(Rect.fromCenter(center: Offset(_cx, r.chinY - 3), width: r.mouthHalf * 2.1, height: (r.chinY - r.mouthY) * 2.0 + 8));
      _paintBeardMass(canvas, r, Path.combine(PathOperation.difference, mass, chinClear), seed: 419, density: density, hairLen: 3.0);
      break;
  }

  _paintMustache(canvas, r, spec.mustache, density);
}
