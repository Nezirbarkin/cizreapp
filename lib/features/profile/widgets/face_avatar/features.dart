part of '../face_avatar_painter.dart';

// -------------------------------------------------------------------- kaşlar
void _paintBrows(Canvas canvas, _Rig r) {
  final spec = r.brow;
  final th = r.m.browThickness * spec.thickness;

  r.mirrored(canvas, (c, mir) {
    final xIn = _cx - (r.eyeDx - r.eyeW * 0.86);
    final total = r.eyeW * 2.15 * spec.length;
    final xOut = xIn - total;
    final base = r.browBaseY;
    final arch = spec.arch;
    final tilt = spec.tilt;

    final yIn = base + 1.6 - tilt * 0.35;
    final yOut = base + 3.6 + tilt * 0.55;
    final peakT = spec.peak;
    final xPk = _lerpD(xIn, xOut, peakT);
    final yPk = base - 2.4 * arch;

    // Merkez hattı: iç uç → tepe → dış uç (kuadratik Bezier, örneklenir).
    Offset centerAt(double t) {
      final p0 = Offset(xIn, yIn);
      final p1 = Offset(xPk, yPk - 1.4 * arch);
      final p2 = Offset(xOut, yOut);
      final u = 1 - t;
      return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
    }

    Offset tangentAt(double t) {
      final p0 = Offset(xIn, yIn);
      final p1 = Offset(xPk, yPk - 1.4 * arch);
      final p2 = Offset(xOut, yOut);
      final d = (p1 - p0) * (2 * (1 - t)) + (p2 - p1) * (2 * t);
      final len = d.distance;
      return len == 0 ? const Offset(-1, 0) : d / len;
    }

    // Kalınlık profili: iç uç dolgun, dış uç incelir.
    double halfThick(double t) {
      final head = 1.0 - 0.35 * math.pow(t, 2.4);
      final tail = 1.0 - 0.72 * math.pow(t, 1.6) * spec.taper.clamp(0.4, 1.6) * 0.75;
      return (1.7 * th) * head * tail.clamp(0.16, 1.0);
    }

    // Gövde çokgeni.
    const steps = 14;
    final upper = <Offset>[];
    final lower = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final p = centerAt(t);
      final tg = tangentAt(t);
      final nrm = Offset(tg.dy, -tg.dx); // yukarı
      final h = halfThick(t);
      upper.add(p + nrm * (h * 1.05));
      lower.add(p - nrm * (h * 0.85));
    }
    final body = Path()..moveTo(upper.first.dx, upper.first.dy);
    for (final p in upper.skip(1)) {
      body.lineTo(p.dx, p.dy);
    }
    for (final p in lower.reversed) {
      body.lineTo(p.dx, p.dy);
    }
    body.close();

    if (!r.detailed) {
      c.drawPath(body, r.fill(_alpha(r.browColor, 0.92 - 0.4 * spec.sparse)));
      return;
    }

    // Yumuşak taban: kıl kıl çizimin altında doku yoğunluğunu verir.
    c.drawPath(body, r.soft(_alpha(r.browColor, 0.62 * (1 - spec.sparse * 0.8)), 0.8));

    final rng = r.rngFor(900 + r.cfg.brow);
    final count = (95 * th.clamp(0.5, 1.8) * (1 - spec.sparse * 0.55)).round();
    for (var i = 0; i < count; i++) {
      final t = rng.nextDouble();
      final p = centerAt(t);
      final tg = tangentAt(t);
      final nrm = Offset(tg.dy, -tg.dx);
      final h = halfThick(t);
      final u = (rng.nextDouble() * 2 - 1);
      final root = p + nrm * (u * h);

      // Kıl yönü: iç kısımda yukarı, dışa doğru kaşın seyrine paralel.
      final up = Offset(-0.25 * tg.dx * 0 + 0.0, -1.0);
      final blend = (1 - t).clamp(0.0, 1.0);
      var dir = tg * (0.85 + 0.5 * t) + up * (0.9 * blend * blend + 0.10) + nrm * (0.10 * u);
      final dl = dir.distance;
      dir = dl == 0 ? tg : dir / dl;

      final len = (2.2 + rng.nextDouble() * 2.0) * (0.75 + 0.25 * th);
      final mid = root + dir * (len * 0.5) + Offset(0, -0.35 * len * 0.18);
      final tip = root + dir * len + Offset(dir.dx * 0.0, 0.25);
      final shade = rng.nextDouble();
      final col = _mix(r.browColor, shade > 0.6 ? r.hairLight : r.hairDark, 0.14 + 0.32 * rng.nextDouble());
      _taper(
        c,
        [root, mid, tip],
        0.62 + 0.2 * th * rng.nextDouble(),
        0.10,
        r.fill(_alpha(col, 0.55 + 0.45 * rng.nextDouble())),
      );
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
      c.rotate(tilt * 0.034);
      c.translate(-center.dx, -center.dy);
    }
    _drawEye(c, r, center, mir);
    c.restore();
  });
}

