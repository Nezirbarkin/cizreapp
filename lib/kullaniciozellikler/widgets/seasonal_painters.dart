// 2026-08-19'da eklenen yeni profil dekorasyonları: mevsim/doğa olayları
// (dolu, kiraz çiçeği, sonbahar yaprağı, meteor, yıldız, köpük), karınca
// yürüyüşü ve yeni avatar çerçeveleri.
//
// `creature_painters.dart` ile aynı sözleşmeyi kullanır — hiçbir görsel dosya
// (asset) yoktur, her şey `Canvas` üzerinde vektörel çizilir. İki çizer şekli
// vardır:
//   * yüzey çizerleri  : ({canvas, size, progress, primaryColor, secondaryColor})
//   * çerçeve çizerleri : ({canvas, center, radius, progress, primaryColor, secondaryColor})
//
// Yeni bir efekt eklerken üç ayrı switch'i (önizleme / avatar / kapak) elle
// güncellemek yerine yalnız `renderer_registry.dart` içine bir satır eklemek
// yeterlidir.

import 'dart:math' as math;

import 'package:flutter/material.dart';

// =============================================================================
// Yüzey çizerleri — fotoğrafın/kapağın üzerini kaplar
// =============================================================================

/// Dolu yağışı: hızlı düşen, zeminden seken buz taneleri.
void paintPhotoHailStorm({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 24,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = secondaryColor.withValues(alpha: 0.10),
  );
  final stonePaint = Paint()..color = Colors.white.withValues(alpha: 0.92);
  final glintPaint = Paint()..color = primaryColor.withValues(alpha: 0.45);

  for (var i = 0; i < count; i++) {
    final seed = i * 67.0;
    final x = ((seed * 31) % 997) / 997 * size.width;
    final speed = 1.6 + (i % 4) * 0.45;
    final phase = (progress * speed + ((seed * 17) % 101) / 101) % 1.0;
    final radius = 1.5 + (i % 3) * 0.9;

    // Düşüşün son %18'inde tane zeminden seker: yükseklik yarım sinüs.
    if (phase > 0.82) {
      final bounce = (phase - 0.82) / 0.18;
      final lift = math.sin(bounce * math.pi) * size.height * 0.12;
      canvas.drawCircle(
        Offset(x + bounce * 6, size.height - lift),
        radius * (1 - bounce * 0.45),
        stonePaint,
      );
      continue;
    }
    final y = (phase / 0.82) * size.height;
    canvas.drawCircle(Offset(x, y), radius, stonePaint);
    canvas.drawCircle(
      Offset(x - radius * 0.3, y - radius * 0.3),
      radius * 0.35,
      glintPaint,
    );
  }
}

/// Karınca yürüyüşü: fotoğrafın üzerinde sıra hâlinde ilerleyen karıncalar.
/// Şeritler dönüşümlü olarak ters yöne yürür.
void paintPhotoAntMarch({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 8,
}) {
  for (var lane = 0; lane < 3; lane++) {
    final laneY = size.height * (0.28 + lane * 0.22);
    final reversed = lane.isOdd;
    for (var i = 0; i < count; i++) {
      var t = (progress * (0.5 + lane * 0.12) + i / count) % 1.0;
      if (reversed) t = 1 - t;
      // Yürüyüş salınımı: her karınca kendi fazında hafifçe iner-kalkar.
      final bob =
          math.sin((progress * 12 + i * 1.7 + lane) * math.pi) *
          size.height *
          0.012;
      paintAnt(
        canvas: canvas,
        at: Offset(t * size.width, laneY + bob),
        scale: size.shortestSide * 0.055,
        facingLeft: reversed,
        gait: progress * 12 + i * 1.7,
        primaryColor: primaryColor,
        secondaryColor: secondaryColor,
      );
    }
  }
}

