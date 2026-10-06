// Hazır PROFİL ARKA PLANLARINI üretir (test DEĞİL, bir üretim aracı) — Görev 2.7.
//
//   $env:GEN_PROFILE_BACKGROUNDS='1'; flutter test test/tools/generate_profile_backgrounds_test.dart
//   python scripts/finalize_profile_backgrounds.py
//
// Çıktı `build/profile_backgrounds/bg_NN.png` (1600×900, 16:9 kapak oranı).
// Python betiği bunları JPEG'e ve 480×270 küçük resimlere çevirir; dosyalar
// Supabase Storage'daki `profile-backgrounds` kovasına yüklenir ve
// `profile_background_presets` tablosu (göç 20260928000001) onları listeler.
//
// APPEND-ONLY: kod (`bg_NN`) = sıra; kullanıcıların kapağı dosya URL'sine
// bağlı olduğundan sıra değişmez, yeni arka plan yalnızca SONA eklenir.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const double _w = 1600;
const double _h = 900;

typedef BackgroundPainter = void Function(Canvas c, math.Random r);

class BackgroundSpec {
  const BackgroundSpec(this.name, this.category, this.paint);
  final String name;
  final String category;
  final BackgroundPainter paint;
}

Color _hex(int v) => Color(0xFF000000 | v);

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0.0, 1.0))!;

Color _alpha(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));

void _fillGradient(Canvas c, List<Color> colors, {Alignment begin = Alignment.topCenter, Alignment end = Alignment.bottomCenter, List<double>? stops}) {
  const rect = Rect.fromLTWH(0, 0, _w, _h);
  c.drawRect(
    rect,
    Paint()..shader = LinearGradient(begin: begin, end: end, colors: colors, stops: stops).createShader(rect),
  );
}

void _glow(Canvas c, Offset center, double radius, Color color, {double strength = 1}) {
  final rect = Rect.fromCircle(center: center, radius: radius);
  c.drawCircle(
    center,
    radius,
    Paint()
      ..shader = RadialGradient(
        colors: [_alpha(color, 0.9 * strength), _alpha(color, 0.35 * strength), _alpha(color, 0)],
        stops: const [0, 0.45, 1],
      ).createShader(rect),
  );
}

/// Pürüzsüz tepe çizgisi: rastgele sinüslerin toplamı.
List<double> _ridge(math.Random r, {required double base, required double amp, int waves = 4, double jag = 0}) {
  final phases = List.generate(waves, (_) => r.nextDouble() * math.pi * 2);
  final freqs = List.generate(waves, (i) => (i + 1) * (0.6 + r.nextDouble() * 0.9));
  final amps = List.generate(waves, (i) => amp / (i + 1) * (0.6 + r.nextDouble() * 0.6));
  return List.generate(161, (i) {
    final x = i / 160;
    var y = base;
    for (var k = 0; k < waves; k++) {
      y += amps[k] * math.sin(x * math.pi * 2 * freqs[k] + phases[k]);
    }
    if (jag > 0) y += (r.nextDouble() - 0.5) * jag;
    return y;
  });
}

Path _ridgePath(List<double> ys, {bool smooth = true}) {
  final p = Path()..moveTo(0, _h);
  p.lineTo(0, ys.first);
  for (var i = 1; i < ys.length; i++) {
    final x = _w * i / (ys.length - 1);
    if (smooth) {
      final px = _w * (i - 1) / (ys.length - 1);
      p.quadraticBezierTo(px, ys[i - 1], (px + x) / 2, (ys[i - 1] + ys[i]) / 2);
    } else {
      p.lineTo(x, ys[i]);
    }
  }
  p
    ..lineTo(_w, ys.last)
    ..lineTo(_w, _h)
    ..close();
  return p;
}