/// Göz açıklığı (sol göz çerçevesi: dış köşe negatif x'te).
Path _eyeOpening(Offset o, double w, double h, EyeSpec spec) {
  final curve = 0.72 + 0.5 * spec.lidCurve;
  final outer = Offset(o.dx - w, o.dy + 0.5);
  final inner = Offset(o.dx + w, o.dy + 1.5);
  final top = Offset(o.dx + w * 0.10, o.dy - h * 1.02 * curve);
  final bottom = Offset(o.dx - w * 0.06, o.dy + h * 0.92);
  return Path()
    ..moveTo(outer.dx, outer.dy)
    ..cubicTo(outer.dx + w * 0.22, o.dy - h * 0.9 * curve, top.dx - w * 0.55, top.dy, top.dx, top.dy)
    ..cubicTo(top.dx + w * 0.55, top.dy, inner.dx - w * 0.28, o.dy - h * 0.62, inner.dx, inner.dy)
    ..cubicTo(inner.dx - w * 0.26, o.dy + h * 0.66, bottom.dx + w * 0.55, bottom.dy, bottom.dx, bottom.dy)
    ..cubicTo(bottom.dx - w * 0.6, bottom.dy, outer.dx + w * 0.3, o.dy + h * 0.62, outer.dx, outer.dy)
    ..close();
}

/// Sadece üst kapak çizgisi.
Path _upperLid(Offset o, double w, double h, EyeSpec spec, {double lift = 0, double spread = 0}) {
  final curve = 0.72 + 0.5 * spec.lidCurve;
  final outer = Offset(o.dx - w - spread, o.dy + 0.5);
  final inner = Offset(o.dx + w + spread * 0.4, o.dy + 1.5);
  final top = Offset(o.dx + w * 0.10, o.dy - h * 1.02 * curve - lift);
  return Path()
    ..moveTo(outer.dx, outer.dy)
    ..cubicTo(outer.dx + w * 0.22, o.dy - h * 0.9 * curve - lift * 0.9, top.dx - w * 0.55, top.dy, top.dx, top.dy)
    ..cubicTo(top.dx + w * 0.55, top.dy, inner.dx - w * 0.28, o.dy - h * 0.62 - lift * 0.6, inner.dx, inner.dy);
}

