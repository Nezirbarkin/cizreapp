part of '../face_avatar_painter.dart';

// ============================================================================
// SAÇ MOTORU (Bitmoji tarzı)
//
// Saç, tek tek tellerden değil, birkaç büyük TUTAMDAN oluşur: her parça düz
// renkle dolar, ışığın tersindeki kenarda cel gölge alır, kendi renginin
// koyusuyla konturlanır. Tutamların ucu sivrilir; içlerinde birkaç kıvrık
// ayırma çizgisi ve sol üstte parlama şeritleri bulunur. Kıvırcık dokuda
// kenarlar bulut gibi kabarır.
// ============================================================================

typedef _Flow = Offset Function(Offset p);

/// Saç stiline göre geometri sabitleri.
class _HairGeo {
  final _Rig r;
  final HairSpec s;
  _HairGeo(this.r) : s = r.hair;

  double get vol => r.hairVol;
  double get wid => r.hairWid;
  double get fh => r.foreheadHalf;
  double get ex => 2.6 + 10.5 * wid;

  /// Kubbenin şakak hizasındaki yarı genişliği.
  double get W => r.templeHalf + ex;
  static const double yc = 70;
  /// Quiff/pompadur hacmi kubbeye değil öndeki kabarıklığa gider.
  bool get frontVolume => r.fringe == HairFringe.quiff || r.fringe == HairFringe.pomp;
  double get topY => _Rig.skullTop - 3.2 - 15.0 * (frontVolume ? vol * 0.45 : vol);

  /// Ön kabarıklığın yüksekliği.
  double get crest => !frontVolume ? 0 : (r.fringe == HairFringe.pomp ? 9.0 : 6.0) + vol * 2;
  double get ry => yc - topY;

  /// Ayrımın olduğu taraf (ortadan ayrıkta sağ kabul edilir).
  int get side => s.part == 0 ? 1 : s.part;
  double get partX => s.part * fh * 0.34;

  bool get curly => s.texture == HairTexture.curly || s.texture == HairTexture.coily;
  bool get wavy => s.texture == HairTexture.wavy;

  /// Saç çizgisinin merkezdeki y'si.
  double get hl {
    var y = 51.0;
    switch (s.hairline) {
      case Hairline.high:
        y -= 5;
        break;
      case Hairline.low:
        y += 5;
        break;
      case Hairline.mShape:
        y -= 1;
        break;
      case Hairline.receding:
        y -= 3;
        break;
      case Hairline.straight:
        y += 1;
        break;
      case Hairline.round:
      case Hairline.widow:
        break;
    }
    if (s.length == HairLength.buzz) y += 1;
    return y;
  }

  /// Sağ yarı saç çizgisi (merkezden şakağa), mutlak koordinat.
  List<Offset> hairlineRight() {
    final f = fh;
    final h = hl;
    List<List<double>> pts;
    switch (s.hairline) {
      case Hairline.widow:
        pts = [[0, h + 5], [0.20, h + 1.2], [0.58, h + 4.0], [0.90, h + 12.5], [0.995, h + 22]];
        break;
      case Hairline.mShape:
        pts = [[0, h], [0.30, h - 0.5], [0.58, h - 6.5], [0.80, h + 2], [0.94, h + 12], [0.995, h + 22]];
        break;
      case Hairline.receding:
        pts = [[0, h - 1], [0.34, h - 3], [0.64, h - 9], [0.86, h + 2.5], [0.995, h + 19]];
        break;
      case Hairline.straight:
        pts = [[0, h + 2.5], [0.5, h + 2.8], [0.86, h + 4.2], [0.97, h + 13], [0.995, h + 22]];
        break;
      case Hairline.round:
      case Hairline.high:
      case Hairline.low:
        pts = [[0, h], [0.36, h + 1.0], [0.70, h + 4.6], [0.92, h + 12.0], [0.995, h + 22]];
        break;
    }
    return pts.map((p) => Offset(_cx + p[0] * f, p[1])).toList();
  }

  /// Verilen |x| (merkezden uzaklık) için saç çizgisinin y'si.
  double hairlineY(double ax) {
    final pts = hairlineRight();
    final x = ax.clamp(0.0, fh * 0.995);
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].dx - _cx >= x) {
        final a = pts[i - 1], b = pts[i];
        final t = (x - (a.dx - _cx)) / math.max(0.0001, (b.dx - a.dx));
        return _lerpD(a.dy, b.dy, t);
      }
    }
    return pts.last.dy;
  }

  /// Soldan sağa tüm saç çizgisi (şakaktan şakağa), [n] örnek.
  List<Offset> hairlineFull([int n = 26]) {
    final right = hairlineRight();
    final all = <Offset>[...right.reversed.map(_mirX), ...right.skip(1)];
    return _sampleSpline(all, n);
  }

  /// Yan kısmın bittiği y (favori/kulak hizası).
  double get sideEndY {
    switch (s.length) {
      case HairLength.bald:
      case HairLength.buzz:
        return _Rig.eyeY - 8;
      case HairLength.crop:
        return _Rig.eyeY - 5;
      case HairLength.short:
        return _Rig.eyeY + 2;
      case HairLength.pulled:
        return _Rig.eyeY - 6;
      case HairLength.ear:
        return r.noseBaseY + 5;
      case HairLength.jaw:
      case HairLength.shoulder:
      case HairLength.long:
      case HairLength.xlong:
        return _Rig.eyeY - 2;
    }
  }

  bool get longSides =>
      s.length == HairLength.jaw ||
      s.length == HairLength.shoulder ||
      s.length == HairLength.long ||
      s.length == HairLength.xlong;

  double get lockEndY {
    switch (s.length) {
      case HairLength.jaw:
        return r.chinY - 1;
      case HairLength.shoulder:
        return 184;
      case HairLength.long:
        return 200;
      case HairLength.xlong:
        return 216;
      default:
        return sideEndY;
    }
  }

  /// Fade'in başladığı (üstünde dolgun saç, altında tıraş) y.
  double get fadeTop => switch (s.fade) {
        HairFade.none => 999,
        HairFade.low => _Rig.eyeY - 2,
        HairFade.mid => _Rig.eyeY - 10,
        HairFade.high => _Rig.eyeY - 18,
        HairFade.skin => _Rig.eyeY - 22,
      };
}

