part of '../face_avatar_painter.dart';

// ============================================================================
// TOPUZ / KUYRUK / ÖRGÜ / KAPALI SAÇ
// ============================================================================

/// Lastik toka.
void _hairTie(Canvas c, _Rig r, Offset at, double w, {double angle = 0}) {
  final col = r.hairLum > 0.25 ? const Color(0xFF3B3346) : const Color(0xFFD9578A);
  c.save();
  c.translate(at.dx, at.dy);
  c.rotate(angle);
  final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: w, height: 3.4), const Radius.circular(1.7));
  c.drawRRect(rect, r.fill(col));
  c.drawRRect(rect, r.stroke(_tone(col, -0.45), r.lineW * 0.8));
  c.restore();
}

/// Kuyruk/tutam: yaprak biçimli, sivri uçlu, akış çizgili.
void _tail(Canvas c, _Rig r, _HairGeo g, List<Offset> spine, double width, {int seed = 1, double tipW = 0.6, bool dark = false}) {
  final path0 = _taperPath(_sampleSpline(spine, 18), width * 0.6, tipW, wMid: width);
  final path = g.curly ? _scallop(path0, 1.4 + 1.2 * g.s.curl, 6, seed: seed) : path0;
  _hairFill(c, r, path, base: dark ? _mix(r.hairColor, r.hairShadow, 0.45) : null);
  if (g.curly) {
    _curlTexture(c, r, path, seed: seed + 1, radius: 2.8);
    return;
  }
  final pts = _sampleSpline(spine, 18);
  // Akış: omurga boyunca, birkaç paralel çizgi.
  c.save();
  c.clipPath(path);
  for (final off in [-0.25, 0.05, 0.3]) {
    final line = <Offset>[];
    for (var i = 1; i < pts.length - 2; i++) {
      final d = _norm(pts[i + 1] - pts[i - 1]);
      final nrm = Offset(-d.dy, d.dx);
      final t = i / (pts.length - 1);
      final wv = g.wavy ? math.sin(t * 9 + off * 4) * 1.4 : 0.0;
      line.add(pts[i] + nrm * (off * width * (1 - t * 0.7) + wv));
    }
    c.drawPath(_taperPath(line, 0.4, 0.1, wMid: 1.2), r.fill(_alpha(r.hairShadow, 0.85)));
  }
  final sheen = <Offset>[for (var i = 2; i < pts.length ~/ 2; i++) pts[i] + const Offset(-1.5, 0)];
  if (sheen.length > 1) c.drawPath(_taperPath(sheen, 0.6, 0.2, wMid: 1.8), r.fill(_alpha(r.hairLight, 0.75)));
  c.restore();
}

/// Örgü: omurga boyunca sağ-sol dönüşümlü yaprak dilimleri.
void _braid(Canvas c, _Rig r, _HairGeo g, List<Offset> spine, double width, {bool fish = false, int seed = 1}) {
  final pts = _sampleSpline(spine, 40);
  final n = fish ? 16 : 9;
  final segLen = (pts.length - 1) / n;
  for (var k = 0; k < n; k++) {
    final i0 = (k * segLen).round();
    final i1 = math.min(pts.length - 1, ((k + 1.25) * segLen).round());
    final a = pts[i0];
    final b = pts[i1];
    final d = _norm(b - a);
    final nrm = Offset(-d.dy, d.dx);
    final t = k / n;
    final w = width * (1 - 0.45 * t);
    final sgn = k.isEven ? 1.0 : -1.0;
    final from = a + nrm * (sgn * w * 0.45);
    final to = b - nrm * (sgn * w * 0.15);
    final leaf = _taperPath(_quadPts(from, (from + to) / 2 + nrm * (-sgn * w * 0.15), to, 6), w * 0.45, w * 0.2, wMid: w * (fish ? 0.55 : 0.75));
    c.drawPath(leaf, r.fill(k.isEven ? r.hairColor : _mix(r.hairColor, r.hairShadow, 0.25)));
    if (!fish) {
      r.celShade(c, leaf, _alpha(r.hairShadow, 0.7), base: k.isEven ? r.hairColor : _mix(r.hairColor, r.hairShadow, 0.25), offset: const Offset(-2, -2), blur: 0);
    }
    c.drawPath(leaf, r.stroke(r.hairLine, r.lineW * 0.85));
  }
  final end = pts.last;
  _hairTie(c, r, end, width * 0.55, angle: math.atan2(pts.last.dy - pts[pts.length - 3].dy, pts.last.dx - pts[pts.length - 3].dx) + math.pi / 2);
  // Uçtaki püskül.
  final d = _norm(pts.last - pts[pts.length - 4]);
  _tail(c, r, g, [end, end + d * 5, end + d * 9], width * 0.55, seed: seed + 9);
}