/// Tek bir karınca: üç gövde segmenti + altı bacak + iki anten.
/// Çerçeve çizeri de aynı gövdeyi kullandığı için ayrı fonksiyon.
void paintAnt({
  required Canvas canvas,
  required Offset at,
  required double scale,
  required bool facingLeft,
  required double gait,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final dir = facingLeft ? -1.0 : 1.0;
  final body = Paint()..color = primaryColor.withValues(alpha: 0.92);
  final limb = Paint()
    ..color = secondaryColor.withValues(alpha: 0.85)
    ..strokeWidth = math.max(0.6, scale * 0.14)
    ..strokeCap = StrokeCap.round;

  // Bacaklar: üç çift, yürüyüş fazına göre ileri-geri salınır.
  for (var i = 0; i < 3; i++) {
    final baseX = at.dx + dir * (i - 1) * scale * 0.55;
    final swing = math.sin(gait + i * 2.1) * scale * 0.42;
    canvas.drawLine(
      Offset(baseX, at.dy),
      Offset(baseX + swing, at.dy - scale * 0.72),
      limb,
    );
    canvas.drawLine(
      Offset(baseX, at.dy),
      Offset(baseX - swing, at.dy + scale * 0.72),
      limb,
    );
  }

  // Gövde: karın (arkada), göğüs (ortada), baş (önde).
  canvas.drawOval(
    Rect.fromCenter(
      center: at - Offset(dir * scale * 0.72, 0),
      width: scale * 1.05,
      height: scale * 0.80,
    ),
    body,
  );
  canvas.drawCircle(at, scale * 0.32, body);
  final head = at + Offset(dir * scale * 0.62, 0);
  canvas.drawCircle(head, scale * 0.38, body);

  for (var s = -1; s <= 1; s += 2) {
    canvas.drawLine(
      head,
      head +
          Offset(
            dir * scale * 0.62,
            s * scale * 0.52 + math.sin(gait) * scale * 0.1,
          ),
      limb,
    );
  }
}

/// Kiraz çiçeği yağmuru: dönerek süzülen taç yaprakları.
void paintPhotoCherryBlossom({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 18,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 73.0;
    final xBase = ((seed * 41) % 997) / 997 * size.width;
    final speed = 0.35 + (i % 5) * 0.11;
    final phase = (progress * speed + ((seed * 19) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 4 + seed) * size.width * 0.09;
    final at = Offset(xBase + sway, phase * size.height);
    final petal = size.shortestSide * (0.030 + (i % 3) * 0.008);
    final tint = Color.lerp(primaryColor, secondaryColor, (i % 4) / 3)!;

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(phase * math.pi * 5 + seed);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: petal * 2,
        height: petal,
      ),
      Paint()..color = tint.withValues(alpha: 0.80),
    );
    // Yaprak kıvrımını taklit eden iç parlaklık.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(petal * 0.25, 0),
        width: petal * 1.1,
        height: petal * 0.62,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.35),
    );
    canvas.restore();
  }
}

/// Sonbahar yaprakları: savrularak, genliği artan yaylarla düşen yapraklar.
void paintPhotoAutumnLeaves({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 14,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 83.0;
    final xBase = ((seed * 29) % 997) / 997 * size.width;
    final speed = 0.28 + (i % 4) * 0.13;
    final phase = (progress * speed + ((seed * 23) % 101) / 101) % 1.0;
    // Salınım genliği düşüşle birlikte artar.
    final sway =
        math.sin(phase * math.pi * 3 + seed) *
        size.width *
        (0.06 + phase * 0.10);
    final at = Offset(xBase + sway, phase * size.height);
    final leaf = size.shortestSide * (0.036 + (i % 3) * 0.010);
    final tint = Color.lerp(primaryColor, secondaryColor, (i % 5) / 4)!;

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(math.sin(phase * math.pi * 4 + seed) * 1.2);
    canvas.drawPath(
      Path()
        ..moveTo(0, -leaf)
        ..quadraticBezierTo(leaf * 0.85, -leaf * 0.1, 0, leaf)
        ..quadraticBezierTo(-leaf * 0.85, -leaf * 0.1, 0, -leaf)
        ..close(),
      Paint()..color = tint.withValues(alpha: 0.85),
    );
    canvas.drawLine(
      Offset(0, -leaf * 0.8),
      Offset(0, leaf * 0.8),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..strokeWidth = math.max(0.5, leaf * 0.09),
    );
    canvas.restore();
  }
}