void _stars(Canvas c, math.Random r, {int count = 260, double maxY = _h, double bright = 1}) {
  final small = <Offset>[];
  for (var i = 0; i < count; i++) {
    small.add(Offset(r.nextDouble() * _w, r.nextDouble() * maxY));
  }
  c.drawPoints(
    ui.PointMode.points,
    small,
    Paint()
      ..color = _alpha(const Color(0xFFFFFFFF), 0.75 * bright)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round,
  );
  for (var i = 0; i < count ~/ 14; i++) {
    final o = Offset(r.nextDouble() * _w, r.nextDouble() * maxY * 0.9);
    final s = 1.5 + r.nextDouble() * 2.5;
    c.drawCircle(o, s * 4, Paint()..color = _alpha(const Color(0xFFBFD7FF), 0.10 * bright)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    c.drawCircle(o, s, Paint()..color = _alpha(const Color(0xFFFFFFFF), 0.95 * bright));
  }
}

void _grain(Canvas c, math.Random r) {
  final light = <Offset>[];
  final dark = <Offset>[];
  for (var i = 0; i < 26000; i++) {
    (i.isEven ? light : dark).add(Offset(r.nextDouble() * _w, r.nextDouble() * _h));
  }
  c.drawPoints(ui.PointMode.points, light, Paint()..color = const Color(0x0DFFFFFF)..strokeWidth = 1.4);
  c.drawPoints(ui.PointMode.points, dark, Paint()..color = const Color(0x0D000000)..strokeWidth = 1.4);
}

void _vignette(Canvas c, {double strength = 0.28}) {
  const rect = Rect.fromLTWH(0, 0, _w, _h);
  c.drawRect(
    rect,
    Paint()
      ..shader = RadialGradient(
        radius: 0.95,
        colors: [const Color(0x00000000), _alpha(const Color(0xFF000000), strength)],
        stops: const [0.55, 1],
      ).createShader(rect),
  );
}

// ------------------------------------------------------------------ temalar

/// 1) Yumuşak gradyan (mesh): büyük, yumuşak renk lekeleri.
BackgroundPainter _mesh(List<int> palette) => (c, r) {
  final colors = palette.map(_hex).toList();
  _fillGradient(c, [colors.first, _mix(colors.first, colors[1], 0.5)], begin: Alignment.topLeft, end: Alignment.bottomRight);
  for (var i = 0; i < 7; i++) {
    final color = colors[i % colors.length];
    final center = Offset(r.nextDouble() * _w, r.nextDouble() * _h);
    final radius = 380 + r.nextDouble() * 520;
    final rect = Rect.fromCircle(center: center, radius: radius);
    c.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(colors: [_alpha(color, 0.85), _alpha(color, 0)]).createShader(rect),
    );
  }
  // İnce parıltılı dalga çizgileri
  for (var k = 0; k < 3; k++) {
    final y0 = _h * (0.3 + 0.2 * k);
    final path = Path()..moveTo(-50, y0);
    for (var x = 0.0; x <= _w + 100; x += 100) {
      path.quadraticBezierTo(x + 50, y0 + math.sin(x / 260 + k) * 60, x + 100, y0 + math.cos(x / 300 + k) * 50);
    }
    c.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.2..color = const Color(0x22FFFFFF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2));
  }
};

/// 2) Gün batımı: gökyüzü, güneş ve katmanlı tepeler.
BackgroundPainter _sunset(List<int> sky, int sun, List<int> hills) => (c, r) {
  _fillGradient(c, sky.map(_hex).toList());
  final sunCenter = Offset(_w * (0.3 + r.nextDouble() * 0.4), _h * 0.58);
  _glow(c, sunCenter, 520, _hex(sun), strength: 0.8);
  c.drawCircle(sunCenter, 92, Paint()..color = _mix(_hex(sun), const Color(0xFFFFFFFF), 0.45));
  // birkaç uzun bulut
  for (var i = 0; i < 5; i++) {
    final y = _h * (0.15 + r.nextDouble() * 0.3);
    final x = r.nextDouble() * _w;
    final rect = Rect.fromCenter(center: Offset(x, y), width: 360 + r.nextDouble() * 420, height: 26 + r.nextDouble() * 22);
    c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(30)), Paint()..color = const Color(0x33FFFFFF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
  }
  final layers = hills.length;
  for (var k = 0; k < layers; k++) {
    final base = _h * (0.62 + 0.09 * k);
    final ys = _ridge(r, base: base, amp: 70 - k * 8, waves: 3);
    c.drawPath(_ridgePath(ys), Paint()..color = _hex(hills[k]));
    // katmanlar arası pus
    final rect = Rect.fromLTWH(0, base - 80, _w, 160);
    c.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_alpha(_hex(sun), 0), _alpha(_hex(sun), 0.10), _alpha(_hex(sun), 0)]).createShader(rect));
  }
};

/// 3) Dağlar: atmosferik derinlikle sivri sıradağlar.
BackgroundPainter _mountains(List<int> sky, List<int> layers, {bool snow = false, int? sun}) => (c, r) {
  _fillGradient(c, sky.map(_hex).toList());
  if (sun != null) _glow(c, Offset(_w * 0.72, _h * 0.26), 300, _hex(sun), strength: 0.7);
  for (var k = 0; k < layers.length; k++) {
    final base = _h * (0.42 + 0.11 * k);
    final ys = _ridge(r, base: base, amp: 120 - k * 14, waves: 6, jag: 10.0 + k * 2);
    final path = _ridgePath(ys, smooth: false);
    final color = _hex(layers[k]);
    c.drawPath(path, Paint()..color = color);
    if (snow && k < 2) {
      // tepelere kar: çizginin hemen altını açık renge boyayan kırpılmış şerit
      c.save();
      c.clipPath(path);
      final top = ys.reduce(math.min);
      c.drawRect(Rect.fromLTWH(0, top - 10, _w, (base - top) * 0.55 + 10), Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xE6FFFFFF), Color(0x00FFFFFF)]).createShader(Rect.fromLTWH(0, top, _w, (base - top) * 0.8)));
      c.restore();
    }
    // sis
    final mist = Rect.fromLTWH(0, base + 10, _w, 170);
    c.drawRect(mist, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_alpha(_hex(sky.last), 0), _alpha(_hex(sky.last), 0.28), _alpha(_hex(sky.last), 0)]).createShader(mist));
  }
};

