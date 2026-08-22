// Satın alınabilir hayvan/doğa figürü dekorasyonları için paylaşılan
// prosedürel çizim yardımcıları. Hem avatar (dairesel) hem kapak (geniş
// banner) painter'ları tarafından kullanılır — mevcut sistemdeki gibi hiçbir
// görsel dosya (asset) kullanılmaz, her şey `Canvas` üzerinde vektörel çizilir.

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Yılan: avatar çerçevesine dolanan segmentli, dalgalı bir gövde + baş.
void paintSnakeCoil({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  const segments = 28;
  const coverage = 0.62; // yılanın çemberin ne kadarını kapladığı
  final path = Path();
  Offset headPoint = center;
  for (var i = 0; i <= segments; i++) {
    final t = i / segments;
    final angle = progress * math.pi * 2 + t * math.pi * 2 * coverage;
    final wobble =
        math.sin(t * math.pi * 7 + progress * math.pi * 2) * radius * 0.045;
    final r = radius + wobble;
    final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
    if (i == segments) headPoint = point;
  }

  final bodyPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = radius * 0.15
    ..shader = LinearGradient(
      colors: [primaryColor, secondaryColor],
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  canvas.drawPath(path, bodyPaint);

  // Pul deseni: gövde boyunca küçük noktalar.
  final scalePaint = Paint()..color = secondaryColor.withValues(alpha: 0.55);
  for (var i = 0; i < segments; i += 2) {
    final t = i / segments;
    final angle = progress * math.pi * 2 + t * math.pi * 2 * coverage;
    final wobble =
        math.sin(t * math.pi * 7 + progress * math.pi * 2) * radius * 0.045;
    final point =
        center + Offset(math.cos(angle), math.sin(angle)) * (radius + wobble);
    canvas.drawCircle(point, radius * 0.03, scalePaint);
  }

  // Baş + gözler.
  canvas.drawCircle(headPoint, radius * 0.1, Paint()..color = primaryColor);
  final eyePaint = Paint()..color = Colors.black87;
  final eyeOffset = Offset(radius * 0.035, 0);
  canvas.drawCircle(headPoint - eyeOffset, radius * 0.016, eyePaint);
  canvas.drawCircle(headPoint + eyeOffset, radius * 0.016, eyePaint);
}

/// Kelebek şekli çizer: iki üst + iki alt kanat ve gövde. `flap` 0 (kapalı)
/// ile 1 (tam açık) arasında kanat çırpma oranı, `heading` kelebeğin baktığı
/// yön (radyan).
void drawButterflyShape(
  Canvas canvas,
  Offset center,
  double size,
  double flap,
  Color primaryColor,
  Color secondaryColor,
  double heading,
) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(heading + math.pi / 2);

  final upperWingPaint = Paint()..color = primaryColor.withValues(alpha: 0.94);
  final lowerWingPaint = Paint()..color = secondaryColor.withValues(alpha: 0.9);
  final spread = 0.32 + flap.clamp(0.0, 1.0) * 0.68;

  for (final side in [-1.0, 1.0]) {
    canvas.save();
    canvas.scale(spread * side.sign, 1);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size * 0.55, -size * 0.32),
        width: size * 0.92,
        height: size * 0.72,
      ),
      upperWingPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size * 0.45, size * 0.34),
        width: size * 0.62,
        height: size * 0.5,
      ),
      lowerWingPaint,
    );
    canvas.restore();
  }

  canvas.drawLine(
    Offset(0, -size * 0.48),
    Offset(0, size * 0.48),
    Paint()
      ..color = Colors.black87
      ..strokeWidth = size * 0.07
      ..strokeCap = StrokeCap.round,
  );
  canvas.restore();
}

/// Kelebek: avatarın çevresinde süzülür, periyodik olarak profile konar.
void paintButterflyLandingOnAvatar({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final cycle = progress % 1.0;
  const landingAngle = math.pi / 2; // avatarın alt kenarı
  late Offset position;
  late double heading;
  late double flap;

  if (cycle < 0.6) {
    final flyT = cycle / 0.6;
    heading = landingAngle + flyT * math.pi * 2 * 0.85;
    final hover = math.sin(flyT * math.pi * 10) * radius * 0.12;
    position =
        center +
        Offset(math.cos(heading), math.sin(heading)) * (radius * 1.2 + hover);
    flap = (math.sin(progress * math.pi * 26) * 0.5 + 0.5).clamp(0.15, 1.0);
  } else {
    heading = landingAngle;
    position = center + Offset(math.cos(heading), math.sin(heading)) * radius;
    flap = (0.15 + (math.sin(progress * math.pi * 40) * 0.5 + 0.5) * 0.15)
        .clamp(0.1, 1.0);
  }

  drawButterflyShape(
    canvas,
    position,
    radius * 0.36,
    flap,
    primaryColor,
    secondaryColor,
    heading,
  );
}

/// Ateş böcekleri: avatar çevresinde yumuşak parıltıyla dolaşır.
void paintFirefliesAvatar({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 6,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 53.0;
    final angle = progress * math.pi * 2 * (0.6 + (i % 3) * 0.22) + seed;
    final wander = math.sin(progress * math.pi * 6 + seed) * radius * 0.16;
    final r = radius * (0.86 + (i % 4) * 0.08) + wander;
    final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
    final glow = (math.sin(progress * math.pi * 6 + seed) * 0.5 + 0.5);
    final paint = Paint()
      ..color = Color.lerp(
        secondaryColor,
        primaryColor,
        glow,
      )!.withValues(alpha: 0.5 + glow * 0.4)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + glow * 2);
    canvas.drawCircle(point, 1.5 + glow * 1.8, paint);
  }
}