// ------------------------------------------------------------- akış alanları
/// Tepeden dışa, biraz yer çekimiyle.
_Flow _flowRadial(_HairGeo g, {double gravity = 0.45}) {
  final c = Offset(_cx + g.partX * 0.3, _HairGeo.yc - 14);
  return (p) => _norm(_norm(p - c) * (1 - gravity) + Offset(0, gravity));
}

/// Ayrımdan iki yana aşağı; [sweep] > 0 tümü ayrımın tersine taranır.
_Flow _flowPart(_HairGeo g, {double sweep = 0.0, double drop = 0.55}) {
  final s = g.side;
  return (p) {
    final xr = (p.dx - (_cx + g.partX)) / g.W;
    final hx = xr * 0.8 + (-s) * sweep;
    return _norm(Offset(hx, drop + 0.4 * ((p.dy - g.topY) / g.ry).clamp(0.0, 1.5)));
  };
}

/// Arkaya taralı (alından tepeye doğru).
_Flow _flowBack(_HairGeo g) => (p) => _norm(Offset((p.dx - _cx) / g.W * 0.35, -1.0));

/// Yukarı ve dışa dik.
_Flow _flowUp(_HairGeo g, {double lean = 0.0}) => (p) => _norm(Offset((p.dx - _cx) / g.W * 0.9 + lean, -1.0));

/// Uzun saç: aşağı akar, hafif dışa.
_Flow _flowDown(_HairGeo g, {double spread = 0.28}) =>
    (p) => _norm(Offset((p.dx - _cx) / (g.W + 6) * spread, 1.0));

// ------------------------------------------------------------- kenar araçları
/// Kapalı yolun dışa bakan normali (yol yönünden bağımsız).
Offset _outward(Path region, Offset p, Offset nrm) {
  return region.contains(p + nrm * 0.8) ? -nrm : nrm;
}

/// Kenarı bulut gibi kabartır (kıvırcık doku): ardışık dışa şişkin yaylar.
Path _scallop(Path src, double amp, double step, {int seed = 1}) {
  final out = Path()..fillType = src.fillType;
  final rng = math.Random(seed * 31 + 3);
  for (final m in src.computeMetrics()) {
    final n = math.max(6, (m.length / step).round());
    final pts = <Offset>[];
    final nrms = <Offset>[];
    for (var i = 0; i < n; i++) {
      final tg = m.getTangentForOffset(m.length * i / n)!;
      pts.add(tg.position);
      nrms.add(Offset(tg.vector.dy, -tg.vector.dx));
    }
    out.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < n; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % n];
      final mid = (a + b) / 2;
      final nrm = _outward(src, mid, nrms[i]);
      final k = amp * (0.75 + 0.5 * rng.nextDouble());
      out.quadraticBezierTo(mid.dx + nrm.dx * k * 2, mid.dy + nrm.dy * k * 2, b.dx, b.dy);
    }
    out.close();
  }
  return out;
}

/// Kenarı düşük frekanslı gürültüyle hafifçe dalgalandırır.
Path _wobble(Path src, double amp, int seed, {double step = 2.4}) {
  final rng = math.Random(seed * 131 + 7);
  final p1 = rng.nextDouble() * 6.28, p2 = rng.nextDouble() * 6.28;
  final out = Path()..fillType = src.fillType;
  for (final m in src.computeMetrics()) {
    final pts = <Offset>[];
    final n = math.max(6, (m.length / step).round());
    for (var i = 0; i < n; i++) {
      final d = m.length * i / n;
      final tg = m.getTangentForOffset(d)!;
      final nrm = Offset(tg.vector.dy, -tg.vector.dx);
      final noise = math.sin(d * 0.19 + p1) * 0.6 + math.sin(d * 0.43 + p2) * 0.4;
      pts.add(tg.position + nrm * (noise * amp));
    }
    out.extendWithPath(_spline(pts, closed: m.isClosed), Offset.zero);
  }
  return out;
}

/// [base] noktaları arasına [tips] uçlarını ekleyerek sivri tutam kenarı
/// çizer (alev/tutam ucu). Path'in mevcut noktası base.first olmalı.
void _appendTips(Path path, List<Offset> base, List<Offset> tips) {
  for (var i = 0; i < base.length - 1; i++) {
    final a = base[i], b = base[i + 1], t = tips[i];
    path.quadraticBezierTo(_lerpD(a.dx, t.dx, 0.15), _lerpD(a.dy, t.dy, 0.8), t.dx, t.dy);
    path.quadraticBezierTo(_lerpD(t.dx, b.dx, 0.65), _lerpD(t.dy, b.dy, 0.35), b.dx, b.dy);
  }
}

/// [base] boyunca, ardışık noktaların ortasından [dir] yönüne [len] kadar
/// sivrilen uçlar (uzunluk hafif rastgele).
List<Offset> _tipsAlong(List<Offset> base, Offset Function(int i, Offset mid) dir, double len, math.Random rng,
    {double jitter = 0.35}) {
  return [
    for (var i = 0; i < base.length - 1; i++)
      () {
        final mid = (base[i] + base[i + 1]) / 2;
        return mid + dir(i, mid) * (len * (1 - jitter / 2 + jitter * rng.nextDouble()));
      }(),
  ];
}

// --------------------------------------------------------------- boyama
/// Saç parçasını boyar: dolgu → cel gölge → kontur.
void _hairFill(Canvas c, _Rig r, Path path, {Color? base, double shade = 1.0, Offset light = const Offset(-6, -5), bool outline = true}) {
  c.drawPath(path, r.fill(base ?? r.hairColor));
  if (shade > 0) {
    r.celShade(c, path, _alpha(r.hairShadow, 0.85 * shade), base: base ?? r.hairColor, offset: light, blur: r.detailed ? 1.0 : 0);
  }
  if (outline) c.drawPath(path, r.stroke(r.hairLine, r.lineW));
}