/// 4) Gece gökyüzü: yıldızlar, samanyolu, ay ve ufuk silueti.
BackgroundPainter _night(List<int> sky, {bool milkyWay = false, double moon = 0, int ground = 0x05070F}) => (c, r) {
  _fillGradient(c, sky.map(_hex).toList());
  if (milkyWay) {
    c.save();
    c.translate(_w / 2, _h / 2);
    c.rotate(-0.42);
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: _w * 1.5, height: 260), Paint()..color = const Color(0x2ED8C8FF)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 70));
    c.drawOval(Rect.fromCenter(center: Offset.zero, width: _w * 1.2, height: 110), Paint()..color = const Color(0x22FFE9D6)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40));
    final pts = <Offset>[];
    for (var i = 0; i < 2600; i++) {
      final x = (r.nextDouble() - 0.5) * _w * 1.4;
      final y = (r.nextDouble() + r.nextDouble() + r.nextDouble() - 1.5) * 120;
      pts.add(Offset(x, y));
    }
    c.drawPoints(ui.PointMode.points, pts, Paint()..color = const Color(0x99FFFFFF)..strokeWidth = 1.6..strokeCap = StrokeCap.round);
    c.restore();
  }
  _stars(c, r, count: 320, maxY: _h * 0.8);
  if (moon > 0) {
    final center = Offset(_w * 0.78, _h * 0.24);
    _glow(c, center, 260, const Color(0xFFDDE7FF), strength: 0.55);
    if (moon < 1) {
      // hilal: ayın dairesinden kaydırılmış dairenin FARKI
      final crescent = Path.combine(
        PathOperation.difference,
        Path()..addOval(Rect.fromCircle(center: center, radius: 64)),
        Path()..addOval(Rect.fromCircle(center: center + Offset(64 * (1 - moon) + 22, -16), radius: 60)),
      );
      c.drawPath(crescent, Paint()..color = const Color(0xFFF4F1E8));
    } else {
      c.drawCircle(center, 64, Paint()..color = const Color(0xFFF4F1E8));
      for (var i = 0; i < 6; i++) {
        c.drawCircle(center + Offset((r.nextDouble() - 0.5) * 80, (r.nextDouble() - 0.5) * 80), 6 + r.nextDouble() * 10, Paint()..color = const Color(0x14000000));
      }
    }
  }
  final ys = _ridge(r, base: _h * 0.86, amp: 40, waves: 4);
  c.drawPath(_ridgePath(ys), Paint()..color = _hex(ground));
};

/// 5) Kuzey ışıkları: bulanık ışık perdeleri, dikey ışınlar, çam siluetleri.
BackgroundPainter _aurora(List<int> sky, List<int> lights) => (c, r) {
  _fillGradient(c, sky.map(_hex).toList());
  _stars(c, r, count: 220, maxY: _h * 0.7, bright: 0.8);
  for (var k = 0; k < lights.length; k++) {
    final color = _hex(lights[k]);
    final y0 = _h * (0.28 + 0.12 * k);
    final amp = 70 + r.nextDouble() * 60;
    final phase = r.nextDouble() * math.pi * 2;
    final center = Path()..moveTo(-100, y0);
    for (var x = -100.0; x <= _w + 100; x += 40) {
      center.lineTo(x, y0 + math.sin(x / 260 + phase) * amp + math.sin(x / 90 + phase * 2) * 18);
    }
    c.drawPath(center, Paint()..style = PaintingStyle.stroke..strokeWidth = 150..color = _alpha(color, 0.22)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60));
    c.drawPath(center, Paint()..style = PaintingStyle.stroke..strokeWidth = 46..color = _alpha(color, 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
    // dikey ışınlar
    for (var i = 0; i < 90; i++) {
      final x = r.nextDouble() * _w;
      final y = y0 + math.sin(x / 260 + phase) * amp;
      final len = 60 + r.nextDouble() * 180;
      final rect = Rect.fromLTWH(x, y - len, 5 + r.nextDouble() * 9, len + 30);
      c.drawRect(rect, Paint()..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [_alpha(color, 0.30), _alpha(color, 0)]).createShader(rect)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
  }
  // çam ağaçları silueti
  final ground = _ridge(r, base: _h * 0.9, amp: 18, waves: 3);
  final paint = Paint()..color = const Color(0xFF03060C);
  c.drawPath(_ridgePath(ground), paint);
  for (var i = 0; i < 46; i++) {
    final x = r.nextDouble() * _w;
    final baseY = ground[(x / _w * 160).round().clamp(0, 160)];
    final h = 60 + r.nextDouble() * 130;
    final wHalf = h * 0.18;
    final tree = Path()
      ..moveTo(x, baseY - h)
      ..lineTo(x - wHalf, baseY + 4)
      ..lineTo(x + wHalf, baseY + 4)
      ..close();
    c.drawPath(tree, paint);
  }
};

/// 6) Katmanlı dalgalar (düz, modern).
BackgroundPainter _waves(List<int> bg, List<int> bands) => (c, r) {
  _fillGradient(c, bg.map(_hex).toList());
  for (var k = 0; k < bands.length; k++) {
    final base = _h * (0.30 + 0.12 * k);
    final phase = r.nextDouble() * math.pi * 2;
    final amp = 42 + r.nextDouble() * 34;
    final path = Path()..moveTo(0, _h);
    for (var x = 0.0; x <= _w; x += 16) {
      path.lineTo(x, base + math.sin(x / (230 + k * 25) + phase) * amp + math.sin(x / 97 + phase) * 9);
    }
    path
      ..lineTo(_w, _h)
      ..close();
    c.drawShadow(path, const Color(0xFF000000), 10, false);
    final color = _hex(bands[k]);
    final rect = Rect.fromLTWH(0, base - amp, _w, _h - base + amp);
    c.drawPath(path, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_mix(color, const Color(0xFFFFFFFF), 0.12), color]).createShader(rect));
  }
};