/// Kedi patisi: avatarın alt kenarından periyodik olarak belirir/çekilir.
void paintCatPawPeek({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final cycle = progress % 1.0;
  double reveal;
  if (cycle < 0.5) {
    reveal = 0;
  } else if (cycle < 0.75) {
    reveal = (cycle - 0.5) / 0.25;
  } else {
    reveal = 1 - (cycle - 0.75) / 0.25;
  }
  reveal = reveal.clamp(0.0, 1.0);
  if (reveal <= 0.01) return;

  final pawSize = radius * 0.5;
  final baseY = center.dy + radius - pawSize * 0.15;
  final offsetY = pawSize * (1 - reveal) * 0.95;
  final pawCenter = Offset(center.dx, baseY + offsetY);

  canvas.drawOval(
    Rect.fromCenter(
      center: pawCenter,
      width: pawSize * 0.85,
      height: pawSize * 0.65,
    ),
    Paint()..color = primaryColor,
  );
  final toePaint = Paint()..color = secondaryColor;
  for (var i = -1; i <= 1; i++) {
    canvas.drawCircle(
      pawCenter + Offset(i * pawSize * 0.28, -pawSize * 0.42),
      pawSize * 0.16,
      toePaint,
    );
  }
}

/// Kapak fotoğrafı için kelebek çayırı: birden fazla kelebek soldan sağa süzülür.
void paintButterflyMeadowCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 4,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 41.0;
    final t = (progress * (0.35 + (i % 3) * 0.12) + i / count) % 1.0;
    final x = t * size.width;
    final y =
        size.height * (0.2 + (i % 4) * 0.18) +
        math.sin(t * math.pi * 6 + seed) * size.height * 0.08;
    final flap = (math.sin(progress * math.pi * 22 + seed) * 0.5 + 0.5).clamp(
      0.2,
      1.0,
    );
    drawButterflyShape(
      canvas,
      Offset(x, y),
      size.shortestSide * 0.16,
      flap,
      i.isEven ? primaryColor : secondaryColor,
      i.isEven ? secondaryColor : primaryColor,
      0,
    );
  }
}

/// Kapak fotoğrafı için aurora perdesi: üst kenarda dalgalanan ışık bandı.
void paintAuroraVeilCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  for (var band = 0; band < 3; band++) {
    final path = Path();
    final baseY = size.height * (0.08 + band * 0.05);
    path.moveTo(0, baseY);
    for (var x = 0.0; x <= size.width; x += size.width / 24) {
      final wave =
          math.sin(
            (x / size.width) * math.pi * 3 +
                progress * math.pi * 2 +
                band * 1.4,
          ) *
          size.height *
          0.05;
      path.lineTo(x, baseY + wave);
    }
    path.lineTo(size.width, 0);
    path.lineTo(0, 0);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [
            primaryColor.withValues(alpha: 0.32 - band * 0.08),
            secondaryColor.withValues(alpha: 0.12),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
  }
}

/// Kapak fotoğrafı için düşen çiçek yaprakları.
void paintPetalDriftCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 14,
}) {
  final paint = Paint();
  for (var i = 0; i < count; i++) {
    final seed = i * 71.0;
    final xBase = ((seed * 37) % 997) / 997 * size.width;
    final speed = 0.5 + (i % 5) * 0.15;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final x = xBase + math.sin(phase * math.pi * 4) * size.width * 0.04;
    final y = phase * size.height;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(phase * math.pi * 4);
    paint.color = (i.isEven ? primaryColor : secondaryColor).withValues(
      alpha: 0.75,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 5, height: 9),
      paint,
    );
    canvas.restore();
  }
}

/// Kapak fotoğrafı için alacakaranlık tonu + parıldayan ateş böcekleri.
void paintFireflyDuskCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 10,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [secondaryColor.withValues(alpha: 0.22), Colors.transparent],
      ).createShader(Offset.zero & size),
  );
  for (var i = 0; i < count; i++) {
    final seed = i * 61.0;
    final x = ((seed * 29) % 997) / 997 * size.width;
    final baseY = ((seed * 17) % 997) / 997 * size.height;
    final wander = math.sin(progress * math.pi * 2 * 2 + seed) * 10;
    final glow = (math.sin(progress * math.pi * 5 + seed) * 0.5 + 0.5);
    canvas.drawCircle(
      Offset(x + wander, baseY),
      1.6 + glow * 2,
      Paint()
        ..color = Color.lerp(
          secondaryColor,
          primaryColor,
          glow,
        )!.withValues(alpha: 0.55 + glow * 0.4)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + glow * 2),
    );
  }
}

// =============================================================================
// İkinci nesil satın alınabilir dekorasyonlar: daha şık/lüks avatar çerçeveleri,
// yeni kapak sahneleri ve tüm profili kaplayan premium haleler.
// =============================================================================

