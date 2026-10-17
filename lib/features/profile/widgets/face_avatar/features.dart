part of '../face_avatar_painter.dart';

// ============================================================================
// KAŞ, GÖZ, BURUN, DUDAK
//
// Hiçbiri kontur çizgisiyle çizilmez: kaş tek tek kıllardan, göz ıslak göz
// küresi + lifli iris + gölge düşüren kapaktan, burun ve dudak ise yalnız
// ışık-gölgeyle (sırt ışığı, kanat çukuru, burun altı gölgesi, dudak hacmi)
// oluşur. Işık sol üstten gelir.
// ============================================================================

// -------------------------------------------------------------------- kaşlar
/// Sol kaşın (ekranda sol) geometrisi: iç uçtan (burun tarafı) dış uca
/// kuadratik bir orta hat ve boyunca değişen kalınlık.
class _BrowGeo {
  final Offset p0, p1, p2;
  final double th;
  final BrowSpec spec;

  _BrowGeo._(this.p0, this.p1, this.p2, this.th, this.spec);

  factory _BrowGeo(_Rig r) {
    final spec = r.brow;
    final th = (r.m.browThickness * spec.thickness).clamp(0.4, 2.2);
    final xIn = _cx - (r.eyeDx - r.eyeW * 0.92);
    final total = r.eyeW * 2.30 * spec.length;
    final xOut = xIn - total;
    final base = r.browBaseY;
    return _BrowGeo._(
      Offset(xIn, base + 2.0 - spec.tilt * 0.4),
      Offset(_lerpD(xIn, xOut, spec.peak), base - 3.6 * spec.arch),
      Offset(xOut, base + 3.4 + spec.tilt * 0.6),
      th.toDouble(),
      spec,
    );
  }

  Offset at(double t) {
    final u = 1 - t;
    return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
  }

  /// İç uçtan dış uca doğru teğet.
  Offset tangent(double t) => _norm((p1 - p0) * (2 * (1 - t)) + (p2 - p1) * (2 * t));

  /// Ekranda yukarı bakan normal.
  Offset up(double t) {
    final tg = tangent(t);
    final n = Offset(-tg.dy, tg.dx);
    return n.dy > 0 ? -n : n;
  }

  double half(double t) {
    final head = 1.0 - 0.18 * math.pow(t, 3.0);
    final tail = 1.0 - 0.80 * math.pow(t, 1.7) * spec.taper.clamp(0.4, 1.6) * 0.72;
    return 1.6 * th * head * tail.clamp(0.20, 1.0);
  }

  Path path() {
    const steps = 16;
    final upper = <Offset>[];
    final lower = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = at(t);
      final n = up(t);
      final h = half(t);
      upper.add(p + n * (h * 1.05));
      lower.add(p - n * (h * 0.95));
    }
    final path = Path()..moveTo(lower.first.dx, lower.first.dy);
    final inner = upper.first;
    path.quadraticBezierTo(inner.dx + 1.4, (inner.dy + lower.first.dy) / 2, inner.dx, inner.dy);
    for (final p in upper.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in lower.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }
}

void _paintBrows(Canvas canvas, _Rig r) {
  final geo = _BrowGeo(r);
  final spec = r.brow;
  final body = geo.path();
  final density = 1.0 - 0.45 * spec.sparse;
  r.mirrored(canvas, (c, mir) {
    if (!r.detailed) {
      c.drawPath(body, r.fill(_alpha(r.browColor, 0.80 * density)));
      return;
    }
    // Kılların altındaki deriye düşen yumuşak renk (kaşın "gölgesi"); iç
    // başta daha silik.
    c.save();
    c.clipPath(body);
    c.drawPath(
      body,
      Paint()
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.9)
        ..shader = ui.Gradient.linear(geo.p0, geo.p2, [
          _alpha(r.browColor, 0.22 * density),
          _alpha(r.browColor, 0.55 * density),
          _alpha(r.browColor, 0.40 * density),
        ], const [0.0, 0.4, 1.0]),
    );
    c.restore();
    // Kıllar: iç başta yukarı-dışa ve kısa, gövdede dışa yatık; alt
    // sıradakiler yukarı, üst sıradakiler aşağı eğilip orta hatta buluşur.
    final rng = r.rngFor(900 + r.cfg.brow + (mir ? 13 : 0));
    final n = ((95 + 45 * (geo.th - 1)) * density).round().clamp(30, 150);
    final dark = _tone(r.browColor, -0.22);
    final light = _tone(r.browColor, 0.14);
    for (var i = 0; i < n; i++) {
      final t = math.pow(rng.nextDouble(), 0.85).toDouble();
      final s = rng.nextDouble() * 2 - 1;
      final h = geo.half(t);
      final up = geo.up(t);
      final tg = geo.tangent(t);
      final root = geo.at(t) + up * (h * 0.95 * s);
      final head = 1 - ((t - 0.04) / 0.20).clamp(0.0, 1.0);
      final body = _norm(tg + up * (-0.42 * s + 0.10));
      final dir = _norm(_lerpO(body, _norm(up * 0.75 + tg * 0.65), head));
      final len = (2.0 + 1.5 * rng.nextDouble()) * (0.75 + 0.25 * geo.th) * (1 - 0.35 * t) * (1 - 0.35 * head);
      final tip = root + dir * len;
      final mid = root + dir * (len * 0.5) + up * 0.18;
      final col = i % 5 == 0 ? light : (i % 3 == 0 ? dark : r.browColor);
      r.strand(c, [root, mid, tip], 0.42 + 0.12 * rng.nextDouble(), _alpha(col, (0.55 + 0.35 * rng.nextDouble()) * (0.75 + 0.25 * density)));
    }
  });
}