/// Topuz: yuvarlak kütle + sarmal çizgiler.
void _bun(Canvas c, _Rig r, _HairGeo g, Offset center, double rad, {bool messy = false, bool ballet = false, int seed = 1}) {
  var path = Path()..addOval(Rect.fromCircle(center: center, radius: rad));
  if (messy || g.curly) path = _scallop(path, messy ? 1.8 : 1.4, messy ? 7 : 5, seed: seed);
  _hairFill(c, r, path);
  if (g.curly) {
    _curlTexture(c, r, path, seed: seed + 1, radius: 2.6);
  } else {
    c.save();
    c.clipPath(path);
    for (var i = 0; i < 3; i++) {
      final rr = rad * (0.35 + i * 0.22);
      c.drawArc(Rect.fromCircle(center: center.translate(rad * 0.1, rad * 0.05), radius: rr), -0.4 + i * 0.6, 2.4, false,
          r.stroke(_alpha(r.hairShadow, 0.9), 1.1));
    }
    c.drawArc(Rect.fromCircle(center: center, radius: rad * 0.62), math.pi * 1.05, 1.1, false, r.stroke(_alpha(r.hairLight, 0.85), 1.8));
    c.restore();
  }
  if (ballet) {
    c.drawOval(Rect.fromCenter(center: center.translate(0, rad * 0.86), width: rad * 1.3, height: 3.2), r.fill(_tone(r.hairColor, -0.4)));
  }
  if (messy && r.detailed) {
    final rng = r.rngFor(seed + 5);
    for (var i = 0; i < 4; i++) {
      final a = -math.pi * (0.15 + 0.7 * rng.nextDouble());
      final p0 = center + Offset(math.cos(a), math.sin(a)) * rad * 0.9;
      final p1 = center + Offset(math.cos(a), math.sin(a)) * (rad + 5 + rng.nextDouble() * 4) + Offset((rng.nextDouble() - 0.5) * 5, 0);
      _taper(c, [p0, (p0 + p1) / 2 + const Offset(1.5, 0), p1], 1.4, 0.2, r.fill(r.hairColor));
      c.drawPath(_taperPath([p0, (p0 + p1) / 2 + const Offset(1.5, 0), p1], 1.4, 0.2), r.stroke(r.hairLine, 0.5));
    }
  }
}

// ======================================================================= ARKA
void _paintTieBack(Canvas canvas, _Rig r, _HairGeo g) {
  final tie = r.tie;
  final topY = g.topY;
  final W = g.W;
  final side = g.side.toDouble();
  switch (tie) {
    case HairTie.bunHigh:
      _bun(canvas, r, g, Offset(_cx, math.max(topY - 7, 12.5)), 12.5, seed: 150);
      break;
    case HairTie.bunTop:
      _bun(canvas, r, g, Offset(_cx, math.max(topY - 4, 11.0)), 10.0, seed: 151);
      break;
    case HairTie.bunMessy:
      _bun(canvas, r, g, Offset(_cx + 3, math.max(topY - 7, 13.0)), 13.5, messy: true, seed: 152);
      break;
    case HairTie.bunBallet:
      _bun(canvas, r, g, Offset(_cx, math.max(topY - 6, 11.5)), 11.5, ballet: true, seed: 153);
      break;
    case HairTie.bunLow:
      _bun(canvas, r, g, Offset(_cx + side * (r.jawHalf + 4), r.gonionY + 2), 12.5, seed: 154);
      break;
    case HairTie.halfBun:
      _bun(canvas, r, g, Offset(_cx, math.max(topY - 3, 10.0)), 8.5, seed: 155);
      break;
    case HairTie.halfUp:
      _tail(canvas, r, g, [Offset(_cx, topY + 6), Offset(_cx + side * 6, topY - 2), Offset(_cx + side * 12, topY + 2)], 7, seed: 156);
      break;
    case HairTie.ponyHigh:
      _tail(canvas, r, g, [
        Offset(_cx + side * 6, topY + 10),
        Offset(_cx + side * (W * 0.62), topY - 3),
        Offset(_cx + side * (W + 10), _HairGeo.yc - 6),
        Offset(_cx + side * (W + 13), 118),
        Offset(_cx + side * (W + 7), 154),
      ], 26, seed: 157, dark: true, tipW: 1.0);
      break;
    case HairTie.ponyLow:
      _tail(canvas, r, g, [
        Offset(_cx + side * (r.jawHalf * 0.5), r.chinY - 18),
        Offset(_cx + side * (r.cheekHalf + 7), r.chinY - 2),
        Offset(_cx + side * (r.cheekHalf + 13), 166),
        Offset(_cx + side * (r.cheekHalf + 10), 194),
      ], 22, seed: 158, dark: true, tipW: 1.0);
      break;
    case HairTie.afroPuffs:
      for (final sgn in [-1.0, 1.0]) {
        _bun(canvas, r, g, Offset(_cx + sgn * g.fh * 0.78, topY + 7), 17, seed: 159 + (sgn > 0 ? 1 : 0));
      }
      break;
    case HairTie.boxBraids:
    case HairTie.dreads:
      _locsBack(canvas, r, g, braided: tie == HairTie.boxBraids);
      break;
    default:
      break;
  }
}