/// Meteor yağmuru: çapraz inen, kuyruklu ışık izleri.
void paintPhotoMeteorShower({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 12,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = const Color(0xFF0B1020).withValues(alpha: 0.18),
  );
  for (var i = 0; i < count; i++) {
    final seed = i * 97.0;
    final startX =
        ((seed * 43) % 997) / 997 * size.width * 1.4 - size.width * 0.2;
    final speed = 1.1 + (i % 4) * 0.5;
    final phase = (progress * speed + ((seed * 11) % 101) / 101) % 1.0;
    final head = Offset(
      startX + phase * size.width * 0.55,
      phase * size.height * 1.15 - size.height * 0.1,
    );
    final tail = head - Offset(size.width * 0.16, size.height * 0.34);
    final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);

    canvas.drawLine(
      tail,
      head,
      Paint()
        ..shader =
            LinearGradient(
              colors: [
                secondaryColor.withValues(alpha: 0),
                primaryColor.withValues(alpha: 0.85 * fade),
              ],
            ).createShader(
              Rect.fromPoints(tail, head).inflate(1),
            )
        ..strokeWidth = 1.0 + (i % 3) * 0.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      head,
      1.6 + (i % 3) * 0.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
  }
}

/// Yıldız yağmuru: süzülürken sönüp yanan beş köşeli yıldızlar.
void paintPhotoStarRain({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 16,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 71.0;
    final xBase = ((seed * 47) % 997) / 997 * size.width;
    final speed = 0.5 + (i % 5) * 0.16;
    final phase = (progress * speed + ((seed * 29) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 3 + seed) * size.width * 0.05;
    final twinkle = 0.45 + 0.55 * math.sin((progress * 6 + i) * math.pi).abs();
    final at = Offset(xBase + sway, phase * size.height);
    final r = size.shortestSide * (0.022 + (i % 3) * 0.007);

    final path = Path();
    for (var j = 0; j < 10; j++) {
      final rr = j.isEven ? r : r * 0.42;
      final a = -math.pi / 2 + j * math.pi / 5 + phase * 2;
      final p = at + Offset(math.cos(a), math.sin(a)) * rr;
      if (j == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path..close(),
      Paint()
        ..color = Color.lerp(
          primaryColor,
          secondaryColor,
          (i % 3) / 2,
        )!.withValues(alpha: 0.85 * twinkle),
    );
  }
}

/// Sabun köpüğü: yüzeyde yükselen, yanardöner kabarcıklar.
void paintPhotoSoapFoam({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 18,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 61.0;
    final xBase = ((seed * 53) % 997) / 997 * size.width;
    final speed = 0.35 + (i % 5) * 0.14;
    final phase = (progress * speed + ((seed * 31) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 5 + seed) * size.width * 0.05;
    final at = Offset(xBase + sway, size.height * (1 - phase));
    final r = size.shortestSide * (0.030 + (i % 4) * 0.012);
    final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);

    canvas.drawCircle(
      at,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, r * 0.16)
        ..shader =
            SweepGradient(
              colors: [
                primaryColor.withValues(alpha: fade),
                secondaryColor.withValues(alpha: fade),
                Colors.white.withValues(alpha: fade),
                primaryColor.withValues(alpha: fade),
              ],
              transform: GradientRotation(phase * math.pi * 2),
            ).createShader(Rect.fromCircle(center: at, radius: r)),
    );
    canvas.drawCircle(
      at + Offset(-r * 0.34, -r * 0.34),
      r * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.55 * fade),
    );
  }
}

// =============================================================================
// Çerçeve çizerleri — avatar halkası üzerine
// =============================================================================

/// Karınca yolu: çerçeve halkası boyunca yürüyen karıncalar.
void paintAntTrailFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 10,
}) {
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.055
      ..color = secondaryColor.withValues(alpha: 0.28),
  );
  for (var i = 0; i < count; i++) {
    final angle = ((progress * 0.55 + i / count) % 1.0) * math.pi * 2;
    final at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    // Gövde teğet yönünde hizalanır.
    canvas.rotate(angle + math.pi / 2);
    paintAnt(
      canvas: canvas,
      at: Offset.zero,
      scale: radius * 0.16,
      facingLeft: false,
      gait: progress * 14 + i * 1.9,
      primaryColor: primaryColor,
      secondaryColor: secondaryColor,
    );
    canvas.restore();
  }
}

