import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'okey_design.dart';

/// Lobi zemininin dekoru — tasarımın kimliğini veren, içeriğin ARKASINDA
/// kalan ince bir katman (bkz. [OkeyDesignDecor]).
///
/// ## Kurallar
///
///  * Dekor hiçbir zaman okunabilirliği bozmaz: çizgiler %4–%12 opaklıkta,
///    ekranın üst ve alt bantlarında yoğunlaşır, ortadaki içerikte söner.
///  * Tek bir [RepaintBoundary] arkasında boyanır; kaydırma onu yeniden
///    çizdirmez (içerik ayrı katmandadır).
///  * [design] açıkça verilir — admin önizleme kartları AKTİF olmayan
///    tasarımların dekorunu da çizer.
class OkeyDesignDecorLayer extends StatelessWidget {
  final OkeyDesign design;

  /// Önizlemelerde (küçük kart) desen adımları da küçülsün diye ölçek.
  final double scale;

  const OkeyDesignDecorLayer({super.key, required this.design, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: OkeyDesignDecorPainter(design: design, scale: scale),
        size: Size.infinite,
      ),
    );
  }
}

class OkeyDesignDecorPainter extends CustomPainter {
  final OkeyDesign design;
  final double scale;

  const OkeyDesignDecorPainter({required this.design, this.scale = 1});

