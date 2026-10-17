part of '../face_avatar_painter.dart';

// ============================================================================
// TEN: kafa, kulak, yüz hacmi, çil/ben, yaş çizgileri
//
// Yüz tek düz renk değil: ışık sol üstten gelir, sağ yan yumuşak bir geçişle
// gölgeye düşer, kenarlar hafifçe kararır (yuvarlak hacim), alın/elmacık/çene
// ucu ışık alır, şakak ve elmacık altı çukurlaşır. Kulak ve burun gibi ince
// deri bölgeleri biraz daha kızıldır. İnce bir gözenek dokusu düzlüğü kırar.
// ============================================================================

// -------------------------------------------------------------------- kulak
/// Sol kulak (aynası sağ kulak). Kapalı saç/uzun saç kulağı örter; yine de
/// altta çizilir.
Path _earPath(_Rig r) {
  final x0 = _cx - r.headX((r.earTop + r.earBottom) / 2) + 2.6;
  final top = r.earTop;
  final bottom = r.earBottom;
  final h = bottom - top;
  return Path()
    ..moveTo(x0 + 1.5, top + 1.5)
    ..cubicTo(x0 - 4, top - 2.4, x0 - 10.2, top + 0.8, x0 - 9.6, top + h * 0.34)
    ..cubicTo(x0 - 9.0, top + h * 0.58, x0 - 6.8, top + h * 0.72, x0 - 5.2, bottom - 4.0)
    ..cubicTo(x0 - 4.4, bottom + 0.6, x0 - 0.4, bottom + 1.4, x0 + 1.6, bottom - 2.6)
    ..close();
}

void _paintEars(Canvas canvas, _Rig r) {
  final ear = _earPath(r);
  final top = r.earTop;
  final h = r.earBottom - r.earTop;
  final x0 = _cx - r.headX((r.earTop + r.earBottom) / 2) + 2.6;
  final earSkin = _mix(r.skin, r.skinWarm, 0.30);
  r.mirrored(canvas, (c, mir) {
    c.drawPath(ear, r.fill(earSkin));
    c.save();
    c.clipPath(ear);
    // Kulak yüzün gerisinde: genel olarak biraz gölgede, başa bağlandığı
    // yer en koyu.
    c.drawPath(ear, r.fill(_alpha(r.skinShadow, mir ? 0.45 : 0.18)));
    r.rimShade(c, ear, _alpha(r.skinShadow, 0.55), width: 4, blur: 1.8);
    c.drawRect(Rect.fromLTRB(x0 - 1.5, top - 4, x0 + 4, top + h + 6), r.soft(_alpha(r.skinDeep, 0.35), 2.0));
    // Kulak çukuru (konka) ve kanal.
    r.glow(c, Offset(x0 - 3.6, top + h * 0.50), 5.4, h * 0.46, _alpha(r.skinDeep, 0.55), 1.3);
    r.glow(c, Offset(x0 - 2.4, top + h * 0.56), 2.0, 3.6, _alpha(r.skinDeep, 0.55), 0.8);
    // Dış kıvrım (heliks) üstünde ışık, iç kıvrım (antiheliks) sırtı.
    c.drawPath(
      Path()
        ..moveTo(x0 - 0.5, top + 0.4)
        ..cubicTo(x0 - 5.0, top - 0.6, x0 - 8.6, top + 2.6, x0 - 8.2, top + h * 0.40),
      r.stroke(_alpha(r.skinLight, mir ? 0.30 : 0.65), 1.3, blur: 0.6),
    );
    c.drawPath(
      Path()
        ..moveTo(x0 - 2.0, top + h * 0.18)
        ..cubicTo(x0 - 6.4, top + h * 0.20, x0 - 6.8, top + h * 0.52, x0 - 4.8, top + h * 0.72),
      r.stroke(_alpha(r.skinLight, mir ? 0.22 : 0.45), 1.0, blur: 0.5),
    );
    // Kulak memesi: dolgun, biraz açık.
    r.glow(c, Offset(x0 - 2.8, r.earBottom - 2.8), 4.2, 3.4, _alpha(r.skinWarm, 0.35), 1.2);
    c.restore();
    c.drawPath(ear, r.edge(r.skinLine, alpha: 0.45));
  });
}

