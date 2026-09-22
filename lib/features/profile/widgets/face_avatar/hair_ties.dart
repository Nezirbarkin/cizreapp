part of '../face_avatar_painter.dart';

// ============================================================================
// TOPUZ / KUYRUK / ÖRGÜ / RASTA / KAPALI SAÇ
// ============================================================================

/// Noktalar boyunca genişliği kökten uca değişen kapalı şerit.
Path _ribbon(List<Offset> pts, double w0, double wMid, double w1) {
  if (pts.length < 2) return Path();
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    final prev = pts[math.max(0, i - 1)];
    final next = pts[math.min(pts.length - 1, i + 1)];
    final d = _norm(next - prev);
    final nrm = Offset(-d.dy, d.dx);
    final t = i / (pts.length - 1);
    final w = t < 0.5 ? _lerpD(w0, wMid, t * 2) : _lerpD(wMid, w1, (t - 0.5) * 2);
    left.add(pts[i] + nrm * (w / 2));
    right.add(pts[i] - nrm * (w / 2));
  }
  final path = _spline([...left, ...right.reversed], closed: true, tension: 0.9);
  return path;
}

/// Nokta dizisi boyunca teğet yönünde akış.
_Flow _flowAlong(List<Offset> pts) {
  return (p) {
    var best = 0;
    var bd = double.infinity;
    for (var i = 0; i < pts.length; i++) {
      final d = (pts[i] - p).distanceSquared;
      if (d < bd) {
        bd = d;
        best = i;
      }
    }
    final a = pts[math.max(0, best - 1)];
    final b = pts[math.min(pts.length - 1, best + 1)];
    return _norm(b - a);
  };
}

/// Eğri (kuadratik/kübik) boyunca örnek noktalar.
List<Offset> _curve(Offset a, Offset b, Offset c, [Offset? d, int n = 14]) {
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    final u = 1 - t;
    if (d == null) {
      out.add(a * (u * u) + b * (2 * u * t) + c * (t * t));
    } else {
      out.add(a * (u * u * u) + b * (3 * u * u * t) + c * (3 * u * t * t) + d * (t * t * t));
    }
  }
  return out;
}

/// Bukle/örgü bağlama lastiği.
void _hairTie(Canvas c, _Rig r, Offset at, double w, {Color? color}) {
  final col = color ?? _mix(r.cfg.clothingColor, const Color(0xFFD9578A), 0.5);
  c.drawOval(Rect.fromCenter(center: at, width: w, height: w * 0.55), r.fill(col));
  if (r.detailed) {
    c.drawOval(
      Rect.fromCenter(center: at.translate(-w * 0.12, -w * 0.08), width: w * 0.5, height: w * 0.2),
      r.fill(_alpha(Colors.white, 0.35)),
    );
  }
}

/// Örgü: birbirine geçen oval halkalar. [pts] merkez hattı.
void _braid(Canvas c, _Rig r, _HairGeo g, List<Offset> pts, double width, {int seed = 1, bool fish = false, Color? baseColor}) {
  final n = pts.length;
  final col = baseColor ?? r.hairColor;
  // Zemin şerit
  final ribbon = _ribbon(pts, width * 0.9, width, width * 0.55);
  c.drawPath(ribbon, r.fill(_mix(col, r.hairDark, 0.45)));
  for (var i = 0; i < n - 1; i++) {
    final a = pts[i], b = pts[i + 1];
    final mid = _lerpO(a, b, 0.5);
    final d = _norm(b - a);
    final ang = math.atan2(d.dy, d.dx);
    final t = i / (n - 1);
    final w = _lerpD(width, width * 0.6, t);
    final segLen = (b - a).distance * 1.7;
    final side = i.isEven ? -1.0 : 1.0;
    final nrm = Offset(-d.dy, d.dx);
    c.save();
    c.translate(mid.dx + nrm.dx * side * w * 0.16, mid.dy + nrm.dy * side * w * 0.16);
    c.rotate(ang + side * (fish ? 0.9 : 0.6));
    final rect = Rect.fromCenter(center: Offset.zero, width: segLen * (fish ? 1.0 : 1.25), height: w * (fish ? 0.55 : 0.75));
    c.drawOval(rect, r.fill(i.isEven ? _mix(col, r.hairLight, 0.10) : _mix(col, r.hairDark, 0.18)));
    if (r.detailed) {
      c.drawOval(rect, r.stroke(_alpha(r.hairDark, 0.55), 0.6));
      // Segmentin içinde tel çizgileri.
      for (var k = -1; k <= 1; k++) {
        c.drawLine(
          Offset(-segLen * 0.42, k * w * 0.16),
          Offset(segLen * 0.42, k * w * 0.16 + side * 0.4),
          r.stroke(_alpha(k == 0 ? r.hairShine : r.hairDark, k == 0 ? 0.30 : 0.25), 0.5),
        );
      }
    }
    c.restore();
  }
  // Uçta tutam.
  final endP = pts.last;
  final prev = pts[pts.length - 2];
  final d = _norm(endP - prev);
  final tuft = Path()
    ..moveTo(endP.dx - width * 0.28, endP.dy)
    ..quadraticBezierTo(endP.dx + d.dx * 5, endP.dy + d.dy * 6 + 3, endP.dx + width * 0.28, endP.dy)
    ..close();
  c.drawPath(tuft, r.fill(_mix(col, r.hairDark, 0.2)));
  _hairTie(c, r, endP.translate(0, -0.5), width * 0.9);
}