  Color get _c => design.decorColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    switch (design.decor) {
      case OkeyDesignDecor.none:
        break;
      case OkeyDesignDecor.spotlight:
        _spotlight(canvas, size);
      case OkeyDesignDecor.quilt:
        _quilt(canvas, size);
      case OkeyDesignDecor.neonGrid:
        _neonGrid(canvas, size);
      case OkeyDesignDecor.cini:
        _cini(canvas, size);
      case OkeyDesignDecor.arabesque:
        _arabesque(canvas, size);
      case OkeyDesignDecor.waves:
        _waves(canvas, size);
    }
    canvas.restore();
  }

  /// Üstten aşağı sönen maske: desen üst bantta görünür, içerikte kaybolur.
  Shader _fadeDown(Size size, {double until = 0.42}) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
    stops: [0, until],
  ).createShader(Offset.zero & size);

  /// Deseni ayrı bir katmanda çizip [mask] ile söndürür.
  void _masked(Canvas canvas, Size size, Shader mask, void Function() draw) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    draw();
    canvas.drawRect(
      rect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = mask,
    );
    canvas.restore();
  }

  // --- KULÜP SPOTLARI ---------------------------------------------------------
  void _spotlight(Canvas canvas, Size size) {
    void pool(Offset center, double radius, double alpha) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _c.withValues(alpha: alpha),
              _c.withValues(alpha: alpha * 0.35),
              _c.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(rect),
      );
    }

    final w = size.width;
    pool(Offset(w * 0.15, -size.height * 0.02), w * 0.75, 0.10);
    pool(Offset(w * 0.92, size.height * 0.08), w * 0.6, 0.07);
    // Spotun yere düşen ince ışık konisi.
    final cone = Path()
      ..moveTo(w * 0.08, 0)
      ..lineTo(w * 0.24, 0)
      ..lineTo(w * 0.62, size.height * 0.55)
      ..lineTo(-w * 0.2, size.height * 0.55)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_c.withValues(alpha: 0.06), _c.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
  }

  // --- KADİFE KAPİTONE --------------------------------------------------------
  void _quilt(Canvas canvas, Size size) {
    final step = 46.0 * scale;
    final line = Paint()
      ..strokeWidth = 0.8
      ..color = _c.withValues(alpha: 0.07);
    final stud = Paint()..color = _c.withValues(alpha: 0.14);
    _masked(canvas, size, _fadeDown(size, until: 0.5), () {
      for (var x = -size.height; x < size.width + size.height; x += step) {
        canvas.drawLine(
          Offset(x, 0),
          Offset(x + size.height, size.height),
          line,
        );
        canvas.drawLine(
          Offset(x, 0),
          Offset(x - size.height, size.height),
          line,
        );
      }
      // Düğmeler çizgilerin kesiştiği yerlerde.
      for (var row = 0; row * step / 2 < size.height; row++) {
        final y = row * step / 2;
        final offset = row.isOdd ? step / 2 : 0.0;
        for (var x = offset; x < size.width + step; x += step) {
          canvas.drawCircle(Offset(x, y), 1.8 * scale, stud);
        }
      }
    });
  }

  // --- NEON IZGARA ------------------------------------------------------------
  void _neonGrid(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.74;
    final glow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_c.withValues(alpha: 0), _c.withValues(alpha: 0.12)],
      ).createShader(Rect.fromLTWH(0, horizon - 60 * scale, w, 60 * scale));
    canvas.drawRect(
      Rect.fromLTWH(0, horizon - 60 * scale, w, 60 * scale),
      glow,
    );

    final line = Paint()
      ..strokeWidth = 1
      ..color = _c.withValues(alpha: 0.16);
    canvas.drawLine(
      Offset(0, horizon),
      Offset(w, horizon),
      line..strokeWidth = 1.4,
    );
    line.strokeWidth = 0.8;
    // Ufka doğru sıklaşan yatay çizgiler.
    for (var i = 1; i < 12; i++) {
      final t = i / 12;
      final y = horizon + (h - horizon) * t * t;
      canvas.drawLine(
        Offset(0, y),
        Offset(w, y),
        line..color = _c.withValues(alpha: 0.05 + 0.10 * t),
      );
    }
    // Kaçış noktasına koşan dikey çizgiler.
    final vanish = Offset(w / 2, horizon);
    for (var i = -10; i <= 10; i++) {
      final bottomX = w / 2 + i * w * 0.14;
      canvas.drawLine(
        vanish,
        Offset(bottomX, h),
        line..color = _c.withValues(alpha: 0.09),
      );
    }
    // Üstte ince tarama çizgileri (CRT).
    _masked(canvas, size, _fadeDown(size, until: 0.3), () {
      final scan = Paint()
        ..strokeWidth = 1
        ..color = _c.withValues(alpha: 0.05);
      for (var y = 0.0; y < h * 0.3; y += 4 * scale) {
        canvas.drawLine(Offset(0, y), Offset(w, y), scan);
      }
    });
  }

  // --- İZNİK ÇİNİSİ -----------------------------------------------------------
  void _cini(Canvas canvas, Size size) {
    final step = 64.0 * scale;
    final outer = step * 0.36;
    final inner = outer * 0.7654;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round
      ..color = _c.withValues(alpha: 0.12);
    final fill = Paint()..color = _c.withValues(alpha: 0.035);
    final coral = Paint()..color = design.sectionLabel.withValues(alpha: 0.10);

    Path star(Offset c) {
      final p = Path();
      for (var i = 0; i < 16; i++) {
        final r = i.isEven ? outer : inner;
        final a = i * math.pi / 8;
        final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
      }
      return p..close();
    }

    _masked(canvas, size, _fadeDown(size, until: 0.48), () {
      for (var y = 0.0; y < size.height * 0.5 + step; y += step) {
        for (var x = 0.0; x < size.width + step; x += step) {
          final s = star(Offset(x, y));
          canvas.drawPath(s, fill);
          canvas.drawPath(s, stroke);
          canvas.drawCircle(Offset(x, y), 3.2 * scale, coral);
          // Aradaki baklava (haç) dolgusu.
          final c = Offset(x + step / 2, y + step / 2);
          final r = step * 0.11;
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - r)
              ..lineTo(c.dx + r, c.dy)
              ..lineTo(c.dx, c.dy + r)
              ..lineTo(c.dx - r, c.dy)
              ..close(),
            stroke,
          );
        }
      }
    });
    // Alt kenarda ince bir çini bordürü.
    final band = size.height - 6 * scale;
    canvas.drawLine(
      Offset(0, band),
      Offset(size.width, band),
      Paint()
        ..strokeWidth = 2 * scale
        ..color = _c.withValues(alpha: 0.10),
    );
  }

  // --- SARAY KAFESİ -------------------------------------------------------------
  void _arabesque(Canvas canvas, Size size) {
    final step = 56.0 * scale;
    final r = step / 2;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = _c.withValues(alpha: 0.10);
    final stud = Paint()..color = _c.withValues(alpha: 0.18);
    _masked(canvas, size, _fadeDown(size, until: 0.45), () {
      for (var y = 0.0; y < size.height * 0.45 + step; y += step) {
        for (var x = 0.0; x < size.width + step; x += step) {
          canvas.drawCircle(Offset(x, y), r, stroke);
          canvas.drawCircle(Offset(x + r, y + r), 1.6 * scale, stud);
        }
      }
    });
    // Üstte kemer silueti: ekranın tepesini çerçeveleyen tek bir sivri kemer.
    final w = size.width;
    final arch = Path()
      ..moveTo(0, size.height * 0.2)
      ..quadraticBezierTo(w * 0.06, 0, w * 0.5, -size.height * 0.02)
      ..quadraticBezierTo(w * 0.94, 0, w, size.height * 0.2);
    canvas.drawPath(
      arch,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * scale
        ..color = _c.withValues(alpha: 0.16),
    );
  }

  // --- EGE DALGALARI ----------------------------------------------------------
  void _waves(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Güneş: sağ üstte yumuşak sıcak bir daire.
    final sunCenter = Offset(w * 0.86, h * 0.07);
    final sunR = w * 0.32;
    canvas.drawCircle(
      sunCenter,
      sunR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            design.accent.withValues(alpha: 0.22),
            design.accent.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: sunCenter, radius: sunR)),
    );
    // Alt bantta üst üste dalga çizgileri.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4 * scale;
    final wave = 120.0 * scale;
    final amp = 7.0 * scale;
    for (var i = 0; i < 6; i++) {
      final y = h * 0.78 + i * 18 * scale;
      final shift = i.isOdd ? wave / 2 : 0.0;
      final path = Path()..moveTo(-wave, y);
      for (var x = -wave; x <= w + wave; x += 6) {
        path.lineTo(x, y + amp * math.sin((x + shift) / wave * 2 * math.pi));
      }
      canvas.drawPath(
        path,
        stroke..color = _c.withValues(alpha: 0.05 + i * 0.018),
      );
    }
  }

  @override
  bool shouldRepaint(OkeyDesignDecorPainter old) =>
      old.design.key != design.key || old.scale != scale;
}