/// 7) Bokeh: bulanık ışık daireleri.
BackgroundPainter _bokeh(List<int> bg, List<int> lights) => (c, r) {
  _fillGradient(c, bg.map(_hex).toList(), begin: Alignment.topLeft, end: Alignment.bottomRight);
  for (var i = 0; i < 110; i++) {
    final color = _hex(lights[r.nextInt(lights.length)]);
    final radius = 10 + math.pow(r.nextDouble(), 2.2) * 150;
    final center = Offset(r.nextDouble() * _w, r.nextDouble() * _h);
    final blur = 2 + radius * 0.10;
    c.drawCircle(center, radius.toDouble(), Paint()..color = _alpha(color, 0.10 + r.nextDouble() * 0.28)..maskFilter = MaskFilter.blur(BlurStyle.normal, blur));
    if (radius > 50) {
      c.drawCircle(center, radius.toDouble(), Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = _alpha(color, 0.18)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
  }
  _vignette(c, strength: 0.35);
};

/// 8) Geometrik low-poly.
BackgroundPainter _lowPoly(List<int> palette) => (c, r) {
  const cols = 18;
  const rows = 10;
  final pts = List.generate(rows + 1, (j) => List.generate(cols + 1, (i) {
    final edgeX = i == 0 || i == cols;
    final edgeY = j == 0 || j == rows;
    final jx = edgeX ? 0.0 : (r.nextDouble() - 0.5) * _w / cols * 0.7;
    final jy = edgeY ? 0.0 : (r.nextDouble() - 0.5) * _h / rows * 0.7;
    return Offset(_w * i / cols + jx, _h * j / rows + jy);
  }));
  final colors = palette.map(_hex).toList();
  Color at(Offset p) {
    final t = ((p.dx / _w) * 0.65 + (p.dy / _h) * 0.35).clamp(0.0, 1.0) * (colors.length - 1);
    final i = t.floor().clamp(0, colors.length - 2);
    return _mix(colors[i], colors[i + 1], t - i);
  }

  for (var j = 0; j < rows; j++) {
    for (var i = 0; i < cols; i++) {
      final a = pts[j][i], b = pts[j][i + 1], d = pts[j + 1][i], e = pts[j + 1][i + 1];
      final tris = (i + j).isEven ? [[a, b, e], [a, e, d]] : [[a, b, d], [b, e, d]];
      for (final t in tris) {
        final centroid = Offset((t[0].dx + t[1].dx + t[2].dx) / 3, (t[0].dy + t[1].dy + t[2].dy) / 3);
        final shade = (r.nextDouble() - 0.5) * 0.16;
        final base = at(centroid);
        final color = shade >= 0 ? _mix(base, const Color(0xFFFFFFFF), shade) : _mix(base, const Color(0xFF000000), -shade);
        final path = Path()
          ..moveTo(t[0].dx, t[0].dy)
          ..lineTo(t[1].dx, t[1].dy)
          ..lineTo(t[2].dx, t[2].dy)
          ..close();
        c.drawPath(path, Paint()..color = color);
        c.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = _alpha(color, 0.9));
      }
    }
  }
  _vignette(c, strength: 0.22);
};

/// 9) Mermer: bulutsu doku + ince damarlar.
BackgroundPainter _marble(int base, List<int> clouds, int vein, {double veinAlpha = 0.85}) => (c, r) {
  c.drawRect(const Rect.fromLTWH(0, 0, _w, _h), Paint()..color = _hex(base));
  // Tüm doku çapraz akar (gerçek mermer damarları yatay değildir).
  c.save();
  c.translate(_w / 2, _h / 2);
  c.rotate(-0.38);
  c.translate(-_w * 0.75, -_h * 0.9);

  /// Uzun, yumuşak akış çizgisi: seyrek kontrol noktaları, küçük sapma.
  Path flow(double x0, double y0, double length, double spread) {
    final p = Path()..moveTo(x0, y0);
    var y = y0;
    for (var x = x0; x < x0 + length; x += 340) {
      final ny = y + (r.nextDouble() - 0.5) * spread;
      p.cubicTo(x + 110, y + (r.nextDouble() - 0.5) * spread * 0.4, x + 230, ny + (r.nextDouble() - 0.5) * spread * 0.4, x + 340, ny);
      y = ny;
    }
    return p;
  }

  for (var i = 0; i < 30; i++) {
    final color = _hex(clouds[r.nextInt(clouds.length)]);
    c.drawPath(
      flow(-200, r.nextDouble() * _h * 1.8, _w * 1.8, 160),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 60 + r.nextDouble() * 160
        ..color = _alpha(color, 0.10 + r.nextDouble() * 0.16)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 30 + r.nextDouble() * 40),
    );
  }
  final veinColor = _hex(vein);
  for (var i = 0; i < 6; i++) {
    final y0 = _h * 0.2 + r.nextDouble() * _h * 1.4;
    final main = flow(-200, y0, _w * 1.8, 120);
    final width = 1.2 + r.nextDouble() * 2.4;
    c.drawPath(main, Paint()..style = PaintingStyle.stroke..strokeWidth = width * 5..color = _alpha(veinColor, 0.08)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    c.drawPath(main, Paint()..style = PaintingStyle.stroke..strokeWidth = width..color = _alpha(veinColor, veinAlpha * (0.55 + r.nextDouble() * 0.45))..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.7));
    // İnce dallar: ana damardan ayrılıp sönen kısa çizgiler
    for (var b = 0; b < 3; b++) {
      final bx = r.nextDouble() * _w * 1.5;
      final by = y0 + (r.nextDouble() - 0.5) * 160;
      final branch = Path()
        ..moveTo(bx, by)
        ..quadraticBezierTo(bx + 120 + r.nextDouble() * 120, by + (r.nextDouble() - 0.5) * 140, bx + 260 + r.nextDouble() * 200, by + (r.nextDouble() - 0.5) * 220);
      c.drawPath(branch, Paint()..style = PaintingStyle.stroke..strokeWidth = width * 0.5..color = _alpha(veinColor, veinAlpha * 0.45)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8));
    }
  }
  c.restore();
  _vignette(c, strength: 0.12);
};

