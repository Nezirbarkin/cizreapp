part of '../face_avatar_painter.dart';

// ============================================================================
// ORTAK GEOMETRİ, PALET VE ÇİZİM YARDIMCILARI
//
// Bitmoji tarzı: büyük kafa (karenin ~%62'si), iri gözler, yumuşak ama net
// "cel" gölgeler ve her parçanın kendi renginin koyusuyla çizilen ince
// konturu. Tüm koordinatlar 200x200 birimlik tuvaldedir.
// ============================================================================

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

Offset _mirX(Offset p) => Offset(_cx - (p.dx - _cx), p.dy);

Offset _norm(Offset o) {
  final d = o.distance;
  return d == 0 ? const Offset(0, 1) : o / d;
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

/// Sağ yarısı verilen simetrik kapalı biçim: [right] tepeden (x=0) başlayıp
/// alttaki orta noktada (x=0) biter; x'ler merkezden uzaklıktır.
Path _symmetric(List<Offset> right, {double tension = 1.0}) {
  final pts = <Offset>[...right];
  for (var i = right.length - 2; i >= 1; i--) {
    pts.add(Offset(-right[i].dx, right[i].dy));
  }
  return _spline(pts.map((p) => Offset(_cx + p.dx, p.dy)).toList(), closed: true, tension: tension);
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

/// Kökü kalın, ucu ince bir şerit/tel çizer (kalem darbesi gibi incelen çokgen).
Path _taperPath(List<Offset> pts, double w0, double w1, {double wMid = -1}) {
  final path = Path();
  if (pts.length < 2) return path;
  final left = <Offset>[];
  final right = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    final prev = pts[math.max(0, i - 1)];
    final next = pts[math.min(pts.length - 1, i + 1)];
    final d = _norm(next - prev);
    final nrm = Offset(-d.dy, d.dx);
    final t = pts.length == 1 ? 0.0 : i / (pts.length - 1);
    final double w;
    if (wMid >= 0) {
      // Ortası dolgun (yaprak biçimi) şerit.
      w = t < 0.5 ? _lerpD(w0, wMid, t * 2) : _lerpD(wMid, w1, (t - 0.5) * 2);
    } else {
      w = _lerpD(w0, w1, t);
    }
    left.add(pts[i] + nrm * (w / 2));
    right.add(pts[i] - nrm * (w / 2));
  }
  path.moveTo(left.first.dx, left.first.dy);
  for (var i = 1; i < left.length; i++) {
    path.lineTo(left[i].dx, left[i].dy);
  }
  for (var i = right.length - 1; i >= 0; i--) {
    path.lineTo(right[i].dx, right[i].dy);
  }
  path.close();
  return path;
}

void _taper(Canvas canvas, List<Offset> pts, double w0, double w1, Paint paint) {
  if (pts.length < 2) return;
  canvas.drawPath(_taperPath(pts, w0, w1), paint);
}

/// Kuadratik Bezier üzerinde [n] nokta.
List<Offset> _quadPts(Offset a, Offset c, Offset b, [int n = 10]) {
  final out = <Offset>[];
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    final u = 1 - t;
    out.add(a * (u * u) + c * (2 * u * t) + b * (t * t));
  }
  return out;
}