/// Dönen dişliler: çerçeveye yerleşmiş, ters yönlerde dönen çarklar.
void paintGearFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int gears = 6,
}) {
  for (var g = 0; g < gears; g++) {
    final angle = g / gears * math.pi * 2;
    final at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    final gearR = radius * (g.isEven ? 0.20 : 0.15);
    final spin = progress * math.pi * 2 * (g.isEven ? 1 : -1.4);
    final tint = g.isEven ? primaryColor : secondaryColor;

    const teeth = 8;
    final path = Path();
    for (var i = 0; i < teeth * 2; i++) {
      final rr = i.isEven ? gearR : gearR * 0.72;
      final a = spin + i * math.pi / teeth;
      final p = at + Offset(math.cos(a), math.sin(a)) * rr;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path..close(),
      Paint()..color = tint.withValues(alpha: 0.88),
    );
    canvas.drawCircle(
      at,
      gearR * 0.32,
      Paint()..color = const Color(0xFF1B2434),
    );
  }
}

/// Defne çelengi: iki yandan yukarı uzanan, nefes alan yaprak dizisi.
void paintLaurelWreathFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final breathe = 1 + math.sin(progress * math.pi * 2) * 0.02;
  const leaves = 11;
  for (var side = -1; side <= 1; side += 2) {
    for (var i = 0; i < leaves; i++) {
      final t = i / (leaves - 1);
      // Alttan başlayıp yukarı açılan yay.
      final angle = math.pi / 2 + side * (0.30 + t * 2.05);
      final at =
          center + Offset(math.cos(angle), math.sin(angle)) * radius * breathe;
      final leafLen = radius * (0.26 - t * 0.12);

      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(
        angle + side * 0.9 + math.sin(progress * math.pi * 2 + i) * 0.06,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(leafLen * 0.5, 0),
          width: leafLen,
          height: leafLen * 0.42,
        ),
        Paint()
          ..color = Color.lerp(
            primaryColor,
            secondaryColor,
            t,
          )!.withValues(alpha: 0.9),
      );
      canvas.restore();
    }
  }
}

/// Zincir: çerçeve boyunca dizilmiş, dönüşümlü dik/yatay metal halkalar.
void paintChainFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int links = 16,
}) {
  for (var i = 0; i < links; i++) {
    final angle = i / links * math.pi * 2 + progress * math.pi * 0.5;
    final at = center + Offset(math.cos(angle), math.sin(angle)) * radius;

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle + math.pi / 2);
    // Ardışık halkaları 90° çevirmek gerçek zincir hissi verir.
    if (i.isOdd) canvas.rotate(math.pi / 2);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: radius * 0.20,
        height: radius * 0.12,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, radius * 0.035)
        ..color = (i.isEven ? primaryColor : secondaryColor).withValues(
          alpha: 0.92,
        ),
    );
    canvas.restore();
  }
}

/// Müzik notaları: çerçeve etrafında dolaşan, hafifçe savrulan notalar.
void paintMusicNoteFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 7,
}) {
  for (var i = 0; i < count; i++) {
    final t = (progress * 0.6 + i / count) % 1.0;
    final angle = t * math.pi * 2;
    // Nota yörüngeden dışarı doğru hafifçe savrulur.
    final r = radius * (1 + math.sin(t * math.pi * 2 + i) * 0.06);
    final at = center + Offset(math.cos(angle), math.sin(angle)) * r;
    final s = radius * 0.13;
    final tint = i.isEven ? primaryColor : secondaryColor;

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(math.sin(progress * math.pi * 2 + i) * 0.25);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, s * 0.55),
        width: s * 1.15,
        height: s * 0.82,
      ),
      Paint()..color = tint.withValues(alpha: 0.92),
    );
    canvas.drawLine(
      Offset(s * 0.52, s * 0.5),
      Offset(s * 0.52, -s * 1.1),
      Paint()
        ..color = tint.withValues(alpha: 0.92)
        ..strokeWidth = math.max(0.9, s * 0.20)
        ..strokeCap = StrokeCap.round,
    );
    if (i.isEven) {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.52, -s * 1.1)
          ..quadraticBezierTo(s * 1.35, -s * 0.75, s * 0.62, -s * 0.25),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.9, s * 0.18)
          ..color = tint.withValues(alpha: 0.92),
      );
    }
    canvas.restore();
  }
}

