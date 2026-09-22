part of '../face_avatar_painter.dart';

// ============================================================================
// SAÇ MOTORU
//
// Saç, "kütle" (path) + o kütlenin içinde akış alanını izleyen tek tek teller
// olarak çizilir. Her kütle: taban dolgu → hacim gölgesi → teller/bukleler →
// kenar koyulaşması → parlama. Akış alanı stile göre değişir (yana taranmış,
// dik, arkaya taralı, aşağı akan…).
// ============================================================================

typedef _Flow = Offset Function(Offset p);

/// Saç stiline göre geometri sabitleri.
class _HairGeo {
  final _Rig r;
  final HairSpec s;
  _HairGeo(this.r) : s = r.hair;

  double get vol => r.hairVol;
  double get wid => r.hairWid;
  double get ex => 1.8 + 9.0 * wid;
  double get fh => r.foreheadHalf;
  double get cw => r.cheekHalf;
  double get W => fh + ex;
  static const double yc = 66;
  double get topY => 30 - 13 * vol;
  double get ry => yc - topY;

  /// Ayrım x'i (merkezden uzaklık, işaretli).
  double get partX => s.part * fh * 0.30;

  /// Saç çizgisinin merkezdeki y'si.
  double get hl {
    var y = 53.0;
    switch (s.hairline) {
      case Hairline.round:
        break;
      case Hairline.high:
        y -= 5;
        break;
      case Hairline.low:
        y += 4;
        break;
      case Hairline.widow:
        break;
      case Hairline.mShape:
        y -= 1;
        break;
      case Hairline.receding:
        y -= 2;
        break;
      case Hairline.straight:
        y += 1;
        break;
    }
    if (s.length == HairLength.buzz) y += 1;
    return y;
  }

  /// Sağ yarı saç çizgisi (merkezden şakağa), mutlak koordinat (sağ taraf).
  List<Offset> hairlineRight() {
    final f = fh;
    final h = hl;
    List<List<double>> pts;
    switch (s.hairline) {
      case Hairline.widow:
        pts = [
          [0, h + 6],
          [0.22, h + 1.4],
          [0.6, h + 4.5],
          [0.9, h + 13.5],
          [0.985, h + 23],
        ];
        break;
      case Hairline.mShape:
        pts = [
          [0, h],
          [0.3, h - 0.5],
          [0.58, h - 6.5],
          [0.8, h + 2],
          [0.93, h + 12],
          [0.985, h + 24],
        ];
        break;
      case Hairline.receding:
        pts = [
          [0, h - 1],
          [0.34, h - 3],
          [0.66, h - 8],
          [0.88, h + 3],
          [0.985, h + 19],
        ];
        break;
      case Hairline.straight:
        pts = [
          [0, h + 3],
          [0.5, h + 3.2],
          [0.86, h + 4.5],
          [0.97, h + 14],
          [0.985, h + 24],
        ];
        break;
      case Hairline.round:
      case Hairline.high:
      case Hairline.low:
        pts = [
          [0, h],
          [0.34, h + 1.2],
          [0.68, h + 5.5],
          [0.9, h + 13.5],
          [0.985, h + 23],
        ];
        break;
    }
    return pts.map((p) => Offset(_cx + p[0] * f, p[1])).toList();
  }

  /// Verilen |x| (merkezden uzaklık) için saç çizgisinin y'si.
  double hairlineY(double ax) {
    final pts = hairlineRight();
    final x = ax.clamp(0.0, fh * 0.985);
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].dx - _cx >= x) {
        final a = pts[i - 1], b = pts[i];
        final t = (x - (a.dx - _cx)) / math.max(0.0001, (b.dx - a.dx));
        return _lerpD(a.dy, b.dy, t);
      }
    }
    return pts.last.dy;
  }

  /// Yan kısmın bittiği y (favori/kulak hizası).
  double get sideEndY {
    switch (s.length) {
      case HairLength.bald:
      case HairLength.buzz:
        return 79;
      case HairLength.crop:
        return 82;
      case HairLength.short:
        return 89;
      case HairLength.pulled:
        return 82;
      case HairLength.ear:
        return 106;
      case HairLength.jaw:
      case HairLength.shoulder:
      case HairLength.long:
      case HairLength.xlong:
        return 90;
    }
  }

  bool get longSides =>
      s.length == HairLength.jaw ||
      s.length == HairLength.shoulder ||
      s.length == HairLength.long ||
      s.length == HairLength.xlong;

  double get lockEndY {
    switch (s.length) {
      case HairLength.jaw:
        return r.chinY - 4;
      case HairLength.shoulder:
        return 172;
      case HairLength.long:
        return 192;
      case HairLength.xlong:
        return 210;
      default:
        return sideEndY;
    }
  }
}

// ------------------------------------------------------------- akış alanları
Offset _norm(Offset o) {
  final d = o.distance;
  return d == 0 ? const Offset(0, 1) : o / d;
}

/// Alından tepeye radyal, biraz yer çekimiyle.
_Flow _flowRadial(_HairGeo g, {double gravity = 0.45, Offset? center}) {
  final c = center ?? Offset(_cx + g.partX * 0.3, 62);
  return (p) {
    final v = _norm(p - c);
    return _norm(v * (1 - gravity) + Offset(0, gravity));
  };
}

/// Ayrımdan iki yana aşağı, ya da tümü tek yana taranmış.
_Flow _flowPart(_HairGeo g, {double sweep = 0.0, double drop = 0.55}) {
  final s = g.s.part == 0 ? 1 : g.s.part;
  return (p) {
    final xr = (p.dx - (_cx + g.partX)) / g.W;
    final hx = xr * 0.75 + (-s) * sweep;
    return _norm(Offset(hx, drop + 0.35 * ((p.dy - g.topY) / g.ry).clamp(0.0, 1.5)));
  };
}