/// 10) Minimal şekiller: pastel zemin, dengeli yerleşimli büyük formlar
/// (yumuşak gölge), nokta ızgarası ve ince yay. [layout] 0-4 hazır yerleşim.
BackgroundPainter _minimal(int bg, List<int> shapes, int layout) => (c, r) {
  c.drawRect(const Rect.fromLTWH(0, 0, _w, _h), Paint()..color = _hex(bg));
  Color col(int i) => _hex(shapes[i % shapes.length]);

  void shaped(Path path, Color color) {
    c.drawShadow(path, const Color(0xFF000000), 16, false);
    c.drawPath(path, Paint()..color = color);
  }

  Path circle(double x, double y, double radius) => Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: radius));
  Path half(double x, double y, double radius) => Path()
    ..addArc(Rect.fromCircle(center: Offset(x, y), radius: radius), math.pi, math.pi)
    ..close();
  Path pill(double x, double y, double w, double h) => Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x, y), width: w, height: h), Radius.circular(math.min(w, h) / 2)));
  void arch(double x, double y, double radius, double stroke, Color color) {
    final rect = Rect.fromCircle(center: Offset(x, y), radius: radius);
    final p = Path()..addArc(rect, math.pi, math.pi);
    c.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke + 8..color = const Color(0x22000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    c.drawPath(p, Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.butt..color = color);
  }

  void dots(double x, double y) {
    final pts = <Offset>[
      for (var i = 0; i < 7; i++)
        for (var j = 0; j < 4; j++) Offset(x + i * 26, y + j * 26),
    ];
    c.drawPoints(ui.PointMode.points, pts, Paint()..color = _alpha(col(shapes.length - 1), 0.5)..strokeWidth = 7..strokeCap = StrokeCap.round);
  }

  void line(double x, double y, double radius, double start) {
    c.drawArc(Rect.fromCircle(center: Offset(x, y), radius: radius), start, 2.2, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = _alpha(col(0), 0.85));
  }

  switch (layout) {
    case 0: // köşede büyük güneş, altta yarım daire, ortada kapsül
      shaped(circle(_w * 0.84, _h * 0.12, 250), col(0));
      shaped(half(_w * 0.2, _h, 260), col(1));
      shaped(pill(_w * 0.47, _h * 0.6, 120, 300), col(2));
      shaped(circle(_w * 0.63, _h * 0.78, 56), col(3));
      dots(_w * 0.08, _h * 0.12);
      line(_w * 0.66, _h * 0.3, 150, 0.6);
    case 1: // iç içe kemerler ve güneş
      arch(_w * 0.32, _h * 1.02, 300, 70, col(0));
      arch(_w * 0.32, _h * 1.02, 190, 60, col(1));
      shaped(circle(_w * 0.32, _h * 0.78, 58), col(2));
      shaped(circle(_w * 0.78, _h * 0.3, 140), col(3));
      shaped(pill(_w * 0.66, _h * 0.72, 90, 220), col(1));
      dots(_w * 0.7, _h * 0.08);
    case 2: // İskandinav: taş gibi yuvarlak formlar, sakin
      shaped(pill(_w * 0.72, _h * 0.58, 520, 300), col(0));
      shaped(circle(_w * 0.56, _h * 0.72, 150), col(1));
      shaped(circle(_w * 0.86, _h * 0.26, 90), col(2));
      arch(_w * 0.22, _h * 0.98, 150, 44, col(3));
      dots(_w * 0.1, _h * 0.14);
      line(_w * 0.4, _h * 0.3, 120, 3.6);
    case 3: // Memphis: canlı renkler, dağınık ama dengeli
      shaped(circle(_w * 0.12, _h * 0.22, 110), col(0));
      shaped(pill(_w * 0.36, _h * 0.72, 300, 110), col(1));
      shaped(half(_w * 0.62, _h * 0.44, 150), col(2));
      arch(_w * 0.86, _h * 0.9, 170, 50, col(3));
      shaped(circle(_w * 0.82, _h * 0.2, 48), col(4));
      dots(_w * 0.5, _h * 0.08);
      line(_w * 0.2, _h * 0.8, 90, 4.2);
    default: // kum ve güneş: ufuk, güneş, tepe
      shaped(circle(_w * 0.64, _h * 0.4, 170), col(0));
      shaped(half(_w * 0.36, _h * 1.05, 420), col(1));
      shaped(half(_w * 0.86, _h * 1.08, 300), col(2));
      arch(_w * 0.64, _h * 0.4, 240, 10, col(3));
      dots(_w * 0.08, _h * 0.1);
  }
};