void _drawEye(Canvas canvas, _Rig r, Offset o, bool mir) {
  final w = r.eyeW;
  final h = r.eyeH;
  final spec = r.eye;
  final lash = r.lash;
  final skinLine = _mix(r.skinDeep, const Color(0xFF1B0F0A), 0.45);
  // Işık sol üstten: ayna gözde parlama sağa kayar (ekranda sol üste sabit kalsın).
  final lx = mir ? 1.0 : -1.0;

  // ---- far
  if (lash.shadowStrength > 0 && r.detailed) {
    final shadowPath = Path()
      ..moveTo(o.dx - w * 1.1, o.dy + 0.5)
      ..cubicTo(o.dx - w * 0.8, o.dy - h * 2.6, o.dx + w * 0.7, o.dy - h * 2.7, o.dx + w * 1.05, o.dy - h * 0.4)
      ..lineTo(o.dx + w, o.dy + 1.5)
      ..close();
    canvas.drawPath(shadowPath, r.soft(_alpha(lash.shadow, lash.shadowStrength * 0.85), 2.1));
  }

  // ---- tam göz kırpma: kapalı, aşağı kıvrık kapak çizgisi
  if (r.blink >= 0.8 && !spec.closed) {
    final lidSkin = _mix(r.skin, r.skinShadow, 0.10);
    canvas.drawPath(_eyeOpening(o, w * 1.06, h * 1.1, spec), r.fill(lidSkin));
    final arc = Path()
      ..moveTo(o.dx - w, o.dy + h * 0.15)
      ..quadraticBezierTo(o.dx, o.dy + h * 1.15, o.dx + w, o.dy + h * 0.2);
    canvas.drawPath(arc, r.stroke(_alpha(_mix(r.lashColor, const Color(0xFF15100E), 0.5), 0.96), 1.7 + lash.liner * 0.5));
    if (lash.length > 0) {
      for (var i = 0; i < 7; i++) {
        final t = (i + 0.5) / 7;
        final x = o.dx - w + w * 2 * t;
        final y = _lerpD(o.dy + h * 0.15, o.dy + h * 0.2, t) + h * 1.0 * math.sin(t * math.pi) * 0.78;
        final len = (1.6 + 1.6 * lash.length) * (1.05 - 0.5 * t);
        _taper(canvas, [Offset(x, y), Offset(x - 0.6 * (1 - t) - 0.2, y + len * 0.5), Offset(x - 1.6 * (1 - t), y + len)], 0.62 * lash.thickness, 0.08, r.fill(_alpha(r.lashColor, 0.92)));
      }
    }
    return;
  }

  // ---- kapalı (gülen) göz
  if (spec.closed) {
    final arc = Path()
      ..moveTo(o.dx - w, o.dy + h * 0.55)
      ..quadraticBezierTo(o.dx, o.dy - h * 1.7, o.dx + w, o.dy + h * 0.45);
    canvas.drawPath(arc, r.stroke(_alpha(skinLine, 0.96), 2.2));
    _drawLashes(canvas, r, o, w, h, closed: true);
    return;
  }

  final opening = _eyeOpening(o, w, h, spec);

  // ---- üst kapak kıvrımı (crease)
  if (r.detailed && !spec.monolid) {
    final crease = _upperLid(o, w * 0.92, h, spec, lift: h * (spec.hooded ? 0.55 : 0.95) + 0.6, spread: 0.2);
    canvas.drawPath(crease, r.stroke(_alpha(r.skinDeep, 0.46), 0.85, blur: 0.5));
    // Kıvrımın üstü hafif ışık, altı hafif gölge.
    canvas.drawPath(
      _upperLid(o, w * 0.9, h, spec, lift: h * 0.45),
      r.stroke(_alpha(r.skinShadow, 0.22), 2.2, blur: 1.6),
    );
  } else if (r.detailed && spec.monolid) {
    canvas.drawPath(
      _upperLid(o, w * 0.9, h, spec, lift: h * 0.5),
      r.stroke(_alpha(r.skinShadow, 0.16), 2.0, blur: 1.6),
    );
  }

  // ---- gözün beyazı
  canvas.drawPath(opening, r.fill(const Color(0xFFF3EFEA)));

  canvas.save();
  canvas.clipPath(opening);

  final irisR = math.min(h * 1.02, w * 0.56);
  final irisC = Offset(o.dx + w * 0.02, o.dy + h * 0.02);

  if (r.detailed) {
    // Beyazın köşelere doğru grileşmesi/kızarması.
    canvas.drawRect(
      Rect.fromCenter(center: o, width: w * 2.4, height: h * 3),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(o.dx - w, o.dy),
          Offset(o.dx + w, o.dy),
          [
            _alpha(const Color(0xFF9C7568), 0.34),
            _alpha(const Color(0xFF9C7568), 0.0),
            _alpha(const Color(0xFF9C7568), 0.0),
            _alpha(const Color(0xFFC46F73), 0.42),
          ],
          const [0.0, 0.26, 0.7, 1.0],
        ),
    );
  }

  final eyeColor = r.cfg.eyeColor;
  // Ojo (iris) — merkezden dışa koyulaşan gradyan.
  canvas.drawCircle(
    irisC,
    irisR,
    Paint()
      ..shader = ui.Gradient.radial(
        irisC.translate(irisR * 0.10 * lx * -1, irisR * 0.14),
        irisR * 1.05,
        [_mix(eyeColor, Colors.white, 0.34), eyeColor, _mix(eyeColor, Colors.black, 0.52)],
        const [0.0, 0.62, 1.0],
      ),
  );

  if (r.detailed) {
    // Ojo lifleri (radyal çizgiler) ve halka.
    final rng = r.rngFor(77 + r.cfg.eyeColor.toARGB32() % 1000);
    for (var i = 0; i < 44; i++) {
      final a = rng.nextDouble() * math.pi * 2;
      final r0 = irisR * (0.30 + rng.nextDouble() * 0.10);
      final r1 = irisR * (0.78 + rng.nextDouble() * 0.20);
      final dark = rng.nextBool();
      canvas.drawLine(
        irisC + Offset(math.cos(a), math.sin(a)) * r0,
        irisC + Offset(math.cos(a), math.sin(a)) * r1,
        r.stroke(
          _alpha(dark ? _mix(eyeColor, Colors.black, 0.5) : _mix(eyeColor, Colors.white, 0.45), 0.18 + 0.22 * rng.nextDouble()),
          0.32 + 0.3 * rng.nextDouble(),
        ),
      );
    }
    // İç halka (collarette).
    canvas.drawCircle(irisC, irisR * 0.5, r.stroke(_alpha(_mix(eyeColor, Colors.white, 0.4), 0.30), 0.55));
    // Dış kenar (limbal halka).
    canvas.drawCircle(irisC, irisR - 0.25, r.stroke(_alpha(_mix(eyeColor, Colors.black, 0.72), 0.85), 0.9));
  } else {
    canvas.drawCircle(irisC, irisR - 0.2, r.stroke(_alpha(_mix(eyeColor, Colors.black, 0.6), 0.85), 0.7));
  }

  // Göz bebeği.
  canvas.drawCircle(irisC, irisR * 0.42, r.fill(const Color(0xFF0E0A08)));

  // Parlamalar: büyük yumuşak + küçük keskin.
  canvas.drawCircle(
    irisC + Offset(-irisR * 0.34, -irisR * 0.38),
    irisR * 0.30,
    r.fill(_alpha(Colors.white, 0.95)),
  );
  canvas.drawCircle(
    irisC + Offset(irisR * 0.32, irisR * 0.34),
    irisR * 0.13,
    r.fill(_alpha(Colors.white, 0.55)),
  );
  if (r.detailed) {
    // Alt kenarda yansıyan ışık (iris altı açılır).
    canvas.drawPath(
      Path()
        ..addArc(Rect.fromCircle(center: irisC, radius: irisR * 0.8), math.pi * 0.15, math.pi * 0.7),
      r.stroke(_alpha(_mix(eyeColor, Colors.white, 0.6), 0.32), 1.0, blur: 0.6),
    );
  }

  // Üst kapağın gözbebeğine düşürdüğü gölge.
  canvas.drawRect(
    Rect.fromCenter(center: o, width: w * 3, height: h * 3.2),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(o.dx, o.dy - h * 1.05),
        Offset(o.dx, o.dy + h * 0.9),
        [_alpha(const Color(0xFF241510), r.detailed ? 0.62 : 0.4), _alpha(const Color(0xFF241510), 0.0), _alpha(const Color(0xFF241510), 0.10)],
        const [0.0, 0.42, 1.0],
      ),
  );

  // Yarım göz kırpma: üst kapak aşağı iner.
  if (r.blink > 0) {
    final lidBottom = o.dy - h * 1.1 + (h * 2.2) * r.blink;
    canvas.drawRect(
      Rect.fromLTRB(o.dx - w * 1.3, o.dy - h * 3, o.dx + w * 1.3, lidBottom),
      r.fill(_mix(r.skin, r.skinShadow, 0.10)),
    );
    canvas.drawLine(
      Offset(o.dx - w * 1.2, lidBottom),
      Offset(o.dx + w * 1.2, lidBottom),
      r.stroke(_alpha(_mix(r.lashColor, const Color(0xFF15100E), 0.5), 0.9), 1.5),
    );
  }

  // Kapaklı göz: üstten sarkan cilt.
  if (spec.hooded) {
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - w - 1, o.dy - h * 1.3)
        ..quadraticBezierTo(o.dx, o.dy - h * 0.05, o.dx + w + 1, o.dy - h * 0.95)
        ..lineTo(o.dx + w + 1, o.dy - h * 2.4)
        ..lineTo(o.dx - w - 1, o.dy - h * 2.4)
        ..close(),
      r.fill(_mix(r.skin, r.skinShadow, 0.42)),
    );
  }
  canvas.restore();

  // ---- alt kapak kenarı ve gözyaşı bezi
  if (r.detailed) {
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + w * 0.92, o.dy + h * 0.5)
        ..cubicTo(o.dx + w * 0.55, o.dy + h * 0.95, o.dx - w * 0.3, o.dy + h * 1.0, o.dx - w * 0.85, o.dy + h * 0.55),
      r.stroke(_alpha(r.skinDeep, 0.40), 0.7, blur: 0.3),
    );
    // Alt kapak nemi (ince açık çizgi).
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + w * 0.7, o.dy + h * 0.72)
        ..cubicTo(o.dx + w * 0.35, o.dy + h * 0.9, o.dx - w * 0.3, o.dy + h * 0.92, o.dx - w * 0.66, o.dy + h * 0.66),
      r.stroke(_alpha(const Color(0xFFFFFFFF), 0.30), 0.55),
    );
    // Gözyaşı bezi (iç köşede pembe).
    canvas.drawOval(
      Rect.fromCenter(center: Offset(o.dx + w * 0.92, o.dy + 1.1), width: 2.6, height: 2.2),
      r.soft(_alpha(const Color(0xFFD98A85), 0.85), 0.7),
    );
  }

  // ---- üst kapak çizgisi (kirpik hattı)
  final lidW = 1.5 + 0.9 * lash.thickness * (lash.length > 0 ? 1 : 0.6) + lash.liner * 0.7;
  final lidColor = lash.liner > 0
      ? const Color(0xFF15100E)
      : _mix(r.lashColor, const Color(0xFF15100E), 0.5);
  canvas.drawPath(_upperLid(o, w, h, spec, lift: -0.2), r.stroke(_alpha(lidColor, 0.96), lidW));

  // Kanatlı eyeliner.
  if (lash.winged || (lash.liner > 0.9 && lash.length > 1.0)) {
    final ow = lash.winged ? 1.0 : 0.6;
    canvas.drawPath(
      Path()
        ..moveTo(o.dx - w - 0.2, o.dy + 0.6)
        ..quadraticBezierTo(o.dx - w - 3.0 * ow, o.dy - 0.6, o.dx - w - 6.2 * ow, o.dy - 3.6 * ow - h * 0.3)
        ..quadraticBezierTo(o.dx - w - 2.0 * ow, o.dy - 3.2 * ow, o.dx - w * 0.55, o.dy - h * 0.86),
      r.fill(_alpha(const Color(0xFF15100E), 0.96)),
    );
  }

  // Alt eyeliner.
  if (lash.lower) {
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + w * 0.8, o.dy + h * 0.6)
        ..cubicTo(o.dx + w * 0.4, o.dy + h * 1.0, o.dx - w * 0.4, o.dy + h * 1.0, o.dx - w * 0.92, o.dy + h * 0.55),
      r.stroke(_alpha(const Color(0xFF15100E), lash.liner > 0 ? 0.6 : 0.30), 0.8),
    );
  }

  _drawLashes(canvas, r, o, w, h);
}