/// Arkaya taralı (alından tepeye doğru).
_Flow _flowBack(_HairGeo g) {
  return (p) {
    final xr = (p.dx - _cx) / g.W;
    return _norm(Offset(xr * 0.35, -1.0));
  };
}

/// Yukarı ve dışa dik.
_Flow _flowUp(_HairGeo g, {double lean = 0.0}) {
  return (p) {
    final xr = (p.dx - _cx) / g.W;
    return _norm(Offset(xr * 0.9 + lean, -1.0));
  };
}

/// Uzun saç: aşağı akar, hafif dışa.
_Flow _flowDown(_HairGeo g, {double spread = 0.28}) {
  return (p) {
    final xr = (p.dx - _cx) / (g.W + 6);
    return _norm(Offset(xr * spread, 1.0));
  };
}

// --------------------------------------------------------------- tel çizimi
Color _strandColor(_Rig r, math.Random rng, Offset p, _HairGeo g) {
  // Işık sol üstten: sol üst bölgede teller biraz daha açık.
  final lightT = (((_cx - p.dx) * 0.6 + (g.hl - p.dy) * 0.9) / 55 + 0.35).clamp(0.0, 1.0);
  final roll = rng.nextDouble();
  if (roll < 0.34) return _mix(r.hairColor, r.hairDark, 0.18 + 0.30 * rng.nextDouble());
  if (roll < 0.72) return _mix(r.hairColor, r.hairLight, (0.05 + 0.22 * lightT) * rng.nextDouble());
  return _mix(r.hairMid, r.hairColor, 0.4 + 0.6 * rng.nextDouble());
}

/// [region] içinde rastgele noktalardan akış alanını izleyen teller çizer.
void _strands(
  Canvas c,
  _Rig r,
  _HairGeo g,
  Path region, {
  required _Flow flow,
  required int count,
  double len = 9,
  double width = 0.85,
  double curl = 0,
  double wavelength = 9,
  int seed = 1,
  double alphaLo = 0.20,
  double alphaHi = 0.46,
}) {
  if (!r.detailed) return;
  final bounds = region.getBounds();
  final rng = r.rngFor(seed);
  var made = 0;
  var tries = 0;
  while (made < count && tries < count * 6) {
    tries++;
    final p = Offset(
      bounds.left + rng.nextDouble() * bounds.width,
      bounds.top + rng.nextDouble() * bounds.height,
    );
    if (!region.contains(p)) continue;
    made++;
    final pts = <Offset>[p];
    var cur = p;
    const steps = 5;
    final stepLen = len * (0.7 + 0.6 * rng.nextDouble()) / steps;
    final phase = rng.nextDouble() * math.pi * 2;
    for (var i = 1; i <= steps; i++) {
      final d = flow(cur);
      final perp = Offset(-d.dy, d.dx);
      final wave = curl * math.sin(i * (2 * math.pi * stepLen / wavelength) + phase) * (0.6 + 0.4 * rng.nextDouble());
      cur = cur + d * stepLen + perp * wave * 0.9;
      pts.add(cur);
    }
    final col = _strandColor(r, rng, p, g);
    _taper(c, pts, width * (0.8 + 0.7 * rng.nextDouble()), 0.14, r.fill(_alpha(col, alphaLo + (alphaHi - alphaLo) * rng.nextDouble())));
  }
}

/// Sıkı bukle/afro dokusu: birbirine yaslanmış küçük tutamlar (tüylü doku).
void _coils(Canvas c, _Rig r, _HairGeo g, Path region, {required int seed, double radius = 2.6, double density = 1.0}) {
  final bounds = region.getBounds();
  final rng = r.rngFor(seed);
  final area = bounds.width * bounds.height * 0.65;
  final blobs = ((r.detailed ? area / (radius * radius * 1.5) : area / (radius * radius * 30)) * density).round();
  for (var i = 0; i < blobs; i++) {
    final p = Offset(
      bounds.left + rng.nextDouble() * bounds.width,
      bounds.top + rng.nextDouble() * bounds.height,
    );
    if (!region.contains(p)) continue;
    final rad = radius * (0.55 + 0.6 * rng.nextDouble());
    final lightT = (((_cx - p.dx) * 0.6 + (g.hl - p.dy) * 0.9) / 55 + 0.35).clamp(0.0, 1.0);
    final roll = rng.nextDouble();
    final col = roll < 0.48
        ? _mix(r.hairColor, r.hairDark, 0.30 + 0.4 * rng.nextDouble())
        : roll < 0.94
            ? _mix(r.hairColor, r.hairLight, (0.05 + 0.30 * lightT) * rng.nextDouble())
            : _mix(r.hairColor, r.hairShine, 0.18 + 0.25 * lightT);
    c.drawCircle(p, rad, r.fill(_alpha(col, 0.50 + 0.4 * rng.nextDouble())));
  }
  if (!r.detailed) return;
  final arcs = (blobs * 0.30).round();
  for (var i = 0; i < arcs; i++) {
    final p = Offset(
      bounds.left + rng.nextDouble() * bounds.width,
      bounds.top + rng.nextDouble() * bounds.height,
    );
    if (!region.contains(p)) continue;
    final rad = radius * (0.6 + 0.5 * rng.nextDouble());
    c.drawArc(
      Rect.fromCircle(center: p, radius: rad),
      rng.nextDouble() * math.pi * 2,
      math.pi * (0.9 + 0.5 * rng.nextDouble()),
      false,
      r.stroke(_alpha(r.hairDark, 0.32), 0.6),
    );
  }
}