/// Tepe kütlesinin ALTINDA kalan parçalar (kubbe bunları örter).
void _paintTieUnder(Canvas canvas, _Rig r, _HairGeo g) {
  switch (r.tie) {
    case HairTie.mohawk:
      final hl = g.hl;
      final top = math.max(g.topY - 8, 4.0);
      final p = Path()..moveTo(_cx - 10, hl + 3);
      p.cubicTo(_cx - 14, _lerpD(hl, top, 0.45), _cx - 19, top + 14, _cx - 16, top + 8);
      final rng = r.rngFor(170);
      final crest = [for (var i = 0; i <= 6; i++) Offset(_cx - 16 + i * 5.33, top + 8 - math.sin(i / 6 * math.pi) * 6)];
      final tips = _tipsAlong(crest, (i, mid) => _norm(Offset((mid.dx - _cx) * 0.04 + 0.3, -1)), 7.0, rng, jitter: 0.4);
      _appendTips(p, crest, tips);
      p.cubicTo(_cx + 19, top + 14, _cx + 14, _lerpD(hl, top, 0.45), _cx + 10, hl + 3);
      p.quadraticBezierTo(_cx, hl + 6, _cx - 10, hl + 3);
      p.close();
      _hairFill(canvas, r, p);
      _hairLines(canvas, r, p, _flowUp(g, lean: 0.15), [for (var i = 0; i < 5; i++) Offset(_cx - 8 + i * 4, hl - 1)],
          len: hl - top, color: r.hairLine, width: 1.1, alpha: 0.6, seed: 171);
      _sheen(canvas, r, p, Rect.fromLTRB(_cx - 13, top + 6, _cx + 16, hl + 30), math.pi * 1.05, math.pi * 0.3, width: 4.5);
      break;
    default:
      break;
  }
}

