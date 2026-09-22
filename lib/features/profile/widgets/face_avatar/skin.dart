part of '../face_avatar_painter.dart';

// -------------------------------------------------------------------- kulak
void _paintEars(Canvas canvas, _Rig r) {
  // Kapalı saç/başörtüsü ve uzun saç kulağı örter; yine de çizilir (altta kalır).
  final cw = r.cheekHalf;
  r.mirrored(canvas, (c, mir) {
    final cx0 = _cx - cw + 0.6;
    const top = 85.0;
    const bottom = 110.0;
    final ear = Path()
      ..moveTo(cx0 + 4, top + 3)
      ..cubicTo(cx0 - 2, top - 3, cx0 - 8.5, top + 1.5, cx0 - 7.4, top + 9)
      ..cubicTo(cx0 - 7, top + 16, cx0 - 5.5, bottom - 3.5, cx0 - 1, bottom - 0.6)
      ..cubicTo(cx0 + 1.6, bottom + 0.8, cx0 + 3.6, bottom - 1, cx0 + 4.2, bottom - 4)
      ..close();
    c.drawPath(ear, r.fill(_mix(r.skin, r.skinShadow, 0.14)));
    if (!r.detailed) return;

    c.save();
    c.clipPath(ear);
    // Kulağın ortası kızarık, kenarı ışık alır.
    c.drawOval(
      Rect.fromCenter(center: Offset(cx0 - 1.5, top + 13), width: 8, height: 15),
      r.soft(_alpha(r.skinWarm, 0.55), 2.2),
    );
    // Helix/antihelix kıvrımı.
    c.drawPath(
      Path()
        ..moveTo(cx0 - 1, top + 5)
        ..cubicTo(cx0 - 6, top + 5, cx0 - 6.2, top + 14, cx0 - 4, top + 18),
      r.stroke(_alpha(r.skinDeep, 0.55), 0.9),
    );
    c.drawPath(
      Path()
        ..moveTo(cx0 - 6.4, top + 4.4)
        ..cubicTo(cx0 - 8.6, top + 10, cx0 - 6.4, top + 18, cx0 - 3.2, bottom - 3),
      r.stroke(_alpha(mir ? r.skinShadow : r.skinLight, 0.55), 0.9),
    );
    // Kulak çukuru (koncha).
    c.drawOval(
      Rect.fromCenter(center: Offset(cx0 - 0.4, top + 14.5), width: 3.6, height: 6.5),
      r.soft(_alpha(r.skinDeep, 0.52), 1.2),
    );
    c.restore();
  });
}

