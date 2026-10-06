// Selfie → avatar BENZERLİK motoru (ML Kit'ten bağımsız, saf hesap).
//
// FaceAvatarAnalyzer, ML Kit'in bulduğu yüz konturlarını ve fotoğrafın
// piksellerini buraya verir; burada:
//   • yüz hizalı koordinat sistemi kurulur (göz ortası merkez, göz hattı yatay,
//     birim = iki göz arası mesafe) → baş eğikliği ve kameraya uzaklık etkisizdir,
//   • ten/saç/göz/kıyafet rengi Lab renk uzayında ölçülür (ışık farkına dayanıklı),
//   • saçın uzunluğu, hacmi, genişliği, kâkülü, dokusu ve alın yüksekliği
//     ölçülüp 90 saç stilinin her biri puanlanır (en yakın + alternatifler),
//   • sakal/bıyık, gözlük ve başörtüsü bölge karşılaştırmasıyla bulunur.
//
// Ayrı dosyada olmasının nedeni test edilebilirlik: sentetik bir resimle
// (test/kullaniciozellikler/face_likeness_test.dart) uçtan uca denenebilir.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Rect;

import '../models/face_avatar_config.dart';

// ============================================================== Lab renk
class LabColor {
  final double l, a, b;
  const LabColor(this.l, this.a, this.b);

  static double _lin(double c) => c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  static double _f(double t) => t > 0.008856 ? math.pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  static double _finv(double t) => t * t * t > 0.008856 ? t * t * t : (t - 16 / 116) / 7.787;
  static double _gam(double c) => c <= 0.0031308 ? 12.92 * c : 1.055 * math.pow(c, 1 / 2.4) - 0.055;

  factory LabColor.fromRgb(double r255, double g255, double b255) {
    final r = _lin(r255 / 255), g = _lin(g255 / 255), b = _lin(b255 / 255);
    final x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047;
    final y = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883;
    final fx = _f(x), fy = _f(y), fz = _f(z);
    return LabColor(116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz));
  }

  factory LabColor.fromColor(Color c) => LabColor.fromRgb(c.r * 255, c.g * 255, c.b * 255);

  Color toColor() {
    final fy = (l + 16) / 116;
    final fx = fy + a / 500;
    final fz = fy - b / 200;
    final x = 0.95047 * _finv(fx), y = _finv(fy), z = 1.08883 * _finv(fz);
    final r = 3.2406 * x - 1.5372 * y - 0.4986 * z;
    final g = -0.9689 * x + 1.8758 * y + 0.0415 * z;
    final bb = 0.0557 * x - 0.2040 * y + 1.0570 * z;
    int ch(double v) => (_gam(v.clamp(0.0, 1.0)) * 255).round().clamp(0, 255);
    return Color.fromARGB(255, ch(r), ch(g), ch(bb));
  }

  double get chroma => math.sqrt(a * a + b * b);

  /// Algısal uzaklık. [lw] < 1 aydınlık farkını (ışık/gölge) daha az önemser.
  double dist(LabColor o, {double lw = 1.0}) {
    final dl = (l - o.l) * lw, da = a - o.a, db = b - o.b;
    return math.sqrt(dl * dl + da * da + db * db);
  }

  LabColor withL(double nl) => LabColor(nl, a, b);

  /// Kanal kanal medyan: tek tük parlama/gölge örneklerine dayanıklı.
  static LabColor median(List<LabColor> xs) {
    double med(List<double> v) {
      v.sort();
      final n = v.length;
      return n.isOdd ? v[n ~/ 2] : (v[n ~/ 2 - 1] + v[n ~/ 2]) / 2;
    }

    return LabColor(med([for (final c in xs) c.l]), med([for (final c in xs) c.a]), med([for (final c in xs) c.b]));
  }

  @override
  String toString() => 'Lab(${l.toStringAsFixed(1)}, ${a.toStringAsFixed(1)}, ${b.toStringAsFixed(1)})';
}