// --------------------------------------------------------------------- gözler
void _paintEyes(Canvas canvas, _Rig r) {
  r.mirrored(canvas, (c, mir) {
    final center = Offset(_cx - r.eyeDx, _Rig.eyeY);
    final tilt = r.eye.tilt;
    c.save();
    if (tilt != 0) {
      c.translate(center.dx, center.dy);
      c.rotate(tilt * 0.036);
      c.translate(-center.dx, -center.dy);
    }
    _drawEye(c, r, center, mir);
    c.restore();
  });
}

double _lidCurve(EyeSpec spec) => 0.80 + 0.45 * spec.lidCurve;

/// Göz açıklığı (sol göz çerçevesi: dış köşe negatif x'te). Üst kapağın
/// tepesi burna yakın, alt kapağın en alçak yeri dış köşeye yakın (badem).
Path _eyeOpening(Offset o, double w, double h, EyeSpec spec) {
  final curve = _lidCurve(spec);
  final outer = Offset(o.dx - w, o.dy + h * 0.10);
  final inner = Offset(o.dx + w, o.dy + h * 0.26);
  final topY = o.dy - h * curve;
  final botY = o.dy + h * 0.84;
  return Path()
    ..moveTo(outer.dx, outer.dy)
    ..cubicTo(outer.dx + w * 0.20, topY + h * 0.10, o.dx - w * 0.30, topY, o.dx + w * 0.10, topY)
    ..cubicTo(o.dx + w * 0.55, topY, inner.dx - w * 0.16, o.dy - h * 0.46, inner.dx, inner.dy)
    ..cubicTo(inner.dx - w * 0.18, o.dy + h * 0.78, o.dx + w * 0.40, botY, o.dx - w * 0.10, botY)
    ..cubicTo(o.dx - w * 0.55, botY, outer.dx + w * 0.16, o.dy + h * 0.58, outer.dx, outer.dy)
    ..close();
}

/// Üst kapak çizgisi (dış köşeden iç köşeye).
List<Offset> _upperLidPts(Offset o, double w, double h, EyeSpec spec, {double lift = 0, double spread = 0}) {
  final curve = _lidCurve(spec);
  final outer = Offset(o.dx - w - spread, o.dy + h * 0.10 - lift * 0.2);
  final inner = Offset(o.dx + w + spread * 0.3, o.dy + h * 0.26 - lift * 0.3);
  final topY = o.dy - h * curve - lift;
  return [
    ..._cubicPts(outer, Offset(outer.dx + w * 0.20, topY + h * 0.10), Offset(o.dx - w * 0.30, topY), Offset(o.dx + w * 0.10, topY), 8),
    ..._cubicPts(Offset(o.dx + w * 0.10, topY), Offset(o.dx + w * 0.55, topY), Offset(inner.dx - w * 0.16, o.dy - h * 0.46 - lift * 0.6), inner, 8).skip(1),
  ];
}

/// Alt kapak çizgisi (iç köşeden dış köşeye).
List<Offset> _lowerLidPts(Offset o, double w, double h, {double drop = 0}) {
  final inner = Offset(o.dx + w, o.dy + h * 0.26);
  final outer = Offset(o.dx - w, o.dy + h * 0.10);
  final botY = o.dy + h * 0.84 + drop;
  return [
    ..._cubicPts(inner, Offset(inner.dx - w * 0.18, o.dy + h * 0.78 + drop), Offset(o.dx + w * 0.40, botY), Offset(o.dx - w * 0.10, botY), 8),
    ..._cubicPts(Offset(o.dx - w * 0.10, botY), Offset(o.dx - w * 0.55, botY), Offset(outer.dx + w * 0.16, o.dy + h * 0.58 + drop * 0.5), outer, 8).skip(1),
  ];
}