/// Kübik Bezier üzerinde [n] nokta.
List<Offset> _cubicPts(Offset a, Offset c1, Offset c2, Offset b, [int n = 12]) {
  final out = <Offset>[];
  for (var i = 0; i <= n; i++) {
    final t = i / n;
    final u = 1 - t;
    out.add(a * (u * u * u) + c1 * (3 * u * u * t) + c2 * (3 * u * t * t) + b * (t * t * t));
  }
  return out;
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
  /// Kafatasının tepesi (saçsız) ve göz hattı.
  static const double skullTop = 22;
  static const double eyeY = 95;

  late final double cheekHalf = kFaceBaseCheekHalf * shape.cheek * m.faceWidth;
  late final double foreheadHalf =
      math.min(kFaceBaseForeheadHalf * shape.forehead * (0.6 + 0.4 * m.faceWidth), cheekHalf + 1.0);
  late final double templeHalf = _lerpD(foreheadHalf, cheekHalf, 0.55);
  late final double jawHalf = kFaceBaseJawHalf * shape.jaw * m.jawWidth;
  late final double chinY = eyeY + kFaceBaseChinLength * shape.chin * m.chinLength;
  late final double chinHalf = 15.5 * shape.chinWidth * (0.85 + 0.15 * m.jawWidth);
  late final double gonionY = eyeY + 26 + 4 * shape.corner + (chinY - eyeY - kFaceBaseChinLength) * 0.45;
  late final double eyeDx = 21.6 * m.eyeSpacing * (0.94 + 0.06 * shape.cheek);
  late final double eyeW = 10.3 * m.eyeSize * eye.width;
  late final double eyeH = 6.9 * m.eyeSize * eye.height;
  late final double browBaseY = eyeY - 14.6 - (m.browHeight - 1) * 8 - brow.lift;
  late final double noseBaseY = eyeY + 19.0 * nose.length * m.noseLength * (0.82 + 0.18 * m.chinLength);
  late final double noseTipY = noseBaseY - 2.8;
  late final double noseHalf = 6.6 * nose.width * m.noseWidth;
  late final double mouthY = noseBaseY + (chinY - noseBaseY) * 0.42;
  late final double mouthHalf = 12.8 * lip.width * m.mouthWidth;
  late final double neckHalf = 16.5 + jawHalf * 0.05;

  /// Kulak: yanağın dışına taşan küçük oval.
  late final double earTop = eyeY - 7;
  late final double earBottom = noseBaseY + 3;

  /// Kafa silueti: tepe → alın → şakak → elmacık → çene köşesi → çene ucu.
  late final Path head = _buildHead();

  Path _buildHead() {
    final k = shape.corner;
    final fh = foreheadHalf, cw = cheekHalf, jw = jawHalf, ch = chinHalf;
    const top = skullTop;
    final gonX = jw * (1 + 0.05 * k);
    final gonY = gonionY;
    final midJawX = _lerpD(gonX, ch, 0.52) + (1 - k) * 3.0;
    final midJawY = _lerpD(gonY, chinY, 0.58);

    return _symmetric([
      const Offset(0, top),
      Offset(fh * 0.54, top + 3.4),
      Offset(fh * 0.88, top + 13.5),
      Offset(fh * 0.995, top + 28),
      Offset(_lerpD(fh, cw, 0.62), eyeY - 17),
      Offset(cw, eyeY + 3),
      Offset(_lerpD(cw, gonX, 0.55) + 0.8 * (1 - k), _lerpD(eyeY + 3, gonY, 0.55)),
      Offset(gonX, gonY),
      Offset(midJawX, midJawY),
      Offset(ch * 1.05, chinY - 2.8),
      Offset(0, chinY),
    ]);
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

  /// Kafa siluetinin sağ yarısı, [y0]..[y1] aralığında (aşağı doğru).
  List<Offset> headEdge(double y0, double y1, {int n = 8, double inset = 0}) {
    return [
      for (var i = 0; i <= n; i++)
        () {
          final y = _lerpD(y0, y1, i / n);
          return Offset(_cx + headX(y) - inset, y);
        }(),
    ];
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

  late final double hairVol = hatCoversScalp ? math.min(hair.volume, 0.25) : hair.volume;
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

  /// Cel gölge: sıcak, hafif doygun.
  late final Color skinShadow = _mix(skin, const Color(0xFFA0503A), 0.24 - 0.06 * skinDepth);
  late final Color skinDeep = _mix(skin, const Color(0xFF4A1C10), 0.46 + 0.04 * skinDepth);
  late final Color skinLine = _mix(skin, const Color(0xFF3C170C), 0.52 + 0.06 * skinDepth);
  late final Color skinLight = _mix(skin, const Color(0xFFFFF4EA), 0.30 * (1 - 0.40 * skinDepth) + 0.06);
  late final Color blush = _mix(skin, const Color(0xFFF0656A), 0.48 - 0.12 * skinDepth);

  late final Color lipBase = () {
    final chosen = kLipColors[cfg.lipColor.clamp(0, kLipColors.length - 1)];
    if (chosen.a > 0) return chosen;
    return _mix(skin, const Color(0xFFC0565E), 0.48 - 0.12 * skinDepth);
  }();
  late final Color lipDark = _mix(lipBase, const Color(0xFF2A0A10), 0.30);
  late final Color lipLight = _mix(lipBase, Colors.white, 0.30);

  /// Yaşa göre grileşen saç rengi.
  late final Color hairColor = () {
    const gray = Color(0xFFD5D8DC);
    const t = [0.0, 0.16, 0.45, 0.82];
    final c = _mix(cfg.hairColor, gray, t[age]);
    // Simsiyah saç düz siyah leke gibi durmasın: Bitmoji'deki koyu arduvaz tonu.
    final lum = c.computeLuminance();
    if (lum < 0.03) return _mix(c, const Color(0xFF3A3B47), 0.38 * (1 - lum / 0.03));
    return c;
  }();
  late final double hairLum = hairColor.computeLuminance();

  /// Saçın gölgesi, konturu ve parlaması. Çok koyu saçta parlama soğuk-gri
  /// (Bitmoji'deki mavimsi siyah), açık saçta sıcak açık ton.
  late final Color hairShadow = _mix(hairColor, const Color(0xFF120A06), 0.30 + 0.10 * hairLum);
  late final Color hairLine = _mix(hairColor, const Color(0xFF0A0604), 0.55);
  late final Color hairLight = hairLum < 0.04
      ? _mix(hairColor, const Color(0xFF8C8FA6), 0.42)
      : _mix(hairColor, const Color(0xFFFFF0D8), 0.28 + 0.18 * (1 - hairLum));
  late final Color hairShine = _mix(hairLight, Colors.white, 0.30);

  late final Color browColor =
      _mix(hairColor, const Color(0xFF2E2018), (0.10 + 0.50 * hairLum).clamp(0.0, 0.7));
  late final Color lashColor = _mix(hairLine, const Color(0xFF120B08), 0.6);
  static const Color ink = Color(0xFF1E1412);

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

  /// Konturun kalınlığı (küçük önizlemede biraz kalın ki görünsün).
  double get lineW => detailed ? 1.05 : 1.5;

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

  math.Random rngFor(int salt) => math.Random(salt * 9973 + 17);

  /// Cel gölge: [shape]'in, ışığa göre kaydırılmış kopyasının dışında kalan
  /// kısmı ([offset] yönünde hilal). Boolean yol işlemi yerine şeklin tamamı
  /// gölgelenir, kaydırılmış kopya [base] (şeklin taban rengi) ile yeniden
  /// boyanır — aynı görüntü, çok daha ucuz. Bu yüzden şeklin dolgusundan
  /// HEMEN SONRA, dokulardan önce çağrılmalıdır.
  void celShade(Canvas canvas, Path shape, Color color, {required Color base, Offset offset = const Offset(-5, -3), double blur = 1.4}) {
    canvas.save();
    canvas.clipPath(shape);
    canvas.drawPath(shape, fill(color));
    canvas.drawPath(shape.shift(offset), soft(base, blur));
    canvas.restore();
  }
}
