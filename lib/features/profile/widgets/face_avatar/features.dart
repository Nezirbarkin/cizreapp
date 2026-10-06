part of '../face_avatar_painter.dart';

// -------------------------------------------------------------------- kaşlar
/// Sol kaşın (ekranda sol) gövdesi. Bitmoji kaşı: net kenarlı, iç ucu dolgun,
/// dışa doğru incelen tek parça.
Path _browPath(_Rig r) {
  final spec = r.brow;
  final th = (r.m.browThickness * spec.thickness).clamp(0.4, 2.2);
  final xIn = _cx - (r.eyeDx - r.eyeW * 0.92);
  final total = r.eyeW * 2.30 * spec.length;
  final xOut = xIn - total;
  final base = r.browBaseY;
  final arch = spec.arch;
  final tilt = spec.tilt;

  final p0 = Offset(xIn, base + 2.0 - tilt * 0.4);
  final p2 = Offset(xOut, base + 3.4 + tilt * 0.6);
  final p1 = Offset(_lerpD(xIn, xOut, spec.peak), base - 3.6 * arch);

  Offset centerAt(double t) {
    final u = 1 - t;
    return p0 * (u * u) + p1 * (2 * u * t) + p2 * (t * t);
  }

  Offset tangentAt(double t) => _norm((p1 - p0) * (2 * (1 - t)) + (p2 - p1) * (2 * t));

  double halfThick(double t) {
    final head = 1.0 - 0.18 * math.pow(t, 3.0);
    final tail = 1.0 - 0.80 * math.pow(t, 1.7) * spec.taper.clamp(0.4, 1.6) * 0.72;
    return 1.75 * th * head * tail.clamp(0.20, 1.0);
  }

  const steps = 16;
  final upper = <Offset>[];
  final lower = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final p = centerAt(t);
    final tg = tangentAt(t);
    final nrm = Offset(tg.dy, -tg.dx); // yukarı
    final h = halfThick(t);
    upper.add(p + nrm * (h * 1.1));
    lower.add(p - nrm * (h * 0.9));
  }
  // İç uç yuvarlatılmış (köşeli kesik değil).
  final path = Path()..moveTo(lower.first.dx, lower.first.dy);
  final inner = upper.first;
  path.quadraticBezierTo(inner.dx + 1.6, (inner.dy + lower.first.dy) / 2, inner.dx, inner.dy);
  for (final p in upper.skip(1)) {
    path.lineTo(p.dx, p.dy);
  }
  for (final p in lower.reversed) {
    path.lineTo(p.dx, p.dy);
  }
  path.close();
  return path;
}