// --------------------------------------------------------------------- kafa
void _paintHead(Canvas canvas, _Rig r) {
  final head = r.head;
  // Taban: ışık merkezinden kenarlara hafif kararan dolgu.
  canvas.drawPath(
    head,
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(_cx - 10, _Rig.eyeY - 16),
        96,
        [_mix(r.skin, r.skinLight, 0.30), r.skin, _mix(r.skin, r.skinShadow, 0.65)],
        const [0.0, 0.52, 1.0],
      ),
  );

  canvas.save();
  canvas.clipPath(head);
  // Sağ yan: yumuşak gölge geçişi (yüz bir küre gibi döner).
  r.celShade(canvas, head, _alpha(r.skinShadow, 0.80), offset: const Offset(-10, -2), blur: 3.2);
  // Kenar kararması.
  r.rimShade(canvas, head, _alpha(r.skinDeep, 0.20), width: 12, blur: 5);

  if (r.detailed) {
    final ex = r.eyeDx;
    // Şakak çukurları.
    r.mirrored(canvas, (c, mir) {
      r.glow(c, Offset(_cx - r.foreheadHalf + 4, r.browBaseY - 4), 11, 24, _alpha(r.skinShadow, mir ? 0.42 : 0.24), 5);
    });
    // Alın ışığı + yağlı parlama.
    r.glow(canvas, Offset(_cx - 9, r.browBaseY - 17), 44, 20, _alpha(r.skinLight, 0.55), 8);
    r.glow(canvas, Offset(_cx - 11, r.browBaseY - 15), 14, 6, _alpha(r.skinSpec, 0.40), 3.5);
    // Elmacık kemiği: üstünde ışık, altında çukur.
    r.mirrored(canvas, (c, mir) {
      r.glow(c, Offset(_cx - ex - 3, _Rig.eyeY + 12), 22, 9, _alpha(mir ? r.skinLight : r.skinSpec, mir ? 0.14 : 0.42), 4.2, rotate: -0.28);
      r.glow(c, Offset(_cx - r.cheekHalf * 0.72, r.noseBaseY + 8), 11, 28, _alpha(r.skinShadow, (mir ? 0.42 : 0.20) + 0.12 * r.age / 3), 6, rotate: 0.32);
    });
    // Çene ucu ışığı ve altında yumuşak gölge.
    r.glow(canvas, Offset(_cx - 3, r.chinY - 9), 16, 7, _alpha(r.skinLight, 0.50), 3.4);
    r.glow(canvas, Offset(_cx + 2, r.chinY - 1.5), 24, 5, _alpha(r.skinShadow, 0.35), 2.4);
    // Burun çevresi ve yanakta deri altı kızıllığı.
    r.glow(canvas, Offset(_cx, r.noseTipY - 1), 18, 12, _alpha(r.skinWarm, 0.22), 5);
  }
  // Yanak allığı / doğal kızarıklık.
  final blushA = 0.06 + 0.30 * r.detail.blush + 0.14 * r.detail.sunkissed;
  r.mirrored(canvas, (c, mir) {
    r.glow(c, Offset(_cx - r.cheekHalf * 0.54, _Rig.eyeY + 18), 22, 14, _alpha(r.blush, blushA), 6);
  });

  // Gözenek dokusu: düz dolguyu kıran çok ince, düşük opaklıklı noktalar.
  if (r.detailed) {
    final rng = r.rngFor(77);
    final b = head.getBounds();
    final dark = <Offset>[];
    final light = <Offset>[];
    for (var i = 0; i < 1800; i++) {
      final p = Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height);
      (i.isEven ? dark : light).add(p);
    }
    canvas.drawPoints(
      ui.PointMode.points,
      dark,
      Paint()
        ..strokeWidth = 0.55
        ..strokeCap = StrokeCap.round
        ..color = _alpha(r.skinDeep, 0.07),
    );
    canvas.drawPoints(
      ui.PointMode.points,
      light,
      Paint()
        ..strokeWidth = 0.5
        ..strokeCap = StrokeCap.round
        ..color = _alpha(r.skinLight, 0.08),
    );
  }
  canvas.restore();
}

/// Kafanın yumuşak kenarı: saçtan ve kulaktan sonra, yüz parçalarından önce.
void _paintHeadOutline(Canvas canvas, _Rig r) {
  canvas.drawPath(r.head, r.edge(r.skinDeep, alpha: 0.40));
}