void _drawStar(Canvas canvas, Offset point, double size, Color color) {
  final path = Path();
  for (var j = 0; j < 10; j++) {
    final r = j.isEven ? size : size * 0.42;
    final a = -math.pi / 2 + j * math.pi / 5;
    final p = point + Offset(math.cos(a), math.sin(a)) * r;
    if (j == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  canvas.drawPath(path, Paint()..color = color);
}

/// Kraliyet Altın Çerçeve: dönen altın halka + parlayan mücevher noktaları.
void paintRoyalGoldFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final ringPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = radius * 0.13
    ..shader = SweepGradient(
      colors: [primaryColor, secondaryColor, primaryColor],
      transform: GradientRotation(progress * math.pi * 2),
    ).createShader(Rect.fromCircle(center: center, radius: radius));
  canvas.drawCircle(center, radius, ringPaint);

  canvas.drawCircle(
    center,
    radius * 0.86,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.02
      ..color = secondaryColor.withValues(alpha: 0.7),
  );

  const gemCount = 8;
  final shimmer = math.sin(progress * math.pi * 2) * 0.5 + 0.5;
  for (var i = 0; i < gemCount; i++) {
    final angle = progress * math.pi * 2 * 0.15 + (math.pi * 2 / gemCount) * i;
    final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
    final glow = math.sin(progress * math.pi * 4 + i) * 0.5 + 0.5;
    canvas.drawCircle(
      point,
      radius * (0.06 + glow * 0.025),
      Paint()..color = Color.lerp(secondaryColor, Colors.white, shimmer * 0.4)!,
    );
  }
}

/// Koi balığı: avatar çevresinde kuyruğunu dalgalandırarak yüzer.
void paintKoiSwim({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final angle = progress * math.pi * 2;
  final swimRadius = radius * 1.12;
  final position =
      center + Offset(math.cos(angle), math.sin(angle)) * swimRadius;
  final heading = angle + math.pi / 2;

  canvas.save();
  canvas.translate(position.dx, position.dy);
  canvas.rotate(heading);
  final bodyLength = radius * 0.62;
  final bodyPaint = Paint()
    ..shader = LinearGradient(colors: [primaryColor, secondaryColor])
        .createShader(
          Rect.fromLTWH(
            -bodyLength / 2,
            -bodyLength * 0.22,
            bodyLength,
            bodyLength * 0.44,
          ),
        );
  final body = Path()
    ..moveTo(bodyLength * 0.5, 0)
    ..quadraticBezierTo(
      bodyLength * 0.1,
      -bodyLength * 0.22,
      -bodyLength * 0.35,
      0,
    )
    ..quadraticBezierTo(
      bodyLength * 0.1,
      bodyLength * 0.22,
      bodyLength * 0.5,
      0,
    )
    ..close();
  canvas.drawPath(body, bodyPaint);

  final tailWave = math.sin(progress * math.pi * 10) * bodyLength * 0.18;
  final tail = Path()
    ..moveTo(-bodyLength * 0.35, 0)
    ..lineTo(-bodyLength * 0.62, -bodyLength * 0.2 + tailWave)
    ..lineTo(-bodyLength * 0.62, bodyLength * 0.2 + tailWave)
    ..close();
  canvas.drawPath(
    tail,
    Paint()..color = secondaryColor.withValues(alpha: 0.85),
  );
  canvas.restore();

  for (var i = 1; i <= 3; i++) {
    final trailAngle = angle - i * 0.18;
    final trailPoint =
        center +
        Offset(math.cos(trailAngle), math.sin(trailAngle)) * swimRadius;
    canvas.drawCircle(
      trailPoint,
      1.4 * (4 - i) / 3,
      Paint()..color = Colors.white.withValues(alpha: 0.4),
    );
  }
}

/// Gece baykuşu: periyodik olarak avatarın üstüne konar, gözlerini kırpıştırır.
void paintOwlPerch({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final cycle = progress % 1.0;
  const perchAngle = -math.pi / 2;
  late Offset position;
  double blink;
  if (cycle < 0.55) {
    final flyT = cycle / 0.55;
    final angle = perchAngle + flyT * math.pi * 2 * 0.7;
    final hover = math.sin(flyT * math.pi * 8) * radius * 0.1;
    position =
        center +
        Offset(math.cos(angle), math.sin(angle)) * (radius * 1.22 + hover);
    blink = 1.0;
  } else {
    position =
        center + Offset(math.cos(perchAngle), math.sin(perchAngle)) * radius;
    final blinkT = ((cycle - 0.55) / 0.45 * 6).floor();
    blink = blinkT.isEven ? 1.0 : 0.25;
  }

  final owlSize = radius * 0.4;
  canvas.save();
  canvas.translate(position.dx, position.dy);
  canvas.drawOval(
    Rect.fromCenter(center: Offset.zero, width: owlSize * 0.9, height: owlSize),
    Paint()..color = primaryColor,
  );
  final eyeColor = Colors.white.withValues(alpha: blink.clamp(0.2, 1.0));
  for (final dx in [-owlSize * 0.2, owlSize * 0.2]) {
    canvas.drawCircle(
      Offset(dx, -owlSize * 0.12),
      owlSize * 0.16,
      Paint()..color = eyeColor,
    );
    canvas.drawCircle(
      Offset(dx, -owlSize * 0.12),
      owlSize * 0.07,
      Paint()..color = Colors.black87,
    );
  }
  final beak = Path()
    ..moveTo(0, -owlSize * 0.02)
    ..lineTo(-owlSize * 0.08, owlSize * 0.14)
    ..lineTo(owlSize * 0.08, owlSize * 0.14)
    ..close();
  canvas.drawPath(beak, Paint()..color = secondaryColor);
  for (final side in [-1.0, 1.0]) {
    final ear = Path()
      ..moveTo(side * owlSize * 0.28, -owlSize * 0.4)
      ..lineTo(side * owlSize * 0.14, -owlSize * 0.56)
      ..lineTo(side * owlSize * 0.4, -owlSize * 0.32)
      ..close();
    canvas.drawPath(ear, Paint()..color = primaryColor);
  }
  canvas.restore();
}

/// Ejderha alevi: avatar çevresinde dolanan parıldayan alev izi.
void paintDragonWisp({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  const segments = 22;
  const coverage = 0.78;
  for (var i = 0; i < segments; i++) {
    final t = i / segments;
    final angle = -progress * math.pi * 2 + t * math.pi * 2 * coverage;
    final flicker = math.sin(progress * math.pi * 10 + t * 20) * radius * 0.06;
    final r = radius + flicker;
    final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
    final size = (radius * (0.14 - t * 0.09)).clamp(
      radius * 0.03,
      radius * 0.14,
    );
    final glow = math.sin(progress * math.pi * 6 + t * 10) * 0.5 + 0.5;
    canvas.drawCircle(
      point,
      size,
      Paint()
        ..color = Color.lerp(
          secondaryColor,
          primaryColor,
          glow,
        )!.withValues(alpha: 0.85 - t * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size * 0.6),
    );
  }
  final headAngle = -progress * math.pi * 2;
  final head =
      center + Offset(math.cos(headAngle), math.sin(headAngle)) * radius;
  canvas.drawCircle(head, radius * 0.1, Paint()..color = primaryColor);
}

/// Yıldız konfeti çerçevesi: ince halka + patlayan yıldız parçacıkları.
void paintStarConfettiFrame({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 14,
}) {
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius * 0.04
      ..color = primaryColor.withValues(alpha: 0.5),
  );
  for (var i = 0; i < count; i++) {
    final seed = i * 47.0;
    final angle = (math.pi * 2 / count) * i + progress * math.pi * 2 * 0.3;
    final pop = math.sin(progress * math.pi * 4 + seed) * 0.5 + 0.5;
    final r = radius * (1.0 + pop * 0.18);
    final point = center + Offset(math.cos(angle), math.sin(angle)) * r;
    _drawStar(
      canvas,
      point,
      radius * (0.05 + pop * 0.04),
      i.isEven ? primaryColor : secondaryColor,
    );
  }
}

/// Kapak fotoğrafı için yıldızlı gece: parıldayan yıldızlar + kayan yıldız.
void paintStarryNightCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 40,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [secondaryColor.withValues(alpha: 0.35), Colors.transparent],
      ).createShader(Offset.zero & size),
  );

  for (var i = 0; i < count; i++) {
    final seed = i * 31.0;
    final x = ((seed * 53) % 997) / 997 * size.width;
    final y = ((seed * 19) % 997) / 997 * size.height * 0.75;
    final twinkle = math.sin(progress * math.pi * 6 + seed) * 0.5 + 0.5;
    canvas.drawCircle(
      Offset(x, y),
      0.6 + twinkle * 1.6,
      Paint()..color = Colors.white.withValues(alpha: 0.4 + twinkle * 0.5),
    );
  }

  final shootT = progress % 1.0;
  if (shootT < 0.25) {
    final t = shootT / 0.25;
    final start = Offset(size.width * 0.1, size.height * 0.1);
    final end = Offset(size.width * 0.55, size.height * 0.45);
    final p = Offset.lerp(start, end, t)!;
    canvas.drawLine(
      p,
      p - const Offset(18, -9),
      Paint()
        ..color = Colors.white.withValues(alpha: (1 - t).clamp(0.0, 1.0))
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }
}

/// Kapak fotoğrafı için kar yağışı.
void paintSnowfallCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 24,
}) {
  final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
  for (var i = 0; i < count; i++) {
    final seed = i * 61.0;
    final xBase = ((seed * 37) % 997) / 997 * size.width;
    final speed = 0.4 + (i % 5) * 0.12;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 6) * size.width * 0.03;
    canvas.drawCircle(
      Offset(xBase + sway, phase * size.height),
      1.6 + (i % 3) * 0.8,
      paint,
    );
  }
}