void _drawEye(Canvas canvas, _Rig r, Offset o, bool mir) {
  final w = r.eyeW;
  final h = r.eyeH;
  final spec = r.eye;
  final lash = r.lash;
  // Işık sol üstten: ayna gözde parlama sağa kayar (ekranda sol üste sabit kalsın).
  final lx = mir ? 1.0 : -1.0;
  final lidInk = _mix(r.lashColor, _Rig.ink, 0.45);
  final lidSkin = _mix(r.skin, r.skinShadow, 0.18);

  // ---- far (göz kapağı rengi): kapak üstünde yumuşak bulut
  if (lash.shadowStrength > 0) {
    final lid = _upperLidPts(o, w * 1.08, h, spec, lift: h * 1.5 + 1.5);
    final shadowPath = _spline([..._upperLidPts(o, w, h, spec), ...lid.reversed]);
    shadowPath.close();
    canvas.drawPath(shadowPath, r.soft(_alpha(lash.shadow, lash.shadowStrength * 0.75), 2.4));
  }

  // ---- kapalı (gülen) göz: yukarı kıvrık kirpik hattı
  if (spec.closed) {
    final arc = Path()
      ..moveTo(o.dx - w, o.dy + h * 0.55)
      ..quadraticBezierTo(o.dx, o.dy - h * 0.95, o.dx + w, o.dy + h * 0.55);
    r.glow(canvas, Offset(o.dx, o.dy - h * 0.6), w * 2.2, h * 2.2, _alpha(r.skinShadow, 0.35), 2.0);
    canvas.drawPath(arc, r.stroke(_alpha(lidInk, 0.9), 1.5, blur: 0.3));
    canvas.drawPath(arc.shift(const Offset(0, -1.6)), r.stroke(_alpha(r.skinLight, 0.30), 1.0, blur: 0.6));
    if (lash.length > 0) {
      final pts = _quadPts(Offset(o.dx - w, o.dy + h * 0.55), Offset(o.dx, o.dy - h * 0.95), Offset(o.dx + w, o.dy + h * 0.55), 10);
      for (var i = 1; i < 8; i++) {
        final p = pts[i];
        final len = 1.2 + 1.8 * lash.length * (1 - i / 10);
        r.strand(canvas, [p, p + Offset(-0.6, 0.9), p + Offset(-1.4, 1.2 + len)], 0.5, _alpha(lidInk, 0.85));
      }
    }
    return;
  }

  // ---- tam göz kırpma: kapalı, aşağı kıvrık kapak çizgisi
  if (r.blink >= 0.8) {
    final arc = Path()
      ..moveTo(o.dx - w, o.dy + h * 0.1)
      ..quadraticBezierTo(o.dx, o.dy + h * 1.0, o.dx + w, o.dy + h * 0.26);
    r.glow(canvas, Offset(o.dx, o.dy - h * 0.2), w * 2.2, h * 2.4, _alpha(r.skinShadow, 0.30), 2.0);
    canvas.drawPath(arc, r.stroke(_alpha(lidInk, 0.9), 1.4 + lash.liner * 0.5, blur: 0.3));
    final pts = _quadPts(Offset(o.dx - w, o.dy + h * 0.1), Offset(o.dx, o.dy + h * 1.0), Offset(o.dx + w, o.dy + h * 0.26), 10);
    for (var i = 1; i < 8; i++) {
      final p = pts[i];
      final len = 1.0 + 2.0 * lash.length * (1 - i / 10);
      r.strand(canvas, [p, p + Offset(-0.5, 1.0), p + Offset(-1.2, 1.4 + len)], 0.5, _alpha(lidInk, 0.85));
    }
    return;
  }

  final opening = _eyeOpening(o, w, h, spec);
  final curve = _lidCurve(spec);
  final topY = o.dy - h * curve;
  final openH = h * (curve + 0.84);

  // ---- üst kapak derisi ve kıvrımı (crease): yumuşak gölge oluğu
  if (!spec.monolid) {
    final lift = h * (spec.hooded ? 0.48 : 0.95) + 1.6;
    final crease = _upperLidPts(o, w * 0.94, h, spec, lift: lift, spread: 0.6);
    final creasePath = _spline(crease.sublist(1, crease.length - 1));
    canvas.drawPath(creasePath, r.stroke(_alpha(r.skinShadow, 0.85), 1.4, blur: 0.8));
    canvas.drawPath(creasePath.shift(const Offset(0, -1.2)), r.stroke(_alpha(r.skinLight, mir ? 0.12 : 0.30), 1.2, blur: 0.8));
    // Kapak derisinin üst kısmı ışık alır.
    r.glow(canvas, Offset(o.dx - w * 0.1, topY - lift * 0.45), w * 1.5, lift * 0.7, _alpha(r.skinLight, mir ? 0.10 : 0.25), 1.6);
  }

  // ---- göz küresi: saf beyaz değil, köşelere doğru gri-pembe gölgeli
  final irisR = w * 0.47;
  final coverTop = ((2 * irisR - openH) * 0.72).clamp(0.4, 3.2);
  final irisC = Offset(o.dx + w * 0.05, topY + irisR - coverTop);
  canvas.drawPath(
    opening,
    Paint()
      ..shader = ui.Gradient.radial(
        irisC,
        w * 1.15,
        [const Color(0xFFF6F0EA), const Color(0xFFEDE3DC), const Color(0xFFC9B6AE)],
        const [0.0, 0.55, 1.0],
      ),
  );
  canvas.save();
  canvas.clipPath(opening);

  // Göz pınarı (iç köşede pembe et).
  r.glow(canvas, Offset(o.dx + w * 0.90, o.dy + h * 0.24), w * 0.38, h * 0.80, _alpha(const Color(0xFFE29A96), 0.85), 0.6);

  // ---- iris
  final eyeColor = r.cfg.eyeColor;
  final limbus = _mix(eyeColor, const Color(0xFF0C0806), 0.62);
  canvas.drawCircle(
    irisC,
    irisR,
    Paint()
      ..shader = ui.Gradient.radial(
        irisC,
        irisR,
        [
          _mix(eyeColor, const Color(0xFF6A4A22), 0.35),
          _mix(eyeColor, Colors.white, 0.10),
          eyeColor,
          _mix(eyeColor, Colors.black, 0.30),
          limbus,
        ],
        const [0.30, 0.48, 0.70, 0.88, 1.0],
      ),
  );
  if (r.detailed) {
    // Işınsal iris lifleri.
    final rng = r.rngFor(611 + (mir ? 1 : 0));
    final fibLight = _alpha(_mix(eyeColor, Colors.white, 0.45), 0.35);
    final fibDark = _alpha(_mix(eyeColor, Colors.black, 0.45), 0.35);
    for (var i = 0; i < 44; i++) {
      final a = i / 44 * math.pi * 2 + rng.nextDouble() * 0.08;
      final d = Offset(math.cos(a), math.sin(a));
      final r0 = irisR * (0.38 + 0.08 * rng.nextDouble());
      final r1 = irisR * (0.70 + 0.24 * rng.nextDouble());
      canvas.drawLine(irisC + d * r0, irisC + d * r1, r.stroke(i.isEven ? fibLight : fibDark, 0.32));
    }
    // Limbus halkası (irisin koyu, yumuşak dış kenarı).
    canvas.drawCircle(irisC, irisR * 0.93, r.stroke(_alpha(limbus, 0.55), irisR * 0.16, blur: 0.35));
  }
  // Göz bebeği.
  canvas.drawCircle(irisC, irisR * 0.36, r.soft(const Color(0xFF0B0807), 0.25));

  // Üst kapağın göz küresine düşürdüğü gölge (gözü "ıslak küre" yapan şey).
  final lidPts = _upperLidPts(o, w, h, spec);
  final lidLine = Path()..addPolygon(lidPts, false);
  canvas.drawPath(lidLine.shift(const Offset(0, 1.8)), r.stroke(_alpha(const Color(0xFF3A2620), 0.45), 3.4, blur: 1.4));
  // Köşelerde göz küresi kararır.
  r.glow(canvas, Offset(o.dx - w * 0.95, o.dy + h * 0.1), w * 0.7, h * 2.0, _alpha(const Color(0xFF8A6E66), 0.35), 1.6);

  // Işık yansımaları: belirgin pencere yansıması + karşıda sönük ikincisi.
  final hl = irisC + Offset(irisR * 0.34 * lx, -irisR * 0.30);
  canvas.drawCircle(hl, irisR * 0.20, r.soft(_alpha(Colors.white, 0.95), 0.2));
  if (r.detailed) {
    canvas.drawCircle(irisC + Offset(-irisR * 0.38 * lx, irisR * 0.36), irisR * 0.16, r.soft(_alpha(Colors.white, 0.22), 0.6));
  }

  // Kısmi göz kırpma: üst kapak aşağı iner.
  if (r.blink > 0) {
    final lidBottom = o.dy - h * 1.1 + (h * 2.1) * r.blink;
    canvas.drawRect(Rect.fromLTRB(o.dx - w * 1.4, o.dy - h * 3, o.dx + w * 1.4, lidBottom), r.fill(lidSkin));
    canvas.drawLine(Offset(o.dx - w * 1.3, lidBottom), Offset(o.dx + w * 1.3, lidBottom), r.stroke(lidInk, 1.6));
  }

  // Kapaklı göz / tek kat: üstten sarkan cilt.
  if (spec.hooded || spec.monolid) {
    final drop = spec.hooded ? h * 0.55 : h * 0.32;
    final lid = Path()
      ..moveTo(o.dx - w * 1.2, o.dy - h * 0.4)
      ..quadraticBezierTo(o.dx, topY + drop * 1.6, o.dx + w * 1.2, o.dy - h * 0.15)
      ..lineTo(o.dx + w * 1.2, o.dy - h * 3)
      ..lineTo(o.dx - w * 1.2, o.dy - h * 3)
      ..close();
    canvas.drawPath(lid, r.fill(_mix(r.skin, r.skinShadow, spec.hooded ? 0.42 : 0.22)));
    if (spec.deepSet > 0) {
      canvas.drawPath(lid, r.fill(_alpha(r.skinShadow, 0.3 * spec.deepSet)));
    }
  }
  canvas.restore();

  // ---- alt kapak: ıslak kenar (açık pembe), altında yumuşak gölge
  final lower = _lowerLidPts(o, w, h);
  final lowerPath = _spline(lower.sublist(1, lower.length - 1));
  canvas.drawPath(lowerPath.shift(const Offset(0, 0.9)), r.stroke(_alpha(_mix(r.skinWarm, Colors.white, 0.25), 0.75), 0.9, blur: 0.3));
  canvas.drawPath(lowerPath.shift(const Offset(0, 1.9)), r.stroke(_alpha(r.skinShadow, 0.55), 1.0, blur: 0.6));

  // ---- üst kirpik hattı: koyu, kenarları yumuşak, dışa doğru kalınlaşan
  final lidW = 1.15 + 0.25 * lash.thickness * (lash.length > 0 ? 1 : 0.4) + lash.liner * 0.9;
  canvas.drawPath(
    _taperPath(lidPts, lidW * 1.15, lidW * 0.45, wMid: lidW * 1.05),
    r.soft(_alpha(lidInk, 0.92), 0.3),
  );
  // Dış köşedeki doğal kuyruk / eyeliner kanadı.
  if (lash.liner > 0 || lash.winged) {
    final tailLen = 1.6 + 1.8 * lash.liner + (lash.winged ? 3.6 : 0);
    final tailBase = lidPts.first;
    canvas.drawPath(
      _taperPath([tailBase.translate(1.6, -0.4), tailBase, tailBase + Offset(-tailLen, -tailLen * (lash.winged ? 0.75 : 0.45))], lidW * 0.9, 0.2),
      r.soft(lidInk, 0.25),
    );
  }

  // Alt eyeliner.
  if (lash.lower) {
    canvas.drawPath(
      lowerPath.shift(const Offset(0, 1.2)),
      r.stroke(_alpha(lidInk, lash.liner > 0 ? 0.70 : 0.40), 0.8 + lash.liner * 0.3, blur: 0.4),
    );
  }

  _drawLashes(canvas, r, o, lidPts, lower, lidInk);
}