// ------------------------------------------------------------- yüz gölgeleri
void _paintFaceShading(Canvas canvas, _Rig r) {
  canvas.save();
  canvas.clipPath(r.head);
  final deep = r.eye.deepSet;

  if (r.detailed) {
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      // Kaş kemiği ışığı.
      r.glow(c, Offset(ex - 1, r.browBaseY + 6), r.eyeW * 2.1, 5, _alpha(r.skinLight, mir ? 0.14 : 0.38), 2.6);
      // Göz çukuru: üst kapak üstü ve burun kökü tarafı.
      r.glow(c, Offset(ex, _Rig.eyeY - r.eyeH * 1.3), r.eyeW * 2.5, r.eyeH * 2.6 + deep * 3, _alpha(r.skinShadow, (mir ? 0.34 : 0.22) + 0.24 * deep), 3.4);
      r.glow(c, Offset(ex + r.eyeW * 1.05, _Rig.eyeY - r.eyeH * 0.3), r.eyeW * 0.9, r.eyeH * 3.0, _alpha(r.skinShadow, (mir ? 0.42 : 0.30) + 0.15 * deep), 2.6);
      // Göz altı: serin, ince gölge (gözyaşı oluğu) ve altında ışık.
      final bags = (r.detail.eyebags + 0.3 * r.age).clamp(0.0, 1.4);
      r.glow(c, Offset(ex + 1.2, _Rig.eyeY + r.eyeH * 1.75 + 1), r.eyeW * 1.7, 3.6 + bags * 1.5, _alpha(r.skinCool, 0.28 + 0.22 * bags), 2.0);
      r.glow(c, Offset(ex - 0.5, _Rig.eyeY + r.eyeH * 2.6 + 2), r.eyeW * 1.6, 3.6, _alpha(r.skinLight, mir ? 0.10 : 0.30), 2.2);
    });
  }

  // Burun-ağız (nazolabial) hattı: gülümsedikçe ve yaşlandıkça belirginleşir.
  final nl = 0.10 + 0.22 * r.m.smile.clamp(0.0, 1.0) + 0.08 * r.age;
  r.mirrored(canvas, (c, mir) {
    final fold = Path()
      ..moveTo(_cx - r.noseHalf * 1.25, r.noseBaseY - 2.5)
      ..cubicTo(_cx - r.noseHalf * 1.9, r.noseBaseY + 3, _cx - r.mouthHalf * 1.12, r.mouthY - 5, _cx - r.mouthHalf * 1.10, r.mouthY + 3);
    c.drawPath(fold, r.stroke(_alpha(r.skinShadow, nl * (mir ? 1.5 : 1.0)), 3.2, blur: 2.0));
    if (r.detailed) {
      c.drawPath(fold.shift(const Offset(-2.4, -0.4)), r.stroke(_alpha(r.skinLight, mir ? 0.08 : 0.20), 2.6, blur: 1.8));
    }
  });

  // Burun altı: üst dudak bölgesi aşağı baktığı için biraz gölgede; ortada
  // filtrum oluğu, iki yanında ışık alan sırtlar.
  final lipTop = r.mouthY - 3.0 * r.lip.upper * r.m.lipFullness;
  final gap = lipTop - r.noseBaseY;
  r.glow(canvas, Offset(_cx + 1.5, r.noseBaseY + gap * 0.55), r.mouthHalf * 2.0, gap + 2, _alpha(r.skinShadow, 0.22), 3.0);
  if (r.detailed && gap > 3) {
    r.glow(canvas, Offset(_cx + 0.3, r.noseBaseY + gap * 0.55), 3.0, gap * 0.9, _alpha(r.skinShadow, 0.40), 1.0);
    for (final sx in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(_cx + sx * 2.3, r.noseBaseY + 1.5),
        Offset(_cx + sx * 3.0, lipTop - 0.3),
        r.stroke(_alpha(r.skinLight, sx < 0 ? 0.45 : 0.18), 1.1, blur: 0.6),
      );
    }
  }

  // Dudak altı çukuru (çene ile alt dudak arası).
  final lipLow = r.mouthY + 5.0 * r.lip.lower * r.m.lipFullness;
  r.glow(canvas, Offset(_cx + 1.0, lipLow + 4.0), r.mouthHalf * 1.1, 4.2, _alpha(r.skinShadow, 0.65), 1.8);
  canvas.restore();
}