// ========================================================================= ÖN
void _paintTieFront(Canvas canvas, _Rig r, _HairGeo g) {
  final tie = r.tie;
  final side = g.side.toDouble();
  final hl = g.hl;
  switch (tie) {
    case HairTie.spaceBuns:
      for (final sgn in [-1.0, 1.0]) {
        _bun(canvas, r, g, Offset(_cx + sgn * g.fh * 0.66, g.topY + 9), 11.5, seed: 180 + (sgn > 0 ? 1 : 0));
      }
      break;

    case HairTie.ponySide:
      final at = Offset(_cx + side * (r.cheekHalf + 3), r.chinY - 10);
      _tail(canvas, r, g, [at, at + Offset(side * 7, 12), at + Offset(side * 8, 30), at + Offset(side * 2, 50)], 21, seed: 182);
      _hairTie(canvas, r, at.translate(side * 0.5, 2), 10, angle: side * 0.3);
      break;

    case HairTie.pigtails:
      for (final sgn in [-1.0, 1.0]) {
        final at = Offset(_cx + sgn * (r.cheekHalf + 5), 104);
        _tail(canvas, r, g, [at, at + Offset(sgn * 8, 18), at + Offset(sgn * 10, 44), at + Offset(sgn * 5, 70)], 19, seed: 183 + (sgn > 0 ? 1 : 0));
        _hairTie(canvas, r, at.translate(sgn * 0.5, 1), 10, angle: sgn * 0.5);
      }
      break;

    case HairTie.braid:
    case HairTie.fishtail:
      _braid(canvas, r, g, [
        Offset(_cx + side * (r.cheekHalf + 1), r.noseBaseY),
        Offset(_cx + side * (r.cheekHalf + 7), r.chinY + 4),
        Offset(_cx + side * (r.cheekHalf + 8), 178),
        Offset(_cx + side * (r.cheekHalf + 5), 196),
      ], 13, fish: tie == HairTie.fishtail, seed: 185);
      break;

    case HairTie.braidSide:
      _braid(canvas, r, g, [
        Offset(_cx + side * (r.cheekHalf - 2), _Rig.eyeY + 6),
        Offset(_cx + side * (r.cheekHalf + 5), r.chinY),
        Offset(_cx + side * (r.cheekHalf + 4), 176),
        Offset(_cx + side * (r.cheekHalf - 2), 198),
      ], 16, seed: 186);
      break;

    case HairTie.braidsTwo:
      for (final sgn in [-1.0, 1.0]) {
        _braid(canvas, r, g, [
          Offset(_cx + sgn * (r.cheekHalf + 1), _Rig.eyeY + 4),
          Offset(_cx + sgn * (r.cheekHalf + 6), r.chinY),
          Offset(_cx + sgn * (r.cheekHalf + 7), 176),
          Offset(_cx + sgn * (r.cheekHalf + 4), 196),
        ], 12, seed: 187 + (sgn > 0 ? 1 : 0));
      }
      break;

    case HairTie.crownBraid:
      final pts = <Offset>[];
      for (var i = 0; i <= 12; i++) {
        final a = math.pi * (1 - i / 12);
        pts.add(Offset(_cx + math.cos(a) * (g.fh + 2), hl - 4 - math.sin(a) * 18));
      }
      _braid(canvas, r, g, pts, 10, seed: 189);
      break;

    case HairTie.cornrows:
      final hlPts = g.hairlineFull(7);
      for (var i = 1; i < hlPts.length - 1; i++) {
        final start = hlPts[i].translate(0, -1);
        final end = Offset(_cx + (start.dx - _cx) * 0.55, g.topY + 6);
        _braid(canvas, r, g, [start, Offset.lerp(start, end, 0.5)!.translate((start.dx - _cx) * 0.08, 0), end], 6, seed: 190 + i);
      }
      break;

    case HairTie.boxBraids:
    case HairTie.dreads:
      _locsFront(canvas, r, g, braided: tie == HairTie.boxBraids);
      break;

    case HairTie.twists:
      final rng = r.rngFor(195);
      final rows = [
        [for (var i = 0; i < 5; i++) -0.56 + i * 0.28],
        [for (var i = 0; i < 6; i++) -0.70 + i * 0.28],
      ];
      for (var row = 0; row < rows.length; row++) {
        for (final fx in rows[row]) {
          final x = fx * g.fh;
          final baseY = row == 0 ? g.topY + 10 : g.hairlineY(x.abs()) - 4;
          final base = Offset(_cx + x, baseY);
          final tip = base + Offset(x * 0.14, -9 - rng.nextDouble() * 4);
          final p = _taperPath([base, (base + tip) / 2, tip], 6.0, 3.2, wMid: 5.6);
          _hairFill(canvas, r, p, shade: 0.5);
          for (var k = 1; k < 4; k++) {
            final q = Offset.lerp(base, tip, k / 4)!;
            canvas.drawLine(q.translate(-2.4, 0.9), q.translate(2.4, -0.9), r.stroke(r.hairLine, 0.7));
          }
        }
      }
      break;

    case HairTie.flatTop:
      final top = math.max(g.topY - 2, 7.0);
      final p = Path()
        ..moveTo(_cx - g.fh - 3, hl + 14)
        ..lineTo(_cx - g.fh - 4, top + 3)
        ..quadraticBezierTo(_cx - g.fh - 4, top, _cx - g.fh, top)
        ..lineTo(_cx + g.fh, top)
        ..quadraticBezierTo(_cx + g.fh + 4, top, _cx + g.fh + 4, top + 3)
        ..lineTo(_cx + g.fh + 3, hl + 14)
        ..quadraticBezierTo(_cx + g.fh * 0.5, hl - 1, _cx, hl)
        ..quadraticBezierTo(_cx - g.fh * 0.5, hl - 1, _cx - g.fh - 3, hl + 14)
        ..close();
      final shaped = _scallop(p, 0.9, 4.5, seed: 196);
      _hairFill(canvas, r, shaped);
      _curlTexture(canvas, r, shaped, seed: 197, radius: 2.2);
      break;

    case HairTie.halfUp:
    case HairTie.halfBun:
      // Yanlardan arkaya toplanan tutamlar: şakakta küçük kıvrım çizgisi.
      r.mirrored(canvas, (c, mir) {
        c.drawPath(
          Path()
            ..moveTo(_cx - g.fh * 0.95, g.hairlineY(g.fh) - 2)
            ..quadraticBezierTo(_cx - g.fh * 0.7, g.topY + 22, _cx - 6, g.topY + 12),
          r.stroke(_alpha(r.hairLine, 0.8), r.lineW),
        );
      });
      break;

    default:
      break;
  }
  if (tie == HairTie.ponyHigh || tie == HairTie.ponyLow || tie == HairTie.bunLow || tie == HairTie.bunHigh || tie == HairTie.bunBallet) {
    // Toplu saç: yanlardan geriye taranma çizgileri.
    canvas.save();
    canvas.clipPath(_capPath(g, r));
    r.mirrored(canvas, (c, mir) {
      for (var i = 0; i < 2; i++) {
        c.drawPath(
          Path()
            ..moveTo(_cx - g.fh * (0.92 - i * 0.2), g.hairlineY(g.fh * (0.92 - i * 0.2)) + 1)
            ..quadraticBezierTo(_cx - g.fh * (0.75 - i * 0.2), g.topY + 26, _cx - 4 - i * 6, g.topY + 8),
          r.stroke(_alpha(r.hairShadow, 0.9), 1.0),
        );
      }
    });
    canvas.restore();
  }
}