// ------------------------------------------------------------------ katalog

/// 50 arka plan: 10 tema × 5. Sıra = dosya numarası (1'den); YALNIZ SONA EKLE.
final List<BackgroundSpec> kProfileBackgrounds = [
  // Yumuşak Gradyan
  BackgroundSpec('Pastel Rüya', 'Gradyan', _mesh([0xFFD6E8, 0xC9E4FF, 0xE8D5FF, 0xFFF1C9, 0xFBCFE8])),
  BackgroundSpec('Okyanus Esintisi', 'Gradyan', _mesh([0x0EA5E9, 0x22D3EE, 0x6366F1, 0xA5F3FC])),
  BackgroundSpec('Şeftali Sabahı', 'Gradyan', _mesh([0xFDBA74, 0xFDA4AF, 0xFEF3C7, 0xFB7185])),
  BackgroundSpec('Orman Nefesi', 'Gradyan', _mesh([0x34D399, 0x059669, 0xA7F3D0, 0x0F766E])),
  BackgroundSpec('Gece Moru', 'Gradyan', _mesh([0x1E1B4B, 0x7C3AED, 0xDB2777, 0x312E81])),
  // Gün Batımı
  BackgroundSpec('Pembe Şafak', 'Gün Batımı', _sunset([0x4C1D95, 0xDB2777, 0xFDBA74], 0xFFE4E6, [0x9D174D, 0x831843, 0x500724])),
  BackgroundSpec('Turuncu Akşam', 'Gün Batımı', _sunset([0x1E3A8A, 0xF97316, 0xFDE68A], 0xFFF7ED, [0xC2410C, 0x7C2D12, 0x431407])),
  BackgroundSpec('Mor Alacakaranlık', 'Gün Batımı', _sunset([0x1E1B4B, 0x6D28D9, 0xF472B6], 0xFBCFE8, [0x5B21B6, 0x3B0764, 0x1E1B4B])),
  BackgroundSpec('Altın Saat', 'Gün Batımı', _sunset([0x7C2D12, 0xF59E0B, 0xFEF3C7], 0xFFFBEB, [0xB45309, 0x78350F, 0x451A03])),
  BackgroundSpec('Çöl Günbatımı', 'Gün Batımı', _sunset([0x831843, 0xEA580C, 0xFCD34D], 0xFEF9C3, [0xD97706, 0xB45309, 0x92400E, 0x78350F])),
  // Dağlar
  BackgroundSpec('Mavi Sabah', 'Dağlar', _mountains([0xBAE6FD, 0xE0F2FE], [0x93C5FD, 0x60A5FA, 0x2563EB, 0x1E3A8A, 0x172554], sun: 0xFFFFFF)),
  BackgroundSpec('Sisli Vadi', 'Dağlar', _mountains([0xD1FAE5, 0xF0FDF4], [0xA7F3D0, 0x6EE7B7, 0x10B981, 0x047857, 0x064E3B])),
  BackgroundSpec('Lavanta Tepeler', 'Dağlar', _mountains([0xEDE9FE, 0xFCE7F3], [0xDDD6FE, 0xC4B5FD, 0xA78BFA, 0x7C3AED, 0x4C1D95], sun: 0xFDE68A)),
  BackgroundSpec('Karlı Zirveler', 'Dağlar', _mountains([0x93C5FD, 0xE0F2FE], [0x94A3B8, 0x64748B, 0x475569, 0x334155, 0x1E293B], snow: true)),
  BackgroundSpec('Sonbahar Dağları', 'Dağlar', _mountains([0xFED7AA, 0xFFF7ED], [0xFDBA74, 0xF97316, 0xC2410C, 0x9A3412, 0x431407], sun: 0xFFF7ED)),
  // Gece Gökyüzü
  BackgroundSpec('Yıldızlı Gece', 'Gece', _night([0x020617, 0x1E1B4B, 0x312E81])),
  BackgroundSpec('Samanyolu', 'Gece', _night([0x05060F, 0x1E1535, 0x3B2A5A], milkyWay: true)),
  BackgroundSpec('Dolunay', 'Gece', _night([0x0B1026, 0x1E3A8A, 0x3B82F6], moon: 1, ground: 0x020617)),
  BackgroundSpec('Hilal', 'Gece', _night([0x0F172A, 0x312E81, 0x6D28D9], moon: 0.35)),
  BackgroundSpec('Mor Gece', 'Gece', _night([0x13052E, 0x4C1D95, 0xBE185D], milkyWay: true, ground: 0x0C0418)),
  // Kuzey Işıkları
  BackgroundSpec('Zümrüt Aurora', 'Kuzey Işıkları', _aurora([0x020617, 0x042F2E, 0x0F172A], [0x34D399, 0x22D3EE])),
  BackgroundSpec('Mor Aurora', 'Kuzey Işıkları', _aurora([0x0B0320, 0x2E1065, 0x0F172A], [0xA78BFA, 0xF472B6])),
  BackgroundSpec('Buz Aurora', 'Kuzey Işıkları', _aurora([0x020617, 0x0C4A6E, 0x082F49], [0x7DD3FC, 0xA5F3FC, 0x34D399])),
  BackgroundSpec('Gül Aurora', 'Kuzey Işıkları', _aurora([0x1A0515, 0x4A044E, 0x1E1B4B], [0xF9A8D4, 0xFB7185])),
  BackgroundSpec('Kutup Gecesi', 'Kuzey Işıkları', _aurora([0x000000, 0x0B1120, 0x1E293B], [0x4ADE80, 0xA3E635, 0x22D3EE])),
  // Dalgalar
  BackgroundSpec('Turkuaz Dalgalar', 'Dalgalar', _waves([0xCFFAFE, 0xECFEFF], [0x67E8F9, 0x22D3EE, 0x06B6D4, 0x0891B2, 0x155E75])),
  BackgroundSpec('Gece Denizi', 'Dalgalar', _waves([0x0F172A, 0x1E293B], [0x1E3A8A, 0x1E40AF, 0x1D4ED8, 0x172554, 0x0B1026])),
  BackgroundSpec('Mercan Dalgaları', 'Dalgalar', _waves([0xFFE4E6, 0xFFF1F2], [0xFDA4AF, 0xFB7185, 0xF43F5E, 0xE11D48, 0x9F1239])),
  BackgroundSpec('Buzul', 'Dalgalar', _waves([0xF8FAFC, 0xE2E8F0], [0xE0F2FE, 0xBAE6FD, 0x7DD3FC, 0x38BDF8, 0x0284C7])),
  BackgroundSpec('Lavanta Dalgası', 'Dalgalar', _waves([0xFAF5FF, 0xF3E8FF], [0xE9D5FF, 0xD8B4FE, 0xC084FC, 0xA855F7, 0x7E22CE])),
  // Bokeh
  BackgroundSpec('Altın Bokeh', 'Işıklar', _bokeh([0x1C1917, 0x292524, 0x451A03], [0xFBBF24, 0xF59E0B, 0xFDE68A, 0xFFFBEB])),
  BackgroundSpec('Şehir Işıkları', 'Işıklar', _bokeh([0x0F172A, 0x1E1B4B, 0x0C0A09], [0x60A5FA, 0xF472B6, 0xFBBF24, 0xA78BFA])),
  BackgroundSpec('Pembe Bokeh', 'Işıklar', _bokeh([0x500724, 0x831843, 0x1E1B4B], [0xF9A8D4, 0xFBCFE8, 0xF472B6])),
  BackgroundSpec('Mavi Işıltı', 'Işıklar', _bokeh([0x020617, 0x0C4A6E, 0x172554], [0x7DD3FC, 0x38BDF8, 0xBAE6FD, 0xE0F2FE])),
  BackgroundSpec('Rengarenk', 'Işıklar', _bokeh([0x111827, 0x1F2937, 0x0F172A], [0xF87171, 0xFBBF24, 0x34D399, 0x60A5FA, 0xC084FC])),
  // Geometrik
  BackgroundSpec('Kristal Mavi', 'Geometrik', _lowPoly([0x0C4A6E, 0x0284C7, 0x38BDF8, 0xBAE6FD])),
  BackgroundSpec('Gün Batımı Poligon', 'Geometrik', _lowPoly([0x7C2D12, 0xEA580C, 0xF472B6, 0x7C3AED])),
  BackgroundSpec('Zümrüt', 'Geometrik', _lowPoly([0x022C22, 0x047857, 0x10B981, 0xA7F3D0])),
  BackgroundSpec('Ametist', 'Geometrik', _lowPoly([0x2E1065, 0x6D28D9, 0xA78BFA, 0xF5D0FE])),
  BackgroundSpec('Kömür', 'Geometrik', _lowPoly([0x0A0A0A, 0x262626, 0x525252, 0x737373])),
  // Mermer
  BackgroundSpec('Beyaz Mermer', 'Mermer', _marble(0xF5F5F4, [0xE7E5E4, 0xD6D3D1, 0xFFFFFF], 0xC8A45C)),
  BackgroundSpec('Siyah Mermer', 'Mermer', _marble(0x0C0A09, [0x292524, 0x1C1917, 0x44403C], 0xD4AF37)),
  BackgroundSpec('Gül Mermer', 'Mermer', _marble(0xFCE7F3, [0xFBCFE8, 0xF9A8D4, 0xFFFFFF], 0xB76E79)),
  BackgroundSpec('Yeşim', 'Mermer', _marble(0x064E3B, [0x047857, 0x065F46, 0x10B981], 0xECFDF5, veinAlpha: 0.6)),
  BackgroundSpec('Lacivert Mermer', 'Mermer', _marble(0x0B1026, [0x1E3A8A, 0x172554, 0x312E81], 0xE2C275)),
  // Minimal
  BackgroundSpec('Pastel Kompozisyon', 'Minimal', _minimal(0xFDF2F8, [0xF9A8D4, 0xA5B4FC, 0xFDE68A, 0x99F6E4], 0)),
  BackgroundSpec('Terrakota', 'Minimal', _minimal(0xFFF7ED, [0xC2410C, 0xEA580C, 0xFDBA74, 0x7C2D12], 1)),
  BackgroundSpec('Nordik', 'Minimal', _minimal(0xF1F5F9, [0x94A3B8, 0x64748B, 0xCBD5E1, 0x0F172A], 2)),
  BackgroundSpec('Memphis', 'Minimal', _minimal(0xFEFCE8, [0xF43F5E, 0x3B82F6, 0xFACC15, 0x10B981, 0x111827], 3)),
  BackgroundSpec('Kum ve Güneş', 'Minimal', _minimal(0xFEF3C7, [0xF59E0B, 0xD97706, 0xFCD34D, 0x92400E], 4)),
];

