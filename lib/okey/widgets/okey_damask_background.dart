import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Masanın ARKA PLANI — koyu turkuaz-mavi zemin üzerine kabartma damask
/// (kıvrım/yaprak) motifi.
///
/// ## Neden CustomPainter, neden bir görsel değil
///
/// Referans masanın zemini tek renk değil: merkezden dışa açılan bir ışık,
/// üzerine düzenli aralıklarla yerleşmiş, zeminden yalnızca birkaç ton açık
/// KABARTMA kıvrımlar var. Bunu bir PNG ile yapmak (a) her ekran oranında
/// ya gerilir ya kırpılır, (b) uygulamanın boyutunu büyütür, (c) koyu/açık
/// varyantı için ikinci bir dosya ister. Vektörel çizim her çözünürlükte
/// keskin kalır ve tek bir [RepaintBoundary] arkasında BİR KEZ boyanır —
/// taşlar hareket ettikçe yeniden çizilmez.
///
/// ## Motifin kabartma hissi nereden geliyor
///
/// Tek bir açık çizgi "boyanmış" görünür. Kabartma, İKİ çizginin üst üste
/// binmesinden doğar: önce 1.5px aşağı kaydırılmış KOYU bir kopya (gölge),
/// sonra tam yerinde AÇIK olan asıl çizgi. Işık yönü masanın geri
/// kalanıyla aynı: yukarıdan-soldan.
class OkeyDamaskBackground extends StatelessWidget {
  /// Motifin zeminden ne kadar ayrıştığı (0 = düz zemin, 1 = referans).
  final double ornamentStrength;

  const OkeyDamaskBackground({super.key, this.ornamentStrength = 1.0});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _DamaskPainter(strength: ornamentStrength),
        size: Size.infinite,
      ),
    );
  }
}

class _DamaskPainter extends CustomPainter {
  final double strength;

  const _DamaskPainter({required this.strength});

  // --- Zemin tonları (referanstan örneklendi) ----------------------------
  static const _deep = Color(0xFF0C3F57);
  static const _mid = Color(0xFF17607D);
  static const _light = Color(0xFF2380A0);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    // 1) ZEMİN — merkezden dışa açılan ışık. Düz bir renk, masaya
    //    "yuvarlaklık" vermiyordu; bu üç duraklı radyal, ortadaki oyun
    //    alanını kenarlardan bir tık öne çıkarır.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.05),
          radius: 0.95,
          colors: [_light, _mid, _deep],
          stops: [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    if (strength <= 0) return;

    // 2) MOTİF IZGARASI — hücre ölçüsü ekranla büyür ki telefonda kalabalık,
    //    tablette seyrek görünmesin.
    final cell = (size.height * 0.30).clamp(90.0, 260.0);
    final motif = _motifPath(cell);

    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = cell * 0.055
      ..color = const Color(0xFF04222F).withValues(alpha: 0.30 * strength);

    final light = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = cell * 0.045
      ..color = const Color(0xFF7FD0E4).withValues(alpha: 0.14 * strength);

    canvas.save();
    canvas.clipRect(rect);

    final cols = (size.width / cell).ceil() + 2;
    final rows = (size.height / cell).ceil() + 2;

    for (var r = -1; r < rows; r++) {
      for (var col = -1; col < cols; col++) {
        // Tek satırlar YARIM hücre kaydırılır: ızgara "tuğla" gibi dizilir,
        // düz bir dama tahtası gibi değil. Damask desenlerinin tamamı bu
        // kaydırmayı kullanır; olmazsa desen mekanik görünür.
        final dx = col * cell + (r.isOdd ? cell / 2 : 0);
        final dy = r * cell;

        canvas.save();
        canvas.translate(dx, dy);
        // Sütunlar dönüşümlü AYNALANIR — motifin tekrarı gözle yakalanmaz.
        if ((col + r).isEven) {
          canvas.translate(cell, 0);
          canvas.scale(-1, 1);
        }
        canvas.save();
        canvas.translate(0, cell * 0.02);
        canvas.drawPath(motif, shadow);
        canvas.restore();
        canvas.drawPath(motif, light);
        canvas.restore();
      }
    }

    canvas.restore();

    // 3) VİNYET — kenarlar koyulaşır, göz masanın ortasında kalır.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.05),
          radius: 1.05,
          colors: [
            const Color(0x00000000),
            const Color(0x00000000),
            const Color(0xFF001A26).withValues(alpha: 0.42),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );
  }

  /// Bir hücrelik damask motifi: büyük kıvrım (scroll) + iki yaprak.
  ///
  /// Tüm koordinatlar 0..1 aralığında yazılıp [s] ile ölçeklenir; böylece
  /// motif her hücre boyunda aynı orana sahip olur.
  static Path _motifPath(double s) {
    final p = Path();
    double x(double v) => v * s;
    double y(double v) => v * s;

    // Ana kıvrım — dıştan içe sarılan bir spiral.
    p.moveTo(x(0.08), y(0.72));
    p.cubicTo(x(-0.02), y(0.34), x(0.28), y(0.02), x(0.56), y(0.14));
    p.cubicTo(x(0.82), y(0.25), x(0.78), y(0.58), x(0.52), y(0.58));
    p.cubicTo(x(0.34), y(0.58), x(0.31), y(0.37), x(0.47), y(0.34));

    // Sağ yaprak.
    p.moveTo(x(0.58), y(0.70));
    p.cubicTo(x(0.86), y(0.66), x(1.02), y(0.86), x(0.90), y(1.02));

    // Sol yaprak.
    p.moveTo(x(0.18), y(0.80));
    p.cubicTo(x(0.36), y(0.88), x(0.34), y(1.04), x(0.18), y(1.04));

    // Tepe tomurcuğu — motifin üst boşluğunu kapatan küçük yay.
    p.addArc(
      Rect.fromCircle(center: Offset(x(0.62), y(0.06)), radius: s * 0.07),
      math.pi * 0.15,
      math.pi * 1.3,
    );

    return p;
  }

  @override
  bool shouldRepaint(_DamaskPainter oldDelegate) =>
      oldDelegate.strength != strength;
}