/// Pati izleri: çerçeve boyunca sırayla beliren ve arkada solan izler.
void paintPawPrintFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 12,
}) {
  // "Yürüyen" baş nokta; geride kalan izler yaşlandıkça söner.
  final head = (progress * count) % count;
  for (var i = 0; i < count; i++) {
    var age = (i - head) % count;
    if (age < 0) age += count;
    final fade = math.max(0.0, 1 - age / (count * 0.55));
    if (fade <= 0.02) continue;

    final angle = i / count * math.pi * 2;
    final at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    final s = radius * 0.11;
    final paint = Paint()
      ..color = Color.lerp(
        secondaryColor,
        primaryColor,
        fade,
      )!.withValues(alpha: 0.35 + 0.6 * fade);

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle + math.pi / 2);
    // Ana yastık + dört parmak.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, s * 0.35),
        width: s * 1.25,
        height: s * 1.0,
      ),
      paint,
    );
    for (var f = 0; f < 4; f++) {
      final fa = -math.pi * 0.78 + f * math.pi * 0.19;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(math.cos(fa), math.sin(fa)) * s * 0.92,
          width: s * 0.46,
          height: s * 0.58,
        ),
        paint,
      );
    }
    canvas.restore();
  }
}

/// Elektrik yayı: çerçeve üzerinde dolaşan, zikzak şimşek kavisi.
void paintLightningArcFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.04
      ..color = secondaryColor.withValues(alpha: 0.22),
  );

  const segments = 26;
  final start = progress * math.pi * 2;
  final path = Path();
  for (var i = 0; i <= segments; i++) {
    final t = i / segments;
    final angle = start + t * math.pi * 0.85;
    // Deterministik zikzak: yay ortasında sapma en yüksek.
    final jitter =
        (((i * 37) % 17) / 17 - 0.5) * radius * 0.13 * math.sin(t * math.pi);
    final p =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + jitter);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  // Önce geniş parlama, sonra ince beyaz çekirdek.
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.05
      ..strokeCap = StrokeCap.round
      ..color = primaryColor.withValues(alpha: 0.9)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.05),
  );
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.02
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.95),
  );
}

/// Sarmaşık: çerçeve boyunca büyüyüp geri çekilen filiz ve yapraklar.
void paintVineGrowFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  // 0->1 büyür, 1->0 geri çekilir (ileri-geri döngü).
  final cycle = progress * 2;
  final grow = cycle <= 1 ? cycle : 2 - cycle;
  const segments = 60;
  final visible = (segments * grow).floor();

  final stem = Path();
  for (var i = 0; i <= visible; i++) {
    final t = i / segments;
    final angle = -math.pi / 2 + t * math.pi * 2;
    final wobble = math.sin(t * math.pi * 9) * radius * 0.035;
    final p =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + wobble);
    if (i == 0) {
      stem.moveTo(p.dx, p.dy);
    } else {
      stem.lineTo(p.dx, p.dy);
    }
  }
  canvas.drawPath(
    stem,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.035
      ..strokeCap = StrokeCap.round
      ..color = secondaryColor.withValues(alpha: 0.92),
  );

  // Filiz boyunca her 5 segmentte bir yaprak; uçtakiler henüz küçük.
  for (var i = 0; i <= visible; i += 5) {
    final t = i / segments;
    final angle = -math.pi / 2 + t * math.pi * 2;
    final at = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    final leafLen =
        radius * 0.17 * math.min(1.0, (visible - i) / 6 + 0.35);
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle + (i % 10 == 0 ? 1.1 : -1.1));
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(leafLen * 0.5, 0),
        width: leafLen,
        height: leafLen * 0.5,
      ),
      Paint()..color = primaryColor.withValues(alpha: 0.9),
    );
    canvas.restore();
  }
}