/// Yuvarlak topuz: tangent akışlı tel ve bant.
void _bun(Canvas c, _Rig r, _HairGeo g, Offset center, double rad, {bool messy = false, bool ballet = false, int seed = 1}) {
  final path = messy
      ? _spline([
          for (var i = 0; i < 12; i++)
            center +
                Offset(math.cos(i / 12 * math.pi * 2), math.sin(i / 12 * math.pi * 2)) *
                    (rad * (0.88 + 0.18 * math.sin(i * 2.3 + seed))),
        ], closed: true)
      : (Path()..addOval(Rect.fromCircle(center: center, radius: rad)));
  Offset flow(Offset p) {
    final v = p - center;
    return _norm(Offset(-v.dy, v.dx));
  }

  _paintMass(c, r, g, path, flow: flow, strands: 150, len: rad * 1.1, width: 0.9, seed: 400 + seed, edge: 0.6, sheen: 0.30, curl: 0);
  if (r.detailed) {
    // Sarmal çizgiler.
    for (var i = 0; i < 3; i++) {
      c.drawArc(
        Rect.fromCircle(center: center, radius: rad * (0.35 + i * 0.22)),
        0.6 + i * 1.1,
        math.pi * 1.2,
        false,
        r.stroke(_alpha(i.isEven ? r.hairDark : r.hairShine, 0.28), 0.8),
      );
    }
  }
}

// ===================================================================== ARKA
void _paintTieBack(Canvas canvas, _Rig r, _HairGeo g) {
  final tie = r.tie;
  final W = g.W;
  switch (tie) {
    case HairTie.ponyHigh:
      // Tepeden çıkıp sağ arkaya savrulan kuyruk.
      final pts = _curve(Offset(_cx + 6, g.topY + 6), Offset(_cx + 46, g.topY - 6), Offset(_cx + 66, 84), Offset(_cx + 54, 150), 16);
      final path = _ribbon(pts, 12, 22, 7);
      _paintMass(canvas, r, g, path, flow: _flowAlong(pts), strands: 220, len: 16, seed: 410, base: r.hairMid, edge: 0.6, sheen: 0.22);
      break;

    case HairTie.ponyLow:
      final pts = _curve(Offset(_cx + 26, 96), Offset(_cx + 50, 118), Offset(_cx + 48, 158), Offset(_cx + 40, 184), 16);
      final path = _ribbon(pts, 12, 20, 8);
      _paintMass(canvas, r, g, path, flow: _flowAlong(pts), strands: 200, len: 14, seed: 411, base: r.hairMid, edge: 0.6, sheen: 0.2);
      break;

    case HairTie.pigtails:
      r.mirrored(canvas, (c, mir) {
        final pts = _curve(Offset(_cx - 34, 58), Offset(_cx - 58, 70), Offset(_cx - 66, 112), Offset(_cx - 56, 152), 16);
        final path = _ribbon(pts, 11, 19, 6);
        _paintMass(c, r, g, path, flow: _flowAlong(pts), strands: 150, len: 14, seed: 412 + (mir ? 1 : 0), base: r.hairMid, edge: 0.6, sheen: 0.22);
      });
      break;

    case HairTie.boxBraids:
      _boxBraids(canvas, r, g, back: true);
      break;

    case HairTie.dreads:
      _dreads(canvas, r, g, back: true);
      break;

    case HairTie.braid:
    case HairTie.fishtail:
      // Sırt örgüsü: kafanın arkasından omuz üstüne görünür.
      break;

    default:
      break;
  }
  if (tie == HairTie.boxBraids || tie == HairTie.dreads) return;
  // W kullanılmıyor uyarısını sustur.
  W.toString();
}