// --------------------------------------------------------------------- kafa
void _paintHead(Canvas canvas, _Rig r) {
  final head = r.head;
  canvas.drawPath(head, r.fill(r.skin));
  if (!r.detailed) return;

  final bounds = head.getBounds().inflate(8);
  final cw = r.cheekHalf;

  canvas.save();
  canvas.clipPath(head);

  // 1) Işık: sol üstten yumuşak, sağ tarafa doğru gölge.
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(_cx - 16, 66),
        88,
        [_alpha(r.skinLight, 0.85), _alpha(r.skinLight, 0.0)],
      ),
  );
  canvas.drawRect(
    bounds,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(_cx - cw, 0),
        Offset(_cx + cw, 0),
        [
          _alpha(r.skinShadow, 0.30),
          _alpha(r.skinShadow, 0.0),
          _alpha(r.skinShadow, 0.0),
          _alpha(r.skinShadow, 0.50),
        ],
        const [0.0, 0.20, 0.58, 1.0],
      ),
  );

  // 2) Kenar koyulaşması: yüze hacim verir.
  canvas.drawPath(head, r.stroke(_alpha(r.skinShadow, 0.62), 10, blur: 5));

  // 3) Çene altı koyu, alın üstü hafif gölge (saçın altı).
  canvas.drawRect(
    Rect.fromLTRB(_cx - cw - 8, r.chinY - 34, _cx + cw + 8, r.chinY + 4),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, r.chinY - 34),
        Offset(0, r.chinY + 2),
        [_alpha(r.skinShadow, 0.0), _alpha(r.skinShadow, 0.50)],
      ),
  );

  // 4) Alın, elmacık, çene vurguları.
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(_cx - 5, 57), width: 42, height: 20),
    r.soft(_alpha(r.skinLight, 0.42), 7),
  );
  r.mirrored(canvas, (c, mir) {
    c.drawOval(
      Rect.fromCenter(center: Offset(_cx - cw * 0.58, 101), width: 15, height: 9),
      r.soft(_alpha(r.skinLight, mir ? 0.16 : 0.34), 4.5),
    );
    // Şakak çukuru.
    c.drawOval(
      Rect.fromCenter(center: Offset(_cx - cw * 0.96, 70), width: 7, height: 17),
      r.soft(_alpha(r.skinShadow, mir ? 0.30 : 0.18), 3.6),
    );
    // Çene köşesi (gonion) yumuşak gölgesi.
    c.drawOval(
      Rect.fromCenter(center: Offset(_cx - r.jawHalf * 0.86, 122), width: 9, height: 20),
      r.soft(_alpha(r.skinDeep, mir ? 0.30 : 0.16), 4),
    );
  });
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx - 1, r.chinY - 6), width: 14, height: 7),
    r.soft(_alpha(r.skinLight, 0.34), 3.6),
  );

  // 5) Ten dokusu: gözenek benzeri ince noktalar.
  final rng = r.rngFor(31337);
  final dark = <Offset>[];
  final light = <Offset>[];
  for (var i = 0; i < 1100; i++) {
    final p = Offset(
      bounds.left + rng.nextDouble() * bounds.width,
      bounds.top + rng.nextDouble() * bounds.height,
    );
    (rng.nextBool() ? dark : light).add(p);
  }
  canvas.drawPoints(
    ui.PointMode.points,
    dark,
    Paint()
      ..strokeWidth = 0.55
      ..strokeCap = StrokeCap.round
      ..color = _alpha(r.skinDeep, 0.10),
  );
  canvas.drawPoints(
    ui.PointMode.points,
    light,
    Paint()
      ..strokeWidth = 0.55
      ..strokeCap = StrokeCap.round
      ..color = _alpha(r.skinLight, 0.16),
  );

  canvas.restore();
}