void _paintBrows(Canvas canvas, _Rig r) {
  final spec = r.brow;
  final body = _browPath(r);
  r.mirrored(canvas, (c, mir) {
    final col = _alpha(r.browColor, 1.0 - 0.45 * spec.sparse);
    c.drawPath(body, r.fill(col));
    if (!r.detailed) return;
    // Alt kenarda hafif koyuluk + üstte birkaç kıl izi (doku).
    c.save();
    c.clipPath(body);
    c.drawPath(body.shift(const Offset(0, -1.2)), r.stroke(_alpha(_tone(r.browColor, -0.25), 0.6), 1.0));
    final b = body.getBounds();
    final rng = r.rngFor(900 + r.cfg.brow);
    final hairs = (14 * (1 - spec.sparse)).round() + 4;
    for (var i = 0; i < hairs; i++) {
      final x = b.right - rng.nextDouble() * b.width * 0.45;
      final y = b.top + rng.nextDouble() * b.height;
      c.drawLine(
        Offset(x, y + 1.8),
        Offset(x - 1.6 - rng.nextDouble(), y - 1.2),
        r.stroke(_alpha(i.isEven ? _tone(r.browColor, 0.18) : _tone(r.browColor, -0.3), 0.55), 0.5),
      );
    }
    c.restore();
    if (spec.sparse > 0.3) {
      // Seyrek kaş: gövdede ten rengi boşluklar.
      final rng2 = r.rngFor(950 + r.cfg.brow);
      c.save();
      c.clipPath(body);
      for (var i = 0; i < 6; i++) {
        final x = b.left + rng2.nextDouble() * b.width;
        c.drawLine(Offset(x, b.top), Offset(x + 1.2, b.bottom), r.stroke(_alpha(r.skin, 0.55), 0.8));
      }
      c.restore();
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

/// Göz açıklığı (sol göz çerçevesi: dış köşe negatif x'te). Üst kapak dolgun
/// yay, alt kapak daha düz.
Path _eyeOpening(Offset o, double w, double h, EyeSpec spec) {
  final curve = 0.80 + 0.45 * spec.lidCurve;
  final outer = Offset(o.dx - w, o.dy + h * 0.10);
  final inner = Offset(o.dx + w, o.dy + h * 0.22);
  final topY = o.dy - h * curve;
  final botY = o.dy + h * 0.86;
  return Path()
    ..moveTo(outer.dx, outer.dy)
    ..cubicTo(outer.dx + w * 0.18, topY + h * 0.05, o.dx - w * 0.30, topY, o.dx + w * 0.08, topY)
    ..cubicTo(o.dx + w * 0.55, topY, inner.dx - w * 0.12, o.dy - h * 0.50, inner.dx, inner.dy)
    ..cubicTo(inner.dx - w * 0.22, o.dy + h * 0.80, o.dx + w * 0.40, botY, o.dx - w * 0.05, botY)
    ..cubicTo(o.dx - w * 0.55, botY, outer.dx + w * 0.16, o.dy + h * 0.60, outer.dx, outer.dy)
    ..close();
}

/// Üst kapak çizgisi (dış köşeden iç köşeye).
List<Offset> _upperLidPts(Offset o, double w, double h, EyeSpec spec, {double lift = 0, double spread = 0}) {
  final curve = 0.80 + 0.45 * spec.lidCurve;
  final outer = Offset(o.dx - w - spread, o.dy + h * 0.10 - lift * 0.2);
  final inner = Offset(o.dx + w + spread * 0.3, o.dy + h * 0.22 - lift * 0.3);
  final topY = o.dy - h * curve - lift;
  return [
    ..._cubicPts(outer, Offset(outer.dx + w * 0.18, topY + h * 0.05), Offset(o.dx - w * 0.30, topY), Offset(o.dx + w * 0.08, topY), 8),
    ..._cubicPts(Offset(o.dx + w * 0.08, topY), Offset(o.dx + w * 0.55, topY), Offset(inner.dx - w * 0.12, o.dy - h * 0.50 - lift * 0.6), inner, 8).skip(1),
  ];
}

void _drawEye(Canvas canvas, _Rig r, Offset o, bool mir) {
  final w = r.eyeW;
  final h = r.eyeH;
  final spec = r.eye;
  final lash = r.lash;
  // Işık sol üstten: ayna gözde parlama sağa kayar (ekranda sol üste sabit kalsın).
  final lx = mir ? 1.0 : -1.0;
  final lidInk = _mix(r.lashColor, _Rig.ink, 0.5);

  // ---- far (göz kapağı rengi)
  if (lash.shadowStrength > 0) {
    final lid = _upperLidPts(o, w * 1.06, h, spec, lift: h * 1.3);
    final shadowPath = _spline([..._upperLidPts(o, w, h, spec), ...lid.reversed]);
    shadowPath.close();
    canvas.drawPath(shadowPath, r.soft(_alpha(lash.shadow, lash.shadowStrength * 0.9), 1.8));
  }

  // ---- kapalı (gülen) göz: yukarı kıvrık yay
  if (spec.closed) {
    final arc = Path()
      ..moveTo(o.dx - w, o.dy + h * 0.45)
      ..quadraticBezierTo(o.dx, o.dy - h * 1.15, o.dx + w, o.dy + h * 0.45);
    canvas.drawPath(arc, r.stroke(lidInk, 2.2));
    if (lash.length > 0) {
      for (var i = 0; i < 2; i++) {
        final base = Offset(o.dx - w * (0.75 - i * 0.28), o.dy - h * (0.05 + i * 0.25));
        _taper(canvas, [base, base + Offset(-1.6, -1.8), base + Offset(-3.2 - lash.length, -2.4 - lash.length)], 1.3, 0.2, r.fill(lidInk));
      }
    }
    return;
  }

  // ---- tam göz kırpma: kapalı, aşağı kıvrık kapak çizgisi
  if (r.blink >= 0.8) {
    final arc = Path()
      ..moveTo(o.dx - w, o.dy + h * 0.1)
      ..quadraticBezierTo(o.dx, o.dy + h * 1.0, o.dx + w, o.dy + h * 0.22);
    canvas.drawPath(arc, r.stroke(lidInk, 2.0 + lash.liner * 0.5));
    if (lash.length > 0.5) {
      for (var i = 0; i < 2; i++) {
        final base = Offset(o.dx - w * (0.85 - i * 0.3), o.dy + h * (0.25 + i * 0.22));
        _taper(canvas, [base, base + Offset(-1.6, 1.4), base + Offset(-3.0, 2.6 + lash.length)], 1.2, 0.2, r.fill(lidInk));
      }
    }
    return;
  }

  final opening = _eyeOpening(o, w, h, spec);

  // ---- üst kapak kıvrımı (crease)
  if (!spec.monolid) {
    final lift = h * (spec.hooded ? 0.42 : 0.80) + 1.2;
    final crease = _upperLidPts(o, w * 0.90, h, spec, lift: lift, spread: 0.4);
    canvas.drawPath(
      _spline(crease.sublist(1, crease.length - 2)),
      r.stroke(_alpha(r.skinLine, 0.55), r.lineW * 0.85),
    );
  }

  // ---- gözün beyazı
  canvas.drawPath(opening, r.fill(const Color(0xFFFFFDFA)));
  canvas.save();
  canvas.clipPath(opening);

  final irisR = math.min(h * 1.0, w * 0.60);
  final irisC = Offset(o.dx + w * 0.04, o.dy + h * 0.10);
  final eyeColor = r.cfg.eyeColor;

  // Ojo: altta açık, üstte koyu (kapak gölgesi), koyu dış halka.
  canvas.drawCircle(
    irisC,
    irisR,
    Paint()
      ..shader = ui.Gradient.linear(
        irisC.translate(0, -irisR),
        irisC.translate(0, irisR),
        [_mix(eyeColor, Colors.black, 0.35), eyeColor, _mix(eyeColor, Colors.white, 0.30)],
        const [0.0, 0.55, 1.0],
      ),
  );
  canvas.drawCircle(irisC, irisR - 0.45, r.stroke(_alpha(_mix(eyeColor, Colors.black, 0.6), 0.95), 0.9));
  // Göz bebeği.
  canvas.drawCircle(irisC, irisR * 0.46, r.fill(const Color(0xFF120C0A)));
  // Parlamalar: büyük net + küçük.
  canvas.drawCircle(irisC + Offset(irisR * 0.36 * lx, -irisR * 0.34), irisR * 0.30, r.fill(Colors.white));
  canvas.drawCircle(irisC + Offset(-irisR * 0.30 * lx, irisR * 0.38), irisR * 0.13, r.fill(_alpha(Colors.white, 0.85)));

  // Üst kapağın göze düşürdüğü gölge.
  final lidShade = Path()..addPolygon(_upperLidPts(o, w, h, spec), false);
  canvas.drawPath(lidShade.shift(const Offset(0, 1.6)), r.stroke(_alpha(const Color(0xFF6E5A55), 0.32), 2.6, blur: 0.9));

  // Kısmi göz kırpma: üst kapak aşağı iner.
  if (r.blink > 0) {
    final lidBottom = o.dy - h * 1.1 + (h * 2.1) * r.blink;
    canvas.drawRect(Rect.fromLTRB(o.dx - w * 1.4, o.dy - h * 3, o.dx + w * 1.4, lidBottom), r.fill(r.skin));
    canvas.drawLine(Offset(o.dx - w * 1.3, lidBottom), Offset(o.dx + w * 1.3, lidBottom), r.stroke(lidInk, 2.0));
  }

  // Kapaklı göz / tek kat: üstten sarkan cilt.
  if (spec.hooded || spec.monolid) {
    final drop = spec.hooded ? h * 0.50 : h * 0.30;
    final lid = Path()
      ..moveTo(o.dx - w * 1.2, o.dy - h * 0.5)
      ..quadraticBezierTo(o.dx, o.dy - h * 1.1 + drop * 1.6, o.dx + w * 1.2, o.dy - h * 0.25)
      ..lineTo(o.dx + w * 1.2, o.dy - h * 3)
      ..lineTo(o.dx - w * 1.2, o.dy - h * 3)
      ..close();
    canvas.drawPath(lid, r.fill(_mix(r.skin, r.skinShadow, spec.hooded ? 0.5 : 0.25)));
    if (spec.deepSet > 0) {
      canvas.drawPath(lid, r.fill(_alpha(r.skinShadow, 0.3 * spec.deepSet)));
    }
  }
  canvas.restore();

  // ---- alt kapak: kısa ince çizgi (iç ve dış köşeye ulaşmaz)
  canvas.drawPath(
    Path()
      ..moveTo(o.dx + w * 0.70, o.dy + h * 0.72)
      ..cubicTo(o.dx + w * 0.35, o.dy + h * 0.98, o.dx - w * 0.35, o.dy + h * 0.98, o.dx - w * 0.82, o.dy + h * 0.55),
    r.stroke(_alpha(r.skinLine, 0.45), r.lineW * 0.8),
  );

  // ---- üst kapak çizgisi (kirpik hattı): kalın, dış köşede küçük kıvrım.
  final lidW = 1.9 + 0.5 * lash.thickness * (lash.length > 0 ? 1 : 0.4) + lash.liner * 0.8;
  final lidPts = _upperLidPts(o, w, h, spec);
  canvas.drawPath(_taperPath(lidPts, lidW * 1.05, lidW * 0.55, wMid: lidW * 1.15), r.fill(lidInk));
  // Dış köşedeki doğal kuyruk (her gözde).
  final tailLen = 2.0 + 1.6 * lash.liner + (lash.winged ? 3.6 : 0);
  final tailBase = lidPts.first;
  canvas.drawPath(
    _taperPath([tailBase.translate(1.4, -0.4), tailBase, tailBase + Offset(-tailLen, -tailLen * (lash.winged ? 0.75 : 0.45))], lidW * 0.9, 0.2),
    r.fill(lidInk),
  );

  // Alt eyeliner.
  if (lash.lower) {
    canvas.drawPath(
      Path()
        ..moveTo(o.dx + w * 0.75, o.dy + h * 0.68)
        ..cubicTo(o.dx + w * 0.35, o.dy + h * 0.98, o.dx - w * 0.4, o.dy + h * 0.98, o.dx - w * 0.95, o.dy + h * 0.45),
      r.stroke(_alpha(lidInk, lash.liner > 0 ? 0.85 : 0.5), 0.9 + lash.liner * 0.3),
    );
  }

  _drawLashes(canvas, r, lidPts, lidInk);
}

/// Kirpikler: dış köşede birkaç belirgin, kıvrık kalın kirpik (Bitmoji tarzı).
void _drawLashes(Canvas canvas, _Rig r, List<Offset> lidPts, Color color) {
  final lash = r.lash;
  if (lash.length <= 0) return;
  final count = lash.length < 0.6 ? 2 : (lash.length < 1.2 ? 3 : 4);
  final paint = r.fill(color);
  for (var i = 0; i < count; i++) {
    // Dış köşeden içeri doğru, kapak boyunca.
    final idx = (i * 2 + 1).clamp(0, lidPts.length - 2);
    final root = lidPts[idx];
    final next = lidPts[idx + 1];
    final tg = _norm(next - root);
    final up = Offset(tg.dy, -tg.dx); // kapağa dik, yukarı
    final len = (1.6 + 2.6 * lash.length) * (1.0 - i * 0.16);
    final dir = _norm(up * 0.75 + tg * -0.65);
    final tip = root + dir * len + Offset(-len * 0.25, 0);
    final mid = root + dir * (len * 0.55);
    _taper(canvas, [root, mid, tip], 1.25 * lash.thickness, 0.15, paint);
  }
  if (lash.lower && r.detailed) {
    // Alt kirpik: üç küçük çizgi.
    final o = Offset(lidPts[lidPts.length ~/ 2].dx, _Rig.eyeY);
    for (var i = 0; i < 3; i++) {
      final x = o.dx - r.eyeW * (0.3 + i * 0.22);
      final y = _Rig.eyeY + r.eyeH * (0.92 - i * 0.08);
      _taper(canvas, [Offset(x, y), Offset(x - 0.6, y + 1.4 + 0.6 * lash.length)], 0.8, 0.15, r.fill(_alpha(color, 0.8)));
    }
  }
}

// ---------------------------------------------------------------------- burun
void _paintNose(Canvas canvas, _Rig r) {
  final w = r.noseHalf;
  final spec = r.nose;
  final tipY = r.noseTipY;
  final baseY = r.noseBaseY;
  final bridgeTop = _Rig.eyeY + 3;
  final bw = 2.4 * spec.bridge;

  // Sırt gölgesi: ışık soldan, sağ yan gölgede (tek parça cel şekil).
  final shade = Path()
    ..moveTo(_cx + bw * 0.7, bridgeTop)
    ..cubicTo(_cx + bw * 1.5, bridgeTop + 6, _cx + w * 0.55 + spec.bump * 1.2, tipY - 8, _cx + w * 0.78, tipY - 1.5)
    ..cubicTo(_cx + w * 1.15, tipY + 1, _cx + w * 1.05, baseY, _cx + w * 0.55, baseY + 0.6)
    ..lineTo(_cx + w * 0.30, baseY - 0.8)
    ..cubicTo(_cx + w * 0.55, tipY - 2, _cx + bw * 0.4, tipY - 9, _cx + bw * 0.1, bridgeTop + 2)
    ..close();
  canvas.drawPath(shade, r.soft(_alpha(r.skinShadow, 0.95), r.detailed ? 1.1 : 0));

  // Kemer (bump): sırtta küçük çıkıntı çizgisi.
  if (spec.bump > 0) {
    canvas.drawPath(
      Path()
        ..moveTo(_cx + bw * 0.9, _Rig.eyeY + 7)
        ..quadraticBezierTo(_cx + bw * 1.6, _Rig.eyeY + 10, _cx + bw * 1.0, _Rig.eyeY + 13),
      r.stroke(_alpha(r.skinLine, 0.5 * spec.bump), r.lineW * 0.8),
    );
  }

  // Burun ucu: alt kısmında yumuşak gölge, üstte parlama.
  final tipR = 3.6 * spec.tip;
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx, baseY + 0.4), width: w * 1.5, height: 2.6),
    r.soft(_alpha(r.skinShadow, 0.9), r.detailed ? 0.9 : 0),
  );
  if (r.detailed) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - 1.4, tipY - tipR * 0.3), width: tipR * 1.1, height: tipR * 0.75),
      r.soft(_alpha(r.skinLight, 0.85), 1.0),
    );
  }

  // Kanatlar ve delikler: iki yanda kısa kıvrık çizgi + küçük koyu delik.
  final visible = 1.0 + spec.upturn * 0.9;
  r.mirrored(canvas, (c, mir) {
    c.drawPath(
      Path()
        ..moveTo(_cx - w * 0.62, tipY - 2.6)
        ..cubicTo(_cx - w * 1.18, tipY - 2.2, _cx - w * 1.22, baseY - 0.4, _cx - w * 0.72, baseY + 0.2),
      r.stroke(_alpha(r.skinLine, mir ? 0.85 : 0.65), r.lineW * 0.95),
    );
    c.save();
    c.translate(_cx - w * 0.42, baseY - 0.4);
    c.rotate(-0.30);
    c.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 2.6 + 0.6 * spec.width, height: 1.15 * visible),
      r.fill(_alpha(_mix(r.skinDeep, _Rig.ink, 0.35), 0.85)),
    );
    c.restore();
  });
}