// ===================================================== KAPAĞIN ALTINDAKİLER
/// Kepin altında kalan (üstünden kapatılan) parçalar: topuzlar, mohawk, düz tepe…
void _paintTieUnder(Canvas canvas, _Rig r, _HairGeo g) {
  final tie = r.tie;
  final topY = g.topY;
  switch (tie) {
    case HairTie.bunHigh:
      _bun(canvas, r, g, Offset(_cx, topY - 4), 12.5, seed: 1);
      break;
    case HairTie.bunLow:
      _bun(canvas, r, g, Offset(_cx, topY + 1), 14, seed: 2);
      break;
    case HairTie.bunTop:
      _bun(canvas, r, g, Offset(_cx, topY - 3), 8.5, seed: 3);
      break;
    case HairTie.bunBallet:
      _bun(canvas, r, g, Offset(_cx, topY - 5), 11.5, ballet: true, seed: 4);
      break;
    case HairTie.bunMessy:
      _bun(canvas, r, g, Offset(_cx + 2, topY - 5), 15, messy: true, seed: 5);
      break;
    case HairTie.halfBun:
      _bun(canvas, r, g, Offset(_cx, topY - 2), 9.5, messy: true, seed: 6);
      break;
    case HairTie.spaceBuns:
      r.mirrored(canvas, (c, mir) {
        _bun(c, r, g, Offset(_cx - 31, topY + 4), 11.5, seed: 7 + (mir ? 1 : 0));
      });
      break;
    case HairTie.afroPuffs:
      r.mirrored(canvas, (c, mir) {
        final center = Offset(_cx - 33, topY + 3);
        final puff = Path()..addOval(Rect.fromCircle(center: center, radius: 17));
        _paintMass(c, r, g, puff, flow: (p) => _norm(p - center), strands: 40, len: 6, seed: 420 + (mir ? 1 : 0), texture: HairTexture.coily, edge: 0.55, sheen: 0.32);
      });
      break;
    case HairTie.mohawk:
      final path = Path()
        ..moveTo(_cx - 9, 70)
        ..cubicTo(_cx - 11, 40, _cx - 9, 14, _cx - 5, 8)
        ..cubicTo(_cx - 2, 4, _cx + 2, 4, _cx + 5, 8)
        ..cubicTo(_cx + 9, 14, _cx + 11, 40, _cx + 9, 70)
        ..close();
      _paintMass(canvas, r, g, path, flow: _flowUp(g), strands: 200, len: 12, seed: 430, edge: 0.5, sheen: 0.35);
      break;
    case HairTie.flatTop:
      final box = RRect.fromRectAndRadius(
        Rect.fromLTRB(_cx - g.fh - 1, 19, _cx + g.fh + 1, 68),
        const Radius.circular(13),
      );
      _paintMass(canvas, r, g, Path()..addRRect(box), flow: _flowUp(g), strands: 60, len: 6, seed: 431, texture: HairTexture.coily, edge: 0.5, sheen: 0.3);
      break;
    case HairTie.twists:
      final dome = _spline([
        Offset(_cx - g.fh - 3, 62),
        Offset(_cx - g.fh - 1, 40),
        Offset(_cx - g.fh * 0.5, 22),
        Offset(_cx, 17),
        Offset(_cx + g.fh * 0.5, 22),
        Offset(_cx + g.fh + 1, 40),
        Offset(_cx + g.fh + 3, 62),
        Offset(_cx, 70),
      ], closed: true);
      _paintMass(canvas, r, g, dome, flow: _flowUp(g), strands: 40, len: 6, seed: 432, texture: HairTexture.coily, edge: 0.5, sheen: 0.3);
      if (r.detailed) {
        canvas.save();
        canvas.clipPath(dome);
        for (var i = -5; i <= 5; i++) {
          final x = _cx + i * (g.fh * 0.17);
          canvas.drawPath(
            Path()
              ..moveTo(x, 66)
              ..quadraticBezierTo(x + (x - _cx) * 0.2, 40, _cx + (x - _cx) * 1.25, 20),
            r.stroke(_alpha(r.hairDark, 0.45), 1.1),
          );
        }
        canvas.restore();
      }
      break;
    default:
      break;
  }
}