String _two(int n) => n.toString().padLeft(2, '0');

void main() {
  test('50 arka plan, 10 tema × 5, benzersiz ad', () {
    expect(kProfileBackgrounds.length, 50);
    expect(kProfileBackgrounds.map((b) => b.name).toSet().length, 50);
    final byCategory = <String, int>{};
    for (final b in kProfileBackgrounds) {
      byCategory[b.category] = (byCategory[b.category] ?? 0) + 1;
    }
    expect(byCategory.length, 10);
    expect(byCategory.values.every((n) => n == 5), isTrue);
  });

  testWidgets('profil arka planlarını üret', (tester) async {
    if (Platform.environment['GEN_PROFILE_BACKGROUNDS'] != '1') return;
    final dir = Directory(Platform.environment['PROFILE_BG_DIR'] ?? 'build/profile_backgrounds')
      ..createSync(recursive: true);
    final manifest = StringBuffer('code\tname\tcategory\n');
    await tester.runAsync(() async {
      for (var i = 0; i < kProfileBackgrounds.length; i++) {
        final spec = kProfileBackgrounds[i];
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, _w, _h));
        spec.paint(canvas, math.Random(1000 + i));
        _grain(canvas, math.Random(5000 + i));
        final img = await rec.endRecording().toImage(_w.toInt(), _h.toInt());
        final bd = await img.toByteData(format: ui.ImageByteFormat.png);
        File('${dir.path}/bg_${_two(i + 1)}.png').writeAsBytesSync(bd!.buffer.asUint8List());
        manifest.writeln('bg_${_two(i + 1)}\t${spec.name}\t${spec.category}');
      }
    });
    File('${dir.path}/manifest.tsv').writeAsStringSync(manifest.toString());
  });
}
