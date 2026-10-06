part of '../face_avatar_painter.dart';

// -------------------------------------------------------------------- kulak
/// Sol kulak (aynası sağ kulak). Kapalı saç/uzun saç kulağı örter; yine de
/// altta çizilir.
Path _earPath(_Rig r) {
  final x0 = _cx - r.headX((r.earTop + r.earBottom) / 2) + 2.2;
  final top = r.earTop;
  final bottom = r.earBottom;
  final h = bottom - top;
  return Path()
    ..moveTo(x0 + 1.5, top + 1.5)
    ..cubicTo(x0 - 4, top - 2.2, x0 - 10.5, top + 1.2, x0 - 9.6, top + h * 0.36)
    ..cubicTo(x0 - 9.2, top + h * 0.62, x0 - 6.4, bottom - 2.4, x0 - 2.2, bottom + 0.4)
    ..cubicTo(x0 + 0.4, bottom + 1.4, x0 + 2.2, bottom - 1.6, x0 + 2.0, bottom - 4)
    ..close();
}

void _paintEars(Canvas canvas, _Rig r) {
  final ear = _earPath(r);
  final top = r.earTop;
  final h = r.earBottom - r.earTop;
  final x0 = _cx - r.headX((r.earTop + r.earBottom) / 2) + 2.2;
  r.mirrored(canvas, (c, mir) {
    c.drawPath(ear, r.fill(r.skin));
    c.save();
    c.clipPath(ear);
    // İç kulak gölgesi ve kıvrım.
    c.drawOval(
      Rect.fromCenter(center: Offset(x0 - 3.2, top + h * 0.48), width: 6.4, height: h * 0.62),
      r.soft(_alpha(r.skinShadow, mir ? 1.0 : 0.85), 1.2),
    );
    c.restore();
    c.drawPath(
      Path()
        ..moveTo(x0 - 1.2, top + h * 0.20)
        ..cubicTo(x0 - 6.4, top + h * 0.18, x0 - 7.0, top + h * 0.55, x0 - 4.2, top + h * 0.74),
      r.stroke(_alpha(r.skinLine, 0.75), r.lineW * 0.9),
    );
    c.drawPath(ear, r.stroke(r.skinLine, r.lineW));
  });
}

// --------------------------------------------------------------------- kafa
void _paintHead(Canvas canvas, _Rig r) {
  final head = r.head;
  canvas.drawPath(head, r.fill(r.skin));

  canvas.save();
  canvas.clipPath(head);
  // Cel gölge: sağ yan ve çene altı.
  r.celShade(canvas, head, _alpha(r.skinShadow, 0.95), base: r.skin, offset: const Offset(-7, -4), blur: r.detailed ? 2.2 : 0);
  if (r.detailed) {
    // Alın ve elmacıkta yumuşak ışık.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(_cx - 10, 52), width: 46, height: 26),
      r.soft(_alpha(r.skinLight, 0.55), 9),
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(_cx - r.cheekHalf * 0.55, _Rig.eyeY + 13), width: 18, height: 9),
      r.soft(_alpha(r.skinLight, 0.42), 4),
    );
  }
  // Yanak allığı (Bitmoji'nin tatlı pembeliği).
  final blushA = 0.16 + 0.34 * r.detail.blush + 0.12 * r.detail.sunkissed;
  r.mirrored(canvas, (c, mir) {
    c.drawOval(
      Rect.fromCenter(
        center: Offset(_cx - r.cheekHalf * 0.56, _Rig.eyeY + 16.5),
        width: 17,
        height: 10,
      ),
      r.soft(_alpha(r.blush, blushA), r.detailed ? 4.5 : 0),
    );
  });
  canvas.restore();
}

/// Kafa konturu: saçtan ve kulaktan sonra değil, yüz parçalarından önce çizilir.
void _paintHeadOutline(Canvas canvas, _Rig r) {
  canvas.drawPath(r.head, r.stroke(r.skinLine, r.lineW));
}

// ------------------------------------------------------------- yüz gölgeleri
void _paintFaceShading(Canvas canvas, _Rig r) {
  canvas.save();
  canvas.clipPath(r.head);

  // Göz çukuru: kaşın altında, burun köküne doğru çok hafif gölge.
  if (r.detailed) {
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      c.drawOval(
        Rect.fromCenter(
          center: Offset(ex + 3, _Rig.eyeY - r.eyeH * 0.9),
          width: r.eyeW * 2.6,
          height: r.eyeH * 2.2 + r.eye.deepSet * 3,
        ),
        r.soft(_alpha(r.skinShadow, (mir ? 0.45 : 0.30) + 0.25 * r.eye.deepSet), 3.4),
      );
    });
  }

  // Dudak altı çukuru.
  final lipLow = r.mouthY + 5.0 * r.lip.lower * r.m.lipFullness;
  canvas.drawOval(
    Rect.fromCenter(center: Offset(_cx + 0.8, lipLow + 4.4), width: r.mouthHalf * 1.05, height: 3.6),
    r.soft(_alpha(r.skinShadow, 0.85), r.detailed ? 1.6 : 0),
  );
  canvas.restore();
}