/// Yolun kenarını düşük frekanslı gürültüyle hafifçe dalgalandırır: tam
/// simetrik, "kesilmiş" görünen siluetleri doğal ve organik yapar.
Path _wobble(Path src, double amp, int seed, {double step = 2.2}) {
  final rng = math.Random(seed * 131 + 7);
  final p1 = rng.nextDouble() * 6.28, p2 = rng.nextDouble() * 6.28, p3 = rng.nextDouble() * 6.28;
  final out = Path();
  for (final m in src.computeMetrics()) {
    final pts = <Offset>[];
    final n = math.max(6, (m.length / step).round());
    for (var i = 0; i < n; i++) {
      final d = m.length * i / n;
      final tg = m.getTangentForOffset(d)!;
      final v = tg.vector;
      final nrm = Offset(v.dy, -v.dx);
      final noise = math.sin(d * 0.21 + p1) * 0.5 + math.sin(d * 0.47 + p2) * 0.32 + math.sin(d * 1.1 + p3) * 0.18;
      pts.add(tg.position + nrm * (noise * amp));
    }
    out.extendWithPath(_spline(pts, closed: m.isClosed, tension: 1.0), Offset.zero);
  }
  return out;
}

/// Kütleyi boyar: dolgu → hacim → teller/bukleler → kenar → parlama.
void _paintMass(
  Canvas c,
  _Rig r,
  _HairGeo g,
  Path massPath, {
  required _Flow flow,
  int strands = 320,
  double len = 9,
  double width = 0.85,
  int seed = 1,
  double edge = 0.5,
  double sheen = 0.30,
  Color? base,
  HairTexture? texture,
  double? curl,
  double wobble = 0.9,
  bool halo = false,
}) {
  final tex = texture ?? g.s.texture;
  final curlAmt = curl ?? g.s.curl;
  final path = (r.detailed && wobble > 0) ? _wobble(massPath, wobble, seed) : massPath;
  c.drawPath(path, r.fill(base ?? r.hairColor));
  if (!r.detailed) {
    return;
  }

  c.save();
  c.clipPath(path);
  final b = path.getBounds();

  // Işık: sol üst açık, sağ alt koyu.
  c.drawRect(
    b.inflate(4),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(b.left, b.top),
        Offset(b.right, b.bottom),
        [_alpha(r.hairLight, 0.30), _alpha(r.hairDark, 0.0), _alpha(r.hairDark, 0.34)],
        const [0.0, 0.5, 1.0],
      ),
  );

  switch (tex) {
    case HairTexture.smooth:
      _strands(c, r, g, path, flow: flow, count: strands, len: len, width: width, seed: seed);
      break;
    case HairTexture.wavy:
      _strands(c, r, g, path, flow: flow, count: strands, len: len * 1.15, width: width, curl: 0.6 + 1.6 * curlAmt, wavelength: 11, seed: seed);
      break;
    case HairTexture.curly:
      _strands(c, r, g, path, flow: flow, count: (strands * 0.55).round(), len: len, width: width * 1.2, curl: 1.4 + 1.8 * curlAmt, wavelength: 6, seed: seed, alphaLo: 0.25, alphaHi: 0.55);
      _coils(c, r, g, path, seed: seed + 5, radius: 3.4, density: 0.55);
      break;
    case HairTexture.coily:
      c.drawRect(b.inflate(2), r.fill(_alpha(r.hairDark, 0.35)));
      _coils(c, r, g, path, seed: seed + 9, radius: 2.1, density: 1.15);
      break;
  }

  // Kenar koyulaşması (hacim).
  c.drawPath(path, r.stroke(_alpha(r.hairDark, edge), 5, blur: 2.6));

  // Tepede parlak halka (stüdyo ışığının saçta bıraktığı yansıma).
  if (halo) {
    c.drawArc(
      Rect.fromCenter(center: Offset(_cx - 3, 60), width: g.W * 1.55, height: g.ry * 1.25),
      math.pi * 1.12,
      math.pi * 0.62,
      false,
      r.stroke(_alpha(r.hairShine, 0.30), 7.5, blur: 4.2),
    );
    c.drawArc(
      Rect.fromCenter(center: Offset(_cx - 2, 62), width: g.W * 1.35, height: g.ry * 1.05),
      math.pi * 1.18,
      math.pi * 0.42,
      false,
      r.stroke(_alpha(r.hairShine, 0.22), 2.4, blur: 1.6),
    );
  }

  // Parlama bandı.
  if (sheen > 0) {
    c.drawOval(
      Rect.fromLTWH(b.left + b.width * 0.06, b.top + b.height * 0.04, b.width * 0.62, b.height * 0.36),
      r.soft(_alpha(r.hairShine, sheen * 1.15), 6),
    );
  }
  c.restore();
}

/// Tek bir tutam (yaprak biçimli, ucu sivri kıvrımlı sap).
Path _lock(Offset base, Offset tip, double width, {double bend = 0.0}) {
  final d = tip - base;
  final len = d.distance;
  final dir = len == 0 ? const Offset(0, 1) : d / len;
  final nrm = Offset(-dir.dy, dir.dx);
  final mid = base + d * 0.5 + nrm * (bend * len);
  return Path()
    ..moveTo(base.dx - nrm.dx * width / 2, base.dy - nrm.dy * width / 2)
    ..quadraticBezierTo(mid.dx - nrm.dx * width * 0.62, mid.dy - nrm.dy * width * 0.62, tip.dx, tip.dy)
    ..quadraticBezierTo(mid.dx + nrm.dx * width * 0.62, mid.dy + nrm.dy * width * 0.62, base.dx + nrm.dx * width / 2, base.dy + nrm.dy * width / 2)
    ..close();
}

// ======================================================================== ARKA
void _paintHairBack(Canvas canvas, _Rig r) {
  final s = r.hair;
  if (s.covered) {
    _paintCoverBack(canvas, r);
    return;
  }
  if (s.bald) return;
  final g = _HairGeo(r);
  _paintBackMass(canvas, r, g);
  _paintTieBack(canvas, r, g);
}