/// [palette] içinde Lab uzayında en yakın rengin sırası.
int nearestIndex(LabColor c, List<Color> palette, {double lw = 1.0}) {
  var best = 0;
  var bestD = double.infinity;
  for (var i = 0; i < palette.length; i++) {
    final d = c.dist(LabColor.fromColor(palette[i]), lw: lw);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

// ============================================================== pikseller
/// RGBA bayt dizisi (ui.Image.toByteData(rawRgba)).
class RgbaPixels {
  final Uint8List data;
  final int width;
  final int height;
  const RgbaPixels(this.data, this.width, this.height);

  bool contains(double x, double y) => x >= 0 && y >= 0 && x < width && y < height;

  /// (x, y) çevresinde [r] piksellik karede ortalama (seyrek adımlarla).
  LabColor? average(double x, double y, int r) {
    if (!contains(x, y)) return null;
    final cx = x.round(), cy = y.round();
    final step = math.max(1, r ~/ 3);
    var rs = 0, gs = 0, bs = 0, n = 0;
    for (var dy = -r; dy <= r; dy += step) {
      for (var dx = -r; dx <= r; dx += step) {
        final px = cx + dx, py = cy + dy;
        if (px < 0 || py < 0 || px >= width || py >= height) continue;
        final i = (py * width + px) * 4;
        rs += data[i];
        gs += data[i + 1];
        bs += data[i + 2];
        n++;
      }
    }
    if (n == 0) return null;
    return LabColor.fromRgb(rs / n, gs / n, bs / n);
  }
}

/// Fotoğraf (algılama) uzayından piksel uzayına eşleme. EXIF dönüşü
/// uygulanmamışsa ML Kit koordinatları ile çözülen pikseller döner kalabilir.
typedef PointMap = Offset Function(Offset p);

List<PointMap> candidateMappings(int w, int h) => [
      (p) => p,
      (p) => Offset(p.dy, h - 1 - p.dx),
      (p) => Offset(w - 1 - p.dy, p.dx),
      (p) => Offset(w - 1 - p.dx, h - 1 - p.dy),
    ];

// ============================================================ yüz çerçevesi
/// Yüz hizalı koordinatlar: göz ortası (0,0), göz hattı +x, çene +y,
/// birim = gözler arası mesafe.
class FaceFrame {
  final Offset origin;
  final double angle;
  final double unit;
  const FaceFrame(this.origin, this.angle, this.unit);

  /// [eyeA] ve [eyeB] göz merkezleri; [below] yüzün alt tarafında bir nokta
  /// (burun/ağız) — çene yönünü belirler.
  factory FaceFrame.fromEyes(Offset eyeA, Offset eyeB, Offset below) {
    final mid = (eyeA + eyeB) / 2;
    final unit = math.max(4.0, (eyeB - eyeA).distance);
    var f = FaceFrame(mid, math.atan2(eyeB.dy - eyeA.dy, eyeB.dx - eyeA.dx), unit);
    if (f.toFace(below).dy < 0) {
      f = FaceFrame(mid, math.atan2(eyeA.dy - eyeB.dy, eyeA.dx - eyeB.dx), unit);
    }
    return f;
  }

  Offset toFace(Offset p) {
    final d = p - origin;
    final c = math.cos(-angle), s = math.sin(-angle);
    return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c) / unit;
  }

  Offset toImage(Offset f) {
    final c = math.cos(angle), s = math.sin(angle);
    final x = f.dx * unit, y = f.dy * unit;
    return origin + Offset(x * c - y * s, x * s + y * c);
  }
}

/// Yüz koordinatlarında örnekleme.
class FaceSampler {
  final RgbaPixels px;
  final FaceFrame frame;
  const FaceSampler(this.px, this.frame);

  bool inside(Offset f) {
    final p = frame.toImage(f);
    return px.contains(p.dx, p.dy);
  }

  LabColor? at(Offset f, {double radius = 0.03}) {
    final p = frame.toImage(f);
    return px.average(p.dx, p.dy, math.max(1, (radius * frame.unit).round()));
  }

  /// Dikdörtgen bölgede ızgara örnekleri (resim dışı noktalar atlanır).
  List<LabColor> grid(Rect r, {int nx = 6, int ny = 4, double radius = 0.03}) {
    final out = <LabColor>[];
    for (var j = 0; j < ny; j++) {
      for (var i = 0; i < nx; i++) {
        final x = nx == 1 ? r.center.dx : r.left + r.width * i / (nx - 1);
        final y = ny == 1 ? r.center.dy : r.top + r.height * j / (ny - 1);
        final c = at(Offset(x, y), radius: radius);
        if (c != null) out.add(c);
      }
    }
    return out;
  }
}

// ======================================================== yüz geometrisi
/// ML Kit konturlarının yüz koordinatlarındaki karşılığı.
class FaceGeometry {
  final List<Offset> contour;
  final List<Offset> browTop;
  final List<Offset> browBottom;
  final List<Offset> eyeA;
  final List<Offset> eyeB;
  final List<Offset> upperLipTop;
  final List<Offset> lowerLipBottom;
  final List<Offset> noseBottom;

  FaceGeometry({
    required this.contour,
    required this.browTop,
    required this.browBottom,
    required this.eyeA,
    required this.eyeB,
    required this.upperLipTop,
    required this.lowerLipBottom,
    required this.noseBottom,
  });

  static double _minY(List<Offset> p, double fb) => p.isEmpty ? fb : p.map((e) => e.dy).reduce(math.min);
  static double _maxY(List<Offset> p, double fb) => p.isEmpty ? fb : p.map((e) => e.dy).reduce(math.max);
  static double _avgY(List<Offset> p, double fb) => p.isEmpty ? fb : p.map((e) => e.dy).reduce((a, b) => a + b) / p.length;
  static double _spanX(List<Offset> p) =>
      p.isEmpty ? 0 : p.map((e) => e.dx).reduce(math.max) - p.map((e) => e.dx).reduce(math.min);
  static double _spanY(List<Offset> p) =>
      p.isEmpty ? 0 : p.map((e) => e.dy).reduce(math.max) - p.map((e) => e.dy).reduce(math.min);

  late final double contourTop = _minY(contour, -1.15);
  late final double chinY = _maxY(contour, 1.6);
  late final double browTopY = _avgY(browTop, -0.36);
  late final double browBottomY = _avgY(browBottom, -0.25);
  late final double noseBottomY = _maxY(noseBottom, 0.8);
  late final double mouthTop = _minY(upperLipTop, 1.0);
  late final double mouthBottom = _maxY(lowerLipBottom, 1.4);
  late final double mouthHalf = math.max(_spanX(upperLipTop), _spanX(lowerLipBottom)) / 2;
  late final double noseWidth = _spanX(noseBottom);
  late final double eyeWidth = math.max(_spanX(eyeA), _spanX(eyeB));
  late final double eyeHeight = math.max(_spanY(eyeA), _spanY(eyeB));
  late final Offset eyeACenter = _center(eyeA, const Offset(-0.5, 0));
  late final Offset eyeBCenter = _center(eyeB, const Offset(0.5, 0));

  static Offset _center(List<Offset> p, Offset fb) {
    if (p.isEmpty) return fb;
    var s = Offset.zero;
    for (final e in p) {
      s += e;
    }
    return s / p.length.toDouble();
  }

  /// Kontur çokgeninin y'deki sol ve sağ kenarı (yatay kesişim).
  (double, double)? edgesAt(double y) {
    if (contour.length < 3) return null;
    double? lo, hi;
    for (var i = 0; i < contour.length; i++) {
      final a = contour[i], b = contour[(i + 1) % contour.length];
      if ((a.dy - y) * (b.dy - y) > 0 || a.dy == b.dy) continue;
      final t = (y - a.dy) / (b.dy - a.dy);
      final x = a.dx + (b.dx - a.dx) * t;
      lo = lo == null ? x : math.min(lo, x);
      hi = hi == null ? x : math.max(hi, x);
    }
    if (lo == null || hi == null || hi - lo < 0.05) return null;
    return (lo, hi);
  }

  double widthAt(double y) {
    final e = edgesAt(y);
    return e == null ? 0 : e.$2 - e.$1;
  }

  /// y'deki yüz (ya da çenenin altında boyun) yarı genişliği.
  double halfAt(double y) {
    if (y >= chinY - 0.05) return 0.62;
    final e = edgesAt(y);
    if (e == null) return 1.0;
    return (e.$2 - e.$1) / 2;
  }
}

// ======================================================= ölçüm sonuçları
enum FringeKind { none, side, blunt, curtain }

class HairObservation {
  final bool bald;
  final bool covered;

  /// HairLength ölçeği: 0 kel, 1 sıfır, 2 asker, 3 kısa, 4 kulak, 5 çene,
  /// 6 omuz, 7 uzun, 8 çok uzun.
  final double length;
  final double volume;
  final double width;
  final FringeKind fringe;

  /// Kâkülün örttüğü taraf (yüz koordinatı: -1 sol, +1 sağ).
  final int fringeSide;

  /// Kaşın üstünde görünen alın yüksekliği (göz arası birimi).
  final double forehead;
  final double curl;
  final bool bunOnTop;

  const HairObservation({
    this.bald = false,
    this.covered = false,
    this.length = 3,
    this.volume = 0.45,
    this.width = 0.25,
    this.fringe = FringeKind.none,
    this.fringeSide = 0,
    this.forehead = 0.8,
    this.curl = 0,
    this.bunOnTop = false,
  });

  @override
  String toString() =>
      'Hair(bald=$bald covered=$covered len=${length.toStringAsFixed(1)} vol=${volume.toStringAsFixed(2)} '
      'wid=${width.toStringAsFixed(2)} fringe=$fringe/$fringeSide fh=${forehead.toStringAsFixed(2)} '
      'curl=${curl.toStringAsFixed(2)} bun=$bunOnTop)';
}

double _specLength(HairSpec s) => switch (s.length) {
      HairLength.bald => 0,
      HairLength.buzz => 1,
      HairLength.crop => 2,
      HairLength.short => 3,
      HairLength.ear => 4,
      HairLength.jaw => 5,
      HairLength.shoulder => 6,
      HairLength.long => 7,
      HairLength.xlong => 8,
      HairLength.pulled => 3,
    };

FringeKind _specFringe(HairSpec s) => switch (s.fringe) {
      HairFringe.sweep || HairFringe.sweepLong || HairFringe.wave || HairFringe.comb => FringeKind.side,
      HairFringe.blunt || HairFringe.wispy => FringeKind.blunt,
      HairFringe.curtain => FringeKind.curtain,
      _ => FringeKind.none,
    };

double _specCurl(HairSpec s) => switch (s.texture) {
      HairTexture.smooth => 0,
      HairTexture.wavy => 0.35 + 0.2 * s.curl,
      HairTexture.curly => 0.75,
      HairTexture.coily => 1.0,
    };

/// Fotoğraftan kendiliğinden seçilmeyecek, ancak kullanıcının seçebileceği
/// özel biçimler (mohawk, örgüler, iki topuz…).
bool _exotic(HairSpec s) {
  switch (s.tie) {
    case HairTie.mohawk:
    case HairTie.flatTop:
    case HairTie.twists:
    case HairTie.cornrows:
    case HairTie.dreads:
    case HairTie.boxBraids:
    case HairTie.afroPuffs:
    case HairTie.spaceBuns:
    case HairTie.pigtails:
    case HairTie.braidsTwo:
    case HairTie.crownBraid:
    case HairTie.fishtail:
    case HairTie.braid:
    case HairTie.braidSide:
    case HairTie.ponySide:
      return true;
    default:
      return s.length == HairLength.buzz && s.tie != HairTie.none;
  }
}

/// Saç stillerini gözleme uzaklığına göre sıralar (ilki en benzer).
List<int> rankHairStyles(HairObservation o) {
  final scores = <int, double>{};
  for (var i = 0; i < kHairStyles.length; i++) {
    final s = kHairStyles[i];
    var sc = 0.0;
    if (o.covered) {
      sc = s.covered ? (s.cover == HairCover.hijab ? 0.0 : 1.0 + i * 0.01) : 100.0;
      scores[i] = sc;
      continue;
    }
    if (s.covered) {
      scores[i] = 100;
      continue;
    }
    if (o.bald) {
      sc = s.bald ? 0 : (s.hairline == Hairline.receding || s.length == HairLength.buzz ? 3 : 50);
      scores[i] = sc + i * 0.001;
      continue;
    }
    if (s.bald) {
      scores[i] = 60;
      continue;
    }
    final dl = _specLength(s) - o.length;
    sc += 1.1 * dl * dl;
    sc += 1.6 * (s.volume - o.volume) * (s.volume - o.volume);
    sc += 1.3 * (s.width - o.width) * (s.width - o.width);
    final dc = _specCurl(s) - o.curl;
    sc += 2.4 * dc * dc;
    final sf = _specFringe(s);
    if (sf != o.fringe) {
      sc += (sf == FringeKind.none || o.fringe == FringeKind.none) ? 1.6 : 2.4;
    }
    // Uzun saçta yan kâkül yönü: ayrım, kâkülün örttüğü tarafın tersindedir.
    if (sf == FringeKind.side && o.fringe == FringeKind.side && o.fringeSide != 0 && s.part != 0 && s.part == o.fringeSide) {
      sc += 0.4;
    }
    final receding = s.hairline == Hairline.receding || s.hairline == Hairline.mShape || s.hairline == Hairline.high;
    if (o.forehead > 1.05) {
      sc += receding ? -0.8 : 0.6;
    } else if (receding) {
      sc += 1.2;
    }
    if (s.length == HairLength.pulled || s.tie != HairTie.none) {
      final bun = s.tie == HairTie.bunHigh || s.tie == HairTie.bunTop || s.tie == HairTie.bunMessy || s.tie == HairTie.bunBallet;
      sc += o.bunOnTop ? (bun ? -1.5 : 0.5) : 2.2;
    }
    if (s.fade != HairFade.none) sc += 0.5;
    if (_exotic(s)) sc += 6;
    scores[i] = sc + i * 0.0001;
  }
  final order = scores.keys.toList()..sort((a, b) => scores[a]!.compareTo(scores[b]!));
  return order;
}

class BeardObservation {
  /// Bölgelerin yanaktan ne kadar koyu olduğu (Lab L farkı).
  final double chin;
  final double jaw;
  final double mustache;
  final double belowChin;
  const BeardObservation({this.chin = 0, this.jaw = 0, this.mustache = 0, this.belowChin = 0});

  @override
  String toString() =>
      'Beard(chin=${chin.toStringAsFixed(1)} jaw=${jaw.toStringAsFixed(1)} must=${mustache.toStringAsFixed(1)} below=${belowChin.toStringAsFixed(1)})';
}

/// Sakal etiketini seçer. [strict] uzun saçlı/başörtülü yüzlerde eşikleri
/// yükseltir (çene altı gölgesi sakal sanılmasın).
String pickBeardLabel(BeardObservation o, {bool strict = false}) {
  final k = strict ? 5.0 : 0.0;
  final chin = o.chin - k, jaw = o.jaw - k, must = o.mustache - k, below = o.belowChin - k;
  if (chin >= 13 && jaw >= 12) {
    if (below >= 20 && chin >= 22) return 'Uzun Sakal';
    if (below >= 12 || chin >= 20) return 'Tam Sakal';
    return 'Kısa Sakal';
  }
  if (chin >= 13 && must >= 11) return 'Keçi';
  if (must >= 13 && chin < 9) return 'Bıyık';
  if (chin >= 14) return 'Çene Ucu';
  final avg = (chin + jaw + must) / 3;
  if (avg >= 10.5) return 'Yoğun Üç Günlük';
  if (avg >= 8) return 'Üç Günlük';
  if (avg >= 6.5 && !strict) return 'Hafif';
  return 'Yok';
}

// =================================================== yüz şekli ve oranlar
/// Ölçülen oranları katalogdaki yüz şekillerinin oranlarıyla karşılaştırıp
/// en yakınını seçer. Karşılaştırma her iki tarafı da kendi "oval"
/// referansına bölerek yapılır; böylece fotoğraf ile çizim arasındaki ölçüm
/// farkı sonucu bozmaz.
int pickFaceShape({required double jawOverFace, required double foreheadOverFace, required double lengthOverHalfWidth}) {
  if (jawOverFace <= 0 || foreheadOverFace <= 0 || lengthOverHalfWidth <= 0) return 0;
  const avgJaw = 0.84;
  const avgForehead = 0.93;
  const avgLength = 1.50;

  double specJaw(FaceShapeSpec s) => (kFaceBaseJawHalf * s.jaw) / (kFaceBaseCheekHalf * s.cheek);
  double specForehead(FaceShapeSpec s) => (kFaceBaseForeheadHalf * s.forehead) / (kFaceBaseCheekHalf * s.cheek);
  double specLength(FaceShapeSpec s) => (kFaceBaseChinLength * s.chin - 1) / (kFaceBaseCheekHalf * s.cheek);

  final oval = kFaceShapes.first;
  final refJaw = specJaw(oval), refForehead = specForehead(oval), refLength = specLength(oval);
  final mJaw = jawOverFace / avgJaw;
  final mForehead = foreheadOverFace / avgForehead;
  final mLength = lengthOverHalfWidth / avgLength;

  var best = 0;
  var bestScore = double.infinity;
  for (var i = 0; i < kFaceShapes.length; i++) {
    final s = kFaceShapes[i];
    final dJaw = (specJaw(s) / refJaw) - mJaw;
    final dFore = (specForehead(s) / refForehead) - mForehead;
    final dLen = (specLength(s) / refLength) - mLength;
    final score = dJaw * dJaw * 1.6 + dFore * dFore * 1.2 + dLen * dLen;
    if (score < bestScore) {
      bestScore = score;
      best = i;
    }
  }
  return best;
}

int _labelIndex(List<String> labels, String label, [int fallback = 0]) {
  final i = labels.indexOf(label);
  return i < 0 ? fallback : i;
}

int pickEyeStyle({required double aspect, required double size, required double tilt}) {
  final labels = kEyeStyles.map((e) => e.label).toList();
  if (aspect <= 0 || size <= 0) return 0;
  if (tilt > 0.10) return _labelIndex(labels, 'Çekik');
  if (tilt < -0.10) return _labelIndex(labels, 'Düşük');
  if (aspect < 0.26) return _labelIndex(labels, 'Uykulu');
  if (aspect < 0.33) return _labelIndex(labels, 'Badem');
  if (aspect > 0.52) return _labelIndex(labels, size > 0.44 ? 'İri' : 'Yuvarlak');
  if (size < 0.36) return _labelIndex(labels, 'Küçük');
  return _labelIndex(labels, 'Normal');
}

int pickBrowStyle({required double thickness, required double arch}) {
  final labels = kBrowStyles.map((e) => e.label).toList();
  if (thickness <= 0) return _labelIndex(labels, 'Doğal', 1);
  if (thickness > 0.185) return _labelIndex(labels, 'Çok Kalın', 1);
  if (thickness > 0.150) return _labelIndex(labels, 'Kalın', 1);
  if (thickness < 0.085) return _labelIndex(labels, 'İnce', 1);
  if (arch > 0.10) return _labelIndex(labels, 'Yay', 1);
  if (arch < 0.03) return _labelIndex(labels, 'Düz', 1);
  return _labelIndex(labels, 'Doğal', 1);
}

/// Ölçülen değeri ortalamaya oranlar; [gain] > 1 farkı hafifçe abartır
/// (karikatürde benzerliği artırır), [spread] uç değerleri sınırlar.
double metricRatio(double measured, double expected, {double spread = 0.22, double gain = 1.1}) {
  if (measured <= 0 || expected <= 0) return 1.0;
  final r = measured / expected;
  return (1 + (r - 1) * gain).clamp(1 - spread, 1 + spread);
}

// ====================================================== piksel analizleri
/// Fotoğraf + yüz geometrisi üzerinden renk ve saç/sakal/gözlük ölçümleri.
class LikenessProbe {
  final FaceSampler s;
  final FaceGeometry g;
  LikenessProbe(this.s, this.g);

  // ----------------------------------------------------------------- ten
  late final LabColor? skin = () {
    final samples = <LabColor>[
      ...s.grid(Rect.fromLTRB(-0.78, 0.38, -0.48, 0.72), nx: 3, ny: 3, radius: 0.04),
      ...s.grid(Rect.fromLTRB(0.48, 0.38, 0.78, 0.72), nx: 3, ny: 3, radius: 0.04),
    ];
    if (samples.length < 4) return null;
    // Aşırı parlak (ışık yansıması) ve aşırı karanlık örnekleri at.
    final med = LabColor.median(samples);
    final kept = samples.where((c) => (c.l - med.l).abs() < 14).toList();
    return LabColor.median(kept.length >= 3 ? kept : samples);
  }();

  // ----------------------------------------------------------- arka plan
  /// Kadrajın köşeleri ve yüzden uzak noktalar (arka plan adayları).
  late final List<LabColor> _farSamples = () {
    final out = <LabColor>[];
    final w = s.px.width.toDouble(), h = s.px.height.toDouble();
    for (final p in [Offset(w * 0.04, h * 0.04), Offset(w * 0.96, h * 0.04), Offset(w * 0.04, h * 0.30), Offset(w * 0.96, h * 0.30)]) {
      final c = s.px.average(p.dx, p.dy, math.max(2, (w * 0.012).round()));
      if (c != null) out.add(c);
    }
    for (final f in const [Offset(-2.5, -1.4), Offset(2.5, -1.4), Offset(-2.7, 0.2), Offset(2.7, 0.2)]) {
      final c = s.at(f, radius: 0.05);
      if (c != null) out.add(c);
    }
    final sk = skin;
    return [for (final c in out) if (sk == null || c.dist(sk, lw: 0.6) > 12) c];
  }();

  /// Arka plan: uzak örneklerden saça benzemeyenler. (Yakın çekimde köşeleri
  /// saç doldurabilir; onlar arka plan sayılmaz.)
  late final List<LabColor> background = () {
    final hc = hairColor;
    return [for (final c in _farSamples) if (hc == null || c.dist(hc, lw: 0.6) > 14) c];
  }();

  // ------------------------------------------------------------- saç rengi
  /// Önce alnın HEMEN üstündeki bant (neredeyse her zaman saç ya da kel
  /// kafa derisi): arka plandan bağımsız ölçülür. Bant ten rengindeyse saç
  /// çizgisi gerideymiş ya da kel: daha yukarıda, arka plana benzemeyen
  /// örnekler aranır.
  late final LabColor? hairColor = () {
    final sk = skin;
    final top = g.contourTop;
    bool notSkin(LabColor c) => sk == null || c.dist(sk, lw: 0.6) > 14;
    LabColor bodyOf(List<LabColor> cands) {
      // Saç parlamalarını değil gövde rengini al: en açık %25'i at.
      cands.sort((a, b) => a.l.compareTo(b.l));
      return LabColor.median(cands.sublist(0, math.max(3, (cands.length * 0.75).round())));
    }

    final near = s.grid(Rect.fromLTRB(-0.45, top - 0.32, 0.45, top - 0.05), nx: 7, ny: 3, radius: 0.03);
    final nearHair = near.where(notSkin).toList();
    if (near.isNotEmpty && nearHair.length >= math.max(4, near.length * 0.4)) return bodyOf(nearHair);

    final far = s.grid(Rect.fromLTRB(-0.5, top - 0.8, 0.5, top - 0.32), nx: 7, ny: 4, radius: 0.03);
    final farHair = [
      for (final c in far)
        if (notSkin(c) && !_farSamples.any((b) => c.dist(b) < 10)) c,
    ];
    if (farHair.length < 5) return null;
    return bodyOf(farHair);
  }();

  /// Pikselin saç olup olmadığı (renk + ten/arka plan ayrımı).
  bool isHair(LabColor c) {
    final hc = hairColor;
    if (hc == null) return false;
    final dh = c.dist(hc, lw: 0.55);
    if (dh > 18) return false;
    final sk = skin;
    if (sk != null && c.dist(sk, lw: 0.55) < dh * 1.1) return false;
    for (final b in background) {
      if (c.dist(b) + 2 < dh) return false;
    }
    return true;
  }

  bool isSkin(LabColor c) {
    final sk = skin;
    if (sk == null) return false;
    return c.dist(sk, lw: 0.5) < 12;
  }

  double hairFrac(Rect r, {int nx = 5, int ny = 3}) {
    final xs = s.grid(r, nx: nx, ny: ny, radius: 0.025);
    if (xs.isEmpty) return -1;
    return xs.where(isHair).length / xs.length;
  }

  // -------------------------------------------------------------- başörtüsü
  late final LabColor? coverColor = () {
    final sk = skin;
    if (sk == null) return null;
    final top = s.grid(Rect.fromLTRB(-0.5, g.contourTop - 0.55, 0.5, g.contourTop - 0.12), nx: 5, ny: 3, radius: 0.03);
    final sides = <LabColor>[];
    for (final y in const [0.0, 0.35, 0.7]) {
      final half = g.halfAt(y);
      for (final sgn in const [-1.0, 1.0]) {
        final c = s.at(Offset(sgn * (half + 0.22), y), radius: 0.05);
        if (c != null) sides.add(c);
      }
    }
    final neck = s.grid(Rect.fromLTRB(-0.22, g.chinY + 0.22, 0.22, g.chinY + 0.42), nx: 3, ny: 2, radius: 0.04);
    if (top.length < 5 || sides.length < 4 || neck.length < 3) return null;
    final t = LabColor.median(top), sd = LabColor.median(sides), nk = LabColor.median(neck);
    final fabric = t.dist(sd, lw: 0.6) < 14 && t.dist(nk, lw: 0.6) < 16;
    final notSkin = nk.dist(sk, lw: 0.6) > 20 && t.dist(sk, lw: 0.6) > 20;
    return fabric && notSkin ? t : null;
  }();

  // --------------------------------------------------------------------- saç
  late final HairObservation hair = () {
    final sk = skin;
    if (coverColor != null) return const HairObservation(covered: true, length: 6);

    final top = g.contourTop;
    // Tepe: saç yoksa ve ten devam ediyorsa kel.
    final topRow = s.grid(Rect.fromLTRB(-0.45, top - 0.45, 0.45, top - 0.10), nx: 6, ny: 3, radius: 0.03);
    final skinTop = topRow.isEmpty ? 0.0 : topRow.where(isSkin).length / topRow.length;
    if (hairColor == null || (skinTop > 0.55 && topRow.where(isHair).length < topRow.length * 0.2)) {
      final sideHair = math.max(
        hairFrac(Rect.fromLTRB(-g.halfAt(-0.3) - 0.3, -0.5, -g.halfAt(-0.3) + 0.05, 0.1)),
        hairFrac(Rect.fromLTRB(g.halfAt(-0.3) - 0.05, -0.5, g.halfAt(-0.3) + 0.3, 0.1)),
      );
      return HairObservation(bald: sideHair < 0.35, length: sideHair < 0.35 ? 0 : 2, volume: 0.1, width: 0.05, forehead: 1.6);
    }

    // Hacim: merkez sütunda saçın bittiği en üst nokta.
    var hairTop = top;
    var reachedEdge = false;
    for (var y = top - 0.05; y > top - 1.6; y -= 0.04) {
      final row = [-0.2, 0.0, 0.2].map((x) => s.at(Offset(x, y), radius: 0.025)).whereType<LabColor>().toList();
      if (row.isEmpty) {
        reachedEdge = true;
        break;
      }
      if (row.where(isHair).length >= 2) hairTop = y;
      if (y < hairTop - 0.16) break;
    }
    final extent = top - hairTop;
    final volume = reachedEdge ? 0.55 : ((extent - 0.28) / 0.42).clamp(0.0, 1.6);

    // Bun: tepede dar ama yüksek ek kütle.
    var bunOnTop = false;
    if (!reachedEdge && extent > 0.5) {
      final wideAtTop = hairFrac(Rect.fromLTRB(-0.7, hairTop + 0.12, -0.35, hairTop + 0.22), nx: 3, ny: 1) +
          hairFrac(Rect.fromLTRB(0.35, hairTop + 0.12, 0.7, hairTop + 0.22), nx: 3, ny: 1);
      bunOnTop = wideAtTop < 0.3;
    }

    // Genişlik: şakak hizasında yüz kenarının dışına taşan saç.
    double sideExtent(double sgn) {
      final half = g.halfAt(-0.3);
      var ext = 0.0;
      var miss = 0;
      for (var d = 0.04; d < 1.4; d += 0.05) {
        final c = s.at(Offset(sgn * (half + d), -0.3), radius: 0.025);
        if (c == null) break;
        if (isHair(c)) {
          ext = d;
          miss = 0;
        } else if (++miss >= 2) {
          break;
        }
      }
      return ext;
    }

    final ext = (sideExtent(-1) + sideExtent(1)) / 2;
    final width = ((ext - 0.10) / 0.36).clamp(0.0, 1.6);

    // Uzunluk: yüzün yanında aşağı doğru seviye seviye saç var mı.
    bool sideHairAt(double y) {
      final half = g.halfAt(y);
      final near = y >= g.chinY - 0.05 ? (0.55, 1.05) : (half + 0.04, half + 0.40);
      final l = hairFrac(Rect.fromLTRB(-near.$2, y - 0.08, -near.$1, y + 0.08), nx: 4, ny: 2);
      final r = hairFrac(Rect.fromLTRB(near.$1, y - 0.08, near.$2, y + 0.08), nx: 4, ny: 2);
      if (l < 0 && r < 0) return false;
      // Çok uzakta da aynı renk varsa arka plandır (koyu duvar vb.).
      final farL = hairFrac(Rect.fromLTRB(-(near.$2 + 1.1), y - 0.08, -(near.$2 + 0.8), y + 0.08), nx: 2, ny: 2);
      final farR = hairFrac(Rect.fromLTRB(near.$2 + 0.8, y - 0.08, near.$2 + 1.1, y + 0.08), nx: 2, ny: 2);
      final lOk = l > 0.5 && farL < 0.6;
      final rOk = r > 0.5 && farR < 0.6;
      // Göğüs/omuz hizasında ortası da aynı renkse kıyafettir.
      if (y > g.chinY + 0.4) {
        final mid = hairFrac(Rect.fromLTRB(-0.25, y - 0.06, 0.25, y + 0.06), nx: 3, ny: 1);
        if (mid > 0.6) return false;
      }
      return (lOk && rOk) || ((l > 0.7 && farL < 0.4) || (r > 0.7 && farR < 0.4));
    }

    final levels = <double, double>{0.25: 4, 0.95: 5, g.chinY - 0.05: 5.5, g.chinY + 0.5: 6, g.chinY + 1.1: 7, g.chinY + 1.7: 8};
    var length = volume < 0.18 ? 2.0 : 3.0;
    for (final e in levels.entries) {
      if (!s.inside(Offset(0, e.key))) {
        if (length >= 6) length = math.max(length, 7);
        break;
      }
      if (sideHairAt(e.key)) {
        length = e.value;
      } else {
        break;
      }
    }

    // Kâkül: kaşların üstündeki alın bandı.
    final fTop = math.max(top + 0.06, g.browTopY - 0.75);
    final fBot = g.browTopY - 0.10;
    double band(double x0, double x1, double y0, double y1) => hairFrac(Rect.fromLTRB(x0, y0, x1, y1), nx: 3, ny: 3).clamp(0.0, 1.0);
    final left = band(-0.7, -0.15, fTop, fBot);
    final right = band(0.15, 0.7, fTop, fBot);
    final center = band(-0.15, 0.15, fTop, fBot);
    final low = band(-0.6, 0.6, fBot - 0.12, fBot);
    var fringe = FringeKind.none;
    var fringeSide = 0;
    final total = (left + right + center) / 3;
    if (total >= 0.18) {
      if (low > 0.55 && left > 0.5 && right > 0.5) {
        fringe = FringeKind.blunt;
      } else if ((left - right).abs() > 0.3) {
        fringe = FringeKind.side;
        fringeSide = left > right ? -1 : 1;
      } else if (center < 0.3 && left > 0.35 && right > 0.35) {
        fringe = FringeKind.curtain;
      } else if (total > 0.45) {
        fringe = FringeKind.blunt;
      }
    }

    // Alın yüksekliği: kaşın üstünden saç başlayana kadar.
    var forehead = 1.6;
    for (var y = g.browTopY - 0.06; y > g.browTopY - 1.6; y -= 0.04) {
      final row = [-0.15, 0.0, 0.15].map((x) => s.at(Offset(x, y), radius: 0.02)).whereType<LabColor>().toList();
      if (row.isEmpty) break;
      if (row.where(isHair).length >= 2) {
        forehead = g.browTopY - y;
        break;
      }
    }

    // Doku: saç bölgesindeki ince ölçekli aydınlık değişimi (kıvırcıkta yüksek).
    var rough = 0.0, n = 0;
    for (var y = top - 0.5; y < top - 0.08; y += 0.045) {
      for (var x = -0.5; x <= 0.5; x += 0.045) {
        final c = s.at(Offset(x, y), radius: 0.008);
        if (c == null || !isHair(c)) continue;
        final nb = [
          s.at(Offset(x + 0.022, y), radius: 0.008),
          s.at(Offset(x - 0.022, y), radius: 0.008),
          s.at(Offset(x, y + 0.022), radius: 0.008),
          s.at(Offset(x, y - 0.022), radius: 0.008),
        ].whereType<LabColor>().toList();
        if (nb.length < 3) continue;
        final mean = nb.map((e) => e.l).reduce((a, b) => a + b) / nb.length;
        rough += (c.l - mean).abs();
        n++;
      }
    }
    final roughness = n == 0 ? 0.0 : rough / n;
    // Geniş/hacimli silüet kıvırcıklığı destekler.
    final curl = (((roughness - 4.5) / 6.0) + (width > 0.7 && volume > 0.7 ? 0.25 : 0.0)).clamp(0.0, 1.0);

    if (sk == null) return const HairObservation();
    return HairObservation(
      length: length,
      volume: volume,
      width: width,
      fringe: fringe,
      fringeSide: fringeSide,
      forehead: forehead,
      curl: curl,
      bunOnTop: bunOnTop,
    );
  }();

  // ------------------------------------------------------------------ sakal
  late final BeardObservation beard = () {
    double darker(Rect r, LabColor? ref) {
      if (ref == null) return 0;
      final xs = s.grid(r, nx: 4, ny: 3, radius: 0.025);
      if (xs.length < 4) return 0;
      final m = LabColor.median(xs);
      var d = ref.l - m.l;
      // Sakal, tenden daha az doygundur; doygun koyuluk (kızarıklık/ruj) sayılmaz.
      if (m.chroma > ref.chroma + 6) d -= 6;
      return d;
    }

    LabColor? med(List<LabColor> xs) => xs.length < 3 ? skin : LabColor.median(xs);
    final cheekL = med(s.grid(Rect.fromLTRB(-0.75, 0.42, -0.5, 0.62), nx: 3, ny: 2, radius: 0.04));
    final cheekR = med(s.grid(Rect.fromLTRB(0.5, 0.42, 0.75, 0.62), nx: 3, ny: 2, radius: 0.04));
    final ref = skin;
    final chin = darker(Rect.fromLTRB(-0.24, g.mouthBottom + 0.10, 0.24, g.chinY - 0.08), ref);
    final jawY0 = math.min(g.mouthBottom, g.chinY - 0.3);
    final jaw = math.min(
      darker(Rect.fromLTRB(-g.halfAt(jawY0) + 0.12, jawY0, -g.halfAt(jawY0) + 0.38, g.chinY - 0.2), cheekL),
      darker(Rect.fromLTRB(g.halfAt(jawY0) - 0.38, jawY0, g.halfAt(jawY0) - 0.12, g.chinY - 0.2), cheekR),
    );
    final must = darker(Rect.fromLTRB(-0.20, g.noseBottomY + 0.05, 0.20, g.mouthTop - 0.03), ref);
    final below = darker(Rect.fromLTRB(-0.2, g.chinY + 0.06, 0.2, g.chinY + 0.22), ref);
    return BeardObservation(chin: chin, jaw: jaw, mustache: must, belowChin: below);
  }();

  // ----------------------------------------------------------------- gözlük
  /// İnce koyu çizgi (çerçeve) şiddeti: profildeki en derin dar çukur.
  static double thinDip(List<double> l, {int k = 3}) {
    var best = 0.0;
    for (var i = k; i < l.length - k; i++) {
      final a = l.sublist(i - k, i).reduce(math.max);
      final b = l.sublist(i + 1, i + k + 1).reduce(math.max);
      final d = math.min(a, b) - l[i];
      if (d > best) best = d;
    }
    return best;
  }

  List<double> _profile(double x, double y0, double y1, {double step = 0.02}) {
    final out = <double>[];
    for (var y = y0; y <= y1; y += step) {
      final c = s.at(Offset(x, y), radius: 0.01);
      if (c != null) out.add(c.l);
    }
    return out;
  }

  /// Gözlük: 'Yok', 'İnce Çerçeve', 'Kalın Çerçeve' ya da 'Güneş'.
  late final String glasses = () {
    // Güneş gözlüğü: her iki göz bölgesi koyu ve tekdüze.
    final eyeA = s.grid(Rect.fromCenter(center: g.eyeACenter, width: 0.4, height: 0.2), nx: 3, ny: 2, radius: 0.02);
    final eyeB = s.grid(Rect.fromCenter(center: g.eyeBCenter, width: 0.4, height: 0.2), nx: 3, ny: 2, radius: 0.02);
    if (eyeA.length >= 4 && eyeB.length >= 4) {
      final la = LabColor.median(eyeA).l, lb = LabColor.median(eyeB).l;
      final sk = skin;
      if (la < 24 && lb < 24 && sk != null && sk.l - math.max(la, lb) > 25) return 'Güneş';
    }
    final bridge = thinDip(_profile(0, -0.30, 0.14));
    final rimA = thinDip(_profile(g.eyeACenter.dx, g.eyeACenter.dy + 0.16, g.eyeACenter.dy + 0.58));
    final rimB = thinDip(_profile(g.eyeBCenter.dx, g.eyeBCenter.dy + 0.16, g.eyeBCenter.dy + 0.58));
    final templeA = thinDip(_profile(-g.halfAt(-0.1) + 0.08, -0.32, 0.16));
    final templeB = thinDip(_profile(g.halfAt(-0.1) - 0.08, -0.32, 0.16));
    final score = (bridge >= 10 ? 1.0 : 0.0) +
        (rimA >= 10 ? 1.0 : 0.0) +
        (rimB >= 10 ? 1.0 : 0.0) +
        (templeA >= 10 ? 0.5 : 0.0) +
        (templeB >= 10 ? 0.5 : 0.0);
    if (score < 2.5 || bridge < 8) return 'Yok';
    final strength = (bridge + rimA + rimB) / 3;
    return strength > 30 ? 'Kalın Çerçeve' : 'İnce Çerçeve';
  }();

  // ---------------------------------------------------------------- renkler
  late final LabColor? eyeColor = () {
    final out = <LabColor>[];
    for (final c in [g.eyeACenter, g.eyeBCenter]) {
      for (final r in const [0.045, 0.07]) {
        for (var k = 0; k < 8; k++) {
          final a = k * math.pi / 4;
          final p = s.at(c + Offset(math.cos(a), math.sin(a) * 0.6) * r, radius: 0.008);
          if (p != null && p.l > 10 && p.l < 72) out.add(p);
        }
      }
    }
    return out.length < 6 ? null : LabColor.median(out);
  }();

  late final LabColor? lipColor = () {
    final xs = s.grid(Rect.fromLTRB(-g.mouthHalf * 0.5, g.mouthBottom - 0.10, g.mouthHalf * 0.5, g.mouthBottom - 0.04), nx: 3, ny: 2, radius: 0.015);
    return xs.length < 3 ? null : LabColor.median(xs);
  }();

  late final LabColor? clothing = () {
    final xs = s.grid(Rect.fromLTRB(-0.7, g.chinY + 0.95, 0.7, g.chinY + 1.35), nx: 5, ny: 2, radius: 0.05);
    if (xs.length < 5) return null;
    final m = LabColor.median(xs);
    final sk = skin;
    if (sk != null && m.dist(sk, lw: 0.6) < 15) return null;
    final hc = hairColor;
    if (hc != null && m.dist(hc, lw: 0.6) < 8) return null;
    return m;
  }();
}

/// Fotoğraftaki ten rengini çizime uygun tona getirir: ışık farkını yumuşatır,
/// doygunluğu ve aydınlığı makul aralığa çeker, paletle hafifçe harmanlar.
Color stylizeSkin(LabColor measured) {
  final l = (measured.l * 0.82 + 15).clamp(30.0, 90.0);
  final chroma = measured.chroma.clamp(8.0, 36.0) * 0.92;
  final hue = math.atan2(measured.b, measured.a).clamp(0.55, 1.15); // turuncu-sarı ten açısı
  final lab = LabColor(l, chroma * math.cos(hue), chroma * math.sin(hue));
  final pal = LabColor.fromColor(kSkinTones[nearestIndex(lab, kSkinTones)]);
  return LabColor(_mixD(lab.l, pal.l, 0.25), _mixD(lab.a, pal.a, 0.25), _mixD(lab.b, pal.b, 0.25)).toColor();
}

double _mixD(double a, double b, double t) => a + (b - a) * t;

/// Ölçülen saç rengine en yakın DOĞAL saç rengi (fotoğrafta saç biraz daha
/// koyu göründüğü için aydınlık hafifçe artırılır).
Color stylizeHair(LabColor measured) {
  final lifted = measured.withL(measured.l + 3);
  final natural = kHairColors.take(kNaturalHairColorCount).toList();
  return natural[nearestIndex(lifted, natural, lw: 0.8)];
}