/// Kirpikler: üst kapak boyunca, dışa doğru kıvrılan ve incelen teller.
void _drawLashes(Canvas canvas, _Rig r, Offset o, double w, double h, {bool closed = false}) {
  final lash = r.lash;
  if (lash.length <= 0) return;

  final rng = r.rngFor(202 + r.cfg.lash);
  final n = r.detailed ? 11 : 5;
  final paint = r.fill(_alpha(r.lashColor, 0.95));

  for (var i = 0; i < n; i++) {
    final t = (i + 0.5) / n; // 0 dış köşe → 1 iç köşe
    final x = o.dx - w + (w * 2) * t;

    double lidY;
    if (closed) {
      final p = t;
      lidY = _lerpD(o.dy + h * 0.55, o.dy + h * 0.45, p) - 1.8 * h * math.sin(p * math.pi) * 0.95;
    } else {
      lidY = o.dy - h * (1.0 * (0.72 + 0.5 * r.eye.lidCurve)) * (0.35 + 0.65 * math.sin((t * 0.86 + 0.08) * math.pi));
    }

    // Dışta uzun ve dışa doğru, içte kısa ve yukarı.
    final len = (1.5 + 2.0 * lash.length) * (1.1 - 0.62 * t) * (0.88 + 0.24 * rng.nextDouble());
    final ang = _lerpD(-2.55, -1.75, t) + (rng.nextDouble() - 0.5) * 0.18; // radyan (yukarı-dışa)
    final dir = Offset(math.cos(ang), math.sin(ang));
    final curl = Offset(-dir.dy, dir.dx) * (0.7 * (1 - t) + 0.3);
    final root = Offset(x, lidY);
    final mid = root + dir * (len * 0.55) + curl * 0.15;
    final tip = root + dir * len + curl * 0.7;
    _taper(canvas, [root, mid, tip], 0.62 * lash.thickness, 0.08, paint);
  }

  if (lash.lower && !closed && r.detailed) {
    for (var i = 0; i < 6; i++) {
      final t = 0.18 + i * 0.13;
      final x = o.dx - w + (w * 2) * t;
      final y = o.dy + h * (0.86 + 0.1 * math.sin(t * math.pi));
      final len = 1.6 + 1.2 * lash.length;
      _taper(
        canvas,
        [Offset(x, y), Offset(x - 0.35, y + len * 0.55), Offset(x - 0.9, y + len)],
        0.6,
        0.1,
        r.fill(_alpha(r.lashColor, 0.78)),
      );
    }
  }
}