/// Uzun saçın kafanın arkasındaki kütlesi (omuzların ve boynun arkası).
void _paintBackMass(Canvas canvas, _Rig r, _HairGeo g) {
  final s = g.s;
  if (!g.longSides && s.length != HairLength.ear) return;
  if (s.length == HairLength.ear) {
    // Kulak boyu: kafanın etrafında hafif hacim.
    final W = g.W + 2;
    final path = _spline([
      Offset(_cx - W, 70),
      Offset(_cx - W - 1, 96),
      Offset(_cx - W + 3, 116),
      Offset(_cx + W - 3, 116),
      Offset(_cx + W + 1, 96),
      Offset(_cx + W, 70),
      Offset(_cx, g.topY + 2),
    ], closed: true);
    _paintMass(canvas, r, g, path, flow: _flowDown(g), strands: 160, len: 12, seed: 11, base: r.hairMid, edge: 0.6, sheen: 0.12);
    return;
  }

  final W = g.W + 5 + (s.layered ? 2 : 0);
  final end = g.lockEndY + (g.s.length == HairLength.jaw ? 2 : 0);
  final bobIn = s.length == HairLength.jaw ? 5.0 : 0.0; // bob uçları içe döner
  final wave = s.texture == HairTexture.smooth ? 0.0 : 3.0;

  final path = Path()
    ..moveTo(_cx - W + 1, 66)
    ..cubicTo(_cx - W - 5, 96, _cx - W - 3 - wave, (66 + end) / 2, _cx - W + 1 + bobIn - wave, end)
    ..quadraticBezierTo(_cx, end + 7, _cx + W - 1 - bobIn + wave, end)
    ..cubicTo(_cx + W + 3 + wave, (66 + end) / 2, _cx + W + 5, 96, _cx + W - 1, 66)
    ..cubicTo(_cx + W - 6, g.topY + 6, _cx - W + 6, g.topY + 6, _cx - W + 1, 66)
    ..close();

  // Katmanlı uçlar: alt kenarı tırtıklı.
  Path shaped = path;
  if (s.layered && end < 205) {
    final rng = r.rngFor(30 + r.cfg.hair);
    final teeth = Path();
    var x = _cx - W;
    while (x < _cx + W) {
      final w = 6 + rng.nextDouble() * 7;
      teeth.addPolygon([
        Offset(x, end - 1),
        Offset(x + w / 2, end + 6 + rng.nextDouble() * 8),
        Offset(x + w, end - 1),
      ], true);
      x += w;
    }
    shaped = Path.combine(PathOperation.union, path, teeth);
  }

  _paintMass(
    canvas,
    r,
    g,
    shaped,
    flow: _flowDown(g, spread: 0.32),
    strands: 520,
    len: 18,
    width: 0.95,
    seed: 21,
    base: r.hairMid,
    edge: 0.62,
    sheen: 0.10,
  );
  if (r.detailed) {
    // Arka saç iç kısımda gölgeli: kafanın altına düşen koyu bölge.
    canvas.save();
    canvas.clipPath(shaped);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx, 120), width: W * 1.9, height: 110),
      r.soft(_alpha(r.hairDark, 0.55), 12),
    );
    canvas.restore();
  }
}

// ======================================================================== ÖN
void _paintHairFront(Canvas canvas, _Rig r) {
  final s = r.hair;
  if (s.covered) {
    _paintCoverFront(canvas, r);
    return;
  }
  if (s.bald) return;
  final g = _HairGeo(r);

  _paintHairlineShadow(canvas, r, g);
  _paintTieUnder(canvas, r, g); // tepe dikenleri, mohawk, afro topuz kabarması
  _paintFade(canvas, r, g);
  _paintCap(canvas, r, g);
  _paintFringe(canvas, r, g);
  _paintSideLocks(canvas, r, g);
  _paintTieFront(canvas, r, g);
  _paintSoftEdge(canvas, r, g);
}

/// Saçın alına düşürdüğü yumuşak gölge.
void _paintHairlineShadow(Canvas canvas, _Rig r, _HairGeo g) {
  if (!r.detailed) return;
  canvas.save();
  canvas.clipPath(r.head);
  final pts = g.hairlineRight();
  final line = <Offset>[
    for (final p in pts.reversed) Offset(_cx - (p.dx - _cx), p.dy),
    ...pts.skip(1),
  ];
  canvas.drawPath(
    _spline(line.map((p) => p.translate(0, 2.2)).toList()),
    r.stroke(_alpha(r.skinDeep, 0.32), 5, blur: 3),
  );
  canvas.restore();
}

/// Yan tıraş (fade): yanlarda saç rengine doğru yumuşak geçiş + kısa kıllar.
void _paintFade(Canvas canvas, _Rig r, _HairGeo g) {
  final s = g.s;
  if (s.fade == HairFade.none && s.length != HairLength.buzz) return;
  final strength = switch (s.fade) {
    HairFade.none => 0.55,
    HairFade.low => 0.42,
    HairFade.mid => 0.58,
    HairFade.high => 0.72,
    HairFade.skin => 0.86,
  };
  // Fade çizgisi (üstte saç, altta ten): düşük fade kulağın yakınında, yüksek
  // fade şakak hizasında başlar.
  final topFade = switch (s.fade) {
    HairFade.low => 92.0,
    HairFade.mid => 82.0,
    HairFade.high => 72.0,
    HairFade.skin => 68.0,
    HairFade.none => 70.0,
  };

  canvas.save();
  canvas.clipPath(r.head);
  final rng = r.rngFor(45);
  r.mirrored(canvas, (c, mir) {
    // Kulak çevresi ve şakak: hair tonunda yumuşak elips.
    final cx0 = _cx - r.cheekHalf;
    final rect = Rect.fromLTRB(cx0 - 6, topFade - 4, cx0 + 14, 116);
    c.drawOval(rect, r.soft(_alpha(r.hairColor, strength * (mir ? 0.85 : 0.75)), r.detailed ? 5 : 0));
    if (r.detailed) {
      for (var i = 0; i < 220; i++) {
        final p = Offset(cx0 - 5 + rng.nextDouble() * 20, topFade - 2 + rng.nextDouble() * (108 - topFade));
        final fade = 1 - ((p.dy - (topFade - 2)) / (110 - topFade)).clamp(0.0, 1.0);
        c.drawCircle(p, 0.32, r.fill(_alpha(r.hairDark, 0.30 * fade * strength + 0.04)));
      }
    }
  });
  canvas.restore();
}