// ===================================================================== ÖN
void _paintTieFront(Canvas canvas, _Rig r, _HairGeo g) {
  final tie = r.tie;
  final topY = g.topY;
  switch (tie) {
    case HairTie.bunHigh:
    case HairTie.bunTop:
    case HairTie.bunBallet:
    case HairTie.bunMessy:
    case HairTie.bunLow:
      // Bant: bunun tabanında.
      final baseY = topY + (tie == HairTie.bunTop ? 4 : 5);
      _hairTie(canvas, r, Offset(_cx, baseY), 12);
      break;

    case HairTie.ponyHigh:
      _hairTie(canvas, r, Offset(_cx + 6, topY + 6), 11);
      break;

    case HairTie.ponySide:
      // Sağ omuz üstüne düşen yan kuyruk (önde).
      final pts = _curve(Offset(_cx + 40, 86), Offset(_cx + 58, 110), Offset(_cx + 56, 150), Offset(_cx + 46, 184), 18);
      final path = _ribbon(pts, 12, 22, 8);
      _paintMass(canvas, r, g, path, flow: _flowAlong(pts), strands: 240, len: 14, seed: 440, edge: 0.55, sheen: 0.28);
      _hairTie(canvas, r, Offset(_cx + 41, 87), 11);
      break;

    case HairTie.pigtails:
      r.mirrored(canvas, (c, mir) {
        _hairTie(c, r, Offset(_cx - 35, 59), 10);
      });
      break;

    case HairTie.halfUp:
      // Tepede küçük bağ + arkadan sarkan kuyruk (üstte).
      final base = Offset(_cx, topY + 6);
      final pts = _curve(base, Offset(_cx + 8, topY - 8), Offset(_cx + 22, topY - 1), null, 8);
      final path = _ribbon(pts, 9, 12, 6);
      _paintMass(canvas, r, g, path, flow: _flowAlong(pts), strands: 60, len: 8, seed: 441, edge: 0.5, sheen: 0.3);
      _hairTie(canvas, r, base, 9);
      break;

    case HairTie.halfBun:
      _hairTie(canvas, r, Offset(_cx, topY + 4), 10);
      break;

    case HairTie.braid:
      // Tek örgü: sağ omuzdan önde.
      final pts = _curve(Offset(_cx + 38, 84), Offset(_cx + 52, 120), Offset(_cx + 50, 160), Offset(_cx + 44, 194), 12);
      _braid(canvas, r, g, pts, 11);
      break;

    case HairTie.braidSide:
      final pts = _curve(Offset(_cx + 36, 92), Offset(_cx + 60, 126), Offset(_cx + 54, 168), Offset(_cx + 46, 198), 12);
      _braid(canvas, r, g, pts, 12);
      break;

    case HairTie.braidsTwo:
      r.mirrored(canvas, (c, mir) {
        final pts = _curve(Offset(_cx - 38, 84), Offset(_cx - 54, 122), Offset(_cx - 52, 164), Offset(_cx - 46, 196), 12);
        _braid(c, r, g, pts, 10.5);
      });
      break;

    case HairTie.fishtail:
      final pts = _curve(Offset(_cx + 36, 88), Offset(_cx + 54, 124), Offset(_cx + 50, 164), Offset(_cx + 44, 198), 16);
      _braid(canvas, r, g, pts, 10.5, fish: true);
      break;

    case HairTie.crownBraid:
      // Saç çizgisi boyunca tepeye sarılan örgü bandı.
      final pts = <Offset>[];
      for (var i = 0; i <= 16; i++) {
        final t = i / 16;
        final a = math.pi * (1 - t);
        pts.add(Offset(_cx + math.cos(a) * (g.fh + 1), 64 - math.sin(a) * (34 - 4 * math.sin(a))));
      }
      _braid(canvas, r, g, pts, 7.2, fish: false);
      break;

    case HairTie.cornrows:
      _cornrows(canvas, r, g);
      break;

    case HairTie.boxBraids:
      _boxBraids(canvas, r, g, back: false);
      break;

    case HairTie.dreads:
      _dreads(canvas, r, g, back: false);
      break;

    default:
      break;
  }
}

void _cornrows(Canvas canvas, _Rig r, _HairGeo g) {
  // Alından tepeye giden paralel örgü sırtları.
  final fh = g.fh;
  canvas.save();
  canvas.clipPath(_capPath(g, r));
  const n = 8;
  for (var i = 0; i < n; i++) {
    final t = (i + 0.5) / n;
    final x = -fh * 0.9 + t * fh * 1.8;
    final start = Offset(_cx + x, g.hairlineY(x.abs()) + 1);
    final end = Offset(_cx + x * 0.62, g.topY + 2);
    final pts = _curve(start, Offset(_cx + x * 0.98, (start.dy + end.dy) / 2), end, null, 12);
    final ribbon = _ribbon(pts, 3.4, 3.4, 2.6);
    canvas.drawPath(ribbon, r.fill(_mix(r.hairColor, r.hairDark, 0.15)));
    if (r.detailed) {
      canvas.drawPath(ribbon, r.stroke(_alpha(r.hairDark, 0.6), 0.5));
      for (var k = 1; k < pts.length - 1; k++) {
        final a = pts[k];
        canvas.drawLine(a.translate(-1.4, -0.6), a.translate(1.4, 0.6), r.stroke(_alpha(r.hairShine, 0.35), 0.5));
      }
    }
  }
  canvas.restore();
}

