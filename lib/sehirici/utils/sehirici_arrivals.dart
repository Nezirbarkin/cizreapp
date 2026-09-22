import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../models/sehirici_models.dart';
import 'sehirici_route_geometry.dart';

/// Bir aracın belirli bir durağa tahmini varışı.
class SehiriciStopArrival {
  final SehiriciLine line;
  final SehiriciActiveTrip trip;

  /// Tahmini varış (dakika). null: hesaplanamadı (konum/sıradaki durak yok).
  final int? minutes;

  /// Araç bu durağı bu turda geçti (sıradaki durak, bu durağın ilerisinde).
  final bool passed;

  const SehiriciStopArrival({
    required this.line,
    required this.trip,
    required this.minutes,
    required this.passed,
  });

  /// Aracın molada olması: varış tahmini anlamsız.
  bool get onBreak => trip.status == SehiriciTripStatus.paused;
}

/// [trip] aracının [stopId] durağına varışını hesaplar.
///
/// Sunucudaki `get_sehirici_trips_for_stop` her seferin KENDİ sıradaki
/// durağına kalan süresini (eta_minutes) döndürür — sorulan duraktan bağımsız.
/// Yani 10. durakta bekleyen biri, araç 2. durağa 3 dk kala "3 dk" görürdü.
/// Burada hattın durak sırası ve durak başına birikimli süreler ([SehiriciLineStop.minutesFromStart])
/// kullanılarak gerçek duraktaki varış hesaplanır:
///
///   varış = sıradaki durağa kalan + (hedef durağın süresi − sıradaki durağın süresi)
///
/// Sıradaki durak hedefin ilerisindeyse araç durağı geçmiştir. Sıradaki durak
/// bilinmiyorsa kuş uçuşu mesafe ve şehir içi ortalama hızla tahmin edilir.
SehiriciStopArrival computeStopArrival({
  required SehiriciLine line,
  required SehiriciActiveTrip trip,
  required String stopId,
  double fallbackSpeedKmh = 25,
}) {
  final stops = line.stops;
  final target = stops.indexWhere((s) => s.stopId == stopId);
  final next =
      trip.nextStopId == null ? -1 : stops.indexWhere((s) => s.stopId == trip.nextStopId);

  if (target >= 0 && next >= 0) {
    if (target < next) {
      return SehiriciStopArrival(
        line: line,
        trip: trip,
        minutes: null,
        passed: true,
      );
    }
    final between =
        math.max(0, stops[target].minutesFromStart - stops[next].minutesFromStart);
    return SehiriciStopArrival(
      line: line,
      trip: trip,
      minutes: math.max(0, (trip.etaMinutes ?? 0) + between),
      passed: false,
    );
  }

  // Yedek: kuş uçuşu mesafe.
  if (target >= 0 && trip.currentLat != null && trip.currentLng != null) {
    final meters = distanceMeters(
      LatLng(trip.currentLat!, trip.currentLng!),
      LatLng(stops[target].lat, stops[target].lng),
    );
    final minutes = (meters / 1000 / fallbackSpeedKmh * 60).ceil();
    return SehiriciStopArrival(
      line: line,
      trip: trip,
      minutes: minutes,
      passed: false,
    );
  }

  return SehiriciStopArrival(
    line: line,
    trip: trip,
    minutes: null,
    passed: false,
  );
}

/// [stopId] durağından geçen hatlardaki tüm aktif seferlerin varışları;
/// en yakın önce, durağı geçenler ve hesaplanamayanlar sonda.
List<SehiriciStopArrival> arrivalsForStop({
  required String stopId,
  required List<SehiriciLine> lines,
  required List<SehiriciActiveTrip> trips,
}) {
  final byLine = {for (final l in lines) l.id: l};
  final out = <SehiriciStopArrival>[];
  for (final trip in trips) {
    final line = byLine[trip.lineId];
    if (line == null) continue;
    if (!line.stops.any((s) => s.stopId == stopId)) continue;
    out.add(computeStopArrival(line: line, trip: trip, stopId: stopId));
  }
  int rank(SehiriciStopArrival a) {
    if (a.passed) return 2;
    if (a.minutes == null || a.onBreak) return 1;
    return 0;
  }

  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return (a.minutes ?? 1 << 30).compareTo(b.minutes ?? 1 << 30);
  });
  return out;
}

/// "az önce", "3 dk", "1 sa 5 dk" — varış süresini insan diliyle yazar.
String formatArrivalMinutes(int minutes) {
  if (minutes <= 0) return 'Şimdi';
  if (minutes < 60) return '$minutes dk';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h sa' : '$h sa $m dk';
}
