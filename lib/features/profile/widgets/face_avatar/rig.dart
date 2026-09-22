part of '../face_avatar_painter.dart';

const double _cx = 100;

double _lerpD(double a, double b, double t) => a + (b - a) * t;

Offset _lerpO(Offset a, Offset b, double t) => Offset(_lerpD(a.dx, b.dx, t), _lerpD(a.dy, b.dy, t));

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0.0, 1.0))!;

Color _alpha(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));

/// Renk ışığını değiştirir: [amount] > 0 açar (beyaza), < 0 koyulaştırır.
Color _tone(Color c, double amount) {
  if (amount >= 0) return _mix(c, Colors.white, amount);
  return _mix(c, Colors.black, -amount);
}

/// Kapalı/açık Catmull-Rom eğrisi. Noktalardan geçen pürüzsüz bir Path üretir.
Path _spline(List<Offset> pts, {bool closed = false, double tension = 1.0}) {
  final path = Path();
  final n = pts.length;
  if (n < 2) return path;
  path.moveTo(pts[0].dx, pts[0].dy);
  Offset at(int i) {
    if (closed) return pts[((i % n) + n) % n];
    return pts[i.clamp(0, n - 1)];
  }

  final segs = closed ? n : n - 1;
  for (var i = 0; i < segs; i++) {
    final p0 = at(i - 1), p1 = at(i), p2 = at(i + 1), p3 = at(i + 2);
    final k = tension / 6;
    final c1 = p1 + (p2 - p0) * k;
    final c2 = p2 - (p3 - p1) * k;
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
  }
  if (closed) path.close();
  return path;
}

/// Noktalardan geçen açık eğri için [n] eşit aralıklı örnek üretir.
List<Offset> _sampleSpline(List<Offset> pts, int n) {
  final path = _spline(pts);
  final metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) return pts;
  final m = metrics.first;
  final out = <Offset>[];
  for (var i = 0; i < n; i++) {
    final t = n == 1 ? 0.0 : i / (n - 1);
    out.add(m.getTangentForOffset(m.length * t)!.position);
  }
  return out;
}

/// Kökü kalın, ucu ince bir tel/kıl çizer (kıl gibi incelen çokgen).
void _taper(Canvas canvas, List<Offset> pts, double w0, double w1, Paint paint) {
  if (pts.length < 2) return;
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    final prev = pts[math.max(0, i - 1)];
    final next = pts[math.min(pts.length - 1, i + 1)];
    var d = next - prev;
    final len = d.distance;
    d = len == 0 ? const Offset(0, 1) : d / len;
    final nrm = Offset(-d.dy, d.dx);
    final t = pts.length == 1 ? 0.0 : i / (pts.length - 1);
    final w = _lerpD(w0, w1, t) / 2;
    left.add(pts[i] + nrm * w);
    right.add(pts[i] - nrm * w);
  }
  final path = Path()..moveTo(left.first.dx, left.first.dy);
  for (var i = 1; i < left.length; i++) {
    path.lineTo(left[i].dx, left[i].dy);
  }
  for (var i = right.length - 1; i >= 0; i--) {
    path.lineTo(right[i].dx, right[i].dy);
  }
  path.close();
  canvas.drawPath(path, paint);
}

class _Rig {
  final FaceAvatarConfig cfg;
  final bool detailed;
  final Color? background;

  /// 0 = gözler açık, 1 = tamamen kapalı (hareketli avatar kareleri).
  final double blink;

  _Rig(this.cfg, {required this.detailed, this.background, this.blink = 0.0});

  // ------------------------------------------------------------- tarifler
  FaceMetrics get m => cfg.metrics;
  late final FaceShapeSpec shape = cfg.faceShapeSpec;
  late final HairSpec hair = cfg.hairSpec;
  late final BrowSpec brow = cfg.browSpec;
  late final EyeSpec eye = cfg.eyeSpec;
  late final LashSpec lash = cfg.lashSpec;
  late final NoseSpec nose = cfg.noseSpec;
  late final LipSpec lip = cfg.lipSpec;
  late final BeardSpec beard = cfg.beardSpec;
  late final GlassesSpec glasses = cfg.glassesSpec;
  late final HeadwearSpec headwear = cfg.headwearSpec;
  late final JewelrySpec jewelry = cfg.jewelrySpec;
  late final DetailSpec detail = cfg.detailSpec;
  late final ClothingSpec clothing = cfg.clothingSpec;
  int get age => cfg.age.clamp(0, 3);

  // ------------------------------------------------------------- geometri
  static const double skullTop = 32;
  static const double eyeY = 91;