void _boxBraids(Canvas canvas, _Rig r, _HairGeo g, {required bool back}) {
  final n = back ? 5 : 6;
  final rng = r.rngFor(450 + (back ? 1 : 0));
  r.mirrored(canvas, (c, mir) {
    for (var i = 0; i < n; i++) {
      final t = (i + 0.5) / n;
      final spread = _lerpD(g.fh * 0.35, g.W + 6, t);
      final startY = _lerpD(58, 92, t);
      final startX = _cx - _lerpD(g.fh * 0.4, r.headX(88) + 2, t);
      final endX = _cx - spread - (back ? 8 : 4) - rng.nextDouble() * 3;
      final endY = (back ? 160 : 150) + rng.nextDouble() * 34 - t * 6;
      final pts = _curve(
        Offset(startX, startY),
        Offset((startX + endX) / 2 - 3, (startY + endY) / 2 - 12),
        Offset(endX + 2, (startY + endY) / 2 + 20),
        Offset(endX, endY),
        14,
      );
      if (back) {
        final path = _ribbon(pts, 5, 5.5, 4);
        c.drawPath(path, r.fill(_mix(r.hairColor, r.hairDark, 0.4)));
      } else {
        _braid(c, r, g, pts, 5.2, seed: i);
      }
    }
  });
}

void _dreads(Canvas canvas, _Rig r, _HairGeo g, {required bool back}) {
  final n = back ? 6 : 7;
  final rng = r.rngFor(460 + (back ? 1 : 0));
  r.mirrored(canvas, (c, mir) {
    for (var i = 0; i < n; i++) {
      final t = (i + 0.5) / n;
      final startY = _lerpD(48, 96, t);
      final startX = _cx - _lerpD(g.fh * 0.3, r.headX(90) + 3, t);
      final endX = _cx - (g.W + 4 + rng.nextDouble() * 10) * (0.7 + 0.5 * t);
      final endY = (back ? 150 : 138) + rng.nextDouble() * 40;
      final pts = _curve(
        Offset(startX, startY),
        Offset(startX - 5, (startY + endY) / 2 - 12),
        Offset(endX - 3, (startY + endY) / 2 + 14),
        Offset(endX, endY),
        16,
      );
      final path = _ribbon(pts, 6.6, 7.2, 5.4);
      c.drawPath(path, r.fill(_mix(r.hairColor, back ? r.hairDark : r.hairMid, back ? 0.5 : 0.05)));
      if (r.detailed) {
        c.drawPath(path, r.stroke(_alpha(r.hairDark, 0.55), 0.6));
        for (var k = 1; k < pts.length - 1; k += 1) {
          final a = pts[k];
          final d = _norm(pts[k + 1] - pts[k - 1]);
          final nrm = Offset(-d.dy, d.dx);
          c.drawLine(a + nrm * 3 - d, a - nrm * 3 + d, r.stroke(_alpha(r.hairDark, 0.45), 0.6));
          c.drawLine(a + nrm * 2.4 + d, a - nrm * 2.4 - d * 0.2, r.stroke(_alpha(r.hairShine, 0.22), 0.5));
        }
      }
    }
  });
}

// =================================================================== KAPALI
Color _coverColor(_Rig r) => r.cfg.clothingColor;

/// Yüz açıklığı: başörtünün yüzü çerçeveleyen oval boşluğu.
Path _faceOpening(_Rig r, {double top = 56, double side = 1.0, double chinExtra = 2}) {
  final cw = r.cheekHalf * side;
  final pts = <Offset>[
    Offset(_cx, top),
    Offset(_cx + cw * 0.62, top + 2.6),
    Offset(_cx + cw * 0.94, 76),
    Offset(_cx + cw * 1.0, 94),
    Offset(_cx + r.jawHalf * 0.96, 122),
    Offset(_cx + r.chinHalf * 1.35, r.chinY - 3),
    Offset(_cx, r.chinY + chinExtra),
    Offset(_cx - r.chinHalf * 1.35, r.chinY - 3),
    Offset(_cx - r.jawHalf * 0.96, 122),
    Offset(_cx - cw * 1.0, 94),
    Offset(_cx - cw * 0.94, 76),
    Offset(_cx - cw * 0.62, top + 2.6),
  ];
  return _spline(pts, closed: true);
}

void _paintCoverBack(Canvas canvas, _Rig r) {
  // Başörtüsünün arkası tamamen ön katmanda çizilir.
}