/// Kapak fotoğrafı için altın saat: sıcak tonlarda süzülen ışık huzmeleri.
void paintGoldenHourCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primaryColor.withValues(alpha: 0.26), Colors.transparent],
      ).createShader(Offset.zero & size),
  );

  final sweep = progress % 1.0;
  for (var i = 0; i < 4; i++) {
    final x = ((sweep + i / 4) % 1.0) * size.width * 1.3 - size.width * 0.15;
    final path = Path()
      ..moveTo(x, 0)
      ..lineTo(x + size.width * 0.08, 0)
      ..lineTo(x - size.width * 0.1, size.height)
      ..lineTo(x - size.width * 0.18, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()..color = secondaryColor.withValues(alpha: 0.12),
    );
  }
}

/// Kapak fotoğrafı için okyanus dalgası: alt kenarda dalgalanan iki katman.
void paintOceanWaveCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  for (var layer = 0; layer < 2; layer++) {
    final path = Path();
    final baseY = size.height * (0.78 + layer * 0.08);
    path.moveTo(0, size.height);
    path.lineTo(0, baseY);
    for (var x = 0.0; x <= size.width; x += size.width / 20) {
      final wave =
          math.sin(
            (x / size.width) * math.pi * 4 + progress * math.pi * 2 + layer,
          ) *
          size.height *
          0.02;
      path.lineTo(x, baseY + wave);
    }
    path.lineTo(size.width, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = (layer == 0 ? primaryColor : secondaryColor).withValues(
          alpha: 0.35 - layer * 0.1,
        ),
    );
  }
}