// ------------------------------------------------------- çil / ben / kırışık
void _paintFaceDetails(Canvas canvas, _Rig r) {
  final d = r.detail;
  final cw = r.cheekHalf;
  const eyeY = _Rig.eyeY;

  canvas.save();
  canvas.clipPath(r.head);

  // ---- çiller: burun sırtı ve elmacıklarda kümelenir.
  if (d.freckles > 0) {
    final rng = r.rngFor(555);
    final dotColor = _mix(r.skin, const Color(0xFF8A4526), 0.50);
    final count = r.detailed ? (22 + 44 * d.freckles).round() : (10 + 18 * d.freckles).round();
    for (var i = 0; i < count; i++) {
      double x, y;
      if (i % 3 == 0) {
        x = _cx + (rng.nextDouble() - 0.5) * 12;
        y = eyeY + 6 + rng.nextDouble() * 9;
      } else {
        final side = rng.nextBool() ? -1.0 : 1.0;
        final t = rng.nextDouble();
        x = _cx + side * (8 + t * (cw * 0.62));
        y = eyeY + 10 + rng.nextDouble() * 12 - t * 3;
      }
      final rad = 0.45 + rng.nextDouble() * 0.5;
      canvas.drawCircle(Offset(x, y), rad, r.fill(_alpha(dotColor, 0.45 + rng.nextDouble() * 0.4)));
    }
  }

  // ---- benler
  void mole(double x, double y, double rad) {
    canvas.drawCircle(Offset(x, y), rad, r.fill(_alpha(const Color(0xFF3B2016), 0.9)));
  }

  if (d.moles & 1 != 0) mole(_cx - cw * 0.52, eyeY + 23, 1.2);
  if (d.moles & 2 != 0) mole(_cx + r.mouthHalf * 0.75, r.mouthY - 6.5, 1.0);
  if (d.moles & 4 != 0) mole(_cx + 6, r.chinY - 7, 1.1);
  if (d.moles & 8 != 0) mole(_cx + cw * 0.78, eyeY - 18, 1.05);

  // ---- gamze
  if (d.dimples) {
    r.mirrored(canvas, (c, mir) {
      c.drawPath(
        Path()
          ..moveTo(_cx - r.mouthHalf - 3.8, r.mouthY - 3)
          ..quadraticBezierTo(_cx - r.mouthHalf - 5.2, r.mouthY + 0.8, _cx - r.mouthHalf - 3.4, r.mouthY + 3.6),
        r.stroke(_alpha(r.skinLine, 0.55), r.lineW * 0.9),
      );
    });
  }

  // ---- göz altı torbası
  final bags = d.eyebags + 0.35 * r.age;
  if (bags > 0) {
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      c.drawPath(
        Path()
          ..moveTo(ex - r.eyeW * 0.75, _Rig.eyeY + r.eyeH + 2.4)
          ..quadraticBezierTo(ex, _Rig.eyeY + r.eyeH + 5.6, ex + r.eyeW * 0.8, _Rig.eyeY + r.eyeH + 2.6),
        r.stroke(_alpha(r.skinLine, 0.42 * bags.clamp(0.0, 1.0)), r.lineW * 0.85),
      );
    });
  }

  // ---- yaş çizgileri
  if (r.age > 0) {
    final line = r.stroke(_alpha(r.skinLine, 0.30 + 0.12 * r.age), r.lineW * 0.8);
    final n = 1 + r.age;
    for (var i = 0; i < n; i++) {
      final y = r.browBaseY - 12 - i * 5.0;
      final w = r.foreheadHalf * (0.46 - i * 0.04);
      canvas.drawPath(
        Path()
          ..moveTo(_cx - w, y + 0.8)
          ..quadraticBezierTo(_cx, y - 1.4, _cx + w, y + 0.8),
        line,
      );
    }
    r.mirrored(canvas, (c, mir) {
      final ex = _cx - r.eyeDx;
      // Kaz ayakları.
      for (var i = 0; i < 1 + (r.age > 1 ? 1 : 0); i++) {
        c.drawPath(
          Path()
            ..moveTo(ex - r.eyeW - 2.6, _Rig.eyeY + 0.5 + i * 3.4)
            ..quadraticBezierTo(ex - r.eyeW - 5, _Rig.eyeY - 0.6 + i * 4.2, ex - r.eyeW - 7, _Rig.eyeY - 1 + i * 5.4),
          line,
        );
      }
      // Burun-ağız hattı.
      c.drawPath(
        Path()
          ..moveTo(_cx - r.noseHalf * 1.35, r.noseBaseY - 1.5)
          ..cubicTo(
            _cx - r.noseHalf * 2.1,
            r.noseBaseY + 4,
            _cx - r.mouthHalf * 1.15,
            r.mouthY - 5,
            _cx - r.mouthHalf * 1.12,
            r.mouthY + 2.5,
          ),
        line,
      );
      if (r.age >= 2) {
        c.drawLine(
          Offset(_cx - r.mouthHalf - 1.5, r.mouthY + 3.5),
          Offset(_cx - r.mouthHalf - 2.6, r.mouthY + 9),
          line,
        );
      }
    });
  }

  canvas.restore();
}