/// Tepe kütlesi (saç çizgisinin üstü + favoriler).
Path _capPath(_HairGeo g, _Rig r, {double growTop = 0}) {
  final s = g.s;
  final W = g.W;
  final topY = g.topY - growTop;
  final ry = _HairGeo.yc - topY;
  final sbY = g.sideEndY;
  final sbW = 1.6 + g.ex * 0.85 + (s.length == HairLength.ear ? 2.6 : 0);
  Offset mir(Offset p) => Offset(_cx - (p.dx - _cx), p.dy);

  double outerX(double y) {
    final t = ((y - _HairGeo.yc) / (sbY - _HairGeo.yc)).clamp(0.0, 1.0);
    final st = t * t * (3 - 2 * t);
    return _lerpD(W, r.headX(sbY) + sbW * 0.3, st);
  }

  // Dış kenar (sağ yarı): tepeden favori altına.
  final rightOuter = <Offset>[
    Offset(_cx, topY),
    Offset(_cx + 0.5 * W, _HairGeo.yc - 0.866 * ry),
    Offset(_cx + 0.866 * W, _HairGeo.yc - 0.5 * ry),
    Offset(_cx + W, _HairGeo.yc),
    Offset(_cx + outerX(_HairGeo.yc + (sbY - _HairGeo.yc) * 0.5), _HairGeo.yc + (sbY - _HairGeo.yc) * 0.5),
    Offset(_cx + outerX(sbY), sbY),
  ];
  final arc = <Offset>[
    ...rightOuter.skip(1).toList().reversed.map(mir),
    ...rightOuter,
  ];

  final path = _spline(arc);

  // Sağ favori: altından kafa kenarı boyunca yukarı.
  final hl = g.hairlineRight();
  final hlEndY = hl.last.dy;
  path.lineTo(_cx + r.headX(sbY) - 0.4, sbY - 0.2);
  final ys = <double>[];
  for (var y = sbY - 0.6; y > hlEndY; y -= 5) {
    ys.add(y);
  }
  for (final y in ys) {
    path.lineTo(_cx + r.headX(y) - 0.6, y);
  }
  // Saç çizgisi: sağ şakaktan sola.
  final hlFull = <Offset>[...hl.reversed, ...hl.skip(1).map(mir)];
  path.extendWithPath(_spline(hlFull), Offset.zero);
  // Sol favori: yukarıdan aşağı.
  for (final y in ys.reversed) {
    path.lineTo(_cx - r.headX(y) + 0.6, y);
  }
  path.lineTo(_cx - r.headX(sbY) + 0.4, sbY - 0.2);
  path.close();
  return path;
}

void _paintCap(Canvas canvas, _Rig r, _HairGeo g) {
  final s = g.s;
  if (s.length == HairLength.bald) return;

  final cap = _capPath(g, r);
  final flow = _capFlow(g);

  final tex = s.texture;
  final isBuzz = s.length == HairLength.buzz;
  _paintMass(
    canvas,
    r,
    g,
    cap,
    flow: flow,
    strands: isBuzz ? 90 : (tex == HairTexture.smooth ? 420 : 320),
    len: switch (s.length) {
      HairLength.buzz => 2.5,
      HairLength.crop => 5,
      HairLength.short => 8,
      _ => 11,
    },
    width: isBuzz ? 0.5 : 0.85,
    seed: 100 + r.cfg.hair,
    edge: isBuzz ? 0.18 : 0.5,
    sheen: isBuzz ? 0.12 : 0.34,
    halo: !isBuzz && tex != HairTexture.coily,
  );
  if (!isBuzz) _flyaways(canvas, r, g);
}

/// Silueti kıran ince, uçuşan teller.
void _flyaways(Canvas canvas, _Rig r, _HairGeo g) {
  if (!r.detailed) return;
  final rng = r.rngFor(330 + r.cfg.hair);
  final curly = g.s.texture == HairTexture.curly || g.s.texture == HairTexture.coily;
  final n = curly ? 9 : (g.vol > 0.6 ? 4 : 0);
  for (var i = 0; i < n; i++) {
    final a = math.pi * (0.08 + 0.84 * rng.nextDouble()); // üst yay
    final rx = g.W - 0.6;
    final base = Offset(_cx - math.cos(a) * rx, _HairGeo.yc - math.sin(a) * (g.ry - 0.6));
    final out = _norm(Offset(-math.cos(a) * 0.9, -math.sin(a) * 0.9 * (g.ry / rx)));
    final side = Offset(-out.dy, out.dx);
    final len = (curly ? 4.0 : 5.0) + rng.nextDouble() * (curly ? 4.0 : 7.0);
    final bend = (rng.nextDouble() - 0.5) * 6.0;
    final p1 = base + out * (len * 0.4) + side * (bend * 0.35);
    final p2 = base + out * (len * 0.75) + side * (bend * 0.85);
    final tip = base + out * len + side * bend;
    _taper(
      canvas,
      [base.translate(-out.dx * 1.5, -out.dy * 1.5), p1, p2, tip],
      0.5,
      0.06,
      r.fill(_alpha(_mix(r.hairColor, r.hairLight, 0.20 * rng.nextDouble()), 0.34)),
    );
  }
}