/// Akış alanını izleyen tutam çizgileri: [seeds]'ten başlar, bölge içinde kalır.
void _hairLines(
  Canvas c,
  _Rig r,
  Path region,
  _Flow flow,
  List<Offset> seeds, {
  required double len,
  Color? color,
  double width = 1.1,
  double alpha = 0.75,
  double curl = 0,
  int seed = 1,
}) {
  final rng = r.rngFor(seed);
  final col = color ?? r.hairShadow;
  c.save();
  c.clipPath(region);
  for (final s in seeds) {
    final pts = <Offset>[s];
    var cur = s;
    const steps = 7;
    final l = len * (0.7 + 0.6 * rng.nextDouble());
    final phase = rng.nextDouble() * math.pi * 2;
    for (var i = 1; i <= steps; i++) {
      final d = flow(cur);
      final perp = Offset(-d.dy, d.dx);
      cur = cur + d * (l / steps) + perp * (curl * math.sin(i * 1.3 + phase));
      pts.add(cur);
    }
    c.drawPath(_taperPath(pts, width * 0.35, width * 0.1, wMid: width), r.fill(_alpha(col, alpha)));
  }
  c.restore();
}

/// [region] içinde, [band] dikdörtgeninde rastgele tohumlar.
List<Offset> _seedsIn(Path region, Rect band, int n, math.Random rng) {
  final out = <Offset>[];
  var tries = 0;
  while (out.length < n && tries < n * 30) {
    tries++;
    final p = Offset(band.left + rng.nextDouble() * band.width, band.top + rng.nextDouble() * band.height);
    if (region.contains(p)) out.add(p);
  }
  return out;
}

/// Bir saç kütlesine doku verir: düzenli aralıklı tutam çizgileri.
/// [seeds] çizgilerin başladığı noktalardır (stil belirler).
void _hairTexture(Canvas c, _Rig r, _HairGeo g, Path region, _Flow flow, List<Offset> seeds, {int seed = 1, double len = 18}) {
  if (g.curly) {
    _curlTexture(c, r, region, seed: seed, radius: g.s.texture == HairTexture.coily ? 2.2 : 3.2);
    return;
  }
  final curl = g.wavy ? 0.8 + 1.2 * g.s.curl : 0.0;
  final use = r.detailed ? seeds : [for (var i = 0; i < seeds.length; i += 2) seeds[i]];
  _hairLines(c, r, region, flow, use, len: len, color: r.hairLine, width: 1.15, alpha: 0.62, curl: curl, seed: seed + 1);
}

/// Saçtaki parlama: [oval]'in [start]..[start+sweep] yayında geniş yumuşak
/// bir bant ve onun üstünde birkaç keskin kısa çizgi (anime/Bitmoji ışığı).
void _sheen(Canvas c, _Rig r, Path region, Rect oval, double start, double sweep, {double width = 7, double strength = 1.0}) {
  c.save();
  c.clipPath(region);
  c.drawArc(oval, start, sweep, false, r.stroke(_alpha(r.hairLight, 0.42 * strength), width, blur: r.detailed ? 2.4 : 0));
  final n = r.detailed ? 4 : 2;
  for (var k = 0; k < n; k++) {
    final t = 0.14 + 0.72 * k / math.max(1, n - 1);
    final a = start + sweep * t;
    final p = Offset(oval.center.dx + math.cos(a) * oval.width / 2, oval.center.dy + math.sin(a) * oval.height / 2);
    final tg = _norm(Offset(-math.sin(a) * oval.width, math.cos(a) * oval.height));
    final l = width * (1.0 + 0.5 * (k.isEven ? 1 : 0));
    c.drawPath(
      _taperPath([p - tg * l * 0.5, p, p + tg * l * 0.5], 0.3, 0.3, wMid: width * 0.32),
      r.fill(_alpha(r.hairShine, 0.85 * strength)),
    );
  }
  c.restore();
}

/// Kıvırcık/kıvrık doku: dağınık C biçimli bukleler (koyu) ve sol üstte
/// birkaç açık bukle.
void _curlTexture(Canvas c, _Rig r, Path region, {required int seed, double radius = 3.0}) {
  final b = region.getBounds();
  final rng = r.rngFor(seed);
  final area = b.width * b.height;
  final n = (area / (radius * radius * (r.detailed ? 16 : 40))).round().clamp(3, 140);
  c.save();
  c.clipPath(region);
  for (var i = 0; i < n; i++) {
    final p = Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height);
    if (!region.contains(p)) continue;
    final rad = radius * (0.75 + 0.5 * rng.nextDouble());
    final start = math.pi * (0.1 + 0.6 * rng.nextDouble());
    final light = (p.dx - b.left) / b.width < 0.45 && (p.dy - b.top) / b.height < 0.4 && rng.nextDouble() < 0.45;
    c.drawArc(
      Rect.fromCircle(center: p, radius: rad),
      start,
      math.pi * 1.25,
      false,
      r.stroke(_alpha(light ? r.hairShine : r.hairLine, light ? 0.7 : 0.55), light ? 1.3 : 1.1),
    );
  }
  c.restore();
}

/// Saçın cilde düşürdüğü gölge (alın/yanak). Saçtan önce çizilir.
void _castOnSkin(Canvas canvas, _Rig r, List<Path> parts, {Offset shift = const Offset(1.5, 3.2)}) {
  canvas.save();
  canvas.clipPath(r.head);
  for (final p in parts) {
    canvas.drawPath(p.shift(shift), r.soft(_alpha(r.skinShadow, 0.95), r.detailed ? 1.4 : 0));
  }
  canvas.restore();
}

// ======================================================================== ARKA
void _paintHairBack(Canvas canvas, _Rig r) {
  final s = r.hair;
  if (s.covered) {
    _paintCoverBack(canvas, r);
    return;
  }
  if (s.bald) return;
  final g = _HairGeo(r);
  _paintBackMass(canvas, r, g);
  _paintTieBack(canvas, r, g);
}