/// Kapak fotoğrafı için havai fişek patlamaları.
void paintFireworkBurstCover({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int bursts = 3,
}) {
  for (var b = 0; b < bursts; b++) {
    final seed = b * 97.0;
    final cycle = (progress + b / bursts) % 1.0;
    if (cycle > 0.5) continue;
    final t = cycle / 0.5;
    final cx = ((seed * 53) % 997) / 997 * size.width;
    final cy = size.height * (0.2 + ((seed * 29) % 997) / 997 * 0.4);
    final radius = t * size.shortestSide * 0.22;
    final alpha = (1 - t).clamp(0.0, 1.0);
    for (var i = 0; i < 12; i++) {
      final angle = (math.pi * 2 / 12) * i;
      final p =
          Offset(cx, cy) + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(
        p,
        1.6,
        Paint()
          ..color = (i.isEven ? primaryColor : secondaryColor).withValues(
            alpha: alpha,
          ),
      );
    }
  }
}

/// Tüm profil için kraliyet halesi: merkezi altın parıltı + dönen ışık noktaları.
void paintRoyalAuraEffect({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final center = Offset(size.width / 2, size.height * 0.3);
  final radius = size.shortestSide * 0.9;
  canvas.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [primaryColor.withValues(alpha: 0.18), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: radius)),
  );
  for (var i = 0; i < 16; i++) {
    final angle = progress * math.pi * 2 * 0.4 + (math.pi * 2 / 16) * i;
    final r = radius * (0.5 + (i % 3) * 0.15);
    final p = center + Offset(math.cos(angle), math.sin(angle)) * r;
    canvas.drawCircle(
      p,
      1.6,
      Paint()..color = secondaryColor.withValues(alpha: 0.7),
    );
  }
}

/// Tüm profil için galaksi sarmalı: merkezden dışa doğru dönen yıldız tozu.
void paintGalaxySwirlEffect({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 60,
}) {
  final center = Offset(size.width / 2, size.height * 0.35);
  for (var i = 0; i < count; i++) {
    final t = i / count;
    final angle = t * math.pi * 8 + progress * math.pi * 2;
    final r = t * size.shortestSide * 0.9;
    final p = center + Offset(math.cos(angle), math.sin(angle)) * r;
    canvas.drawCircle(
      p,
      1 + (i % 3) * 0.6,
      Paint()
        ..color = Color.lerp(
          primaryColor,
          secondaryColor,
          t,
        )!.withValues(alpha: 0.5),
    );
  }
}

/// Tüm profil için anka alevi: yükselen parıldayan alev parçacıkları.
void paintPhoenixFlameEffect({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 30,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 43.0;
    final xBase = ((seed * 37) % 997) / 997 * size.width;
    final speed = 0.5 + (i % 4) * 0.15;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 5 + seed) * size.width * 0.03;
    final y = size.height * (1 - phase);
    final glow = 1 - phase;
    canvas.drawCircle(
      Offset(xBase + sway, y),
      1.4 + glow * 2.4,
      Paint()
        ..color = Color.lerp(
          secondaryColor,
          primaryColor,
          glow,
        )!.withValues(alpha: 0.15 + glow * 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + glow * 2),
    );
  }
}

/// Tüm profil için kristal parıltı: dönen küçük elmas parçacıkları.
void paintCrystalShimmerEffect({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 18,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 71.0;
    final x = ((seed * 53) % 997) / 997 * size.width;
    final y = ((seed * 29) % 997) / 997 * size.height;
    final shimmer = math.sin(progress * math.pi * 4 + seed) * 0.5 + 0.5;
    final s = 4 + shimmer * 5;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(progress * math.pi + seed);
    final path = Path()
      ..moveTo(0, -s)
      ..lineTo(s * 0.6, 0)
      ..lineTo(0, s)
      ..lineTo(-s * 0.6, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = (i.isEven ? primaryColor : secondaryColor).withValues(
          alpha: 0.25 + shimmer * 0.5,
        ),
    );
    canvas.restore();
  }
}

/// Tüm profil için gök gürültülü fırtına: yağmur + periyodik şimşek flaşı.
void paintThunderStormEffect({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int rainCount = 26,
}) {
  final flashCycle = progress % 1.0;
  if (flashCycle < 0.06) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Colors.white.withValues(
          alpha: (0.06 - flashCycle) / 0.06 * 0.35,
        ),
    );
  }
  final rainPaint = Paint()
    ..color = secondaryColor.withValues(alpha: 0.5)
    ..strokeWidth = 1.4;
  for (var i = 0; i < rainCount; i++) {
    final seed = i * 37.0;
    final xBase = ((seed * 53) % 997) / 997 * size.width;
    final speed = 0.8 + (i % 4) * 0.2;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final y = phase * size.height;
    canvas.drawLine(Offset(xBase, y), Offset(xBase - 4, y + 14), rainPaint);
  }
  if (flashCycle < 0.06) {
    final boltX = size.width * 0.5;
    final path = Path()
      ..moveTo(boltX, 0)
      ..lineTo(boltX - 14, size.height * 0.35)
      ..lineTo(boltX + 4, size.height * 0.35)
      ..lineTo(boltX - 10, size.height * 0.7);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = primaryColor.withValues(alpha: 0.85),
    );
  }
}