_Flow _capFlow(_HairGeo g) {
  switch (g.s.fringe) {
    case HairFringe.slick:
      return _flowBack(g);
    case HairFringe.spiky:
    case HairFringe.quiff:
    case HairFringe.pomp:
    case HairFringe.messy:
      return _flowUp(g, lean: 0.1 * g.s.part);
    case HairFringe.sweep:
    case HairFringe.sweepLong:
    case HairFringe.wave:
      return _flowPart(g, sweep: 0.55);
    case HairFringe.comb:
      return _flowPart(g, sweep: 0.25, drop: 0.7);
    case HairFringe.curtain:
      return _flowPart(g, sweep: 0.0, drop: 0.8);
    default:
      return _flowRadial(g, gravity: g.s.length == HairLength.short ? 0.5 : 0.35);
  }
}

// ---------------------------------------------------------------- kâkül
void _paintFringe(Canvas canvas, _Rig r, _HairGeo g) {
  final s = g.s;
  final fringe = r.fringe;
  if (fringe == HairFringe.none) return;
  if (s.length == HairLength.buzz) return;
  final fh = g.fh;
  final hl = g.hl;
  final side = s.part == 0 ? 1 : s.part;
  final W = g.W;

  switch (fringe) {
    case HairFringe.none:
      return;

    case HairFringe.micro:
    case HairFringe.crop:
    case HairFringe.comb:
      // Alın kenarında kısa, ileri taranmış bir şerit.
      final depth = fringe == HairFringe.micro ? 4.5 : 6.0;
      final top = <Offset>[
        for (final p in g.hairlineRight().reversed) Offset(_cx - (p.dx - _cx), p.dy - 6),
        for (final p in g.hairlineRight().skip(1)) Offset(p.dx, p.dy - 6),
      ];
      final low = <Offset>[
        for (final p in g.hairlineRight().reversed) Offset(_cx - (p.dx - _cx), p.dy + depth * (1 - (p.dx - _cx) / fh * 0.5)),
        for (final p in g.hairlineRight().skip(1)) Offset(p.dx, p.dy + depth * (1 - (p.dx - _cx) / fh * 0.5)),
      ];
      final path = Path()..moveTo(top.first.dx, top.first.dy);
      for (final p in top.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      for (final p in low.reversed) {
        path.lineTo(p.dx, p.dy);
      }
      path.close();
      _paintMass(canvas, r, g, path, flow: _flowPart(g, sweep: fringe == HairFringe.comb ? 0.35 : 0.1, drop: 0.9), strands: 90, len: 5, seed: 210, edge: 0.15, sheen: 0.2);
      if (fringe == HairFringe.comb && r.detailed) {
        // Sert ayrım çizgisi.
        canvas.drawPath(
          Path()
            ..moveTo(_cx + g.partX, hl + 2)
            ..quadraticBezierTo(_cx + g.partX + side * 1.5, hl - 8, _cx + g.partX + side * 3, g.topY + 6),
          r.stroke(_alpha(r.skinDeep, 0.55), 0.9),
        );
        canvas.drawPath(
          Path()
            ..moveTo(_cx + g.partX + 1, hl + 1)
            ..quadraticBezierTo(_cx + g.partX + side * 2.5, hl - 8, _cx + g.partX + side * 4, g.topY + 7),
          r.stroke(_alpha(r.hairShine, 0.45), 0.7),
        );
      }
      return;

    case HairFringe.sweep:
    case HairFringe.sweepLong:
    case HairFringe.wave:
      final long = fringe != HairFringe.sweep;
      final farX = -side * fh * 1.0;
      final endY = hl + 23 + (long ? 16 : 0) + (fringe == HairFringe.wave ? 4 : 0);
      final ctrlY = hl + (long ? 30 : 17);
      final pX = _cx + g.partX;
      // Yakın taraf: ayrımdan şakağa küçük örtü.
      // Üst sınır: saç çizgisi, ayrımdan uzak şakağa.
      final topEdge = <Offset>[];
      for (var i = 0; i <= 8; i++) {
        final t = i / 8;
        final x = _lerpD(g.partX, farX, t);
        topEdge.add(Offset(_cx + x, g.hairlineY(x.abs()) - 6));
      }
      final path = Path()..moveTo(pX, hl - 3);
      for (final p in topEdge) {
        path.lineTo(p.dx, p.dy);
      }
      path.lineTo(_cx + farX * 1.01, endY);
      path.quadraticBezierTo(_cx + farX * 0.30, ctrlY + (fringe == HairFringe.wave ? 6 : 0), pX, hl + 3);
      path.close();
      _paintMass(canvas, r, g, path, flow: _flowPart(g, sweep: 0.9, drop: 0.35), strands: 240, len: 14, seed: 220, edge: 0.20, sheen: 0.32);
      if (fringe == HairFringe.wave && r.detailed) {
        for (var i = 0; i < 3; i++) {
          canvas.drawPath(
            Path()
              ..moveTo(pX, hl + 2 + i * 6)
              ..quadraticBezierTo(_cx + farX * 0.45, hl + 8 + i * 7, _cx + farX * 0.95, hl + 18 + i * 6),
            r.stroke(_alpha(r.hairShine, 0.28), 1.6, blur: 1.2),
          );
        }
      }
      return;

    case HairFringe.blunt:
    case HairFringe.wispy:
      final low = r.browBaseY - (fringe == HairFringe.wispy ? 5.5 : 4.5);
      final path = Path()..moveTo(_cx - fh * 1.0, hl + 22);
      final hlr = g.hairlineRight();
      for (final p in hlr.reversed) {
        path.lineTo(_cx - (p.dx - _cx), p.dy - 6);
      }
      for (final p in hlr.skip(1)) {
        path.lineTo(p.dx, p.dy - 6);
      }
      path
        ..lineTo(_cx + fh * 1.02, low + 4)
        ..quadraticBezierTo(_cx, low + 4.5, _cx - fh * 1.02, low + 4)
        ..close();
      _paintMass(
        canvas,
        r,
        g,
        path,
        flow: (p) => _norm(Offset((p.dx - _cx) / W * 0.25, 1.0)),
        strands: fringe == HairFringe.wispy ? 140 : 260,
        len: 12,
        seed: 230,
        edge: 0.22,
        sheen: 0.28,
      );
      if (fringe == HairFringe.wispy && r.detailed) {
        // Seyrek: alt kenardan ten görünsün.
        final rng = r.rngFor(231);
        canvas.save();
        canvas.clipPath(r.head);
        for (var i = 0; i < 12; i++) {
          final x = _cx - fh + rng.nextDouble() * fh * 2;
          canvas.drawLine(Offset(x, low - 2), Offset(x + (rng.nextDouble() - 0.5) * 2, low + 6), r.stroke(_alpha(r.skin, 0.9), 1.5));
        }
        canvas.restore();
      }
      return;

    case HairFringe.curtain:
      final extra = g.longSides ? 12.0 : 0.0;
      r.mirrored(canvas, (c, mir) {
        final path = Path()
          ..moveTo(_cx - 0.02 * fh, hl - 8)
          ..lineTo(_cx - fh * 1.0, g.hairlineY(fh * 0.985) - 8)
          ..lineTo(_cx - fh * 1.0, g.hairlineY(fh * 0.985) - 2)
          ..lineTo(_cx - fh * 1.06, hl + 26 + extra)
          ..quadraticBezierTo(_cx - fh * 0.5, hl + 8, _cx - 0.05 * fh, hl + 5)
          ..close();
        _paintMass(c, r, g, path, flow: (p) => _norm(Offset(-0.6 + (p.dx - (_cx - fh * 0.5)) / W * 0.2, 0.7)), strands: 120, len: 12, seed: 240 + (mir ? 1 : 0), edge: 0.16, sheen: 0.28);
      });
      return;

    case HairFringe.quiff:
    case HairFringe.pomp:
      // Alnın üstünde yüksek, kıvrımlı hacim.
      final big = fringe == HairFringe.pomp;
      final cx0 = _cx + g.partX * 0.5;
      final hgt = (big ? 22.0 : 16.0) + g.vol * 5;
      final path = Path()
        ..moveTo(_cx - fh * 0.98, hl + 12)
        ..cubicTo(_cx - fh * 1.05, hl - hgt * 0.6, cx0 - fh * 0.5, hl - hgt, cx0 + fh * 0.05, hl - hgt - 1)
        ..cubicTo(cx0 + fh * 0.7, hl - hgt + 2, _cx + fh * 1.05, hl - hgt * 0.4, _cx + fh * 0.98, hl + 12)
        ..cubicTo(_cx + fh * 0.6, hl + 1, _cx + fh * 0.2, hl - 2, _cx, hl - 1)
        ..cubicTo(_cx - fh * 0.2, hl - 2, _cx - fh * 0.6, hl + 1, _cx - fh * 0.98, hl + 12)
        ..close();
      _paintMass(canvas, r, g, path, flow: _flowUp(g, lean: 0.12 * side), strands: 260, len: 11, seed: 250, edge: 0.55, sheen: 0.42);
      if (r.detailed) {
        // Kıvrımın önünde parlak kenar çizgisi.
        canvas.drawPath(
          Path()
            ..moveTo(_cx - fh * 0.7, hl + 4)
            ..quadraticBezierTo(cx0, hl - hgt * 0.5, _cx + fh * 0.7, hl + 4),
          r.stroke(_alpha(r.hairShine, 0.35), 1.6, blur: 1.2),
        );
      }
      return;

    case HairFringe.slick:
      if (r.detailed) {
        // Arkaya tarak izleri.
        final rng = r.rngFor(260);
        canvas.save();
        canvas.clipPath(_capPath(g, r));
        for (var i = 0; i < 26; i++) {
          final x0 = -fh * 0.95 + (i / 25) * fh * 1.9;
          final start = Offset(_cx + x0, g.hairlineY(x0.abs()) + 1);
          final end = Offset(_cx + x0 * 0.85, g.topY + 6 + rng.nextDouble() * 4);
          canvas.drawPath(
            Path()
              ..moveTo(start.dx, start.dy)
              ..quadraticBezierTo((start.dx + end.dx) / 2 + (rng.nextDouble() - 0.5) * 3, (start.dy + end.dy) / 2, end.dx, end.dy),
            r.stroke(_alpha(i.isEven ? r.hairShine : r.hairDark, i.isEven ? 0.28 : 0.30), 0.8),
          );
        }
        canvas.restore();
      }
      return;

    case HairFringe.spiky:
      // Ön hattı boyunca kısa dikenler.
      for (var i = 0; i < 9; i++) {
        final t = (i + 0.5) / 9;
        final x = -fh * 0.92 + t * fh * 1.84;
        final base = Offset(_cx + x, g.hairlineY(x.abs()) + 1.5);
        final tip = Offset(_cx + x * 1.08, base.dy - 5 - (i.isEven ? 4 : 1));
        final lockP = _lock(base.translate(0, 4), tip, 8.5);
        canvas.drawPath(lockP, r.fill(r.hairColor));
        if (r.detailed) canvas.drawPath(lockP, r.stroke(_alpha(r.hairDark, 0.35), 0.6));
      }
      return;

    case HairFringe.messy:
      final rng = r.rngFor(270 + r.cfg.hair);
      for (var i = 0; i < 9; i++) {
        final x = (rng.nextDouble() * 2 - 1) * fh * 0.9;
        final base = Offset(_cx + x, g.hairlineY(x.abs()) - 3);
        final ang = -math.pi / 2 + (x / fh) * 0.9 + (rng.nextDouble() - 0.5) * 0.9;
        final len = 8 + rng.nextDouble() * 9;
        final tip = base + Offset(math.cos(ang), math.sin(ang)) * len;
        final lockP = _lock(base, tip, 6.5 + rng.nextDouble() * 3, bend: (rng.nextDouble() - 0.5) * 0.5);
        canvas.drawPath(lockP, r.fill(_mix(r.hairColor, r.hairLight, 0.10 * rng.nextDouble())));
        if (r.detailed) canvas.drawPath(lockP, r.stroke(_alpha(r.hairDark, 0.35), 0.6));
      }
      return;
  }
}

// ---------------------------------------------------------- uzun yan tutamlar
void _paintSideLocks(Canvas canvas, _Rig r, _HairGeo g) {
  final s = g.s;
  if (!g.longSides) return;
  final endY = g.lockEndY;
  final jawY = math.min(r.chinY - 6, 138.0);
  final W = g.W;

  r.mirrored(canvas, (c, mir) {
    // Sol tutam (mirror ile sağı).
    final innerTop = Offset(_cx - g.fh * 0.985, g.hairlineY(g.fh * 0.985) + 1);
    final inner = <Offset>[
      innerTop,
      Offset(_cx - r.headX(98) + 1.0, 98),
      Offset(_cx - r.headX(120) + 0.5, 120),
      Offset(_cx - r.jawHalf * 0.96, jawY),
    ];
    if (endY > jawY + 6) {
      inner.add(Offset(_cx - (r.neckHalf + 7), _lerpD(jawY, endY, 0.4)));
      inner.add(Offset(_cx - (r.neckHalf + 9 + (s.length == HairLength.xlong ? 4 : 0)), endY));
    }
    final outerW = W + 6 + (s.texture == HairTexture.smooth ? 0 : 3);
    final outer = <Offset>[
      Offset(_cx - outerW, endY),
      Offset(_cx - outerW - 1, _lerpD(jawY, endY, 0.4).clamp(100.0, 200.0)),
      Offset(_cx - outerW, 100),
      Offset(_cx - W * 0.97, 74),
    ];
    if (s.length == HairLength.jaw) {
      // Bob: uç içe döner.
      outer[0] = Offset(_cx - outerW + 5, endY);
      inner.removeLast();
      inner.add(Offset(_cx - r.jawHalf * 0.78, endY - 1));
    }
    if (s.texture != HairTexture.smooth) {
      final amp = 1.5 + 2.5 * s.curl;
      for (var i = 1; i < inner.length; i++) {
        inner[i] = inner[i].translate(-math.sin(inner[i].dy * 0.11) * amp * 0.6, 0);
      }
      for (var i = 0; i < outer.length - 1; i++) {
        outer[i] = outer[i].translate(-math.sin(outer[i].dy * 0.11 + 1) * amp, 0);
      }
    }
    final path = _spline(inner);
    path.quadraticBezierTo(
      (inner.last.dx + outer.first.dx) / 2,
      endY + (s.length == HairLength.jaw ? 4 : 7) + (s.layered ? 5 : 0),
      outer.first.dx,
      outer.first.dy,
    );
    path.extendWithPath(_spline(outer), Offset.zero);
    path.close();

    final sideFlow = _flowDown(g, spread: 0.35);
    _paintMass(c, r, g, path, flow: sideFlow, strands: 320, len: 18, width: 0.95, seed: 300 + (mir ? 1 : 0), edge: 0.42, sheen: 0.22);
    _silkStreaks(c, r, g, path, seed: 310 + (mir ? 1 : 0));
  });
}

/// Uzun saçta boydan boya akan yumuşak parlak şeritler (ipeksi görünüm).
void _silkStreaks(Canvas c, _Rig r, _HairGeo g, Path region, {required int seed}) {
  if (!r.detailed) return;
  final b = region.getBounds();
  final rng = r.rngFor(seed);
  c.save();
  c.clipPath(region);
  for (var i = 0; i < 9; i++) {
    final x = b.left + rng.nextDouble() * b.width;
    final y0 = b.top + rng.nextDouble() * b.height * 0.5;
    final len = 24 + rng.nextDouble() * 40;
    final sway = (rng.nextDouble() - 0.5) * 7;
    final light = i % 3 != 0;
    c.drawPath(
      Path()
        ..moveTo(x, y0)
        ..cubicTo(x + sway, y0 + len * 0.35, x - sway, y0 + len * 0.7, x + sway * 0.4, y0 + len),
      r.stroke(_alpha(light ? r.hairShine : r.hairDark, light ? 0.13 : 0.16), 2.0 + rng.nextDouble() * 1.6, blur: 1.3),
    );
  }
  c.restore();
}

/// Saç çizgisinin kenarını yumuşatan ince tüyler.
void _paintSoftEdge(Canvas canvas, _Rig r, _HairGeo g) {
  if (!r.detailed) return;
  if (g.s.length == HairLength.buzz) return;
  final rng = r.rngFor(320 + r.cfg.hair);
  final fh = g.fh;
  final fr = r.fringe;
  // Perde/kâkül gibi alnı kapatan stillerde kenar zaten tanımlı.
  if (fr == HairFringe.blunt || fr == HairFringe.sweep || fr == HairFringe.sweepLong || fr == HairFringe.wave || fr == HairFringe.curtain) return;
  final n = 34;
  for (var i = 0; i < n; i++) {
    final x = (rng.nextDouble() * 2 - 1) * fh * 0.97;
    final y0 = g.hairlineY(x.abs()) - 0.6 + (fr == HairFringe.micro ? 4 : 0) + (fr == HairFringe.comb ? 5 : 0);
    final base = Offset(_cx + x, y0);
    final len = 1.6 + rng.nextDouble() * 2.6;
    final dir = _norm(Offset((rng.nextDouble() - 0.5) * 0.7 - x / fh * 0.3, 0.9));
    _taper(canvas, [base.translate(0, -1.5), base + dir * len * 0.5, base + dir * len], 0.6, 0.08, r.fill(_alpha(_mix(r.hairColor, r.hairDark, 0.15), 0.55 + 0.35 * rng.nextDouble())));
  }
}