/// Uzun saçın kafanın arkasındaki kütlesi (boynun iki yanı ve omuz arkası).
void _paintBackMass(Canvas canvas, _Rig r, _HairGeo g) {
  final s = g.s;
  if (!g.longSides && s.length != HairLength.ear) return;
  if (r.tie == HairTie.boxBraids || r.tie == HairTie.dreads) return;

  final W = g.W + (s.length == HairLength.ear ? 2 : 6) + (s.layered ? 2 : 0) + (g.curly ? 6 * s.curl : 0);
  final end = s.length == HairLength.ear ? r.noseBaseY + 14 : g.lockEndY + (s.length == HairLength.jaw ? 3 : 0);
  final bobIn = s.length == HairLength.jaw ? 4.0 : 0.0;
  final rng = r.rngFor(30 + r.cfg.hair);

  final path = Path()..moveTo(_cx - W + 2, _HairGeo.yc);
  path.cubicTo(_cx - W - 4, 100, _cx - W - 3, (100 + end) / 2, _cx - W + 2 + bobIn, end);
  // Alt kenar: sivri tutam uçları.
  final base = <Offset>[for (var i = 0; i <= 6; i++) Offset(_lerpD(_cx - W + 2 + bobIn, _cx + W - 2 - bobIn, i / 6), end - 2)];
  final tipLen = s.length == HairLength.jaw ? 3.0 : (s.layered ? 11.0 : 7.0);
  final tips = _tipsAlong(base, (i, mid) => _norm(Offset((mid.dx - _cx) / W * 0.4, 1)), tipLen, rng);
  path.lineTo(base.first.dx, base.first.dy);
  _appendTips(path, base, tips);
  path.cubicTo(_cx + W + 3, (100 + end) / 2, _cx + W + 4, 100, _cx + W - 2, _HairGeo.yc);
  path.cubicTo(_cx + W - 6, g.topY + 8, _cx - W + 6, g.topY + 8, _cx - W + 2, _HairGeo.yc);
  path.close();

  final shaped = g.curly ? _scallop(path, 1.6 + 1.6 * s.curl, 7, seed: 31) : path;
  final dark = _mix(r.hairColor, r.hairShadow, 0.55);
  _hairFill(canvas, r, shaped, base: dark, shade: 0.6);
  if (!g.curly) {
    _hairLines(canvas, r, shaped, _flowDown(g, spread: 0.35),
        _seedsIn(shaped, Rect.fromLTRB(_cx - W, 110, _cx + W, end - 10), r.detailed ? 8 : 3, rng),
        len: 28, color: r.hairLine, width: 1.2, alpha: 0.55, curl: g.wavy ? 2.0 : 0, seed: 32);
  } else {
    _curlTexture(canvas, r, shaped, seed: 33, radius: 3.2);
  }
}

// ======================================================================== ÖN
void _paintHairFront(Canvas canvas, _Rig r) {
  final s = r.hair;
  if (s.covered) {
    _paintCoverFront(canvas, r);
    return;
  }
  if (s.bald) {
    _paintBaldShine(canvas, r);
    return;
  }
  final g = _HairGeo(r);

  if (s.length == HairLength.buzz) {
    _paintBuzz(canvas, r, g);
    _paintTieUnder(canvas, r, g);
    _paintTieFront(canvas, r, g);
    return;
  }

  final cap = _capPath(g, r);
  final fringe = _fringeParts(g, r);
  final sides = g.longSides ? _sideLockPaths(g, r) : const <Path>[];

  // Gölgeler önce: saç kendi gölgesini örter.
  _castOnSkin(canvas, r, [cap, ...fringe.map((f) => f.path), ...sides]);

  _paintTieUnder(canvas, r, g); // tepe dikenleri, mohawk, afro topuz kabarması
  _paintCap(canvas, r, g, cap);
  for (final f in fringe) {
    _hairFill(canvas, r, f.path, base: f.tone);
    if (!g.curly) {
      _hairLines(canvas, r, f.path, f.flow, f.lines, len: f.lineLen, color: r.hairLine, width: 1.15, alpha: 0.62, curl: g.wavy ? 1.2 : 0, seed: f.seed);
      if (f.sheen.isNotEmpty) {
        _hairLines(canvas, r, f.path, f.flow, f.sheen, len: f.lineLen * 0.55, color: r.hairShine, width: 2.0, alpha: 0.7, seed: f.seed + 7);
      }
    } else {
      _curlTexture(canvas, r, f.path, seed: f.seed, radius: 2.8);
    }
  }
  for (var i = 0; i < sides.length; i++) {
    _paintSideLock(canvas, r, g, sides[i], i == 1);
  }
  _paintTieFront(canvas, r, g);
}

/// Kel kafada hafif parlama.
void _paintBaldShine(Canvas canvas, _Rig r) {
  if (!r.detailed) return;
  canvas.save();
  canvas.clipPath(r.head);
  canvas.drawOval(
    Rect.fromCenter(center: const Offset(_cx - 12, _Rig.skullTop + 12), width: 26, height: 10),
    r.soft(_alpha(Colors.white, 0.35), 3),
  );
  canvas.restore();
}

/// Sıfır tıraş: kafa derisinde saç renginde gölge + net saç çizgisi.
void _paintBuzz(Canvas canvas, _Rig r, _HairGeo g) {
  final hl = g.hairlineFull();
  final area = Path()..moveTo(hl.first.dx, hl.first.dy);
  for (final p in hl.skip(1)) {
    area.lineTo(p.dx, p.dy);
  }
  // Sağ favoriden aşağı, kafanın kenarından tepeye, soldan geri.
  final sb = g.sideEndY;
  for (final p in r.headEdge(hl.last.dy, sb, n: 4)) {
    area.lineTo(p.dx + 1, p.dy);
  }
  area.lineTo(_cx + r.headX(sb) + 3, sb);
  area.lineTo(_cx + r.headX(30) + 6, 30);
  area.lineTo(_cx, _Rig.skullTop - 4);
  area.lineTo(_cx - r.headX(30) - 6, 30);
  area.lineTo(_cx - r.headX(sb) - 3, sb);
  for (final p in r.headEdge(hl.first.dy, sb, n: 4).reversed) {
    area.lineTo(_cx - (p.dx - _cx) - 1, p.dy);
  }
  area.close();
  canvas.save();
  canvas.clipPath(r.head);
  final buzz = Color.alphaBlend(_alpha(r.hairColor, 0.62), r.skin);
  canvas.drawPath(area, r.fill(buzz));
  r.celShade(canvas, area, _alpha(r.hairShadow, 0.5), base: buzz, offset: const Offset(-6, -4));
  if (r.detailed) {
    final rng = r.rngFor(45);
    final b = area.getBounds();
    for (var i = 0; i < 260; i++) {
      final p = Offset(b.left + rng.nextDouble() * b.width, b.top + rng.nextDouble() * b.height);
      if (!area.contains(p)) continue;
      canvas.drawCircle(p, 0.35, r.fill(_alpha(r.hairLine, 0.35)));
    }
  }
  canvas.restore();
}