// =============================================================================
// Fotoğraf-üstü (overlay) efektleri: çerçeve/yaratık değil, doğrudan profil
// fotoğrafının kendi yüzeyine binen efektler — çağıran taraf bu boyutu
// dairesel olarak (ClipOval) fotoğrafla birebir eşleşecek şekilde keser.
// `renderer_key` her zaman `photo_` önekiyle başlar; Flutter tarafı bunu
// görüp çerçeve halkası çizmeden doğrudan fotoğrafın üstüne bindirir.
// =============================================================================

/// Fotoğrafın üzerine düşen şimşek çakması: kısa beyaz flaş + zikzak bolt.
void paintPhotoLightningStrike({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = secondaryColor.withValues(alpha: 0.10),
  );

  final cycle = progress % 1.0;
  if (cycle < 0.08) {
    final t = cycle / 0.08;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: (1 - t) * 0.55),
    );
    final boltX = size.width * 0.5;
    final path = Path()
      ..moveTo(boltX, 0)
      ..lineTo(boltX - size.width * 0.12, size.height * 0.32)
      ..lineTo(boltX + size.width * 0.04, size.height * 0.32)
      ..lineTo(boltX - size.width * 0.08, size.height * 0.62)
      ..lineTo(boltX + size.width * 0.1, size.height * 0.62)
      ..lineTo(boltX - size.width * 0.02, size.height);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.035
        ..color = primaryColor.withValues(alpha: (1 - t).clamp(0.0, 1.0))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }
}

/// Fotoğrafın üzerine yağan yağmur: kayan damla çizgileri + hafif buğu tonu.
void paintPhotoRainOverlay({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 22,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = secondaryColor.withValues(alpha: 0.10),
  );

  final paint = Paint()
    ..color = Colors.white.withValues(alpha: 0.5)
    ..strokeWidth = 1.2
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < count; i++) {
    final seed = i * 43.0;
    final xBase = ((seed * 53) % 997) / 997 * size.width;
    final speed = 1.1 + (i % 5) * 0.25;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final y = phase * size.height;
    canvas.drawLine(
      Offset(xBase, y),
      Offset(xBase - 2, y + size.height * 0.16),
      paint,
    );
  }

  final dropPaint = Paint()..color = Colors.white.withValues(alpha: 0.28);
  for (var i = 0; i < 6; i++) {
    final seed = i * 91.0;
    final x = ((seed * 29) % 997) / 997 * size.width;
    canvas.drawCircle(
      Offset(x, size.height * (0.82 + (i % 3) * 0.05)),
      1.4,
      dropPaint,
    );
  }
}

/// Fotoğrafın üzerine eski TV efekti: tarama çizgileri + statik parazit +
/// periyodik sinyal kayması + hafif vinyet.
void paintPhotoOldTvEffect({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = primaryColor.withValues(alpha: 0.12),
  );

  final linePaint = Paint()..color = Colors.black.withValues(alpha: 0.16);
  final lineSpacing = size.height / 24;
  for (var y = 0.0; y < size.height; y += lineSpacing) {
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, lineSpacing * 0.4),
      linePaint,
    );
  }

  final noisePaint = Paint()..color = Colors.white.withValues(alpha: 0.35);
  for (var i = 0; i < 40; i++) {
    final seed = i * 67.0 + (progress * 997).floorToDouble();
    final x = ((seed * 53) % 997) / 997 * size.width;
    final y = ((seed * 31) % 997) / 997 * size.height;
    canvas.drawRect(Rect.fromLTWH(x, y, 1.4, 1.4), noisePaint);
  }

  final glitchCycle = progress % 1.0;
  if (glitchCycle < 0.05) {
    final y = (glitchCycle / 0.05) * size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, size.height * 0.03),
      Paint()..color = secondaryColor.withValues(alpha: 0.4),
    );
  }

  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
        radius: 0.85,
      ).createShader(Offset.zero & size),
  );
}

// =============================================================================
// Fotoğraf-üstü efektlerin ikinci dalgası: yukarıdaki 3 örnek ("sadece örnek
// verdim, onlarca efekt koy") üzerine 14 yeni benzersiz, birbirinden farklı
// tema — kar, sis, sıcak dalgalanma, dijital glitch/VHS, film grenli, güneş
// parlaması, bokeh, kırağı, konfeti, baloncuk, çatlak cam, duman, alev.
// Hepsi doğrudan fotoğrafın üzerine (dairesel kırpılı) biner.
// =============================================================================

/// Fotoğrafın üzerine yağan kar.
void paintPhotoSnowOverlay({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 20,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = secondaryColor.withValues(alpha: 0.08),
  );
  final paint = Paint()..color = Colors.white.withValues(alpha: 0.85);
  for (var i = 0; i < count; i++) {
    final seed = i * 59.0;
    final xBase = ((seed * 37) % 997) / 997 * size.width;
    final speed = 0.4 + (i % 5) * 0.12;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 6) * size.width * 0.04;
    canvas.drawCircle(
      Offset(xBase + sway, phase * size.height),
      1.3 + (i % 3) * 0.6,
      paint,
    );
  }
}

