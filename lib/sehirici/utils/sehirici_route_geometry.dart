import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Harita üzerinde rota geometrisi ile ilgili pure yardımcılar.
/// Nokta sadeleştirme, mesafe, süre tahmini.
///
/// Tüm fonksiyonlar `dart:math` veya `google_maps_flutter`'a bağlıdır
/// (Supabase'e değil) → unit test edilebilir, Supabase init gerekmez.

/// Verilen iki LatLng arasındaki mesafeyi metre cinsinden döner (haversine).
double distanceMeters(LatLng a, LatLng b) => _distanceMeters(a, b);

double _distanceMeters(LatLng a, LatLng b) {
  const double earthRadius = 6371000.0;
  final double dLat = (b.latitude - a.latitude) * math.pi / 180;
  final double dLng = (b.longitude - a.longitude) * math.pi / 180;
  final double lat1 = a.latitude * math.pi / 180;
  final double lat2 = b.latitude * math.pi / 180;
  final double h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) *
          math.cos(lat2) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

/// Bir noktanın polyline'a (ardışık doğru parçaları) en yakın mesafesi (metre).
/// Boş/tek noktalı path için o noktaya olan mesafeyi döner. İçerideki
/// `_perpendicularDistanceMeters`'ı (segment mesafesi) kullanır.
double nearestDistanceToPolylineMeters(LatLng p, List<LatLng> path) {
  if (path.isEmpty) return double.infinity;
  if (path.length == 1) return _distanceMeters(p, path.first);
  double min = double.infinity;
  for (int i = 1; i < path.length; i++) {
    final d = _perpendicularDistanceMeters(p, path[i - 1], path[i]);
    if (d < min) min = d;
  }
  return min;
}

/// Polyline'ın toplam uzunluğu (metre). 0/1 nokta için 0.
double pathLengthMeters(List<LatLng> path) {
  if (path.length < 2) return 0;
  double total = 0;
  for (int i = 1; i < path.length; i++) {
    total += _distanceMeters(path[i - 1], path[i]);
  }
  return total;
}

/// Ortalama hızla seyahat süresi (dakika). Mesafe ≤ 0 ise 0.
int estimateDurationMinutes(double meters, {double averageSpeedKmh = 30}) {
  if (meters <= 0) return 0;
  final double km = meters / 1000;
  final double hours = km / averageSpeedKmh;
  return (hours * 60).round();
}

/// Bir [LatLng]'in, [a]-[b] doğru parçasına **dik mesafesini** (metre) hesaplar.
/// Doğru parçasına dik nokta, parçanın uzantısı dışında kalıyorsa parçanın en
/// yakın ucuna olan mesafeyi döner (doğru-segment mesafesi).
double _perpendicularDistanceMeters(LatLng p, LatLng a, LatLng b) {
  // Eğer a == b ise doğru parçası bir noktadır; mesafe = |p - a|
  if (a.latitude == b.latitude && a.longitude == b.longitude) {
    return _distanceMeters(p, a);
  }
  // Yerel düz koordinat sistemine çevirmek için basitleştirilmiş yaklaşık:
  // çok küçük mesafelerde (şehir içi rota noktaları, < 10 km) enlem/boylam
  // farklarını metreye dönüştürürken sabit cos(lat) kullanmak yeterli.
  final double meanLatRad =
      ((a.latitude + b.latitude) / 2) * math.pi / 180;
  final double cosLat = math.cos(meanLatRad);
  // a, b, p'yi metre koordinatına çevir (yaklaşık equirectangular)
  final double ax = 0.0;
  final double ay = 0.0;
  final double bx = (b.longitude - a.longitude) * 111320 * cosLat;
  final double by = (b.latitude - a.latitude) * 110540;
  final double px = (p.longitude - a.longitude) * 111320 * cosLat;
  final double py = (p.latitude - a.latitude) * 110540;
  // px, py noktasının ax,ay - bx,by doğrusuna uzaklığı
  final double dx = bx - ax;
  final double dy = by - ay;
  final double lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) {
    return math.sqrt(px * px + py * py);
  }
  // En yakın noktanın t parametresi
  double t = ((px - ax) * dx + (py - ay) * dy) / lengthSq;
  t = t.clamp(0.0, 1.0);
  final double cx = ax + t * dx;
  final double cy = ay + t * dy;
  final double ex = px - cx;
  final double ey = py - cy;
  return math.sqrt(ex * ex + ey * ey);
}

/// Douglas-Peucker polyline sadeleştirme. [toleranceMeters]'tan daha kısa
/// sapma gösteren ara noktalar atılır; uç noktalar her zaman korunur.
///
/// Karmaşıklık: O(n log n) ortalama (divide-and-conquer rekürsif).
///
/// 0 veya 1 nokta için girdi aynen döner. [toleranceMeters] ≤ 0 ise
/// hiç sadeleştirme yapılmaz (identity).
List<LatLng> simplifyPath(
  List<LatLng> path, {
  double toleranceMeters = 8,
}) {
  if (path.length < 3 || toleranceMeters <= 0) return List.of(path);

  final List<bool> keep = List<bool>.filled(path.length, false);
  keep[0] = true;
  keep[path.length - 1] = true;

  void recurse(int first, int last) {
    if (last <= first + 1) return;
    double maxDist = 0;
    int maxIdx = first;
    final LatLng a = path[first];
    final LatLng b = path[last];
    for (int i = first + 1; i < last; i++) {
      final double d = _perpendicularDistanceMeters(path[i], a, b);
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }
    if (maxDist > toleranceMeters) {
      keep[maxIdx] = true;
      recurse(first, maxIdx);
      recurse(maxIdx, last);
    }
  }

  recurse(0, path.length - 1);

  final result = <LatLng>[];
  for (int i = 0; i < path.length; i++) {
    if (keep[i]) result.add(path[i]);
  }
  return result;
}