/// Kutu örgü / rasta: arkada omuzlara dökülen çok sayıda ince tel.
void _locsBack(Canvas canvas, _Rig r, _HairGeo g, {required bool braided}) {
  final W = g.W + 4;
  final end = g.lockEndY;
  final n = 12;
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    final x = _lerpD(-W, W, t);
    final start = Offset(_cx + x * 0.8, _HairGeo.yc - 6);
    final mid = Offset(_cx + x * 1.04, 120);
    final stop = Offset(_cx + x * 1.0, end - (i % 3) * 5);
    _rope(canvas, r, [start, mid, stop], braided ? 5.0 : 6.0, braided: braided, dark: true);
  }
}

void _locsFront(Canvas canvas, _Rig r, _HairGeo g, {required bool braided}) {
  final end = g.lockEndY;
  for (final sgn in [-1.0, 1.0]) {
    for (var k = 0; k < 3; k++) {
      final x0 = g.fh * (0.95 - k * 0.12);
      final start = Offset(_cx + sgn * x0, g.hairlineY(x0) - 2);
      final mid = Offset(_cx + sgn * (r.cheekHalf + 2 + k * 4), r.noseBaseY + 4);
      final stop = Offset(_cx + sgn * (r.cheekHalf + 6 + k * 5), end - k * 6);
      _rope(canvas, r, [start, mid, stop], braided ? 5.2 : 6.2, braided: braided);
    }
  }
}

/// Tek ince örgü ya da rasta teli.
void _rope(Canvas c, _Rig r, List<Offset> spine, double w, {required bool braided, bool dark = false}) {
  final pts = _sampleSpline(spine, 22);
  final path = _taperPath(pts, w, w * 0.75);
  c.drawPath(path, r.fill(dark ? _mix(r.hairColor, r.hairShadow, 0.45) : r.hairColor));
  c.save();
  c.clipPath(path);
  for (var i = 1; i < pts.length - 1; i += 2) {
    final d = _norm(pts[i + 1] - pts[i - 1]);
    final nrm = Offset(-d.dy, d.dx);
    if (braided) {
      c.drawLine(pts[i] - nrm * w, pts[i] + nrm * w + d * 2.2, r.stroke(_alpha(r.hairLine, 0.8), 0.7));
    } else {
      c.drawLine(pts[i] - nrm * w, pts[i] + nrm * w, r.stroke(_alpha(r.hairShadow, 0.8), 0.8));
    }
  }
  c.restore();
  c.drawPath(path, r.stroke(r.hairLine, r.lineW * 0.8));
}