/// Tepe kütlesi: kubbe dış kenarı + favoriler + saç çizgisi (iç kenar).
Path _capPath(_HairGeo g, _Rig r) {
  final s = g.s;
  final W = g.W;
  final topY = g.topY;
  final ry = _HairGeo.yc - topY;
  final sbY = g.sideEndY;
  final fadeTight = s.fade != HairFade.none;
  final isEar = s.length == HairLength.ear;
  final thick = fadeTight ? 1.6 : (isEar ? 10.0 + g.ex * 0.4 : 2.2 + g.ex * 0.55);
  final rng = r.rngFor(60 + r.cfg.hair);

  double outerX(double y) {
    final t = ((y - _HairGeo.yc) / (sbY - _HairGeo.yc)).clamp(0.0, 1.0);
    final st = t * t * (3 - 2 * t);
    return _lerpD(fadeTight ? r.headX(_HairGeo.yc) + 2.2 : W, r.headX(sbY) + thick, st);
  }

  // Dış kenar (soldan sağa): sol favori altı → kubbe → sağ favori altı.
  final rightOuter = <Offset>[
    Offset(_cx, topY),
    Offset(_cx + 0.5 * W, _HairGeo.yc - 0.866 * ry),
    Offset(_cx + 0.866 * W, _HairGeo.yc - 0.5 * ry),
    Offset(_cx + (fadeTight ? r.headX(_HairGeo.yc - 4) + 2.4 : W), _HairGeo.yc),
    Offset(_cx + outerX(_lerpD(_HairGeo.yc, sbY, 0.5)), _lerpD(_HairGeo.yc, sbY, 0.5)),
    Offset(_cx + _lerpD(outerX(sbY - 5), r.headX(sbY - 5), isEar ? 0.0 : 0.35), sbY - 5),
    Offset(_cx + r.headX(sbY) + (isEar ? thick * 0.75 : 0.6), sbY),
  ];
  var outer = _sampleSpline([...rightOuter.skip(1).toList().reversed.map(_mirX), ...rightOuter], 40);
  if (g.crest > 0) {
    // Ayrım tarafında öne/yukarı kalkan tepe.
    final xc = _cx + g.side * W * 0.18;
    outer = [
      for (final p in outer)
        p.dy < _HairGeo.yc ? p.translate(0, -g.crest * math.exp(-math.pow((p.dx - xc) / (W * 0.95), 2)) * ((_HairGeo.yc - p.dy) / g.ry).clamp(0.0, 1.0)) : p,
    ];
  }

  // Dikenli/dağınık stillerde üst siluet sivri tutamlarla kırılır.
  final fr = r.fringe;
  final path = Path();
  if (fr == HairFringe.spiky || fr == HairFringe.messy || (s.texture == HairTexture.wavy && s.length.index <= HairLength.short.index)) {
    final i0 = 6, i1 = outer.length - 7;
    final top = outer.sublist(i0, i1 + 1);
    final every = fr == HairFringe.spiky ? 3 : 4;
    final base = <Offset>[for (var i = 0; i < top.length; i += every) top[i]];
    if (base.last != top.last) base.add(top.last);
    final len = fr == HairFringe.spiky ? 6.5 + 4 * g.vol : 4.0;
    final tips = _tipsAlong(base, (i, mid) => _norm(mid - Offset(_cx, _HairGeo.yc + 6)), len, rng, jitter: 0.6);
    path.moveTo(outer.first.dx, outer.first.dy);
    for (final p in outer.sublist(1, i0 + 1)) {
      path.lineTo(p.dx, p.dy);
    }
    _appendTips(path, base, tips);
    for (final p in outer.sublist(i1)) {
      path.lineTo(p.dx, p.dy);
    }
  } else {
    path.moveTo(outer.first.dx, outer.first.dy);
    for (final p in outer.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
  }

  // Sağ favori: altından kafa kenarı boyunca yukarı.
  final hlR = g.hairlineRight();
  final hlEndY = hlR.last.dy;
  for (final p in r.headEdge(sbY, hlEndY, n: 6, inset: 0.6)) {
    path.lineTo(p.dx, p.dy);
  }

  // Saç çizgisi: sağ şakaktan sola. Kısa/dağınık kâkülde sivri uçlu.
  final line = g.hairlineFull().reversed.toList();
  final jagged = fr == HairFringe.micro || fr == HairFringe.crop || fr == HairFringe.spiky || fr == HairFringe.messy;
  if (jagged) {
    // Saç çizgisinin orta bölümünde birkaç büyük, eğik tutam ucu.
    final i0 = (line.length * 0.18).round(), i1 = (line.length * 0.82).round();
    final step = fr == HairFringe.micro ? 3 : 2;
    final base = <Offset>[for (var i = i0; i <= i1; i += step) line[i]];
    final len = switch (fr) {
      HairFringe.micro => 3.2,
      HairFringe.crop => 5.0,
      HairFringe.messy => 6.0,
      _ => 4.2,
    };
    final lean = fr == HairFringe.spiky ? 0.0 : 0.55 * g.side;
    final tips = _tipsAlong(base, (i, mid) => _norm(Offset(lean + (mid.dx - _cx) / g.fh * 0.3, 1)), len, rng, jitter: 0.5);
    for (final p in line.sublist(0, i0 + 1)) {
      path.lineTo(p.dx, p.dy);
    }
    _appendTips(path, base, tips);
    for (final p in line.sublist(i0 + (base.length - 1) * step)) {
      path.lineTo(p.dx, p.dy);
    }
  } else {
    for (final p in line) {
      path.lineTo(p.dx, p.dy);
    }
  }
  // Sol favori: yukarıdan aşağı.
  for (final p in r.headEdge(hlEndY, sbY, n: 6, inset: 0.6)) {
    path.lineTo(_cx - (p.dx - _cx), p.dy);
  }
  path.close();

  if (g.curly) return _scallop(path, 1.5 + 2.0 * s.curl, s.texture == HairTexture.coily ? 6.0 : 8.5, seed: 61);
  if (r.detailed && !jagged) return _wobble(path, 0.5, 62);
  return path;
}

_Flow _capFlow(_HairGeo g, HairFringe fr) {
  switch (fr) {
    case HairFringe.slick:
      return _flowBack(g);
    case HairFringe.spiky:
    case HairFringe.quiff:
    case HairFringe.pomp:
    case HairFringe.messy:
      return _flowUp(g, lean: 0.1 * g.s.part);
    case HairFringe.sweep:
    case HairFringe.sweepLong:
    case HairFringe.wave:
      return _flowPart(g, sweep: 0.55);
    case HairFringe.comb:
      return _flowPart(g, sweep: 0.35, drop: 0.7);
    case HairFringe.curtain:
      return _flowPart(g, sweep: 0.0, drop: 0.8);
    default:
      return _flowRadial(g, gravity: g.s.length == HairLength.short ? 0.5 : 0.35);
  }
}

void _paintCap(Canvas canvas, _Rig r, _HairGeo g, Path cap) {
  final s = g.s;
  final fr = r.fringe;
  final fadeTop = g.fadeTop;
  final hasFade = s.fade != HairFade.none;

  canvas.drawPath(cap, r.fill(r.hairColor));
  r.celShade(canvas, cap, _alpha(r.hairShadow, 0.85), base: r.hairColor, offset: const Offset(-7, -6), blur: r.detailed ? 1.0 : 0);

  final flow = _capFlow(g, fr);
  final W = g.W;
  final ry = g.ry;
  final List<Offset> seeds;
  if (fr == HairFringe.slick || fr == HairFringe.quiff || fr == HairFringe.pomp || fr == HairFringe.spiky || fr == HairFringe.messy) {
    final line = g.hairlineFull(11);
    seeds = [for (final p in line.sublist(1, line.length - 1)) p.translate(0, -3)];
  } else {
    seeds = [
      for (var i = 0; i < 9; i++)
        () {
          final x = _lerpD(-0.74 * W, 0.74 * W, i / 8);
          final domeY = _HairGeo.yc - ry * math.sqrt(math.max(0.0, 1 - (x / W) * (x / W)));
          return Offset(_cx + x, domeY + 0.30 * (g.hairlineY(x.abs()) - domeY));
        }(),
    ];
  }
  _hairTexture(canvas, r, g, cap, flow, seeds,
      seed: 100 + r.cfg.hair,
      len: switch (s.length) {
        HairLength.crop => ry * 0.45,
        HairLength.short => ry * 0.6,
        _ => ry * 0.7,
      });
  if (g.crest > 0 && !g.curly) {
    // Kabarık önün kıvrım çizgisi: alından tepeye yuvarlanan tutam.
    final side = g.side.toDouble();
    final top = g.topY - g.crest * 0.8;
    for (var k = 0; k < 2; k++) {
      final x0 = _cx - side * g.fh * (0.75 - k * 0.35);
      canvas.drawPath(
        _taperPath(_quadPts(Offset(x0, g.hairlineY((x0 - _cx).abs()) - 1), Offset(x0 + side * 6, top + 10 + k * 6), Offset(_cx + side * g.fh * (0.35 + k * 0.2), top + 6 + k * 8), 10),
            0.3, 0.2, wMid: 1.3),
        r.fill(_alpha(r.hairLine, 0.6)),
      );
    }
  }
  if (!g.curly) {
    _sheen(canvas, r, cap, Rect.fromCenter(center: Offset(_cx - 2 + g.partX * 0.2, _HairGeo.yc - 2 - g.crest * 0.5), width: 2 * (W - 8), height: 2 * (ry - 8 + g.crest * 0.6)),
        math.pi * 1.10, math.pi * 0.34);
  }

  // Ayrım çizgisi.
  if ((fr == HairFringe.comb || fr == HairFringe.sweep || fr == HairFringe.sweepLong || fr == HairFringe.wave) && s.part != 0) {
    final px = _cx + g.partX;
    canvas.drawPath(
      Path()
        ..moveTo(px, g.hl - 1)
        ..quadraticBezierTo(px + g.side * 1.5, g.hl - 10, px - g.side * 2, g.topY + 9),
      r.stroke(r.hairLine, r.lineW * 1.1),
    );
  }
  if (fr == HairFringe.curtain || (s.part == 0 && g.longSides && fr != HairFringe.blunt)) {
    canvas.drawPath(
      Path()
        ..moveTo(_cx, g.hl - 2)
        ..quadraticBezierTo(_cx + 0.6, g.hl - 12, _cx - 0.5, g.topY + 10),
      r.stroke(r.hairLine, r.lineW * 1.1),
    );
  }

  // Fade: yanlar ten rengine doğru erir; kontur yalnız fade'in üstünde.
  if (hasFade) {
    canvas.save();
    canvas.clipPath(cap);
    final skinStop = s.fade == HairFade.skin ? 1.0 : 0.72;
    r.mirrored(canvas, (c, mir) {
      final x0 = _cx - r.headX(fadeTop) - 6;
      final rect = Rect.fromLTRB(x0, fadeTop - 4, _cx - r.foreheadHalf * 0.55, g.sideEndY + 2);
      c.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, fadeTop - 4),
            Offset(0, g.sideEndY),
            [_alpha(r.skin, 0.0), _alpha(r.skin, skinStop * 0.85)],
          ),
      );
    });
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, 200, fadeTop + 2));
    canvas.drawPath(cap, r.stroke(r.hairLine, r.lineW));
    canvas.restore();
  } else {
    canvas.drawPath(cap, r.stroke(r.hairLine, r.lineW));
  }
}