/// Ham GPS izini yol eşlemeye (map matching) verilmeden önce temizler.
///
/// Şoför izleri iki tür kirlilik taşır ve ikisi de OSRM `match` servisini
/// yoldan çıkarıp "her tarafa çizgi" üreten rotalara yol açar:
///
///  1. **Duruş bulutu** — araç durakta/kırmızı ışıkta beklerken 10 sn'de bir
///     nokta yazılır; GPS gezinmesi (drift) yüzünden 15-20 m'lik alanda
///     onlarca nokta birikir. Map matching bu bulutu "ileri geri manevra"
///     sanıp çevredeki sokaklara sapar.
///  2. **Işınlanma** — tünel/bina çıkışında tek bir hatalı fix izi kilometrelerce
///     öteye fırlatır; eşleme aradaki tüm yolları doldurmaya çalışır.
///
/// [minSpacingMeters] altındaki noktalar (ilk hariç) atılır; ardışık iki nokta
/// arası [maxJumpMeters]'ı aşarsa aykırı nokta atlanır ve iz son sağlam
/// noktadan devam eder. Son nokta, aralık kuralına takılsa bile korunur —
/// izin bittiği yer rota için anlamlıdır.
List<LatLng> sanitizeGpsTrace(
  List<LatLng> trace, {
  double minSpacingMeters = 12,
  double maxJumpMeters = 3000,
}) {
  final out = <LatLng>[];
  for (final p in trace) {
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude < -90 ||
        p.latitude > 90 ||
        p.longitude < -180 ||
        p.longitude > 180) {
      continue;
    }
    if (out.isEmpty) {
      out.add(p);
      continue;
    }
    final d = _distanceMeters(out.last, p);
    if (d > maxJumpMeters) continue; // aykırı fix — atla
    if (d < minSpacingMeters) continue; // duruş bulutu — atla
    out.add(p);
  }
  // İzin son noktası aralık kuralına takıldıysa geri ekle (tek nokta hariç).
  if (out.length >= 2 && trace.isNotEmpty) {
    final last = trace.last;
    if (last.latitude.isFinite &&
        last.longitude.isFinite &&
        _distanceMeters(out.last, last) <= maxJumpMeters &&
        out.last != last) {
      out.add(last);
    }
  }
  return out;
}

/// Bir polyline'ı, şeklini bozmadan en fazla [maxPoints] noktaya indirir.
///
/// [simplifyPath] tek bir toleransla çalışır; yol geometrisi çok uzun olduğunda
/// (çok turlu bir vardiya izi) sabit tolerans binlerce noktayı geçirir ve bu
/// noktalar JSONB'ye yazılıp her harita çiziminde işlenir. Burada tolerans,
/// hedef nokta sayısına ulaşana kadar kademeli olarak artırılır.
///
/// [maxPoints] < 2 ise veya girdi zaten yeterince kısaysa girdi aynen döner.
List<LatLng> simplifyToMaxPoints(
  List<LatLng> path, {
  required int maxPoints,
  double startToleranceMeters = 2,
  double maxToleranceMeters = 40,
}) {
  if (maxPoints < 2 || path.length <= maxPoints) return List.of(path);
  var tolerance = startToleranceMeters <= 0 ? 1.0 : startToleranceMeters;
  var result = simplifyPath(path, toleranceMeters: tolerance);
  while (result.length > maxPoints && tolerance < maxToleranceMeters) {
    tolerance *= 1.8;
    result = simplifyPath(path, toleranceMeters: tolerance);
  }
  return result;
}

/// Bir önceki ve sonraki nokta arasındaki bearing (pusula yönü) hesaplar.
/// Sonuç 0-360 derece (0 = kuzey, 90 = doğu, 180 = güney, 270 = batı).
/// Aynı nokta ise null döner.
double? bearingDegrees(LatLng from, LatLng to) {
  if (from.latitude == to.latitude && from.longitude == to.longitude) {
    return null;
  }
  final double lat1 = from.latitude * math.pi / 180;
  final double lat2 = to.latitude * math.pi / 180;
  final double dLng = (to.longitude - from.longitude) * math.pi / 180;
  final double y = math.sin(dLng) * math.cos(lat2);
  final double x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  double brng = math.atan2(y, x) * 180 / math.pi;
  brng = (brng + 360) % 360;
  return brng;
}

/// Bearing'i 8 yön kısaltmasına çevirir (T, KD, D, GD, G, GB, B, KB).
String bearingToCardinal(double degrees) {
  final dirs = ['K', 'KD', 'D', 'GD', 'G', 'GB', 'B', 'KB'];
  final idx = (((degrees + 22.5) % 360) / 45).floor() % 8;
  return dirs[idx];
}