// ================================================================ KAPALI SAÇ
/// Yüz açıklığı (başörtüsü/kapüşon içinden görünen yüz).
Path _faceOpening(_Rig r, {double top = 52, double side = 1.0, double chinExtra = 3}) {
  final fh = r.foreheadHalf;
  final cw = r.cheekHalf * side;
  return _symmetric([
    Offset(0, top),
    Offset(fh * 0.62, top + 1.6),
    Offset(fh * 0.94, top + 11),
    Offset(cw + 0.6, _Rig.eyeY - 4),
    Offset(cw - 0.5, _Rig.eyeY + 14),
    Offset(r.jawHalf + 2.5, r.gonionY + 4),
    Offset(r.chinHalf + 6, r.chinY + 0.5),
    Offset(0, r.chinY + chinExtra),
  ]);
}

/// Kumaş yüzeyi: dolgu → cel gölge → kıvrımlar → kontur.
void _fabric(Canvas c, _Rig r, Path p, Color col, {List<List<Offset>> folds = const [], Offset light = const Offset(-7, -5)}) {
  c.drawPath(p, r.fill(col));
  r.celShade(c, p, _alpha(_tone(col, -0.28), 0.95), base: col, offset: light, blur: r.detailed ? 1.2 : 0);
  if (folds.isNotEmpty) {
    c.save();
    c.clipPath(p);
    for (final f in folds) {
      c.drawPath(_taperPath(_sampleSpline(f, 12), 0.4, 0.3, wMid: 1.6), r.fill(_alpha(_tone(col, -0.38), 0.75)));
    }
    c.restore();
  }
  c.drawPath(p, r.stroke(_tone(col, -0.52), r.lineW));
}

Color _coverColor(_Rig r) => r.cfg.clothingColor;

void _paintCoverBack(Canvas canvas, _Rig r) {
  final cover = r.hair.cover;
  final col = _coverColor(r);
  final cw = r.cheekHalf;
  switch (cover) {
    case HairCover.hijab:
    case HairCover.hijabWrap:
    case HairCover.shawl:
      // Omuzlara dökülen kumaşın arka katmanı (boynun arkası).
      final back = _symmetric([
        const Offset(0, 40),
        Offset(cw + 14, 92),
        Offset(cw + 18, 140),
        Offset(cw + 30, 186),
        const Offset(90, 214),
        const Offset(0, 214),
      ]);
      _fabric(canvas, r, back, _tone(col, -0.22));
      break;
    default:
      break;
  }
}