// ------------------------------------------------------- çil / ben / kırışık
void _paintFaceDetails(Canvas canvas, _Rig r) {
  final d = r.detail;
  final cw = r.cheekHalf;
  const eyeY = _Rig.eyeY;

  canvas.save();
  canvas.clipPath(r.head);

  // ---- çiller: burun sırtı ve elmacıklarda kümelenir, boyları ve tonları
  // farklı, kenarları yumuşak.
  if (d.freckles > 0) {
    final rng = r.rngFor(555);
    final dotColor = _mix(r.skin, const Color(0xFF8A4526), 0.42);
    final count = r.detailed ? (45 + 90 * d.freckles).round() : (10 + 18 * d.freckles).round();
    for (var i = 0; i < count; i++) {
      double x, y;
      if (i % 3 == 0) {
        x = _cx + (rng.nextDouble() - 0.5) * 13;
        y = eyeY + 8 + rng.nextDouble() * 10;
      } else {
        final side = rng.nextBool() ? -1.0 : 1.0;
        final t = rng.nextDouble();
        x = _cx + side * (8 + t * (cw * 0.62));
        y = eyeY + 11 + rng.nextDouble() * 13 - t * 3;
      }
      final rad = 0.22 + rng.nextDouble() * 0.40;
      canvas.drawCircle(Offset(x, y), rad, r.soft(_alpha(dotColor, 0.22 + rng.nextDouble() * 0.35), 0.18));
    }
  }

  // ---- benler
  void mole(double x, double y, double rad) {
    canvas.drawCircle(Offset(x, y), rad, r.soft(_alpha(const Color(0xFF3B2016), 0.85), 0.3));
    canvas.drawCircle(Offset(x - rad * 0.3, y - rad * 0.3), rad * 0.35, r.fill(_alpha(Colors.white, 0.18)));
  }

  if (d.moles & 1 != 0) mole(_cx - cw * 0.52, eyeY + 24, 1.1);
  if (d.moles & 2 != 0) mole(_cx + r.mouthHalf * 0.75, r.mouthY - 7, 0.95);
  if (d.moles & 4 != 0) mole(_cx + 6, r.chinY - 8, 1.0);
  if (d.moles & 8 != 0) mole(_cx + cw * 0.78, eyeY - 18, 1.0);

  // ---- gamze
  if (d.dimples) {
    r.mirrored(canvas, (c, mir) {
      final p = Path()
        ..moveTo(_cx - r.mouthHalf - 3.8, r.mouthY - 3)
        ..quadraticBezierTo(_cx - r.mouthHalf - 5.2, r.mouthY + 0.8, _cx - r.mouthHalf - 3.4, r.mouthY + 3.6);
      c.drawPath(p, r.stroke(_alpha(r.skinShadow, 0.75), 1.6, blur: 0.9));
      c.drawPath(p.shift(const Offset(-1.2, 0)), r.stroke(_alpha(r.skinLight, 0.25), 1.0, blur: 0.6));
    });
  }

  // ---- göz altı torbası: koyu kıvrım + altında ışık alan şişlik.
  final bags = d.eyebags + 0.35 * r.age;
  if (bags > 0) {
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      final p = Path()
        ..moveTo(ex - r.eyeW * 0.75, _Rig.eyeY + r.eyeH * 1.6 + 2.6)
        ..quadraticBezierTo(ex, _Rig.eyeY + r.eyeH * 1.6 + 5.8, ex + r.eyeW * 0.85, _Rig.eyeY + r.eyeH * 1.6 + 2.4);
      final a = bags.clamp(0.0, 1.0);
      c.drawPath(p, r.stroke(_alpha(r.skinShadow, 0.55 * a), 1.3, blur: 0.8));
      c.drawPath(p.shift(const Offset(0, 1.3)), r.stroke(_alpha(r.skinLight, 0.30 * a), 1.0, blur: 0.6));
    });
  }

  // ---- yaş çizgileri: her kırışık koyu bir oluk ve hemen altında ışık
  // alan kenardan oluşur (çizgi film çizgisi değil).
  if (r.age > 0) {
    final a = 0.22 + 0.10 * r.age;
    final line = r.stroke(_alpha(r.skinShadow, a + 0.15), 0.9, blur: 0.5);
    final lift = r.stroke(_alpha(r.skinLight, a * 0.9), 0.8, blur: 0.5);
    void crease(Canvas c, Path p, {Offset light = const Offset(0, 0.9)}) {
      c.drawPath(p, line);
      if (r.detailed) c.drawPath(p.shift(light), lift);
    }

    final n = 1 + r.age;
    for (var i = 0; i < n; i++) {
      final y = r.browBaseY - 11 - i * 4.6;
      final w = r.foreheadHalf * (0.46 - i * 0.04);
      crease(
        canvas,
        Path()
          ..moveTo(_cx - w, y + 0.8)
          ..quadraticBezierTo(_cx, y - 1.4, _cx + w, y + 0.8),
      );
    }
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      // Kaz ayakları.
      for (var i = 0; i < 1 + (r.age > 1 ? 1 : 0); i++) {
        crease(
          c,
          Path()
            ..moveTo(ex - r.eyeW - 2.6, _Rig.eyeY + 0.5 + i * 3.4)
            ..quadraticBezierTo(ex - r.eyeW - 5, _Rig.eyeY - 0.6 + i * 4.2, ex - r.eyeW - 7, _Rig.eyeY - 1 + i * 5.4),
          light: const Offset(0.6, 0.6),
        );
      }
      // Ağız köşesinden aşağı (marionet) çizgisi.
      if (r.age >= 2) {
        crease(
          c,
          Path()
            ..moveTo(_cx - r.mouthHalf - 1.5, r.mouthY + 3.5)
            ..quadraticBezierTo(_cx - r.mouthHalf - 2.6, r.mouthY + 7, _cx - r.mouthHalf - 2.2, r.mouthY + 11),
          light: const Offset(-0.8, 0),
        );
      }
    });
  }

  canvas.restore();
}