// ---------------------------------------------------------------------- burun
void _paintNose(Canvas canvas, _Rig r) {
  final w = r.noseHalf;
  final spec = r.nose;
  final tipY = r.noseTipY;
  final baseY = r.noseBaseY;
  final bridgeW = 2.6 * spec.bridge;

  if (r.detailed) {
    // Sırt: sol (ışıklı) tarafta ince parlak şerit, sağda gölge.
    r.mirrored(canvas, (c, mir) {
      final side = -1.0;
      // Sırt kenarı gölgesi (her iki yan), sağ taraf daha koyu.
      c.drawPath(
        Path()
          ..moveTo(_cx - bridgeW * 1.6, _Rig.eyeY + 4)
          ..cubicTo(_cx - bridgeW * 2.1, _Rig.eyeY + 10, _cx - w * 0.72, tipY - 6, _cx - w * 0.78, tipY + 1),
        r.stroke(_alpha(r.skinDeep, (mir ? 0.42 : 0.24) + 0.10 * r.skinDepth), 2.6, blur: 1.9),
      );
      // Kanat (ala) — burun deliklerini saran yumuşak hacim.
      final ala = Path()
        ..moveTo(_cx - w * 0.55, tipY - 1.6)
        ..cubicTo(_cx - w * 1.2, tipY - 1.2, _cx - w * 1.32, baseY - 1.6, _cx - w * 0.96, baseY + 0.6)
        ..cubicTo(_cx - w * 0.7, baseY + 2.0, _cx - w * 0.3, baseY + 1.2, _cx - 1.3, baseY + 0.4)
        ..cubicTo(_cx - w * 0.3, tipY + 2.2, _cx - w * 0.42, tipY, _cx - w * 0.55, tipY - 1.6)
        ..close();
      c.drawPath(ala, r.soft(_alpha(r.skinDeep, (mir ? 0.30 : 0.20) + 0.10 * r.skinDepth), 1.3));
      // Ala oluğu: ince koyu kavis.
      c.drawPath(
        Path()
          ..moveTo(_cx - w * 0.5, tipY - 2.6)
          ..cubicTo(_cx - w * 1.15, tipY - 2.4, _cx - w * 1.36, baseY - 2.4, _cx - w * 1.0, baseY),
        r.stroke(_alpha(r.skinDeep, (mir ? 0.62 : 0.46) + 0.1 * r.skinDepth), 1.1, blur: 0.5),
      );
      if (side < 0) {
        // Sırt parlaması yalnızca ışık tarafında.
        c.drawPath(
          Path()
            ..moveTo(_cx + bridgeW * 0.15, _Rig.eyeY + 6)
            ..cubicTo(_cx + bridgeW * 0.15, _Rig.eyeY + 12, _cx + 0.2, tipY - 6, _cx - 0.2, tipY - 2.4),
          r.stroke(_alpha(r.skinLight, mir ? 0.10 : 0.34), 2.0, blur: 1.4),
        );
      }
    });

    // Kemer (bump) — sırtta hafif çıkıntı gölgesi.
    if (spec.bump > 0) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx - 0.4, _Rig.eyeY + 9.5), width: 5.6, height: 5),
        r.soft(_alpha(r.skinLight, 0.22 * spec.bump), 2),
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(_cx + 1.8, _Rig.eyeY + 12.4), width: 3.6, height: 4.8),
        r.soft(_alpha(r.skinShadow, 0.34 * spec.bump), 1.8),
      );
    }

    // Burun ucu: yuvarlak hacim, parlak nokta.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - 0.4, tipY - 0.6), width: 8.4 * spec.tip, height: 6.4 * spec.tip),
      r.soft(_alpha(r.skinLight, 0.62 + 0.12 * r.skinDepth), 2.4),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx + 0.6, tipY + 0.8), width: 7 * spec.tip, height: 5.6 * spec.tip),
      r.soft(_alpha(r.skinWarm, 0.22), 2.2),
    );
    // Burun ucu ile üst arasında ince gölge (nasion/lobül ayrımı).
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx + 1.4, tipY - 3.6), width: 6, height: 3),
      r.soft(_alpha(r.skinShadow, 0.18), 1.6),
    );
  }

  // Delikler: çevre gölgeli koyu oval.
  final visible = 1.0 + spec.upturn * 0.9;
  r.mirrored(canvas, (c, mir) {
    c.save();
    c.translate(_cx - w * 0.52, baseY - 0.5);
    c.rotate(-0.42);
    final nostril = Rect.fromCenter(center: Offset.zero, width: 3.6 * spec.width * 0.9, height: 1.7 * visible);
    if (r.detailed) {
      c.drawOval(nostril.inflate(0.7), r.soft(_alpha(r.skinDeep, 0.35), 0.8));
    }
    c.drawOval(nostril, r.fill(_alpha(_mix(r.skinDeep, const Color(0xFF1A0C08), 0.5), mir ? 0.88 : 0.78)));
    c.restore();
  });
}