/// Fotoğrafın üzerinde dalgalanan sis perdesi.
void paintPhotoFogOverlay({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  for (var band = 0; band < 3; band++) {
    final path = Path();
    final baseY = size.height * (0.25 + band * 0.28);
    path.moveTo(-size.width * 0.2, baseY);
    for (
      var x = -size.width * 0.2;
      x <= size.width * 1.2;
      x += size.width / 16
    ) {
      final wave =
          math.sin(
            (x / size.width) * math.pi * 2 + progress * math.pi * 2 + band,
          ) *
          size.height *
          0.06;
      path.lineTo(x, baseY + wave);
    }
    path.lineTo(size.width * 1.2, size.height);
    path.lineTo(-size.width * 0.2, size.height);
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.14 - band * 0.02)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
  }
}

/// Fotoğrafın üzerinde sıcak hava dalgalanması (ısı tirtili).
void paintPhotoHeatWave({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = primaryColor.withValues(alpha: 0.05),
  );
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0
    ..color = secondaryColor.withValues(alpha: 0.2);
  for (var i = 0; i < 10; i++) {
    final x = size.width * (i / 10);
    final path = Path()..moveTo(x, size.height);
    for (var y = size.height; y >= 0; y -= size.height / 14) {
      final wobble =
          math.sin(progress * math.pi * 4 + y * 0.1 + i) * size.width * 0.015;
      path.lineTo(x + wobble, y);
    }
    canvas.drawPath(path, paint);
  }
}

/// Fotoğrafın üzerinde neon renkli dijital glitch (RGB kayması) çizgileri.
void paintPhotoNeonGlitch({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final cycle = progress % 1.0;
  if (cycle < 0.12) {
    final t = cycle / 0.12;
    for (var i = 0; i < 3; i++) {
      final y = size.height * ((i / 3 + t) % 1.0);
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.width, size.height * 0.04),
        Paint()
          ..color = (i.isEven ? primaryColor : secondaryColor).withValues(
            alpha: 0.5,
          ),
      );
    }
  }
  final linePaint = Paint()
    ..color = primaryColor.withValues(alpha: 0.12)
    ..strokeWidth = 1;
  for (var y = size.height * 0.15; y < size.height; y += size.height / 8) {
    canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
  }
}

/// Fotoğrafın üzerinde VHS kaseti tarzı statik parazit + renk kayması.
void paintPhotoVhsStatic({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = primaryColor.withValues(alpha: 0.06),
  );
  final noisePaint = Paint();
  for (var i = 0; i < 30; i++) {
    final seed = i * 53.0 + (progress * 600).floorToDouble();
    final y = ((seed * 31) % 997) / 997 * size.height;
    final w = ((seed * 17) % 997) / 997 * size.width * 0.6 + size.width * 0.1;
    final x = ((seed * 23) % 997) / 997 * size.width;
    noisePaint.color = Colors.white.withValues(alpha: 0.08 + (i % 5) * 0.02);
    canvas.drawRect(Rect.fromLTWH(x, y, w, 1.4), noisePaint);
  }
  final glitchCycle = progress % 1.0;
  if (glitchCycle < 0.06) {
    final y = (glitchCycle / 0.06) * size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.width, size.height * 0.05),
      Paint()..color = secondaryColor.withValues(alpha: 0.35),
    );
  }
}

/// Fotoğrafın üzerinde film grenli doku + hafif flicker + vinyet.
void paintPhotoFilmGrain({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final flicker = (math.sin(progress * math.pi * 40) * 0.5 + 0.5) * 0.06;
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = Colors.black.withValues(alpha: 0.08 + flicker),
  );
  final grainPaint = Paint();
  for (var i = 0; i < 60; i++) {
    final seed = i * 37.0 + (progress * 800).floorToDouble();
    final x = ((seed * 53) % 997) / 997 * size.width;
    final y = ((seed * 71) % 997) / 997 * size.height;
    grainPaint.color = Colors.white.withValues(alpha: 0.05 + (i % 3) * 0.02);
    canvas.drawRect(Rect.fromLTWH(x, y, 1, 1), grainPaint);
  }
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = RadialGradient(
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.32)],
        radius: 0.9,
      ).createShader(Offset.zero & size),
  );
}

/// Fotoğrafın üzerinden geçen güneş parlaması (lens flare).
void paintPhotoSunFlare({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final cycle = progress % 1.0;
  final flareX = cycle * size.width * 1.3 - size.width * 0.15;
  final flareY = size.height * 0.25;
  final center = Offset(flareX, flareY);
  final flareRadius = size.shortestSide * 0.16;
  canvas.drawCircle(
    center,
    flareRadius,
    Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withValues(alpha: 0.5), Colors.transparent],
      ).createShader(Rect.fromCircle(center: center, radius: flareRadius)),
  );
  final mid = Offset(size.width / 2, size.height / 2);
  for (var i = 1; i <= 3; i++) {
    final p = center + (mid - center) * (i * 0.28);
    canvas.drawCircle(
      p,
      size.shortestSide * 0.02 * i,
      Paint()..color = primaryColor.withValues(alpha: 0.18),
    );
  }
}

/// Fotoğrafın üzerinde süzülen bulanık bokeh ışıkları.
void paintPhotoBokehLights({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 10,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 61.0;
    final xBase = ((seed * 43) % 997) / 997 * size.width;
    final speed = 0.3 + (i % 4) * 0.1;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final y = size.height * (1 - phase);
    final r = size.shortestSide * (0.05 + (i % 3) * 0.03);
    canvas.drawCircle(
      Offset(xBase, y),
      r,
      Paint()
        ..color = (i.isEven ? primaryColor : secondaryColor).withValues(
          alpha: 0.22,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.6),
    );
  }
}