// ------------------------------------------------------------- yüz gölgeleri
void _paintFaceShading(Canvas canvas, _Rig r) {
  if (!r.detailed) return;
  final cw = r.cheekHalf;

  canvas.save();
  canvas.clipPath(r.head);

  r.mirrored(canvas, (c, mir) {
    final ex = _cx - r.eyeDx;
    // Göz çukuru: kaş altında ve burun köküne doğru yumuşak gölge.
    c.drawOval(
      Rect.fromCenter(
        center: Offset(ex + 1.2, _Rig.eyeY - 1.0),
        width: r.eyeW * 2.9,
        height: r.eyeH * 4.4 + r.eye.deepSet * 3,
      ),
      r.soft(_alpha(r.skinShadow, (mir ? 0.30 : 0.22) + 0.10 * r.eye.deepSet), 4.2),
    );
    // Burun kökünde iç gölge.
    c.drawOval(
      Rect.fromCenter(center: Offset(_cx - 5.4, _Rig.eyeY + 1), width: 5.5, height: 15),
      r.soft(_alpha(r.skinShadow, mir ? 0.34 : 0.20), 2.6),
    );
    // Alt göz kapağı hafif kabarık (ışık alır).
    c.drawOval(
      Rect.fromCenter(center: Offset(ex, _Rig.eyeY + r.eyeH + 4.4), width: r.eyeW * 2.0, height: 4.6),
      r.soft(_alpha(r.skinLight, mir ? 0.12 : 0.26), 2.4),
    );
    // Yanak allığı.
    final blushA = 0.13 + 0.30 * r.detail.blush + 0.10 * r.detail.sunkissed;
    c.drawOval(
      Rect.fromCenter(center: Offset(_cx - cw * 0.56, _Rig.eyeY + 17), width: 19, height: 12),
      r.soft(_alpha(r.blush, blushA), 6),
    );
    // Nazolabial (burun-ağız) hattı: yumuşak gölge.
    final nasolabial = Path()
      ..moveTo(_cx - r.noseHalf * 1.35, r.noseBaseY - 0.6)
      ..cubicTo(
        _cx - r.noseHalf * 1.9,
        r.noseBaseY + 5,
        _cx - r.mouthHalf * 1.02,
        r.mouthY - 5,
        _cx - r.mouthHalf * 0.98,
        r.mouthY + 2.6,
      );
    c.drawPath(nasolabial, r.stroke(_alpha(r.skinShadow, (mir ? 0.30 : 0.22) + 0.06 * r.age), 2.2, blur: 1.7));
  });

  // Dudak altı çukuru ve çene.
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx, r.mouthY + 10.8), width: 20, height: 5),
    r.soft(_alpha(r.skinShadow, 0.42), 2.6),
  );
  // Burun altı gölgesi.
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx + 0.6, r.noseBaseY + 2.6), width: r.noseHalf * 2.6, height: 4.4),
    r.soft(_alpha(r.skinDeep, 0.30), 2.3),
  );
  // Filtrum (üst dudak oluğu): iki açık çıkıntı, orta gölge.
  canvas.drawPath(
    Path()
      ..moveTo(_cx, r.noseBaseY + 2.4)
      ..lineTo(_cx, r.mouthY - 5.6),
    r.stroke(_alpha(r.skinShadow, 0.26), 2.0, blur: 1.2),
  );
  r.mirrored(canvas, (c, mir) {
    c.drawPath(
      Path()
        ..moveTo(_cx - 2.8, r.noseBaseY + 2.6)
        ..lineTo(_cx - 3.4, r.mouthY - 5.4),
      r.stroke(_alpha(r.skinLight, mir ? 0.10 : 0.28), 1.6, blur: 1.0),
    );
  });

  canvas.restore();
}