// ---------------------------------------------------------------- kâkül
class _FringePart {
  final Path path;
  final _Flow flow;
  final List<Offset> lines;
  final List<Offset> sheen;
  final double lineLen;
  final int seed;
  final Color? tone;
  const _FringePart(this.path, this.flow, this.lines, {this.sheen = const [], this.lineLen = 16, this.seed = 1, this.tone});
}

List<_FringePart> _fringeParts(_HairGeo g, _Rig r) {
  final s = g.s;
  final fr = r.fringe;
  final fh = g.fh;
  final hl = g.hl;
  final side = g.side;
  final rng = r.rngFor(200 + r.cfg.hair);
  if (s.length == HairLength.buzz) return const [];

  switch (fr) {
    case HairFringe.none:
    case HairFringe.slick:
    case HairFringe.micro:
    case HairFringe.crop:
    case HairFringe.spiky:
      return const [];

    case HairFringe.comb:
      // Ayrımın uzak tarafında yana yatırılmış küçük tutam.
      final far = -side.toDouble();
      final px = _cx + g.partX;
      final p = Path()..moveTo(px, hl - 9);
      p.quadraticBezierTo(_cx + far * fh * 0.45, hl - 9, _cx + far * fh * 0.97, g.hairlineY(fh * 0.95) - 3);
      final base = [
        Offset(_cx + far * fh * 0.99, g.hairlineY(fh * 0.95) + 4),
        Offset(_cx + far * fh * 0.62, hl + 6.5),
        Offset(_cx + far * fh * 0.28, hl + 4.5),
        Offset(px, hl + 1.5),
      ];
      final tips = _tipsAlong(base, (i, mid) => _norm(Offset(far * 0.9, 0.7)), 4.2, rng);
      p.lineTo(base.first.dx, base.first.dy);
      _appendTips(p, base, tips);
      p.close();
      return [
        _FringePart(p, _flowPart(g, sweep: 0.9, drop: 0.25), _seedsIn(p, p.getBounds(), 4, rng), lineLen: 14, seed: 210),
      ];

    case HairFringe.sweep:
    case HairFringe.sweepLong:
    case HairFringe.wave:
      final long = fr != HairFringe.sweep;
      final far = -side.toDouble();
      final px = _cx + g.partX;
      final endY = hl + (long ? 27 : 19) + (fr == HairFringe.wave ? 3 : 0) + (g.longSides ? 4 : 0);
      final farX = _cx + far * (fh + (long ? 3.0 : 1.0));
      final p = Path()..moveTo(px + side * 2, hl - 10);
      p.quadraticBezierTo(_cx + far * fh * 0.4, hl - 13, farX, g.hairlineY(fh) - 4);
      p.quadraticBezierTo(farX + far * 2.5, endY - 10, farX - far * 0.5, endY);
      // Alt kenar: uzak şakaktan ayrıma, 4 sivri uç.
      final edge = _quadPts(Offset(farX - far * 0.5, endY), Offset(_cx + far * fh * 0.25, endY - 4), Offset(px + side * 1.5, hl + 2), 4);
      final tips = _tipsAlong(edge, (i, mid) => _norm(Offset(far * (0.6 - i * 0.12), 1.0)), long ? 7.0 : 5.0, rng);
      _appendTips(p, edge, tips);
      p.close();
      final flow = _flowPart(g, sweep: 0.9, drop: long ? 0.55 : 0.35);
      final lineSeeds = [for (var i = 0; i < (r.detailed ? 5 : 3); i++) Offset(_lerpD(px, farX, 0.08 + i * 0.16), hl - 7 + i * 1.6)];
      return [
        _FringePart(
          r.detailed && !g.curly ? _wobble(p, 0.35, 220) : p,
          flow,
          lineSeeds,
          sheen: [Offset(_lerpD(px, farX, 0.25), hl - 6), Offset(_lerpD(px, farX, 0.45), hl - 4)],
          lineLen: long ? 34 : 26,
          seed: 220,
        ),
      ];

    case HairFringe.blunt:
    case HairFringe.wispy:
      final wispy = fr == HairFringe.wispy;
      final low = r.browBaseY - (wispy ? 4.0 : 5.0);
      final hlr = g.hairlineRight();
      final p = Path()..moveTo(_cx - fh * 1.0, g.hairlineY(fh) + 8);
      for (final q in hlr.reversed) {
        p.lineTo(_cx - (q.dx - _cx), q.dy - 7);
      }
      for (final q in hlr.skip(1)) {
        p.lineTo(q.dx, q.dy - 7);
      }
      p.lineTo(_cx + fh * 1.0, g.hairlineY(fh) + 8);
      p.quadraticBezierTo(_cx + fh * 1.02, low - 1, _cx + fh * 0.9, low + 1);
      final n = wispy ? 7 : 9;
      final edge = [for (var i = 0; i <= n; i++) Offset(_lerpD(_cx + fh * 0.9, _cx - fh * 0.9, i / n), low + 1.5 - 2.5 * math.pow((i / n - 0.5).abs() * 2, 2))];
      final tips = _tipsAlong(edge, (i, mid) => _norm(Offset((mid.dx - _cx) / fh * 0.25, 1)), wispy ? 5.0 : 1.6, rng, jitter: 0.5);
      p.lineTo(edge.first.dx, edge.first.dy);
      _appendTips(p, edge, tips);
      p.quadraticBezierTo(_cx - fh * 1.02, low - 1, _cx - fh * 1.0, g.hairlineY(fh) + 8);
      p.close();
      Offset flow(Offset q) => _norm(Offset((q.dx - _cx) / g.W * 0.25, 1.0));
      return [
        _FringePart(
          p,
          flow,
          [for (var i = 1; i < n; i += wispy ? 1 : 2) Offset(edge[i].dx, hl - 4)],
          sheen: [Offset(_cx - fh * 0.5, hl - 2), Offset(_cx - fh * 0.2, hl - 3)],
          lineLen: (low - hl) + 6,
          seed: 230,
        ),
      ];

    case HairFringe.curtain:
      final extra = g.longSides ? 12.0 : 0.0;
      final parts = <_FringePart>[];
      for (final sgn in [-1.0, 1.0]) {
        final p = Path()..moveTo(_cx + sgn * 0.5, hl - 9);
        p.quadraticBezierTo(_cx + sgn * fh * 0.6, hl - 10, _cx + sgn * fh * 1.0, g.hairlineY(fh) - 5);
        p.lineTo(_cx + sgn * (fh + 2.5), hl + 26 + extra);
        final edge = _quadPts(Offset(_cx + sgn * (fh + 2.5), hl + 26 + extra), Offset(_cx + sgn * fh * 0.45, hl + 8), Offset(_cx + sgn * 1.2, hl + 2), 3);
        final tips = _tipsAlong(edge, (i, mid) => _norm(Offset(sgn * 0.5, 1)), 4.5, rng);
        _appendTips(p, edge, tips);
        p.close();
        parts.add(_FringePart(
          p,
          (q) => _norm(Offset(sgn * 0.75, 0.8)),
          [Offset(_cx + sgn * fh * 0.2, hl - 6), Offset(_cx + sgn * fh * 0.45, hl - 5), Offset(_cx + sgn * fh * 0.7, hl - 2)],
          sheen: sgn < 0 ? [Offset(_cx - fh * 0.35, hl - 5)] : const [],
          lineLen: 26 + extra,
          seed: 240 + (sgn > 0 ? 1 : 0),
        ));
      }
      return parts;

    case HairFringe.quiff:
    case HairFringe.pomp:
      return const [];

    case HairFringe.messy:
      final parts = <_FringePart>[];
      for (var i = 0; i < 5; i++) {
        final x = (-0.8 + i * 0.4 + (rng.nextDouble() - 0.5) * 0.15) * fh;
        final root = Offset(_cx + x, g.hairlineY(x.abs()) - 7);
        final ang = math.pi / 2 + (x / fh) * 0.5 + (rng.nextDouble() - 0.5) * 0.9;
        final len = 12 + rng.nextDouble() * 6;
        final tip = root + Offset(math.cos(ang), math.sin(ang)) * len;
        final bend = (rng.nextDouble() - 0.5) * 6;
        final spine = _quadPts(root, (root + tip) / 2 + Offset(bend, 0), tip, 8);
        final path = _taperPath(spine, 7.5, 0.4, wMid: 8.5);
        parts.add(_FringePart(path, (q) => _norm(tip - root), [root], lineLen: len * 0.8, seed: 270 + i,
            tone: i.isEven ? null : _mix(r.hairColor, r.hairShadow, 0.18)));
      }
      return parts;
  }
}