/// Kirpikler: kapak boyunca çok sayıda ince, kıvrık tel; dış üçte birde
/// uzun ve yoğun, iç köşede kısa. Alt kirpikler seyrek ve soluk.
void _drawLashes(Canvas canvas, _Rig r, Offset o, List<Offset> lidPts, List<Offset> lowerPts, Color color) {
  final lash = r.lash;
  // "Yok" seçiliyken bile gerçek gözde kısa kirpik vardır; yalnız kısa ve seyrek.
  final length = math.max(lash.length, 0.18);
  final rng = r.rngFor(640);
  final count = r.detailed ? (16 + 14 * length).round() : 6;
  final m = (_spline(lidPts).computeMetrics().toList()).first;
  for (var i = 0; i < count; i++) {
    final t = (i + 0.3 * rng.nextDouble()) / count;
    final tg = m.getTangentForOffset(m.length * t)!;
    final root = tg.position;
    final dirT = _norm(tg.vector); // dış köşeden iç köşeye
    var up = Offset(dirT.dy, -dirT.dx);
    if (up.dy > 0) up = -up;
    // Dış köşeye yakın kirpikler uzun ve dışa yatık.
    final outerW = math.pow(1 - t, 1.4).toDouble();
    final len = (1.0 + 2.8 * length) * (0.45 + 0.75 * outerW) * (0.8 + 0.4 * rng.nextDouble());
    final dir = _norm(up * 1.0 + dirT * -(0.25 + 0.75 * outerW));
    final tip = root + dir * len + Offset(0, len * 0.18);
    final mid = root + dir * (len * 0.55) + up * 0.2;
    r.strand(canvas, [root, mid, tip], (0.42 + 0.14 * lash.thickness) * (r.detailed ? 1 : 1.4), _alpha(color, 0.75 + 0.2 * rng.nextDouble()));
  }
  if (r.detailed && (lash.lower || lash.length >= 0.8)) {
    final nLow = lash.lower ? 9 : 5;
    final ml = (_spline(lowerPts).computeMetrics().toList()).first;
    for (var i = 0; i < nLow; i++) {
      final t = 0.25 + 0.7 * (i + rng.nextDouble() * 0.5) / nLow;
      final tg = ml.getTangentForOffset(ml.length * t)!;
      final root = tg.position + const Offset(0, 1.0);
      final len = (0.8 + 0.9 * lash.length) * (0.6 + 0.6 * t);
      r.strand(canvas, [root, root + Offset(-0.4 * t, len * 0.5), root + Offset(-0.9 * t, len)], 0.30, _alpha(color, lash.lower ? 0.50 : 0.22));
    }
  }
}