// ------------------------------------------------------- çil / ben / kırışık
void _paintFaceDetails(Canvas canvas, _Rig r) {
  final d = r.detail;
  final cw = r.cheekHalf;

  canvas.save();
  canvas.clipPath(r.head);

  // ---- çiller: burun sırtı ve elmacıklarda kümelenir.
  if (d.freckles > 0) {
    final rng = r.rngFor(555);
    final dotColor = _mix(r.skin, const Color(0xFF8A4A2A), 0.55);
    final count = r.detailed ? (26 + 60 * d.freckles).round() : (10 + 24 * d.freckles).round();
    for (var i = 0; i < count; i++) {
      // Yarısı elmacık (iki yana), yarısı burun köprüsü üzerinde.
      double x, y;
      if (i % 3 == 0) {
        x = _cx + (rng.nextDouble() - 0.5) * 13;
        y = _Rig.eyeY + 4 + rng.nextDouble() * 11;
      } else {
        final side = rng.nextBool() ? -1.0 : 1.0;
        final t = rng.nextDouble();
        x = _cx + side * (7 + t * (cw * 0.72));
        y = _Rig.eyeY + 9 + rng.nextDouble() * 15 - t * 3;
      }
      final rad = 0.35 + rng.nextDouble() * 0.55;
      canvas.drawCircle(Offset(x, y), rad, r.fill(_alpha(dotColor, 0.35 + rng.nextDouble() * 0.45)));
    }
  }

  // ---- benler
  void mole(double x, double y, double rad) {
    canvas.drawCircle(Offset(x, y), rad, r.fill(_alpha(const Color(0xFF3B2016), 0.86)));
    if (r.detailed) {
      canvas.drawCircle(Offset(x - rad * 0.3, y - rad * 0.3), rad * 0.4, r.fill(_alpha(Colors.white, 0.22)));
    }
  }

  if (d.moles & 1 != 0) mole(_cx - cw * 0.55, _Rig.eyeY + 22, 1.05);
  if (d.moles & 2 != 0) mole(_cx + r.mouthHalf * 0.7, r.mouthY - 7.5, 0.9);
  if (d.moles & 4 != 0) mole(_cx + 6, r.chinY - 8, 1.0);
  if (d.moles & 8 != 0) mole(_cx + cw * 0.8, 74, 0.95);

  // ---- gamze
  if (d.dimples && r.detailed) {
    r.mirrored(canvas, (c, mir) {
      c.drawPath(
        Path()
          ..moveTo(_cx - r.mouthHalf - 4, r.mouthY - 2.4)
          ..quadraticBezierTo(_cx - r.mouthHalf - 5.6, r.mouthY + 1.4, _cx - r.mouthHalf - 3.6, r.mouthY + 5),
        r.stroke(_alpha(r.skinDeep, 0.34), 1.5, blur: 0.9),
      );
    });
  }

  // ---- göz altı torbası
  final bags = d.eyebags + 0.30 * r.age;
  if (bags > 0 && r.detailed) {
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      c.drawPath(
        Path()
          ..moveTo(ex - r.eyeW * 0.9, _Rig.eyeY + r.eyeH + 3.2)
          ..quadraticBezierTo(ex, _Rig.eyeY + r.eyeH + 6.8, ex + r.eyeW * 0.9, _Rig.eyeY + r.eyeH + 3.6),
        r.stroke(_alpha(r.skinShadow, 0.34 * bags.clamp(0.0, 1.0)), 2.6, blur: 1.6),
      );
    });
  }

  // ---- yaş çizgileri
  if (r.age > 0 && r.detailed) {
    final line = r.stroke(_alpha(r.skinDeep, 0.13 + 0.08 * r.age), 0.9, blur: 0.5);
    // Alın çizgileri.
    final n = 1 + r.age;
    for (var i = 0; i < n; i++) {
      final y = 56 + i * 5.2;
      final w = r.foreheadHalf * (0.62 - i * 0.04);
      canvas.drawPath(
        Path()
          ..moveTo(_cx - w, y + 0.6)
          ..quadraticBezierTo(_cx, y - 1.6, _cx + w, y + 0.6),
        line,
      );
    }
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      // Kaz ayakları.
      for (var i = 0; i < 2 + (r.age > 1 ? 1 : 0); i++) {
        c.drawPath(
          Path()
            ..moveTo(ex - r.eyeW - 2.4, _Rig.eyeY - 1 + i * 3.2)
            ..quadraticBezierTo(ex - r.eyeW - 5.2, _Rig.eyeY - 2.4 + i * 4.4, ex - r.eyeW - 8, _Rig.eyeY - 3 + i * 5.6),
          line,
        );
      }
      // Kaşlar arası çatık çizgisi.
      c.drawLine(Offset(_cx - 2.6, r.browBaseY - 4), Offset(_cx - 2.4, r.browBaseY + 2), line);
      // Derin nazolabial.
      c.drawPath(
        Path()
          ..moveTo(_cx - r.noseHalf * 1.4, r.noseBaseY - 0.6)
          ..cubicTo(
            _cx - r.noseHalf * 2.1,
            r.noseBaseY + 5,
            _cx - r.mouthHalf * 1.05,
            r.mouthY - 5,
            _cx - r.mouthHalf * 1.0,
            r.mouthY + 3,
          ),
        r.stroke(_alpha(r.skinDeep, 0.16 + 0.06 * r.age), 1.0, blur: 0.6),
      );
      // Dudak kenarı çizgileri.
      if (r.age >= 2) {
        c.drawLine(
          Offset(_cx - r.mouthHalf - 1.6, r.mouthY + 2.6),
          Offset(_cx - r.mouthHalf - 2.4, r.mouthY + 8.6),
          line,
        );
      }
    });
  }

  canvas.restore();
}