/// Fotoğrafın köşelerinden büyüyen kırağı/buz deseni.
void paintPhotoIceFrost({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = primaryColor.withValues(alpha: 0.04),
  );
  final grow = 0.6 + (math.sin(progress * math.pi * 2) * 0.5 + 0.5) * 0.4;
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2
    ..color = Colors.white.withValues(alpha: 0.6);
  final center = Offset(size.width / 2, size.height / 2);
  for (final corner in [
    Offset.zero,
    Offset(size.width, 0),
    Offset(0, size.height),
    Offset(size.width, size.height),
  ]) {
    final toCenter = center - corner;
    final baseAngle = math.atan2(toCenter.dy, toCenter.dx);
    for (var branch = -2; branch <= 2; branch++) {
      final angle = baseAngle + branch * 0.22;
      final length = size.shortestSide * (0.16 - branch.abs() * 0.02) * grow;
      final end = corner + Offset(math.cos(angle), math.sin(angle)) * length;
      canvas.drawLine(corner, end, paint);
      final mid = Offset.lerp(corner, end, 0.6)!;
      final sideAngle = angle + math.pi / 2;
      canvas.drawLine(
        mid,
        mid + Offset(math.cos(sideAngle), math.sin(sideAngle)) * length * 0.25,
        paint,
      );
    }
  }
}

/// Fotoğrafın üzerine patlayan konfeti.
void paintPhotoConfettiBurst({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 18,
}) {
  final paint = Paint();
  for (var i = 0; i < count; i++) {
    final seed = i * 47.0;
    final xBase = ((seed * 53) % 997) / 997 * size.width;
    final speed = 0.6 + (i % 5) * 0.15;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final x = xBase + math.sin(phase * math.pi * 5) * size.width * 0.05;
    final y = phase * size.height;
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(phase * math.pi * 6);
    paint.color = (i.isEven ? primaryColor : secondaryColor).withValues(
      alpha: 0.8,
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: 4, height: 6),
      paint,
    );
    canvas.restore();
  }
}

/// Fotoğrafın üzerinde yükselen su altı baloncukları.
void paintPhotoBubbleOverlay({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 14,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = secondaryColor.withValues(alpha: 0.1),
  );
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..color = Colors.white.withValues(alpha: 0.55);
  for (var i = 0; i < count; i++) {
    final seed = i * 71.0;
    final xBase = ((seed * 37) % 997) / 997 * size.width;
    final speed = 0.3 + (i % 4) * 0.12;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 4) * size.width * 0.03;
    final y = size.height * (1 - phase);
    canvas.drawCircle(Offset(xBase + sway, y), 2 + (i % 4) * 1.2, paint);
  }
}

/// Fotoğrafın üzerinde çatlamış cam deseni + hafif parıltı.
void paintPhotoCrackGlass({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
}) {
  final shimmer = math.sin(progress * math.pi * 2) * 0.5 + 0.5;
  final center = Offset(size.width * 0.62, size.height * 0.38);
  final paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1
    ..color = Colors.white.withValues(alpha: 0.5 + shimmer * 0.2);
  const cracks = 9;
  for (var i = 0; i < cracks; i++) {
    final angle = (math.pi * 2 / cracks) * i + 0.3;
    final length = size.shortestSide * (0.28 + (i % 3) * 0.08);
    var point = center;
    final path = Path()..moveTo(point.dx, point.dy);
    for (var seg = 0; seg < 3; seg++) {
      final segAngle = angle + (seg.isEven ? 0.15 : -0.15);
      point =
          point + Offset(math.cos(segAngle), math.sin(segAngle)) * (length / 3);
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path, paint);
  }
  canvas.drawCircle(
    center,
    3,
    Paint()..color = Colors.white.withValues(alpha: 0.7),
  );
}

/// Fotoğrafın üzerinde süzülen duman.
void paintPhotoSmokeDrift({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 5,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 83.0;
    final speed = 0.25 + (i % 3) * 0.08;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final x =
        size.width * (0.2 + (i % 3) * 0.3) +
        math.sin(phase * math.pi * 2) * size.width * 0.08;
    final y = size.height * (1 - phase);
    final r = size.shortestSide * (0.18 + (i % 2) * 0.06);
    canvas.drawCircle(
      Offset(x, y),
      r,
      Paint()
        ..color = (i.isEven ? secondaryColor : primaryColor).withValues(
          alpha: 0.10,
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5),
    );
  }
}

/// Fotoğrafın alt kısmından yükselen alev.
void paintPhotoFlameOverlay({
  required Canvas canvas,
  required Size size,
  required double progress,
  required Color primaryColor,
  required Color secondaryColor,
  int count = 16,
}) {
  for (var i = 0; i < count; i++) {
    final seed = i * 41.0;
    final xBase = ((seed * 37) % 997) / 997 * size.width;
    final speed = 0.7 + (i % 4) * 0.2;
    final phase = (progress * speed + ((seed * 13) % 101) / 101) % 1.0;
    final sway = math.sin(phase * math.pi * 6 + seed) * size.width * 0.04;
    final y = size.height * (1 - phase * 0.65);
    final glow = 1 - phase;
    canvas.drawCircle(
      Offset(xBase + sway, y),
      1.6 + glow * 2.6,
      Paint()
        ..color = Color.lerp(
          secondaryColor,
          primaryColor,
          glow,
        )!.withValues(alpha: 0.2 + glow * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + glow * 2),
    );
  }
}