void _paintCoverFront(Canvas canvas, _Rig r) {
  final cover = r.hair.cover;
  final col = _coverColor(r);
  final fh = r.foreheadHalf;
  final cw = r.cheekHalf;
  const top = _Rig.skullTop - 6;

  switch (cover) {
    case HairCover.none:
      return;

    case HairCover.hijab:
    case HairCover.hijabWrap:
      final outer = _symmetric([
        const Offset(0, top),
        Offset(fh * 0.62, top + 3),
        Offset(fh + 9, top + 22),
        Offset(cw + 10, _Rig.eyeY - 6),
        Offset(cw + 9, r.chinY - 8),
        Offset(r.jawHalf + 22, r.chinY + 18),
        const Offset(70, 200),
        const Offset(76, 214),
        const Offset(0, 214),
      ]);
      final opening = _faceOpening(r);
      final cloth = Path.combine(PathOperation.difference, outer, opening);
      // Kumaşın yüze düşürdüğü gölge.
      canvas.save();
      canvas.clipPath(opening);
      canvas.drawPath(opening, r.stroke(_alpha(r.skinShadow, 0.95), 5.5, blur: r.detailed ? 1.2 : 0));
      canvas.restore();
      _fabric(canvas, r, cloth, col, folds: [
        [Offset(_cx - cw - 4, r.chinY + 6), Offset(_cx - cw + 2, r.chinY + 22), Offset(_cx - 30, 196)],
        [Offset(_cx + cw + 2, r.chinY), Offset(_cx + cw - 2, r.chinY + 22), Offset(_cx + 34, 198)],
        [Offset(_cx - 6, r.chinY + 14), Offset(_cx - 2, r.chinY + 30), Offset(_cx - 8, 204)],
        [Offset(_cx - fh - 4, 48), Offset(_cx - cw - 6, 80), Offset(_cx - cw - 7, 110)],
      ]);
      // Alın bandı (bone) — açıklığın üstünde ince şerit.
      final band = Path.combine(PathOperation.difference, _faceOpening(r, top: 48.5, side: 1.06, chinExtra: 5), opening);
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, 200, _Rig.eyeY - 6));
      canvas.drawPath(band, r.fill(_tone(col, -0.12)));
      canvas.restore();
      canvas.drawPath(opening, r.stroke(_tone(col, -0.52), r.lineW));
      if (cover == HairCover.hijabWrap) {
        // Çenenin altından karşı omuza sarılan kat.
        final wrap = Path()
          ..moveTo(_cx - cw - 2, r.chinY - 6)
          ..quadraticBezierTo(_cx - 8, r.chinY + 16, _cx + cw + 8, r.chinY - 4)
          ..lineTo(_cx + cw + 12, r.chinY + 10)
          ..quadraticBezierTo(_cx - 2, r.chinY + 34, _cx - cw - 10, r.chinY + 14)
          ..close();
        _fabric(canvas, r, wrap, _tone(col, 0.06), folds: [
          [Offset(_cx - cw + 4, r.chinY + 6), Offset(_cx, r.chinY + 20), Offset(_cx + cw, r.chinY + 6)],
        ]);
        canvas.drawCircle(Offset(_cx + cw + 8, r.chinY + 2), 1.6, r.fill(const Color(0xFFD9B44A)));
      }
      return;

    case HairCover.shawl:
      // Önden saç çizgisi görünür, şal başın üstünden omuzlara.
      final g = _HairGeo(r);
      final hl = g.hairlineFull(14);
      final hair = Path()..moveTo(hl.first.dx, hl.first.dy);
      for (final p in hl.skip(1)) {
        hair.lineTo(p.dx, p.dy);
      }
      hair.lineTo(_cx + fh * 0.6, g.hl - 8);
      hair.quadraticBezierTo(_cx, g.hl - 12, _cx - fh * 0.6, g.hl - 8);
      hair.close();
      _hairFill(canvas, r, hair, shade: 0.4);
      final outer = _symmetric([
        const Offset(0, top + 2),
        Offset(fh * 0.66, top + 5),
        Offset(fh + 10, top + 26),
        Offset(cw + 11, _Rig.eyeY),
        Offset(cw + 14, r.chinY),
        Offset(cw + 26, 186),
        const Offset(80, 214),
        const Offset(0, 214),
      ]);
      final opening = _symmetric([
        Offset(0, g.hl - 9),
        Offset(fh * 0.7, g.hl - 6),
        Offset(fh + 2, g.hl + 12),
        Offset(cw + 2, _Rig.eyeY + 4),
        Offset(cw + 4, r.chinY),
        Offset(r.neckHalf + 16, 172),
        const Offset(0, 182),
      ]);
      _fabric(canvas, r, Path.combine(PathOperation.difference, outer, opening), col, folds: [
        [Offset(_cx - cw - 6, 120), Offset(_cx - cw - 10, 160), Offset(_cx - cw - 16, 200)],
        [Offset(_cx + cw + 6, 120), Offset(_cx + cw + 10, 160), Offset(_cx + cw + 16, 200)],
      ]);
      return;

    case HairCover.babushka:
      final outer = _symmetric([
        const Offset(0, top + 1),
        Offset(fh * 0.62, top + 4),
        Offset(fh + 8, top + 24),
        Offset(cw + 7, _Rig.eyeY + 2),
        Offset(r.jawHalf + 8, r.gonionY + 8),
        Offset(r.chinHalf + 6, r.chinY + 6),
        Offset(0, r.chinY + 7),
      ]);
      final opening = _faceOpening(r, top: 54, chinExtra: 2);
      _fabric(canvas, r, Path.combine(PathOperation.difference, outer, opening), col, folds: [
        [Offset(_cx - fh * 0.5, top + 8), Offset(_cx - fh * 0.7, 46), Offset(_cx - fh * 0.9, 58)],
        [Offset(_cx + fh * 0.4, top + 8), Offset(_cx + fh * 0.65, 44), Offset(_cx + fh * 0.88, 58)],
      ]);
      // Çene altında düğüm ve iki uç.
      final knot = Offset(_cx + 6, r.chinY + 6);
      for (final a in [0.5, 1.1]) {
        final tip = knot + Offset(math.cos(a), math.sin(a)) * 16;
        _fabric(canvas, r, _taperPath([knot, (knot + tip) / 2 + const Offset(2, 0), tip], 5, 3, wMid: 7), _tone(col, -0.06));
      }
      canvas.drawCircle(knot, 4, r.fill(_tone(col, -0.1)));
      canvas.drawCircle(knot, 4, r.stroke(_tone(col, -0.52), r.lineW));
      return;

    case HairCover.turban:
      _paintTurban(canvas, r, col);
      return;

    case HairCover.bandana:
      // Kısa saç yanlardan görünür, bandana başı örter.
      final g = _HairGeo(r);
      final cap = _capPath(g, r);
      _hairFill(canvas, r, cap, shade: 0.6);
      _paintBandana(canvas, r, col);
      return;
  }
}