// ---------------------------------------------------------------------- ağız
void _paintMouth(Canvas canvas, _Rig r) {
  final lip = r.lip;
  final w = r.mouthHalf;
  final y = r.mouthY;
  final smile = r.m.smile;
  final lift = 3.0 * smile + 1.7 * lip.corner; // köşeler yukarı
  final upper = 2.6 * lip.upper * r.m.lipFullness;
  final lower = 4.2 * lip.lower * r.m.lipFullness;
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
    ..cubicTo(_cx - w * 0.75, cornerL.dy - upper * 0.55, _cx - w * 0.45, upTop + 0.4, _cx - w * 0.22, upTop - 0.25 * bow)
    ..quadraticBezierTo(_cx - w * 0.08, upTop - 0.2 * bow, _cx, upTop + 0.75 * bow)
    ..quadraticBezierTo(_cx + w * 0.08, upTop - 0.2 * bow, _cx + w * 0.22, upTop - 0.25 * bow)
    ..cubicTo(_cx + w * 0.45, upTop + 0.4, _cx + w * 0.75, cornerR.dy - upper * 0.55, cornerR.dx, cornerR.dy);
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
    ..cubicTo(_cx + w * 0.72, lowBottom - lower * 0.25, _cx + w * 0.36, lowBottom, _cx, lowBottom)
    ..cubicTo(_cx - w * 0.36, lowBottom, _cx - w * 0.72, lowBottom - lower * 0.25, cornerL.dx, cornerL.dy)
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
    canvas.drawPath(inside, r.fill(const Color(0xFF5A1E22)));
    canvas.save();
    canvas.clipPath(inside);
    // Dil.
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx, mid + open * 1.05), width: w * 1.1, height: open * 0.9),
      r.fill(const Color(0xFFC85A62)),
    );
    // Üst dişler: beyaz şerit.
    final teethBottom = mid - open * 0.35 + open * 0.62;
    canvas.drawRect(
      Rect.fromLTRB(_cx - w, mid - open - 2, _cx + w, teethBottom),
      r.fill(const Color(0xFFFFFFFF)),
    );
    canvas.drawLine(
      Offset(_cx - w, teethBottom),
      Offset(_cx + w, teethBottom),
      r.stroke(_alpha(const Color(0xFFB8AFA8), 0.9), 0.7),
    );
    canvas.restore();
  }

  // Dudak dolguları.
  canvas.drawPath(lowerLip, r.fill(r.lipBase));
  canvas.drawPath(upperLip, r.fill(_mix(r.lipBase, r.lipDark, 0.38)));
  // Alt dudak parlaması.
  if (r.detailed) {
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - w * 0.18, y + open + lower * 0.55), width: w * 0.62, height: 1.6),
      r.soft(_alpha(r.lipLight, 0.9), 0.8),
    );
  }
  // Dudak kenarı (yalnız alt dudağın altında hafif).
  canvas.drawPath(
    Path()
      ..moveTo(_cx - w * 0.55, lowBottom - lower * 0.12)
      ..quadraticBezierTo(_cx, lowBottom + 0.6, _cx + w * 0.55, lowBottom - lower * 0.12),
    r.stroke(_alpha(_mix(r.lipDark, r.skinLine, 0.5), 0.45), r.lineW * 0.8),
  );

  // Ağız hattı ve köşe çukurları.
  final line = Path()..addPolygon(open > 0.8 ? topLine : lineAt(0), false);
  canvas.drawPath(line, r.stroke(_mix(r.lipDark, _Rig.ink, 0.55), r.lineW * 1.1));
  r.mirrored(canvas, (c, mir) {
    c.drawPath(
      Path()
        ..moveTo(_cx - w - 0.2, cornerL.dy + 0.2)
        ..quadraticBezierTo(_cx - w - 1.8, cornerL.dy - 0.4, _cx - w - 2.2, cornerL.dy - 1.8 - smile),
      r.stroke(_alpha(r.skinLine, 0.6), r.lineW * 0.8),
    );
  });
}