  late final double cheekHalf = kFaceBaseCheekHalf * shape.cheek * m.faceWidth;
  late final double foreheadHalf =
      math.min(kFaceBaseForeheadHalf * shape.forehead * m.faceWidth, cheekHalf + 1.5);
  late final double jawHalf = kFaceBaseJawHalf * shape.jaw * m.jawWidth;
  late final double chinY = eyeY + kFaceBaseChinLength * shape.chin * m.chinLength;
  late final double chinHalf = 10.5 * shape.chinWidth * (0.85 + 0.15 * m.jawWidth);
  late final double eyeDx = 17.4 * m.eyeSpacing * (0.92 + 0.08 * shape.cheek);
  late final double eyeW = 9.2 * m.eyeSize * eye.width;
  late final double eyeH = 4.8 * m.eyeSize * eye.height;
  late final double browBaseY = eyeY - 11.5 - (m.browHeight - 1) * 8 - brow.lift;
  late final double noseBaseY = eyeY + 20.5 * nose.length;
  late final double noseTipY = noseBaseY - 3.2;
  late final double noseHalf = 6.3 * nose.width * m.noseWidth;
  late final double mouthY = noseBaseY + (chinY - noseBaseY) * 0.375;
  late final double mouthHalf = 16.8 * lip.width * m.mouthWidth;
  late final double neckHalf = 13.6 + jawHalf * 0.05;

  /// Kafa silueti: alın → elmacık → çene, Catmull-Rom ile yumuşatılmış.
  late final Path head = _buildHead();

  Path _buildHead() {
    final k = shape.corner;
    final fh = foreheadHalf, cw = cheekHalf, jw = jawHalf, ch = chinHalf;
    final top = skullTop;
    final gonY = 121 + 8 * k;
    final gonX = jw * (1 + 0.05 * k);
    final midJawX = _lerpD(gonX, ch, 0.52) + (1 - k) * 2.4;
    final midJawY = _lerpD(gonY, chinY, 0.6);

    final right = <Offset>[
      Offset(0, top),
      Offset(fh * 0.50, top + 4.6),
      Offset(fh * 0.866, top + 17),
      Offset(fh * 0.985, top + 28.1),
      Offset(fh, 66),
      Offset(_lerpD(fh, cw, 0.55), 80),
      Offset(cw, 92),
      Offset(_lerpD(cw, gonX, 0.5) + 0.4, _lerpD(100, gonY, 0.55)),
      Offset(gonX, gonY),
      Offset(midJawX, midJawY),
      Offset(ch * 1.02, chinY - 2.6),
      Offset(0, chinY),
    ];
    final pts = <Offset>[...right];
    for (var i = right.length - 2; i >= 1; i--) {
      pts.add(Offset(-right[i].dx, right[i].dy));
    }
    return _spline(pts.map((p) => Offset(_cx + p.dx, p.dy)).toList(), closed: true);
  }

  // ------------------------------------------------------ kafa çizgisi arama
  /// Kafa silüetinin sağ yarısı (yukarıdan çeneye), y'ye göre artan noktalar.
  late final List<Offset> _headRight = () {
    final out = <Offset>[];
    final metric = head.computeMetrics().first;
    var lastY = -1e9;
    for (var d = 0.0; d < metric.length; d += 0.8) {
      final p = metric.getTangentForOffset(d)!.position;
      if (p.dx < _cx - 0.01) break;
      if (p.dy >= lastY) {
        out.add(p);
        lastY = p.dy;
      }
    }
    return out;
  }();