/// Türban: başın üstünde sarılı katlar, önde çapraz büküm.
void _paintTurban(Canvas canvas, _Rig r, Color cloth) {
  final fh = r.foreheadHalf;
  const top = _Rig.skullTop - 10;
  final base = _Rig.eyeY - 30;
  final dome = Path()
    ..moveTo(_cx - fh - 7, base + 6)
    ..cubicTo(_cx - fh - 12, base - 26, _cx - fh * 0.6, top, _cx, top)
    ..cubicTo(_cx + fh * 0.6, top, _cx + fh + 12, base - 26, _cx + fh + 7, base + 6)
    ..quadraticBezierTo(_cx, base + 14, _cx - fh - 7, base + 6)
    ..close();
  _castOnSkin(canvas, r, [dome]);
  _fabric(canvas, r, dome, cloth, folds: [
    [Offset(_cx - fh - 6, base - 2), Offset(_cx - 6, top + 14), Offset(_cx + fh * 0.6, top + 6)],
    [Offset(_cx - fh - 4, base + 4), Offset(_cx, top + 26), Offset(_cx + fh + 4, base - 14)],
    [Offset(_cx + fh + 6, base - 2), Offset(_cx + 6, top + 16), Offset(_cx - fh * 0.6, top + 8)],
  ]);
  // Önde çapraz büküm.
  final twist = Path()
    ..moveTo(_cx - 9, base + 9)
    ..quadraticBezierTo(_cx - 2, base - 6, _cx + 6, top + 12)
    ..lineTo(_cx + 12, top + 16)
    ..quadraticBezierTo(_cx + 4, base - 4, _cx + 2, base + 10)
    ..close();
  _fabric(canvas, r, twist, _tone(cloth, 0.08));
}

/// Alından geçen bandana: üst kısım başı örter, yanda düğüm.
void _paintBandana(Canvas canvas, _Rig r, Color cloth) {
  final fh = r.foreheadHalf;
  final g = _HairGeo(r);
  final low = g.hl + 4;
  final p = Path()
    ..moveTo(_cx - fh - 6, low + 10)
    ..cubicTo(_cx - fh - 10, 20, _cx - fh * 0.5, _Rig.skullTop - 6, _cx, _Rig.skullTop - 6)
    ..cubicTo(_cx + fh * 0.5, _Rig.skullTop - 6, _cx + fh + 10, 20, _cx + fh + 6, low + 10)
    ..quadraticBezierTo(_cx, low - 4, _cx - fh - 6, low + 10)
    ..close();
  _castOnSkin(canvas, r, [p]);
  _fabric(canvas, r, p, cloth, folds: [
    [Offset(_cx - fh * 0.6, 30), Offset(_cx - fh * 0.5, 44), Offset(_cx - fh * 0.7, low)],
    [Offset(_cx + fh * 0.4, 28), Offset(_cx + fh * 0.55, 42), Offset(_cx + fh * 0.75, low)],
  ]);
  if (r.detailed) {
    // Bandana deseni: küçük beyaz noktalar.
    canvas.save();
    canvas.clipPath(p);
    final rng = r.rngFor(780);
    for (var i = 0; i < 26; i++) {
      final q = Offset(_cx - fh - 6 + rng.nextDouble() * (fh * 2 + 12), 16 + rng.nextDouble() * (low - 10));
      canvas.drawCircle(q, 0.9, r.fill(_alpha(Colors.white, 0.75)));
    }
    canvas.restore();
  }
  // Yanda düğüm ve uçlar.
  final knot = Offset(_cx + fh + 6, low + 4);
  for (final a in [0.3, 0.95]) {
    final tip = knot + Offset(math.cos(a), math.sin(a)) * 13;
    _fabric(canvas, r, _taperPath([knot, (knot + tip) / 2, tip], 4, 2.4, wMid: 5.5), _tone(cloth, -0.06));
  }
  canvas.drawCircle(knot, 3.4, r.fill(_tone(cloth, -0.1)));
  canvas.drawCircle(knot, 3.4, r.stroke(_tone(cloth, -0.52), r.lineW));
}