// ---------------------------------------------------------------------- ağız
void _paintMouth(Canvas canvas, _Rig r) {
  final lip = r.lip;
  final w = r.mouthHalf;
  final y = r.mouthY;
  final smile = r.m.smile;
  final lift = 2.7 * smile + 1.6 * lip.corner; // köşeler yukarı
  final upper = 3.7 * lip.upper * r.m.lipFullness;
  final lower = 5.6 * lip.lower * r.m.lipFullness;
  final bow = lip.bow;
  final open = math.max(0.0, smile - 0.62) * 6.4; // gülümsemede dişler

  final cornerL = Offset(_cx - w, y - lift);
  final cornerR = Offset(_cx + w, y - lift);
  final centerLine = y + 0.2 + open * 0.15;

  // Ağız hattı (iki dudağın buluştuğu eğri).
  Path mouthLine({double dy = 0}) => Path()
    ..moveTo(cornerL.dx, cornerL.dy + dy)
    ..cubicTo(_cx - w * 0.55, centerLine + 0.9 + dy, _cx - w * 0.18, centerLine + 0.4 + dy, _cx, centerLine + 0.2 + dy)
    ..cubicTo(_cx + w * 0.18, centerLine + 0.4 + dy, _cx + w * 0.55, centerLine + 0.9 + dy, cornerR.dx, cornerR.dy + dy);

  // Üst dudak: cupid's bow'lu.
  final upperTopY = y - upper - 0.7;
  final upperLip = Path()
    ..moveTo(cornerL.dx, cornerL.dy)
    ..cubicTo(_cx - w * 0.78, cornerL.dy - upper * 0.35, _cx - w * 0.55, upperTopY + 0.6, _cx - w * 0.25, upperTopY - 0.1 * bow)
    ..cubicTo(_cx - w * 0.12, upperTopY - 0.9 * bow, _cx - w * 0.06, upperTopY + 0.5, _cx, upperTopY + 0.9 * bow + 0.3)
    ..cubicTo(_cx + w * 0.06, upperTopY + 0.5, _cx + w * 0.12, upperTopY - 0.9 * bow, _cx + w * 0.25, upperTopY - 0.1 * bow)
    ..cubicTo(_cx + w * 0.55, upperTopY + 0.6, _cx + w * 0.78, cornerR.dy - upper * 0.35, cornerR.dx, cornerR.dy)
    ..cubicTo(_cx + w * 0.55, centerLine + 0.9 - open, _cx + w * 0.18, centerLine + 0.4 - open, _cx, centerLine + 0.2 - open)
    ..cubicTo(_cx - w * 0.18, centerLine + 0.4 - open, _cx - w * 0.55, centerLine + 0.9 - open, cornerL.dx, cornerL.dy)
    ..close();

  // Alt dudak: dolgun, altta yumuşak.
  final lowerBottom = y + lower + open * 0.9;
  final lowerLip = Path()
    ..moveTo(cornerL.dx, cornerL.dy)
    ..cubicTo(_cx - w * 0.55, centerLine + 0.9 + open, _cx - w * 0.18, centerLine + 0.4 + open, _cx, centerLine + 0.2 + open)
    ..cubicTo(_cx + w * 0.18, centerLine + 0.4 + open, _cx + w * 0.55, centerLine + 0.9 + open, cornerR.dx, cornerR.dy)
    ..cubicTo(_cx + w * 0.72, lowerBottom - lower * 0.15, _cx + w * 0.34, lowerBottom, _cx, lowerBottom)
    ..cubicTo(_cx - w * 0.34, lowerBottom, _cx - w * 0.72, lowerBottom - lower * 0.15, cornerL.dx, cornerL.dy)
    ..close();

  // Dişler (gülümserken).
  if (open > 0.35) {
    final mouthInside = Path()
      ..moveTo(cornerL.dx + 1.2, cornerL.dy)
      ..cubicTo(_cx - w * 0.5, centerLine + 0.9 - open, _cx + w * 0.5, centerLine + 0.9 - open, cornerR.dx - 1.2, cornerR.dy)
      ..cubicTo(_cx + w * 0.5, centerLine + 0.9 + open, _cx - w * 0.5, centerLine + 0.9 + open, cornerL.dx + 1.2, cornerL.dy)
      ..close();
    canvas.drawPath(mouthInside, r.fill(const Color(0xFF3B1517)));
    canvas.save();
    canvas.clipPath(mouthInside);
    canvas.drawRect(
      Rect.fromLTRB(_cx - w, centerLine - open - 1, _cx + w, centerLine + open * 0.55),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, centerLine - open),
          Offset(0, centerLine + open * 0.55),
          [const Color(0xFFF7F3EC), const Color(0xFFDDD5C8)],
        ),
    );
    if (r.detailed) {
      for (var i = -3; i <= 3; i++) {
        canvas.drawLine(
          Offset(_cx + i * w * 0.22, centerLine - open),
          Offset(_cx + i * w * 0.22, centerLine + open * 0.5),
          r.stroke(_alpha(const Color(0xFFB9AFA0), 0.5), 0.35),
        );
      }
      // Üst dişlerin altına gölge.
      canvas.drawRect(
        Rect.fromLTRB(_cx - w, centerLine - open - 1, _cx + w, centerLine - open + 1.6),
        r.soft(_alpha(const Color(0xFF3B1517), 0.5), 1),
      );
    }
    canvas.restore();
  }

  // Dudak dolguları.
  canvas.drawPath(lowerLip, r.fill(r.lipBase));
  canvas.drawPath(upperLip, r.fill(_mix(r.lipBase, r.lipDark, 0.34)));

  if (r.detailed) {
    // Alt dudak: üstten koyu → altta ışıklı parlama.
    canvas.save();
    canvas.clipPath(lowerLip);
    canvas.drawRect(
      Rect.fromLTRB(_cx - w - 2, y - 2, _cx + w + 2, lowerBottom + 2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(_cx, y),
          Offset(_cx, lowerBottom),
          [_alpha(r.lipDark, 0.55), _alpha(r.lipBase, 0.0), _alpha(r.lipLight, 0.30)],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - w * 0.16, y + lower * 0.62), width: w * 0.85, height: 2.4),
      r.soft(_alpha(Colors.white, 0.55), 1.5),
    );
    // Dudak dokusu: ince dikey çizgiler.
    final rng = r.rngFor(88);
    for (var i = 0; i < 14; i++) {
      final x = _cx + (rng.nextDouble() * 2 - 1) * w * 0.7;
      canvas.drawLine(
        Offset(x, y + 1.4),
        Offset(x + (rng.nextDouble() - 0.5) * 0.5, y + lower * (0.7 + rng.nextDouble() * 0.25)),
        r.stroke(_alpha(r.lipDark, 0.10), 0.35),
      );
    }
    canvas.restore();

    canvas.save();
    canvas.clipPath(upperLip);
    canvas.drawRect(
      Rect.fromLTRB(_cx - w - 2, upperTopY - 2, _cx + w + 2, y + 2),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(_cx, upperTopY),
          Offset(_cx, y),
          [_alpha(r.lipLight, 0.28), _alpha(r.lipDark, 0.0), _alpha(r.lipDark, 0.34)],
          const [0.0, 0.42, 1.0],
        ),
    );
    // Cupid's bow tepe parlamaları.
    r.mirrored(canvas, (c, mir) {
      c.drawOval(
        Rect.fromCenter(center: Offset(_cx - w * 0.26, upperTopY + 1.6), width: 4.5, height: 1.5),
        r.soft(_alpha(Colors.white, mir ? 0.10 : 0.30), 0.9),
      );
    });
    canvas.restore();

    // Vermilion sınırı: dudak dış hattı çok hafif.
    canvas.drawPath(
      upperLip,
      r.stroke(_alpha(_mix(r.lipBase, r.skinDeep, 0.5), 0.30), 0.55),
    );
    canvas.drawPath(
      lowerLip,
      r.stroke(_alpha(_mix(r.lipBase, r.skinDeep, 0.5), 0.20), 0.55),
    );
  }

  // Ağız hattı ve köşeler.
  canvas.drawPath(
    mouthLine(),
    r.stroke(_alpha(_mix(r.lipDark, const Color(0xFF1A0709), 0.45), 0.92), 1.15),
  );
  r.mirrored(canvas, (c, mir) {
    c.drawCircle(
      Offset(_cx - w - 0.5, cornerL.dy - 0.2),
      1.0,
      r.fill(_alpha(r.skinDeep, r.detailed ? 0.42 : 0.3)),
    );
  });
}