void _paintCoverFront(Canvas canvas, _Rig r) {
  final cover = r.hair.cover;
  final cloth = _coverColor(r);
  final cw = r.cheekHalf;
  final fh = r.foreheadHalf;
  final chin = r.chinY;

  Path outer;
  Path opening;
  const foldStart = 30.0;

  switch (cover) {
    case HairCover.hijab:
      outer = _spline([
        Offset(_cx, 19),
        Offset(_cx + fh * 0.62, 23),
        Offset(_cx + fh + 12, 44),
        Offset(_cx + cw + 15, 78),
        Offset(_cx + cw + 16, 112),
        Offset(_cx + cw + 15, 140),
        Offset(_cx + cw + 24, 170),
        Offset(_cx + cw + 32, 204),
        Offset(_cx - cw - 32, 204),
        Offset(_cx - cw - 24, 170),
        Offset(_cx - cw - 15, 140),
        Offset(_cx - cw - 16, 112),
        Offset(_cx - cw - 15, 78),
        Offset(_cx - fh - 12, 44),
        Offset(_cx - fh * 0.62, 23),
      ], closed: true);
      opening = _faceOpening(r, top: 57);
      break;

    case HairCover.hijabWrap:
      outer = _spline([
        Offset(_cx, 20),
        Offset(_cx + fh * 0.62, 24),
        Offset(_cx + fh + 11, 45),
        Offset(_cx + cw + 13, 78),
        Offset(_cx + cw + 14, 112),
        Offset(_cx + cw + 16, 142),
        Offset(_cx + cw + 22, 170),
        Offset(_cx + 30, 186),
        Offset(_cx, 190),
        Offset(_cx - 30, 186),
        Offset(_cx - cw - 22, 170),
        Offset(_cx - cw - 16, 142),
        Offset(_cx - cw - 14, 112),
        Offset(_cx - cw - 13, 78),
        Offset(_cx - fh - 11, 45),
        Offset(_cx - fh * 0.62, 24),
      ], closed: true);
      opening = _faceOpening(r, top: 57);
      break;

    case HairCover.babushka:
      outer = _spline([
        Offset(_cx, 21),
        Offset(_cx + fh * 0.62, 25),
        Offset(_cx + fh + 10, 46),
        Offset(_cx + cw + 11, 80),
        Offset(_cx + cw + 10, 108),
        Offset(_cx + cw + 6, 130),
        Offset(_cx + r.jawHalf * 0.9, chin + 2),
        Offset(_cx + 12, chin + 12),
        Offset(_cx - 12, chin + 12),
        Offset(_cx - r.jawHalf * 0.9, chin + 2),
        Offset(_cx - cw - 6, 130),
        Offset(_cx - cw - 10, 108),
        Offset(_cx - cw - 11, 80),
        Offset(_cx - fh - 10, 46),
        Offset(_cx - fh * 0.62, 25),
      ], closed: true);
      opening = _faceOpening(r, top: 56);
      break;

    case HairCover.shawl:
      final base = _spline([
        Offset(_cx, 20),
        Offset(_cx + fh * 0.62, 24),
        Offset(_cx + fh + 13, 44),
        Offset(_cx + cw + 18, 80),
        Offset(_cx + cw + 20, 114),
        Offset(_cx + cw + 22, 146),
        Offset(_cx + cw + 30, 176),
        Offset(_cx + cw + 36, 204),
        Offset(_cx - cw - 36, 204),
        Offset(_cx - cw - 30, 176),
        Offset(_cx - cw - 22, 146),
        Offset(_cx - cw - 20, 114),
        Offset(_cx - cw - 18, 80),
        Offset(_cx - fh - 13, 44),
        Offset(_cx - fh * 0.62, 24),
      ], closed: true);
      // Önde V açıklık: boyun ve kıyafet görünsün.
      final vOpen = Path()
        ..moveTo(_cx - 20, chin - 4)
        ..lineTo(_cx + 20, chin - 4)
        ..lineTo(_cx + 16, 204)
        ..lineTo(_cx - 16, 204)
        ..close();
      outer = Path.combine(PathOperation.difference, base, vOpen);
      opening = _faceOpening(r, top: 52, side: 1.06);
      break;

    case HairCover.turban:
      _paintTurban(canvas, r, cloth);
      return;

    case HairCover.bandana:
      _paintBandana(canvas, r, cloth);
      return;

    case HairCover.none:
      return;
  }

  final fabric = Path.combine(PathOperation.difference, outer, opening);

  // Örtünün yüze düşürdüğü gölge.
  if (r.detailed) {
    canvas.save();
    canvas.clipPath(r.head);
    canvas.drawPath(opening, r.stroke(_alpha(r.skinDeep, 0.55), 5, blur: 3));
    canvas.restore();
  }

  canvas.drawPath(fabric, r.fill(cloth));
  canvas.save();
  canvas.clipPath(fabric);

  // Kumaş hacmi ve kıvrımlar.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 210),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        const Offset(200, 0),
        [_alpha(Colors.white, 0.16), _alpha(Colors.black, 0.0), _alpha(Colors.black, 0.24)],
        const [0.0, 0.42, 1.0],
      ),
  );
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 210),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, foldStart),
        const Offset(0, 204),
        [_alpha(Colors.white, 0.10), _alpha(Colors.black, 0.20)],
      ),
  );
  if (r.detailed) {
    final rng = r.rngFor(470 + cover.index);
    // Yumuşak dikey kıvrım gölgeleri.
    for (var i = 0; i < 9; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final x0 = _cx + side * (cw + 4 + rng.nextDouble() * 22);
      canvas.drawPath(
        Path()
          ..moveTo(x0, 100 + rng.nextDouble() * 14)
          ..quadraticBezierTo(x0 + side * (3 + rng.nextDouble() * 5), 150, x0 + side * (8 + rng.nextDouble() * 10), 204),
        r.stroke(_alpha(Colors.black, 0.16 + 0.1 * rng.nextDouble()), 3 + rng.nextDouble() * 2, blur: 2.6),
      );
      canvas.drawPath(
        Path()
          ..moveTo(x0 - side * 3, 104)
          ..quadraticBezierTo(x0 + side * 2, 150, x0 + side * 6, 200),
        r.stroke(_alpha(Colors.white, 0.10), 2, blur: 1.8),
      );
    }
    // Alın kenarı boyunca kumaş kıvrımı.
    canvas.drawPath(
      Path()
        ..moveTo(_cx - cw * 0.9, 68)
        ..quadraticBezierTo(_cx, 46, _cx + cw * 0.9, 68),
      r.stroke(_alpha(Colors.black, 0.18), 2.4, blur: 2),
    );
    // Çene altı gölgesi.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx, chin + 8), width: 56, height: 22),
      r.soft(_alpha(Colors.black, 0.32), 5),
    );
    if (cover == HairCover.hijabWrap) {
      // Boyunda sarılı rulo.
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx, chin + 14), width: cw * 2.6, height: 20),
        r.soft(_alpha(Colors.white, 0.18), 3),
      );
      canvas.drawPath(
        Path()
          ..moveTo(_cx - cw * 1.2, chin + 10)
          ..quadraticBezierTo(_cx, chin + 26, _cx + cw * 1.2, chin + 10),
        r.stroke(_alpha(Colors.black, 0.30), 2.4, blur: 1.6),
      );
    }
  }
  canvas.restore();

  // Açıklık kenarına ince dikiş/vurgu.
  canvas.drawPath(opening, r.stroke(_alpha(Colors.black, 0.34), 1.0, blur: r.detailed ? 0.5 : 0));

  if (cover == HairCover.babushka) {
    // Çene altında düğüm ve iki uç.
    final knot = Offset(_cx, chin + 10);
    r.mirrored(canvas, (c, mir) {
      final tail = Path()
        ..moveTo(knot.dx - 2, knot.dy)
        ..quadraticBezierTo(knot.dx - 14, knot.dy + 10, knot.dx - 16, knot.dy + 22)
        ..lineTo(knot.dx - 7, knot.dy + 20)
        ..quadraticBezierTo(knot.dx - 6, knot.dy + 10, knot.dx + 1, knot.dy + 3)
        ..close();
      c.drawPath(tail, r.fill(_tone(cloth, mir ? -0.14 : 0.04)));
      c.drawPath(tail, r.stroke(_alpha(Colors.black, 0.25), 0.7));
    });
    canvas.drawCircle(knot, 5.2, r.fill(_tone(cloth, -0.06)));
    if (r.detailed) {
      canvas.drawCircle(knot.translate(-1.2, -1.2), 2.2, r.soft(_alpha(Colors.white, 0.3), 1.2));
      canvas.drawCircle(knot, 5.2, r.stroke(_alpha(Colors.black, 0.28), 0.7));
    }
  }
}