  /// Verilen y'de kafanın sağ kenarının merkezden uzaklığı.
  double headX(double y) {
    final pts = _headRight;
    if (y <= pts.first.dy) return pts.first.dx - _cx;
    if (y >= pts.last.dy) return pts.last.dx - _cx;
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].dy >= y) {
        final a = pts[i - 1], b = pts[i];
        final t = (y - a.dy) / math.max(0.0001, b.dy - a.dy);
        return _lerpD(a.dx, b.dx, t) - _cx;
      }
    }
    return pts.last.dx - _cx;
  }

  // ------------------------------------------------- başlık - saç etkileşimi
  bool get hatCoversScalp {
    switch (headwear.kind) {
      case Headwear.cap:
      case Headwear.capBack:
      case Headwear.beanie:
      case Headwear.beaniePom:
      case Headwear.fedora:
      case Headwear.flatCap:
      case Headwear.sunHat:
      case Headwear.hood:
      case Headwear.turbanWrap:
        return true;
      default:
        return false;
    }
  }

  late final double hairVol = hatCoversScalp ? math.min(hair.volume, 0.30) : hair.volume;
  late final double hairWid = hatCoversScalp ? math.min(hair.width, 0.30) : hair.width;

  /// Şapka altında görünmeyecek biçimler (topuz, dikenler…) sadeleştirilir.
  late final HairTie tie = () {
    if (!hatCoversScalp) return hair.tie;
    switch (hair.tie) {
      case HairTie.bunLow:
      case HairTie.bunHigh:
      case HairTie.bunTop:
      case HairTie.bunMessy:
      case HairTie.bunBallet:
      case HairTie.spaceBuns:
      case HairTie.afroPuffs:
      case HairTie.mohawk:
      case HairTie.twists:
      case HairTie.flatTop:
      case HairTie.halfBun:
      case HairTie.crownBraid:
        return HairTie.none;
      default:
        return hair.tie;
    }
  }();

  late final HairFringe fringe = () {
    if (!hatCoversScalp) return hair.fringe;
    switch (hair.fringe) {
      case HairFringe.spiky:
      case HairFringe.quiff:
      case HairFringe.pomp:
      case HairFringe.slick:
      case HairFringe.messy:
        return HairFringe.micro;
      default:
        return hair.fringe;
    }
  }();

  // ---------------------------------------------------------------- renkler
  late final Color skin = cfg.skinTone;
  late final double skinLum = skin.computeLuminance();

  /// 0 = çok açık ten, 1 = çok koyu.
  late final double skinDepth = (1 - (skinLum / 0.62)).clamp(0.0, 1.0);

  late final Color skinShadow = _mix(skin, const Color(0xFF8A3A22), 0.30 - 0.06 * skinDepth);
  late final Color skinDeep = _mix(skin, const Color(0xFF3A160C), 0.56);
  late final Color skinLight = _mix(skin, const Color(0xFFFFF1E2), 0.26 * (1 - 0.45 * skinDepth) + 0.10);
  late final Color skinWarm = _mix(skin, const Color(0xFFD8564E), 0.40);
  late final Color blush = _mix(skin, const Color(0xFFDE5E5A), 0.55);

  late final Color lipBase = () {
    final chosen = kLipColors[cfg.lipColor.clamp(0, kLipColors.length - 1)];
    if (chosen.a > 0) return chosen;
    return _mix(skin, const Color(0xFFB4525A), 0.50 - 0.10 * skinDepth);
  }();
  late final Color lipDark = _mix(lipBase, const Color(0xFF2A0A10), 0.36);
  late final Color lipLight = _mix(lipBase, Colors.white, 0.34);

  /// Yaşa göre grileşen saç rengi.
  late final Color hairColor = () {
    const gray = Color(0xFFD9DCE0);
    const t = [0.0, 0.14, 0.42, 0.80];
    return _mix(cfg.hairColor, gray, t[age]);
  }();
  late final double hairLum = hairColor.computeLuminance();
  late final Color hairDark = _mix(hairColor, const Color(0xFF0B0604), 0.52);
  late final Color hairMid = _mix(hairColor, const Color(0xFF0B0604), 0.24);
  late final Color hairLight = _mix(hairColor, const Color(0xFFFFEBCB), 0.30 + 0.25 * (1 - hairLum));
  late final Color hairShine = _mix(hairColor, const Color(0xFFFFF6E6), 0.55);

  late final Color browColor = _mix(hairColor, const Color(0xFF2E2018), 0.12 + 0.42 * hairLum.clamp(0.0, 1.0));
  late final Color lashColor = _mix(hairDark, const Color(0xFF120B08), 0.55);

  // -------------------------------------------------------------- yardımcı
  Paint fill(Color c) => Paint()..color = c;

  Paint soft(Color c, double sigma) {
    final p = Paint()..color = c;
    if (detailed && sigma > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
    return p;
  }

  Paint stroke(Color c, double w, {StrokeCap cap = StrokeCap.round, double blur = 0}) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round
      ..color = c;
    if (detailed && blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    return p;
  }

  /// Sol tarafı çizdirir, sonra aynasını çizer. [isMirror] ikinci geçişte true
  /// olur — ışık yönüne bağlı öğeler (parlama, gölge) bunu kullanır.
  void mirrored(Canvas canvas, void Function(Canvas c, bool isMirror) drawLeft) {
    drawLeft(canvas, false);
    canvas.save();
    canvas.translate(200, 0);
    canvas.scale(-1, 1);
    drawLeft(canvas, true);
    canvas.restore();
  }

  /// [sgn]: -1 sol, +1 sağ. İşaretle çarpılan x ofsetleriyle her iki yan çizilir.
  void mirroredPaths(void Function(double sgn) draw) {
    draw(-1);
    draw(1);
  }

  math.Random rngFor(int salt) => math.Random(salt * 9973 + 17);
}