// ---------------------------------------------------------- uzun yan tutamlar
/// Yüzün iki yanından omuzlara dökülen tutam kütleleri (sol, sağ). Üstte
/// başın hacmini sarar, aşağı doğru daralır ve sivri uçlarla biter.
List<Path> _sideLockPaths(_HairGeo g, _Rig r) {
  final s = g.s;
  final endY = g.lockEndY;
  final jawY = math.min(r.gonionY + 4, r.chinY - 8);
  final W = g.W;
  final out = <Path>[];
  for (final sgn in [-1.0, 1.0]) {
    final rng = r.rngFor(300 + (sgn > 0 ? 1 : 0) + r.cfg.hair);
    Offset P(double x, double y) => Offset(_cx + sgn * x, y);
    final waveAmp = g.wavy ? 1.2 + 2.2 * s.curl : 0.0;
    double wv(double y) => waveAmp * math.sin(y * 0.11 + (sgn > 0 ? 1.3 : 0));
    final isJaw = s.length == HairLength.jaw;

    // İç kenar: şakaktan yüzün kenarı boyunca aşağı (yanağı hafifçe örter).
    final inner = <Offset>[
      P(g.fh * 0.99, g.hairlineY(g.fh) + 1),
      P(r.headX(_Rig.eyeY - 6) - 1.5, _Rig.eyeY - 6),
      P(r.headX(r.noseBaseY) - 2.5 + wv(r.noseBaseY), r.noseBaseY),
      P(r.headX(jawY) - 1.5 + wv(jawY), jawY),
    ];
    final double endInnerX;
    final double endOuterX;
    if (isJaw) {
      endInnerX = r.jawHalf * 0.84;
      endOuterX = W + 2;
    } else {
      final midY = _lerpD(jawY, endY, 0.45);
      inner.add(P(r.neckHalf + 7 + wv(midY), midY));
      endInnerX = r.neckHalf + 9 + (s.length == HairLength.xlong ? 3 : 0);
      endOuterX = endInnerX + 22 + (s.layered ? 4 : 0) + (g.curly ? 6 : 0);
    }
    final innerPts = _sampleSpline([...inner, P(endInnerX + wv(endY), endY - 4)], 18);

    final path = Path()..moveTo(innerPts.first.dx, innerPts.first.dy);
    for (final p in innerPts.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    // Uç: sivri tutamlar (iç → dış), dış uç biraz yukarıda.
    final nTips = isJaw ? 3 : 4;
    final edge = [
      for (var i = 0; i <= nTips; i++)
        _lerpO(P(endInnerX, endY - 4), P(endOuterX, endY - (isJaw ? 6 : 10)), i / nTips),
    ];
    final tipLen = isJaw ? 4.0 : (s.layered ? 11.0 : 8.0);
    final tips = _tipsAlong(edge, (i, mid) => _norm(Offset(-sgn * 0.25, 1)), tipLen, rng, jitter: 0.6);
    path.lineTo(edge.first.dx, edge.first.dy);
    _appendTips(path, edge, tips);
    // Dış kenar: aşağıdan şakağa yukarı; ortada omuz hizasında dolgun.
    final outerW = W + 4 + (g.curly ? 4 : 0) + (s.layered ? 2 : 0);
    final outer = _sampleSpline([
      P(endOuterX, endY - (isJaw ? 6 : 10)),
      if (!isJaw) P(_lerpD(endOuterX, outerW + 2, 0.7) + wv(_lerpD(jawY, endY, 0.55)), _lerpD(jawY, endY, 0.55)),
      P(outerW + 1 + wv(jawY), jawY),
      P(outerW + wv(102), 102),
      P(W * 0.99, _HairGeo.yc + 2),
      P(g.fh * 0.86, g.hairlineY(g.fh * 0.86) - 6),
    ], 16);
    for (final p in outer.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    out.add(g.curly ? _scallop(path, 1.4 + 1.6 * s.curl, 6.5, seed: 310 + (sgn > 0 ? 1 : 0)) : path);
  }
  return out;
}

void _paintSideLock(Canvas canvas, _Rig r, _HairGeo g, Path path, bool right) {
  _hairFill(canvas, r, path, shade: right ? 1.0 : 0.7, light: Offset(right ? -6 : -4, -3));
  final b = path.getBounds();
  if (g.curly) {
    _curlTexture(canvas, r, path, seed: 330 + (right ? 1 : 0), radius: 3.0);
    return;
  }
  // Uzunlamasına tutam ayrımları: üstte başlar, uçlara iner.
  final flow = _flowDown(g, spread: 0.25);
  final seeds = [for (var i = 1; i <= 3; i++) Offset(_lerpD(b.left, b.right, i / 4), b.top + b.height * 0.28)];
  _hairLines(canvas, r, path, flow, seeds, len: b.height * 0.75, color: r.hairLine, width: 1.2, alpha: 0.6, curl: g.wavy ? 1.6 : 0, seed: 340 + (right ? 1 : 0));
  // Dikey parlama bandı.
  final x = _lerpD(b.left, b.right, right ? 0.42 : 0.38);
  _sheen(canvas, r, path, Rect.fromLTRB(x - 30, b.top + 10, x + 6, b.top + b.height * 0.9), math.pi * 0.85, math.pi * 0.35,
      width: 5.5, strength: right ? 0.6 : 1.0);
}