void _paintTurban(Canvas canvas, _Rig r, Color cloth) {
  final fh = r.foreheadHalf;
  final cw = r.cheekHalf;
  final dome = _spline([
    Offset(_cx, 12),
    Offset(_cx + fh * 0.7, 16),
    Offset(_cx + fh + 8, 34),
    Offset(_cx + fh + 10, 54),
    Offset(_cx + fh + 6, 70),
    Offset(_cx + fh * 0.5, 66),
    Offset(_cx, 60),
    Offset(_cx - fh * 0.5, 66),
    Offset(_cx - fh - 6, 70),
    Offset(_cx - fh - 10, 54),
    Offset(_cx - fh - 8, 34),
    Offset(_cx - fh * 0.7, 16),
  ], closed: true);
  canvas.drawPath(dome, r.fill(cloth));
  canvas.save();
  canvas.clipPath(dome);
  canvas.drawRect(
    dome.getBounds(),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(dome.getBounds().left, 0),
        Offset(dome.getBounds().right, 0),
        [_alpha(Colors.white, 0.20), _alpha(Colors.black, 0.0), _alpha(Colors.black, 0.28)],
        const [0.0, 0.45, 1.0],
      ),
  );
  if (r.detailed) {
    // Çapraz sarım kıvrımları.
    for (var i = 0; i < 6; i++) {
      final y = 20 + i * 8.0;
      final band = Path()
        ..moveTo(_cx - fh - 12, y + 10)
        ..quadraticBezierTo(_cx, y - 8 + (i.isEven ? 2 : -2), _cx + fh + 12, y + 14);
      canvas.drawPath(band, r.stroke(_alpha(Colors.black, 0.24), 2.4, blur: 1.4));
      canvas.drawPath(band.shift(const Offset(0, -2.4)), r.stroke(_alpha(Colors.white, 0.16), 1.6, blur: 1.0));
    }
  }
  canvas.restore();
  // Ön düğüm.
  final knot = Offset(_cx + fh * 0.32, 56);
  canvas.drawOval(Rect.fromCenter(center: knot, width: 18, height: 12), r.fill(_tone(cloth, -0.08)));
  if (r.detailed) {
    canvas.drawOval(Rect.fromCenter(center: knot.translate(-2, -1.5), width: 8, height: 4), r.soft(_alpha(Colors.white, 0.28), 1.4));
    canvas.drawPath(
      Path()
        ..moveTo(knot.dx - 8, knot.dy)
        ..quadraticBezierTo(knot.dx, knot.dy + 6, knot.dx + 8, knot.dy),
      r.stroke(_alpha(Colors.black, 0.3), 0.8),
    );
  }
  canvas.drawPath(dome, r.stroke(_alpha(Colors.black, 0.30), 0.9));
  cw.toString();
}