// ---------------------------------------------------------------------- burun
void _paintNose(Canvas canvas, _Rig r) {
  final w = r.noseHalf;
  final spec = r.nose;
  final tipY = r.noseTipY;
  final baseY = r.noseBaseY;
  final bridgeTop = _Rig.eyeY - 2;
  final bw = 2.6 * spec.bridge;
  final blur = r.detailed ? 1.0 : 0.0;

  canvas.save();
  canvas.clipPath(r.head);

  // Sırtın iki yanı: gölge tarafı (sağ) belirgin, ışık tarafı (sol) silik.
  for (final side in [1.0, -1.0]) {
    final a = side > 0 ? 0.80 : 0.34;
    final shade = Path()
      ..moveTo(_cx + side * bw * 0.6, bridgeTop)
      ..cubicTo(_cx + side * bw * 1.6, bridgeTop + 8, _cx + side * (w * 0.55 + spec.bump * 1.0), tipY - 9, _cx + side * w * 0.80, tipY - 1.5)
      ..lineTo(_cx + side * w * 1.05, tipY - 3)
      ..cubicTo(_cx + side * w * 0.9, tipY - 10, _cx + side * bw * 2.6, bridgeTop + 9, _cx + side * bw * 2.4, bridgeTop)
      ..close();
    canvas.drawPath(shade, r.soft(_alpha(r.skinShadow, a), r.detailed ? 2.2 : 0));
  }
  // Burun sırtı ışığı.
  if (r.detailed) {
    canvas.drawPath(
      Path()
        ..moveTo(_cx - 0.6, _Rig.eyeY + 3)
        ..quadraticBezierTo(_cx - 1.4 - spec.bump * 0.6, (bridgeTop + tipY) / 2, _cx - 1.0, tipY - 3.5),
      r.stroke(_alpha(r.skinSpec, 0.40), 1.8, blur: 1.1),
    );
  }

  // Kemer (bump): sırtta ışık alan çıkıntı ve altında gölge.
  if (spec.bump > 0) {
    r.glow(canvas, Offset(_cx - 0.6, _Rig.eyeY + 10), 3.2, 5, _alpha(r.skinSpec, 0.45 * spec.bump), 1.0);
    r.glow(canvas, Offset(_cx + 1.4, _Rig.eyeY + 14), 3.4, 4, _alpha(r.skinShadow, 0.45 * spec.bump), 1.2);
  }

  // Burun ucu: top biçimli; altı gölgede, üstünde parlama, deri altı kızıllık.
  final tipR = 3.6 * spec.tip;
  r.glow(canvas, Offset(_cx, tipY - 0.5), tipR * 2.6, tipR * 2.0, _alpha(r.skinWarm, 0.30), 2.0);
  // Ucun sağ yanı gölgede (top biçimi), altı daha da koyu.
  r.glow(canvas, Offset(_cx + tipR * 0.75, tipY), tipR * 0.9, tipR * 1.5, _alpha(r.skinShadow, 0.45), 1.2);
  r.glow(canvas, Offset(_cx + 0.6, baseY - 0.4), w * 1.45, 3.4, _alpha(r.skinDeep, 0.55), r.detailed ? 1.0 : 0);

  // Kanatlar: yuvarlak tümsek; dış ve üst kenarında kanat oluğu gölgesi.
  r.mirrored(canvas, (c, mir) {
    final wc = Offset(_cx - w * 0.80, baseY - 2.2);
    final wr = w * 0.40 + 0.6;
    c.drawArc(
      Rect.fromCircle(center: wc, radius: wr + 0.4),
      math.pi * 0.45,
      math.pi * 1.25,
      false,
      r.stroke(_alpha(r.skinShadow, mir ? 0.95 : 0.70), 1.6, blur: 0.9),
    );
    r.glow(c, wc + const Offset(0.3, -0.6), wr * 1.2, wr, _alpha(r.skinLight, mir ? 0.10 : 0.35), 1.0);
    // Burun deliği: koyu, kenarı yumuşak, eğik.
    final visible = 1.0 + spec.upturn * 0.9;
    c.save();
    c.translate(_cx - w * 0.40, baseY - 0.5);
    c.rotate(-0.32);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 2.8 + 0.6 * spec.width, height: 1.25 * visible),
      r.soft(_alpha(_mix(r.skinDeep, _Rig.ink, 0.45), 0.88), r.detailed ? 0.4 : 0),
    );
    c.restore();
  });
  // Ucun parlaması (sol üst).
  r.glow(canvas, Offset(_cx - 1.4, tipY - tipR * 0.45), tipR * 1.1, tipR * 0.75, _alpha(r.skinSpec, 0.75), blur);

  // Burnun üst dudağa düşürdüğü gölge (ışık sol üstte → sağ alta düşer).
  r.glow(canvas, Offset(_cx + 1.6, baseY + 2.6), w * 1.7, 3.6, _alpha(r.skinShadow, 0.42), r.detailed ? 1.6 : 0);
  canvas.restore();
}