void _paintBandana(Canvas canvas, _Rig r, Color cloth) {
  // Saçın üstüne bağlanmış bandana: alın bandı + yandan düğüm.
  final g = _HairGeo(r);
  _paintHairlineShadow(canvas, r, g);
  _paintFade(canvas, r, g);
  _paintCap(canvas, r, g);
  _paintFringe(canvas, r, g);
  _paintSideLocks(canvas, r, g);
  final fh = r.foreheadHalf;
  final band = Path()
    ..moveTo(_cx - fh - 4, 66)
    ..quadraticBezierTo(_cx, 36, _cx + fh + 4, 66)
    ..lineTo(_cx + fh + 3, 58)
    ..quadraticBezierTo(_cx, 26, _cx - fh - 3, 58)
    ..close();
  canvas.drawPath(band, r.fill(cloth));
  if (r.detailed) {
    canvas.save();
    canvas.clipPath(band);
    final rng = r.rngFor(480);
    for (var i = 0; i < 26; i++) {
      canvas.drawCircle(
        Offset(_cx - fh + rng.nextDouble() * fh * 2, 34 + rng.nextDouble() * 32),
        0.9,
        r.fill(_alpha(Colors.white, 0.55)),
      );
    }
    canvas.drawRect(band.getBounds(), r.fill(_alpha(Colors.black, 0.10)));
    canvas.restore();
    canvas.drawPath(band, r.stroke(_alpha(Colors.black, 0.32), 0.8));
  }
  // Sağ şakakta düğüm.
  final knot = Offset(_cx + fh + 2, 62);
  canvas.drawCircle(knot, 4.6, r.fill(_tone(cloth, -0.08)));
  final tail = Path()
    ..moveTo(knot.dx, knot.dy)
    ..quadraticBezierTo(knot.dx + 10, knot.dy + 4, knot.dx + 14, knot.dy + 16)
    ..lineTo(knot.dx + 6, knot.dy + 12)
    ..quadraticBezierTo(knot.dx + 4, knot.dy + 6, knot.dx - 1, knot.dy + 3)
    ..close();
  canvas.drawPath(tail, r.fill(_tone(cloth, -0.14)));
  _paintTieFront(canvas, r, g);
  _paintSoftEdge(canvas, r, g);
}