// ---------------------------------------------------------------------- ağız
void _paintMouth(Canvas canvas, _Rig r) {
  final lip = r.lip;
  final w = r.mouthHalf;
  final y = r.mouthY;
  final smile = r.m.smile;
  final lift = 2.6 * smile + 1.5 * lip.corner; // köşeler yukarı
  final upper = 3.0 * lip.upper * r.m.lipFullness;
  final lower = 4.4 * lip.lower * r.m.lipFullness;
  final bow = lip.bow;
  final open = math.max(0.0, smile - 0.60) * 13.0 + (lip.corner > 1.2 ? 2.2 : 0); // gülümsemede dişler

  final cornerL = Offset(_cx - w, y - lift);
  final cornerR = Offset(_cx + w, y - lift);
  final mid = y + 0.6 + lift * 0.25;

  // Ağız hattı (iki dudağın buluştuğu eğri), [dy] aşağı kaydırma.
  List<Offset> lineAt(double dy) => [
    ..._cubicPts(cornerL, Offset(_cx - w * 0.55, mid + dy), Offset(_cx - w * 0.20, mid + dy), Offset(_cx, mid + dy), 8),
    ..._cubicPts(Offset(_cx, mid + dy), Offset(_cx + w * 0.20, mid + dy), Offset(_cx + w * 0.55, mid + dy), cornerR, 8).skip(1),
  ];

  final topLine = lineAt(-open * 0.35);
  final botLine = lineAt(open);

  // Üst dudak: cupid's bow'lu.
  final upTop = y - upper - 0.4;
  final upperLip = Path()
    ..moveTo(cornerL.dx, cornerL.dy)
    ..cubicTo(_cx - w * 0.75, cornerL.dy - upper * 0.50, _cx - w * 0.45, upTop + 0.4, _cx - w * 0.20, upTop - 0.25 * bow)
    ..quadraticBezierTo(_cx - w * 0.08, upTop - 0.2 * bow, _cx, upTop + 0.75 * bow)
    ..quadraticBezierTo(_cx + w * 0.08, upTop - 0.2 * bow, _cx + w * 0.20, upTop - 0.25 * bow)
    ..cubicTo(_cx + w * 0.45, upTop + 0.4, _cx + w * 0.75, cornerR.dy - upper * 0.50, cornerR.dx, cornerR.dy);
  for (final p in topLine.reversed) {
    upperLip.lineTo(p.dx, p.dy);
  }
  upperLip.close();

  // Alt dudak.
  final lowBottom = y + lower + open + 0.4;
  final lowerLip = Path()..moveTo(botLine.first.dx, botLine.first.dy);
  for (final p in botLine.skip(1)) {
    lowerLip.lineTo(p.dx, p.dy);
  }
  lowerLip
    ..cubicTo(_cx + w * 0.70, lowBottom - lower * 0.22, _cx + w * 0.36, lowBottom, _cx, lowBottom)
    ..cubicTo(_cx - w * 0.36, lowBottom, _cx - w * 0.70, lowBottom - lower * 0.22, cornerL.dx, cornerL.dy)
    ..close();

  // Ağız içi + dişler (gülümserken).
  if (open > 0.8) {
    final inside = Path()..moveTo(topLine.first.dx, topLine.first.dy);
    for (final p in topLine.skip(1)) {
      inside.lineTo(p.dx, p.dy);
    }
    for (final p in botLine.reversed) {
      inside.lineTo(p.dx, p.dy);
    }
    inside.close();
    canvas.drawPath(inside, r.fill(const Color(0xFF3E1416)));
    canvas.save();
    canvas.clipPath(inside);
    // Dil.
    r.glow(canvas, Offset(_cx, mid + open * 1.05), w * 1.2, open * 0.9, const Color(0xFFB0545A), 1.0);
    // Üst dişler: kenarlara doğru gölgelenen kırık beyaz.
    final teethBottom = mid - open * 0.35 + open * 0.62;
    final teeth = Rect.fromLTRB(_cx - w * 0.92, mid - open - 2, _cx + w * 0.92, teethBottom);
    canvas.drawRRect(
      RRect.fromRectAndRadius(teeth, const Radius.circular(1.2)),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(_cx - w, 0),
          Offset(_cx + w, 0),
          const [Color(0xFF9E928A), Color(0xFFEDE7DE), Color(0xFFF5F0E8), Color(0xFFDCD3C9), Color(0xFF8E827A)],
          const [0.0, 0.28, 0.48, 0.72, 1.0],
        ),
    );
    if (r.detailed) {
      // Diş araları (yalnız ön dişler) ve üst dudağın dişlere gölgesi.
      for (final dx in [-0.62, -0.36, -0.12, 0.12, 0.36, 0.62]) {
        canvas.drawLine(Offset(_cx + w * dx, mid - open), Offset(_cx + w * dx * 1.02, teethBottom), r.stroke(_alpha(const Color(0xFF8A7E76), 0.35), 0.35));
      }
    }
    canvas.drawRect(Rect.fromLTRB(_cx - w, mid - open - 3, _cx + w, mid - open * 0.35 + 1.4), r.soft(_alpha(const Color(0xFF5A3A36), 0.45), 0.9));
    canvas.restore();
  }

  final upCol = _mix(r.lipBase, r.lipDark, 0.34);
  final edgeBlur = r.detailed ? 0.45 : 0.0;

  // Alt dudak: dolgun, üst kısmı ışık alır, alt kenarı gölgeye döner.
  final lb = lowerLip.getBounds();
  canvas.drawPath(
    lowerLip,
    Paint()
      ..maskFilter = edgeBlur > 0 ? MaskFilter.blur(BlurStyle.normal, edgeBlur) : null
      ..shader = ui.Gradient.linear(
        Offset(0, lb.top),
        Offset(0, lb.bottom),
        [_mix(r.lipBase, r.lipDark, 0.25), _mix(r.lipBase, r.lipLight, 0.18), r.lipBase, _mix(r.lipBase, r.lipDark, 0.30)],
        const [0.0, 0.35, 0.70, 1.0],
      ),
  );
  // Üst dudak: aşağı baktığı için koyu; üst kenarı (dudak sırtı) biraz açık.
  final ub = upperLip.getBounds();
  canvas.drawPath(
    upperLip,
    Paint()
      ..maskFilter = edgeBlur > 0 ? MaskFilter.blur(BlurStyle.normal, edgeBlur) : null
      ..shader = ui.Gradient.linear(
        Offset(0, ub.top),
        Offset(0, ub.bottom),
        [_mix(upCol, r.lipLight, 0.12), upCol, _mix(upCol, r.lipDark, 0.35)],
        const [0.0, 0.5, 1.0],
      ),
  );

  if (r.detailed) {
    canvas.save();
    canvas.clipPath(lowerLip);
    // Dikey dudak çizgileri (doku).
    final rng = r.rngFor(733);
    for (var i = 0; i < 14; i++) {
      final x = _cx + (rng.nextDouble() * 2 - 1) * w * 0.75;
      canvas.drawLine(Offset(x, y + 0.5), Offset(x + (x - _cx) * 0.04, lowBottom - 0.8), r.stroke(_alpha(r.lipDark, 0.12), 0.35));
    }
    // Alt dudak ışığı: geniş yumuşak + küçük nemli parlama.
    r.glow(canvas, Offset(_cx - w * 0.18, y + open + lower * 0.48), w * 0.80, lower * 0.55, _alpha(r.lipLight, 0.55), 1.2);
    r.glow(canvas, Offset(_cx - w * 0.22, y + open + lower * 0.42), w * 0.22, 0.9, _alpha(Colors.white, 0.45), 0.4);
    canvas.restore();
    // Üst dudak sırtının (vermilyon kenarı) ışığı.
    canvas.drawPath(
      Path()
        ..moveTo(_cx - w * 0.75, cornerL.dy - upper * 0.45 - 0.6)
        ..quadraticBezierTo(_cx - w * 0.40, upTop - 0.6, _cx - w * 0.20, upTop - 0.25 * bow - 0.7)
        ..quadraticBezierTo(_cx - w * 0.08, upTop - 0.2 * bow - 0.7, _cx, upTop + 0.75 * bow - 0.7),
      r.stroke(_alpha(r.skinLight, 0.40), 0.9, blur: 0.6),
    );
  }

  // Dudakların buluştuğu koyu hat: ortada ve köşelerde en koyu, kenarı yumuşak.
  final line = Path()..addPolygon(open > 0.8 ? topLine : lineAt(0), false);
  final lineCol = _mix(r.lipDark, _Rig.ink, 0.45);
  canvas.drawPath(line, r.stroke(_alpha(lineCol, 0.85), 1.0, blur: 0.4));
  if (r.detailed) {
    canvas.drawPath(line.shift(const Offset(0, 0.6)), r.stroke(_alpha(lineCol, 0.25), 1.6, blur: 0.9));
  }
  // Köşe çukurları.
  r.mirrored(canvas, (c, mir) {
    c.drawPath(
      Path()
        ..moveTo(_cx - w + 0.4, cornerL.dy + 0.2)
        ..quadraticBezierTo(_cx - w - 1.6, cornerL.dy - 0.4, _cx - w - 2.0, cornerL.dy - 1.6 - smile),
      r.stroke(_alpha(r.skinShadow, mir ? 0.85 : 0.65), 1.2, blur: 0.6),
    );
  });
}
